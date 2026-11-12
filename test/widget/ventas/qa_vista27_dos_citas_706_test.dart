// QA de «Entrega cita» (vista 27C·02 «Entregas pendientes», 27C·03 «Marcar entregado» y la hoja
// «¿Qué venta?» de la ficha, HU-VEN-003, #706): una venta que creció tiene dos citas de entrega, una por
// grupo de libros. Lo que no cubren los tests del implementador: matriz de tamaños y escalas, guías de
// accesibilidad, que las dos tarjetas de la MISMA venta se distingan (a la vista y para el lector),
// fallas y reintentos sobre una sola cita, y el recorrido de la lista cuando se entrega una y otra.
// Con `--dart-define=QA_CAPTURAS=true` se guardan capturas en `.dart_tool/qa_capturas/`.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_entregar_desde_la_ficha.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista42_venta_crece_693_arnes.dart'
    show capturarPantalla693, cargarFuentes693, textosFueraDeLaPantalla693;
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

const _matriz = <({String nombre, Size tamano, double escala})>[
  (nombre: '360x640 ×1,0', tamano: Size(360, 640), escala: 1),
  (nombre: '360x640 ×2,0', tamano: Size(360, 640), escala: 2),
  (nombre: '412x915 ×1,0', tamano: Size(412, 915), escala: 1),
  (nombre: '412x915 ×2,0', tamano: Size(412, 915), escala: 2),
];

Finder get _cta => find.byKey(const Key('venta_cta'));

/// «Hoy» es miércoles 28/10 a las 12:00 (ver `ahoraDeLosTests`).
final _atrasada = DateTime(2026, 10, 26, 9);
final _sabado = DateTime(2026, 10, 31, 9);
final _martes = DateTime(2026, 11, 3, 16, 30);

/// Lo de antes de la venta 0042 (de María), con su cita.
EntregaPendiente _deAntes({DateTime? fecha}) => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-1',
  lineas: [lineaDe('e-1', 'p-salud')],
  fechaPrevista: fecha ?? _sabado,
  agendaId: 'a-1',
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

/// El libro que se le sumó, con su propia cita.
EntregaPendiente _sumado({DateTime? fecha}) => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-1',
  lineas: [lineaDe('e-2', 'p-hijos')],
  fechaPrevista: fecha ?? _martes,
  agendaId: 'a-2',
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

EntregaPendiente get _sinFecha => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-1',
  lineas: [lineaDe('e-3', 'p-salud')],
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

EntornoDeEntrega _entorno(List<EntregaPendiente> lista) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(lista);
  e.entregas.respuestaDeCumplir = cumplidaCon();
  return e;
}

/// La hoja «¿Qué venta?» de la ficha de María con las [lista] de entregas.
Future<EntornoDeEntrega> _montarHoja(
  WidgetTester tester,
  List<EntregaPendiente> lista, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = _entorno(lista)..ahora = ahoraDeLosTests;
  final personas = PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'María')]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDeEntregaDiferida(e),
        personaRepositoryProvider.overrideWithValue(personas),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir'),
                onPressed: () =>
                    FlujoEntregarDesdeLaFicha.abrir(context, personaId: 'p1', espacioId: 'esp-1'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await asentar(tester);
  return e;
}

