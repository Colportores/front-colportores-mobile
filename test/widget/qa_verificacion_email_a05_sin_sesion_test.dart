// QA de la vista 12, artboard A05 «Ya verificado» (#279): la variante SIN sesión («Ir al login»), que
// `qa_verificacion_email_a05_test.dart` mide solo con sesión en accesibilidad y tamaños, y los casos
// límite de navegación que ahí quedan con sesión (doble toque, atrás del sistema, segundo plano).
// Fuente de prueba (Ahem): con las reales `textContrastGuideline` da falsos negativos en letra chica.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';
const _titulo = 'Tu email ya está verificado';
const _texto = 'Ya podés entrar a tu inicio.';

final _boton = find.byKey(const Key('verificacion_email_ir_login'));
final _abajo = find.byKey(const Key('pantalla_de_abajo'));

void _pantalla(WidgetTester tester, Size tamano, double escala) {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// El `ProviderScope` va como argumento directo de `pumpWidget` (ver `app_test.dart`): sin sesión.
Future<void> _montar(WidgetTester tester, Widget home) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(theme: temaClaro(), home: home),
  ),
);

/// A05 sola, sin sesión (como llega con el enlace de un correo ya usado y sin sesión abierta).
Future<void> _a05Sola(WidgetTester tester, Size tamano, double escala) async {
  _pantalla(tester, tamano, escala);
  await _montar(
    tester,
    const VerificacionEmailPage(
      email: _correo,
      estadoInicial: EstadoVerificacionEmail.yaVerificado,
    ),
  );
  await tester.pumpAndSettle();
}

/// A05 apilada sobre otra pantalla, como la deja `app.dart`: así «Ir al login» tiene adónde salir.
Future<void> _a05SobreOtraPantalla(WidgetTester tester) async {
  _pantalla(tester, const Size(390, 844), 1);
  await _montar(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('pantalla_de_abajo'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const VerificacionEmailPage(
                  email: _correo,
                  estadoInicial: EstadoVerificacionEmail.yaVerificado,
                ),
              ),
            ),
            child: const Text('abrir A05'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_abajo);
  await tester.pumpAndSettle();
  expect(find.text(_titulo), findsOneWidget);
}

void main() {
  group('QA #279 · 12-A05 sin sesión · accesibilidad y tamaños', () {
    for (final (nombre, tam) in const [('360×640', Size(360, 640)), ('412×915', Size(412, 915))]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('sin sesión en $nombre, texto $escala: sin overflow y accesible', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await _a05Sola(tester, tam, escala);

          expect(tester.takeException(), isNull);
          expect(find.text(_texto), findsOneWidget);
          expect(find.text('Ir al login'), findsOneWidget);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }

    // skip: QA #279 — el título de A05 («Tu email ya está verificado») es un `Text` suelto: no se
    // marca como encabezado, así que TalkBack/VoiceOver no lo ofrecen en la navegación por encabezados
    // (los títulos de la vista 14, por ejemplo, sí llevan `Semantics(header: true)`).
    testWidgets('el título de A05 es un encabezado para el lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await _a05Sola(tester, const Size(360, 640), 1);

      expect(
        tester.getSemantics(find.byKey(const Key('verificacion_email_titulo'))),
        isSemantics(isHeader: true),
      );
      semantica.dispose();
    }, skip: true);
  });

  group('QA #279 · 12-A05 sin sesión · navegación y casos límite', () {
    testWidgets('«Ir al login» dos veces seguidas sale una sola vez, sin errores', (tester) async {
      await _a05SobreOtraPantalla(tester);

      await tester.tap(_boton);
      await tester.tap(_boton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_titulo), findsNothing);
      expect(_abajo, findsOneWidget);
    });

    testWidgets('el atrás del sistema vuelve a la pantalla de abajo y no deja nada pendiente', (
      tester,
    ) async {
      await _a05SobreOtraPantalla(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(_titulo), findsNothing);
      expect(_abajo, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segundo plano y vuelta, pasado más de un minuto: la pantalla sigue ahí', (
      tester,
    ) async {
      await _a05SobreOtraPantalla(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 90));

      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(_texto), findsOneWidget);
      expect(_abajo, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el texto al 200 % el botón «Ir al login» se alcanza y sale', (tester) async {
      await _a05SobreOtraPantalla(tester);
      _pantalla(tester, const Size(360, 640), 2);
      await tester.pumpAndSettle();

      await tester.ensureVisible(_boton);
      await tester.tap(_boton);
      await tester.pumpAndSettle();

      expect(find.text(_titulo), findsNothing);
      expect(_abajo, findsOneWidget);
    });
  });
}
