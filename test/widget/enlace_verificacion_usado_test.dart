// HU-AUTH-002, «"Vencido" vs "ya usado"» (front-colportores-mobile#242): el enlace de verificación
// que Supabase rechaza con `otp_expired`. Cubre los tres casos de la HU —sesión activa, login en
// silencio, texto genérico— en la raíz de la app, y las pantallas «ya verificado» (A05 de la
// vista 12) y «enlace que ya no sirve» solas, con sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';
const _clave = 'Secreto123';

const _textoGenerico =
    'Este enlace ya no sirve: puede que ya lo hayas usado o que haya vencido. Si ya verificaste '
    'tu email, entrá con tu contraseña. Si no, pedí un enlace nuevo.';

/// Cuenta registrada que todavía no confirmó el correo (como tras el registro).
Future<AuthRemoteDataSourceEnMemoria> _remotoPendiente({bool confirmada = false}) async {
  final remote = AuthRemoteDataSourceEnMemoria(
    credenciales: const {},
    requiereVerificacionAlRegistrar: true,
  );
  await remote.registrar(
    nombre: 'Lucía',
    apellido: 'Silva',
    cedula: '12345678',
    email: _correo,
    password: _clave,
  );
  if (confirmada) remote.confirmarEmail(_correo);
  return remote;
}

/// El `ProviderScope` va como argumento directo de `pumpWidget` (ver `app_test.dart`).
Future<void> _montarApp(WidgetTester tester, AuthRemoteDataSourceEnMemoria remote) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ],
        child: const ColportoresApp(),
      ),
    );

/// Abre la pantalla de espera como la deja el registro: con el correo y la contraseña en memoria.
Future<void> _abrirEspera(WidgetTester tester) async {
  unawaited(
    navigatorKeyColportores.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const VerificacionEmailPage(email: _correo, password: _clave),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), _correo);
  await tester.enterText(find.byKey(const Key('login_password')), _clave);
  await tester.tap(find.byKey(const Key('login_enviar')));
  await tester.pumpAndSettle();
}

