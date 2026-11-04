// QA #610 — varios respaldos juntos, aviso de «Empezar sin recuperar» y la fila «Recuperar mi
// respaldo» de Configuración. Lo que el implementador no probó: lector de pantalla, sistema «atrás»,
// textos en el borde (un solo respaldo en la lista de varios), tamaños y capturas.
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas`.
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_recuperacion_175_arnes.dart';
import '../../helpers/qa_recuperacion_610_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  group('Estados nuevos: sin overflow, sin texto cortado, con captura', () {
    for (final tamano in [chico175, grande175]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado610.values) {
          testWidgets('${estado.rotulo} · ${sufijo175(tamano, escala)}', (tester) async {
            final a = await llegarA610(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            sinTextoCortado175(tester);
            for (final boton in [cta, cta2, hojaVolver, hojaConfirmar]) {
              if (boton.evaluate().isEmpty) continue;
              await tester.ensureVisible(boton);
              await tester.pump();
              final r = tester.getRect(boton);
              final v = tester.view.physicalSize / tester.view.devicePixelRatio;
              expect(r.left >= 0 && r.right <= v.width, isTrue, reason: 'ancho: $r');
            }
            await capturar175(tester, '610_${estado.name}_${sufijo175(tamano, escala)}');
            await liberar175(tester, a);
          });
        }
      }
    }
  });

  group('Lector de pantalla', () {
    testWidgets('la hoja anuncia su título como encabezado y «Volver» es el primer botón', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final a = await llegarA610(tester, Estado610.hojaDesdeEncontrado);
      expect(
        tester.getSemantics(find.text('¿Empezar sin recuperar?')),
        matchesSemantics(label: '¿Empezar sin recuperar?', isHeader: true),
      );
      // «Volver» (la acción segura) viene antes que «Empezar sin recuperar» en el orden de lectura.
      final volver = tester.getTopLeft(hojaVolver).dy;
      final empezar = tester.getTopLeft(hojaConfirmar).dy;
      expect(volver < empezar, isTrue);
      await liberar175(tester, a);
      h.dispose();
    });

    testWidgets('varios: la contraseña que no abre las copias se anuncia (región viva)', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final a = await llegarA610(tester, Estado610.variosContrasenaDistinta);
      final nodo = tester.getSemantics(
        find.text(
          'Esta contraseña no abre tus copias; probá la que usabas cuando hiciste los últimos '
          'respaldos.',
        ),
      );
      expect(nodo.flagsCollection.isLiveRegion || _ancestroVivo(tester, nodo), isTrue);
      await liberar175(tester, a);
      h.dispose();
    });
  });

  group('Navegación', () {
    testWidgets('el «atrás» del sistema cierra la hoja y el asistente sigue donde estaba', (
      tester,
    ) async {
      final a = await llegarA610(tester, Estado610.hojaDesdeVarios);
      expect(hojaEmpezar, findsOneWidget);
      await tester.binding.handlePopRoute();
      await asentar175(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(hojaEmpezar, findsNothing);
      expect(find.byKey(const Key('recuperacion_pagina')), findsOneWidget);
      expect(textoDe(cta), 'Recuperar todos mis datos');
      expect(a.resuelta.marcas, 0, reason: 'volver no anota nada como resuelto');
      await liberar175(tester, a);
    });

    testWidgets('abrir la hoja, volver y abrirla otra vez: sigue ofreciendo las dos salidas', (
      tester,
    ) async {
      final a = await llegarA610(tester, Estado610.hojaDesdeEncontrado);
      await tocar175(tester, hojaVolver);
      await tester.pump(const Duration(milliseconds: 400));
      await tocar175(tester, cta2);
      expect(hojaVolver, findsOneWidget);
      expect(hojaConfirmar, findsOneWidget);
      await liberar175(tester, a);
    });
  });

  group('Datos límite: varios respaldos', () {
    testWidgets('tres respaldos: el texto dice 3 y se muestran las tres tarjetas', (tester) async {
      final a = ArnesRecuperacion();
      a.servicio.busqueda = VariosRespaldosEnDrive([
        respaldo610('a'),
        respaldo610('b', dia: 15),
        respaldo610('c', dia: 1),
      ]);
      await abrirAsistente175(tester, a);
      expect(find.textContaining('Encontramos 3 respaldos'), findsOneWidget);
      expect(find.textContaining('15 partes · 38 MB'), findsNWidgets(3));
      await liberar175(tester, a);
    });

    testWidgets('suma de pesos en la confirmación previa de «Abrí tus copias»', (tester) async {
      final a = ArnesRecuperacion();
      a.servicio.busqueda = VariosRespaldosEnDrive([
        respaldo610('a'),
        respaldo610('b', partes: 9, mb: 20),
      ]);
      await abrirAsistente175(tester, a);
      await irAContrasena175(tester);
      expect(
        find.text('Vamos a restaurar 58 MB. La operación puede tardar varios minutos.'),
        findsOneWidget,
      );
      await liberar175(tester, a);
    });

    testWidgets('H1: un solo respaldo dentro de «varios» no dice «1 respaldos»', (tester) async {
      final a = ArnesRecuperacion();
      a.servicio.busqueda = VariosRespaldosEnDrive([respaldo610('a')]);
      await abrirAsistente175(tester, a);
      expect(find.textContaining('1 respaldos'), findsNothing);
      await liberar175(tester, a);
    }, skip: !_verHallazgos); // skip: QA #610: con 1 solo respaldo en VariosRespaldosEnDrive el texto dice «Encontramos 1 respaldos» (menor)
  });

  group('Configuración: la fila «Recuperar mi respaldo»', () {
    testWidgets('el SnackBar «ya hay datos» se anuncia y la fila cumple el tamaño de toque', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final a = ArnesRecuperacion();
      await abrirAppHastaConfiguracion610(tester, a);
      final fila = find.byKey(const Key('configuracion_recuperar_respaldo'));
      expect(tester.getSize(fila).height >= 48, isTrue);
      a.lector.sinDatos = false;
      await tester.tap(fila);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final aviso = find.byKey(const Key('configuracion_recuperar_respaldo_no'));
      expect(aviso, findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturar175(tester, '610_config_ya_hay_datos');
      h.dispose();
    });

    testWidgets('captura de la fila en Configuración', (tester) async {
      final a = ArnesRecuperacion();
      await abrirAppHastaConfiguracion610(tester, a);
      await capturar175(tester, '610_config_fila');
    });

    testWidgets('la fila con texto al 200 % en 412x915: sin overflow', (tester) async {
      final a = ArnesRecuperacion();
      await abrirAppHastaConfiguracion610(tester, a, tamano: grande175, escala: 2);
      expect(tester.takeException(), isNull);
      await capturar175(tester, '610_config_fila_x2');
    });
  });
}

bool _ancestroVivo(WidgetTester tester, SemanticsNode nodo) {
  SemanticsNode? n = nodo;
  while (n != null) {
    if (n.flagsCollection.isLiveRegion) return true;
    n = n.parent;
  }
  return false;
}
