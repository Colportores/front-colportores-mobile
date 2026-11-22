// QA de #715 (casas «fuera del área» en el mapa, #713; HU-SYNC-011, R-UB12), pasada del QA. Cubre lo
// que los tests del implementador no tocan: cada estado nuevo a 360x640 y 412x915 con el texto a 1,0
// y a 2,0 (sin desbordes, el aviso dentro de la pantalla y por encima de la hoja), una baja también
// marcada, el interruptor reabierto, los pulls con «Referencias» abierta, y las dos entradas del
// shell («ir a la casa» y «tras guardar vuelve al mapa») con la casa oculta. Las capturas (con
// `--dart-define=QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/fuera_del_area_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_fuera_del_area.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_mapa_fuera_del_area_715_arnes.dart';
import 'navegacion_inicio_649_arnes.dart';

void main() {
  group('QA #715 · cada estado nuevo en los dos teléfonos', () {
    for (final MapEntry(key: nombreTamano, value: tamano) in tamanos715.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final MapEntry(key: nombre, value: armar) in escenas715.entries) {
          testWidgets('$nombre · $nombreTamano · texto $escala: sin desbordes y todo a la vista', (
            tester,
          ) async {
            await cargarFuentes715(tester);
            final m = await armar(tester, tamano, escala);

            expect(tester.takeException(), isNull);
            if (avisoMapa715.evaluate().isNotEmpty) {
              final caja = tester.getRect(avisoMapa715);
              expect(caja.left, greaterThanOrEqualTo(0));
              expect(caja.right, lessThanOrEqualTo(tamano.width));
              expect(caja.height, greaterThanOrEqualTo(48));
              // El aviso no queda debajo de la hoja.
              expect(caja.bottom, lessThanOrEqualTo(tester.getTopLeft(hoja).dy + 1));
            }
            if (interruptor715.evaluate().isNotEmpty) {
              await tester.ensureVisible(interruptor715);
              await asentarLista(tester, 4);
              expect(tester.getSize(interruptor715).height, greaterThanOrEqualTo(48));
            }
            expect(m.altas, isEmpty);
            await capturar715(tester, '$nombre $nombreTamano x$escala');
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('QA #715 · casos límite del interruptor y de los pulls', () {
    testWidgets('dado un interruptor apagado, cuando se reabre «Referencias», entonces lo muestra '
        'apagado y prenderlo trae las casas de vuelta', (tester) async {
      final m = await montar715(tester, FueraDelAreaFalsas715({'u1', 'u3'}));
      await ocultar715(tester);

      await abrirReferencias715(tester);
      await tester.ensureVisible(interruptor715);
      expect(tester.widget<SwitchListTile>(interruptor715).value, isFalse);
      expect(
        find.text('2 casas. Ocultarlas solo cambia lo que ves en el mapa: no se borra nada.'),
        findsOneWidget,
      );

      await tester.tap(interruptor715);
      await asentarLista(tester, 4);
      expect(tester.widget<SwitchListTile>(interruptor715).value, isTrue);
      await cerrarReferencias715(tester);

      expect(dibujadas715(m.mapa), {'u1', 'u2', 'u3', 'u4'});
      expect(conAro715(m.mapa), {'u1', 'u3'});
      expect(avisoMapa715, findsNothing);
    });

    testWidgets('el interruptor se anuncia con su nombre y su cuenta, y se puede activar con el '
        'lector', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar715(tester, FueraDelAreaFalsas715({'u1', 'u3'}));
      await abrirReferencias715(tester);
      await tester.ensureVisible(interruptor715);

      final nodo = tester.getSemantics(interruptor715);
      expect(nodo.label, contains('Mostrar las casas fuera de tu área'));
      expect(nodo.label, contains('2 casas'));
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });

    testWidgets('«Referencias» abierta con las casas ocultas: un pull que devuelve todas al área '
        'saca el interruptor sin errores y la elección se conserva', (tester) async {
      final fuera = FueraDelAreaFalsas715({'u1', 'u3'});
      final m = await montar715(tester, fuera);
      await abrirReferencias715(tester);
      await tester.ensureVisible(interruptor715);
      await tester.tap(interruptor715);
      await asentarLista(tester, 4);
      expect(dibujadas715(m.mapa), {'u2', 'u4'});

      fuera.emitir(const {});
      await asentarLista(tester, 6);
      expect(tester.takeException(), isNull);
      expect(interruptor715, findsNothing);
      expect(dibujadas715(m.mapa), {
        'u1',
        'u2',
        'u3',
        'u4',
      }, reason: 'nada fuera del área, nada oculto');

      fuera.emitir({'u2'});
      await asentarLista(tester, 6);
      await cerrarReferencias715(tester);
      expect(dibujadas715(m.mapa), {
        'u1',
        'u3',
        'u4',
      }, reason: 'la elección de ocultar sigue en pie');
      expect(find.text('1 casa fuera de tu área oculta'), findsOneWidget);
    });

    testWidgets(
      'una baja marcada fuera del área no cuenta ni se dibuja, y no rompe «Cercanía» a 2×',
      (tester) async {
        final m = await montar715(
          tester,
          FueraDelAreaFalsas715({'u1', 'u5'}),
          casas: casas715(conBaja: true),
          escala: 2,
          tamano: const Size(360, 640),
        );
        await tocarAsa(tester, 2);

        expect(tester.takeException(), isNull);
        expect(conAro715(m.mapa), {'u1'});
        await ocultar715(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('1 casa fuera de tu área oculta'), findsWidgets);
      },
    );

    testWidgets(
      'el pull saca la casa elegida del área con la hoja abierta y las casas ocultas: sigue a '
      'la vista hasta cerrar la hoja',
      (tester) async {
        final fuera = FueraDelAreaFalsas715({'u1'});
        final m = await montar715(tester, fuera);
        await ocultar715(tester);
        expect(dibujadas715(m.mapa), {'u2', 'u3', 'u4'});

        m.mapa.tocarPunto('u2');
        await asentarLista(tester);
        fuera.emitir({'u1', 'u2'});
        await asentarLista(tester, 6);
        expect(dibujadas715(m.mapa), contains('u2'), reason: 'la elegida nunca se oculta');
        expect(find.byType(EtiquetaFueraDelArea), findsOneWidget);

        await tester.tap(cerrarVistaPrevia);
        await asentarLista(tester);
        expect(dibujadas715(m.mapa), {'u3', 'u4'});
        expect(
          find.descendant(
            of: avisoMapa715,
            matching: find.text('2 casas fuera de tu área ocultas'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('QA #715 · hallazgos', () {
    testWidgets('la pestaña «Cercanía» cuenta lo que la lista muestra: con 2 casas ocultas de 4, '
        'dice 2 y no 4', (tester) async {
      await montar715(tester, FueraDelAreaFalsas715({'u1', 'u3'}));
      await ocultar715(tester);
      await tocarAsa(tester, 2);

      expect(fila('u2'), findsOneWidget);
      expect(fila('u4'), findsOneWidget);
      expect(fila('u1'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(ClavesMapaUbicaciones.pestanaCercania),
          matching: find.text('4'),
        ),
        findsNothing,
        reason:
            'la pestaña sigue contando las 4 casas: la lista muestra 2 y el aviso dice 2 ocultas',
      );
    }, skip: !verHallazgos715);

    test('el interruptor apagado se ve: su borde y su pulgar contra la hoja blanca llegan a 3:1 '
        '(WCAG 1.4.11)', () {
      final tema = temaClaro();
      double luz(Color c) => c.computeLuminance();
      double contraste(Color a, Color b) {
        final claro = luz(a) > luz(b) ? a : b;
        final oscuro = claro == a ? b : a;
        return (luz(claro) + 0.05) / (luz(oscuro) + 0.05);
      }

      // En el tema M3 el pulgar y el borde del interruptor apagado son `colorScheme.outline`.
      expect(contraste(tema.colorScheme.outline, Colors.white), greaterThanOrEqualTo(3));
    }, skip: !verHallazgos715);
  });

  group('QA #715 · las entradas del shell con la casa oculta', () {
    Future<Montaje649> montarShell(WidgetTester tester) async {
      final fuera = FueraDelAreaFalsas715({'u1'});
      return montar649(
        tester,
        filas: [
          filaLista('u1', numero: '101'),
          filaLista('u2', numero: '102', metrosAlNorte: 30),
        ],
        extras: [fuera.sobrescribe],
      );
    }

    Set<String> dibujadas(Montaje649 m) => dibujadas715(m.mapa);

    testWidgets('«ir a la casa» a una casa oculta: se ve, con su hoja y su etiqueta', (
      tester,
    ) async {
      final m = await montarShell(tester);
      await m.irA('mapa');
      m.contenedor.read(verFueraDelAreaProvider.notifier).ocultar();
      await m.asentar();
      expect(dibujadas(m), {'u2'});

      m.notificador.irALaCasa('u1');
      await m.asentar();

      expect(m.seleccionada, 'u1');
      expect(dibujadas(m), contains('u1'));
      expect(find.byType(EtiquetaFueraDelArea), findsOneWidget);
    });

    testWidgets(
      '«tras guardar vuelve al mapa» con la casa oculta: la casa que la colportora acaba de '
      'trabajar sigue a la vista, para volver a tocarla',
      (tester) async {
        final m = await montarShell(tester);
        await m.irA('mapa');
        m.contenedor.read(verFueraDelAreaProvider.notifier).ocultar();
        await m.asentar();

        m.mapa.tocarPunto('u1');
        await m.asentar();
        expect(m.seleccionada, 'u1');
        m.notificador.volverAlMapa('u1');
        await m.asentar();

        expect(dibujadas(m), contains('u1'));
      },
      skip: !verHallazgos715,
    );
  });
}
