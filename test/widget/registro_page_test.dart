import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Remoto que lanza una excepción fija en `registrar` — para ver el banner del límite de
/// intentos/emails de Supabase sin depender del backend real.
final class _RemoteQueLanzaAlRegistrar implements AuthRemoteDataSource {
  _RemoteQueLanzaAlRegistrar(this.excepcion);

  final AuthRemoteException excepcion;

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async => throw excepcion;

  @override
  Future<SesionModel> iniciarSesionConGoogle() => throw UnimplementedError();

  @override
  Future<SesionModel?> obtenerSesionActual() async => null;

  @override
  Future<void> cerrarSesion(String accessToken) => throw UnimplementedError();

  @override
  Future<void> revocarSesion(String accessToken) => throw UnimplementedError();

  @override
  Future<void> reenviarVerificacion(String email) => throw UnimplementedError();

  @override
  Stream<void> get erroresVerificacionEmail => const Stream.empty();

  @override
  Stream<void> get verificacionesExitosas => const Stream.empty();

  @override
  Future<void> solicitarRecuperacionPassword(String email) => throw UnimplementedError();
}

/// [RegistroPage] aislada (sin [ColportoresApp]): igual criterio que `login_page_test.dart` —
/// cubre diseño/tema/validación/proveedores. El caso feliz necesita, además, una pantalla debajo
/// en la pila para poder comprobar que `popUntil((r) => r.isFirst)` cierra el registro.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPagina(
  WidgetTester tester, {
  ThemeData? tema,
  bool? mostrarApple,
  AuthRemoteDataSource? remote,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        remote ??
            AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(
      theme: tema ?? temaClaro(),
      home: RegistroPage(mostrarApple: mostrarApple),
    ),
  ),
);

