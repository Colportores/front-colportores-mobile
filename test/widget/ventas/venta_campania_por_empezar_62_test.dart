// «Cuenta antes» (HU-AUTH-008, #62; decisión de Cristian del 23/10): con la campaña por empezar la
// cuenta es activa pero no se vende hasta ese día. La venta no se abre, el aviso dice cuándo empieza
// y no se guarda nada; con la campaña en curso, o sin saber cuál es, todo sigue como siempre.
//
// Las dos entradas a la venta: «¿A quién le vendés?» (pestaña Ventas, `venderDesdeVentas`) y «Sumar un
// libro» a una venta abierta (`sumarALaVenta`). Casos límite: doble toque, dos intentos seguidos, el día
// que empieza la campaña, la lectura que falla y volver y reentrar.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_venta_que_crece.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/campanias_inscriptas_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/elegir_persona_para_vender_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/personas_para_vender_falsos.dart';
import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

/// Viernes 20/11/2026, 12:00 en Montevideo (15:00 UTC).
final _ahora = DateTime.utc(2026, 11, 20, 15);

const _verano = CampaniaInscripta(
  campaniaId: 'camp-verano',
  nombre: 'Verano 2027',
  fechaInicio: '2026-12-01',
  fechaFin: '2027-02-28',
);

const _primavera = CampaniaInscripta(
  campaniaId: 'camp-primavera',
  nombre: 'Primavera 2026',
  fechaInicio: '2026-09-01',
  fechaFin: '2026-12-15',
);

const _textoVerano =
    'Tu campaña Verano 2027 empieza el 01/12. Hasta entonces podés bajar el mapa y las casas; '
    'la jornada y las ventas se habilitan ese día.';

final _venta39 = VentaAbierta(
  ventaId: 'v-39',
  espacioPersonaId: 'ep-1',
  numeroTalonario: '0039',
  fecha: DateTime.utc(2026, 10, 23, 15),
  montoTotalCentavos: 120000,
  cobradoCentavos: 40000,
  entregada: true,
  descripcion: 'Colección de 1 libro',
);

final class _Mundo {
  _Mundo({List<CampaniaInscripta>? campanias})
    : replica = CampaniasInscriptasEnMemoria(campanias),
      lector = LectorDePersonasParaVenderFalso([
        personaParaVender('1', nombre: 'Ana', apellido: 'Zapata'),
        personaParaVender('2', nombre: 'Beatriz', apellido: 'Álvarez'),
      ]);

  final CampaniasInscriptasEnMemoria replica;
  final LectorDePersonasParaVenderFalso lector;
  final entorno = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [_venta39]));
  final agendas = AgendaRepositorioQueAgenda();
  DateTime ahora = _ahora;
  final salidas = <Object?>[];
}

Future<void> _montar(WidgetTester tester, _Mundo m, {double escala = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...m.entorno.overrides,
        lectorDePersonasParaVenderProvider.overrideWithValue(m.lector),
        agendaRepositoryProvider.overrideWithValue(m.agendas),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => DateTime(2026, 11, 20, 14, 35)),
        relojCampaniaProvider.overrideWithValue(() => m.ahora),
        campaniasInscriptasDataSourceProvider.overrideWithValue(m.replica),
        ...Telefono().overrides,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  key: const Key('abrir_elegir'),
                  onPressed: () => unawaited(
                    Navigator.of(
                      context,
                    ).push(ElegirPersonaParaVenderPage.ruta(colportorId: 'col-1')),
                  ),
                  child: const Text('abrir'),
                ),
                TextButton(
                  key: const Key('abrir_sumar'),
                  onPressed: () async => m.salidas.add(
                    await FlujoVentaQueCrece.abrir(context, (
                      ubicacionId: 'ub-1',
                      espacioId: 'esp-1',
                      personaId: 'per-1',
                    ), colportorId: 'col-1'),
                  ),
                  child: const Text('sumar'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await asentar(tester);
}

Finder get _snack => find.byKey(const Key('campania_por_empezar_aviso'));
Finder get _formularioDeVenta => find.byKey(const Key('venta_talonario'));
Finder _fila(String id) => find.byKey(Key('persona_para_vender_ep-$id'));

Future<void> _abrirElegir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_elegir')));
  await asentar(tester);
}

