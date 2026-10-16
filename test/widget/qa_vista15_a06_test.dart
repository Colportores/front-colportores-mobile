// QA de la vista 15, artboard 15-A06 «enlace que no sirve» (HU-AUTH-005, #247). Complementa
// `confirmar_recuperacion_password_page_test.dart`: A06 en los tamaños del checklist (360x640 y
// 412x915, texto al 100 % y al 200 %) y el atrás del sistema dentro de la app. Una sola pantalla
// para el enlace vencido y el ya usado (decisión de Cristian, 02/10): 15-A07 se quitó.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _titulo = TextosConfirmacionRecuperacion.vencido;
const _rotulo = TextosConfirmacionRecuperacion.rotuloEnlaceNoValido;

void _pantalla(WidgetTester tester, Size tam, double texto) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Relación de contraste de WCAG entre dos colores opacos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
});

Future<void> _montarA06(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(
        RecuperacionPasswordEnMemoria(),
      ),
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      home: const ConfirmarRecuperacionPasswordPage(enlace: EnlaceRecuperacion.vencido),
    ),
  ),
);

void main() {
  group('QA #247 — 15-A06 en los tamaños del checklist', () {
    for (final (tam, texto) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 2.0),
      (Size(412, 915), 1.0),
      (Size(412, 915), 2.0),
    ]) {
      testWidgets('${tam.width.toInt()}x${tam.height.toInt()} a ${(texto * 100).toInt()} %: textos '
          'enteros, las dos salidas, sin overflow y accesible', (tester) async {
        _pantalla(tester, tam, texto);
        final semantica = tester.ensureSemantics();
        await _cargarFuentes(tester);
        await _montarA06(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(_rotulo), findsOneWidget);
        expect(find.text(_titulo), findsOneWidget);
        expect(find.text('Solicitar un enlace nuevo'), findsOneWidget);
        expect(find.text('Volver al login'), findsOneWidget);
        expect(find.textContaining('expiró'), findsNothing);
        expect(find.textContaining('ya fue utilizado'), findsNothing);
        expect(find.byType(TextField), findsNothing, reason: 'no hay formulario');
        for (final t in [_rotulo, _titulo]) {
          expect(tester.getRect(find.text(t)).right, lessThanOrEqualTo(tam.width));
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        if (texto >= 2) {
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        } else {
          // A 10 px la guía de Flutter mide el borde suavizado de las letras y da ~1,4 aunque el
          // color cumple: el rótulo se mide por sus colores, y la guía completa corre al 200 %.
          final fondo = Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor;
          for (final t in [_rotulo, _titulo]) {
            final color = tester.widget<Text>(find.text(t)).style!.color!;
            expect(_contraste(color, fondo), greaterThanOrEqualTo(4.5), reason: t);
          }
        }

        // Captura fuera del repo (.dart_tool está en .gitignore).
        await tester.runAsync(() async {
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final img = await render.toImage();
          final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
          File(
            '${dir.path}/264_a06_${tam.width.toInt()}x${tam.height.toInt()}_$texto.png',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
        });
        semantica.dispose();
      });
    }
  });

  testWidgets('A06 dentro de la app: el atrás del sistema también lleva al login', (tester) async {
    final recuperacion = RecuperacionPasswordEnMemoria();
    final container = ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(recuperacion),
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ColportoresApp()),
    );
    await tester.pumpAndSettle();

    recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
    await tester.pumpAndSettle();
    expect(find.text(_titulo), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_titulo), findsNothing);
    expect(find.byKey(const Key('login_enviar')), findsOneWidget);
  });
}
