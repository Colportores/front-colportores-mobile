// «¿Cuándo volvés a cobrar?» (decisión de Cristian, 23/10, «Agenda cobro»; #428): la hoja sola, sin
// la entrevista. El recorrido completo, con la venta de verdad, está en
// `agenda/flujo_entrevista_venta_428_test.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_cuando_cobrar.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_cuando_cobrar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/venta_falsos.dart';

void main() {
  CuandoCobrar? elegida;
  bool? agendo;
  late AgendaRepositorioQueAgenda agendas;

  setUp(() {
    elegida = null;
    agendo = null;
    agendas = AgendaRepositorioQueAgenda();
  });

  VentaGuardada guardada(int centavos) => VentaGuardada(
    venta: ventaDe('v-1', monto: centavos),
    items: [itemDe('i-1', 'v-1')],
  );

  Future<void> montarHoja(
    WidgetTester tester, {
    int saldo = 120000,
    String persona = 'Pedro Gómez',
    double escala = 1,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => elegida = await mostrarHojaCuandoCobrar(
                context,
                saldoCentavos: saldo,
                persona: persona,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  group('la hoja', () {
    testWidgets('muestra el saldo, a quién y las cuatro salidas', (tester) async {
      await montarHoja(tester);

      expect(find.text('¿Cuándo volvés a cobrar?'), findsOneWidget);
      expect(find.text(r'Quedan $ 1.200 por cobrar a Pedro Gómez.'), findsOneWidget);
      for (final texto in ['Hoy', 'Mañana', 'Otro día', 'Sin fecha']) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
    });

    testWidgets('sin nombre el saldo no queda con «a »', (tester) async {
      await montarHoja(tester, persona: '  ');

      expect(find.text(r'Quedan $ 1.200 por cobrar.'), findsOneWidget);
    });

    for (final o in CuandoCobrar.values) {
      testWidgets('tocar «${o.name}» devuelve esa opción', (tester) async {
        await montarHoja(tester);

        await tester.tap(find.byKey(ClavesCuandoCobrar.opcion(o)));
        await tester.pumpAndSettle();

        expect(elegida, o);
        expect(find.byKey(ClavesCuandoCobrar.hoja), findsNothing);
      });
    }

    testWidgets('cerrarla por afuera o con atrás no la cierra', (tester) async {
      await montarHoja(tester);

      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(elegida, isNull);
    });

    testWidgets('cada opción es un botón de al menos 48 dp, con etiqueta y con contraste', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarHoja(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel(RegExp('^Sin fecha')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dos opciones casi a la vez devuelven solo la primera', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarHoja(tester);

      tester.semantics.performAction(find.semantics.byLabel(RegExp('^Hoy')), SemanticsAction.tap);
      tester.semantics.performAction(
        find.semantics.byLabel(RegExp('^Sin fecha')),
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();

      expect(elegida, CuandoCobrar.hoy);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    for (final tamano in [const Size(320, 568), const Size(412, 915)]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'con un nombre larguísimo a ${tamano.width.toInt()}×${tamano.height.toInt()} y letra '
          '$escala no desborda y llega a todas las opciones',
          (tester) async {
            await montarHoja(
              tester,
              persona: 'María de los Ángeles Fernández de la Cruz y Sotomayor Echeverría',
              saldo: 999999999,
              escala: escala,
              tamano: tamano,
            );

            expect(tester.takeException(), isNull);
            for (final o in CuandoCobrar.values) {
              await tester.ensureVisible(find.byKey(ClavesCuandoCobrar.opcion(o)));
              expect(find.byKey(ClavesCuandoCobrar.opcion(o)), findsOneWidget);
            }
          },
        );
      }
    }
  });

  group('el flujo', () {
    Future<void> montarFlujo(WidgetTester tester, VentaGuardada venta) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var n = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agendaRepositoryProvider.overrideWithValue(agendas),
            generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
            relojVisitaProvider.overrideWithValue(() => DateTime(2026, 10, 23, 14, 35)),
            ...Telefono().overrides,
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async => agendo = await FlujoCuandoCobrar.preguntar(
                    context,
                    ref,
                    guardada: venta,
                    espacioId: 'esp-1',
                    espacioPersonaId: 'ep-1',
                    colportorId: 'col-1',
                    persona: 'Pedro',
                    direccion: 'Grecia 3307',
                  ),
                  child: const Text('preguntar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('preguntar'));
      await tester.pumpAndSettle();
    }

    testWidgets('una venta que no deja saldo no pregunta nada', (tester) async {
      await montarFlujo(tester, guardada(0));

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsNothing);
      expect(agendo, isFalse);
      expect(agendas.recibidas, isEmpty);
    });

    testWidgets('«Sin fecha» devuelve false y no agenda', (tester) async {
      await montarFlujo(tester, guardada(150000));

      await tester.tap(find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
      await tester.pumpAndSettle();

      expect(agendo, isFalse);
      expect(agendas.recibidas, isEmpty);
    });

    testWidgets('«Mañana» agenda una cobranza y devuelve true', (tester) async {
      await montarFlujo(tester, guardada(150000));

      await tester.tap(find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agendar_hoja_listo')));
      await tester.pumpAndSettle();

      expect(agendo, isTrue);
      expect(agendas.guardadas, hasLength(1));
      expect(find.textContaining('Cobranza agendada para'), findsOneWidget);
    });

    testWidgets('«Otro día» abre el calendario y agenda el día elegido', (tester) async {
      await montarFlujo(tester, guardada(150000));

      await tester.tap(find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.otroDia)));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agendar_hoja_listo')));
      await tester.pumpAndSettle();

      expect(agendo, isTrue);
      final dia = agendas.recibidas.single.agenda.fechaProgramada.toLocal();
      expect(dia.day, 25);
    });

    testWidgets('cancelar el calendario vuelve a la pregunta', (tester) async {
      await montarFlujo(tester, guardada(150000));

      await tester.tap(find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.otroDia)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(agendas.recibidas, isEmpty);
    });
  });
}