void main() {
  group('27C·02 · «Entregas pendientes» con las dos citas de una venta', () {
    for (final c in _matriz) {
      testWidgets('${c.nombre}: dos tarjetas de la 0042 (y una sin fecha), sin desbordes', (
        tester,
      ) async {
        await cargarFuentes693(tester);
        final e = _entorno([_deAntes(fecha: _atrasada), _sumado(), _sinFecha]);
        await montarPantalla(
          tester,
          e,
          () => EntregasPendientesPage.ruta(colportorId: 'col-1'),
          escala: c.escala,
          tamano: c.tamano,
        );

        expect(tester.takeException(), isNull);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        await capturarPantalla693(
          tester,
          '706_27C02_dos_citas_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );
      });
    }

    testWidgets('las dos tarjetas de la misma venta se distinguen para el lector', (tester) async {
      final handle = tester.ensureSemantics();
      final e = _entorno([_deAntes(), _sumado()]);
      await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

      final salud = tester.getSemantics(find.textContaining('Salud y Hogar').first);
      final hijos = tester.getSemantics(find.textContaining('Nuestros Hijos').first);

      // Cada tarjeta dice sus libros (lo único que las separa): no se funden en una.
      expect(salud.label, contains('Salud y Hogar'));
      expect(salud.label, isNot(contains('Nuestros Hijos')));
      expect(hijos.label, contains('Nuestros Hijos'));
      expect(hijos.label, isNot(contains('Salud y Hogar')));
      handle.dispose();
    });

    testWidgets('las dos tarjetas de la misma venta dicen cada una su fecha', (tester) async {
      final e = _entorno([_deAntes(), _sumado()]);
      await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

      // Sáb 31/10 y mar 03/11: las dos fechas a la vista, una por tarjeta.
      expect(find.textContaining('31/10'), findsOneWidget);
      expect(find.textContaining('03/11'), findsOneWidget);
    });

    testWidgets(
      'al entregar una cita, la lista sigue con la otra; al entregar la otra, queda vacía',
      (tester) async {
        final e = _entorno([_deAntes(), _sumado()]);
        await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

        e.entregas.emitirPendientes([_sumado()]);
        await asentar(tester);
        expect(find.textContaining('Salud y Hogar'), findsNothing);
        expect(find.textContaining('Nuestros Hijos'), findsOneWidget);

        e.entregas.emitirPendientes(const []);
        await asentar(tester);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Nuestros Hijos'), findsNothing);
        expect(find.byKey(const Key('entregas_pagina')), findsOneWidget);
      },
    );

    testWidgets('error al leer y reintentar: la lista vuelve con las dos citas', (tester) async {
      final e = _entorno([_deAntes(), _sumado()]);
      e.entregas.errorDePendientes = StateError('lectura');
      await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

      expect(find.textContaining('No pudimos leer'), findsWidgets);
      e.entregas.errorDePendientes = null;
      await tocar(tester, find.text('Reintentar'));

      expect(find.textContaining('Salud y Hogar'), findsOneWidget);
      expect(find.textContaining('Nuestros Hijos'), findsOneWidget);
    });
  });

  group('27C·03 · «Marcar entregado» de una de las dos citas', () {
    for (final c in _matriz) {
      for (final cual in const ['antes', 'sumado']) {
        testWidgets('${c.nombre}: la cita $cual, sin desbordes', (tester) async {
          await cargarFuentes693(tester);
          final e = _entorno([_deAntes(), _sumado()]);
          final elegida = cual == 'antes' ? _deAntes() : _sumado();
          await montarPantalla(
            tester,
            e,
            () => MarcarEntregadoPage.rutaDe(CualEntrega.de(elegida)),
            escala: c.escala,
            tamano: c.tamano,
          );

          expect(tester.takeException(), isNull);
          expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
          expect(find.byKey(const Key('marcar_pagina')), findsOneWidget);
          await capturarPantalla693(
            tester,
            '706_27C03_${cual}_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
          );
        });
      }
    }

    testWidgets('si falla a mitad, el botón vuelve y el reintento sigue siendo de ESA cita', (
      tester,
    ) async {
      final e = _entorno([_deAntes(), _sumado()]);
      e.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
      final salida = await montarPantalla(
        tester,
        e,
        () => MarcarEntregadoPage.rutaDe(CualEntrega.de(_sumado())),
      );

      await tocar(tester, _cta);
      expect(salida.cerrada, isFalse);
      expect(tester.widget<FilledButton>(_cta).onPressed, isNotNull);

      await tocar(tester, _cta);

      expect(e.entregas.cumplidas, hasLength(2));
      expect(
        [for (final c in e.entregas.cumplidas) c.entregaIds],
        [
          {'e-2'},
          {'e-2'},
        ],
      );
      expect(salida.cerrada, isTrue);
    });

    testWidgets(
      'si la cita ya se entregó mientras la pantalla estaba abierta, no entrega la otra',
      (tester) async {
        final e = _entorno([_deAntes(), _sumado()]);
        await montarPantalla(
          tester,
          e,
          () => MarcarEntregadoPage.rutaDe(CualEntrega.de(_sumado())),
        );

        // La cita sumada se entregó desde otro lado (la Agenda): ya no está entre las pendientes.
        e.entregas.emitirPendientes([_deAntes()]);
        await asentar(tester);

        expect(tester.takeException(), isNull);
        // Lo que quede en pantalla no puede ofrecer entregar lo de la otra cita como si fuera esta.
        if (find.byKey(const Key('venta_cta')).evaluate().isNotEmpty) {
          await tocar(tester, _cta);
          for (final c in e.entregas.cumplidas) {
            expect(c.entregaIds, isNot(contains('e-1')));
          }
        }
      },
    );
  });

  group('32B · la hoja «¿Qué venta?» de la ficha con las dos citas de una venta', () {
    for (final c in _matriz) {
      testWidgets('${c.nombre}: las dos citas y otra venta, sin desbordes', (tester) async {
        await cargarFuentes693(tester);
        await _montarHoja(
          tester,
          [_deAntes(), _sumado(), pendienteDe('v-9', fecha: _sabado, talonario: '0031')],
          tamano: c.tamano,
          escala: c.escala,
        );

        expect(tester.takeException(), isNull);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        expect(find.byKey(const ValueKey('que_entrega_v-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('que_entrega_v-1_1')), findsOneWidget);
        await capturarPantalla693(
          tester,
          '706_32B_que_venta_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );
      });
    }

    testWidgets('las dos filas de la misma venta se distinguen para el lector', (tester) async {
      final handle = tester.ensureSemantics();
      await _montarHoja(tester, [_deAntes(), _sumado()]);

      final a = tester.getSemantics(find.text('Salud y Hogar × 1'));
      final b = tester.getSemantics(find.text('Nuestros Hijos × 1'));

      expect(a.label, isNot(b.label));
      expect(a.label, contains('31/10'));
      expect(b.label, contains('03/11'));
      handle.dispose();
    });

    testWidgets('con muchas entregas de la misma venta (cinco citas) no repite claves ni rompe', (
      tester,
    ) async {
      EntregaPendiente cita(int n) => EntregaPendiente(
        ventaId: 'v-1',
        espacioPersonaId: 'ep-1',
        lineas: [lineaDe('e-$n', 'p-salud')],
        fechaPrevista: _sabado.add(Duration(days: n)),
        agendaId: 'a-$n',
        espacioId: 'esp-1',
        numeroTalonario: '0042',
      );
      await _montarHoja(tester, [
        for (var i = 0; i < 5; i++) cita(i),
      ], tamano: const Size(360, 640));

      expect(tester.takeException(), isNull);
      for (var i = 0; i < 5; i++) {
        final clave = i == 0 ? 'que_entrega_v-1' : 'que_entrega_v-1_$i';
        await tester.scrollUntilVisible(find.byKey(ValueKey(clave)), 80, maxScrolls: 30);
        expect(find.byKey(ValueKey(clave)), findsOneWidget);
      }
    });
  });
}