/// Arranca en una pantalla inicial cualquiera y empuja [RegistroPage] arriba, para poder
/// verificar que el éxito hace `pop` hasta volver a ella.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPilaConPantallaInicial(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('abrir_registro'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => const RegistroPage())),
              child: const Text('abrir registro'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _completarFormulario(
  WidgetTester tester, {
  String email = 'lucia.silva@correo.com',
  String password = 'Secreto123',
}) async {
  await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
  await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
  await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
  await tester.enterText(find.byKey(const Key('registro_email')), email);
  await tester.enterText(find.byKey(const Key('registro_password')), password);
  await tester.tap(find.byKey(const Key('registro_terminos')));
  await tester.pump();
}

void main() {
  group('RegistroPage — diseño', () {
    testWidgets('renderiza con tema claro sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _montarPagina(tester, tema: temaClaro());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza con tema oscuro sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _montarPagina(tester, tema: temaOscuro());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('el botón de Apple solo aparece cuando mostrarApple es true', (tester) async {
      await _montarPagina(tester, mostrarApple: true);
      await tester.pumpAndSettle();
      expect(find.text('Apple'), findsOneWidget);

      await _montarPagina(tester, mostrarApple: false);
      await tester.pumpAndSettle();
      expect(find.text('Apple'), findsNothing);
    });
  });

  group('RegistroPage — validación', () {
    testWidgets('enviar vacío muestra errores por campo y no llama al notifier', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu nombre'), findsOneWidget);
      expect(find.text('Ingresá tu apellido'), findsOneWidget);
      expect(find.text('Ingresá tu cédula'), findsOneWidget);
      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(find.text('Tenés que aceptar los términos.'), findsOneWidget);
      expect(remote.usuariosRegistrados, isEmpty);
    });
  });

  group('RegistroPage — flujo', () {
    testWidgets('caso feliz: registra, deja la sesión iniciada y cierra la página', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await _montarPilaConPantallaInicial(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('abrir_registro')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('registro_continuar')), findsOneWidget);

      await _completarFormulario(tester);
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      // Cerró el registro y volvió a la pantalla inicial.
      expect(find.byKey(const Key('registro_continuar')), findsNothing);
      expect(find.byKey(const Key('abrir_registro')), findsOneWidget);
      expect(find.text('Cuenta creada'), findsOneWidget);
      expect(remote.usuariosRegistrados.containsKey('lucia.silva@correo.com'), isTrue);
    });

    testWidgets('email ya registrado muestra el banner general', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarFormulario(tester, email: 'ana@example.com');
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_error_general')), findsOneWidget);
      expect(
        find.text(
          'Ya existe una cuenta con ese email. ¿Querés iniciar sesión o recuperar tu '
          'contraseña?',
        ),
        findsOneWidget,
      );
    });

    testWidgets('demasiados intentos (rate limit de Supabase) muestra el banner general', (
      tester,
    ) async {
      final remote = _RemoteQueLanzaAlRegistrar(
        const ServidorException(
          mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
        ),
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarFormulario(tester);
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_error_general')), findsOneWidget);
      expect(
        find.text('Demasiados intentos. Esperá unos minutos y volvé a probar.'),
        findsOneWidget,
      );
    });

    // Criterio de aceptación "Registro exitoso con datos válidos" de HU-AUTH-001, según quedó
    // tras el PR #79 (#19): con "Confirm email" activo, Supabase no deja la sesión iniciada y la
    // UI tiene que navegar (pushReplacement, no pop) a VerificacionEmailPage. El otro test de
    // "caso feliz" de este archivo cubre la sesión inmediata (sin verificación pendiente); este
    // cubre la rama que de verdad se da con Supabase real, y protege el cambio de #79 de un
    // regreso accidental al viejo comportamiento (volver al login con un banner).
    testWidgets(
      'requiere verificación: reemplaza la página por VerificacionEmailPage (no vuelve al login)',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();

        await _completarFormulario(tester, email: 'lucia.silva@correo.com');
        await tester.tap(find.byKey(const Key('registro_continuar')));
        await tester.pumpAndSettle();

        expect(find.byType(RegistroPage), findsNothing);
        final pagina = tester.widget<VerificacionEmailPage>(find.byType(VerificacionEmailPage));
        expect(pagina.email, 'lucia.silva@correo.com');
        expect(pagina.password, 'Secreto123');
      },
    );

    // Nueva cobertura: "sin conectividad" (HU-AUTH-001) a nivel de página — antes solo estaba
    // probado en el repositorio/use case, no en que RegistroPage efectivamente muestre el banner.
    testWidgets('sin conexión muestra el banner general y no registra a nadie', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {},
        simularSinConexion: true,
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarFormulario(tester);
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_error_general')), findsOneWidget);
      expect(find.text('Necesitás conexión para registrarte por primera vez'), findsOneWidget);
      expect(remote.usuariosRegistrados, isEmpty);
    });
  });

  // Bugs reales encontrados durante el QA de HU-AUTH-001 (issue #16): el código no cumplía estos
  // criterios de aceptación. Los de email-ya-registrado y sin-conexión se arreglaron en #86 (ya
  // sin `skip:`); los de trade-off E2E (#85) y fallo intermitente 5xx (#90) siguen sin arreglar y
  // quedan con `skip:` apuntando al issue correspondiente, para que la suite no se rompa y quede
  // visible qué falta.
  group('RegistroPage — bugs conocidos de HU-AUTH-001', () {
    testWidgets(
      'debería pedir la casilla del trade-off E2E antes de aceptar (R-AU05)',
      (tester) async {
        await _montarPagina(tester);
        await tester.pumpAndSettle();

        // Criterio de aceptación de HU-AUTH-001: además de "Acepto Términos y Política de
        // Privacidad", el formulario debe mostrar y exigir "Entiendo que perder mi contraseña
        // hace mis datos locales irrecuperables" (R-AU05, trade-off E2E). Hoy solo existe una
        // casilla ("registro_terminos"), sin ese segundo texto en ningún lado de la pantalla.
        expect(find.textContaining('irrecuperable'), findsOneWidget);
      },
      // Bug real, no se arregla en este QA: falta la casilla de trade-off E2E que exige el
      // criterio de aceptación de HU-AUTH-001. Ver issue #85.
      skip: true,
    );

    testWidgets(
      'email ya registrado: debería ofrecer accesos directos a login y recuperar contraseña',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {'ana@example.com': 'secreto123'},
        );
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();

        await _completarFormulario(tester, email: 'ana@example.com');
        await tester.tap(find.byKey(const Key('registro_continuar')));
        await tester.pumpAndSettle();

        // Criterio de aceptación de HU-AUTH-001: "la UI ofrece accesos directos a HU-AUTH-003 e
        // HU-AUTH-004" (iniciar sesión / recuperar contraseña) además del mensaje.
        expect(find.text('Iniciar sesión'), findsOneWidget);
        expect(find.text('Recuperar contraseña'), findsOneWidget);
      },
    );

    testWidgets('sin conexión: mensaje exacto del criterio y contraseña borrada por seguridad', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {},
        simularSinConexion: true,
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarFormulario(tester);
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      // Criterio de aceptación de HU-AUTH-001: mensaje exacto "Necesitás conexión para
      // registrarte por primera vez" (no el genérico de FailureSinConexion, que también usa el
      // login) y la contraseña se descarta del formulario "por seguridad".
      expect(find.text('Necesitás conexión para registrarte por primera vez'), findsOneWidget);
      // El finder original acá era `find.descendant(of: find.byKey(...), matching:
      // find.byType(TextField))`: nunca matchea porque en `_CampoRegistro` la key va puesta en
      // el propio `TextField` (`key: widget.fieldKey`) y `find.descendant` excluye la raíz por
      // defecto (`matchRoot: false`). Corregido según la nota del issue #86 (salió de la
      // revisión del PR #88).
      final campoPassword = tester.widget<TextField>(find.byKey(const Key('registro_password')));
      expect(campoPassword.controller?.text, isEmpty);
    });

    testWidgets(
      'fallo intermitente del backend (5xx): mensaje accionable y botón Reintentar sin perder '
      'los datos',
      (tester) async {
        final remote = _RemoteQueLanzaAlRegistrar(const ServidorException(status: 503));
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();

        await _completarFormulario(tester);
        await tester.tap(find.byKey(const Key('registro_continuar')));
        await tester.pumpAndSettle();

        // Criterio de aceptación "Edge - fallo intermitente del backend": mensaje accionable
        // exacto (no el genérico de FailureServidor), un botón "Reintentar" que no pierda los
        // datos del formulario, y (no verificable acá) el registro local de un NetworkFailure sin
        // PII. Hoy no hay botón "Reintentar" en ningún lado de la pantalla ni ese mensaje.
        expect(
          find.text('Servicio temporalmente no disponible, reintentá en unos minutos'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
        await tester.pumpAndSettle();

        final campoEmail = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('registro_email')),
            matching: find.byType(TextField),
          ),
        );
        expect(
          campoEmail.controller?.text,
          'lucia.silva@correo.com',
          reason: 'el botón "Reintentar" no debería perder los datos ya tipeados',
        );
      },
      // Bug real, no se arregla en este QA: el fallo intermitente del backend (5xx) no muestra el
      // mensaje accionable exacto ni ofrece un botón "Reintentar" que pide el criterio de
      // aceptación de HU-AUTH-001. Ver issue #90.
      skip: true,
    );
  });

  group('Desde el login', () {
    testWidgets('"Registrate" abre RegistroPage', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(theme: temaClaro(), home: const LoginPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_ir_a_registro')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_continuar')), findsOneWidget);
    });
  });
}
