// QA del delta de la vista 14 (#223), decisión de Cristian del 01/10: el aviso de impacto dice
// «Tus datos guardados en este teléfono se conservan.» y el texto viejo no queda en ningún estado.
// Desde el 02/10 (#272) el aviso solo informa: sin casilla «Entiendo el impacto» ni ⚠.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _aviso = 'Tus datos guardados en este teléfono se conservan.';
final _avisoKey = find.byKey(const Key('recuperacion_password_aviso'));

Future<AuthRemoteDataSourceEnMemoria> _montar(WidgetTester tester) async {
  final remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(theme: temaClaro(), home: const RecuperacionPasswordPage()),
    ),
  );
  await tester.pumpAndSettle();
  return remoto;
}

void _sinTextoViejo() {
  for (final viejo in const ['backup', 'restaurar', 'no podrás abrirlos', 'abrirlos ahí']) {
    expect(find.textContaining(viejo, findRichText: true), findsNothing, reason: viejo);
  }
}

/// Ni casilla ni ⚠ (#272).
void _sinCasillaNiAdvertencia() {
  expect(find.byType(Checkbox), findsNothing);
  expect(find.byType(CheckboxListTile), findsNothing);
  expect(find.textContaining('Entiendo el impacto'), findsNothing);
  expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  expect(find.byIcon(Icons.warning_amber), findsNothing);
  expect(find.byIcon(Icons.warning), findsNothing);
}

Future<void> _llenarYEnviar(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const Key('recuperacion_password_email')), email);
  final enviar = find.byKey(const Key('recuperacion_password_enviar'));
  await tester.ensureVisible(enviar);
  await tester.tap(enviar);
  await tester.pumpAndSettle();
}

void main() {
  group('QA #223 — aviso «se conservan» en todos los estados', () {
    testWidgets('A01 y A02: literal exacto, una sola vez, sin texto viejo y sin casilla ni ⚠', (
      tester,
    ) async {
      await _montar(tester);
      expect(find.text(_aviso), findsOneWidget);
      _sinTextoViejo();
      _sinCasillaNiAdvertencia();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        'lucia@correo.com',
      );
      await tester.pump();
      expect(find.text(_aviso), findsOneWidget);
      _sinTextoViejo();
      _sinCasillaNiAdvertencia();
    });

    testWidgets('A03 email inválido y A06 sin conexión conservan el aviso nuevo', (tester) async {
      final remoto = await _montar(tester);
      await _llenarYEnviar(tester, 'lucia@');
      expect(find.text('Revisá el email: parece incompleto.'), findsOneWidget);
      expect(find.text(_aviso), findsOneWidget);
      _sinTextoViejo();
      _sinCasillaNiAdvertencia();

      remoto.simularSinConexion = true;
      await _llenarYEnviar(tester, 'lucia@correo.com');
      expect(find.textContaining('Necesitás conexión'), findsOneWidget);
      expect(find.text(_aviso), findsOneWidget);
      _sinTextoViejo();
      _sinCasillaNiAdvertencia();
    });

    testWidgets('A05 éxito: pantalla aparte sin el aviso de impacto ni el texto viejo', (
      tester,
    ) async {
      await _montar(tester);
      await _llenarYEnviar(tester, 'lucia@correo.com');
      expect(find.textContaining('te enviamos un enlace'), findsOneWidget);
      expect(_avisoKey, findsNothing);
      _sinTextoViejo();
    });

    for (final (tam, texto) in const [(Size(360, 640), 2.0), (Size(412, 915), 2.0)]) {
      testWidgets('el aviso a 200 % en ${tam.width.toInt()}x${tam.height.toInt()}: entero, sin '
          'overflow y con la accesibilidad', (tester) async {
        tester.view
          ..physicalSize = tam
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = texto;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final semantica = tester.ensureSemantics();
        await _montar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(_aviso), findsOneWidget);
        _sinCasillaNiAdvertencia();
        expect(tester.getRect(_avisoKey).right, lessThanOrEqualTo(tam.width));
        expect(find.bySemanticsLabel(RegExp('se conservan')), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  });
}
