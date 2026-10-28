// QA de la entrega para otro día y «Entregas pendientes» (#435, vista 27 grupo C): los dos escenarios de
// la HU con su texto, el atrás en cada estado, «sin conexión» sin mencionar la señal y los casos límite
// que los tests del PR no cubren.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/qa_vista27_entrega_435_arnes.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(cta435).onPressed != null;

String _textoDelBoton(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(of: cta435, matching: find.byType(Text))).data!;

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

final _senal = RegExp('conexi|señal|internet|wifi|datos móviles', caseSensitive: false);

void main() {
  group('HU-VEN-003 · Escenario: Entrega diferida', () {
    testWidgets(
      'Dado que vendí pero no tengo material, cuando elijo otro día y guardo, entonces se crea la '
      'entrega PENDIENTE con la fecha prevista elegida y se agenda el recordatorio',
      (tester) async {
        final m = await montar435(tester, Estado435.otroDiaSinFecha);
        await elegirFecha435(tester, dia: 3);
        await tocarCta435(tester);

        final r = m.entorno.entregas.diferidas.single;
        expect(r.fechaPrevista.toLocal().day, ahoraDeLosTests.add(const Duration(days: 3)).day);
        expect(r.filasNuevas, isNotEmpty);
        expect(r.filasNuevas.every((f) => f.pendiente), isTrue, reason: 'estado PENDIENTE');
        expect(
          r.filasNuevas.every(
            (f) => f.fechaPrevista!.toLocal().day == r.fechaPrevista.toLocal().day,
          ),
          isTrue,
        );
        expect(find.textContaining('Entrega guardada para'), findsOneWidget);
      },
    );

    testWidgets('elegir HOY guarda la entrega para hoy (la validación es por día)', (tester) async {
      final m = await montar435(tester, Estado435.otroDiaSinFecha);
      await elegirFecha435(tester, dia: 0);
      await tocarCta435(tester);

      final r = m.entorno.entregas.diferidas.single;
      expect(r.fechaPrevista.toLocal().day, ahoraDeLosTests.day);
    });
  });

  group('HU-VEN-003 · Escenario: Cumplir entrega pendiente', () {
    testWidgets(
      'Dado que tengo una entrega pendiente, cuando la marco entregada, entonces todo lo pendiente '
      'pasa a entregado y vuelve con el aviso',
      (tester) async {
        final m = await montar435(tester, Estado435.marcarTodo);
        await tocarCta435(tester);

        final c = m.entorno.entregas.cumplidas.single;
        expect(c.ventaId, 'v-1');
        expect(c.entregaIds, {'e-1', 'e-2'});
        expect(c.nuevaFecha, isNull);
        expect(find.text('Entrega marcada.'), findsOneWidget);
      },
    );
  });

  group('Marcar entregado · casos límite', () {
    testWidgets('falla con una entrega parcial: sigue lo destildado y la nueva fecha; reintenta', (
      tester,
    ) async {
      final m = await montar435(tester, Estado435.marcarParcialConFecha);
      m.entorno.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
      await tocarCta435(tester);

      expect(find.text('Reintentar'), findsWidgets);
      expect(find.text('Nuestros Hijos sigue pendiente. ¿Para cuándo?'), findsOneWidget);
      expect(tester.widget<FilledButton>(cta435).onPressed, isNotNull);

      await tocarCta435(tester);
      final llamadas = m.entorno.entregas.cumplidas;
      expect(llamadas, hasLength(2));
      expect(llamadas.last.entregaIds, {'e-1'});
      expect(llamadas.last.nuevaFecha, llamadas.first.nuevaFecha);
      expect(llamadas.last.nuevaFecha, isNotNull);
    });

    testWidgets('destildar todo apaga el botón; volver a tildar uno lo enciende', (tester) async {
      await montar435(tester, Estado435.marcarSinNada);
      expect(_habilitado(tester), isFalse);
      expect(find.text('Elegí al menos un producto para marcar como entregado.'), findsOneWidget);

      await tocar(tester, find.text('Salud y Hogar × 1'));
      expect(_habilitado(tester), isTrue);
      expect(_textoDelBoton(tester), 'Marcar 1 entregado');
      expect(find.textContaining('Elegí al menos'), findsNothing);
    });

    testWidgets('volver a tildar lo destildado borra el «¿Para cuándo?» y el campo', (
      tester,
    ) async {
      await montar435(tester, Estado435.marcarParcialConFecha);
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.text('NUEVA FECHA'), findsNothing);
      expect(_textoDelBoton(tester), 'Marcar entregado');
    });

    testWidgets('nombres largos con emoji a 360×640 y texto 2,0: nada se corta ni desborda', (
      tester,
    ) async {
      final e = entorno435();
      e.fuente.productos = const ProductosDeLaEntrega(
        nombres: {
          'p-salud': 'Salud y Hogar 🌿 edición especial de colección con un título larguísimo',
          'p-hijos': 'Nuestros Hijos 👪 guía completa para madres, padres y maestros de escuela',
        },
      );
      await montar435(tester, Estado435.marcarTodo, tamano: chico435, escala: 2, entorno: e);
      await tocar(tester, find.textContaining('Nuestros Hijos'));

      expect(tester.takeException(), isNull);
      sinTextoCortado435(tester);
      await capturar435(tester, 'marcar_nombres_largos_360x640_2x');
    });
  });

  group('Atrás en cada estado', () {
    const sinGuardar = [
      Estado435.otroDiaSinFecha,
      Estado435.otroDiaConFecha,
      Estado435.otroDiaCargando,
      Estado435.otroDiaErrorDeLectura,
      Estado435.otroDiaSinProductos,
      Estado435.otroDiaErrorAlGuardar,
      Estado435.otroDiaPonerFecha,
      Estado435.pendientes,
      Estado435.pendientesVacia,
      Estado435.pendientesCargando,
      Estado435.pendientesError,
      Estado435.marcarTodo,
      Estado435.marcarParcialConFecha,
      Estado435.marcarSinNada,
      Estado435.marcarCargando,
      Estado435.marcarError,
      Estado435.marcarNadaPendiente,
      Estado435.marcarErrorAlGuardar,
    ];
    for (final estado in sinGuardar) {
      testWidgets('${estado.rotulo}: el atrás del sistema vuelve a la pantalla anterior', (
        tester,
      ) async {
        final m = await montar435(tester, estado);
        expect(find.byKey(const Key('abrir_pantalla')), findsNothing);

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.byKey(const Key('abrir_pantalla')), findsOneWidget);
        await soltar435(tester, m);
      });
    }

    for (final estado in [Estado435.otroDiaGuardando, Estado435.marcarGuardando]) {
      testWidgets('${estado.rotulo}: el atrás del sistema no sale', (tester) async {
        final m = await montar435(tester, estado);

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.byKey(const Key('abrir_pantalla')), findsNothing);
        await soltar435(tester, m);
      });
    }
  });

  group('Sin conexión funciona igual: ningún estado habla de la señal', () {
    for (final estado in Estado435.values) {
      testWidgets(estado.rotulo, (tester) async {
        final m = await montar435(tester, estado);
        final textos = [
          for (final t in tester.widgetList<Text>(find.byType(Text)))
            if (t.data != null) t.data!,
        ];
        expect(textos.where(_senal.hasMatch), isEmpty);
        await soltar435(tester, m);
      });
    }
  });

  group('Error al leer las entregas · salida', () {
    testWidgets('«Reintentar» de 27C·07 recupera la lista cuando vuelve a andar', (tester) async {
      final m = await montar435(tester, Estado435.pendientesError);
      expect(find.text('No pudimos leer tus entregas.'), findsOneWidget);

      m.entorno.entregas.errorDePendientes = null;
      await tocar(tester, find.byKey(const Key('venta_aviso_accion')));

      expect(find.text('No pudimos leer tus entregas.'), findsNothing);
      expect(find.text('ATRASADAS'), findsOneWidget);
    });
  });

  group('Hallazgos (se corren con --dart-define=QA_HALLAZGOS=true)', () {
    for (final estado in [Estado435.otroDiaGuardando, Estado435.marcarGuardando]) {
      // skip: QA #435 — mientras guarda, el botón es una ruedita sin etiqueta ni región viva: el lector
      // de pantalla no dice que se está guardando.
      testWidgets('${estado.rotulo}: el lector de pantalla oye que se está guardando', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final m = await montar435(tester, estado);

        final nodo = tester.getSemantics(cta435);
        expect(nodo.label, contains('Guardando'));
        await soltar435(tester, m);
        handle.dispose();
      }, skip: !_hallazgos);
    }
  });
}
