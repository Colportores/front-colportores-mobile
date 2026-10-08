import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_envio_recuperacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/ultimo_envio_recuperacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';

/// [RecuperacionPasswordPage] aislada (sin [ColportoresApp]) — mismo criterio que
/// `login_page_test.dart`.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPagina(
  WidgetTester tester, {
  ThemeData? tema,
  required AuthRemoteDataSourceEnMemoria remote,
  UltimoEnvioRecuperacionRepository? ultimoEnvio,
  DateTime Function()? ahora,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      if (ultimoEnvio != null)
        ultimoEnvioRecuperacionRepositoryProvider.overrideWithValue(ultimoEnvio),
    ],
    child: MaterialApp(
      theme: tema ?? temaClaro(),
      home: RecuperacionPasswordPage(ahora: ahora ?? DateTime.now),
    ),
  ),
);

/// El reloj de la pantalla en los tests: la hora de ahora, que el test adelanta a mano.
final class _Reloj {
  _Reloj(this.ahora);

  DateTime ahora;

  DateTime call() => ahora;

  void avanzar(Duration cuanto) => ahora = ahora.add(cuanto);
}

/// Pasa [cuanto] tiempo: el reloj de la pantalla y el del test (donde corre su timer).
Future<void> _pasar(WidgetTester tester, _Reloj reloj, Duration cuanto) async {
  reloj.avanzar(cuanto);
  await tester.pump(cuanto);
}

/// Lee la hora guardada cuando el test lo dice: para tocar «Enviar» mientras todavía se lee.
final class _UltimoEnvioDemorado implements UltimoEnvioRecuperacionRepository {
  _UltimoEnvioDemorado(this._lectura);

  final Completer<DateTime?> _lectura;
  DateTime? guardado;

  @override
  Future<DateTime?> leer() => _lectura.future;

  @override
  Future<void> guardar(DateTime cuando) async => guardado = cuando;
}

const _mensajeNeutro = 'Si el email está registrado, te enviamos un enlace de recuperación';
const _textoAviso = 'Tus datos guardados en este teléfono se conservan.';

Future<void> _completar(WidgetTester tester, {String email = 'lucia.silva@correo.com'}) async {
  await tester.enterText(find.byKey(const Key('recuperacion_password_email')), email);
  await tester.pump();
}

/// Decisión de Cristian del 02/10 (#272): ni la casilla «Entiendo el impacto» ni el ⚠.
void _sinCasillaNiAdvertencia() {
  expect(find.byKey(const Key('recuperacion_password_checkbox')), findsNothing);
  expect(find.byType(Checkbox), findsNothing);
  expect(find.byType(CheckboxListTile), findsNothing);
  expect(find.textContaining('Entiendo el impacto'), findsNothing);
  expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  expect(find.byIcon(Icons.warning_amber), findsNothing);
  expect(find.byIcon(Icons.warning), findsNothing);
}

/// Con el texto al 200 % los botones quedan fuera de pantalla: sin esto el toque no llega.
Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
}

OutlinedButton _reenviar(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byKey(const Key('recuperacion_password_reenviar')));

/// Lo escrito en el campo (el hint del campo es otro email: `find.text` lo confundiría).
String _textoDelCampo(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email'))).controller!.text;

FilledButton _enviar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')));

/// La página dentro de un Navigator con una ruta debajo, para probar «Volver al login» y el atrás.
Future<void> _montarSobreLogin(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  UltimoEnvioRecuperacionRepository? ultimoEnvio,
  DateTime Function()? ahora,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        if (ultimoEnvio != null)
          ultimoEnvioRecuperacionRepositoryProvider.overrideWithValue(ultimoEnvio),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_recuperacion'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => RecuperacionPasswordPage(ahora: ahora ?? DateTime.now),
                  ),
                ),
                child: const Text('pantalla de abajo'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir_recuperacion')));
  await tester.pumpAndSettle();
}

