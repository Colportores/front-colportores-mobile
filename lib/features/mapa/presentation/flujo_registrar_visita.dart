import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../agenda/domain/entities/visita.dart';
import '../../agenda/domain/entities/visita_guardada.dart';
import '../../agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import '../../agenda/presentation/flujo_entrevista_dada.dart';
import '../../agenda/presentation/providers/agenda_providers.dart';
import '../../agenda/presentation/widgets/flujo_entrevista.dart';
import '../../agenda/presentation/widgets/textos_entrevista.dart';
import '../../jornada/domain/jornada_sin_cerrar.dart';
import '../../jornada/domain/usecases/finalizar_jornada_use_case.dart';
import '../../jornada/domain/usecases/obtener_jornada_activa_use_case.dart';
import '../../jornada/presentation/providers/jornada_providers.dart';
import '../domain/entities/eleccion_de_cita.dart';
import '../domain/entities/eleccion_de_venta.dart';
import '../domain/entities/ubicacion.dart' show TipoUbicacion;
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
/// - **Cobranza** sigue al cobro (C·08 → vista 28). Si no se cobra y la colportora toca «Cancelar»,
///   el flujo del cobro le pregunta «¿María no te pagó?»; con «Sí, anotar la visita» queda la visita
///   «Cobranza» sin cobro ([anotarCobranzaSinCobro]) y la cita sigue `PROGRAMADA`.
/// - **Programar entrevista**, **Entrevista dada** y **Cobranza** siguen a «¿Con quién?» y a los
///   flujos de sus propias HU: aparecen cuando esos destinos están enganchados
///   ([programarEntrevistaDesdeLaCasaProvider], [entrevistaDadaDesdeLaCasaProvider],
///   [cobrarDesdeLaCasaProvider]); sin destino no se dibujan.
/// - **Vender** (decisión de Cristian, 04/11, «Vender desde el mapa»): solo si en la casa ya hubo una
///   entrevista dada; abre la venta con la casa y la persona de la última entrevista ya puestas
///   ([venderDesdeLaCasaProvider]). Sin entrevista previa, o sin destino, no se dibuja.
///
/// Las visitas que guarda este flujo («No contestó», «Rechazo» y «Cobranza») llevan el `jornada_id` de
/// la jornada abierta de la colportora, si tiene una (#475) y es la de hoy; si no, van sin jornada
/// (también cuando la abierta quedó de otro día: #524). La «Entrevista
/// dada» la guarda su propio flujo (#450), que es quien completa el suyo.
///
/// Los ids de la visita se generan una vez por opción y se repiten en los reintentos: un doble toque o
/// un reintento tras una falla no guarda la visita dos veces.
abstract final class FlujoRegistrarVisita {
  /// Abre «¿Qué pasó?» para [datos]. Devuelve `true` si algo se resolvió y la hoja de la casa puede
  /// cerrarse (también cuando «Entrevista dada» o «Vender» terminaron en una venta guardada: tras
  /// guardar vuelve al mapa libre, decisión de Cristian del 05/11); `false` si la colportora cerró
  /// «¿Qué pasó?» sin elegir, o no hay dónde registrar.
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
    // En un edificio o un negocio todo es por depto: «¿Qué pasó en el 2A?» y «Grecia 3307 · Piso 2»
    // (vista 39, N·07).
    final enDepto =
        lugar.ubicacion.tipo == TipoUbicacion.edificio ||
        (lugar.espacio.numeroDepto?.trim().isNotEmpty ?? false);
    final piso = lugar.espacio.piso?.trim() ?? '';

    final programar = contenedor.read(programarEntrevistaDesdeLaCasaProvider);
    final entrevistaDada = contenedor.read(entrevistaDadaDesdeLaCasaProvider);
    final cobrar = contenedor.read(cobrarDesdeLaCasaProvider);
    final cobro = cobrar == null ? null : await _quienDebe(contenedor, espacioId);
    final vender = contenedor.read(venderDesdeLaCasaProvider);
    final venta = vender == null ? null : await _quienVende(contenedor, espacioId);

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

    // «Entrevista dada» o «Vender» terminaron en una venta: «¿Qué pasó?» se resolvió.
    SalidaDeOpcion? salidaConVenta(Object? hecho) =>
        hecho is VentaRegistradaEnLaCasa ? const OpcionResuelta() : null;

