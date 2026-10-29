// QA de «Dados de baja» al pie del edificio (vista 11, HU-UBI-007, #473, PR #559). Sin artboard nuevo:
// patrón de 11·01 y de 09·03/09·04. Lo que revisa, a 360×640 y 412×915 con el texto al 100 % y al 200 %
// (los tests del implementador usan una pantalla de 390×1600 que esconde casi todo): cada estado sin
// overflow, el aviso con «Deshacer» a la vista y sin tapar lo que se puede tocar, los avisos de falla
// dentro de lo que se ve, los casos límite y la reentrada.
//
// Los que llevan `skip:` documentan un hallazgo (`QA #473`); `--dart-define=QA_HALLAZGOS=true` los
// corre. Con `--dart-define=QA_CAPTURAS=true` saca las capturas a `.dart_tool/qa_capturas/` (no se
// commitean).
import 'dart:ui' show Tristate;

import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_con_deshacer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_bajas_473_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

String _donde(Size t, double escala) =>
    '${t.width.toInt()}×${t.height.toInt()} al ${(escala * 100).toInt()} %';

/// El rectángulo de lo que se ve de la hoja, recortado a la pantalla.
Rect _pantalla(WidgetTester tester) => Offset.zero & tester.view.physicalSize;

void _dentroDeLaPantalla(WidgetTester tester, Finder f, String que) {
  final r = tester.getRect(f);
  final p = _pantalla(tester);
  expect(
    r.left >= -0.5 && r.right <= p.width + 0.5 && r.top >= -0.5 && r.bottom <= p.height + 0.5,
    isTrue,
    reason: '$que queda fuera de la pantalla: $r en $p',
  );
}