void main() {
  group('Vista 14 (#223) — un estado por artboard', () {
    testWidgets(
      'A01 principal: eyebrow, título, apoyo, aviso informativo, campo y botón habilitado, '
      'sin casilla ni ⚠',
      (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();

        expect(find.text('RECUPERAR CONTRASEÑA'), findsOneWidget);
        expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
        expect(
          find.text('Ingresá tu email y te enviamos un enlace para restablecerla.'),
          findsOneWidget,
        );
        expect(find.text(_textoAviso), findsOneWidget);
        expect(find.text('CORREO'), findsOneWidget);
        _sinCasillaNiAdvertencia();
        expect(find.text('Enviar enlace de recuperación'), findsOneWidget);
        expect(_enviar(tester).onPressed, isNotNull, reason: 'ya no hay casilla que lo apague');
      },
    );

    testWidgets('A02 (el canvas dibuja la casilla marcada; sin casilla es el mismo formulario con '
        'el email completo): el botón sigue habilitado', (tester) async {
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      await _completar(tester);

      expect(_textoDelCampo(tester), 'lucia.silva@correo.com');
      _sinCasillaNiAdvertencia();
      expect(find.text(_textoAviso), findsOneWidget);
      expect(_enviar(tester).onPressed, isNotNull);
    });

    for (final email in ['lucia', 'lucia@', 'lucia@correo', 'lu cia@correo.com']) {
      testWidgets(
        'A03 email inválido («$email»): «Revisá el email: parece incompleto.», sin enviar y '
        'con el botón habilitado',
        (tester) async {
          final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
          await _montarPagina(tester, remote: remote);
          await tester.pumpAndSettle();

          await _completar(tester, email: email);
          await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
          await tester.pumpAndSettle();

          expect(find.text('Revisá el email: parece incompleto.'), findsOneWidget);
          expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
          expect(_enviar(tester).onPressed, isNotNull);
          expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
        },
      );
    }

    testWidgets('A03 corregir el email y volver a enviar lleva al éxito', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester, email: 'lucia@');
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        'lucia@correo.com',
      );
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Revisá el email: parece incompleto.'), findsNothing);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
    });

    testWidgets('A04 enviando: «Enviando…», campo, botón y atrás deshabilitados', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..demoraRecuperacion = Completer<void>();
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester);

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pump();

      expect(find.text('Enviando…'), findsOneWidget);
      expect(_enviar(tester).onPressed, isNull);
      expect(
        tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email'))).enabled,
        isFalse,
      );
      _sinCasillaNiAdvertencia();
      expect(
        tester.widget<IconButton>(find.byKey(const Key('recuperacion_password_atras'))).onPressed,
        isNull,
      );

      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
    });

    testWidgets(
      'A05 éxito: pantalla aparte con el mensaje de la HU, el apoyo del spam, «Reenviar en '
      '60s» y «Volver al login»',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completar(tester);

        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.text(_mensajeNeutro), findsOneWidget);
        expect(find.text('Si no lo encontrás, revisá la carpeta de spam.'), findsOneWidget);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(find.text('Volver al login'), findsOneWidget);
        expect(find.text('¿Olvidaste tu contraseña?'), findsNothing, reason: 'es otra pantalla');
        expect(find.byKey(const Key('recuperacion_password_enviar')), findsNothing);
      },
    );

    testWidgets('A05 la cuenta regresiva baja y «Reenviar enlace» vuelve a enviar y reinicia los '
        '60 s', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 18));
      expect(find.text('Reenviar en 42s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 42));
      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.pump();
      await tester.pump();

      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 2);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
    });

    testWidgets('A05 «Reenviar» tocado dos veces seguidas envía una sola vez', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      remote.demoraRecuperacion = Completer<void>();

      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.tap(
        find.byKey(const Key('recuperacion_password_reenviar')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.text('Enviando…'), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNull);

      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 2);
    });

    testWidgets('A05 si el reenvío falla por falta de conexión, lo dice en la misma pantalla y '
        'deja reintentar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));

      remote.simularSinConexion = true;
      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNotNull);

      remote.simularSinConexion = false;
      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.pumpAndSettle();
      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsNothing);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
    });

    testWidgets('A05 «Volver al login» y el atrás de A01 cierran la pantalla', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      final ahora = DateTime(2026, 10, 8, 10);
      await _montarSobreLogin(tester, remote: remote, ahora: () => ahora);
      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recuperacion_password_volver_login')));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(find.text('pantalla de abajo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('abrir_recuperacion')));
      await tester.pumpAndSettle();
      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(
        _textoDelCampo(tester),
        isEmpty,
        reason: 'al volver a entrar el correo no se guarda: solo la hora del envío (#281)',
      );
      expect(
        _enviar(tester).onPressed,
        isNull,
        reason: 'los 60 s del envío siguen corriendo aunque se haya salido de la pantalla (#281)',
      );
      expect(find.text('Podés pedir otro enlace en 60s.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
    });

    testWidgets('A05 al volver de segundo plano la cuenta regresiva sigue la hora real, sin perder '
        'el cooldown', (tester) async {
      var ahora = DateTime(2026, 9, 30, 10);
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(remote),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: RecuperacionPasswordPage(ahora: () => ahora),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _completar(tester);
      await _tocar(tester, 'recuperacion_password_enviar');
      await tester.pumpAndSettle();
      expect(find.text('Reenviar en 60s'), findsOneWidget);

      // Segundo plano 45 s: el timer no corrió, pero el reloj sí.
      ahora = ahora.add(const Duration(seconds: 45));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Reenviar en 15s'), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNull, reason: 'todavía no pasaron los 60 s');

      ahora = ahora.add(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Reenviar enlace'), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNotNull);
    });

    testWidgets('A06 sin conexión: «Necesitás conexión…» con el email que se escribió y el botón '
        'habilitado; al volver la conexión, envía', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..simularSinConexion = true;
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester);

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
      expect(_textoDelCampo(tester), 'lucia.silva@correo.com');
      _sinCasillaNiAdvertencia();
      expect(_enviar(tester).onPressed, isNotNull);

      remote.simularSinConexion = false;
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
    });

    testWidgets('el email de la sesión llega precargado y se puede cambiar', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: const RecuperacionPasswordPage(emailInicial: 'ana@example.com'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ana@example.com'), findsOneWidget);
    });
  });

  group('Vista 14 (#223) — accesibilidad y tamaños', () {
    final estados = <String, Future<void> Function(WidgetTester)>{
      'A01 principal': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
      },
      'A02 sin casilla, con el email completo': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
        await _completar(tester);
      },
      'A03 email inválido': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
        await _completar(tester, email: 'lucia@');
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
      },
      'A04 enviando': (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
          ..demoraRecuperacion = Completer<void>();
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pump();
      },
      'A05 éxito': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
        await _completar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
      },
      'A05 éxito con error al reenviar': (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 60));
        remote.simularSinConexion = true;
        await _tocar(tester, 'recuperacion_password_reenviar');
        await tester.pumpAndSettle();
      },
      'A06 sin conexión': (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
          ..simularSinConexion = true;
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
      },
      // Estado del escenario «Edge – volver a “Olvidé mi contraseña” con la espera vigente» (#281):
      // el canvas no lo dibuja, lo pide la HU.
      'A01 con la espera vigente (#281)': (tester) async {
        final ahora = DateTime.utc(2026, 10, 8, 10);
        await _montarPagina(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
          ultimoEnvio: UltimoEnvioRecuperacionEnMemoria(
            ahora.subtract(const Duration(seconds: 20)),
          ),
          ahora: () => ahora,
        );
        await tester.pumpAndSettle();
        await _completar(tester);
      },
    };

    for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
      testWidgets('$nombre: tamaño de toque, etiquetas y contraste en 390x844', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await preparar(tester);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      for (final (tam, escala) in [
        (const Size(360, 640), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 2.0),
        (const Size(360, 740), 2.0),
      ]) {
        testWidgets('$nombre: sin overflow en ${tam.width.toInt()}x${tam.height.toInt()} con texto '
            '$escala', (tester) async {
          tester.view.physicalSize = tam;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await preparar(tester);

          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('un email de 300 caracteres al 200 % no desborda', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        '${'a' * 300}@correo.com',
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('RecuperacionPasswordPage — diseño', () {
    testWidgets('renderiza sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );

      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('RecuperacionPasswordPage — aviso informativo, sin casilla (#272)', () {
    testWidgets('el aviso de impacto es «Tus datos guardados en este teléfono se conservan.» y no '
        'queda rastro del texto viejo (decisión 01/10)', (tester) async {
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      expect(find.text('Tus datos guardados en este teléfono se conservan.'), findsOneWidget);
      expect(find.textContaining('restaurar desde tu backup'), findsNothing);
      expect(find.textContaining('no podrás abrirlos'), findsNothing);
    });

    testWidgets('muestra la advertencia literal de la HU antes de enviar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_aviso')), findsOneWidget);
      expect(find.text(_textoAviso), findsOneWidget);
    });

    testWidgets('no hay casilla ni ⚠: el aviso solo informa y el botón arranca habilitado', (
      tester,
    ) async {
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      _sinCasillaNiAdvertencia();
      expect(find.byKey(const Key('recuperacion_password_aviso')), findsOneWidget);
      expect(find.text(_textoAviso), findsOneWidget);
      expect(_enviar(tester).onPressed, isNotNull);
    });

    testWidgets('el aviso no lleva ícono: dentro de su recuadro solo hay el texto', (tester) async {
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      final recuadro = find.ancestor(
        of: find.byKey(const Key('recuperacion_password_aviso')),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(of: recuadro.first, matching: find.byType(Icon)),
        findsNothing,
        reason: 'ni ⚠ ni ningún otro ícono',
      );
    });

    testWidgets(
      'un toque con el campo vacío pide el email y no envía (ya no lo frena una casilla)',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.text('Ingresá tu email'), findsOneWidget);
        expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
        expect(_enviar(tester).onPressed, isNotNull);
      },
    );
  });

  group('RecuperacionPasswordPage — envío por teclado y reentrada', () {
    testWidgets('el "Listo" del teclado envía si ya se puede', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
    });

    testWidgets('el "Listo" del teclado con el campo vacío pide el email y no envía', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.showKeyboard(find.byKey(const Key('recuperacion_password_email')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsNothing);
      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
    });

    testWidgets('el "Listo" del teclado y el botón, uno detrás del otro, envían una sola vez', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..demoraRecuperacion = Completer<void>();
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completar(tester);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pump();
      expect(find.text('Enviando…'), findsOneWidget);

      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
    });

    testWidgets('doble tap seguido dispara una sola solicitud (guarda de reentrada)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);

      // Dos taps seguidos sin `pump()` entre medio: simula un doble tap más rápido que el próximo
      // repintado, cuando el botón todavía no se deshabilitó visualmente.
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
    });
  });

  group('RecuperacionPasswordPage — la espera sobrevive a salir y volver a entrar (#281)', () {
    const textoEspera = 'Podés pedir otro enlace en';

    late _Reloj reloj;
    late AuthRemoteDataSourceEnMemoria remote;

    setUp(() {
      reloj = _Reloj(DateTime.utc(2026, 10, 8, 10));
      remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
    });

    /// El teléfono con un enlace pedido hace [hace].
    UltimoEnvioRecuperacionEnMemoria envioHace(Duration hace) =>
        UltimoEnvioRecuperacionEnMemoria(reloj.ahora.subtract(hace));

    Future<void> reentrar(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('abrir_recuperacion')));
      await tester.pumpAndSettle();
    }

    testWidgets('al volver a entrar a los 20 s: el formulario de siempre con el correo editable, '
        '«Enviar» deshabilitado, «Podés pedir otro enlace en 40s.» y ninguna llamada al servidor', (
      tester,
    ) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(seconds: 20)),
        ahora: reloj.call,
      );

      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(find.text(_textoAviso), findsOneWidget);
      expect(find.text('$textoEspera 40s.'), findsOneWidget);
      expect(_enviar(tester).onPressed, isNull);
      expect(find.text('Enviar enlace de recuperación'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email'))).enabled,
        isTrue,
        reason: 'el correo se puede editar mientras se espera',
      );
      await _completar(tester);
      expect(_textoDelCampo(tester), 'lucia.silva@correo.com');
      expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
      expect(find.byKey(const Key('recuperacion_password_reenviar')), findsNothing);
      expect(find.text(_mensajeNeutro), findsNothing);
      expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
    });

    testWidgets('dentro de la espera, tocar el botón o el «Listo» del teclado no llama al '
        'servidor', (tester) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(seconds: 20)),
        ahora: reloj.call,
      );
      await _completar(tester);

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')), warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
      expect(find.text('$textoEspera 40s.'), findsOneWidget);
    });

    testWidgets('el aviso baja cada segundo; al llegar a 0 desaparece, el botón se habilita y '
        'envía lo que se escribió mientras tanto', (tester) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(seconds: 56)),
        ahora: reloj.call,
      );
      await _completar(tester, email: 'ana@correo.com');
      expect(find.text('$textoEspera 4s.'), findsOneWidget);

      for (final restante in [3, 2, 1]) {
        await _pasar(tester, reloj, const Duration(seconds: 1));
        expect(find.text('$textoEspera ${restante}s.'), findsOneWidget);
        expect(_enviar(tester).onPressed, isNull);
      }

      await _pasar(tester, reloj, const Duration(seconds: 1));
      expect(find.textContaining(textoEspera), findsNothing);
      expect(_enviar(tester).onPressed, isNotNull);
      expect(_textoDelCampo(tester), 'ana@correo.com', reason: 'lo escrito no se pierde');

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail, {'ana@correo.com': 1});
    });

    for (final (nombre, hace) in [
      ('justo 60 s', const Duration(seconds: 60)),
      ('61 s', const Duration(seconds: 61)),
      ('una hora', const Duration(hours: 1)),
    ]) {
      testWidgets('con el último enlace hace $nombre ya no hay espera: formulario normal', (
        tester,
      ) async {
        await _montarSobreLogin(
          tester,
          remote: remote,
          ultimoEnvio: envioHace(hace),
          ahora: reloj.call,
        );

        expect(find.textContaining(textoEspera), findsNothing);
        expect(_enviar(tester).onPressed, isNotNull);
      });
    }

    testWidgets('sin ningún enlace pedido antes, no hay espera', (tester) async {
      await _montarSobreLogin(tester, remote: remote, ahora: reloj.call);

      expect(find.textContaining(textoEspera), findsNothing);
      expect(_enviar(tester).onPressed, isNotNull);
    });

    testWidgets('faltando 500 ms se muestra «1s» (se redondea para arriba) y a la vuelta se '
        'habilita', (tester) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(milliseconds: 59500)),
        ahora: reloj.call,
      );

      expect(find.text('$textoEspera 1s.'), findsOneWidget);
      await _pasar(tester, reloj, const Duration(seconds: 1));
      expect(find.textContaining(textoEspera), findsNothing);
      expect(_enviar(tester).onPressed, isNotNull);
    });

    for (final (nombre, adelantado) in [
      ('20 s', const Duration(seconds: 20)),
      ('3 horas', const Duration(hours: 3)),
    ]) {
      testWidgets('si la hora guardada quedó $nombre en el futuro (se atrasó el reloj), la espera '
          'es de 60 s, no más', (tester) async {
        await _montarSobreLogin(
          tester,
          remote: remote,
          ultimoEnvio: UltimoEnvioRecuperacionEnMemoria(reloj.ahora.add(adelantado)),
          ahora: reloj.call,
        );

        expect(find.text('$textoEspera 60s.'), findsOneWidget);
        await _pasar(tester, reloj, const Duration(seconds: 60));
        expect(find.textContaining(textoEspera), findsNothing);
        expect(_enviar(tester).onPressed, isNotNull);
      });
    }

    testWidgets('volver a entrar varias veces sigue contando desde el mismo envío, no desde la '
        'entrada', (tester) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(seconds: 10)),
        ahora: reloj.call,
      );
      expect(find.text('$textoEspera 50s.'), findsOneWidget);

      for (final (paso, restante) in [(15, 35), (20, 15)]) {
        await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
        await tester.pumpAndSettle();
        reloj.avanzar(Duration(seconds: paso));
        await reentrar(tester);
        expect(find.text('$textoEspera ${restante}s.'), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
      await tester.pumpAndSettle();
      reloj.avanzar(const Duration(seconds: 15));
      await reentrar(tester);
      expect(find.textContaining(textoEspera), findsNothing);
      expect(_enviar(tester).onPressed, isNotNull);
    });

    testWidgets('el atrás del sistema sale de la pantalla también durante la espera', (
      tester,
    ) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(seconds: 20)),
        ahora: reloj.call,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(find.text('pantalla de abajo'), findsOneWidget);
    });

    testWidgets('de segundo plano, la espera se recalcula con la hora real y no con el timer', (
      tester,
    ) async {
      await _montarSobreLogin(
        tester,
        remote: remote,
        ultimoEnvio: envioHace(const Duration(seconds: 20)),
        ahora: reloj.call,
      );
      expect(find.text('$textoEspera 40s.'), findsOneWidget);

      reloj.avanzar(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('$textoEspera 10s.'), findsOneWidget);

      reloj.avanzar(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.textContaining(textoEspera), findsNothing);
      expect(_enviar(tester).onPressed, isNotNull);
    });

    group('qué guarda el teléfono', () {
      testWidgets('un envío que sale guarda su hora, y salir y volver a entrar la respeta', (
        tester,
      ) async {
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: memoria, ahora: reloj.call);
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();
        expect(await memoria.leer(), reloj.ahora);

        await tester.tap(find.byKey(const Key('recuperacion_password_volver_login')));
        await tester.pumpAndSettle();
        reloj.avanzar(const Duration(seconds: 25));
        await reentrar(tester);

        expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
        expect(find.text('$textoEspera 35s.'), findsOneWidget);
        expect(_enviar(tester).onPressed, isNull);
      });

      testWidgets('«Reenviar» guarda la hora nueva y la espera corre desde ahí', (tester) async {
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: memoria, ahora: reloj.call);
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();
        await _pasar(tester, reloj, const Duration(seconds: 60));
        expect(_reenviar(tester).onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
        await tester.pumpAndSettle();
        expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 2);
        expect(await memoria.leer(), reloj.ahora);

        await tester.tap(find.byKey(const Key('recuperacion_password_volver_login')));
        await tester.pumpAndSettle();
        reloj.avanzar(const Duration(seconds: 10));
        await reentrar(tester);
        expect(find.text('$textoEspera 50s.'), findsOneWidget);
      });

      testWidgets('A05 y la reentrada cuentan desde el mismo envío guardado', (tester) async {
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: memoria, ahora: reloj.call);
        await _completar(tester);
        final salio = reloj.ahora;
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();
        await _pasar(tester, reloj, const Duration(seconds: 45));
        expect(find.text('Reenviar en 15s'), findsOneWidget);

        await tester.tap(find.byKey(const Key('recuperacion_password_volver_login')));
        await tester.pumpAndSettle();
        await reentrar(tester);

        expect(find.text('$textoEspera 15s.'), findsOneWidget);
        expect(await memoria.leer(), salio, reason: 'ver la espera no mueve la hora del envío');
      });

      testWidgets('un envío sin conexión (A06) no guarda la hora: se puede reintentar al instante '
          'y al volver a entrar no hay espera', (tester) async {
        remote.simularSinConexion = true;
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: memoria, ahora: reloj.call);
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
        expect(await memoria.leer(), isNull);
        expect(find.textContaining(textoEspera), findsNothing);
        expect(_enviar(tester).onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
        await tester.pumpAndSettle();
        await reentrar(tester);
        expect(find.textContaining(textoEspera), findsNothing);
        expect(_enviar(tester).onPressed, isNotNull);
      });

      testWidgets('un email inválido (A03) no guarda la hora', (tester) async {
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: memoria, ahora: reloj.call);
        await _completar(tester, email: 'lucia@');
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.text('Revisá el email: parece incompleto.'), findsOneWidget);
        expect(await memoria.leer(), isNull);
        expect(find.textContaining(textoEspera), findsNothing);
      });

      testWidgets('si el envío falla con un error del servidor, la hora no se guarda', (
        tester,
      ) async {
        remote.fallaAlSolicitarRecuperacion = const ServidorException(status: 500);
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: memoria, ahora: reloj.call);
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('recuperacion_password_error_general')), findsOneWidget);
        expect(await memoria.leer(), isNull);
        expect(_enviar(tester).onPressed, isNotNull);
      });

      testWidgets('si el enlace sale pero la pantalla ya no está, la hora igual queda guardada', (
        tester,
      ) async {
        remote.demoraRecuperacion = Completer<void>();
        final memoria = UltimoEnvioRecuperacionEnMemoria();
        final visible = ValueNotifier<bool>(true);
        addTearDown(visible.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
              authRemoteDataSourceProvider.overrideWithValue(remote),
              authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
              ultimoEnvioRecuperacionRepositoryProvider.overrideWithValue(memoria),
            ],
            child: MaterialApp(
              theme: temaClaro(),
              home: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, mostrar, _) =>
                    mostrar ? RecuperacionPasswordPage(ahora: reloj.call) : const SizedBox(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pump();
        expect(find.text('Enviando…'), findsOneWidget);

        visible.value = false;
        await tester.pump();
        reloj.avanzar(const Duration(seconds: 2));
        remote.demoraRecuperacion!.complete();
        await tester.pumpAndSettle();

        expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
        expect(await memoria.leer(), reloj.ahora, reason: 'la hora del fin de la llamada');
        expect(tester.takeException(), isNull);
      });

      testWidgets('con el almacén roto al guardar, el envío igual termina en A05 con su cuenta '
          'regresiva', (tester) async {
        final almacen = AlmacenSeguroEnMemoria();
        final repo = UltimoEnvioRecuperacionRepositoryImpl(almacen, logger: loggerMudo());
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: repo, ahora: reloj.call);
        await _completar(tester);
        almacen.simularFalla = true;

        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.text(_mensajeNeutro), findsOneWidget);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(find.byKey(const Key('recuperacion_password_error_general')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('con el almacén roto al leer, la pantalla abre normal (sin espera) y envía', (
        tester,
      ) async {
        final almacen = AlmacenSeguroEnMemoria()..simularFalla = true;
        final repo = UltimoEnvioRecuperacionRepositoryImpl(almacen, logger: loggerMudo());
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: repo, ahora: reloj.call);

        expect(find.textContaining(textoEspera), findsNothing);
        expect(_enviar(tester).onPressed, isNotNull);
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();
        expect(find.text(_mensajeNeutro), findsOneWidget);
      });

      testWidgets('con el almacén seguro real, la espera sobrevive a cerrar y abrir la app', (
        tester,
      ) async {
        final almacen = AlmacenSeguroEnMemoria();
        UltimoEnvioRecuperacionRepositoryImpl repo() =>
            UltimoEnvioRecuperacionRepositoryImpl(almacen, logger: loggerMudo());
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: repo(), ahora: reloj.call);
        await _completar(tester);
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        // Se cierra la app: se descarta todo el árbol, el almacén seguro queda.
        await tester.pumpWidget(const SizedBox());
        reloj.avanzar(const Duration(seconds: 20));
        await _montarSobreLogin(tester, remote: remote, ultimoEnvio: repo(), ahora: reloj.call);

        expect(find.text('$textoEspera 40s.'), findsOneWidget);
        expect(_enviar(tester).onPressed, isNull);
      });
    });

    group('un toque mientras todavía se lee la hora guardada', () {
      testWidgets('con una espera vigente no envía: al terminar la lectura muestra la espera', (
        tester,
      ) async {
        final lectura = Completer<DateTime?>();
        final demorado = _UltimoEnvioDemorado(lectura);
        await _montarPagina(tester, remote: remote, ultimoEnvio: demorado, ahora: reloj.call);
        await tester.pump();
        await _completar(tester);

        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pump();
        lectura.complete(reloj.ahora.subtract(const Duration(seconds: 20)));
        await tester.pumpAndSettle();

        expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
        expect(demorado.guardado, isNull);
        expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
        expect(find.text('$textoEspera 40s.'), findsOneWidget);
        expect(
          find.text('Enviar enlace de recuperación'),
          findsOneWidget,
          reason: 'no queda trabado en «Enviando…»',
        );
        expect(_enviar(tester).onPressed, isNull);
      });

      testWidgets('sin espera vigente envía recién cuando la lectura terminó, una sola vez', (
        tester,
      ) async {
        final lectura = Completer<DateTime?>();
        final demorado = _UltimoEnvioDemorado(lectura);
        await _montarPagina(tester, remote: remote, ultimoEnvio: demorado, ahora: reloj.call);
        await tester.pump();
        await _completar(tester);

        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pump();
        expect(remote.solicitudesRecuperacionPorEmail, isEmpty, reason: 'todavía no se sabe');
        lectura.complete(null);
        await tester.pumpAndSettle();

        expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
        expect(find.text(_mensajeNeutro), findsOneWidget);
        expect(demorado.guardado, reloj.ahora);
      });
    });

    group('tamaños grandes con la espera a la vista', () {
      for (final (tam, escala) in [
        (const Size(360, 640), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 2.0),
      ]) {
        testWidgets('${tam.width.toInt()}x${tam.height.toInt()} con texto $escala: la espera y '
            'un email de 300 caracteres no desbordan y el aviso se alcanza', (tester) async {
          tester.view.physicalSize = tam;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _montarPagina(
            tester,
            remote: remote,
            ultimoEnvio: envioHace(const Duration(seconds: 20)),
            ahora: reloj.call,
          );
          await tester.pumpAndSettle();

          await tester.enterText(
            find.byKey(const Key('recuperacion_password_email')),
            '${'a' * 300}@correo.com',
          );
          await tester.pumpAndSettle();

          expect(find.text('$textoEspera 40s.'), findsOneWidget);
          await tester.ensureVisible(find.byKey(const Key('recuperacion_password_espera')));
          expect(tester.takeException(), isNull);
        });
      }
    });
  });

  group('RecuperacionPasswordPage — anti-enumeración', () {
    testWidgets('email registrado: mensaje neutro y arranca el cooldown de 60s', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(
        _reenviar(tester).onPressed,
        isNull,
        reason: 'deshabilitado mientras dura el cooldown',
      );

      await tester.pump(const Duration(seconds: 60));

      expect(find.text('Reenviar enlace'), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNotNull);
    });

    testWidgets('email no registrado: el mismo mensaje neutro (no revela que no existe)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester, email: 'noexiste@correo.com');
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
    });

    testWidgets('rate limit de Supabase (429) también se enmascara como éxito', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..fallaAlSolicitarRecuperacion = const ServidorException(status: 429);
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(find.byKey(const Key('recuperacion_password_error_general')), findsNothing);
    });
  });

  group('RecuperacionPasswordPage — errores reales del servicio', () {
    testWidgets('sin conexión muestra el error, sin arrancar cooldown', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..simularSinConexion = true;
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_error_general')), findsOneWidget);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')))
            .onPressed,
        isNotNull,
        reason: 'un error real no es rate limit: no debe dejar el botón en cooldown',
      );
    });

    // Era el bug #94: la página mostraba el mensaje genérico de FailureSinConexion.
    testWidgets('sin conexión muestra el texto literal de la HU-AUTH-004 (línea 822)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..simularSinConexion = true;
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
      expect(find.text('Sin conexión. Reintentá cuando tengas señal'), findsNothing);
    });

    testWidgets('falla real del servidor (no 429) muestra el mensaje traducido', (tester) async {
      final remote =
          AuthRemoteDataSourceEnMemoria(
              credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
            )
            ..fallaAlSolicitarRecuperacion = const ServidorException(
              status: 500,
              mensaje: 'El servidor no pudo procesar la solicitud',
            );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('El servidor no pudo procesar la solicitud'), findsOneWidget);
    });

    testWidgets('email vacío: error de validación en el campo', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu email'), findsOneWidget);
    });
  });

  group('LoginPage — enlace de recuperación', () {
    testWidgets('"¿Olvidaste tu clave?" navega a RecuperacionPasswordPage', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(theme: temaClaro(), home: const LoginPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_olvidaste_clave')));
      await tester.pumpAndSettle();

      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
    });
  });
}
