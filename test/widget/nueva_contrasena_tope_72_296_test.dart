// Vista 15 «Nueva contraseña» (HU-AUTH-005), tope de 72 bytes en UTF-8 (#296, decisión del 02/10):
// al pasarse el campo dice «Es demasiado larga. Acortala.», «Guardar contraseña» queda apagado, no
// se recorta lo escrito y no hay contador. Si el servidor la rechaza por largo, el mismo texto.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _tope72 = 'Es demasiado larga. Acortala.';
const _etiquetaCumple = 'CONTRASEÑA NUEVA · ✓ CUMPLE LOS REQUISITOS';

late RecuperacionPasswordEnMemoria _recuperacion;

Finder _k(String k) => find.byKey(Key('confirmar_recuperacion_$k'));
Finder get _guardar => _k('guardar');

Future<void> _montar(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'Vieja1234'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
      dbLocalRepositoryProvider.overrideWithValue(DbLocalRepositoryEnMemoria()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  _recuperacion.simularEnlace(EnlaceRecuperacion.valido);
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, String nueva, {String? repetida}) async {
  await tester.enterText(_k('nueva'), nueva);
  await tester.enterText(_k('repetida'), repetida ?? nueva);
  await tester.pump();
}

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_guardar).onPressed != null;

String _texto(WidgetTester tester, String campo) =>
    tester.widget<TextField>(_k(campo)).controller!.text;

Future<void> _tocarGuardar(WidgetTester tester) async {
  await tester.ensureVisible(_guardar);
  await tester.tap(_guardar, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void _pantalla(WidgetTester tester, Size tam, {double texto = 1.0}) {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
  });

  group('Vista 15 — contraseña nueva de más de 72 bytes (#296)', () {
    for (final (descripcion, clave) in [
      ('73 caracteres ASCII', 'Aa1${'x' * 70}'),
      ('37 ñ (74 bytes en 37 caracteres)', 'ñ' * 37),
      ('emojis de 4 bytes: 21 caracteres, 75 bytes', 'Aa1${'😀' * 18}'),
      ('un pegado de 5000 caracteres', 'Aa1${'x' * 4997}'),
    ]) {
      testWidgets('$descripcion: el campo avisa y «Guardar contraseña» queda apagado', (
        tester,
      ) async {
        await _montar(tester);

        await _escribir(tester, clave);

        expect(find.text(_tope72), findsOneWidget);
        expect(_habilitado(tester), isFalse);
        expect(_texto(tester, 'nueva'), clave, reason: 'nunca se recorta lo que escribió');
        expect(find.text(_etiquetaCumple), findsNothing);

        await _tocarGuardar(tester);
        expect(_recuperacion.actualizaciones, isEmpty);
        expect(_k('guardando'), findsNothing);
      });
    }

    testWidgets('72 bytes justos entran: sin aviso, «Guardar» habilitado y la contraseña se '
        'guarda', (tester) async {
      await _montar(tester);
      final justa = 'Aa1${'x' * 69}';

      await _escribir(tester, justa);

      expect(find.text(_tope72), findsNothing);
      expect(find.text(_etiquetaCumple), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      await _tocarGuardar(tester);
      expect(_recuperacion.actualizaciones, [justa]);
    });

    testWidgets('al acortarla el aviso se va y «Guardar» vuelve a andar', (tester) async {
      await _montar(tester);
      await _escribir(tester, 'Aa1${'x' * 70}');
      expect(_habilitado(tester), isFalse);

      await _escribir(tester, 'Aa1${'x' * 69}');

      expect(find.text(_tope72), findsNothing);
      expect(_habilitado(tester), isTrue);
      await _tocarGuardar(tester);
      expect(_recuperacion.actualizaciones, ['Aa1${'x' * 69}']);
    });

    testWidgets('solo la de arriba pasa el tope: la de repetir no lleva el aviso', (tester) async {
      await _montar(tester);

      await _escribir(tester, 'Aa1${'x' * 70}');

      expect(find.text(_tope72), findsOneWidget, reason: 'un solo aviso, en el campo de arriba');
      expect(find.text('Las contraseñas no coinciden'), findsNothing);
    });

    testWidgets('sin contador a la vista ni tope que corte lo que se escribe', (tester) async {
      await _montar(tester);
      await _escribir(tester, 'Aa1${'x' * 70}');

      for (final campo in ['nueva', 'repetida']) {
        final decoracion = tester.widget<TextField>(_k(campo)).decoration!;
        expect(tester.widget<TextField>(_k(campo)).maxLength, isNull);
        expect(decoracion.counterText, isNull);
        expect(decoracion.counter, isNull);
      }
      expect(find.textContaining('73'), findsNothing);
      expect(find.textContaining('/72'), findsNothing);
    });

    testWidgets('«Listo» del teclado con la de más de 72 bytes no envía y no pisa el aviso', (
      tester,
    ) async {
      await _montar(tester);
      await _escribir(tester, 'Aa1${'x' * 70}');

      await tester.tap(_k('repetida'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_recuperacion.actualizaciones, isEmpty);
      expect(find.text(_tope72), findsOneWidget);
      expect(find.text('Todavía no cumple los requisitos de abajo.'), findsNothing);
    });

    testWidgets('si el servidor la rechaza por larga, el campo dice lo mismo, «Guardar» no queda '
        'ocupado y se puede corregir', (tester) async {
      await _montar(tester);
      _recuperacion.fallaAlActualizar = const PasswordDemasiadoLargaException();
      await _escribir(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(find.text(_tope72), findsOneWidget);
      expect(_k('guardando'), findsNothing);
      expect(_habilitado(tester), isTrue);
      expect(find.text('Guardar contraseña'), findsOneWidget);

      // Escribir de nuevo saca el aviso viejo del servidor.
      await _escribir(tester, 'NuevaClave2');
      expect(find.text(_tope72), findsNothing);

      _recuperacion.fallaAlActualizar = null;
      await _tocarGuardar(tester);
      expect(_recuperacion.actualizaciones, ['NuevaClave2']);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });

    testWidgets('dos toques seguidos en «Guardar» con una de 72 bytes mandan una sola vez', (
      tester,
    ) async {
      await _montar(tester);
      final demora = Completer<void>();
      _recuperacion.demoraAlActualizar = demora;
      await _escribir(tester, 'Aa1${'x' * 69}');

      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();
      await tester.tap(_guardar, warnIfMissed: false);
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();

      expect(_recuperacion.actualizaciones, ['Aa1${'x' * 69}']);
    });

    testWidgets('volver atrás y reentrar con el enlace: los campos vuelven vacíos y sin aviso', (
      tester,
    ) async {
      await _montar(tester);
      await _escribir(tester, 'Aa1${'x' * 70}');
      expect(find.text(_tope72), findsOneWidget);

      await tester.tap(_k('atras'));
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);

      _recuperacion.simularEnlace(EnlaceRecuperacion.valido);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);
      expect(_texto(tester, 'nueva'), isEmpty);
      expect(find.text(_tope72), findsNothing);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets('360x640 con el texto al 200 %: el aviso se lee entero y no hay overflow', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640), texto: 2.0);
      await _montar(tester);

      await _escribir(tester, 'Aa1${'x' * 70}');
      await tester.ensureVisible(find.text(_tope72));
      await tester.pump();

      expect(find.text(_tope72), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
