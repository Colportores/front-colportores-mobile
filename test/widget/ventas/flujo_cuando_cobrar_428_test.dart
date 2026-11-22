// «¿Cuándo volvés a cobrar?» (vista 42, 42B·01B y 42B·01C; decisión de Cristian, 23/10, «Agenda
// cobro»; #428, #432): la pantalla sola y el flujo que agenda, sin la entrevista. El recorrido completo,
// con la venta de verdad, está en `agenda/flujo_entrevista_venta_428_test.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/ventas/presentation/flujo_cuando_cobrar.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/cuando_cobrar_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_venta.dart'
    show BotonDeVenta;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;

void main() {
  EleccionCuandoCobrar? elegida;
  CobranzaDeLaVenta? quedo;
  late AgendaRepositorioQueAgenda agendas;

  // Viernes 23/10/2026, 14:35.
  final ahora = DateTime(2026, 10, 23, 14, 35);

  setUp(() {
    elegida = null;
    quedo = null;
    agendas = AgendaRepositorioQueAgenda();
  });

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  bool guardarPrendido(WidgetTester tester) =>
      tester.widget<BotonDeVenta>(find.byKey(ClavesCuandoCobrar.guardar)).alPresionar != null;

  Future<void> montarPagina(
    WidgetTester tester, {
    int saldo = 80000,
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
              onPressed: () async => elegida = await CuandoCobrarPage.abrir(
                context,
                numeroTalonario: '0039',
                persona: persona,
                saldoCentavos: saldo,
                reloj: () => ahora,
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

  group('42B·01B: la pregunta', () {
    testWidgets('dice la venta, a quién y el saldo, y las cuatro opciones con sus ayudas', (
      tester,
    ) async {
      await montarPagina(tester);

      expect(find.text('VENTA 0039'), findsOneWidget);
      expect(find.text('¿Cuándo volvés a cobrar?'), findsOneWidget);
      expect(find.text(r'Pedro Gómez · saldo $ 800'), findsOneWidget);
      expect(find.text('Más tarde, en esta misma salida'), findsOneWidget);
      expect(find.text('Sábado 24/10'), findsOneWidget, reason: 'mañana, con su día');
      expect(find.text('Elegís el día y la hora'), findsOneWidget);
      expect(find.text('Queda en tus cobranzas, sin día ni aviso'), findsOneWidget);
      expect(guardarPrendido(tester), isFalse, reason: '«Guardar» se prende al elegir');
    });

    testWidgets('«Sin fecha» prende «Guardar» y lo devuelve sin fecha', (tester) async {
      await montarPagina(tester);

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
      expect(guardarPrendido(tester), isTrue);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

      expect(elegida, (opcion: CuandoCobrar.sinFecha, fecha: null));
    });

    testWidgets('atrás sin elegir es «Sin fecha»', (tester) async {
      await montarPagina(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
      expect(elegida?.opcion, CuandoCobrar.sinFecha);
    });

    testWidgets('«Mañana» pide solo la hora (el día ya está) y la muestra en la opción', (
      tester,
    ) async {
      await montarPagina(tester);

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
      expect(find.text('Hora'), findsWidgets, reason: 'el título de la hoja');
      expect(find.byKey(ClavesAgendarVisita.hojaDiaFijo), findsOneWidget);
      expect(find.byKey(ClavesAgendarVisita.dia(0)), findsNothing);
      await tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));

      expect(find.text('Sábado 24/10 · 10:00'), findsOneWidget);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
      expect(elegida, (opcion: CuandoCobrar.manana, fecha: DateTime(2026, 10, 24, 10)));
    });

    testWidgets('«Hoy» propone el próximo múltiplo de 5 minutos', (tester) async {
      await montarPagina(tester);

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.hoy)));
      await tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));

      expect(find.text('Más tarde, en esta misma salida · 14:40'), findsOneWidget);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
      expect(elegida?.fecha, DateTime(2026, 10, 23, 14, 40));
    });

    testWidgets('42B·01C: «Otro día» abre «Día y hora» sin «Hoy» ni «Mañana»', (tester) async {
      await montarPagina(tester);

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.otroDia)));
      expect(find.text('Día y hora'), findsOneWidget);
      expect(find.byKey(ClavesAgendarVisita.dia(0)), findsNothing);
      expect(find.byKey(ClavesAgendarVisita.dia(1)), findsNothing);
      for (final texto in ['Dom 25', 'Lun 26', 'Mar 27', 'Mié 28', 'Otro día…']) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
      await tocar(tester, find.text('Lun 26'));
      await tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));

      expect(find.text('Lunes 26/10 · 10:00'), findsOneWidget);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
      expect(elegida, (opcion: CuandoCobrar.otroDia, fecha: DateTime(2026, 10, 26, 10)));
    });

    testWidgets('cerrar «Día y hora» sin «Listo» deja lo que estaba elegido', (tester) async {
      await montarPagina(tester);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

      expect(elegida?.opcion, CuandoCobrar.sinFecha);
    });

    testWidgets('dos toques seguidos en una opción abren una sola hoja', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarPagina(tester);

      final manana = find.semantics.byLabel(RegExp('^Mañana'));
      tester.semantics.performAction(manana, SemanticsAction.tap);
      tester.semantics.performAction(manana, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesAgendarVisita.hojaListo), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dos toques en «Guardar» cierran una sola pantalla', (tester) async {
      await montarPagina(tester);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));

      await tester.tap(find.byKey(ClavesCuandoCobrar.guardar));
      await tester.tap(find.byKey(ClavesCuandoCobrar.guardar), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('abrir'), findsOneWidget, reason: 'la pantalla de abajo sigue');
    });

    testWidgets('las opciones son botones de 48 dp con etiqueta, elegibles y con contraste', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarPagina(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel(RegExp('^Sin fecha')), findsOneWidget);
      semantica.dispose();
    });

    for (final tamano in [const Size(320, 568), const Size(412, 915)]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'con un nombre larguísimo a ${tamano.width.toInt()}×${tamano.height.toInt()} y letra '
          '$escala no desborda y llega a todas las opciones y a «Guardar»',
          (tester) async {
            await montarPagina(
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
            expect(find.byKey(ClavesCuandoCobrar.guardar).hitTestable(), findsOneWidget);
          },
        );
      }
    }
  });

  group('el flujo que agenda', () {
    Future<void> montarFlujo(WidgetTester tester, {int saldo = 150000}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var n = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agendaRepositoryProvider.overrideWithValue(agendas),
            generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
            relojVisitaProvider.overrideWithValue(() => ahora),
            ...Telefono().overrides,
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => quedo = await FlujoCuandoCobrar.preguntar(
                    context,
                    ProviderScope.containerOf(context),
                    numeroTalonario: '0039',
                    espacioId: 'esp-1',
                    espacioPersonaId: 'ep-1',
                    colportorId: 'col-1',
                    persona: 'Pedro',
                    direccion: 'Grecia 3307',
                    saldoCentavos: saldo,
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

    testWidgets('sin saldo no pregunta nada', (tester) async {
      await montarFlujo(tester, saldo: 0);

      expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
      expect(quedo, isA<SinSaldoQueCobrar>());
      expect(agendas.recibidas, isEmpty);
    });

    testWidgets('«Sin fecha» no agenda', (tester) async {
      await montarFlujo(tester);

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

      expect(quedo, isA<CobranzaSinFecha>());
      expect(agendas.recibidas, isEmpty);
    });

    testWidgets('«Mañana» agenda una cobranza y la devuelve', (tester) async {
      await montarFlujo(tester);

      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
      await tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

      expect(quedo, isA<CobranzaAgendada>());
      expect(agendas.guardadas, hasLength(1));
      expect(
        (quedo! as CobranzaAgendada).agenda.fechaProgramada.toLocal(),
        DateTime(2026, 10, 24, 10),
      );
    });

    testWidgets(
      'si la cita falla, devuelve «no agendada» (el aviso sale en el mapa); nada trabado',
      (tester) async {
        agendas.lanzar = StateError('sin base');
        await montarFlujo(tester);

        await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
        await tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
        await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

        expect(quedo, isA<CobranzaNoAgendada>());
        expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
