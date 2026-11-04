// «Sí, registrar la venta» de la entrevista (vista 39, R·06 / R·07 → vista 27 → R·08; #428): de la hoja
// «Terminó la entrevista» a la venta con la casa, la persona y la visita ya puestas, y de la venta
// guardada a «¿Cuándo volvés a cobrar?» (decisión «Agenda cobro», 23/10).
//
// Por R44, si la venta no se completa el resultado de la visita no se guarda y la entrevista sigue en
// curso. Acá se prueba con la DB de las ventas en memoria, que corre `antesDeGuardar` como lo hace la
// transacción real (solo si la venta llega a guardarse).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/aviso_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/flujo_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/saldo_pendiente_repository.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart'
    show saldoPendienteRepositoryProvider;
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart' show TipoUbicacion;
import 'package:colportores_mobile/features/mapa/presentation/providers/cobranza_recien_agendada_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_cuando_cobrar.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/entrevista_falsos.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/persona_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

/// Lo que registra la visita viene de [MontajeEntrevista.agenda]; lo que agenda, de [agendas].
final class _AgendaDeTodo implements AgendaRepository {
  _AgendaDeTodo(this.visitas, this.agendas);

  final AgendaFalsa visitas;
  final AgendaRepositorioQueAgenda agendas;

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) => visitas.registrarVisita(visita, agendaId: agendaId, nota: nota);

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) =>
      agendas.agendar(agenda, nota: nota);

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda>> modificar(CambiosDeAgenda cambios, {required DateTime ahora}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, DetalleDeAgenda?>> obtenerDetalle(String agendaId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) => throw UnimplementedError();
}

/// Lo que quedó sin cobrar de la venta, tal como lo diría la DB local.
final class _SaldoFalso implements SaldoPendienteRepository {
  _SaldoFalso(this.saldoCentavos);

  final int saldoCentavos;

  @override
  Stream<VentaConSaldo?> observarVenta(String ventaId) => Stream.value(
    VentaConSaldo(
      ventaId: ventaId,
      numeroTalonario: '0039',
      fecha: DateTime(2026, 10, 23),
      montoTotalCentavos: 300000,
      cobradoCentavos: 300000 - saldoCentavos,
    ),
  );

  @override
  Stream<int> observarDePersona(String personaId) => throw UnimplementedError();

  @override
  Stream<int> observarDeUbicacion(String ubicacionId) => throw UnimplementedError();

  @override
  Stream<int> observarTotal(String colportorId) => throw UnimplementedError();
}

ProviderContainer contenedor(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Finder get _cta => find.byKey(const Key('venta_cta'));

Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));