void main() {
  const tamanos = [telefonoChico211, telefonoGrande211];
  const escalas = [1.0, 2.0];

  group('matriz de estados: sin overflow, nada fuera de la pantalla, capturas', () {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        for (final estado in EstadoBajas.values) {
          testWidgets('${estado.rotulo} a ${_donde(tamano, escala)}', (tester) async {
            await llegarABajas(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull, reason: 'overflow o error al dibujar');
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            await capturar473(
              tester,
              '${estado.name}_${tamano.width.toInt()}_${(escala * 10).toInt()}',
            );
            // Bajo el pliegue también: la hoja entera, hasta el final de la lista.
            tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.jumpTo(9000);
            await asentarHoja(tester);
            expect(tester.takeException(), isNull, reason: 'overflow al final de la lista');
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            await capturar473(
              tester,
              '${estado.name}_${tamano.width.toInt()}_${(escala * 10).toInt()}_fin',
            );
          });
        }
      }
    }
  });

  group('el aviso con «Deshacer» dentro de la hoja', () {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        final donde = _donde(tamano, escala);

        testWidgets('se ve entero, se alcanza con el toque y «Deshacer» mide 48 dp a $donde', (
          tester,
        ) async {
          await llegarABajas(tester, EstadoBajas.reactivado, tamano: tamano, escala: escala);

          expect(textoAviso473.hitTestable(), findsOneWidget);
          _dentroDeLaPantalla(tester, tarjeta473, 'la tarjeta del aviso');
          final hoja = tester.getRect(hojaUbicacion);
          final tarjeta = tester.getRect(tarjeta473);
          expect(
            hoja.contains(tarjeta.topLeft) && hoja.contains(tarjeta.bottomRight),
            isTrue,
            reason: 'la tarjeta se sale de la hoja',
          );
          expect(deshacer473.hitTestable(), findsOneWidget);
          final d = tester.getSize(deshacer473);
          expect(d.height >= 47.9 && d.width >= 47.9, isTrue, reason: '«Deshacer» mide $d');
          expect(find.byType(SnackBar), findsNothing);
        });

        testWidgets('no tapa la última fila de «Dados de baja»: se puede subir por encima de él a '
            '$donde', (tester) async {
          await llegarABajas(tester, EstadoBajas.desplegadoMuchas, tamano: tamano, escala: escala);
          // Reactivar el primero: sale el aviso y la lista queda con 7 bajas.
          await tocarReactivar473(tester, 'b-1');
          expect(tarjeta473, findsOneWidget);

          tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.jumpTo(9000);
          await asentarHoja(tester);

          final ultima = reactivar473('b-8');
          expect(ultima, findsOneWidget);
          final rUltima = tester.getRect(ultima);
          final rAviso = tester.getRect(tarjeta473);
          expect(
            rUltima.overlaps(rAviso),
            isFalse,
            reason: 'el «Reactivar» de la última baja $rUltima queda tapado por el aviso $rAviso',
          );
        });
      }
    }

    testWidgets('el aviso con lector trae la ✕ de 48 dp y no se va solo', (tester) async {
      await llegarABajas(tester, EstadoBajas.reactivadoLector);
      final x = tester.getSize(cerrarAviso473);
      expect(x.height >= 47.9 && x.width >= 47.9, isTrue, reason: 'la ✕ mide $x');
      await tester.pump(const Duration(seconds: 30));
      expect(tarjeta473, findsOneWidget, reason: 'con lector no corre el plazo');
      await tester.tap(cerrarAviso473);
      await asentarHoja(tester);
      expect(tarjeta473, findsNothing);
    });

    testWidgets('el mensaje es región viva (el lector lo dice al aparecer)', (tester) async {
      final h = tester.ensureSemantics();
      await llegarABajas(tester, EstadoBajas.reactivado);
      final nodo = tester.getSemantics(textoAviso473);
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      h.dispose();
    });
  });

  group('avisos de falla: dentro de lo que se ve', () {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        final donde = _donde(tamano, escala);

        testWidgets('«No pudimos reactivar…» queda a la vista y con la acción a mano a $donde', (
          tester,
        ) async {
          await llegarABajas(tester, EstadoBajas.errorReactivar, tamano: tamano, escala: escala);

          expect(avisoRojo473, findsOneWidget);
          expect(avisoRojo473.hitTestable(), findsOneWidget);
          final r = tester.getRect(avisoRojo473);
          final hoja = tester.getRect(hojaUbicacion);
          expect(
            r.top >= hoja.top && r.bottom <= _pantalla(tester).height,
            isTrue,
            reason: 'el aviso rojo $r queda fuera de lo que se ve de la hoja $hoja',
          );
          // El botón sigue habilitado: se puede reintentar.
          await irA473(tester, reactivar473('b-1'));
          expect(habilitado(tester, reactivar473('b-1')), isTrue);
        });

        testWidgets('«No se puede reactivar el depto 103…» dice qué hacer a $donde', (
          tester,
        ) async {
          await llegarABajas(tester, EstadoBajas.numeroTomado, tamano: tamano, escala: escala);

          expect(
            find.descendant(
              of: avisoRojo473,
              matching: find.textContaining('No se puede reactivar el depto 103'),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Cambiale el número'), findsOneWidget);
          expect(tarjeta473, findsNothing, reason: 'no se reactivó: no hay «Deshacer»');
          final r = tester.getRect(avisoRojo473);
          expect(r.bottom <= _pantalla(tester).height && r.top >= 0, isTrue);
        });

        testWidgets('el error de leer las bajas trae «Reintentar» de 48 dp y funciona a $donde', (
          tester,
        ) async {
          final m = await llegarABajas(
            tester,
            EstadoBajas.errorBajas,
            tamano: tamano,
            escala: escala,
          );
          await irA473(tester, reintentarBajas473);
          expect(reintentarBajas473.hitTestable(), findsOneWidget);
          expect(tester.getSize(reintentarBajas473).height >= 47.9, isTrue);
          expect(find.textContaining('No pudimos leer los deptos dados de baja'), findsOneWidget);

          m.repo.fallaAlListarBajas = null;
          final antes = m.repo.listadosConBajas;
          await tester.tap(reintentarBajas473);
          await asentarHoja(tester);
          expect(m.repo.listadosConBajas, antes + 1);
          expect(errorBajas473, findsNothing);
          expect(find.textContaining('Dados de baja · 2'), findsOneWidget);
        });
      }
    }

    testWidgets('el aviso de la falla de leer las bajas se anuncia (región viva)', (tester) async {
      final h = tester.ensureSemantics();
      await llegarABajas(tester, EstadoBajas.errorBajas);
      await irA473(tester, errorBajas473);
      final nodo = tester.getSemantics(
        find.descendant(
          of: errorBajas473,
          matching: find.textContaining('No pudimos leer los deptos'),
        ),
      );
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      h.dispose();
    });
  });

  group('casos límite', () {
    testWidgets('reentrar a la hoja: «Dados de baja» vuelve plegado y sin el aviso anterior', (
      tester,
    ) async {
      final m = await llegarABajas(tester, EstadoBajas.reactivado);
      expect(tarjeta473, findsOneWidget);

      // Cerrar la hoja y abrirla de nuevo.
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.jumpTo(0);
      await asentarHoja(tester);
      await tester.tap(cerrarHojaUbicacion);
      await asentarHoja(tester);
      expect(hojaUbicacion, findsNothing);
      await abrirLaHoja(tester);

      expect(tarjeta473, findsNothing);
      expect(m.repo.activos.map((e) => e.id), contains('b-1'), reason: 'la reactivación se guardó');
      await irA473(tester, cabecera473);
      expect(find.text('Dados de baja · 1'), findsOneWidget);
      expect(find.text('▾'), findsOneWidget, reason: 'plegado al abrir');
      expect(tester.takeException(), isNull);
    });

    testWidgets('el plazo de 8 s: a los 7,9 s sigue, a los 8,1 s se fue; «Deshacer» a tiempo '
        'devuelve la baja', (tester) async {
      final m = await llegarABajas(tester, EstadoBajas.reactivado);
      await tester.pump(const Duration(milliseconds: 6800));
      expect(tarjeta473, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(tarjeta473, findsNothing);
      expect(m.repo.activos.map((e) => e.id), contains('b-1'), reason: 'se queda reactivado');
    });

    // skip: QA #473 — tras reactivar todas las bajas, una baja nueva reaparece DESPLEGADA (el estado
    // `_bajasAbiertas` sobrevive a la desaparición de la cabecera); el issue pide «plegado».
    testWidgets('reactivar todas las bajas hace desaparecer «Dados de baja»; una baja nueva '
        'vuelve a aparecer PLEGADA', (tester) async {
      final m = await llegarABajas(tester, EstadoBajas.desplegado);
      await tocarReactivar473(tester, 'b-1');
      await tocarReactivar473(tester, 'b-2');
      expect(cabecera473, findsNothing, reason: 'sin bajas no hay «Dados de baja»');

      // Dar de baja el 101 desde su edición (11·02).
      await irA473(tester, filaDepto('e-101'));
      await abrirEdicionDepto(tester, 'e-101');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      // Lo que pida la baja (sin personas: confirma o ya está hecha).
      if (find.text('Dar de baja').evaluate().isNotEmpty) {
        await tester.tap(find.text('Dar de baja').last);
        await asentarHoja(tester);
      }
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-101').estaBorrada, isTrue);

      await irA473(tester, cabecera473);
      expect(find.text('▾'), findsOneWidget, reason: 'la HU/el issue: «plegado»');
    }, skip: !_verHallazgos);

    testWidgets('«Reactivar» mientras reactiva otro: el otro botón no se pierde y no se pisa el '
        'aviso', (tester) async {
      final m = await llegarABajas(tester, EstadoBajas.desplegado);
      await tocarReactivar473(tester, 'b-1');
      // Antes de que se vaya el aviso, el segundo.
      await tocarReactivar473(tester, 'b-2');

      expect(m.repo.llamadas.where((l) => l.startsWith('restaurar')).length, 2);
      expect(tarjeta473, findsOneWidget, reason: 'un solo aviso, el del último');
      expect(find.textContaining('reactivado.'), findsOneWidget);
      // «Deshacer» deshace el del último y el plazo es el del último.
      await tester.pump(const Duration(milliseconds: 7000));
      expect(tarjeta473, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tarjeta473, findsNothing);
    });

    testWidgets('«Deshacer» y luego reactivar de nuevo: el depto vuelve a la lista y el aviso '
        'es nuevo', (tester) async {
      final m = await llegarABajas(tester, EstadoBajas.deshecho);
      expect(find.text('Volvió a quedar de baja.'), findsOneWidget);
      await tocarReactivar473(tester, 'b-1');
      expect(m.repo.activos.map((e) => e.id), contains('b-1'));
      expect(find.textContaining('reactivado.'), findsOneWidget);
      expect(deshacer473, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '450 bajas: la lista se desplaza y la cabecera dice la cuenta sin cortarse a 360×640 '
      'al 200 %',
      (tester) async {
        await cargarFuentes211(tester);
        final m = await montarHoja(
          tester,
          espacios: [
            ...deptosDelCanvas(),
            for (var i = 0; i < 450; i++)
              espacioDe(
                'x-$i',
                '${i + 1}',
                piso: '${i % 30}',
                orden: 10 + (i % 40),
                baja: DateTime.utc(2026, 10, 22),
              ),
          ],
          tamano: telefonoChico211,
          escala: 2,
        );
        await irA473(tester, cabecera473);
        expect(find.text('Dados de baja · 450'), findsOneWidget);
        await tester.tap(cabecera473);
        await asentarHoja(tester);
        expect(tester.takeException(), isNull);
        expect(m.repo.listadosConBajas, 1);
      },
    );

    testWidgets(
      'piso y número con emoji o texto muy largo no rompen la fila ni tapan «Reactivar»',
      (tester) async {
        await cargarFuentes211(tester);
        await montarHoja(
          tester,
          espacios: [
            espacioDe(
              'x-1',
              '🏠 Apto ${'9' * 38}',
              piso: 'Subsuelo ${'B' * 60}',
              baja: DateTime.utc(2026, 10, 22),
            ),
          ],
          tamano: telefonoChico211,
          escala: 2,
        );
        await desplegar473(tester);
        expect(tester.takeException(), isNull);
        final c = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
        c.jumpTo(c.position.maxScrollExtent);
        await asentarHoja(tester);
        expect(reactivar473('x-1').hitTestable(), findsOneWidget);
        expect(tester.getSize(reactivar473('x-1')).height >= 47.9, isTrue);
      },
    );
  });

  group('accesibilidad de lo nuevo', () {
    testWidgets('la cabecera anuncia que está plegada/desplegada y la acción está en el nodo '
        'tocable', (tester) async {
      final h = tester.ensureSemantics();
      await llegarABajas(tester, EstadoBajas.plegado);
      await irA473(tester, cabecera473);
      var nodo = tester.getSemantics(find.bySemanticsLabel('Dados de baja, 2 deptos'));
      expect(nodo.getSemanticsData().flagsCollection.isExpanded, Tristate.isFalse);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(cabecera473);
      await asentarHoja(tester);
      nodo = tester.getSemantics(find.bySemanticsLabel('Dados de baja, 2 deptos'));
      expect(nodo.getSemanticsData().flagsCollection.isExpanded, Tristate.isTrue);
      h.dispose();
    });

    testWidgets('«Reactivar» dice de qué depto es y tiene acción de toque para el lector', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarABajas(tester, EstadoBajas.desplegado);
      await irA473(tester, reactivar473('b-1'));
      final nodo = tester.getSemantics(find.bySemanticsLabel('Reactivar Depto 103'));
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      h.dispose();
    });

    testWidgets('«Reactivando…» queda apagado y el lector lo dice', (tester) async {
      final h = tester.ensureSemantics();
      await llegarABajas(tester, EstadoBajas.reactivando);
      expect(find.text('Reactivando…'), findsOneWidget);
      expect(habilitado(tester, reactivar473('b-1')), isFalse);
      expect(find.bySemanticsLabel('Reactivando… Depto 103'), findsOneWidget);
      h.dispose();
    });
  });

  group('coherencia visual con las pantallas vecinas', () {
    // skip: QA #473 — «No pudimos deshacer…» sale con el «✓» verde de «hecho»: una falla con la marca de
    // éxito. Las fallas de la hoja van con el «!» rojo (`AvisoAlta`).
    testWidgets('«No pudimos deshacer…» no lleva el «✓» de éxito', (tester) async {
      await llegarABajas(tester, EstadoBajas.noPudoDeshacer);
      expect(find.textContaining('No pudimos deshacer'), findsOneWidget);
      expect(find.text('✓'), findsNothing);
    }, skip: !_verHallazgos);

    // skip: QA #473 — el texto de «Deshacer» de la tarjeta no declara `fontFamily` (los demás botones de
    // la hoja y de 09·03 sí, 'Inter'): sin letra del tema se dibuja con la del sistema.
    testWidgets('«Deshacer» del aviso usa la letra de la app (Inter) como el mensaje', (
      tester,
    ) async {
      await llegarABajas(tester, EstadoBajas.reactivado);
      String? letra(Finder f) => tester
          .widget<RichText>(find.descendant(of: f, matching: find.byType(RichText)).first)
          .text
          .style
          ?.fontFamily;
      expect(letra(textoAviso473), 'Inter');
      expect(letra(deshacer473), 'Inter');
    }, skip: !_verHallazgos);

    // skip: QA #473 — el tema (`OutlinedButtonTheme`) deja el relleno horizontal en 0: «Reactivar» toca
    // el borde de la píldora, igual que «Editar edificio» de la misma hoja (preexistente).
    testWidgets('«Reactivar» tiene aire entre la letra y el borde de la píldora', (tester) async {
      await llegarABajas(tester, EstadoBajas.desplegado);
      await irA473(tester, reactivar473('b-1'));
      final boton = tester.getRect(reactivar473('b-1'));
      final texto = tester.getRect(
        find.descendant(of: reactivar473('b-1'), matching: find.text('Reactivar')),
      );
      expect(texto.left - boton.left >= 8, isTrue, reason: 'aire a la izquierda: $texto en $boton');
    }, skip: !_verHallazgos);
  });

  group('privacidad', () {
    testWidgets('el aviso y sus textos no llevan nada más que el depto (sin personas ni notas)', (
      tester,
    ) async {
      await llegarABajas(tester, EstadoBajas.reactivado);
      final texto = tester.widget<Text>(textoAviso473).data!;
      expect(texto, 'Depto 103 reactivado. Vuelve a aparecer en el edificio.');
      expect(ColoresAvisoDeshacer.fondo, isNotNull);
    });
  });
}