void main() {
  group('«¿A quién le vendés?» con la campaña por empezar', () {
    testWidgets('tocar una persona no abre la venta: avisa cuándo empieza y la lista sigue donde '
        'estaba', (tester) async {
      final m = _Mundo(campanias: [_verano]);
      await _montar(tester, m);
      await _abrirElegir(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(find.descendant(of: _snack, matching: find.text(_textoVerano)), findsOneWidget);
      expect(_formularioDeVenta, findsNothing);
      expect(_fila('1'), findsOneWidget);
      expect(_fila('2'), findsOneWidget);
      expect(m.entorno.ventas.recibidas, isEmpty);
    });

    testWidgets('doble toque: un solo aviso y la lista sigue sin trabarse', (tester) async {
      final m = _Mundo(campanias: [_verano]);
      await _montar(tester, m);
      await _abrirElegir(tester);

      await tester.tap(_fila('1'));
      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(_snack, findsOneWidget);
      expect(_formularioDeVenta, findsNothing);
      // Otra persona se puede tocar enseguida: nada quedó «ocupado».
      await tester.tap(_fila('2'));
      await asentar(tester);
      expect(_snack, findsOneWidget);
    });

    testWidgets('el día que empieza la campaña la venta se abre, sin reiniciar nada', (
      tester,
    ) async {
      final m = _Mundo(campanias: [_verano]);
      await _montar(tester, m);
      await _abrirElegir(tester);
      await tester.tap(_fila('1'));
      await asentar(tester);
      expect(_formularioDeVenta, findsNothing);

      m.ahora = DateTime.utc(2026, 12, 1, 4);
      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(_formularioDeVenta, findsOneWidget);
    });

    testWidgets('volver atrás y reentrar: sigue frenando', (tester) async {
      final m = _Mundo(campanias: [_verano]);
      await _montar(tester, m);
      await _abrirElegir(tester);
      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);

      await _abrirElegir(tester);
      await tester.tap(_fila('2'));
      await asentar(tester);

      expect(_snack, findsOneWidget);
      expect(_formularioDeVenta, findsNothing);
    });

    testWidgets('con letra al 200 % el aviso se lee y no desborda', (tester) async {
      final m = _Mundo(campanias: [_verano]);
      await _montar(tester, m, escala: 2);
      await _abrirElegir(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(_snack, findsOneWidget);
    });
  });

  group('«¿A quién le vendés?» sin nada que frene', () {
    testWidgets('con una campaña en curso (y otra por empezar) la venta se abre', (tester) async {
      final m = _Mundo(campanias: [_primavera, _verano]);
      await _montar(tester, m);
      await _abrirElegir(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(_formularioDeVenta, findsOneWidget);
      expect(_snack, findsNothing);
    });

    testWidgets('sin saber cuál es la campaña (el pull no la trajo) no se frena', (tester) async {
      final m = _Mundo(campanias: null);
      await _montar(tester, m);
      await _abrirElegir(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(_formularioDeVenta, findsOneWidget);
    });

    testWidgets('si leer la réplica falla no se frena (el servidor lo respalda)', (tester) async {
      final m = _Mundo()..replica.falla = StateError('lectura rota');
      await _montar(tester, m);
      await _abrirElegir(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(_formularioDeVenta, findsOneWidget);
    });
  });

  group('«Sumar un libro» con la campaña por empezar', () {
    testWidgets('no abre la venta que crece: avisa cuándo empieza, no suma nada y devuelve false', (
      tester,
    ) async {
      final m = _Mundo(campanias: [_verano]);
      await _montar(tester, m);

      await tester.tap(find.byKey(const Key('abrir_sumar')));
      await asentar(tester);

      expect(find.descendant(of: _snack, matching: find.text(_textoVerano)), findsOneWidget);
      expect(find.text('VENTA 0039 · SUMAR UN LIBRO'), findsNothing);
      expect(m.salidas.single, isFalse);
      expect(m.entorno.crece.sumas, isEmpty);
    });

    testWidgets('con la campaña en curso abre la venta que crece como siempre', (tester) async {
      final m = _Mundo(campanias: [_primavera]);
      await _montar(tester, m);

      await tester.tap(find.byKey(const Key('abrir_sumar')));
      await asentar(tester);

      expect(find.text('VENTA 0039 · SUMAR UN LIBRO'), findsOneWidget);
      expect(_snack, findsNothing);
    });
  });
}
