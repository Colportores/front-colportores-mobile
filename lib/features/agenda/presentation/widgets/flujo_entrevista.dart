import 'dart:async';

import 'package:dartz/dartz.dart' show Either, Unit;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../cobranzas/presentation/providers/cobranzas_providers.dart'
    show saldoPendienteRepositoryProvider;
import '../../../inicio/presentation/providers/navegacion_inicio_provider.dart';
import '../../../mapa/presentation/pages/alta_persona_page.dart';
import '../../../mapa/presentation/providers/cobranza_recien_agendada_providers.dart';
import '../../../mapa/presentation/providers/hoja_casa_providers.dart'
    show contextoDeLaCasaProvider;
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart' show FormatoPersonas, TextosPersonas;
import '../../../mapa/presentation/textos_registrar_visita.dart';
import '../../../mapa/presentation/widgets/aviso_con_deshacer.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../../ventas/domain/entities/cliente_de_la_venta.dart';
import '../../../ventas/domain/entities/entrega.dart' show EntregaRegistrada;
import '../../../ventas/domain/entities/nueva_venta.dart' show VentaGuardada;
import '../../../ventas/domain/usecases/diferir_entrega_use_case.dart' show ResultadoDiferirEntrega;
import '../../../ventas/presentation/flujo_cuando_cobrar.dart';
import '../../../ventas/presentation/formato_venta.dart' show TextosVenta;
import '../../../ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import '../../../ventas/presentation/pages/cuando_cobrar_page.dart' show TextosCuandoCobrar;
import '../../../ventas/presentation/pages/entregar_ahora_page.dart';
import '../../../ventas/presentation/pages/entregar_otro_dia_page.dart';
import '../../../ventas/presentation/pages/nueva_venta_page.dart';
import '../../../ventas/presentation/pages/venta_registrada_page.dart';
import '../../../ventas/presentation/providers/nueva_venta_notifier.dart' show ArgumentosDeVenta;
import '../../../ventas/presentation/providers/ventas_providers.dart'
    show ContextoDeCobroDeLaVenta, cobrarDespuesDeLaVentaProvider;
import '../../domain/entities/agenda.dart';
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/entities/entrevista_en_curso.dart';
import '../../domain/entities/misionero_dejado.dart';
import '../../domain/services/recordatorios.dart' show ResultadoRecordatorio;
import '../../domain/usecases/cerrar_entrevista_con_venta_use_case.dart';
import '../../domain/usecases/finalizar_entrevista_use_case.dart';
import '../../domain/usecases/registrar_resultado_visita_use_case.dart';
import '../pages/modificar_agenda_page.dart';
import '../providers/agenda_providers.dart';
import '../providers/entrevista_providers.dart';
import '../providers/rotulo_entrevista_providers.dart';
import 'hoja_entrevista_en_curso.dart';
import 'hoja_termino_entrevista.dart';
import 'textos_entrevista.dart';

