// QA de HU-NOT-003 (#187, PR #615) — guías de accesibilidad y tamaños del aviso con la app abierta
// (24C·08): 360×640 y 412×915, texto 1,0 y 2,0, con un título normal y con el nombre de una campaña
// largo. Con la letra de prueba (Ahem): con las fuentes reales `textContrastGuideline` da falsos
// negativos (lee el fondo de una captura con glifos reales).

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/push_remotas_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/aviso_push_en_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];
const _escalas = [1.0, 2.0];
const _titulos = <(String, String)>[
  ('pedido', 'Tu pedido fue autorizado'),
  (
    'campaña larga',
    'Te asignaron la zona Cerro Norte Sector Oriental Extendido en la campaña Primavera 2026 de '
        'colportaje universitario y comunitario',
  ),
];

Notificacion _aviso(String titulo, {String? detalle}) => Notificacion(
  id: 'push-1',
  tipo: TipoNotificacion.pedidoAutorizado,
  titulo: titulo,
  detalle: detalle,
  recibidaEn: DateTime.utc(2026, 11, 9, 15, 30),
);

void main() {
  for (final (nombreT, tam) in _tamanos) {
    for (final escala in _escalas) {
      for (final (nombreTit, titulo) in _titulos) {
        group('$nombreT · ×$escala · $nombreTit', () {
          Future<CanalAvisosPush> montar(WidgetTester tester) async {
            tester.view
              ..physicalSize = tam
              ..devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = escala;
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            final canal = CanalAvisosPush();
            addTearDown(canal.cerrar);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [canalAvisosPushProvider.overrideWithValue(canal)],
                child: MaterialApp(
                  theme: temaClaro(),
                  home: const Scaffold(body: Center(child: Text('Hoy'))),
                  builder: (context, child) =>
                      AvisoPushEnAppHost(activo: true, child: child ?? const SizedBox()),
                ),
              ),
            );
            canal.mostrar(_aviso(titulo));
            await tester.pump(const Duration(milliseconds: 50));
            return canal;
          }

          testWidgets('sin overflow y dentro de la pantalla, sin tapar más de 3/4', (tester) async {
            await montar(tester);

            expect(tester.takeException(), isNull);
            final caja = tester.getRect(find.byKey(const Key('aviso_push_en_app_abrir')));
            expect(caja.left, greaterThanOrEqualTo(0));
            expect(caja.right, lessThanOrEqualTo(tam.width));
            expect(caja.bottom, lessThan(tam.height * .75));
          });

          testWidgets('guías de toque, etiqueta y contraste', (tester) async {
            final semantica = tester.ensureSemantics();
            await montar(tester);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        });
      }
    }
  }

  group('teclado', () {
    testWidgets('con Tab se llega al aviso y luego a la ✕, y Enter en la ✕ lo cierra', (
      tester,
    ) async {
      final canal = CanalAvisosPush();
      addTearDown(canal.cerrar);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [canalAvisosPushProvider.overrideWithValue(canal)],
          child: MaterialApp(
            theme: temaClaro(),
            home: Scaffold(
              body: Center(
                child: Column(
                  children: [
                    TextButton(onPressed: () {}, child: const Text('Uno')),
                    TextButton(onPressed: () {}, child: const Text('Dos')),
                  ],
                ),
              ),
            ),
            builder: (context, child) =>
                AvisoPushEnAppHost(activo: true, child: child ?? const SizedBox()),
          ),
        ),
      );
      canal.mostrar(_aviso('Tu pedido fue autorizado'));
      await tester.pump(const Duration(milliseconds: 50));

      Key? enFoco() {
        Key? clave;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
          final k = e.widget.key;
          if (k == const Key('aviso_push_en_app_abrir') ||
              k == const Key('aviso_push_en_app_cerrar')) {
            clave = k;
            return false;
          }
          return true;
        });
        return clave;
      }

      final recorrido = <String>[];
      var alcanzoAbrir = false;
      var alcanzoCerrar = false;
      for (var i = 0; i < 8 && !alcanzoCerrar; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final k = enFoco();
        recorrido.add('${FocusManager.instance.primaryFocus?.context?.widget.runtimeType}:$k');
        alcanzoAbrir |= k == const Key('aviso_push_en_app_abrir');
        alcanzoCerrar |= k == const Key('aviso_push_en_app_cerrar');
      }
      expect(alcanzoAbrir, isTrue, reason: 'Tab llega al aviso: $recorrido');
      expect(alcanzoCerrar, isTrue, reason: 'Tab llega a la ✕: $recorrido');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byKey(const Key('aviso_push_en_app_abrir')), findsNothing);
    });
  });
  group('teclado · r2: el foco no se pierde ni queda atrapado', () {
    late CanalAvisosPush canal;
    late FocusNode dos;

    Future<void> montar(WidgetTester tester) async {
      canal = CanalAvisosPush();
      addTearDown(canal.cerrar);
      dos = FocusNode(debugLabel: 'dos');
      addTearDown(dos.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [canalAvisosPushProvider.overrideWithValue(canal)],
          child: MaterialApp(
            theme: temaClaro(),
            home: Scaffold(
              body: Center(
                child: Column(
                  children: [
                    TextButton(onPressed: () {}, child: const Text('Uno')),
                    TextButton(focusNode: dos, onPressed: () {}, child: const Text('Dos')),
                  ],
                ),
              ),
            ),
            builder: (context, child) =>
                AvisoPushEnAppHost(activo: true, child: child ?? const SizedBox()),
          ),
        ),
      );
      dos.requestFocus();
      await tester.pump();
      expect(dos.hasPrimaryFocus, isTrue);
      canal.mostrar(_aviso('Tu pedido fue autorizado'));
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> tab(WidgetTester tester, {bool mayus = false}) async {
      if (mayus) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      if (mayus) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    testWidgets('Tab, Tab, Tab: aviso, ✕ y de vuelta al botón que tenía el foco', (tester) async {
      await montar(tester);

      await tab(tester);
      expect(dos.hasFocus, isFalse);
      await tab(tester);
      await tab(tester);

      expect(dos.hasPrimaryFocus, isTrue);
      expect(find.byKey(const Key('aviso_push_en_app_abrir')), findsOneWidget);
    });

    testWidgets('Mayús+Tab recorre al revés: ✕, aviso y de vuelta al botón', (tester) async {
      await montar(tester);

      await tab(tester);
      await tab(tester, mayus: true);

      expect(dos.hasPrimaryFocus, isTrue, reason: 'Mayús+Tab desde la tarjeta devuelve el foco');
    });

    testWidgets('cerrar el aviso con Enter en la ✕ devuelve el foco al botón de antes', (
      tester,
    ) async {
      await montar(tester);

      await tab(tester);
      await tab(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.byKey(const Key('aviso_push_en_app_abrir')), findsNothing);
      expect(dos.hasPrimaryFocus, isTrue, reason: 'el foco no se pierde al irse el aviso');
    });

    testWidgets('con el foco en la tarjeta el aviso no se va solo a los 8 s, y al soltarlo se va', (
      tester,
    ) async {
      await montar(tester);

      await tab(tester);
      await tester.pump(const Duration(seconds: 20));
      expect(find.byKey(const Key('aviso_push_en_app_abrir')), findsOneWidget);

      await tab(tester);
      await tab(tester);
      await tester.pump();
      expect(find.byKey(const Key('aviso_push_en_app_abrir')), findsNothing);
      expect(dos.hasPrimaryFocus, isTrue);
    });
  });
}
