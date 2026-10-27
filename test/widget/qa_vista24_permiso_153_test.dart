// QA del PR #478 (#153, HU-NOT-001, vista 24 grupo A): lo que los tests del implementador no miden.
// Cada artboard del canvas (24A·01 a 24A·06) y cada estado de la HU, en 360×640 y 412×915 con el texto
// al 100 % y al 200 %, con las fuentes reales: sin overflow, sin texto cortado, con el botón a la
// vista, las guías de toque y de etiquetas de Flutter, y los textos literales de la HU y del canvas.
// El contraste va aparte (`qa_vista24_permiso_153_contraste_test.dart`).
//
// Capturas: `--dart-define=QA_CAPTURAS=true` las deja en `.dart_tool/qa_capturas/` (no se commitean).
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_vista24_153_arnes.dart';

/// `--dart-define=QA_HALLAZGOS=true` corre los tests de hallazgos que siguen sin arreglar.
const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

String _t(Size tam, double escala) => '${tam.width.toInt()}×${tam.height.toInt()} ×$escala';

/// Los botones y avisos que cada estado debe tener a la vista, para el chequeo de alcance.
Map<Estado24, List<String>> _llaves = {
  Estado24.a01: ['permiso_notificaciones_activar', 'permiso_notificaciones_ahora_no'],
  Estado24.a02Fallo: [
    'permiso_notificaciones_fallo',
    'permiso_notificaciones_activar',
    'permiso_notificaciones_ahora_no',
  ],
  Estado24.a03: ['aviso_notificaciones_ir', 'aviso_notificaciones_cerrar'],
  Estado24.a06: ['notificaciones_abrir_ajustes'],
  Estado24.a06AjustesNoAbren: ['notificaciones_abrir_ajustes', 'notificaciones_ajustes_no_abren'],
  Estado24.sinPedir: ['notificaciones_activar'],
  Estado24.errorAlLeer: ['notificaciones_reintentar'],
  Estado24.fallaAlActivar: ['notificaciones_fallo', 'notificaciones_activar'],
};