/// El recorrido de una entrevista en curso, de la hoja R·05 a «Terminó la entrevista» (R·06 / R·07).
/// Lo abren el aviso fijo del mapa, la hoja de la casa (#444) y el cierre de la jornada.
abstract final class FlujoEntrevista {
  /// R·05: abre «Entrevista en curso» de [colportorId] y, si toca «Finalizar entrevista», sigue a
  /// [terminar]. Sin entrevista en curso no hace nada.
  static Future<SalidaTerminoEntrevista?> abrir(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
  }) =>
      abrirEn(context, ProviderScope.containerOf(context, listen: false), colportorId: colportorId);

  /// Lo mismo que [abrir] para quien no es un widget (el gancho de «Entrevista dada» de la hoja de la
  /// casa, que se abre sobre el navegador de la app): lee del [ref] que le pasan, el contenedor.
  static Future<SalidaTerminoEntrevista?> abrirEn(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final estado = await notificador.esperarLectura();
    final entrevista = estado.entrevista;
    if (entrevista == null || !context.mounted) return null;
    final rotulo = await _rotulo(ref, entrevista);
    if (!context.mounted) return null;

    final finalizar = await mostrarHojaEntrevistaEnCurso(
      context,
      direccion: rotulo.direccion,
      persona: rotulo.persona,
      inicio: entrevista.inicio,
      notaInicial: estado.notaBorrador,
      alEscribirNota: notificador.escribirNota,
      reloj: ref.read(relojEntrevistaProvider),
    );
    if (finalizar != true || !context.mounted) return null;
    return terminarEn(context, ref, colportorId: colportorId, pedirSalida: estado.recuperada);
  }

  /// R·06: «Terminó la entrevista» de la que [colportorId] tiene en curso.
  ///
  /// La salida es «ahora» salvo que [pedirSalida]: si la app se cerró con la entrevista abierta o se
  /// termina la jornada con ella abierta, la hora de salida **no se inventa**, se le pide
  /// (decisión de Cristian, 23/10, #450). Devuelve cómo se cerró la hoja, o `null` si no había
  /// entrevista o se cerró sin elegir (la entrevista sigue en curso).
  ///
  /// «Sí, registrar la venta» sigue por la venta (vista 27) con la casa, la persona y la visita ya
  /// puestas ([_registrarLaVenta], #428): devuelve [VentaGuardadaEnLaEntrevista] si se guardó, o
  /// [VentaSinCompletar] si no (por R44 no se guarda el resultado y la entrevista sigue en curso).
  /// [desdeLaJornada] es `true` cuando se llega desde «Finalizar jornada»: el aviso de la venta que no
  /// se completó dice que hay que terminar la entrevista para cerrar la jornada, y la casa no se
  /// vuelve a elegir en el mapa. Con [conVenta] en `false` la hoja devuelve [QuiereRegistrarLaVenta] sin
  /// seguir (la cuenta restringida, a la espera de la decisión de Cristian, «Venta susp.»).
  static Future<SalidaTerminoEntrevista?> terminar(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    bool pedirSalida = false,
    bool desdeLaJornada = false,
    bool conVenta = true,
  }) => terminarEn(
    context,
    ProviderScope.containerOf(context, listen: false),
    colportorId: colportorId,
    pedirSalida: pedirSalida,
    desdeLaJornada: desdeLaJornada,
    conVenta: conVenta,
  );

  /// Lo mismo que [terminar] para quien no es un widget: lee del [ref] que le pasan, el contenedor.
  static Future<SalidaTerminoEntrevista?> terminarEn(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    bool pedirSalida = false,
    bool desdeLaJornada = false,
    bool conVenta = true,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final estado = await notificador.esperarLectura();
    final entrevista = estado.entrevista;
    if (entrevista == null || !context.mounted) return null;
    final rotulo = await _rotulo(ref, entrevista);
    if (!context.mounted) return null;

    final reloj = ref.read(relojEntrevistaProvider);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final medidas = MediaQuery.maybeOf(context);
    // «Sin salida» (25/10): si la casa ya no está en el teléfono no hay dónde guardar la visita; la
    // entrevista se suelta y la hoja se cierra con un aviso, para no dejar trabado el cierre de la
    // jornada.
    var sinLugar = false;
    // Las horas con las que se (re)abre la hoja: las de la entrevista, o las que la colportora ya
    // confirmó si vuelve con atrás desde el nombre de la venta.
    var entradaVista = entrevista.inicio;
    DateTime? salidaVista = pedirSalida ? null : reloj();
    var persona = rotulo.persona;
    // Lo que se guardó, para el aviso de «Lo que dejaste» (42B·08E) y su «Deshacer».
    ResultadoVisitaRegistrado? registrado;
    var dejadosGuardados = 0;
    final misioneros = await _misioneros(ref);
    if (!context.mounted) return null;
    SalidaTerminoEntrevista? resultado;
    while (true) {
      if (!context.mounted) return null;
      final r = resultado = await mostrarHojaTerminoEntrevista(
        context,
        direccion: rotulo.direccion,
        persona: persona,
        entrada: entradaVista,
        salida: salidaVista,
        entradaInferida: false,
        reloj: reloj,
        misioneros: misioneros,
        alGuardar: (entrada, salida, dejados) async {
          final guardado = await notificador.finalizar(
            entrada: entrada,
            salida: salida,
            misioneros: dejados,
          );
          // `null`: ya había un guardado en curso (no pasa con la hoja, que lo impide).
          if (guardado == null) return const FailureInesperado();
          return guardado.fold<Failure?>(
            (falla) {
              if (falla != entrevistaSinLugar) return falla;
              sinLugar = true;
              return null;
            },
            (g) {
              registrado = g;
              dejadosGuardados = dejados.values.fold(0, (a, n) => a + n);
              return null;
            },
          );
        },
      );
      if (r is! QuiereRegistrarLaVenta || !conVenta || !context.mounted) break;
      // La venta necesita a quién: una entrevista sin persona pide el nombre antes (decisión de
      // Cristian, 05/11, «Entrev. s/n»). Atrás vuelve a esta hoja con las horas ya confirmadas.
      final enCurso = ref.read(entrevistaEnCursoProvider(colportorId)).entrevista;
      if (enCurso == null || enCurso.espacioPersonaId != null) break;
      final pedida = await _pedirLaPersona(
        context,
        ref,
        colportorId: colportorId,
        espacioId: enCurso.espacioId,
      );
      if (!context.mounted) return const VentaSinCompletar();
      if (pedida == null) {
        entradaVista = r.entrada;
        salidaVista = r.salida;
        continue;
      }
      final vinculo = pedida.vinculo;
      if (vinculo == null) {
        _avisar(mensajero, TextosEntrevista.ventaNoGuardada(pedida.nombre));
        return const VentaSinCompletar();
      }
      await notificador.ponerPersona(vinculo);
      persona = pedida.nombre;
      break;
    }
    if (resultado is EntrevistaGuardada) {
      final guardada = registrado;
      if (!sinLugar && dejadosGuardados > 0 && guardada != null && mensajero != null) {
        await _avisarMisioneros(
          ref,
          mensajero,
          mediaQuery: medidas ?? const MediaQueryData(),
          cuantos: dejadosGuardados,
          guardada: guardada,
          direccion: _lugar(rotulo.direccion),
        );
      } else {
        mensajero?.showSnackBar(
          SnackBar(
            content: Text(
              sinLugar
                  ? TextosEntrevista.sinLugar
                  : TextosEntrevista.guardada(_lugar(rotulo.direccion)),
            ),
          ),
        );
      }
      // Tras guardar, el mapa queda libre con la casa a la vista (05/11). Desde «Finalizar jornada»
      // la colportora sigue en lo suyo: no se la saca de ahí.
      if (!desdeLaJornada) await _volverAlMapa(ref, entrevista.espacioId);
    }
    final quiere = resultado;
    if (quiere is QuiereRegistrarLaVenta && conVenta) {
      if (!context.mounted) return const VentaSinCompletar();
      return _registrarLaVenta(
        context,
        ref,
        colportorId: colportorId,
        persona: persona,
        direccion: rotulo.direccion,
        desdeLaJornada: desdeLaJornada,
        preparar: () => notificador.prepararVenta(entrada: quiere.entrada, salida: quiere.salida),
        guardarVisita: notificador.guardarVisitaDeLaVenta,
        soltar: notificador.soltarTrasLaVenta,
      );
    }
    return resultado;
  }

  /// R·07: «Terminó la entrevista» **sin inicio registrado**. La entrada es la hora de la visita
  /// anterior de la colportora (con el aviso de que se tomó de ahí) o, si no tiene ninguna, queda
  /// para elegir. La salida es «ahora». Los ids de la visita se fijan al abrir la hoja: reintentar
  /// tras una falla no la guarda dos veces.
  static Future<SalidaTerminoEntrevista?> terminarSinInicio(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    required String espacioId,
    String? espacioPersonaId,
    required String direccion,
    required String persona,
    String? agendaId,
    String? jornadaId,
  }) => terminarSinInicioEn(
    context,
    ProviderScope.containerOf(context, listen: false),
    colportorId: colportorId,
    espacioId: espacioId,
    espacioPersonaId: espacioPersonaId,
    direccion: direccion,
    persona: persona,
    agendaId: agendaId,
    jornadaId: jornadaId,
  );

  /// Lo mismo que [terminarSinInicio] para quien no es un widget: lee del [ref] que le pasan, el
  /// contenedor.
  static Future<SalidaTerminoEntrevista?> terminarSinInicioEn(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    required String espacioId,
    String? espacioPersonaId,
    required String direccion,
    required String persona,
    String? agendaId,
    String? jornadaId,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final entradaPrevia = await notificador.horaDeLaVisitaAnterior();
    if (!context.mounted) return null;
    final reloj = ref.read(relojEntrevistaProvider);
    final ids = ref.read(registrarResultadoVisitaUseCaseProvider).nuevosIds();
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final medidas = MediaQuery.maybeOf(context);
    final inferida = entradaPrevia != null;
    // Con quién es la entrevista: sin persona hasta que, si hay venta, se pide el nombre.
    var vinculo = espacioPersonaId;
    var nombre = persona;
    FinalizarEntrevistaParams parametros(
      DateTime entrada,
      DateTime salida, [
      Map<String, int> dejados = const {},
    ]) => FinalizarEntrevistaParams(
      ids: ids,
      espacioId: espacioId,
      espacioPersonaId: vinculo,
      colportorId: colportorId,
      entrada: entrada,
      salida: salida,
      agendaId: agendaId,
      jornadaId: jornadaId,
      nota: ref.read(entrevistaEnCursoProvider(colportorId)).notaBorrador,
      misioneros: dejados,
    );
    var entradaVista = entradaPrevia;
    var salidaVista = reloj();
    ResultadoVisitaRegistrado? registrado;
    var dejadosGuardados = 0;
    final misioneros = await _misioneros(ref);
    if (!context.mounted) return null;
    SalidaTerminoEntrevista? resultado;
    while (true) {
      final r = resultado = await mostrarHojaTerminoEntrevista(
        context,
        direccion: direccion,
        persona: nombre,
        entrada: entradaVista,
        salida: salidaVista,
        entradaInferida: inferida,
        reloj: reloj,
        misioneros: misioneros,
        alGuardar: (entrada, salida, dejados) async {
          final guardado = await notificador.finalizarSinInicio(
            parametros(entrada, salida, dejados),
          );
          // Sin entrevista en curso no hay nada que «se cierre»: lo que no se guardó es la visita.
          return guardado.fold<Failure?>(
            (falla) => falla == entrevistaSinLugar
                ? const FailureValidacion(
                    campos: {'espacio': TextosEntrevista.sinLugarSinInicio},
                    mensaje: TextosEntrevista.sinLugarSinInicio,
                  )
                : falla,
            (g) {
              registrado = g;
              dejadosGuardados = dejados.values.fold(0, (a, n) => a + n);
              return null;
            },
          );
        },
      );
      if (r is! QuiereRegistrarLaVenta || !context.mounted || vinculo != null) break;
      // La venta necesita a quién (decisión de Cristian, 05/11, «Entrev. s/n»); atrás vuelve a esta hoja.
      final pedida = await _pedirLaPersona(
        context,
        ref,
        colportorId: colportorId,
        espacioId: espacioId,
      );
      if (!context.mounted) return const VentaSinCompletar();
      if (pedida == null) {
        entradaVista = r.entrada;
        salidaVista = r.salida;
        continue;
      }
      if (pedida.vinculo == null) {
        _avisar(mensajero, TextosEntrevista.ventaNoGuardada(pedida.nombre));
        return const VentaSinCompletar();
      }
      vinculo = pedida.vinculo;
      nombre = pedida.nombre;
      break;
    }
    if (resultado is EntrevistaGuardada) {
      final guardada = registrado;
      if (dejadosGuardados > 0 && guardada != null && mensajero != null) {
        await _avisarMisioneros(
          ref,
          mensajero,
          mediaQuery: medidas ?? const MediaQueryData(),
          cuantos: dejadosGuardados,
          guardada: guardada,
          direccion: _lugar(direccion),
        );
      } else {
        mensajero?.showSnackBar(
          SnackBar(content: Text(TextosEntrevista.guardada(_lugar(direccion)))),
        );
      }
      // Tras guardar, el mapa queda libre con la casa a la vista (05/11).
      await _volverAlMapa(ref, espacioId);
    }
    final quiere = resultado;
    if (quiere is QuiereRegistrarLaVenta) {
      if (!context.mounted) return const VentaSinCompletar();
      final casoDeUso = ref.read(cerrarEntrevistaConVentaUseCaseProvider);
      return _registrarLaVenta(
        context,
        ref,
        colportorId: colportorId,
        persona: nombre,
        direccion: direccion,
        desdeLaJornada: false,
        // Sin entrevista en curso no hay nada que soltar: la visita se guarda con la venta.
        preparar: () => casoDeUso.preparar(parametros(quiere.entrada, quiere.salida)),
        guardarVisita: casoDeUso.guardarVisita,
      );
    }
    return resultado;
  }

  /// R·07 cuando «Empezar entrevista» no se pudo guardar (vista 39, R·04): lo mismo que
  /// [terminarSinInicioEn], con la dirección y el nombre leídos de lo que hay en el teléfono.
  static Future<SalidaTerminoEntrevista?> terminarSinInicioDeLaCasa(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    required String espacioId,
    String? espacioPersonaId,
    String? agendaId,
    String? jornadaId,
  }) async {
    final rotulo = await _rotuloDe(ref, espacioId: espacioId, espacioPersonaId: espacioPersonaId);
    if (!context.mounted) return null;
    return terminarSinInicioEn(
      context,
      ref,
      colportorId: colportorId,
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      direccion: rotulo.direccion,
      persona: rotulo.persona,
      agendaId: agendaId,
      jornadaId: jornadaId,
    );
  }

  /// «Sí, registrar la venta» (R·06 / R·07 → vista 27 → R·08; #428).
  ///
  /// 1. [preparar] arma la visita `VENTA` sin guardar nada. Si ya no hay casa o persona, un aviso dice
  ///    qué pasó y la entrevista sigue en curso.
  /// 2. Abre la venta con la casa, la persona y la visita puestas. Al registrarla, la visita `VENTA` se
  ///    guarda en la misma transacción ([guardarVisita]): si la venta no se guarda, la visita tampoco
  ///    (R44). Después, [soltar] cierra la entrevista en curso.
  /// 3. 27A·14 «Venta registrada: ¿y ahora?»: «Cobrar ahora» abre el cobro (vista 28) y «Entregar
  ///    ahora» la entrega (27B, #432), en ese orden: así, con todo cobrado y entregado, 27B·03 dice
  ///    «Venta completa». «Entregar otro día» (27C) llega con #435.
  /// 4. Con saldo —lo que quedó sin cobrar—, pregunta «¿Cuándo volvés a cobrar?» y agenda la cobranza
  ///    (decisión «Agenda cobro»).
  /// 5. R·08, tras guardar: el mapa queda libre con la casa a la vista y su color nuevo (decisión de
  ///    Cristian, 05/11); al volver a tocarla, su hoja muestra la cobranza pendiente y la cita con «Cambiar».
  static Future<SalidaTerminoEntrevista> _registrarLaVenta(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    required String persona,
    required String direccion,
    required bool desdeLaJornada,
    required Future<Either<Failure, VentaDeLaEntrevista>> Function() preparar,
    required Future<void> Function(VentaDeLaEntrevista) guardarVisita,
    Future<Either<Failure, Unit>> Function(VentaDeLaEntrevista)? soltar,
    bool avisarSiNoSeGuardo = true,
  }) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    final noSeGuardo = desdeLaJornada
        ? TextosEntrevista.ventaNoGuardadaEnLaJornada(persona)
        : TextosEntrevista.ventaNoGuardada(persona);

    VentaDeLaEntrevista? venta;
    Failure? falla;
    try {
      (await preparar()).fold((f) => falla = f, (v) => venta = v);
    } on Object {
      falla = const FailureInesperado();
    }
    final preparada = venta;
    if (preparada == null) {
      // Las fallas de validación ya dicen qué pasó y qué hacer; cualquier otra, el aviso común.
      final f = falla;
      _avisar(
        mensajero,
        f is FailureValidacion ? TextosEntrevista.ventaNoGuardadaCon(f.mensaje) : noSeGuardo,
      );
      return const VentaSinCompletar();
    }
    if (!context.mounted) return const VentaSinCompletar();
    return _venderYSeguir(
      context,
      ref,
      mensajero: mensajero,
      navegador: navegador,
      colportorId: colportorId,
      espacioId: preparada.espacioId,
      espacioPersonaId: preparada.espacioPersonaId,
      persona: persona,
      direccion: direccion,
      desdeLaJornada: desdeLaJornada,
      visitaId: preparada.visitaId,
      antesDeGuardar: () => guardarVisita(preparada),
      soltar: soltar == null ? null : () => soltar(preparada),
      // Volver atrás desde la venta sin guardar no avisa nada si no hay entrevista que siga en curso.
      noSeGuardo: avisarSiNoSeGuardo ? noSeGuardo : null,
    );
  }

  /// El paso del nombre de la venta de una entrevista **sin persona** (decisión de Cristian, 05/11,
  /// «Entrev. s/n»): el alta corta (32 A) de la casa de la entrevista. Devuelve a la persona dada de
  /// alta (su vínculo y su nombre), o `null` si la colportora volvió atrás sin guardar a nadie: no se
  /// guardó nada y la entrevista sigue como estaba. Si la persona quedó guardada pero no se pudo leer
  /// su vínculo, `vinculo` viene `null` (la persona está; la venta no sigue).
  static Future<({String? vinculo, String nombre})?> _pedirLaPersona(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    required String espacioId,
  }) async {
    final nueva = await AltaPersonaPage.abrir(
      context,
      espacioId: espacioId,
      colportorId: colportorId,
      ayuda: TextosPersonas.altaParaVender,
    );
    if (nueva == null) return null;
    final nombre = FormatoPersonas.nombreCompleto(nueva);
    String? vinculo;
    try {
      final personas = await ref
          .read(personaRepositoryProvider)
          .observarDelEspacio(espacioId)
          .first
          .timeout(const Duration(seconds: 2));
      for (final p in personas) {
        if (p.persona.id == nueva.id) {
          vinculo = p.vinculo.id;
          break;
        }
      }
    } on Object {
      // Sin el vínculo no se sigue a la venta: la persona ya quedó guardada en la casa.
    }
    return (vinculo: vinculo, nombre: nombre);
  }

  /// «+ Registrar venta» de la pestaña Ventas (#546, decisión de Cristian del 28/10): la venta (vista
  /// 27) de la persona elegida en «¿A quién le vendés?» y todo el hilo que sigue (27A·14, la entrega,
  /// el cobro, «¿Cuándo volvés a cobrar?» y «Así quedó la venta», 42B·01), con la casa y la persona ya
  /// resueltas. No hay entrevista ni visita: la venta sale de la pestaña, no de una casa abierta. El
  /// cierre termina con «Listo» y vuelve a quien lo abrió (no al mapa), con el aviso de lo que quedó.
  ///
  /// Devuelve [VentaGuardadaEnLaEntrevista] si se guardó, o [VentaSinCompletar] si no.
  static Future<SalidaTerminoEntrevista> venderDesdeVentas(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    required String espacioId,
    required String espacioPersonaId,
    required String persona,
    required String direccion,
  }) {
    final navegador = Navigator.of(context);
    return _venderYSeguir(
      context,
      ref,
      mensajero: ScaffoldMessenger.maybeOf(context),
      navegador: navegador,
      colportorId: colportorId,
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      persona: persona,
      direccion: direccion,
      // Como desde la jornada: «Listo» y sin llevar al mapa.
      desdeLaJornada: true,
      noSeGuardo: null,
    );
  }

  /// «Vender» de «¿Qué pasó?» (vista 39, decisión de Cristian del 04/11, «Vender desde el mapa»): la
  /// venta (vista 27) de la casa y la persona que ya tuvieron una entrevista dada, y de ahí todo lo que
  /// sigue a «Sí, registrar la venta»: «Venta registrada», el cobro, «¿Cuándo volvés a cobrar?» y R·08
  /// (vuelve al mapa libre, con la casa a la vista).
  ///
  /// Además de la venta guarda una visita «Venta» de hoy (decisión de Cristian, 05/11, «Vender visita»),
  /// con la misma regla de «Sí, registrar la venta» (R44): la visita se guarda **en la misma
  /// transacción** que la venta, así que si la venta no se guarda no queda la visita. Lleva la jornada
  /// abierta ([jornadaId]) y la agenda que cumple ([agendaId]), si las hay; no hay entrevista que
  /// cerrar. Si la casa o la persona ya no están, no se vende y un aviso dice qué hacer.
  ///
  /// Devuelve [VentaGuardadaEnLaEntrevista] si se guardó, o [VentaSinCompletar] si no (no cambió nada).
  static Future<SalidaTerminoEntrevista> venderDesdeLaCasa(
    BuildContext context,
    ProviderContainer ref, {
    required String colportorId,
    required String espacioId,
    required String espacioPersonaId,
    String? agendaId,
    String? jornadaId,
  }) async {
    final rotulo = await _rotuloDe(ref, espacioId: espacioId, espacioPersonaId: espacioPersonaId);
    if (!context.mounted) return const VentaSinCompletar();
    final casoDeUso = ref.read(cerrarEntrevistaConVentaUseCaseProvider);
    final ahora = ref.read(relojEntrevistaProvider)();
    // Los ids de la visita se fijan una vez: el reintento de la venta no la guarda dos veces.
    final ids = ref.read(registrarResultadoVisitaUseCaseProvider).nuevosIds();
    return _registrarLaVenta(
      context,
      ref,
      colportorId: colportorId,
      persona: rotulo.persona,
      direccion: rotulo.direccion,
      desdeLaJornada: false,
      preparar: () async {
        final preparada = await casoDeUso.preparar(
          FinalizarEntrevistaParams(
            ids: ids,
            espacioId: espacioId,
            espacioPersonaId: espacioPersonaId,
            colportorId: colportorId,
            // No hay entrevista con horas: la visita es del momento en que se vende y no guarda
            // horas de entrevista (#466).
            entrada: ahora,
            salida: ahora,
            conHoras: false,
            agendaId: agendaId,
            jornadaId: jornadaId,
          ),
        );
        // Los avisos de la entrevista hablan de «la entrevista»: acá no hay ninguna en curso.
        return preparada.leftMap(
          (f) => f == ventaSinLugar
              ? ventaDeLaCasaSinLugar
              : f == ventaSinPersona
              ? ventaDeLaCasaSinPersona
              : f,
        );
      },
      guardarVisita: casoDeUso.guardarVisita,
      // Volver atrás desde la venta sin guardar no avisa nada (QA de #648, P1): «¿Qué pasó?» queda
      // abierta como estaba y no cambió nada, no hay qué decir.
      avisarSiNoSeGuardo: false,
    );
  }

  /// Los misioneros que se pueden anotar en «Lo que dejaste» (42B·08, #608). Si no se pueden leer,
  /// ninguno: el paso no aparece y guardar la entrevista no espera al catálogo.
  static Future<List<MisioneroParaDejar>> _misioneros(ProviderContainer ref) async {
    try {
      return await ref.read(misionerosParaDejarProvider).leer().timeout(const Duration(seconds: 2));
    } on Object {
      return const [];
    }
  }

  /// 42B·08E: «Entrevista guardada. Dejaste 3 misioneros.» con «Deshacer» (como R·01), que da de
  /// baja la visita y sus misioneros. Sin conexión (42B·08F) dice que quedó en el celular.
  static Future<void> _avisarMisioneros(
    ProviderContainer ref,
    ScaffoldMessengerState mensajero, {
    required MediaQueryData mediaQuery,
    required int cuantos,
    required ResultadoVisitaRegistrado guardada,
    required String direccion,
  }) async {
    var sinRed = false;
    try {
      sinRed =
          await ref
              .read(monitorConectividadProvider)
              .actual()
              .timeout(const Duration(seconds: 1)) ==
          TipoConexion.sinConexion;
    } on Object {
      sinRed = false;
    }
    if (sinRed) {
      _avisar(mensajero, TextosEntrevista.guardadaConMisionerosSinRed(cuantos));
      return;
    }
    final deshacer = ref.read(deshacerResultadoVisitaUseCaseProvider);
    var tocado = false;
    mensajero.clearSnackBars();
    mostrarAvisoConDeshacer(
      mensajero,
      mediaQuery: mediaQuery,
      texto: TextosEntrevista.guardadaConMisioneros(cuantos),
      etiquetaDeshacer: TextosRegistrarVisita.deshacer,
      duracion: TextosRegistrarVisita.duracionDeshacer,
      alDeshacer: () {
        // Un segundo toque (o uno tardío) no deshace dos veces.
        if (tocado) return;
        tocado = true;
        unawaited(() async {
          var deshecha = false;
          try {
            deshecha = (await deshacer(
              DeshacerResultadoVisitaParams.de(guardada.guardada),
            )).isRight();
          } on Object {
            deshecha = false;
          }
          mensajero.showSnackBar(
            SnackBar(
              content: Text(
                deshecha
                    ? TextosRegistrarVisita.seDeshizo(direccion)
                    : TextosRegistrarVisita.noPudimosDeshacer,
              ),
            ),
          );
        }());
      },
    );
  }

  static void _avisar(ScaffoldMessengerState? mensajero, String texto) => mensajero
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(texto)));

  /// Desde la venta hacia adelante (vista 27 → 27A·14 → cobro → «¿Cuándo volvés a cobrar?» → R·08), con
  /// la casa y la persona ya resueltas. [antesDeGuardar] y [visitaId] solo los trae la venta que sale de
  /// una entrevista; [soltar] cierra esa entrevista una vez guardada la venta. [noSeGuardo] es el aviso de
  /// la venta que no se completó (la entrevista sigue en curso); `null` = sin aviso.
  static Future<SalidaTerminoEntrevista> _venderYSeguir(
    BuildContext context,
    ProviderContainer ref, {
    required ScaffoldMessengerState? mensajero,
    required NavigatorState navegador,
    required String colportorId,
    required String espacioId,
    required String espacioPersonaId,
    required String persona,
    required String direccion,
    required bool desdeLaJornada,
    required String? noSeGuardo,
    String? visitaId,
    Future<void> Function()? antesDeGuardar,
    Future<Either<Failure, Unit>> Function()? soltar,
  }) async {
    // Al guardar la venta la entrevista se suelta y el aviso fijo del mapa (de donde puede venir este
    // flujo) sale del árbol: su `context` se desmonta a mitad de camino. Lo que sigue usa el contexto
    // del navegador y el contenedor, que duran lo que dura la app.
    final contextoFirme = navegador.context;
    void avisar(String texto) => _avisar(mensajero, texto);

    final cliente = await _cliente(
      ref,
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      persona: persona,
      direccion: direccion,
    );
    if (!context.mounted) return const VentaSinCompletar();
    final guardada = await navegador.push(
      NuevaVentaPage.ruta(
        argumentos: ArgumentosDeVenta(
          colportorId: colportorId,
          cliente: cliente,
          visitaId: visitaId,
        ),
        antesDeGuardar: antesDeGuardar,
      ),
    );
    if (guardada == null) {
      if (noSeGuardo != null) avisar(noSeGuardo);
      return const VentaSinCompletar();
    }

    // La venta y la visita ya están guardadas: lo que sigue no las deshace.
    var cerrada = true;
    if (soltar != null) {
      try {
        cerrada = (await soltar()).isRight();
      } on Object {
        cerrada = false;
      }
    }
    final numero = guardada.venta.numeroTalonario;
    final total = guardada.totalCentavos;

    // El hilo de la venta (vista 42, 42B·01): 27A·14 → entrega (27B·01) → cobro (28·01) → con saldo,
    // «¿Cuándo volvés a cobrar?» (01B) → «Así quedó la venta» (01D a 01G) → el mapa con un aviso (01H).
    var entrega = EntregaDelCierre.otroDia;
    // La entrega que quedó agendada en «Entregar otro día» (27C·01, #435), para el cierre (01F, 01G).
    ResultadoDiferirEntrega? diferida;
    var saldo = total;
    CobranzaDeLaVenta cobranza = const SinSaldoQueCobrar();
    if (contextoFirme.mounted) {
      final cobrar = ref.read(cobrarDespuesDeLaVentaProvider);
      // Salir del cobro sin cobrar nada vuelve a «¿Y ahora?» con el saldo intacto (decisión del 10/11,
      // P4 del QA): no adelanta el hilo. Lo ya entregado no se vuelve a ofrecer.
      while (true) {
        final seguimiento = contextoFirme.mounted
            ? await _ventaRegistrada(
                contextoFirme,
                guardada: guardada,
                nombre: cliente.nombre,
                // Con la entrega ya agendada (27C·01) el grupo ENTREGA no vuelve: entregarla ahora
                // dejaría una «Entrega agendada» de algo entregado (revisión de #687).
                conEntregarAhora: entrega == EntregaDelCierre.otroDia && diferida == null,
                conEntregarOtroDia: entrega == EntregaDelCierre.otroDia && diferida == null,
                conCobro: cobrar != null,
              )
            : null;
        if (seguimiento?.entrega == MomentoDeEntrega.ahora && contextoFirme.mounted) {
          final registrada = await _entregarAhora(
            contextoFirme,
            guardada: guardada,
            nombre: cliente.nombre,
          );
          if (registrada != null) {
            entrega = registrada.quedaPendiente
                ? EntregaDelCierre.parcial
                : EntregaDelCierre.completa;
            // Lo que se había dejado para otro día se acaba de entregar (su cita ya se cumplió): el
            // cierre no muestra una «Entrega agendada» de algo entregado. Si quedó algo, se pregunta
            // de nuevo para cuándo (abajo).
            diferida = null;
          }
        }
        // «Entregar otro día» (27C·01): la fecha de la entrega. Volver sin guardarla vuelve a «¿Y
        // ahora?», como salir del cobro sin cobrar.
        if (seguimiento?.entrega == MomentoDeEntrega.otroDia && contextoFirme.mounted) {
          diferida = await _entregarOtroDia(
            contextoFirme,
            guardada: guardada,
            nombre: cliente.nombre,
          );
          if (diferida == null) continue;
        }
        if (seguimiento?.cobrarAhora == true && cobrar != null && contextoFirme.mounted) {
          final quedo = await _cobrarAhora(
            ref,
            cobrar,
            guardada: guardada,
            espacioId: espacioId,
            espacioPersonaId: espacioPersonaId,
            colportorId: colportorId,
          );
          if (quedo == null) continue;
          saldo = quedo;
        }
        break;
      }
      // Sin entregar todo y sin fecha de entrega todavía, la app la pide antes del cierre y antes de
      // «¿Cuándo volvés a cobrar?» (42B·01F: cobrada sin entregar; 01G: «Terminar sin entregar ni
      // cobrar»; y tras una entrega parcial, para lo que quedó: decisión del 10/11, P2 de #687).
      // Volver sin elegir la deja sin fecha: lo que falta sigue en «Entregas pendientes».
      if (entrega != EntregaDelCierre.completa && diferida == null && contextoFirme.mounted) {
        diferida = await _entregarOtroDia(
          contextoFirme,
          guardada: guardada,
          nombre: cliente.nombre,
        );
      }
      if (contextoFirme.mounted) {
        cobranza = await FlujoCuandoCobrar.preguntar(
          contextoFirme,
          ref,
          numeroTalonario: numero,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
          colportorId: colportorId,
          persona: cliente.nombre,
          direccion: cliente.direccion,
          saldoCentavos: saldo,
        );
      }
      if (contextoFirme.mounted) {
        final descripcion = await _descripcion(ref, guardada.venta.id);
        if (contextoFirme.mounted) {
          cobranza = await AsiQuedoLaVentaPage.abrir(
            contextoFirme,
            AsiQuedoLaVentaPage(
              numeroTalonario: numero,
              persona: cliente.nombre,
              direccion: cliente.direccion,
              descripcion: descripcion,
              totalCentavos: total,
              entrega: entrega,
              entregaAgendada: diferida == null
                  ? null
                  : (
                      fecha: diferida.entrega.cita.fechaProgramada.toLocal(),
                      conRecordatorio: diferida.recordatorio == ResultadoRecordatorio.programado,
                    ),
              cobradoCentavos: total - saldo,
              saldoCentavos: saldo,
              cobranza: cobranza,
              textoBoton: desdeLaJornada ? TextosVenta.listo : TextosCierreDeVenta.volverAlMapa,
              alCambiar: (agenda) => _cambiarLaCobranza(contextoFirme, agenda, colportorId),
              alPonerFecha: () => FlujoCuandoCobrar.preguntar(
                contextoFirme,
                ref,
                numeroTalonario: numero,
                espacioId: espacioId,
                espacioPersonaId: espacioPersonaId,
                colportorId: colportorId,
                persona: cliente.nombre,
                direccion: cliente.direccion,
                saldoCentavos: saldo,
              ),
            ),
          );
        }
      }
    }
    // 42B·01H: el aviso en el mapa, con lo que quedó.
    final diaDeEntrega = diferida?.entrega.cita.fechaProgramada.toLocal();
    avisar(switch (cobranza) {
      _ when !cerrada => TextosEntrevista.ventaGuardadaEntrevistaAbierta,
      CobranzaAgendada(:final agenda) when diaDeEntrega != null =>
        TextosCierreDeVenta.avisoEntregaYCobranzaAgendada(
          numero,
          diaDeEntrega,
          agenda.fechaProgramada.toLocal(),
        ),
      CobranzaSinFecha() when diaDeEntrega != null =>
        TextosCierreDeVenta.avisoEntregaYCobranzaSinFecha(numero, diaDeEntrega),
      SinSaldoQueCobrar() when diaDeEntrega != null => TextosCierreDeVenta.avisoEntregaAgendada(
        numero,
        diaDeEntrega,
      ),
      CobranzaAgendada(:final agenda) => TextosCierreDeVenta.avisoCobranzaAgendada(
        numero,
        agenda.fechaProgramada.toLocal(),
      ),
      CobranzaSinFecha() => TextosCierreDeVenta.avisoCobranzaSinFecha(numero),
      // La cita no se guardó: el aviso lo repite y dice qué hacer.
      CobranzaNoAgendada() => TextosCuandoCobrar.noSePudoAgendar,
      SinSaldoQueCobrar() when entrega == EntregaDelCierre.completa && saldo <= 0 =>
        TextosCierreDeVenta.avisoEntregadaYPagada(numero),
      SinSaldoQueCobrar() => TextosEntrevista.ventaGuardada(numero),
    });
    final cita = switch (cobranza) {
      CobranzaAgendada(:final agenda) => agenda,
      _ => null,
    };
    if (!desdeLaJornada) {
      await _volverAlMapa(ref, espacioId, cobranza: cita, persona: cliente.nombre);
    }
    return VentaGuardadaEnLaEntrevista(numeroTalonario: numero);
  }

  /// 27A·14 «Venta registrada: ¿y ahora?». Sin salida del atrás: se sale con «Continuar» (o «Terminar
  /// sin entregar ni cobrar») y es lo que elige lo que se hace después. `null` = terminó sin pedir nada.
  static Future<SeguimientoDeLaVenta?> _ventaRegistrada(
    BuildContext context, {
    required VentaGuardada guardada,
    required String nombre,
    required bool conEntregarAhora,
    required bool conEntregarOtroDia,
    required bool conCobro,
  }) => Navigator.of(context).push<SeguimientoDeLaVenta>(
    MaterialPageRoute(
      builder: (ruta) => VentaRegistradaPage(
        guardada: guardada,
        nombreDelCliente: nombre,
        conEntregarAhora: conEntregarAhora,
        conEntregarOtroDia: conEntregarOtroDia,
        conCobro: conCobro,
        alContinuar: (seguimiento) => Navigator.of(ruta).pop(seguimiento),
        alTerminar: () => Navigator.of(ruta).pop(),
      ),
    ),
  );

  /// «Entregar ahora» (27B·01, #432): la colportora tilda lo que entrega y, registrada la entrega,
  /// sigue el hilo de la venta (42B·01 reemplaza a 27B·03 y 27B·04). `null` si volvió atrás sin
  /// entregar: la venta queda para entregar otro día.
  static Future<EntregaRegistrada?> _entregarAhora(
    BuildContext context, {
    required VentaGuardada guardada,
    required String nombre,
  }) => Navigator.of(context).push<EntregaRegistrada>(
    MaterialPageRoute<EntregaRegistrada>(
      builder: (ruta) => EntregarAhoraPage(
        guardada: guardada,
        nombreDelCliente: nombre,
        alEntregar: (registrada) => Navigator.of(ruta).pop(registrada),
      ),
    ),
  );

  /// «Entregar otro día» (27C·01, #435): la fecha y la hora de la entrega, con su cita y su
  /// recordatorio. Sin aviso propio: lo que quedó lo dicen el cierre y el aviso del mapa. `null` si
  /// volvió sin guardar.
  static Future<ResultadoDiferirEntrega?> _entregarOtroDia(
    BuildContext context, {
    required VentaGuardada guardada,
    required String nombre,
  }) => Navigator.of(context).push<ResultadoDiferirEntrega>(
    EntregarOtroDiaPage.ruta(guardada: guardada, nombreDelCliente: nombre, conAviso: false),
  );

  /// «Cambiar» de la cobranza en «Así quedó la venta» (42B·01E → 22C·02): «Modificar agenda» con la
  /// cita. Devuelve la cita como quedó, o `null` si no la cambió.
  static Future<Agenda?> _cambiarLaCobranza(
    BuildContext context,
    Agenda agenda,
    String colportorId,
  ) async {
    if (!context.mounted) return null;
    final cambio = await ModificarAgendaPage.abrir(
      context,
      detalle: DetalleDeAgenda(agenda: agenda),
      colportorId: colportorId,
    );
    return cambio?.resultado.agenda;
  }

  /// Lo vendido en una línea («Colección de 1 libro»), para el cierre; vacío si no se puede leer.
  static Future<String> _descripcion(ProviderContainer ref, String ventaId) async {
    try {
      final venta = await ref
          .read(saldoPendienteRepositoryProvider)
          .observarVenta(ventaId)
          .first
          .timeout(const Duration(seconds: 2));
      return venta?.descripcion ?? '';
    } on Object {
      return '';
    }
  }

  /// «Cobrar ahora»: abre el cobro (vista 28) y devuelve lo que quedó sin cobrar, en centavos; `null`
  /// si salió sin cobrar nada. Si falla, o no se puede leer cuánto quedó, es el total de la venta:
  /// preguntar «¿Cuándo volvés a cobrar?» de más es mejor que dejar una deuda sin cita.
  static Future<int?> _cobrarAhora(
    ProviderContainer ref,
    Future<bool> Function(ContextoDeCobroDeLaVenta) cobrar, {
    required VentaGuardada guardada,
    required String espacioId,
    required String espacioPersonaId,
    required String colportorId,
  }) async {
    final total = guardada.totalCentavos;
    try {
      final cobrado = await cobrar((
        ventaId: guardada.venta.id,
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        colportorId: colportorId,
      ));
      if (!cobrado) return null;
      final venta = await ref
          .read(saldoPendienteRepositoryProvider)
          .observarVenta(guardada.venta.id)
          .first
          .timeout(const Duration(seconds: 2));
      return venta?.saldoCentavos ?? total;
    } on Object {
      return total;
    }
  }

  /// A quién y dónde se le vende: el nombre y «Mataojo 2044 · Depto 3B» de lo que hoy hay en el
  /// teléfono; si no se pueden leer, lo que ya mostraba la entrevista.
  static Future<ClienteDeLaVenta> _cliente(
    ProviderContainer ref, {
    required String espacioId,
    required String espacioPersonaId,
    required String persona,
    required String direccion,
  }) async {
    var nombre = persona.trim();
    var lugar = direccion.trim();
    try {
      final contexto = (await ref.read(espacioRepositoryProvider).buscar(espacioId)).fold(
        (_) => null,
        (c) => c,
      );
      if (contexto != null) {
        lugar = FormatoPersonas.dondeEstaElEspacio(contexto.espacio, contexto.ubicacion);
      }
    } on Object {
      // Se queda con la dirección que ya mostraba la entrevista.
    }
    try {
      final personas = await ref
          .read(personaRepositoryProvider)
          .observarDelEspacio(espacioId)
          .first
          .timeout(const Duration(seconds: 2));
      for (final p in personas) {
        if (p.vinculo.id == espacioPersonaId) {
          final leido = [
            p.persona.nombre,
            p.persona.apellido,
          ].where((t) => t.trim().isNotEmpty).join(' ');
          if (leido.isNotEmpty) nombre = leido;
          break;
        }
      }
    } on Object {
      // Se queda con el nombre que ya mostraba la entrevista.
    }
    return ClienteDeLaVenta(
      espacioPersonaId: espacioPersonaId,
      nombre: nombre.isEmpty ? TextosEntrevista.sinNombre : nombre,
      direccion: lugar,
    );
  }

  /// Tras guardar (decisión de Cristian, 05/11, que cambió el R·08 de la vista 39): lo que se hizo con la
  /// casa [espacioId] —el fin de la entrevista o la venta— ya está guardado, así que el mapa queda
  /// libre, con la casa a la vista y su marcador en el color nuevo, y la hoja de la casa no se vuelve a
  /// subir (`NavegacionInicioNotifier.volverAlMapa`). Si quedó agendada una cobranza ([cobranza]), se
  /// marca para que la hoja la muestre como tarjeta con «Cambiar» cuando la colportora la vuelva a
  /// abrir.
  static Future<void> _volverAlMapa(
    ProviderContainer ref,
    String espacioId, {
    Agenda? cobranza,
    String persona = '',
  }) async {
    try {
      // La hoja que ya estaba abierta lee de nuevo: lo que la persona debe cambió con la venta (y con
      // «Cobrar ahora»), y el contexto de la casa solo se entera si se lo pide (QA de #428).
      ref.invalidate(contextoDeLaCasaProvider);
      final lugar = (await ref.read(espacioRepositoryProvider).buscar(espacioId)).fold<String?>(
        (_) => null,
        (c) => c?.ubicacion.id,
      );
      if (lugar == null) return;
      if (cobranza != null) {
        ref.read(cobranzaRecienAgendadaProvider.notifier).marcar((
          ubicacionId: lugar,
          agendaId: cobranza.id,
          persona: persona,
        ));
      }
      ref.read(navegacionInicioProvider.notifier).volverAlMapa(lugar);
    } on Object {
      // Sin llevarla al mapa, la colportora igual lo abre y toca la casa: no se rompe nada.
    }
  }

  static Future<RotuloEntrevista> _rotulo(
    ProviderContainer ref,
    EntrevistaEnCurso entrevista,
  ) async {
    try {
      return await ref.read(rotuloDeEntrevistaProvider(entrevista).future);
    } on Object {
      return (direccion: '', persona: '');
    }
  }

  /// Lo mismo para un lugar y una persona que todavía no tienen una entrevista guardada.
  static Future<RotuloEntrevista> _rotuloDe(
    ProviderContainer ref, {
    required String espacioId,
    String? espacioPersonaId,
  }) async {
    try {
      return await ref.read(
        rotuloDelLugarYLaPersonaProvider((
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
        )).future,
      );
    } on Object {
      return (direccion: '', persona: '');
    }
  }

  /// «Grecia 3307», o «La casa» si no se sabe la dirección.
  static String _lugar(String direccion) => direccion.isEmpty ? 'La casa' : direccion;
}
