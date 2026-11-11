// «Cobranza» de «¿Qué pasó?» (vista 39, C·06) con el flujo real de «$ Cobrar» (#440): la opción lleva a
// «¿Qué venta?» (C·08) y al cobro en efectivo (vista 28), y solo si se cobró la visita queda guardada
// como «Cobranza» (decisión P4 de #411: la guarda `FlujoRegistrarVisita`, no el cobro).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/flujo_cobrar_desde_la_casa.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/dialogo_no_te_pago.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/campo_falsos.dart' show agendaDe;
import '../../helpers/cobrar_desde_la_casa_arnes.dart';
import '../../helpers/cobro_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/persona_falsos.dart';
import '../mapa/hoja_con_quien_arnes.dart' show SaldosFalsos;
import '../mapa/personas_arnes.dart' show asentar;
import '../mapa/registrar_visita_arnes.dart' show casaGrecia;

const _noPudimosGuardar = 'No pudimos guardar la visita. Probá de nuevo.';

final _pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');

Finder get _hoja => find.byKey(ClavesQuePaso.hoja);

final class _Montaje {
  _Montaje(this.cobros, this.agenda);

  final CobranzasQueLeen cobros;
  final AgendaRepositorioFalso agenda;
  final resultados = <bool>[];
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  required CobranzasQueLeen cobros,
  AgendaRepositorioFalso? agenda,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final navegador = GlobalKey<NavigatorState>();
  final montaje = _Montaje(cobros, agenda ?? AgendaRepositorioFalso());
  final telefono = Telefono();
  var n = 0;
  var ids = 0;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(montaje.agenda),
        generadorIdVisitaProvider.overrideWithValue(() => 'visita-${++n}'),
        relojVisitaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 25, 15)),
        cobranzaRepositoryProvider.overrideWithValue(cobros),
        generadorIdCobroProvider.overrideWithValue(() => 'cobro-${++ids}'),
        relojCobroProvider.overrideWithValue(() => hoyDelCobro),
        ...telefono.overrides,
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()..sembrar([_pedro])),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaGrecia())),
        saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'pedro': 120000})),
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        cobrarDesdeLaCasaProvider.overrideWith(
          (ref) =>
              (datos) => FlujoCobrarDesdeLaCasa.abrir(
                navegador.currentContext!,
                datos,
                colportorId: 'col-1',
              ),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorKey: navegador,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => montaje.resultados.add(
                  await FlujoRegistrarVisita.abrir(context, (
                    ubicacionId: 'ub-1',
                    espacioId: 'esp-1',
                    agendaId: null,
                  ), colportorId: 'col-1'),
                ),
                child: const Text('registrar visita'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('registrar visita'));
  await asentar(tester);
  return montaje;
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await asentar(tester);
}

Future<void> _cobrarMonto(WidgetTester tester, String monto) async {
  await escribirMonto(tester, monto);
  await tocarCobro(tester, botonRegistrar);
}

Finder get _cobranza => find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.cobranza));

