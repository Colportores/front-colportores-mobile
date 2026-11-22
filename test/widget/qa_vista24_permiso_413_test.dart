// QA del PR #576 (#413, HU-NOT-001, vista 24 grupo A), ronda sobre lo que cambió respecto de #478:
// P3 (texto de «los ajustes no abren»), P4 (texto del aviso 24A·03 = canvas), el pedido interrumpido
// por el sistema (Android, `grantResults` vacío → `Interrumpido`) y la fila «Notificaciones» de
// Configuración con el título que se achica. Los 6 artboards (24A·01 a 24A·06) ya los cubre
// `qa_vista24_permiso_153_test.dart`; acá solo el delta y sus bordes.
//
// Capturas: `--dart-define=QA_CAPTURAS=true` las deja en `.dart_tool/qa_capturas/` (no se commitean).
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/aviso_notificaciones.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/aviso_notificaciones_apagadas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_vista24_153_arnes.dart';

const _ajustesNoAbren =
    'No pudimos abrir los ajustes. Abrí los ajustes del teléfono, buscá esta app y activá las '
    'notificaciones.';

void main() {
  group('P3 y P4: textos exactos de la decisión', () {
    test('las constantes son las de la decisión del 26/10, sin «Colportaje»', () {
      expect(TextosNotificaciones.ajustesNoAbren, _ajustesNoAbren);
      expect(
        TextosNotificaciones.avisoApagadas,
        'Las notificaciones están apagadas. Podés activarlas en configuración.',
      );
      expect(TextosNotificaciones.ajustesNoAbren, isNot(contains('Colportaje')));
      expect(TextosNotificaciones.avisoApagadas, isNot(contains('desactivadas')));
    });

    for (final tam in tamanos) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets(
          '24A·06 con los ajustes que no abren, a ${tam.width.toInt()}×${tam.height.toInt()} '
          '×$escala: el texto de P3 entero, anunciado, con el botón a mano',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA(tester, Estado24.a06AjustesNoAbren, tam: tam, escala: escala);
            expect(tester.takeException(), isNull);
            expect(find.text(_ajustesNoAbren), findsOneWidget);
            final aviso = find.byKey(const Key('notificaciones_ajustes_no_abren'));
            expect(tester.getSemantics(aviso), isSemantics(isLiveRegion: true));
            sinTextoCortado(tester);
            expect(palabrasPartidas(tester), isEmpty);
            final boton = find.byKey(const Key('notificaciones_abrir_ajustes'));
            await tester.ensureVisible(boton);
            await tester.pump();
            dentroDeLaPantalla(tester, boton, tam);
            await capturar(
              tester,
              'p3_${tam.width.toInt()}x${tam.height.toInt()}_${escala.toInt()}x',
            );
            semantica.dispose();
            await cerrar(tester);
          },
        );

        testWidgets(
          '24A·03 a ${tam.width.toInt()}×${tam.height.toInt()} ×$escala: el aviso del canvas '
          '(más largo que el de la HU) entra sin cortarse y con sus dos acciones',
          (tester) async {
            await llegarA(tester, Estado24.a03, tam: tam, escala: escala);
            expect(tester.takeException(), isNull);
            expect(find.text(textoAviso), findsOneWidget);
            sinTextoCortado(tester);
            expect(palabrasPartidas(tester), isEmpty);
            dentroDeLaPantalla(tester, avisoCerrar, tam);
            dentroDeLaPantalla(tester, find.byKey(const Key('aviso_notificaciones_ir')), tam);
            await capturar(
              tester,
              'p4_${tam.width.toInt()}x${tam.height.toInt()}_${escala.toInt()}x',
            );
            await cerrar(tester);
          },
        );
      }
    }
  });

  group('pedido interrumpido por el sistema (Android: grantResults vacío → Interrumpido)', () {
    const canal = MethodChannel(PermisoNotificacionesCanal.nombre);
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void responder(Future<Object?>? Function(MethodCall) f) {
      mensajero.setMockMethodCallHandler(canal, f);
      addTearDown(() => mensajero.setMockMethodCallHandler(canal, null));
    }

    test('sale como falla de «pedir», no como «no», y no deja nada trabado: el reintento '
        'responde', () async {
      var llamadas = 0;
      responder((llamada) async {
        if (llamada.method != 'pedir') return null;
        llamadas++;
        if (llamadas == 1) {
          throw PlatformException(code: 'NOTIFICACIONES', message: 'Interrumpido');
        }
        return true;
      });
      final sistema = PermisoNotificacionesCanal();

      await expectLater(
        sistema.pedir(),
        throwsA(
          isA<PermisoNotificacionesException>().having((e) => e.operacion, 'operacion', 'pedir'),
        ),
      );
      expect(await sistema.pedir(), isTrue);
      expect(llamadas, 2);
    });

    test('la excepción no lleva datos de la persona en el toString', () async {
      responder(
        (_) async => throw PlatformException(code: 'NOTIFICACIONES', message: 'Interrumpido'),
      );
      try {
        await PermisoNotificacionesCanal().pedir();
        fail('tenía que fallar');
      } on PermisoNotificacionesException catch (e) {
        expect(e.toString(), 'PermisoNotificacionesException(pedir)');
      }
    });

    testWidgets('en el pedido del primer ingreso: la falla dice qué hacer y la persona puede '
        'volver a intentar o seguir con «Ahora no»', (tester) async {
      final a = await llegarA(tester, Estado24.a02Fallo);
      expect(pedidoFallo, findsOneWidget);
      expect(pedidoActivar, findsOneWidget);
      expect(pedidoAhoraNo, findsOneWidget);
      // Se puede reintentar más de una vez: la falla no deja el botón apagado ni el pedido «en curso».
      await tester.tap(pedidoActivar);
      await tester.pumpAndSettle();
      expect(pedidoFallo, findsOneWidget);
      expect(tester.widget<FilledButton>(pedidoActivar).onPressed, isNotNull);
      a.telefono.sistema.fallaAlPedir = false;
      await tester.tap(pedidoActivar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(toastActivadas, findsOneWidget);
      await cerrar(tester);
    });
  });

  group('fila «Notificaciones» de Configuración con el título que se achica (FittedBox)', () {
    const tamanosChicos = [Size(320, 568), Size(360, 640), Size(412, 915)];
    for (final tam in tamanosChicos) {
      for (final escala in const [1.0, 2.0, 3.0]) {
        testWidgets(
          'a ${tam.width.toInt()}×${tam.height.toInt()} ×$escala: la palabra entera entre el '
          'ícono y la flecha, con nombre para el lector y 48 dp de alto',
          (tester) async {
            final semantica = tester.ensureSemantics();
            fijarTamano(tester, tamano: tam, texto: escala);
            await cargarFuentes(tester);
            await abrirPantalla(tester, Telefono(), const ConfiguracionPage());
            final fila = find.byKey(const Key('configuracion_notificaciones'));
            await tester.ensureVisible(fila);
            await tester.pump();

            expect(tester.takeException(), isNull);
            final titulo = find.descendant(of: fila, matching: find.text('Notificaciones'));
            expect(titulo, findsOneWidget);
            final rt = tester.getRect(titulo);
            final ri = tester.getRect(
              find.descendant(of: fila, matching: find.byIcon(Icons.notifications_none_outlined)),
            );
            final rf = tester.getRect(
              find.descendant(of: fila, matching: find.byIcon(Icons.chevron_right)),
            );
            expect(rt.left, greaterThanOrEqualTo(ri.right - 0.5), reason: 'pisa el ícono');
            expect(rt.right, lessThanOrEqualTo(rf.left + 0.5), reason: 'pisa la flecha');
            expect(tester.getSize(fila).height, greaterThanOrEqualTo(48));
            // Lo que se achica sigue legible: la letra pintada no baja de la mitad de la del texto al
            // tamaño que eligió la persona.
            final natural = tester.renderObject<RenderParagraph>(titulo).size.height;
            final escalaReal = rt.height / natural;
            debugPrint(
              'fila ${tam.width.toInt()}×${tam.height.toInt()} ×$escala: escala real $escalaReal',
            );
            expect(escalaReal, greaterThanOrEqualTo(0.5), reason: 'el título queda ilegible');
            expect(
              tester.getSemantics(fila),
              isSemantics(label: 'Notificaciones', hasTapAction: true),
              reason: 'el lector tiene que oír el nombre de la fila y poder activarla',
            );
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await capturar(
              tester,
              'fila_${tam.width.toInt()}x${tam.height.toInt()}_${escala.toInt()}x',
            );
            semantica.dispose();
            await cerrar(tester);
          },
        );
      }
    }

    testWidgets('al 3,0× la fila sigue abriendo Configuración › Notificaciones', (tester) async {
      fijarTamano(tester, tamano: const Size(360, 640), texto: 3);
      await cargarFuentes(tester);
      await abrirPantalla(tester, Telefono(), const ConfiguracionPage());
      final fila = find.byKey(const Key('configuracion_notificaciones'));
      await tester.ensureVisible(fila);
      await tester.pump();
      await tester.tap(fila);
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsOneWidget);
      await cerrar(tester);
    });
  });

  group('hallazgos (se corren con --dart-define=QA_HALLAZGOS=true)', () {
    // skip: QA #413 — 24A·03 a 360×640 ×2,0: con el texto del canvas (P4) el aviso ocupa 6 renglones, llega
    // al tope del 40 % del alto y «Ir a configuración» queda bajo el borde del propio aviso: hay que
    // desplazar dentro de la caja para verlo (la ✕ sí se ve).
    testWidgets(
      'H1 · 24A·03 a 360×640 ×2,0: «Ir a configuración» se ve sin desplazar el aviso',
      (tester) async {
        await llegarA(tester, Estado24.a03, tam: const Size(360, 640), escala: 2);
        final caja = tester.getRect(
          find.descendant(
            of: find.byType(AvisoNotificacionesApagadas),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final accion = tester.getRect(find.byKey(const Key('aviso_notificaciones_ir')));
        expect(
          accion.bottom,
          lessThanOrEqualTo(caja.bottom + 0.5),
          reason: 'la acción queda ${accion.bottom - caja.bottom} dp bajo el borde del aviso',
        );
        await cerrar(tester);
      },
      skip: !const bool.fromEnvironment('QA_HALLAZGOS'),
    );
  });
}