void main() {
  group('matriz: cada estado × 360×640 y 412×915 × 1,0 y 2,0', () {
    for (final e in Estado24.values) {
      for (final tam in tamanos) {
        for (final escala in escalas) {
          testWidgets('${e.rotulo} a ${_t(tam, escala)}: sin overflow, sin texto cortado, botones '
              'a la vista y guías de toque', (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA(tester, e, tam: tam, escala: escala);

            expect(tester.takeException(), isNull, reason: 'overflow o error al pintar');
            sinTextoCortado(tester);
            expect(palabrasPartidas(tester), isEmpty, reason: 'palabra partida a la mitad');
            for (final k in _llaves[e] ?? const <String>[]) {
              final f = find.byKey(Key(k));
              expect(f, findsOneWidget, reason: k);
              await tester.ensureVisible(f);
              await tester.pump();
              dentroDeLaPantalla(tester, f, tam);
            }
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await capturar(
              tester,
              '${e.name}_${tam.width.toInt()}x${tam.height.toInt()}_${escala.toInt()}x',
            );
            semantica.dispose();
            await cerrar(tester);
          });
        }
      }
    }
  });

  group('textos literales de la HU y del canvas', () {
    testWidgets('24A·01: título de la HU, los tres motivos del canvas y los dos botones', (
      tester,
    ) async {
      await llegarA(tester, Estado24.a01);
      for (final texto in [
        'Activá notificaciones para no perderte avisos importantes',
        'Recordatorios de tus visitas',
        'Con la dirección y el tipo, sin el nombre del cliente',
        'Pedidos y tickets revisados',
        'Cambios de zona y de campaña',
        'Activar notificaciones',
        'Ahora no',
      ]) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
      await cerrar(tester);
    });

    testWidgets('24A·03: "Notificaciones desactivadas. Activá en Configuración." (HU) con las '
        'acciones del canvas', (tester) async {
      await llegarA(tester, Estado24.a03);
      expect(find.text('Notificaciones desactivadas. Activá en Configuración.'), findsOneWidget);
      expect(find.text('Ir a configuración'), findsOneWidget);
      expect(find.byTooltip('Cerrar aviso'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('24A·04: «Notificaciones activadas.» y sigue en Hoy', (tester) async {
      await llegarA(tester, Estado24.a04);
      expect(find.text('Notificaciones activadas.'), findsOneWidget);
      expect(principal, findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('24A·05: el texto sin conexión del canvas, sin lo anterior', (tester) async {
      await llegarA(tester, Estado24.a05);
      expect(
        find.text(
          'Activadas. Los recordatorios ya funcionan; los avisos de tu coordinador empiezan a '
          'llegar cuando haya conexión.',
        ),
        findsOneWidget,
      );
      expect(find.text('Notificaciones activadas.'), findsNothing);
      await cerrar(tester);
    });

    testWidgets('24A·06: texto del canvas y «Abrir ajustes del teléfono»', (tester) async {
      await llegarA(tester, Estado24.a06);
      expect(
        find.text(
          'Las notificaciones están bloqueadas en los ajustes del teléfono. Desde la app no las '
          'podemos activar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Abrir ajustes del teléfono'), findsOneWidget);
      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('avisos de error: qué pasa y qué hacer, con la acción a mano', () {
    testWidgets('el pedido que falla dice qué hacer (probar de nuevo o «Ahora no») y los dos '
        'botones están habilitados', (tester) async {
      final alcanzado = await llegarA(tester, Estado24.a02Fallo);
      final texto = (tester.widget(pedidoFallo) as Text).data!;
      expect(texto, contains('Probá de nuevo'));
      expect(texto, contains('Ahora no'));
      expect(tester.widget<FilledButton>(pedidoActivar).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(pedidoAhoraNo).onPressed, isNotNull);
      expect(alcanzado.telefono.sistema.pedidos, 1);
      await cerrar(tester);
    });

    testWidgets('el error del pedido se anuncia (región viva) y el botón de reintento está ahí', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA(tester, Estado24.a02Fallo);
      expect(tester.getSemantics(pedidoFallo), isSemantics(isLiveRegion: true));
      semantica.dispose();
      await cerrar(tester);
    });

    testWidgets('error al leer en Configuración: dice qué pasó y ofrece «Reintentar», que '
        'reintenta de verdad', (tester) async {
      final alcanzado = await llegarA(tester, Estado24.errorAlLeer);
      expect(find.text('No pudimos revisar las notificaciones.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      alcanzado.telefono.sistema
        ..fallaAlLeer = false
        ..estado = EstadoSistemaNotificaciones.activadas;
      await tester.tap(find.byKey(const Key('notificaciones_reintentar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pref_recordatorios_interruptor')), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('los ajustes que no abren dicen dónde buscarlos a mano y el botón sigue '
        'disponible', (tester) async {
      await llegarA(tester, Estado24.a06AjustesNoAbren);
      expect(
        (tester.widget(find.byKey(const Key('notificaciones_ajustes_no_abren'))) as Text).data,
        contains('Buscá'),
      );
      final boton = find.byKey(const Key('notificaciones_abrir_ajustes'));
      expect(tester.widget<TextButton>(boton).onPressed, isNotNull);
      await cerrar(tester);
    });
  });

  group('casos límite del flujo', () {
    testWidgets('falla, reintento que sale bien: el toast llega y la persona entra a Hoy', (
      tester,
    ) async {
      final alcanzado = await llegarA(tester, Estado24.a02Fallo);
      alcanzado.telefono.sistema.fallaAlPedir = false;
      await tester.tap(pedidoActivar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(toastActivadas, findsOneWidget);
      expect(principal, findsOneWidget);
      expect(pedidoFallo, findsNothing);
      await cerrar(tester);
    });

    testWidgets('falla y «Ahora no»: sigo a Hoy con el aviso sutil, sin nada trabado', (
      tester,
    ) async {
      await llegarA(tester, Estado24.a02Fallo);
      await tester.tap(pedidoAhoraNo);
      await tester.pumpAndSettle();
      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('«No permitir» en el diálogo: sigo a Hoy con el aviso, sin toast de éxito', (
      tester,
    ) async {
      final t = Telefono()..sistema.respuestaAlPedir = false;
      await abrirApp(tester, t);
      await tester.tap(pedidoActivar);
      await tester.pumpAndSettle();
      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsOneWidget);
      expect(toastActivadas, findsNothing);
    });

    testWidgets(
      '«No permitir» y desde el aviso a Configuración: dice bloqueadas y ofrece abrir los '
      'ajustes',
      (tester) async {
        final t = Telefono()..sistema.respuestaAlPedir = false;
        await abrirApp(tester, t);
        await tester.tap(pedidoActivar);
        await tester.pumpAndSettle();
        await tester.tap(avisoIr);
        await tester.pumpAndSettle();
        expect(find.text(textoBloqueadas), findsOneWidget);
        expect(find.byKey(const Key('notificaciones_abrir_ajustes')), findsOneWidget);
      },
    );

    testWidgets('volver a la app con el diálogo abierto no lo cierra ni pide dos veces', (
      tester,
    ) async {
      final alcanzado = await llegarA(tester, Estado24.a02);
      volverALaApp(tester);
      await tester.pump();
      expect(pedidoPidiendo, findsOneWidget);
      expect(alcanzado.telefono.sistema.pedidos, 1);
      alcanzado.dialogo!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(toastActivadas, findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('sin conexión, desde el aviso de Hoy › Configuración › «Activar», también dice el '
        'texto de 24A·05', (tester) async {
      final t = Telefono()..recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      t.conexion.tipo = TipoConexion.sinConexion;
      await abrirApp(tester, t);
      await tester.tap(avisoIr);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notificaciones_activar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('cuando haya conexión'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('el pedido contestado no deja la app esperando: el spinner del botón tiene nombre '
        'para el lector', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA(tester, Estado24.a02);
      expect(find.bySemanticsLabel('Esperando tu respuesta'), findsOneWidget);
      semantica.dispose();
      await cerrar(tester);
    });

    testWidgets('el título del pedido y el de Configuración son encabezados', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA(tester, Estado24.a01);
      expect(
        tester.getSemantics(find.byKey(const Key('permiso_notificaciones_titulo'))),
        isSemantics(isHeader: true),
      );
      semantica.dispose();
      await cerrar(tester);
    });
  });

  group('la fila «Notificaciones» de Configuración (entrada de 24A·03 y 24A·06)', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets('a ${_t(tam, escala)}: se llega, se lee entera, mide 48 dp y tiene nombre', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          fijarTamano(tester, tamano: tam, texto: escala);
          await cargarFuentes(tester);
          await abrirPantalla(tester, Telefono(), const ConfiguracionPage());

          final fila = find.byKey(const Key('configuracion_notificaciones'));
          await tester.ensureVisible(fila);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(fila).height, greaterThanOrEqualTo(48));
          sinTextoCortado(tester);
          dentroDeLaPantalla(tester, fila, tam);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await capturar(
            tester,
            'configuracion_${tam.width.toInt()}x${tam.height.toInt()}_${escala.toInt()}x',
          );
          semantica.dispose();
          await cerrar(tester);
        });
      }
    }

    testWidgets('dos toques seguidos en la fila abren una sola pantalla', (tester) async {
      await abrirPantalla(tester, Telefono(), const ConfiguracionPage());
      final fila = find.byKey(const Key('configuracion_notificaciones'));
      await tester.ensureVisible(fila);
      await tester.pump();
      await tester.tap(fila);
      await tester.tap(fila, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsOneWidget);
      await tester.tap(find.byKey(const Key('notificaciones_atras')));
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsNothing);
    });
  });

  group('hallazgos', () {
    // skip: QA #153 — la fila «Notificaciones» de Configuración parte la palabra («Notificacione» /
    // «s») a 360 dp con el texto al 200 %: «Notificaciones» mide 210,8 dp y el título tiene 208 dp
    // (leading + chevron comen el ancho). La pantalla vecina «Borrar datos locales» corta por palabras.
    testWidgets(
      'H1 · la fila «Notificaciones» de Configuración no parte la palabra a 360 dp ×2,0',
      (tester) async {
        fijarTamano(tester, tamano: const Size(360, 640), texto: 2);
        await cargarFuentes(tester);
        await abrirPantalla(tester, Telefono(), const ConfiguracionPage());
        final fila = find.byKey(const Key('configuracion_notificaciones'));
        await tester.ensureVisible(fila);
        await tester.pump();

        expect(palabrasPartidas(tester), isEmpty);
        await cerrar(tester);
      },
      skip: !_hallazgos,
    );
  });
}
