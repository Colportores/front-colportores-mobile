import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../agenda/domain/entities/visita.dart';
import '../../agenda/domain/entities/visita_guardada.dart';
import '../../agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import '../../agenda/presentation/providers/agenda_providers.dart';
import '../../jornada/domain/usecases/obtener_jornada_activa_use_case.dart';
import '../../jornada/presentation/providers/jornada_providers.dart';
import '../domain/entities/eleccion_de_cita.dart';
import '../domain/entities/persona_de_la_entrevista.dart';
import 'formato_ubicaciones.dart';
import 'providers/hoja_casa_providers.dart';
import 'providers/personas_providers.dart';
import 'textos_personas.dart';
import 'textos_registrar_visita.dart';
import 'widgets/aviso_con_deshacer.dart';
import 'widgets/hoja_con_quien.dart';
import 'widgets/hoja_que_paso.dart';

/// «Registrar visita» de la vista 39: la hoja «¿Qué pasó?» (C·06), lo que hace cada opción y el aviso
/// «Guardado» con «Deshacer» (R·01). Es lo que enchufa `registrarVisitaDesdeLaCasaProvider`.
///
/// - **No contestó** y **Rechazo** guardan de un toque: la visita (con la agenda de la casa, si tiene
///   una programada: «No contestó» la deja `NO_CUMPLIDA`), la casa se repinta y se vuelve al mapa con
///   el aviso «Guardado. Grecia 3307 quedó como «No contestó».» y su «Deshacer».
/// - **Programar entrevista**, **Entrevista dada** y **Cobranza** siguen a «¿Con quién?» y a los
///   flujos de sus propias HU: aparecen cuando esos destinos están enganchados
///   ([programarEntrevistaDesdeLaCasaProvider], [entrevistaDadaDesdeLaCasaProvider],
///   [cobrarDesdeLaCasaProvider]); sin destino no se dibujan.
///
/// Las visitas que guarda este flujo («No contestó», «Rechazo» y «Cobranza») llevan el `jornada_id` de
/// la jornada abierta de la colportora, si tiene una (#475); si no, van sin jornada. La «Entrevista
/// dada» la guarda su propio flujo (#450), que es quien completa el suyo.
///
/// Los ids de la visita se generan una vez por opción y se repiten en los reintentos: un doble toque o
/// un reintento tras una falla no guarda la visita dos veces.
abstract final class FlujoRegistrarVisita {
  /// Abre «¿Qué pasó?» para [datos]. Devuelve `true` si algo se resolvió y la hoja de la casa puede
  /// cerrarse; `false` si la colportora cerró «¿Qué pasó?» sin elegir, o no hay dónde registrar.
  /// Lanza si no puede leer la casa (la hoja de la casa lo dice).
  static Future<bool> abrir(
    BuildContext context,
    ContextoDeVisita datos, {
    required String? colportorId,
  }) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final mediaQuery = MediaQuery.of(context);
    final espacioId = datos.espacioId;
    if (espacioId == null) {
      // El depto se elige antes (C·09, #452): sin él no hay dónde guardar la visita.
      _avisar(mensajero, TextosRegistrarVisita.edificioSinDepto);
      return false;
    }
    final contenedor = ProviderScope.containerOf(context, listen: false);
    // Se lee del repositorio y no de los providers `autoDispose`: sin nadie mirando se liberan a mitad
    // de la lectura.
    final lugar = (await contenedor.read(espacioRepositoryProvider).buscar(espacioId)).fold(
      (falla) => throw falla,
      (encontrado) => encontrado,
    );
    if (lugar == null) {
      _avisar(mensajero, TextosRegistrarVisita.casaNoEstaMas);
      return false;
    }
    final direccion = FormatoUbicaciones.direccion(lugar.ubicacion);

    final programar = contenedor.read(programarEntrevistaDesdeLaCasaProvider);
    final entrevistaDada = contenedor.read(entrevistaDadaDesdeLaCasaProvider);
    final cobrar = contenedor.read(cobrarDesdeLaCasaProvider);
    final cobro = cobrar == null ? null : await _quienDebe(contenedor, espacioId);

    // Se toman acá, no al tocar «Deshacer»: la hoja y la pestaña pueden haberse ido para entonces.
    final registrar = contenedor.read(registrarResultadoVisitaUseCaseProvider);
    final deshacer = contenedor.read(deshacerResultadoVisitaUseCaseProvider);
    final agendas = contenedor.read(agendaRepositoryProvider);
    if (!context.mounted) return false;

    // Los ids de cada opción: se repiten en los reintentos de la misma y no se comparten entre opciones.
    final idsPorOpcion = <OpcionQuePaso, IdsResultadoVisita>{};
    IdsResultadoVisita idsDe(OpcionQuePaso o) => idsPorOpcion[o] ??= registrar.nuevosIds();

    VisitaGuardada? guardada;
    String? resultadoDicho;