    // La agenda que la visita viene a cerrar, de mejor esfuerzo: la tocada en la fila de la agenda
    // (23B) o la programada de la casa. Sin la lectura, la visita se guarda igual, como espontánea.
    Future<String?> agendaDeLaVisita() async {
      final tocada = datos.agendaId;
      if (tocada != null) return tocada;
      try {
        return (await agendas.agendaProgramadaDe(espacioId)).fold((_) => null, (a) => a?.id);
      } on Object {
        return null;
      }
    }

    Future<SalidaDeOpcion> guardarDeUnToque(OpcionQuePaso opcion) async {
      final colportor = colportorId;
      if (colportor == null || colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      final resultado = opcion == OpcionQuePaso.noContesto
          ? TipoResultadoVisita.noContesto
          : TipoResultadoVisita.rechazo;
      // Desde una fila de la agenda (23B) viene la agenda tocada: es esa, no «la más antigua» de la
      // casa. Si ya no se puede cumplir (se canceló, se cerró) el repositorio guarda la visita como
      // espontánea y no toca la agenda. Desde la hoja de la casa se lee la programada del espacio, de
      // mejor esfuerzo: sin la lectura la visita se guarda igual, como espontánea.
      final agendaId = await agendaDeLaVisita();
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

    // «Ya tenés una entrevista en curso en …» lleva «Ir a la entrevista»: abre esa entrevista (R·05) con
    // la misma navegación del aviso fijo del mapa. Al volver con atrás, si sigue en curso, el aviso vuelve
    // con su botón; si la terminó, eso es guardar y se cierra todo (ver abajo).
    OpcionFallida fallaConOtraEntrevista(String aviso, String colportor) => OpcionFallida(
      aviso,
      accion: (
        etiqueta: TextosEntrevista.irALaEntrevista,
        alTocar: () async {
          if (!context.mounted) return const OpcionCancelada();
          await FlujoEntrevista.abrirEn(context, contenedor, colportorId: colportor);
          final sigue = await FlujoEntrevistaDada.avisoSiHayOtraEnCurso(
            contenedor,
            colportorId: colportor,
            espacioId: espacioId,
          );
          // Si la terminó (con venta o sin venta) eso es guardar: se cierra «¿Qué pasó?» y la hoja de la
          // casa, y queda el mapa libre (decisión de Cristian, «Tras guardar», 05/11). Para dar la
          // entrevista de esta casa, se vuelve a tocar. Si volvió con atrás sin terminarla, sigue el
          // aviso con su botón.
          return sigue == null ? const OpcionResuelta() : fallaConOtraEntrevista(sigue, colportor);
        },
      ),
    );

    Future<SalidaDeOpcion> darLaEntrevista() async {
      final colportor = colportorId;
      if (entrevistaDada == null || colportor == null || colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      // Con otra entrevista en curso en otra casa no se empieza una segunda: se dice antes de
      // preguntar «¿Con quién?».
      final aviso = await FlujoEntrevistaDada.avisoSiHayOtraEnCurso(
        contenedor,
        colportorId: colportor,
        espacioId: espacioId,
      );
      if (aviso != null) return fallaConOtraEntrevista(aviso, colportor);
      if (!context.mounted) return const OpcionCancelada();
      final eleccion = await mostrarHojaConQuien(
        context,
        espacioId: espacioId,
        colportorId: colportor,
      );
      if (eleccion == null) return const OpcionCancelada();
      final hecho = await entrevistaDada((
        ubicacionId: datos.ubicacionId,
        espacioId: espacioId,
        // «Todavía no sé con quién»: la entrevista sigue sin persona.
        persona: eleccion.persona,
        agendaId: await agendaDeLaVisita(),
        jornadaId: await _jornadaAbierta(contenedor, colportor),
      ));
      return salidaConVenta(hecho) ??
          (hecho == true ? const OpcionResuelta() : const OpcionCancelada());
    }

    Future<SalidaDeOpcion> venderUna() async {
      final colportor = colportorId;
      if (vender == null ||
          venta == null ||
          venta.isEmpty ||
          colportor == null ||
          colportor.trim().isEmpty) {
        return const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
      }
      // Una sola persona entrevistada: la venta es de ella, sin preguntar. Con más de una se pregunta a
      // quién (regla R6: quien tiene que dar un dato lo da, no se le elige); atrás vuelve a «¿Qué
      // pasó?» sin guardar nada.
      var espacioPersonaId = venta.first.espacioPersonaId;
      if (venta.length > 1) {
        if (!context.mounted) return const OpcionCancelada();
        final elegida = await mostrarHojaConQuienVende(
          context,
          espacioId: espacioId,
          colportorId: colportor,
          entrevistadas: [for (final q in venta) q.espacioPersonaId],
        );
        switch (elegida) {
          case null:
            return const OpcionCancelada();
          // Se dieron de baja mientras tanto: se dice por qué y «¿Qué pasó?» sigue abierta.
          case NadieParaVender():
            return const OpcionFallida(TextosRegistrarVisita.nadieParaVender);
          case VenderA(:final persona):
            espacioPersonaId = persona.espacioPersonaId;
        }
      }
      final hecho = await vender((
        ubicacionId: datos.ubicacionId,
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        // La visita «Venta» de hoy cuelga de la agenda que cumple y de la jornada abierta, como la
        // entrevista: se leen al vender, no al abrir la hoja.
        agendaId: await agendaDeLaVisita(),
        jornadaId: await _jornadaAbierta(contenedor, colportor),
      ));
      return salidaConVenta(hecho) ?? const OpcionCancelada();
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
        // «Cancelar» y «Sí, anotar la visita» (03/11): el flujo del cobro ya guardó la visita «Cobranza»
        // sin cobro, con `anotarCobranzaSinCobro`; acá no se guarda otra vez.
        if (hecho is CobranzaAnotadaSinCobro) return const OpcionResuelta();
        if (hecho != true) return const OpcionCancelada();
        cobroHecho = true;
      }
      // El cobro se hizo: la visita queda en el historial como «Cobranza» (decisión «Visita cobro»,
      // 23/10), sin agenda. Si no se puede guardar, el cobro ya está hecho y la hoja lo dice.
      final r = await _guardarVisitaDeCobranza(
        contenedor,
        registrar,
        ids: idsDe(OpcionQuePaso.cobranza),
        espacioId: espacioId,
        espacioPersonaId: cobro.espacioPersonaId,
        colportorId: colportor,
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
      if (venta != null && venta.isNotEmpty) OpcionQuePaso.vender,
    };

    final resuelta = await mostrarHojaQuePaso(
      context,
      titulo: enDepto
          ? TextosRegistrarVisita.tituloDelDepto(lugar.espacio.numeroDepto)
          : TextosRegistrarVisita.titulo,
      direccion: enDepto && piso.isNotEmpty ? '$direccion · Piso $piso' : direccion,
      ofrecidas: ofrecidas,
      cobro: cobro == null ? null : (persona: cobro.nombre, saldoCentavos: cobro.saldoCentavos),
      venta: venta == null || venta.isEmpty
          ? null
          : (persona: venta.length == 1 ? venta.single.nombre : null),
      alElegir: (opcion) => switch (opcion) {
        OpcionQuePaso.noContesto || OpcionQuePaso.rechazo => guardarDeUnToque(opcion),
        OpcionQuePaso.programarEntrevista => programarUna(),
        OpcionQuePaso.entrevistaDada => darLaEntrevista(),
        OpcionQuePaso.cobranza => cobrarUna(),
        OpcionQuePaso.vender => venderUna(),
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

  /// Guarda la visita «Cobranza» **sin cobro** (decisión de Cristian, 03/11, «Sin cobro»): la colportora
  /// tocó «Cancelar» en «$ Cobrar», contestó «Sí, anotar la visita» a «¿María no te pagó?» y queda la
  /// pasada en el historial. Va **sin agenda**, como la «Cobranza» con cobro: la cita de cobranza no se
  /// toca y sigue `PROGRAMADA` (regla común de la vista 39, S37).
  ///
  /// Es lo que usa el flujo del cobro (`FlujoCobrarDesdeLaCasa`), así que cubre los dos caminos —«$ Cobrar»
  /// de la hoja de la casa y «Cobranza» de «¿Qué pasó?»— con un solo lugar que escribe la visita. [ids]
  /// se genera una vez por pregunta y se repite en el reintento: una falla seguida de otro «Sí» no
  /// guarda dos visitas. Devuelve `true` si quedó guardada; nunca lanza.
  static Future<bool> anotarCobranzaSinCobro(
    ProviderContainer contenedor, {
    required IdsResultadoVisita ids,
    required String espacioId,
    String? espacioPersonaId,
    required String colportorId,
  }) async {
    try {
      final r = await _guardarVisitaDeCobranza(
        contenedor,
        contenedor.read(registrarResultadoVisitaUseCaseProvider),
        ids: ids,
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        colportorId: colportorId,
      );
      return r.isRight();
    } on Object {
      return false;
    }
  }

  /// La visita «Cobranza» (con o sin cobro) sin agenda y con la jornada abierta de hoy, si la hay.
  static Future<Either<Failure, ResultadoVisitaRegistrado>> _guardarVisitaDeCobranza(
    ProviderContainer contenedor,
    RegistrarResultadoVisitaUseCase registrar, {
    required IdsResultadoVisita ids,
    required String espacioId,
    required String? espacioPersonaId,
    required String colportorId,
  }) async => registrar(
    RegistrarResultadoVisitaParams(
      ids: ids,
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      colportorId: colportorId,
      resultado: TipoResultadoVisita.cobranza,
      jornadaId: await _jornadaAbierta(contenedor, colportorId),
    ),
  );

  /// La jornada abierta de [colportorId] **en el momento de guardar** (no al abrir la hoja: la
  /// colportora pudo iniciarla o cerrarla mientras tanto), o `null` si no tiene ninguna.
  ///
  /// Si la abierta quedó de otro día —con el mismo criterio de «quedó abierta» de #250/#326: ni la
  /// hora más temprana del margen normal de ahora (ahora − 30 min) cae en el día de su inicio—, no
  /// es la jornada de hoy: colgarle la visita la pondría fuera del rango que la colportora corrija
  /// después. La visita va sin jornada, igual que cuando no hay ninguna; al cerrarla y empezar la de
  /// hoy, las siguientes llevan la nueva (#524).
  ///
  /// Mejor esfuerzo, como la agenda: si la lectura falla la visita se guarda igual, sin jornada (el
  /// campo es opcional en el servidor); nunca se inventa una ni se frena el guardado.
  static Future<String?> _jornadaAbierta(ProviderContainer contenedor, String colportorId) async {
    try {
      final r = await contenedor.read(obtenerJornadaActivaUseCaseProvider)(
        ObtenerJornadaActivaParams(colportorId: colportorId),
      );
      final ahora = contenedor.read(relojVisitaProvider)();
      return r.fold(
        (_) => null,
        (jornada) =>
            jornada == null ||
                JornadaSinCerrar.quedoAbierta(
                  inicio: jornada.inicio,
                  ahora: ahora,
                  margen: FinalizarJornadaUseCase.margenHaciaAtras,
                )
            ? null
            : jornada.id,
      );
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

  /// A quién se le puede vender desde «Vender»: las personas de la casa con una entrevista dada
  /// (`visita` de resultado `ENTREVISTA`, que no estén dadas de baja), la de la entrevista más reciente
  /// primero; `null` si en la casa nunca hubo una (la opción no se ofrece) o no se pudo leer (no se
  /// afirma lo que no se sabe). Con una sola, la venta es de ella; con más, se pregunta a quién.
  static Future<List<_QuienVende>?> _quienVende(
    ProviderContainer contenedor,
    String espacioId,
  ) async {
    try {
      final personas = await contenedor
          .read(personaRepositoryProvider)
          .observarDelEspacio(espacioId)
          .first;
      if (personas.isEmpty) return null;
      final entrevistas = await contenedor
          .read(lectorEntrevistasDePersonasProvider)
          .ultimaEntrevistaDe(personas.map((p) => p.vinculo.id));
      final entrevistadas = <({DateTime fecha, _QuienVende quien})>[];
      for (final p in personas) {
        final fecha = entrevistas[p.vinculo.id];
        if (fecha == null) continue;
        entrevistadas.add((
          fecha: fecha,
          quien: _QuienVende(
            espacioPersonaId: p.vinculo.id,
            nombre: FormatoPersonas.nombreCompleto(p.persona),
          ),
        ));
      }
      if (entrevistadas.isEmpty) return null;
      // `sort` de Dart no es estable: a igual fecha queda primero la que ya venía primero (el orden de
      // la casa), que es lo que elegía el «Vender» de una sola persona.
      final orden = entrevistadas.asMap().map((i, e) => MapEntry(e.quien.espacioPersonaId, i));
      entrevistadas.sort((a, b) {
        final porFecha = b.fecha.compareTo(a.fecha);
        return porFecha != 0
            ? porFecha
            : orden[a.quien.espacioPersonaId]!.compareTo(orden[b.quien.espacioPersonaId]!);
      });
      return [for (final e in entrevistadas) e.quien];
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

/// A quién se le vende desde «Vender».
class _QuienVende {
  const _QuienVende({required this.espacioPersonaId, required this.nombre});

  final String espacioPersonaId;
  final String nombre;
}