void _pantalla(WidgetTester tester, [Size tamanio = const Size(390, 844)]) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Caso 1 — sesión activa: «Tu email ya está verificado» y entra a la app', () {
    testWidgets('muestra el texto de la vista 12 (A05) y, pasados unos segundos, vuelve a Inicio', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _entrar(tester);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.text('Tu email ya está verificado'), findsOneWidget);
      // Decisión de Cristian (02/10): con sesión, el texto dice a dónde se va de verdad.
      expect(find.text('Te llevamos a tu inicio…'), findsOneWidget);
      expect(find.text('Te llevamos al login…'), findsNothing);
      expect(find.text('Ir a mi inicio ahora'), findsOneWidget);
      expect(find.text('Ir al login ahora'), findsNothing);
      expect(find.byKey(const Key('verificacion_email_ir_login')), findsOneWidget);
      // No es la pantalla de «enlace vencido»: ya no se trata el enlace usado como expirado.
      expect(find.text('El enlace expiró'), findsNothing);
      expect(find.byKey(const Key('verificacion_email_reenviar')), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Tu email ya está verificado'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Tu email ya está verificado'), findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('«Ir al login ahora» sale sin esperar; el temporizador después no hace nada', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _entrar(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('verificacion_email_ir_login')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(find.text('Tu email ya está verificado'), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('con otra pantalla encima, la pila se vacía hasta la raíz y se ve A05', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _entrar(tester);
      unawaited(
        navigatorKeyColportores.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('otra pantalla'))),
        ),
      );
      await tester.pumpAndSettle();

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      expect(find.text('Tu email ya está verificado'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('otra pantalla'), findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('dos enlaces usados seguidos, y volver a abrir uno después: cada uno se atiende', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _entrar(tester);

      remote.simularEnlaceVerificacionInvalido();
      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('verificacion_email_titulo')), findsOneWidget);

      await tester.tap(find.byKey(const Key('verificacion_email_ir_login')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      expect(find.text('Tu email ya está verificado'), findsOneWidget);
    });
  });

  group('Caso 2 — la pantalla de espera sigue abierta: login en silencio', () {
    testWidgets('si la cuenta ya estaba confirmada, el login entra y dice «ya verificado»', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(remote.llamadasIniciarSesion, 1);
      expect(find.text('Tu email ya está verificado'), findsOneWidget);
      // El login en silencio dejó la sesión abierta: la salida es Inicio, no el login.
      expect(find.text('Te llevamos a tu inicio…'), findsOneWidget);
      expect(find.text('Te llevamos al login…'), findsNothing);
      expect(find.text('El enlace expiró'), findsNothing);
      expect(find.text('Ya verifiqué mi email'), findsNothing);

      await tester.tap(find.byKey(const Key('verificacion_email_ir_login')));
      await tester.pumpAndSettle();
      // El login en silencio dejó la sesión abierta: la raíz es la app.
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('si responde email_not_confirmed: «El enlace expiró» con Reenviar y el correo', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(remote.llamadasIniciarSesion, 1);
      expect(find.text('El enlace expiró'), findsOneWidget);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(find.textContaining(_correo), findsWidgets);
      expect(find.byKey(const Key('inicio_principal')), findsNothing);

      // Sin pedir un nuevo login: reenvía desde acá.
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail[_correo], 1);
    });

    testWidgets('si el login falla por otra cosa (sin conexión): el caso genérico, sin trabarse', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);
      remote.simularSinConexion = true;

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.text(_textoGenerico), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_ir_login')), findsNothing);
      expect(find.text('Ir al login'), findsOneWidget);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      // Nada quedó «ocupado»: con conexión de nuevo, se puede reenviar.
      remote.simularSinConexion = false;
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail[_correo], 1);
    });

    testWidgets('si las credenciales ya no valen: el caso genérico', (tester) async {
      _pantalla(tester);
      // La cuenta existe con otra contraseña (se cambió desde otro lado).
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: 'Otra12345'});
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.text(_textoGenerico), findsOneWidget);
    });

    testWidgets('dos enlaces mientras el login está en curso: un solo login, una sola pantalla', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      final demora = Completer<void>();
      remote.demoraIniciarSesion = demora;
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pump();
      remote.simularEnlaceVerificacionInvalido();
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();

      expect(remote.llamadasIniciarSesion, 1);
      expect(find.byKey(const Key('verificacion_email_titulo')), findsOneWidget);
      expect(find.text('Tu email ya está verificado'), findsOneWidget);
    });

    testWidgets('después de salir de la pantalla de espera, ya no hay login en silencio', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);

      navigatorKeyColportores.currentState!.pop();
      await tester.pumpAndSettle();

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(
        remote.llamadasIniciarSesion,
        0,
        reason: 'la contraseña no se guarda: se fue con la pantalla',
      );
      expect(find.text(_textoGenerico), findsOneWidget);
    });

    testWidgets('con la contraseña en memoria de otra pantalla de espera, usa la vigente', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      await _abrirEspera(tester);
      navigatorKeyColportores.currentState!.pop();
      await tester.pumpAndSettle();
      await _abrirEspera(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(remote.llamadasIniciarSesion, 1);
      expect(find.text('Tu email ya está verificado'), findsOneWidget);
    });
  });

  group('Caso 3 — sin sesión ni pantalla de espera: el texto genérico', () {
    testWidgets('el texto literal de la HU con «Ir al login» y «Reenviar»', (tester) async {
      _pantalla(tester);
      final remote = await _remotoPendiente();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.text(_textoGenerico), findsOneWidget);
      expect(find.text('Ir al login'), findsOneWidget);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(find.text('El enlace expiró'), findsNothing);
      expect(remote.llamadasIniciarSesion, 0);
    });

    testWidgets('«Ir al login» vuelve al login y un enlace posterior vuelve a mostrar el aviso', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ir al login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
      expect(find.text(_textoGenerico), findsNothing);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      expect(find.text(_textoGenerico), findsOneWidget);
    });

    testWidgets('el atrás del sistema vuelve al login, sin cerrar la app', (tester) async {
      _pantalla(tester);
      final remote = await _remotoPendiente();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
    });

    testWidgets('sin correo conocido: pide el correo para reenviar y valida lo que se escribe', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_campo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail, isEmpty);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), _correo);
      await tester.pump();
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail[_correo], 1);
      expect(find.text('Te reenviamos el correo. Puede tardar unos minutos.'), findsOneWidget);
    });

    testWidgets('Reenviar sin conexión avisa qué hacer y deja el botón habilitado', (tester) async {
      _pantalla(tester);
      final remote = await _remotoPendiente();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), _correo);
      await tester.pump();
      remote.simularSinConexion = true;

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(
        find.text('Necesitás conexión para reenviar el email. Conectate y probá de nuevo.'),
        findsOneWidget,
      );

      remote.simularSinConexion = false;
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail[_correo], 1);
    });

    testWidgets('arranque en frío: espera a leer la sesión y, si había, dice «ya verificado»', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoPendiente(confirmada: true);
      final sesion = await remote.iniciarSesion(email: _correo, password: _clave);
      final local = AuthLocalDataSourceEnMemoria();
      await local.guardarSesion(sesion);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(remote),
            authLocalDataSourceProvider.overrideWithValue(local),
          ],
          child: const ColportoresApp(),
        ),
      );
      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.text('Tu email ya está verificado'), findsOneWidget);
      expect(find.text(_textoGenerico), findsNothing);
    });
  });

  group('Pantallas solas', () {
    Future<void> montar(
      WidgetTester tester, {
      required EstadoVerificacionEmail estado,
      AuthRemoteDataSourceEnMemoria? remote,
      String email = _correo,
      double escala = 1,
      bool pilaDeDos = false,
    }) async {
      final pagina = VerificacionEmailPage(email: email, estadoInicial: estado);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              remote ?? AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _clave}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
              child: child!,
            ),
            home: pilaDeDos
                ? Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        key: const Key('abrir'),
                        onPressed: () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => pagina)),
                        child: const Text('abrir'),
                      ),
                    ),
                  )
                : pagina,
          ),
        ),
      );
      if (pilaDeDos) {
        await tester.tap(find.byKey(const Key('abrir')));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('«ya verificado»: sin eyebrow, sin tarjeta de correo y sin acciones de reenvío', (
      tester,
    ) async {
      _pantalla(tester);
      await montar(tester, estado: EstadoVerificacionEmail.yaVerificado);

      expect(find.text('Tu email ya está verificado'), findsOneWidget);
      expect(find.text('Te llevamos al login…'), findsOneWidget);
      expect(find.text('Ir al login ahora'), findsOneWidget);
      expect(find.text('VERIFICACIÓN DE EMAIL'), findsNothing);
      expect(find.byKey(const Key('verificacion_email_tarjeta')), findsNothing);
      expect(find.byKey(const Key('verificacion_email_reenviar')), findsNothing);
      expect(find.byKey(const Key('verificacion_email_volver_login')), findsNothing);
    });

    testWidgets('«ya verificado» con sesión: «Te llevamos a tu inicio…» y «Ir a mi inicio ahora»', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _clave});
      final container = ProviderContainer(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);
      await container.read(sesionProvider.notifier).iniciarSesion(email: _correo, password: _clave);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: temaClaro(),
            home: const VerificacionEmailPage(
              email: _correo,
              estadoInicial: EstadoVerificacionEmail.yaVerificado,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Te llevamos a tu inicio…'), findsOneWidget);
      expect(find.text('Te llevamos al login…'), findsNothing);
      expect(find.text('Ir a mi inicio ahora'), findsOneWidget);

      // Si la sesión termina con la pantalla abierta, el texto pasa a decir la verdad.
      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pump();
      expect(find.text('Te llevamos al login…'), findsOneWidget);
      expect(find.text('Te llevamos a tu inicio…'), findsNothing);
      expect(find.text('Ir al login ahora'), findsOneWidget);
    });

    testWidgets('«ya verificado» con sesión a 200 % de texto: sin overflow', (tester) async {
      _pantalla(tester, const Size(360, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _clave});
      final container = ProviderContainer(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);
      await container.read(sesionProvider.notifier).iniciarSesion(email: _correo, password: _clave);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: temaClaro(),
            home: const VerificacionEmailPage(
              email: _correo,
              estadoInicial: EstadoVerificacionEmail.yaVerificado,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ir a mi inicio ahora'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«ya verificado»: doble toque en «Ir al login ahora» sale una sola vez', (
      tester,
    ) async {
      _pantalla(tester);
      await montar(tester, estado: EstadoVerificacionEmail.yaVerificado, pilaDeDos: true);

      final boton = find.byKey(const Key('verificacion_email_ir_login'));
      final onPressed = tester.widget<FilledButton>(boton).onPressed!;
      onPressed();
      onPressed();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('abrir')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«ya verificado»: salir con el atrás del sistema cancela el temporizador', (
      tester,
    ) async {
      _pantalla(tester);
      await montar(tester, estado: EstadoVerificacionEmail.yaVerificado, pilaDeDos: true);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('abrir')), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });

    testWidgets('«enlace que ya no sirve» con correo: tarjeta, texto literal y las dos acciones', (
      tester,
    ) async {
      _pantalla(tester);
      await montar(tester, estado: EstadoVerificacionEmail.enlaceInutil);

      expect(find.text(_textoGenerico), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_tarjeta')), findsOneWidget);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(find.text('Ir al login'), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_campo')), findsNothing);
    });

    testWidgets(
      '«enlace que ya no sirve»: reenviar inicia la cuenta regresiva y bloquea el toque',
      (tester) async {
        _pantalla(tester);
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _clave});
        await montar(tester, estado: EstadoVerificacionEmail.enlaceInutil, remote: remote);

        await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(remote.reenviosPorEmail[_correo], 1);
        expect(find.textContaining('Reenviar en'), findsOneWidget);

        await tester.tap(find.byKey(const Key('verificacion_email_reenviar')), warnIfMissed: false);
        await tester.pump();
        expect(remote.reenviosPorEmail[_correo], 1);
        await tester.pump(const Duration(seconds: 61));
      },
    );

    testWidgets('«enlace que ya no sirve»: «Ir al login» vuelve a la pantalla anterior', (
      tester,
    ) async {
      _pantalla(tester);
      await montar(tester, estado: EstadoVerificacionEmail.enlaceInutil, pilaDeDos: true);

      await tester.tap(find.byKey(const Key('verificacion_email_volver_login')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });

    testWidgets('«enlace que ya no sirve»: correo larguísimo y texto al 200 % sin overflow', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640));
      await montar(
        tester,
        estado: EstadoVerificacionEmail.enlaceInutil,
        email: '${'nombre.muy.largo' * 6}@dominio-de-prueba-muy-largo.example.com',
        escala: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('verificacion_email_reenviar')));
      expect(tester.takeException(), isNull);
    });

    for (final estado in [
      EstadoVerificacionEmail.yaVerificado,
      EstadoVerificacionEmail.enlaceInutil,
    ]) {
      for (final MapEntry(key: nombre, value: tam) in const {
        '360x640': Size(360, 640),
        '412x915': Size(412, 915),
      }.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('$estado en $nombre, texto $escala: sin overflow y accesible', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            _pantalla(tester, tam);
            await montar(tester, estado: estado, escala: escala);

            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });
}