    Future<SalidaDeOpcion> guardarDeUnToque(OpcionQuePaso opcion) async {
      final colportor = colportorId;
      if (colportor == null || colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      final resultado = opcion == OpcionQuePaso.noContesto
          ? TipoResultadoVisita.noContesto
          : TipoResultadoVisita.rechazo;
      // Mejor esfuerzo: sin la lectura la visita se guarda igual, como espontánea.
      String? agendaId;
      try {
        agendaId = (await agendas.agendaProgramadaDe(espacioId)).fold((_) => null, (a) => a?.id);
      } on Object {
        agendaId = null;
      }
      final r = await registrar(
        RegistrarResultadoVisitaParams(
          ids: idsDe(opcion),
          espacioId: espacioId,
          colportorId: colportor,
          resultado: resultado,
          agendaId: agendaId,
          jornadaId: await _jornadaAbierta(contenedor, colportor),
        ),
      );
      return r.fold(
        (falla) => OpcionFallida(
          falla is FailureValidacion && falla.campos.containsKey('espacio')
              ? TextosRegistrarVisita.casaNoEstaMas
              : TextosRegistrarVisita.noPudimosGuardar,
        ),
        (registrado) {
          guardada = registrado.guardada;
          resultadoDicho = opcion == OpcionQuePaso.noContesto
              ? TextosRegistrarVisita.resultadoNoContesto
              : TextosRegistrarVisita.resultadoRechazo;
          return const OpcionResuelta();
        },
      );
    }

    Future<SalidaDeOpcion> programarUna() async {
      final colportor = colportorId;
      if (programar == null || colportor == null || colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      if (!context.mounted) return const OpcionCancelada();
      final eleccion = await mostrarHojaConQuienParaProgramar(
        context,
        espacioId: espacioId,
        colportorId: colportor,
      );
      if (eleccion == null) return const OpcionCancelada();
      final hecho = await programar((
        ubicacionId: datos.ubicacionId,
        espacioId: espacioId,
        espacioPersonaId: eleccion.espacioPersonaId,
        personaId: switch (eleccion) {
          CitaConPersona(:final persona) => persona.personaId,
          CitaSinPersona() => null,
        },
      ));
      return hecho == true ? const OpcionResuelta() : const OpcionCancelada();
    }

    Future<SalidaDeOpcion> darLaEntrevista() async {
      final colportor = colportorId;
      if (entrevistaDada == null || colportor == null || colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      if (!context.mounted) return const OpcionCancelada();
      final PersonaDeLaEntrevista? persona = await mostrarHojaConQuien(
        context,
        espacioId: espacioId,
        colportorId: colportor,
      );
      if (persona == null) return const OpcionCancelada();
      final hecho = await entrevistaDada((
        ubicacionId: datos.ubicacionId,
        espacioId: espacioId,
        persona: persona,
      ));
      return hecho == true ? const OpcionResuelta() : const OpcionCancelada();
    }

    // El cobro ya se hizo y solo falta guardar la visita: un reintento no lo repite.
    var cobroHecho = false;

    Future<SalidaDeOpcion> cobrarUna() async {
      final colportor = colportorId;
      if (cobrar == null || cobro == null || colportor == null || colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      if (!cobroHecho) {
        final hecho = await cobrar((
          ubicacionId: datos.ubicacionId,
          espacioId: espacioId,
          personaId: cobro.personaId,
        ));
        if (hecho != true) return const OpcionCancelada();
        cobroHecho = true;
      }
      // El cobro se hizo: la visita queda en el historial como «Cobranza» (decisión «Visita cobro»,
      // 23/10), sin agenda. Si no se puede guardar, el cobro ya está hecho y la hoja lo dice.
      final r = await registrar(
        RegistrarResultadoVisitaParams(
          ids: idsDe(OpcionQuePaso.cobranza),
          espacioId: espacioId,
          espacioPersonaId: cobro.espacioPersonaId,
          colportorId: colportor,
          resultado: TipoResultadoVisita.cobranza,
          jornadaId: await _jornadaAbierta(contenedor, colportor),
        ),
      );
      return r.fold(
        (_) => const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar),
        (_) => const OpcionResuelta(),
      );
    }

    final ofrecidas = {
      OpcionQuePaso.noContesto,
      OpcionQuePaso.rechazo,
      if (programar != null) OpcionQuePaso.programarEntrevista,
      if (entrevistaDada != null) OpcionQuePaso.entrevistaDada,
      if (cobro != null) OpcionQuePaso.cobranza,
    };

    final resuelta = await mostrarHojaQuePaso(
      context,
      direccion: direccion,
      ofrecidas: ofrecidas,
      cobro: cobro == null ? null : (persona: cobro.nombre, saldoCentavos: cobro.saldoCentavos),
      alElegir: (opcion) => switch (opcion) {
        OpcionQuePaso.noContesto || OpcionQuePaso.rechazo => guardarDeUnToque(opcion),
        OpcionQuePaso.programarEntrevista => programarUna(),
        OpcionQuePaso.entrevistaDada => darLaEntrevista(),
        OpcionQuePaso.cobranza => cobrarUna(),
      },
    );

    final visitaGuardada = guardada;
    final dicho = resultadoDicho;
    if (resuelta && visitaGuardada != null && dicho != null && mensajero != null) {
      _avisarGuardado(
        mensajero,
        mediaQuery: mediaQuery,
        direccion: direccion,
        resultado: dicho,
        guardada: visitaGuardada,
        deshacer: deshacer,
      );
    }
    return resuelta;
  }

  /// La jornada abierta de [colportorId] **en el momento de guardar** (no al abrir la hoja: la
  /// colportora pudo iniciarla o cerrarla mientras tanto), o `null` si no tiene ninguna.
  ///
  /// Mejor esfuerzo, como la agenda: si la lectura falla la visita se guarda igual, sin jornada (el
  /// campo es opcional en el servidor); nunca se inventa una ni se frena el guardado.
  static Future<String?> _jornadaAbierta(ProviderContainer contenedor, String colportorId) async {
    try {
      final r = await contenedor.read(obtenerJornadaActivaUseCaseProvider)(
        ObtenerJornadaActivaParams(colportorId: colportorId),
      );
      return r.fold((_) => null, (jornada) => jornada?.id);
    } on Object {
      return null;
    }
  }

  /// Quién de la casa debe más, para la ayuda de «Cobranza»; `null` si nadie debe (la opción no se
  /// ofrece) o no se pudo leer (no se afirma lo que no se sabe).
  static Future<_QuienDebe?> _quienDebe(ProviderContainer contenedor, String espacioId) async {
    try {
      final personas = await contenedor
          .read(personaRepositoryProvider)
          .observarDelEspacio(espacioId)
          .first;
      final saldos = await contenedor
          .read(saldosDePersonasProvider)
          .saldosPendientes(personas.map((p) => p.persona.id));
      _QuienDebe? mejor;
      for (final p in personas) {
        final saldo = saldos[p.persona.id] ?? 0;
        if (saldo > 0 && (mejor == null || saldo > mejor.saldoCentavos)) {
          mejor = _QuienDebe(
            personaId: p.persona.id,
            espacioPersonaId: p.vinculo.id,
            nombre: FormatoPersonas.nombreCompleto(p.persona),
            saldoCentavos: saldo,
          );
        }
      }
      return mejor;
    } on Object {
      return null;
    }
  }

  static void _avisar(ScaffoldMessengerState? mensajero, String texto) {
    mensajero
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// R·01: «Guardado. Grecia 3307 quedó como «No contestó».» con «Deshacer», que dura 8 s.
  ///
  /// El aviso de un resultado nuevo reemplaza al anterior, y cada «Deshacer» es de su visita.
  static void _avisarGuardado(
    ScaffoldMessengerState mensajero, {
    required MediaQueryData mediaQuery,
    required String direccion,
    required String resultado,
    required VisitaGuardada guardada,
    required DeshacerResultadoVisitaUseCase deshacer,
  }) {
    var tocado = false;
    mostrarAvisoConDeshacer(
      mensajero,
      mediaQuery: mediaQuery,
      texto: TextosRegistrarVisita.guardado(direccion, resultado),
      etiquetaDeshacer: TextosRegistrarVisita.deshacer,
      duracion: TextosRegistrarVisita.duracionDeshacer,
      alDeshacer: () {
        // Un segundo toque (o uno tardío) no deshace dos veces.
        if (tocado) return;
        tocado = true;
        unawaited(_deshacer(mensajero, deshacer, guardada, direccion));
      },
    );
  }

  static Future<void> _deshacer(
    ScaffoldMessengerState mensajero,
    DeshacerResultadoVisitaUseCase deshacer,
    VisitaGuardada guardada,
    String direccion,
  ) async {
    var deshecha = false;
    try {
      final Either<Failure, Visita> r = await deshacer(DeshacerResultadoVisitaParams.de(guardada));
      deshecha = r.isRight();
    } on Object {
      // Cualquier falla se dice igual: no se pudo deshacer, la visita sigue guardada.
      deshecha = false;
    }
    // Sin `hideCurrentSnackBar`: si mientras tanto se guardó otra visita, su aviso (y su «Deshacer»)
    // no se pisa; este espera su turno.
    mensajero.showSnackBar(
      SnackBar(
        content: Text(
          deshecha
              ? TextosRegistrarVisita.seDeshizo(direccion)
              : TextosRegistrarVisita.noPudimosDeshacer,
        ),
      ),
    );
  }
}

/// Quien más debe en la casa.
class _QuienDebe {
  const _QuienDebe({
    required this.personaId,
    required this.espacioPersonaId,
    required this.nombre,
    required this.saldoCentavos,
  });

  final String personaId;
  final String espacioPersonaId;
  final String nombre;
  final int saldoCentavos;
}