void main() {
  late MontajeEntrevista montaje;
  late EntornoDeVenta entorno;
  late AgendaRepositorioQueAgenda agendas;
  late Telefono telefono;
  SalidaTerminoEntrevista? salida;
  var devolvio = false;
  var extras = <Override>[];

  setUp(() {
    extras = [];
    montaje = MontajeEntrevista();
    entorno = EntornoDeVenta();
    agendas = AgendaRepositorioQueAgenda();
    telefono = Telefono();
    salida = null;
    devolvio = false;
  });

  Future<void> montar(
    WidgetTester tester, {
    double escala = 1,
    Size tamano = const Size(390, 844),
    bool conVenta = true,
    bool conEntrevista = true,
    bool conMapa = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    montaje.agendaPropia = _AgendaDeTodo(montaje.agenda, agendas);
    final personas = PersonaRepositorioFalso()
      ..sembrar([clienteDePersonas('1', 'Pedro', apellido: 'Gómez')]);
    Future<void> corre(Future<SalidaTerminoEntrevista?> Function() flujo) async {
      devolvio = false;
      salida = await flujo();
      devolvio = true;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...montaje.overrides,
          ...entorno.overrides,
          ...telefono.overrides,
          ...extras,
          if (conMapa) ...overridesLista(repo: RepoListaFalso()),
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(casaMataojo()),
          ),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => SingleChildScrollView(
                child: Column(
                  children: [
                    // Como en el mapa: sin entrevista, el aviso sale del árbol (no queda vacío).
                    Consumer(
                      builder: (context, ref, _) =>
                          ref.watch(
                            entrevistaEnCursoProvider('col-1').select((e) => e.hayEntrevista),
                          )
                          ? const AvisoEntrevistaEnCurso(colportorId: 'col-1')
                          : const SizedBox.shrink(),
                    ),
                    ElevatedButton(
                      key: const Key('abrir'),
                      onPressed: () => corre(
                        () => conVenta
                            ? FlujoEntrevista.abrir(context, ref, colportorId: 'col-1')
                            : FlujoEntrevista.terminar(
                                context,
                                ref,
                                colportorId: 'col-1',
                                conVenta: false,
                              ),
                      ),
                      child: const Text('abrir'),
                    ),
                    ElevatedButton(
                      key: const Key('jornada'),
                      onPressed: () => corre(
                        () => FlujoEntrevista.terminar(
                          context,
                          ref,
                          colportorId: 'col-1',
                          pedirSalida: true,
                          desdeLaJornada: true,
                        ),
                      ),
                      child: const Text('jornada'),
                    ),
                    ElevatedButton(
                      key: const Key('sin-inicio'),
                      onPressed: () => corre(
                        () => FlujoEntrevista.terminarSinInicio(
                          context,
                          ref,
                          colportorId: 'col-1',
                          espacioId: 'esp-1',
                          espacioPersonaId: 'ep-1',
                          direccion: 'Grecia 3307',
                          persona: 'Pedro Gómez',
                        ),
                      ),
                      child: const Text('sin inicio'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (conMapa) {
      contenedor(tester).listen(mapaUbicacionesProvider('col-1'), (_, _) {});
      await tester.pumpAndSettle();
    }
    if (conEntrevista) {
      // Empezó en esta sesión, a las 14:23, y ahora son las 14:41 (no se pide la salida).
      montaje.reloj = () => inicioEntrevista;
      await contenedor(tester)
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      montaje.reloj = () => ahoraEntrevista;
      await tester.pumpAndSettle();
    }
  }

  Future<void> tocarKey(WidgetTester tester, Key clave) async {
    await tester.ensureVisible(find.byKey(clave));
    await tester.tap(find.byKey(clave));
    await tester.pumpAndSettle();
  }

  /// R·05 → R·06 → «Sí, registrar la venta».
  Future<void> hastaLaVenta(WidgetTester tester, {bool desdeElAviso = false}) async {
    await tocarKey(tester, desdeElAviso ? ClavesEntrevista.avisoFijo : const Key('abrir'));
    await tocarKey(tester, ClavesEntrevista.finalizar);
    await tocarKey(tester, ClavesEntrevista.registrarVenta);
  }

  /// 27A·01 → 27A·05: un pack fijo ($ 3.000) con el talonario [numero], sin tocar «Registrar».
  Future<void> armarLaVenta(WidgetTester tester, {String numero = '0039'}) async {
    await tocar(tester, find.text('Pack Familia'));
    await tocar(tester, find.text(TextosVenta.armarLaColeccion));
    await tocar(tester, find.text(TextosVenta.agregarALaVenta));
    await escribir(tester, _campo('venta_talonario'), numero);
  }

  Future<void> registrar(WidgetTester tester) async {
    await tocar(tester, _cta);
    await tester.pumpAndSettle();
  }

  /// 27A·14 «Venta registrada: ¿y ahora?» → «Listo». Si la pantalla no está, no hace nada.
  Future<void> listo(WidgetTester tester) async {
    if (find.byKey(const Key('venta_terminar')).evaluate().isEmpty) return;
    await tocarKey(tester, const Key('venta_terminar'));
  }

  /// Lo elegido en «¿Cuándo volvés a cobrar?», pasando antes por «Venta registrada».
  Future<void> elegirCuando(WidgetTester tester, CuandoCobrar opcion) async {
    await listo(tester);
    await tocarKey(tester, ClavesCuandoCobrar.opcion(opcion));
  }

  Future<void> hastaLaPregunta(WidgetTester tester) async {
    await hastaLaVenta(tester);
    await armarLaVenta(tester);
    await registrar(tester);
    await listo(tester);
  }

  group('de «Sí, registrar la venta» a la venta (R·06 → 27)', () {
    testWidgets('abre la venta con la persona y la casa ya puestas, sin guardar nada todavía', (
      tester,
    ) async {
      await montar(tester);

      await hastaLaVenta(tester);

      expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(montaje.agenda.recibidas, isEmpty, reason: 'R44: nada se guarda hasta la venta');
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(devolvio, isFalse);
    });

    testWidgets('la venta guardada deja la visita como VENTA con la venta atada, y cierra la '
        'entrevista', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      final visita = montaje.agenda.recibidas.single.visita;
      expect(visita.tipoResultado, TipoResultadoVisita.venta);
      expect(visita.espacioPersonaId, 'ep-1');
      final venta = entorno.ventas.recibidas.single.venta;
      expect(venta.visitaId, visita.id, reason: 'la venta lleva el id de la visita');
      expect(venta.numeroTalonario, '0039');
      expect(montaje.almacen.guardadas, isEmpty);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
      expect((salida! as VentaGuardadaEnLaEntrevista).numeroTalonario, '0039');
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
      expect(find.text('Venta 0039 guardada.'), findsOneWidget);
    });

    testWidgets('la nota de la entrevista viaja con la visita de la venta', (tester) async {
      await montar(tester);
      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.botonNota);
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'volver con la esposa');
      await tester.pumpAndSettle();
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.registrarVenta);
      await armarLaVenta(tester);
      await registrar(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(montaje.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.venta);
      expect(montaje.agenda.recibidas.single.nota!.texto, 'volver con la esposa');
    });

    testWidgets('si la persona se unió a otra, la visita y la venta cuelgan del vínculo vivo', (
      tester,
    ) async {
      montaje.destino.destino = const DestinoDeEntrevista(
        espacioId: 'esp-2',
        espacioPersonaId: 'ep-9',
      );
      await montar(tester);

      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      final visita = montaje.agenda.recibidas.single.visita;
      expect(visita.espacioId, 'esp-2');
      expect(visita.espacioPersonaId, 'ep-9');
      expect(entorno.ventas.recibidas.single.venta.espacioPersonaId, 'ep-9');
    });
  });

  group('la venta no se completa (R44): la entrevista sigue en curso', () {
    testWidgets('salir de la venta sin guardar no guarda la visita y avisa qué pasó', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaVenta(tester);

      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();

      expect(salida, isA<VentaSinCompletar>());
      expect(montaje.agenda.recibidas, isEmpty);
      expect(entorno.ventas.recibidas, isEmpty);
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(
        find.text('La venta no se guardó. La entrevista con Pedro Gómez sigue en curso.'),
        findsOneWidget,
      );
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
    });

    testWidgets('con la venta a medias, salir pide confirmar y «Seguir» no pierde nada', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaVenta(tester);
      await armarLaVenta(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
      expect(devolvio, isFalse);
      expect(montaje.agenda.recibidas, isEmpty);
    });

    testWidgets('si el guardado de la venta falla, la visita tampoco se guarda y se puede '
        'reintentar', (tester) async {
      await montar(tester);
      await hastaLaVenta(tester);
      await armarLaVenta(tester);
      entorno.ventas.respuesta = const FailureInesperado();

      await registrar(tester);

      expect(find.byKey(const Key('venta_error')), findsOneWidget);
      expect(montaje.agenda.recibidas, isEmpty);
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(devolvio, isFalse);
      expect(
        tester.widget<FilledButton>(_cta).onPressed,
        isNotNull,
        reason: 'el botón vuelve a habilitarse',
      );

      entorno.ventas.respuesta = null;
      await registrar(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(montaje.agenda.recibidas, hasLength(1));
      expect(montaje.almacen.guardadas, isEmpty);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('después de salir, volver a «Finalizar» y registrar la venta guarda una sola '
        'visita', (tester) async {
      await montar(tester);
      await hastaLaVenta(tester);
      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(salida, isA<VentaSinCompletar>());

      // El aviso de la venta que no se guardó se va solo antes de volver a intentar.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await hastaLaVenta(tester);
      await armarLaVenta(tester);
      await registrar(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(montaje.agenda.recibidas, hasLength(1));
      expect(entorno.ventas.recibidas, hasLength(1));
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('dos toques seguidos en «Registrar» guardan una sola venta y una sola visita', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);
      await hastaLaVenta(tester);
      await armarLaVenta(tester);

      final cta = find.semantics.byLabel(RegExp('Registrar'));
      tester.semantics.performAction(cta, SemanticsAction.tap);
      tester.semantics.performAction(cta, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(entorno.ventas.recibidas, hasLength(1));
      expect(montaje.agenda.recibidas, hasLength(1));
      semantica.dispose();
    });

    testWidgets('la casa ya no está: avisa, no abre la venta y la entrevista sigue', (
      tester,
    ) async {
      montaje.destino.sinDestino = true;
      await montar(tester);

      await hastaLaVenta(tester);

      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
      expect(salida, isA<VentaSinCompletar>());
      expect(find.textContaining('La casa de esta entrevista ya no está'), findsOneWidget);
      expect(find.textContaining('cerrala con «No, guardar y volver al mapa»'), findsOneWidget);
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(montaje.agenda.recibidas, isEmpty);
    });

    testWidgets('la persona ya no está: avisa y la entrevista sigue; se cierra sin venta', (
      tester,
    ) async {
      montaje.destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');
      await montar(tester);

      await hastaLaVenta(tester);

      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
      expect(find.textContaining('La persona de esta entrevista ya no está'), findsOneWidget);
      expect(montaje.almacen.guardadas, hasLength(1));

      montaje.destino.destino = null;
      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.finalizar);
      await tocarKey(tester, ClavesEntrevista.guardarYVolver);
      expect(salida, isA<EntrevistaGuardada>());
    });

    testWidgets('si no se pueden leer la casa y la persona, avisa con el texto común', (
      tester,
    ) async {
      montaje.destino.falla = true;
      await montar(tester);

      await hastaLaVenta(tester);

      expect(salida, isA<VentaSinCompletar>());
      expect(
        find.text('La venta no se guardó. La entrevista con Pedro Gómez sigue en curso.'),
        findsOneWidget,
      );
      expect(montaje.almacen.guardadas, hasLength(1));
    });

    testWidgets('si no se puede borrar la entrevista, la venta queda guardada y el aviso lo '
        'dice', (tester) async {
      await montar(tester);
      montaje.rota.fallaAlBorrar = true;

      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(entorno.ventas.recibidas, hasLength(1));
      expect(montaje.agenda.recibidas, hasLength(1));
      expect(find.text(TextosEntrevista.ventaGuardadaEntrevistaAbierta), findsOneWidget);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });
  });

  group('R·08: volver a la casa', () {
    String? seleccionada(WidgetTester tester) =>
        contenedor(tester).read(mapaUbicacionesProvider('col-1')).seleccionadaId;

    testWidgets('con la venta guardada la casa queda elegida en el mapa, con su hoja', (
      tester,
    ) async {
      await montar(tester, conMapa: true);
      expect(seleccionada(tester), isNull);

      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(seleccionada(tester), 'ub-1');
    });

    testWidgets('si la venta no se completa, el mapa queda como estaba', (tester) async {
      await montar(tester, conMapa: true);

      await hastaLaVenta(tester);
      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();

      expect(seleccionada(tester), isNull);
    });

    testWidgets('sin el mapa montado no pasa nada', (tester) async {
      await montar(tester);

      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(tester.takeException(), isNull);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });
  });

  group('desde «Finalizar jornada»: la jornada no se cierra sola detrás de la venta', () {
    Future<void> hastaLaVentaDesdeLaJornada(WidgetTester tester) async {
      await tocarKey(tester, const Key('jornada'));
      await tocarKey(tester, ClavesEntrevista.filaSalida);
      await tocarKey(tester, const Key('hoja_hora_usar'));
      await tocarKey(tester, ClavesEntrevista.registrarVenta);
    }

    testWidgets('con la venta guardada devuelve la venta, no «entrevista guardada»', (
      tester,
    ) async {
      await montar(tester, conMapa: true);
      await hastaLaVentaDesdeLaJornada(tester);
      await armarLaVenta(tester);
      await registrar(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
      expect(salida, isNot(isA<EntrevistaGuardada>()));
      expect(montaje.almacen.guardadas, isEmpty);
      expect(
        contenedor(tester).read(mapaUbicacionesProvider('col-1')).seleccionadaId,
        isNull,
        reason: 'desde la jornada no se vuelve a la casa en el mapa',
      );
    });

    testWidgets('si la venta no se completa, el aviso dice que hay que terminar la entrevista', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaVentaDesdeLaJornada(tester);

      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();

      expect(salida, isA<VentaSinCompletar>());
      expect(
        find.text(
          'La venta no se guardó. La entrevista con Pedro Gómez sigue en curso. '
          'Terminala para poder cerrar la jornada.',
        ),
        findsOneWidget,
      );
      expect(montaje.almacen.guardadas, hasLength(1));
    });
  });

  group('cuenta restringida: no cambia nada hasta que Cristian decida', () {
    testWidgets('«Sí, registrar la venta» sigue devolviendo la intención, sin abrir la venta', (
      tester,
    ) async {
      await montar(tester, conVenta: false);
      await tocarKey(tester, const Key('abrir'));
      await tocarKey(tester, ClavesEntrevista.filaSalida);
      await tocarKey(tester, const Key('hoja_hora_usar'));
      await tocarKey(tester, ClavesEntrevista.registrarVenta);

      expect(salida, isA<QuiereRegistrarLaVenta>());
      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
      expect(montaje.agenda.recibidas, isEmpty);
      expect(montaje.almacen.guardadas, hasLength(1));
    });
  });

  group('R·07 (sin inicio registrado)', () {
    testWidgets('«Sí, registrar la venta» abre la venta y guarda la visita con la venta', (
      tester,
    ) async {
      montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
      await montar(tester, conEntrevista: false);

      await tocarKey(tester, const Key('sin-inicio'));
      await tester.ensureVisible(find.byKey(ClavesEntrevista.registrarVenta));
      await tocarKey(tester, ClavesEntrevista.registrarVenta);
      expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
      await armarLaVenta(tester);
      await registrar(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(montaje.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.venta);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('si la venta no se completa no se guarda nada', (tester) async {
      montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
      await montar(tester, conEntrevista: false);

      await tocarKey(tester, const Key('sin-inicio'));
      await tester.ensureVisible(find.byKey(ClavesEntrevista.registrarVenta));
      await tocarKey(tester, ClavesEntrevista.registrarVenta);
      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();

      expect(salida, isA<VentaSinCompletar>());
      expect(montaje.agenda.recibidas, isEmpty);
    });
  });

  group('«¿Cuándo volvés a cobrar?» (decisión «Agenda cobro»)', () {
    testWidgets('pregunta por el saldo y ofrece hoy, mañana, otro día y sin fecha', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);

      expect(find.text('¿Cuándo volvés a cobrar?'), findsOneWidget);
      expect(find.text(r'Quedan $ 3.000 por cobrar a Pedro Gómez.'), findsOneWidget);
      for (final o in CuandoCobrar.values) {
        expect(find.byKey(ClavesCuandoCobrar.opcion(o)), findsOneWidget, reason: o.name);
      }
    });

    testWidgets('no se puede cerrar sin elegir: ni tocando afuera ni con atrás', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);

      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(devolvio, isFalse);
    });

    testWidgets('«Sin fecha» no agenda nada', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);

      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(agendas.recibidas, isEmpty);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('«Mañana» abre día y hora a las 10:00 y agenda la cobranza de esa persona', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaPregunta(tester);

      await elegirCuando(tester, CuandoCobrar.manana);
      expect(find.byKey(const Key('agendar_hoja_listo')), findsOneWidget);
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      final agenda = agendas.recibidas.single.agenda;
      expect(agenda.tipo, TipoAgenda.cobranza);
      expect(agenda.espacioId, 'esp-1');
      expect(agenda.espacioPersonaId, 'ep-1');
      final ahora = montaje.reloj().toUtc();
      expect(
        agenda.fechaProgramada.toLocal(),
        DateTime(ahora.year, ahora.month, ahora.day + 1, 10),
      );
      expect(find.textContaining('Cobranza agendada para'), findsOneWidget);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('«Hoy» propone el próximo múltiplo de 5 minutos, que siempre es futuro', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaPregunta(tester);

      await elegirCuando(tester, CuandoCobrar.hoy);
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      final agenda = agendas.recibidas.single.agenda;
      expect(agenda.fechaProgramada.toLocal().minute, 45);
      expect(agenda.fechaProgramada.toLocal().hour, 14);
    });

    testWidgets('una hora de hoy que ya pasó pide confirmar; «Cambiar» vuelve a la pregunta', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.hoy);
      // 14:45 → 14:40: ya pasó (son las 14:41).
      await tocarKey(tester, const Key('agendar_hoja_menos'));
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      expect(find.byKey(const Key('agendar_hora_pasada_igual')), findsOneWidget);
      expect(agendas.recibidas, isEmpty, reason: 'el primer intento no guardó nada');
      await tocarKey(tester, const Key('agendar_hora_pasada_cambiar'));

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(agendas.guardadas, isEmpty);
    });

    testWidgets('una hora de hoy que ya pasó se puede agendar igual', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.hoy);
      await tocarKey(tester, const Key('agendar_hoja_menos'));
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      await tocarKey(tester, const Key('agendar_hora_pasada_igual'));

      expect(agendas.guardadas, hasLength(1));
      expect(find.textContaining('Cobranza agendada para'), findsOneWidget);
    });

    testWidgets('la hoja de la casa que ya estaba abierta vuelve a leer lo que la persona debe', (
      tester,
    ) async {
      final lecturas = <ClaveDeLaCasa>[];
      extras.addAll(overridesHojaCasa(lecturas: lecturas));
      await montar(tester, conMapa: true);
      const clave = (ubicacionId: 'ub-1', tipo: TipoUbicacion.casa);
      final suscripcion = contenedor(tester).listen(contextoDeLaCasaProvider(clave), (_, _) {});
      addTearDown(suscripcion.close);
      await tester.pump();
      expect(lecturas, hasLength(1));

      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);
      await tester.pump();

      expect(lecturas.length, greaterThan(1), reason: 'se pidió el contexto de nuevo (R·08)');
    });

    testWidgets('cerrar «Día y hora» sin confirmar vuelve a la pregunta', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.manana);

      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(agendas.recibidas, isEmpty);
    });

    testWidgets('si la cita no se pudo guardar, la venta sigue guardada y el aviso dice qué '
        'hacer', (tester) async {
      await montar(tester);
      await hastaLaPregunta(tester);
      agendas.fallas.add(const FailureInesperado());

      await elegirCuando(tester, CuandoCobrar.manana);
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      expect(find.text(TextosCuandoCobrar.noSePudoAgendar), findsOneWidget);
      expect(entorno.ventas.recibidas, hasLength(1));
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('si agendar lanza, tampoco se pierde la venta ni queda nada trabado', (
      tester,
    ) async {
      await montar(tester);
      await hastaLaPregunta(tester);
      agendas.lanzar = StateError('sin base');

      await elegirCuando(tester, CuandoCobrar.manana);
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      expect(find.text(TextosCuandoCobrar.noSePudoAgendar), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(devolvio, isTrue);
    });

    testWidgets('dos toques seguidos en una opción abren una sola vez «Día y hora»', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);
      await hastaLaPregunta(tester);

      final manana = find.semantics.byLabel(RegExp('^Mañana'));
      tester.semantics.performAction(manana, SemanticsAction.tap);
      tester.semantics.performAction(manana, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agendar_hoja_listo')), findsOneWidget);
      await tocarKey(tester, const Key('agendar_hoja_listo'));
      expect(agendas.recibidas, hasLength(1));
      semantica.dispose();
    });
  });

  group('27A·14 «Venta registrada: ¿y ahora?» (decisión P2 del 29/10)', () {
    Future<void> hastaVentaRegistrada(WidgetTester tester) async {
      await hastaLaVenta(tester);
      await armarLaVenta(tester);
      await registrar(tester);
    }

    void conCobro(List<ContextoDeCobroDeLaVenta> recibidos, {bool? cobra, Object? lanza}) {
      extras.add(
        cobrarDespuesDeLaVentaProvider.overrideWithValue((contexto) async {
          recibidos.add(contexto);
          if (lanza != null) throw lanza;
          return cobra ?? true;
        }),
      );
    }

    testWidgets('al guardar se monta la pantalla, antes de preguntar cuándo volver a cobrar', (
      tester,
    ) async {
      await montar(tester);

      await hastaVentaRegistrada(tester);

      expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsNothing);
      expect(
        find.text(TextosVenta.clienteYMonto('Pedro Gómez', FormatoVenta.monto(300000))),
        findsOneWidget,
      );
      expect(devolvio, isFalse);
      expect(entorno.ventas.recibidas, hasLength(1), reason: 'la venta ya está guardada');
    });

    testWidgets('sin cobro enganchado y sin entrega, no dibuja grupos: solo «Listo»', (
      tester,
    ) async {
      await montar(tester);
      await hastaVentaRegistrada(tester);

      expect(find.text(TextosVenta.cobro), findsNothing);
      expect(find.text(TextosVenta.entrega), findsNothing);
      expect(find.text(TextosVenta.cobrarAhora), findsNothing);

      await tocarKey(tester, const Key('venta_terminar'));
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
    });

    testWidgets('el atrás no sale de la pantalla: la venta ya está guardada', (tester) async {
      await montar(tester);
      await hastaVentaRegistrada(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
    });

    testWidgets('con el cobro enganchado se ofrece «Cobrar ahora»; sin elegirlo, sigue la '
        'pregunta', (tester) async {
      final cobros = <ContextoDeCobroDeLaVenta>[];
      conCobro(cobros);
      await montar(tester);
      await hastaVentaRegistrada(tester);

      expect(find.text(TextosVenta.cobrarAhora), findsOneWidget);
      await tocar(tester, find.text(TextosVenta.continuar));

      expect(cobros, isEmpty);
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
    });

    testWidgets('«Cobrar ahora» abre el cobro con la venta; si queda saldo, pregunta con lo que '
        'queda', (tester) async {
      final cobros = <ContextoDeCobroDeLaVenta>[];
      conCobro(cobros);
      extras.add(saldoPendienteRepositoryProvider.overrideWithValue(_SaldoFalso(120000)));
      await montar(tester);
      await hastaVentaRegistrada(tester);

      await tocar(tester, find.text(TextosVenta.cobrarAhora));
      await tocar(tester, find.text(TextosVenta.continuar));

      expect(cobros, hasLength(1));
      expect(cobros.single.ventaId, entorno.ventas.recibidas.single.venta.id);
      expect(cobros.single.espacioId, 'esp-1');
      expect(cobros.single.espacioPersonaId, 'ep-1');
      expect(cobros.single.colportorId, 'col-1');
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(find.text(TextosCuandoCobrar.saldo(120000, 'Pedro Gómez')), findsOneWidget);
    });

    testWidgets('si «Cobrar ahora» cobra todo, no pregunta cuándo volver a cobrar', (tester) async {
      final cobros = <ContextoDeCobroDeLaVenta>[];
      conCobro(cobros);
      extras.add(saldoPendienteRepositoryProvider.overrideWithValue(_SaldoFalso(0)));
      await montar(tester);
      await hastaVentaRegistrada(tester);

      await tocar(tester, find.text(TextosVenta.cobrarAhora));
      await tocar(tester, find.text(TextosVenta.continuar));

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsNothing);
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
      expect(agendas.recibidas, isEmpty);
    });

    testWidgets('si no se cobró, o el cobro falla, pregunta con el total y no queda nada trabado', (
      tester,
    ) async {
      final cobros = <ContextoDeCobroDeLaVenta>[];
      conCobro(cobros, lanza: StateError('sin base'));
      await montar(tester);
      await hastaVentaRegistrada(tester);

      await tocar(tester, find.text(TextosVenta.cobrarAhora));
      await tocar(tester, find.text(TextosVenta.continuar));

      expect(tester.takeException(), isNull);
      expect(find.text(TextosCuandoCobrar.saldo(300000, 'Pedro Gómez')), findsOneWidget);
      await tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));
      expect(salida, isA<VentaGuardadaEnLaEntrevista>());
    });

    testWidgets('dos toques seguidos en «Continuar» abren el cobro una sola vez', (tester) async {
      final semantica = tester.ensureSemantics();
      final cobros = <ContextoDeCobroDeLaVenta>[];
      conCobro(cobros, cobra: false);
      await montar(tester);
      await hastaVentaRegistrada(tester);

      await tocar(tester, find.text(TextosVenta.cobrarAhora));
      final continuar = find.semantics.byLabel(RegExp('^Continuar'));
      tester.semantics.performAction(continuar, SemanticsAction.tap);
      tester.semantics.performAction(continuar, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(cobros, hasLength(1));
      semantica.dispose();
    });

    testWidgets('con «Mañana» la cobranza queda marcada para la tarjeta de R·08 (con «Cambiar»)', (
      tester,
    ) async {
      await montar(tester, conMapa: true);
      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.manana);
      await tocarKey(tester, const Key('agendar_hoja_listo'));

      final cita = agendas.recibidas.single.agenda;
      final marca = contenedor(tester).read(cobranzaRecienAgendadaProvider);
      expect(marca, isNotNull);
      expect(marca!.agendaId, cita.id);
      expect(marca.ubicacionId, 'ub-1');
      expect(marca.persona, 'Pedro Gómez');
    });

    testWidgets('sin cobranza agendada («Sin fecha») no se marca nada para R·08', (tester) async {
      await montar(tester, conMapa: true);
      await hastaLaPregunta(tester);
      await elegirCuando(tester, CuandoCobrar.sinFecha);

      expect(contenedor(tester).read(cobranzaRecienAgendadaProvider), isNull);
    });
  });

  group('desde el aviso fijo del mapa', () {
    testWidgets(
      'al guardar la venta el aviso sale del árbol y el flujo sigue: agenda la cobranza',
      (tester) async {
        await montar(tester, conMapa: true);

        await hastaLaVenta(tester, desdeElAviso: true);
        await armarLaVenta(tester);
        await registrar(tester);
        expect(
          find.byKey(ClavesEntrevista.avisoFijo),
          findsNothing,
          reason: 'la entrevista se soltó: el aviso ya no está',
        );
        await elegirCuando(tester, CuandoCobrar.manana);
        await tocarKey(tester, const Key('agendar_hoja_listo'));

        expect(agendas.recibidas, hasLength(1), reason: 'la cobranza se agendó igual');
        expect(agendas.recibidas.single.agenda.tipo, TipoAgenda.cobranza);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Cobranza agendada para'), findsOneWidget);
        expect(contenedor(tester).read(mapaUbicacionesProvider('col-1')).seleccionadaId, 'ub-1');
      },
    );
  });
}
