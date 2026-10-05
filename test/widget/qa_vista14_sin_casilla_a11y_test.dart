// QA de la vista 14 sin casilla (#272, HU-AUTH-004): la accesibilidad de cada estado en los dos
// tamaños de referencia (360×640 y 412×915) y el anuncio de los errores. Los tests existentes miran
// 390×844; acá se completan los otros dos tamaños. Fuente de prueba (Ahem): con las reales,
// `textContrastGuideline` da falsos negativos en letra chica (la geometría va en el otro archivo).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _incompleto = 'Revisá el email: parece incompleto.';
const _sinConexion = 'Necesitás conexión para solicitar la recuperación';
const _mensajeNeutro = 'Si el email está registrado, te enviamos un enlace de recuperación';

Finder _k(String key) => find.byKey(Key(key));

Future<void> _montar(
  WidgetTester tester,
  AuthRemoteDataSourceEnMemoria remote, {
  required Size tamano,
  double escala = 1,
}) async {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(theme: temaClaro(), home: const RecuperacionPasswordPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, String email) async {
  await tester.enterText(_k('recuperacion_password_email'), email);
  await tester.pump();
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.ensureVisible(_k('recuperacion_password_enviar'));
  await tester.tap(_k('recuperacion_password_enviar'));
}

/// El estado de cada artboard con datos de la vista (A01 a A06; A02 es A01 con el email escrito).
final _estados = <String, Future<void> Function(WidgetTester, Size)>{
  'A01 principal': (tester, tam) async {
    await _montar(tester, AuthRemoteDataSourceEnMemoria(credenciales: const {}), tamano: tam);
  },
  'A02 con el email escrito': (tester, tam) async {
    await _montar(tester, AuthRemoteDataSourceEnMemoria(credenciales: const {}), tamano: tam);
    await _escribir(tester, 'lucia.silva@correo.com');
  },
  'A03 email inválido': (tester, tam) async {
    await _montar(tester, AuthRemoteDataSourceEnMemoria(credenciales: const {}), tamano: tam);
    await _escribir(tester, 'lucia@');
    await _enviar(tester);
    await tester.pumpAndSettle();
  },
  'A04 enviando': (tester, tam) async {
    final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
      ..demoraRecuperacion = Completer<void>();
    await _montar(tester, remote, tamano: tam);
    await _escribir(tester, 'lucia.silva@correo.com');
    await _enviar(tester);
    await tester.pump();
    addTearDown(() => remote.demoraRecuperacion?.complete());
  },
  'A05 éxito neutro': (tester, tam) async {
    await _montar(tester, AuthRemoteDataSourceEnMemoria(credenciales: const {}), tamano: tam);
    await _escribir(tester, 'lucia.silva@correo.com');
    await _enviar(tester);
    await tester.pumpAndSettle();
  },
  'A06 sin conexión': (tester, tam) async {
    final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})..simularSinConexion = true;
    await _montar(tester, remote, tamano: tam);
    await _escribir(tester, 'lucia.silva@correo.com');
    await _enviar(tester);
    await tester.pumpAndSettle();
  },
};

void main() {
  group('QA #272 · vista 14 · accesibilidad de cada estado en 360×640 y 412×915', () {
    for (final tam in const [Size(360, 640), Size(412, 915)]) {
      for (final MapEntry(key: nombre, value: preparar) in _estados.entries) {
        testWidgets('$nombre en ${tam.width.toInt()}×${tam.height.toInt()}: toque, etiquetas y '
            'contraste', (tester) async {
          final semantica = tester.ensureSemantics();
          await preparar(tester, tam);

          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  });

  group('QA #272 · vista 14 · los errores se anuncian', () {
    testWidgets('A06: el aviso «Necesitás conexión…» es una región viva y deja el botón a mano', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..simularSinConexion = true;
      await _montar(tester, remote, tamano: const Size(360, 640));
      await _escribir(tester, 'lucia.silva@correo.com');
      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(find.text(_sinConexion), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(_sinConexion),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
        reason: 'el aviso aparece tras tocar el botón: sin región viva, TalkBack no lo lee',
      );
      expect(tester.widget<FilledButton>(_k('recuperacion_password_enviar')).onPressed, isNotNull);
    });

    testWidgets('A03: el error del campo está en el árbol de semántica y el botón sigue a mano', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        tamano: const Size(360, 640),
      );
      await _escribir(tester, 'lucia@');
      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('parece incompleto')), findsWidgets);
      expect(find.text(_incompleto), findsOneWidget);
      expect(tester.widget<FilledButton>(_k('recuperacion_password_enviar')).onPressed, isNotNull);
      semantica.dispose();
    });
  });

  group('QA #272 · vista 14 · casos límite de entrada que faltaban', () {
    for (final email in ['lucíá.ñandú@correo.com', 'lucia😀@correo.com']) {
      testWidgets('«$email» (Ñ, acentos o emoji): no rompe la pantalla y no revela nada', (
        tester,
      ) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montar(tester, remote, tamano: const Size(360, 640));
        await _escribir(tester, email);
        await _enviar(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // O la valida y manda el neutro, o dice «parece incompleto»: nunca otra cosa.
        expect(
          find.text(_mensajeNeutro).evaluate().length + find.text(_incompleto).evaluate().length,
          1,
        );
      });
    }

    testWidgets('texto pegado de 5000 caracteres: A03 sin desborde y sin mandarlo', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montar(tester, remote, tamano: const Size(360, 640), escala: 2);
      await _escribir(tester, '${'a' * 5000}@correo.com');
      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_mensajeNeutro), findsNothing);
      expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
    });

    testWidgets('email válido seguido de A03 y otra vez válido: al final llega al éxito', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montar(tester, remote, tamano: const Size(412, 915));
      await _escribir(tester, 'lucia@');
      await _enviar(tester);
      await tester.pumpAndSettle();
      expect(find.text(_incompleto), findsOneWidget);

      await _escribir(tester, 'lucia.silva@correo.com');
      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(find.text(_incompleto), findsNothing);
    });
  });
}
