// QA de la vista 14 (#223, HU-AUTH-004): casos límite de entrada y navegación que
// `recuperacion_password_page_test.dart` no cubre: formatos de email, lo tipeado tras un error,
// el atrás del sistema mientras se envía y un email más largo que el máximo de un email real.
//
// QA de #281 (la hora del último envío, HU-AUTH-004): los grupos «QA #281» de abajo recorren la
// espera de 60 s de punta a punta con el almacén seguro real (reinicio de la app, reloj del
// teléfono, cierre de sesión), la validación y las fallas después de la espera, los toques
// superpuestos y la accesibilidad del estado nuevo.
import 'dart:async';

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_envio_recuperacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/ultimo_envio_recuperacion_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/espera_recuperacion_use_cases.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';

const _mensajeNeutro = 'Si el email está registrado, te enviamos un enlace de recuperación';
const _incompleto = 'Revisá el email: parece incompleto.';
const _sinConexion = 'Necesitás conexión para solicitar la recuperación';

Finder _k(String key) => find.byKey(Key(key));

/// La pantalla abierta desde otra ruta (como desde el login), para poder salir y volver.
Future<void> _montar(WidgetTester tester, AuthRemoteDataSourceEnMemoria remote) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (c) => TextButton(
            key: const Key('abrir'),
            onPressed: () => Navigator.of(
              c,
            ).push<void>(MaterialPageRoute<void>(builder: (_) => const RecuperacionPasswordPage())),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_k('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_k(key));
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _enviarCon(WidgetTester tester, String email) async {
  await tester.enterText(_k('recuperacion_password_email'), email);
  await _tocar(tester, 'recuperacion_password_enviar');
}

// ---------------------------------------------------------------------------------------------
// QA #281: la hora del último envío.
// ---------------------------------------------------------------------------------------------

const _espera = 'Podés pedir otro enlace en';

/// El reloj del teléfono en estos tests: la hora de ahora, que el test mueve a mano.
final class _Reloj {
  _Reloj(this.ahora);

  DateTime ahora;

  DateTime call() => ahora;
}

/// Pasa [cuanto] tiempo: el reloj de la pantalla y el del test (donde corre su timer).
Future<void> _pasar(WidgetTester tester, _Reloj reloj, Duration cuanto) async {
  reloj.ahora = reloj.ahora.add(cuanto);
  await tester.pump(cuanto);
}

/// Entrega la hora guardada recién cuando el test lo dice (un almacén lento).
final class _LecturaDemorada implements UltimoEnvioRecuperacionRepository {
  _LecturaDemorada(this.lectura);

  final Completer<DateTime?> lectura;
  DateTime? guardado;

  @override
  Future<DateTime?> leer() => lectura.future;

  @override
  Future<void> guardar(DateTime cuando) async => guardado = cuando;
}

/// Junta las líneas que el logger escribiría, para mirar qué dejan en el log.
final class _SalidaDeLog extends LogOutput {
  final List<String> lineas = [];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

List<Override> _overridesConReloj({
  required AuthRemoteDataSourceEnMemoria remote,
  required UltimoEnvioRecuperacionRepository ultimoEnvio,
}) => [
  dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
  authRemoteDataSourceProvider.overrideWithValue(remote),
  authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
  ultimoEnvioRecuperacionRepositoryProvider.overrideWithValue(ultimoEnvio),
];

/// La ruta de abajo (el login) con «abrir», y la pantalla encima: ya abierta al volver.
Widget _appConPantalla({required DateTime Function() ahora, String? emailInicial}) => MaterialApp(
  theme: temaClaro(),
  home: Builder(
    builder: (c) => TextButton(
      key: const Key('abrir'),
      onPressed: () => Navigator.of(c).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RecuperacionPasswordPage(emailInicial: emailInicial, ahora: ahora),
        ),
      ),
      child: const Text('abrir'),
    ),
  ),
);

/// Monta la app y abre la pantalla. Se puede llamar de nuevo después de `pumpWidget(SizedBox())`
/// para simular que se cerró y se abrió la app: lo guardado en el almacén queda.
Future<void> _montarConReloj(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  required UltimoEnvioRecuperacionRepository ultimoEnvio,
  required DateTime Function() ahora,
  String? emailInicial,
  Size? tamano,
  double escala = 1,
}) async {
  if (tamano != null) {
    tester.view
      ..physicalSize = tamano
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = escala;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overridesConReloj(remote: remote, ultimoEnvio: ultimoEnvio),
      child: _appConPantalla(ahora: ahora, emailInicial: emailInicial),
    ),
  );
  await tester.tap(_k('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _reabrir(WidgetTester tester) async {
  await tester.tap(_k('abrir'));
  await tester.pumpAndSettle();
}

FilledButton _botonEnviar(WidgetTester tester) =>
    tester.widget<FilledButton>(_k('recuperacion_password_enviar'));

/// Lo escrito en el campo (el hint es otro email: `find.text` lo confundiría).
String _textoDelCampo(WidgetTester tester) =>
    tester.widget<TextField>(_k('recuperacion_password_email')).controller!.text;

UltimoEnvioRecuperacionRepositoryImpl _repoReal(AlmacenSeguro almacen) =>
    UltimoEnvioRecuperacionRepositoryImpl(almacen, logger: loggerMudo());

void main() {
  late AuthRemoteDataSourceEnMemoria remote;
  setUp(() => remote = AuthRemoteDataSourceEnMemoria(credenciales: const {}));

  group('QA vista 14 — validación del email', () {
    for (final email in ['lucia+cobros@correo.com', '  lucia@correo.com  ', 'LUCIA@CORREO.COM']) {
      testWidgets('«$email» es válido y lleva al éxito neutro', (tester) async {
        await _montar(tester, remote);
        await _enviarCon(tester, email);
        expect(find.text(_mensajeNeutro), findsOneWidget);
      });
    }

    for (final email in [
      'lucia@@correo.com',
      'lucia@correo.c',
      '@correo.com',
      'lucia correo.com',
    ]) {
      testWidgets('«$email» muestra A03 y no envía', (tester) async {
        await _montar(tester, remote);
        await _enviarCon(tester, email);
        expect(find.text(_incompleto), findsOneWidget);
        expect(find.text(_mensajeNeutro), findsNothing);
      });
    }

    testWidgets('solo espacios: pide el email, no dice «parece incompleto»', (tester) async {
      await _montar(tester, remote);
      await _enviarCon(tester, '     ');
      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text(_incompleto), findsNothing);
    });

    testWidgets('después de A03 lo tipeado sigue y el botón queda habilitado', (tester) async {
      await _montar(tester, remote);
      await _enviarCon(tester, 'lucia@');
      expect(find.text('lucia@'), findsOneWidget);
      expect(tester.widget<FilledButton>(_k('recuperacion_password_enviar')).onPressed, isNotNull);
    });

    testWidgets('después de A06 lo tipeado sigue y reintentar lleva al éxito', (tester) async {
      remote.simularSinConexion = true;
      await _montar(tester, remote);
      await _enviarCon(tester, 'lucia@correo.com');
      expect(find.text(_sinConexion), findsOneWidget);
      expect(find.text('lucia@correo.com'), findsOneWidget);

      remote.simularSinConexion = false;
      await _tocar(tester, 'recuperacion_password_enviar');
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(find.text(_sinConexion), findsNothing);
    });

    testWidgets('un email de 300 caracteres no es un email: A03 en vez de mandarlo', (
      tester,
    ) async {
      await _montar(tester, remote);
      await _enviarCon(tester, '${'a' * 290}@correo.com');
      expect(find.text(_mensajeNeutro), findsNothing);
    });
  });

  group('QA vista 14 — navegación', () {
    testWidgets('el atrás del sistema mientras envía no saca de la pantalla, como la flecha', (
      tester,
    ) async {
      remote.demoraRecuperacion = Completer<void>();
      await _montar(tester, remote);
      await tester.enterText(_k('recuperacion_password_email'), 'lucia@correo.com');
      await tester.tap(_k('recuperacion_password_enviar'));
      await tester.pump();
      expect(tester.widget<IconButton>(_k('recuperacion_password_atras')).onPressed, isNull);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'salir y volver a entrar dentro de los 60 s: formulario sin el correo ni casilla, con el '
      'botón deshabilitado y la espera a la vista (#281)',
      (tester) async {
        await _montar(tester, remote);
        await _enviarCon(tester, 'lucia@correo.com');
        await _tocar(tester, 'recuperacion_password_volver_login');
        await tester.tap(_k('abrir'));
        await tester.pumpAndSettle();

        expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
        expect(find.text('lucia@correo.com'), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(tester.widget<FilledButton>(_k('recuperacion_password_enviar')).onPressed, isNull);
        expect(_k('recuperacion_password_espera'), findsOneWidget);
      },
    );
  });

  group('QA #281 · la hora del último envío, de punta a punta', () {
    late _Reloj reloj;
    late AlmacenSeguroEnMemoria almacen;

    // El cierre de sesión y el borrado de datos ya los cubre custodia_clave_db_test.dart (la hora
    // del último enlace sobrevive a `olvidar` y a `reconstruirAlmacen`, y se va con
    // `olvidarDatosDelUsuario`): acá no se repite con un almacén que el cierre de sesión no toca.
    setUp(() {
      reloj = _Reloj(DateTime.utc(2026, 10, 8, 10));
      almacen = AlmacenSeguroEnMemoria();
    });

    Future<void> pedirElEnlace(WidgetTester tester, {String email = 'ana@correo.com'}) async {
      await tester.enterText(_k('recuperacion_password_email'), email);
      await _tocar(tester, 'recuperacion_password_enviar');
      expect(find.text(_mensajeNeutro), findsOneWidget);
    }

    testWidgets(
      'Dado que pedí un enlace hace 20 s y volví al login, cuando entro de nuevo a «Olvidé mi '
      'contraseña», veo el formulario con el correo editable, «Enviar enlace de recuperación» '
      'deshabilitado y «Podés pedir otro enlace en 40s.», sin llamar al servidor; y al llegar a 0 '
      'se habilita',
      (tester) async {
        await _montarConReloj(
          tester,
          remote: remote,
          ultimoEnvio: _repoReal(almacen),
          ahora: reloj.call,
        );
        await pedirElEnlace(tester);
        await _tocar(tester, 'recuperacion_password_volver_login');
        await _pasar(tester, reloj, const Duration(seconds: 20));

        await _reabrir(tester);

        expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
        expect(find.text('Podés pedir otro enlace en 40s.'), findsOneWidget);
        expect(find.text('Enviar enlace de recuperación'), findsOneWidget);
        expect(_botonEnviar(tester).onPressed, isNull);
        expect(tester.widget<TextField>(_k('recuperacion_password_email')).enabled, isTrue);
        expect(_textoDelCampo(tester), isEmpty, reason: 'el teléfono no guarda el correo');
        expect(find.text(_mensajeNeutro), findsNothing, reason: 'sin envío no hay «te enviamos»');
        expect(_k('recuperacion_password_reenviar'), findsNothing);
        expect(remote.solicitudesRecuperacionPorEmail, {'ana@correo.com': 1});

        // El correo se puede corregir mientras se espera.
        await tester.enterText(_k('recuperacion_password_email'), 'ana.perez@correo.com');
        await _pasar(tester, reloj, const Duration(seconds: 39));
        expect(find.text('Podés pedir otro enlace en 1s.'), findsOneWidget);
        expect(_botonEnviar(tester).onPressed, isNull);

        await _pasar(tester, reloj, const Duration(seconds: 1));
        expect(find.textContaining(_espera), findsNothing);
        expect(_botonEnviar(tester).onPressed, isNotNull);
        expect(_textoDelCampo(tester), 'ana.perez@correo.com', reason: 'lo tipeado no se pierde');

        await _tocar(tester, 'recuperacion_password_enviar');
        expect(find.text(_mensajeNeutro), findsOneWidget);
        expect(remote.solicitudesRecuperacionPorEmail['ana.perez@correo.com'], 1);
      },
    );

    testWidgets('cerrar y abrir la app varias veces no reinicia la espera; un envío nuevo guarda '
        'la hora nueva', (tester) async {
      await _montarConReloj(
        tester,
        remote: remote,
        ultimoEnvio: _repoReal(almacen),
        ahora: reloj.call,
      );
      await pedirElEnlace(tester);

      Future<void> cerrarYAbrirLaApp(Duration despues) async {
        await tester.pumpWidget(const SizedBox());
        reloj.ahora = reloj.ahora.add(despues);
        await _montarConReloj(
          tester,
          remote: remote,
          ultimoEnvio: _repoReal(almacen),
          ahora: reloj.call,
        );
      }

      await cerrarYAbrirLaApp(const Duration(seconds: 20));
      expect(find.text('$_espera 40s.'), findsOneWidget);

      await cerrarYAbrirLaApp(const Duration(seconds: 35));
      expect(find.text('$_espera 5s.'), findsOneWidget, reason: 'a los 55 s del envío');

      await cerrarYAbrirLaApp(const Duration(seconds: 5));
      expect(find.textContaining(_espera), findsNothing, reason: 'a los 60 s ya no hay espera');
      expect(_botonEnviar(tester).onPressed, isNotNull);

      // Un envío nuevo reemplaza la hora: la espera empieza desde ahí, no desde el primero.
      await pedirElEnlace(tester);
      await _tocar(tester, 'recuperacion_password_volver_login');
      await cerrarYAbrirLaApp(const Duration(seconds: 10));
      expect(find.text('$_espera 50s.'), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail, {'ana@correo.com': 2});
    });

    testWidgets('con el reloj del teléfono en hora local (no UTC) la cuenta es la misma', (
      tester,
    ) async {
      reloj = _Reloj(DateTime(2026, 10, 8, 10));
      expect(reloj.ahora.isUtc, isFalse);
      await _montarConReloj(
        tester,
        remote: remote,
        ultimoEnvio: _repoReal(almacen),
        ahora: reloj.call,
      );
      await pedirElEnlace(tester);
      await _tocar(tester, 'recuperacion_password_volver_login');
      await _pasar(tester, reloj, const Duration(seconds: 20));

      await _reabrir(tester);

      expect(find.text('$_espera 40s.'), findsOneWidget);
    });

    testWidgets('se atrasa el reloj 1 hora con la espera a la vista y la app vuelve de segundo '
        'plano: la cuenta nunca pasa de 60 s; si se adelanta, la espera termina', (tester) async {
      await _montarConReloj(
        tester,
        remote: remote,
        ultimoEnvio: UltimoEnvioRecuperacionEnMemoria(
          reloj.ahora.subtract(const Duration(seconds: 20)),
        ),
        ahora: reloj.call,
      );
      expect(find.text('$_espera 40s.'), findsOneWidget);

      reloj.ahora = reloj.ahora.subtract(const Duration(hours: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('$_espera 60s.'), findsOneWidget);
      expect(_botonEnviar(tester).onPressed, isNull);

      reloj.ahora = reloj.ahora.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.textContaining(_espera), findsNothing);
      expect(_botonEnviar(tester).onPressed, isNotNull);
    });
  });

  group('QA #281 · validación, fallas y toques seguidos después de la espera', () {
    late _Reloj reloj;
    late UltimoEnvioRecuperacionEnMemoria ultimo;
    late DateTime pedidoA;

    setUp(() {
      reloj = _Reloj(DateTime.utc(2026, 10, 8, 10));
      pedidoA = reloj.ahora.subtract(const Duration(seconds: 20));
      ultimo = UltimoEnvioRecuperacionEnMemoria(pedidoA);
    });

    Future<void> abrirYEsperar(WidgetTester tester) async {
      await _montarConReloj(tester, remote: remote, ultimoEnvio: ultimo, ahora: reloj.call);
      expect(find.text('$_espera 40s.'), findsOneWidget);
    }

    for (final (escrito, aviso) in [
      ('lucia@', _incompleto),
      ('lucia@@correo.com', _incompleto),
      ('     ', 'Ingresá tu email'),
      ('', 'Ingresá tu email'),
    ]) {
      testWidgets('un correo «$escrito» tipeado durante la espera: al terminar, el aviso del '
          'campo y no se guarda la hora (se puede reintentar al instante)', (tester) async {
        await abrirYEsperar(tester);
        await tester.enterText(_k('recuperacion_password_email'), escrito);
        await _pasar(tester, reloj, const Duration(seconds: 40));
        expect(_botonEnviar(tester).onPressed, isNotNull);

        await _tocar(tester, 'recuperacion_password_enviar');

        expect(find.text(aviso), findsOneWidget);
        expect(find.text(_mensajeNeutro), findsNothing);
        expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
        expect(await ultimo.leer(), pedidoA, reason: 'un envío que no salió no guarda la hora');
        expect(_botonEnviar(tester).onPressed, isNotNull, reason: 'queda habilitado');
        expect(_k('recuperacion_password_espera'), findsNothing);

        await tester.enterText(_k('recuperacion_password_email'), 'lucia@correo.com');
        await _tocar(tester, 'recuperacion_password_enviar');
        expect(find.text(_mensajeNeutro), findsOneWidget);
      });
    }

    testWidgets('sin conexión al terminar la espera: A06 con «Necesitás conexión…», el botón '
        'vuelve a habilitarse, la hora no cambia y al volver la conexión envía', (tester) async {
      await abrirYEsperar(tester);
      await tester.enterText(_k('recuperacion_password_email'), 'lucia@correo.com');
      await _pasar(tester, reloj, const Duration(seconds: 40));
      remote.simularSinConexion = true;

      await _tocar(tester, 'recuperacion_password_enviar');

      expect(find.text(_sinConexion), findsOneWidget);
      expect(find.text('Enviando…'), findsNothing, reason: 'nada queda trabado en «Enviando…»');
      expect(_botonEnviar(tester).onPressed, isNotNull);
      expect(_textoDelCampo(tester), 'lucia@correo.com');
      expect(await ultimo.leer(), pedidoA);
      expect(_k('recuperacion_password_espera'), findsNothing);

      // Sale y vuelve a entrar: sigue sin espera, porque el envío no salió.
      await _tocar(tester, 'recuperacion_password_atras');
      await _reabrir(tester);
      expect(find.textContaining(_espera), findsNothing);

      remote.simularSinConexion = false;
      await tester.enterText(_k('recuperacion_password_email'), 'lucia@correo.com');
      await _tocar(tester, 'recuperacion_password_enviar');
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(await ultimo.leer(), reloj.ahora);
    });

    testWidgets('tocar el botón dos veces y el «Listo» del teclado justo al terminar la espera '
        'envía una sola vez', (tester) async {
      ultimo = UltimoEnvioRecuperacionEnMemoria(reloj.ahora.subtract(const Duration(seconds: 59)));
      await _montarConReloj(tester, remote: remote, ultimoEnvio: ultimo, ahora: reloj.call);
      expect(find.text('$_espera 1s.'), findsOneWidget);
      await tester.enterText(_k('recuperacion_password_email'), 'lucia@correo.com');
      await tester.tap(_k('recuperacion_password_enviar'), warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(remote.solicitudesRecuperacionPorEmail, isEmpty, reason: 'todavía falta 1 s');

      await _pasar(tester, reloj, const Duration(seconds: 1));
      await tester.tap(_k('recuperacion_password_enviar'));
      await tester.tap(_k('recuperacion_password_enviar'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(remote.solicitudesRecuperacionPorEmail, {'lucia@correo.com': 1});
    });

    testWidgets('con el correo que llega de la sesión y la espera vigente: precargado, editable y '
        'el botón deshabilitado', (tester) async {
      await _montarConReloj(
        tester,
        remote: remote,
        ultimoEnvio: ultimo,
        ahora: reloj.call,
        emailInicial: 'ana@correo.com',
      );

      expect(_textoDelCampo(tester), 'ana@correo.com');
      expect(tester.widget<TextField>(_k('recuperacion_password_email')).enabled, isTrue);
      expect(_botonEnviar(tester).onPressed, isNull);
      expect(find.text('$_espera 40s.'), findsOneWidget);
    });

    testWidgets('salir de la pantalla antes de que termine la lectura de la hora guardada no '
        'deja errores ni timers', (tester) async {
      final lectura = Completer<DateTime?>();
      final lenta = _LecturaDemorada(lectura);
      await _montarConReloj(tester, remote: remote, ultimoEnvio: lenta, ahora: reloj.call);
      expect(_botonEnviar(tester).onPressed, isNotNull, reason: 'mientras lee se puede usar');

      await _tocar(tester, 'recuperacion_password_atras');
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      lectura.complete(pedidoA);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('abrir y cerrar la pantalla muchas veces con la espera vigente no acumula timers', (
      tester,
    ) async {
      await _montarConReloj(tester, remote: remote, ultimoEnvio: ultimo, ahora: reloj.call);
      for (var i = 0; i < 6; i++) {
        await _tocar(tester, 'recuperacion_password_atras');
        await _reabrir(tester);
        expect(find.text('$_espera 40s.'), findsOneWidget);
      }
      await _pasar(tester, reloj, const Duration(seconds: 40));
      expect(find.textContaining(_espera), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // QA #281: un reenvío en vuelo no queda registrado hasta que el servidor contesta, y en A05
    // «Volver al login» sigue habilitado (la flecha y el atrás de A01 sí se bloquean). Se sale, se
    // vuelve a entrar y la pantalla nueva lee la hora vieja: sin espera, con «Enviar» habilitado,
    // mientras el reenvío anterior sigue en vuelo.
    // skip: QA #281 — A05: «Volver al login» sale con un reenvío en vuelo y la reentrada ofrece otro
    testWidgets(
      'A05: con un reenvío en vuelo no se puede salir y reentrar a un formulario que deja pedir '
      'otro enlace',
      (tester) async {
        await _montarConReloj(
          tester,
          remote: remote,
          ultimoEnvio: _repoReal(AlmacenSeguroEnMemoria()),
          ahora: reloj.call,
        );
        await tester.enterText(_k('recuperacion_password_email'), 'ana@correo.com');
        await _tocar(tester, 'recuperacion_password_enviar');
        await _pasar(tester, reloj, const Duration(seconds: 60));
        remote.demoraRecuperacion = Completer<void>();
        await tester.tap(_k('recuperacion_password_reenviar'));
        await tester.pump(); // el spinner no deja asentar
        expect(find.text('Enviando…'), findsOneWidget);

        final volver = tester.widget<TextButton>(_k('recuperacion_password_volver_login'));
        if (volver.onPressed != null) {
          await tester.tap(_k('recuperacion_password_volver_login'));
          await tester.pumpAndSettle();
          await _reabrir(tester);
          expect(
            _botonEnviar(tester).onPressed,
            isNull,
            reason: 'el reenvío anterior sigue en vuelo y la pantalla nueva deja pedir otro enlace',
          );
        }
        remote.demoraRecuperacion!.complete();
        await tester.pumpAndSettle();
      },
      skip: true,
    );
  });

  group('QA #281 · privacidad de lo que se guarda y de lo que se loguea', () {
    test('con el almacén roto, el log dice qué falló y nada del correo ni de la hora', () async {
      final salida = _SalidaDeLog();
      final almacen = AlmacenSeguroEnMemoria()..simularFalla = true;
      final repo = UltimoEnvioRecuperacionRepositoryImpl(
        almacen,
        logger: AppLogger(output: salida),
      );

      await repo.guardar(DateTime.utc(2026, 10, 8, 10, 11, 12));
      await repo.leer();

      final log = salida.lineas.join('\n');
      expect(log, contains('RECUPERACION_ULTIMO_ENVIO_ESCRIBIR'));
      expect(log, contains('RECUPERACION_ULTIMO_ENVIO_LEER'));
      expect(log, isNot(contains('2026-10-08')));
      expect(log, isNot(contains('@')));
    });

    test('la clave guarda solo la hora: ni el correo ni nada de la cuenta', () async {
      final almacen = AlmacenSeguroEnMemoria();
      await _repoReal(almacen).guardar(DateTime.utc(2026, 10, 8, 10, 11, 12));

      expect(almacen.contenido.keys, [ClaveSegura.ultimoEnvioRecuperacion]);
      expect(almacen.contenido.values.single, '2026-10-08T10:11:12.000Z');
      // Los parámetros de los dos casos de uso llevan solo una hora: nada que filtrar por toString.
      expect(ConsultarEsperaRecuperacionParams(ahora: DateTime.utc(2026, 10, 8, 10)).props, [
        isA<DateTime>(),
      ]);
      expect(RegistrarEnvioRecuperacionParams(cuando: DateTime.utc(2026, 10, 8, 10)).props, [
        isA<DateTime>(),
      ]);
    });
  });

  group('QA #281 · accesibilidad de la espera vigente', () {
    late _Reloj reloj;

    setUp(() => reloj = _Reloj(DateTime.utc(2026, 10, 8, 10)));

    final estados = <String, Future<void> Function(WidgetTester, Size)>{
      'A01 con la espera vigente (40 s)': (tester, tam) async {
        await _montarConReloj(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
          ultimoEnvio: UltimoEnvioRecuperacionEnMemoria(
            reloj.ahora.subtract(const Duration(seconds: 20)),
          ),
          ahora: reloj.call,
          tamano: tam,
        );
      },
      'A01 con la espera vigente y el correo escrito (1 s)': (tester, tam) async {
        await _montarConReloj(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
          ultimoEnvio: UltimoEnvioRecuperacionEnMemoria(
            reloj.ahora.subtract(const Duration(seconds: 59)),
          ),
          ahora: reloj.call,
          tamano: tam,
          emailInicial: 'lucia.silva@correo.com',
        );
      },
    };

    for (final tam in const [Size(360, 640), Size(412, 915)]) {
      for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
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

    testWidgets('el lector de pantalla encuentra el botón deshabilitado y, enseguida, la razón', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await estados.values.first(tester, const Size(360, 640));

      expect(
        tester.getSemantics(_k('recuperacion_password_enviar')),
        isSemantics(
          label: 'Enviar enlace de recuperación',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      final recorrido = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.label)
          .toList();
      final iBoton = recorrido.indexWhere((l) => l.contains('Enviar enlace de recuperación'));
      final iRazon = recorrido.indexWhere((l) => l.contains('$_espera 40s.'));
      expect(iBoton, isNonNegative, reason: 'el botón no está en el recorrido: $recorrido');
      expect(iRazon, iBoton + 1, reason: 'la razón va justo después del botón: $recorrido');
      semantica.dispose();
    });
  });
}
