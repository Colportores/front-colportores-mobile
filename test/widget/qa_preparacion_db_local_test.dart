// QA de la vista 13 (#222, HU-AUTH-009): casos límite de la pantalla de preparación que
// `preparacion_db_local_page_test.dart` no cubre: la contraseña de confirmación vacía o de solo
// espacios, sin conexión al confirmarla y el doble toque.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_ajustes_sistema.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/preparacion_db_local_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/password_para_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _password = 'Secreto123';

late DbLocalRepositoryEnMemoria _db;
late AuthRemoteDataSourceEnMemoria _remoto;

/// El abridor de ajustes, con lo que devolvió cada apertura y una espera para el doble toque.
final class _AbridorFalso implements AbridorAjustesSistema {
  final llamadas = <String>[];
  bool resultado = true;
  bool lanza = false;
  Completer<void>? espera;

  Future<bool> _abrir(String cual) async {
    llamadas.add(cual);
    await espera?.future;
    if (lanza) throw StateError('el abridor falló');
    return resultado;
  }

  @override
  Future<bool> abrirSeguridad() => _abrir('seguridad');

  @override
  Future<bool> abrirAlmacenamiento() => _abrir('almacenamiento');
}

late _AbridorFalso _ajustes;

Finder get _principal => find.byType(InicioPage);
Finder _boton(String key) => find.byKey(Key(key));

/// Entra con email y contraseña y monta la app, que prepara la DB local. Con [restaurada], como
/// una sesión que ya estaba al abrir la app: sin la contraseña del login en memoria.
Future<ProviderContainer> _entrar(
  WidgetTester tester, {
  bool esperar = true,
  bool restaurada = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_remoto),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(_db),
      abridorAjustesSistemaProvider.overrideWithValue(_ajustes),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container.read(sesionProvider.notifier).iniciarSesion(email: _email, password: _password);
  if (restaurada) container.read(passwordParaDbLocalProvider).olvidar();

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  if (esperar) await tester.pumpAndSettle();
  return container;
}

bool _botonHabilitado(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_boton(key)).onPressed != null;

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_boton(key));
  await tester.tap(_boton(key));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _db = DbLocalRepositoryEnMemoria();
    _ajustes = _AbridorFalso();
    _remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password});
  });

  group('QA #222 — confirmar la contraseña (sesión restaurada)', () {
    for (final entrada in ['', '     ', '	 ']) {
      testWidgets('contraseña "${entrada.trim().isEmpty ? 'vacía o solo espacios' : entrada}" '
          '(${entrada.length} caracteres): no pasa y deja reintentar', (tester) async {
        await _entrar(tester, restaurada: true);
        await tester.enterText(_boton('preparacion_db_password'), entrada);
        await _tocar(tester, 'preparacion_db_confirmar_password');

        expect(tester.takeException(), isNull);
        expect(_principal, findsNothing);
        expect(_db.llamadas, isNot(contains('crearDek')));
        expect(find.text(TextosPreparacionDbLocal.passwordIncorrecta), findsOneWidget);
        expect(_botonHabilitado(tester, 'preparacion_db_confirmar_password'), isTrue);
      });
    }

    testWidgets(
      'sin conexión al confirmar: dice "Necesitás conexión para confirmar tu contraseña."',
      (tester) async {
        await _entrar(tester, restaurada: true);
        _remoto.simularSinConexion = true;
        await tester.enterText(_boton('preparacion_db_password'), _password);
        await _tocar(tester, 'preparacion_db_confirmar_password');

        expect(find.text('Necesitás conexión para confirmar tu contraseña.'), findsOneWidget);
        expect(_principal, findsNothing);
        expect(_db.llamadas, isNot(contains('crearDek')));
        expect(_botonHabilitado(tester, 'preparacion_db_confirmar_password'), isTrue);

        _remoto.simularSinConexion = false;
        await _tocar(tester, 'preparacion_db_confirmar_password');
        expect(_principal, findsOneWidget);
      },
    );

    testWidgets('lo tipeado no se pierde después de un error', (tester) async {
      await _entrar(tester, restaurada: true);
      await tester.enterText(_boton('preparacion_db_password'), 'equivocada');
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(find.text(TextosPreparacionDbLocal.passwordIncorrecta), findsOneWidget);
      expect(find.text('equivocada'), findsOneWidget);
    });
  });
}