void main() {
  group('«Cobranza» → «¿Qué venta?» → cobro', () {
    testWidgets('con varias ventas: se elige, se cobra y la visita queda como «Cobranza»', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        cobros: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await _tocar(tester, _cobranza);
      expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
      await _tocar(tester, find.byKey(ClavesQueVenta.fila('v-45')));
      await _tocar(tester, find.byKey(ClavesQueVenta.cobrar));
      await _cobrarMonto(tester, '240');
      await tocarCobro(tester, find.text('Volver al mapa'));
      await asentar(tester);

      expect(m.cobros.base.recibidos.single.ventaId, 'v-45');
      final registrada = m.agenda.recibidas.single;
      expect(registrada.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(registrada.visita.espacioPersonaId, 'ep-pedro');
      expect(registrada.agendaId, isNull);
      expect(m.resultados, [true]);
      expect(_hoja, findsNothing);
    });

    testWidgets('con una sola venta: salta C·08, abre el cobro y guarda la visita al cobrar', (
      tester,
    ) async {
      final m = await _montar(tester, cobros: cobranzasConVentas([ventaDelCanvas38()]));

      await _tocar(tester, _cobranza);

      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
      expect(pagina, findsOneWidget);
      await _cobrarMonto(tester, '600');
      await tocarCobro(tester, find.text('Listo'));
      await asentar(tester);

      expect(m.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(m.resultados, [true]);
    });

    testWidgets(
      '«Cancelar» en C·08 y «No, me equivoqué»: ninguna visita, ningún cobro y «¿Qué pasó?» sigue '
      'abierta',
      (tester) async {
        final m = await _montar(
          tester,
          cobros: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        );

        await _tocar(tester, _cobranza);
        await _tocar(tester, find.byKey(ClavesQueVenta.cancelar));
        // La decisión del 03/11: antes de volver se pregunta, y todavía no se escribió nada.
        expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
        expect(m.agenda.recibidas, isEmpty);
        await _tocar(tester, find.byKey(ClavesNoTePago.noMeEquivoque));

        expect(m.agenda.recibidas, isEmpty);
        expect(m.cobros.base.recibidos, isEmpty);
        expect(_hoja, findsOneWidget);
        expect(m.resultados, isEmpty);
        // Volvió a «¿Qué pasó?» y la opción no quedó trabada.
        await _tocar(tester, _cobranza);
        expect(find.byKey(ClavesQueVenta.lista), findsOneWidget);
      },
    );

    testWidgets(
      '«Cancelar» en C·08 y «Sí, anotar la visita»: queda UNA visita «Cobranza» sin cobro y sin '
      'agenda, «¿Qué pasó?» se resuelve y no hay un «Guardado» con «Deshacer»',
      (tester) async {
        final agenda = AgendaRepositorioFalso()
          ..programada = agendaDe('cita-1', tipo: TipoAgenda.cobranza);
        final m = await _montar(
          tester,
          cobros: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
          agenda: agenda,
        );

        await _tocar(tester, _cobranza);
        await _tocar(tester, find.byKey(ClavesQueVenta.cancelar));
        await _tocar(tester, find.byKey(ClavesNoTePago.anotar));

        final registrada = m.agenda.recibidas.single;
        expect(registrada.visita.tipoResultado, TipoResultadoVisita.cobranza);
        expect(registrada.visita.espacioPersonaId, 'ep-pedro');
        expect(registrada.agendaId, isNull, reason: 'la cita de cobranza no se toca');
        expect(agenda.programada!.estado, EstadoAgenda.programada);
        expect(m.cobros.base.recibidos, isEmpty);
        expect(m.resultados, [true]);
        expect(_hoja, findsNothing);
        expect(find.text('Anotamos la visita de cobranza.'), findsOneWidget);
        expect(find.text('Deshacer'), findsNothing);
      },
    );

    testWidgets(
      '«Sí, anotar la visita» y falla el guardado: «¿Qué pasó?» sigue abierta sin visita; el '
      'reintento guarda una sola',
      (tester) async {
        final agenda = AgendaRepositorioFalso()
          ..resultados.add(const FailureInesperado(causa: 'StateError'));
        final m = await _montar(
          tester,
          cobros: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
          agenda: agenda,
        );
        await _tocar(tester, _cobranza);
        await _tocar(tester, find.byKey(ClavesQueVenta.cancelar));

        await _tocar(tester, find.byKey(ClavesNoTePago.anotar));
        expect(find.text(_noPudimosGuardar), findsOneWidget);
        expect(m.resultados, isEmpty);

        await _tocar(tester, find.byKey(ClavesNoTePago.anotar));

        expect(m.agenda.recibidas.map((r) => r.visita.id), ['visita-1', 'visita-1']);
        expect(m.resultados, [true]);
        expect(_hoja, findsNothing);
      },
    );

    testWidgets(
      'una sola venta, «✕» del cobro sin cobrar y «No, me equivoqué»: no se guarda la visita y se '
      'puede elegir otra opción',
      (tester) async {
        final m = await _montar(tester, cobros: cobranzasConVentas([ventaDelCanvas38()]));

        await _tocar(tester, _cobranza);
        await tocarCobro(tester, cerrarCobro);
        // Decisión del 10/11 (P2 de #440): con una sola venta, «✕» es el «Cancelar» y pregunta.
        expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
        expect(m.agenda.recibidas, isEmpty);
        await _tocar(tester, find.byKey(ClavesNoTePago.noMeEquivoque));

        expect(m.agenda.recibidas, isEmpty);
        expect(m.cobros.base.recibidos, isEmpty);
        expect(m.resultados, isEmpty);
        expect(_hoja, findsOneWidget);
        // La opción no quedó trabada: se puede volver a tocar.
        await _tocar(tester, _cobranza);
        expect(pagina, findsOneWidget);
      },
    );

    testWidgets(
      'una sola venta, «✕» del cobro sin cobrar y «Sí, anotar la visita»: UNA visita «Cobranza» sin '
      'cobro ni agenda, «¿Qué pasó?» se resuelve y no la guarda otra vez',
      (tester) async {
        final agenda = AgendaRepositorioFalso()
          ..programada = agendaDe('cita-1', tipo: TipoAgenda.cobranza);
        final m = await _montar(
          tester,
          cobros: cobranzasConVentas([ventaDelCanvas38()]),
          agenda: agenda,
        );

        await _tocar(tester, _cobranza);
        expect(find.byKey(ClavesQueVenta.lista), findsNothing, reason: 'C·08 se salta');
        await tocarCobro(tester, cerrarCobro);
        await _tocar(tester, find.byKey(ClavesNoTePago.anotar));

        final registrada = m.agenda.recibidas.single;
        expect(registrada.visita.tipoResultado, TipoResultadoVisita.cobranza);
        expect(registrada.visita.espacioPersonaId, 'ep-pedro');
        expect(registrada.agendaId, isNull, reason: 'la cita de cobranza no se toca');
        expect(agenda.programada!.estado, EstadoAgenda.programada);
        expect(m.cobros.base.recibidos, isEmpty);
        expect(m.resultados, [true]);
        expect(_hoja, findsNothing);
        expect(pagina, findsNothing);
        expect(find.text('Anotamos la visita de cobranza.'), findsOneWidget);
      },
    );

    testWidgets(
      'una sola venta, cobro parcial y atrás del sistema: sin pregunta y UNA sola visita «Cobranza»',
      (tester) async {
        final m = await _montar(tester, cobros: cobranzasConVentas([ventaDelCanvas38()]));

        await _tocar(tester, _cobranza);
        await _cobrarMonto(tester, '600');
        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.byType(DialogoNoTePago), findsNothing);
        expect(m.cobros.base.recibidos, hasLength(1));
        expect(m.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
        expect(m.resultados, [true]);
      },
    );

    testWidgets(
      'el cobro sale bien y el guardado de la visita falla: el reintento no cobra de nuevo',
      (tester) async {
        final agenda = AgendaRepositorioFalso()
          ..resultados.add(const FailureInesperado(causa: 'StateError'));
        final m = await _montar(
          tester,
          cobros: cobranzasConVentas([ventaDelCanvas38()]),
          agenda: agenda,
        );

        await _tocar(tester, _cobranza);
        await _cobrarMonto(tester, '600');
        await tocarCobro(tester, find.text('Listo'));
        await asentar(tester);

        expect(find.text(_noPudimosGuardar), findsOneWidget);
        expect(m.cobros.base.recibidos, hasLength(1));

        await _tocar(tester, _cobranza);

        expect(m.cobros.base.recibidos, hasLength(1), reason: 'el cobro ya estaba hecho');
        expect(pagina, findsNothing);
        expect(m.agenda.recibidas.map((r) => r.visita.id), ['visita-1', 'visita-1']);
        expect(m.resultados, [true]);
      },
    );

    testWidgets(
      'no se pueden leer las ventas: el aviso de C·08 con «Reintentar» y sigue el flujo',
      (tester) async {
        final cobros = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
          ..fallas.add(const FailureInesperado(causa: 'x'));
        final m = await _montar(tester, cobros: cobros);

        await _tocar(tester, _cobranza);
        expect(find.byKey(ClavesQueVenta.error), findsOneWidget);
        await _tocar(tester, find.byKey(ClavesQueVenta.reintentar));
        await _tocar(tester, find.byKey(ClavesQueVenta.cobrar));

        expect(pagina, findsOneWidget);
        expect(m.agenda.recibidas, isEmpty);
      },
    );

    testWidgets('dos toques seguidos en «Cobranza» abren una sola vez C·08', (tester) async {
      await _montar(tester, cobros: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]));

      await tester.tap(_cobranza);
      await tester.tap(_cobranza, warnIfMissed: false);
      await asentar(tester);

      expect(find.byKey(ClavesQueVenta.lista), findsOneWidget);
    });

    testWidgets('textScaler 2.0 en 320×568: de «Cobranza» al cobro y a guardar la visita', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        cobros: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        escala: 2,
        tamano: const Size(320, 568),
      );

      await _tocar(tester, _cobranza);
      await _tocar(tester, find.byKey(ClavesQueVenta.cobrar));
      await _cobrarMonto(tester, '1200');
      await tocarCobro(tester, find.text('Volver al mapa'));
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(m.resultados, [true]);
    });
  });
}
