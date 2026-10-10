import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/remoto_sin_sesion_deslizante.dart';

/// Remoto que lanza una excepción fija en `registrar` — para ver el banner del límite de
/// intentos/emails de Supabase sin depender del backend real.
final class _RemoteQueLanzaAlRegistrar
    with RemotoSinSesionDeslizante
    implements AuthRemoteDataSource {
  _RemoteQueLanzaAlRegistrar(this.excepcion);

  final AuthRemoteException excepcion;

  /// Cuántas veces se llamó a [registrar] — para probar la guarda de doble tap en "Reintentar".
  int llamadasRegistrar = 0;

  /// Si no es `null`, [registrar] no lanza hasta que el test lo complete — para que el segundo
  /// toque del doble tap ocurra mientras el primero todavía está en vuelo. Sin esto el fake
  /// resuelve instantáneo (como el resto de los fakes en memoria) y no hay ventana de carrera
  /// real: la guarda ya se resetea antes del segundo toque, y el test no prueba nada.
  Completer<void>? demora;

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
  }) async {
    llamadasRegistrar++;
    await demora?.future;
    throw excepcion;
  }

  @override
  Future<SesionModel?> obtenerSesionActual() async => null;

  @override
  SesionModel? sesionEnElCliente() => null;

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
/// cubre diseño/tema/validación. El caso feliz necesita, además, una pantalla debajo
/// en la pila para poder comprobar que `popUntil((r) => r.isFirst)` cierra el registro.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPagina(
  WidgetTester tester, {
  ThemeData? tema,
  AuthRemoteDataSource? remote,
  double escalaTexto = 1,
  DateTime Function()? ahora,
  BloqueoReenvioVerificacionRepository? bloqueos,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        remote ??
            AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      if (bloqueos != null)
        bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(bloqueos),
    ],
    child: MaterialApp(
      theme: tema ?? temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escalaTexto)),
        child: child!,
      ),
      home: RegistroPage(ahora: ahora ?? DateTime.now),
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
  BloqueoReenvioVerificacionRepository? bloqueos,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      if (bloqueos != null)
        bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(bloqueos),
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
  await tester.ensureVisible(find.byKey(const Key('registro_trade_off')));
  await tester.tap(find.byKey(const Key('registro_trade_off')));
  await tester.pump();
}

/// La casilla nueva del trade-off E2E (#85) corrió "Continuar" fuera del viewport por default de
/// los tests (800x600): sin esto, `tester.tap` tira "outside the bounds of the root of the render
/// tree" en vez de tocar el botón.
Future<void> _tocarContinuar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('registro_continuar')));
  await tester.tap(find.byKey(const Key('registro_continuar')));
}

void main() {
  group('RegistroPage — diseño', () {
    testWidgets('renderiza sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _montarPagina(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // Convención de accesibilidad del carril (jornada_page_test.dart): 360x740 para overflow con
    // el texto al 200 %. La casilla nueva del trade-off E2E (#85) no desborda (Text en Expanded,
    // igual que la de términos); el desborde real que encontró este test era otro, preexistente y
    // ajeno a #85 (el divisor «O REGISTRATE CON», arreglado en #108 y quitado con el ingreso por
    // Google en #265).
    testWidgets('sin overflow con el texto al 200 % en 360x740', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _montarPagina(tester, escalaTexto: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // Decisión del 02/10 (#265): se entra solo con correo y contraseña. El canvas 1a trae «O
    // REGISTRATE CON» + «Google» / «Apple»; no van, y no queda nada de ellos (ni botón, ni divisor,
    // ni la «G» / «A» del ícono), tampoco con el texto al 200 % en un teléfono chico.
    for (final (escala, ancho, alto) in [(1.0, 390.0, 844.0), (2.0, 360.0, 740.0)]) {
      testWidgets('sin ingreso por proveedor: ni Google, ni Apple, ni divisor (texto ×$escala)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(ancho, alto);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await _montarPagina(tester, escalaTexto: escala);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('registro_ir_a_login')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('¿Ya tenés cuenta? Entrar'), findsOneWidget);
        expect(find.textContaining('Google'), findsNothing);
        expect(find.textContaining('Apple'), findsNothing);
        expect(find.text('O REGISTRATE CON'), findsNothing);
        expect(find.text('G'), findsNothing);
        expect(find.text('A'), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.text('Disponible próximamente'), findsNothing);
      });
    }

    // Hueco de accesibilidad preexistente, anotado en la revisión de #106/#110 (issue #108):
    // este archivo no tenía `meetsGuideline` ni contraste. Misma convención que
    // jornada_page_test.dart: 390x844, tamaño de toque Android/iOS, etiquetas y contraste.
    // El bug de contraste 2.30 en "DATOS PERSONALES" (`colores.oro` fijo, #115) se resolvió con
    // la paleta única 1b (#121): ya no hay que saltear el tema claro.
    testWidgets('tamaño de toque, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _montarPagina(tester);
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  });

  group('RegistroPage — validación', () {
    testWidgets('enviar vacío muestra errores por campo y no llama al notifier', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _tocarContinuar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu nombre'), findsOneWidget);
      expect(find.text('Ingresá tu apellido'), findsOneWidget);
      expect(find.text('Ingresá tu cédula'), findsOneWidget);
      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(find.text('Tenés que aceptar los términos.'), findsOneWidget);
      expect(find.text('Tenés que aceptar el trade-off de tu contraseña.'), findsOneWidget);
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
      await _tocarContinuar(tester);
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
      await _tocarContinuar(tester);
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
      await _tocarContinuar(tester);
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
        await _tocarContinuar(tester);
        await tester.pumpAndSettle();

        expect(find.byType(RegistroPage), findsNothing);
        final pagina = tester.widget<VerificacionEmailPage>(find.byType(VerificacionEmailPage));
        expect(pagina.email, 'lucia.silva@correo.com');
        expect(pagina.password, 'Secreto123');
      },
    );

    // HU-AUTH-002, #325: el correo del alta es el primer envío; los 60 s para reenviar cuentan desde
    // ahí, así que la pantalla de verificación arranca con «Reenviar en Ns».
    group('el correo del alta cuenta como primer envío (#325)', () {
      final antiguo = DateTime(2026, 10, 8, 10);

      testWidgets('requiere verificación: la pantalla de verificación recibe la hora del alta que '
          'tomó el registro', (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await _montarPagina(tester, remote: remote, ahora: () => antiguo);
        await tester.pumpAndSettle();

        await _completarFormulario(tester, email: 'lucia.silva@correo.com');
        await _tocarContinuar(tester);
        await tester.pumpAndSettle();

        final pagina = tester.widget<VerificacionEmailPage>(find.byType(VerificacionEmailPage));
        expect(pagina.envioDelAlta, antiguo);
      });

      testWidgets('requiere verificación: el teléfono guarda la espera de 60 s de esa dirección y '
          'la pantalla arranca con «Reenviar en 60s», sin el aviso «Te reenviamos el correo»', (
        tester,
      ) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria();
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await _montarPagina(tester, remote: remote, bloqueos: bloqueos);
        await tester.pumpAndSettle();

        await _completarFormulario(tester, email: '  Lucia.Silva@Correo.COM ');
        await _tocarContinuar(tester);
        await tester.pumpAndSettle();

        final pagina = tester.widget<VerificacionEmailPage>(find.byType(VerificacionEmailPage));
        final delAlta = pagina.envioDelAlta!;
        final guardados = await bloqueos.leer(ahora: delAlta);
        expect(guardados.esperas, {
          'lucia.silva@correo.com': delAlta.add(const Duration(seconds: 60)).toUtc(),
        });
        expect(guardados.bloqueos, isEmpty);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(find.byKey(const Key('verificacion_email_mensaje_reenvio')), findsNothing);
        // Cierra la pantalla (y su cuenta regresiva) como lo haría la app.
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('si la persona sale de «Registrarse» con el alta en vuelo, el correo que salió '
          'igual cuenta: se guarda la espera de 60 s y no se abre la verificación', (tester) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria();
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await _montarPilaConPantallaInicial(tester, remote: remote, bloqueos: bloqueos);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('abrir_registro')));
        await tester.pumpAndSettle();
        await _completarFormulario(tester, email: '  Lucia.Silva@Correo.COM ');

        remote.demoraRegistrar = Completer<void>();
        await _tocarContinuar(tester);
        await tester.pump();
        expect(remote.llamadasRegistrar, 1);

        // Vuelve atrás antes de la respuesta de la red.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(RegistroPage), findsNothing);

        remote.demoraRegistrar!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(VerificacionEmailPage), findsNothing);
        expect(tester.takeException(), isNull);
        final guardados = await bloqueos.leer(ahora: DateTime.now());
        expect(guardados.esperas.keys, ['lucia.silva@correo.com']);
        expect(guardados.bloqueos, isEmpty);
      });

      testWidgets('si sale con el alta en vuelo y el alta falla, no se guarda ningún envío', (
        tester,
      ) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria();
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {'ana@example.com': 'secreto123'},
          requiereVerificacionAlRegistrar: true,
        );
        await _montarPilaConPantallaInicial(tester, remote: remote, bloqueos: bloqueos);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('abrir_registro')));
        await tester.pumpAndSettle();
        await _completarFormulario(tester, email: 'ana@example.com');

        remote.demoraRegistrar = Completer<void>();
        await _tocarContinuar(tester);
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        remote.demoraRegistrar!.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect((await bloqueos.leer(ahora: DateTime.now())).estaVacio, isTrue);
      });

      testWidgets(
        'con la sesión inmediata (sin verificación pendiente) no se guarda ningún envío',
        (tester) async {
          final bloqueos = BloqueoReenvioVerificacionEnMemoria();
          final remote = AuthRemoteDataSourceEnMemoria(
            credenciales: const {'ana@example.com': 'secreto123'},
          );
          await _montarPilaConPantallaInicial(tester, remote: remote, bloqueos: bloqueos);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('abrir_registro')));
          await tester.pumpAndSettle();

          await _completarFormulario(tester);
          await _tocarContinuar(tester);
          await tester.pumpAndSettle();

          expect(find.byType(VerificacionEmailPage), findsNothing);
          expect(find.text('Cuenta creada'), findsOneWidget);
          expect((await bloqueos.leer(ahora: DateTime.now())).estaVacio, isTrue);
        },
      );

      testWidgets('el registro rechazado (correo ya registrado) no guarda ningún envío', (
        tester,
      ) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria();
        await _montarPagina(tester, bloqueos: bloqueos);
        await tester.pumpAndSettle();

        await _completarFormulario(tester, email: 'ana@example.com');
        await _tocarContinuar(tester);
        await tester.pumpAndSettle();

        expect(find.byType(VerificacionEmailPage), findsNothing);
        expect((await bloqueos.leer(ahora: DateTime.now())).estaVacio, isTrue);
      });
    });

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
      await _tocarContinuar(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_error_general')), findsOneWidget);
      expect(find.text('Necesitás conexión para registrarte por primera vez'), findsOneWidget);
      expect(remote.usuariosRegistrados, isEmpty);
    });
  });

  // Bugs reales encontrados durante el QA de HU-AUTH-001 (issue #16): el código no cumplía estos
  // criterios de aceptación. Los de email-ya-registrado, sin-conexión, trade-off E2E (#85) y
  // fallo intermitente 5xx (#90) ya están arreglados (sin `skip:`). El único `skip:` que queda en
  // este archivo es el overflow de `_DivisorTexto`, ajeno a estos bugs — ver issue #108.
  group('RegistroPage — bugs conocidos de HU-AUTH-001', () {
    testWidgets('R-AU05: casilla del trade-off E2E, con el texto de la DEK envuelta (issue #85)', (
      tester,
    ) async {
      await _montarPagina(tester);
      await tester.pumpAndSettle();

      // Criterio de aceptación de HU-AUTH-001, con el texto actualizado (decisión de Cristian,
      // 23/09): desde la DEK envuelta (#26, ADR-006) el Keystore abre la DB local igual aunque se
      // pierda la contraseña — lo irrecuperable es el backup, no los datos locales. El finder
      // busca "no se pueden recuperar" (el texto viejo, "irrecuperable", ya no es exacto).
      expect(find.byKey(const Key('registro_trade_off')), findsOneWidget);
      expect(
        find.text(
          'Entiendo que mi contraseña protege la copia de seguridad de mis datos: si la '
          'olvido y pierdo el teléfono, los datos de mis clientes no se pueden recuperar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'R-AU05: acepta términos pero no el trade-off — Continuar lo exige aparte (issue #85)',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
        await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
        await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
        await tester.enterText(find.byKey(const Key('registro_email')), 'lucia.silva@correo.com');
        await tester.enterText(find.byKey(const Key('registro_password')), 'Secreto123');
        await tester.tap(find.byKey(const Key('registro_terminos')));
        await tester.pump();

        await _tocarContinuar(tester);
        await tester.pumpAndSettle();

        expect(find.text('Tenés que aceptar el trade-off de tu contraseña.'), findsOneWidget);
        expect(remote.usuariosRegistrados, isEmpty);
      },
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
        await _tocarContinuar(tester);
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
      await _tocarContinuar(tester);
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
        await _tocarContinuar(tester);
        await tester.pumpAndSettle();

        // Criterio de aceptación "Edge - fallo intermitente del backend": mensaje accionable
        // exacto (no el genérico de FailureServidor) y un botón "Reintentar" que no pierda los
        // datos del formulario. El registro local del NetworkFailure (status, sin PII) lo cubre
        // `auth_repository_impl_test.dart`, no esta pantalla.
        expect(
          find.text('Servicio temporalmente no disponible, reintentá en unos minutos'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);

        // El banner con el botón empuja el resto de la pantalla más abajo, fuera del viewport
        // default de los tests (800x600) — mismo caso que `registro_continuar` en #85.
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Reintentar'));
        await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
        await tester.pumpAndSettle();

        // El finder original acá era `find.descendant(of: find.byKey(...), matching:
        // find.byType(TextField))`: nunca matchea porque en `_CampoRegistro` la key va puesta en
        // el propio `TextField` (`key: widget.fieldKey`) y `find.descendant` excluye la raíz por
        // defecto (`matchRoot: false`) — mismo hallazgo que el issue documentó para este test
        // (salió de la revisión del PR #88). Corregido con `find.byKey` directo.
        final campoEmail = tester.widget<TextField>(find.byKey(const Key('registro_email')));
        expect(
          campoEmail.controller?.text,
          'lucia.silva@correo.com',
          reason: 'el botón "Reintentar" no debería perder los datos ya tipeados',
        );
      },
    );

    // Revisión de #111 (#90): `_enviar()` no tenía guarda de reentrada, solo el botón
    // deshabilitado en el build — dos toques más rápidos que el próximo repintado (mismo patrón
    // que `recuperacion_password_page_test.dart`) disparaban dos `signUp`, y Supabase reenviaba
    // el correo de confirmación. "Crear cuenta" y "Reintentar" comparten `_enviar()`: los dos
    // botones necesitan la guarda.
    testWidgets('doble toque en "Crear cuenta" dispara una sola llamada a registrar', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPilaConPantallaInicial(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('abrir_registro')));
      await tester.pumpAndSettle();

      await _completarFormulario(tester);

      // `demora` mantiene la primera llamada en vuelo: sin esto, el fake resuelve instantáneo
      // (no hay I/O real) y el segundo toque llega cuando la guarda ya se reseteó — no habría
      // ventana de carrera que probar. Dos taps seguidos sin `pump()` entre medio simulan un
      // doble tap más rápido que el próximo repintado, cuando el botón todavía no se deshabilitó
      // visualmente.
      remote.demoraRegistrar = Completer<void>();
      await tester.ensureVisible(find.byKey(const Key('registro_continuar')));
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.tap(find.byKey(const Key('registro_continuar')));
      remote.demoraRegistrar!.complete();
      await tester.pumpAndSettle();

      expect(remote.llamadasRegistrar, 1);
      expect(find.text('Cuenta creada'), findsOneWidget);
    });

    testWidgets('doble toque en "Reintentar" dispara una sola llamada más a registrar', (
      tester,
    ) async {
      final remote = _RemoteQueLanzaAlRegistrar(const ServidorException(status: 503));
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarFormulario(tester);
      await _tocarContinuar(tester);
      await tester.pumpAndSettle();
      expect(remote.llamadasRegistrar, 1, reason: 'el primer intento');

      // Mismo motivo que arriba: `demora` mantiene el reintento en vuelo para que el segundo
      // toque compita de verdad contra la guarda, en vez de llegar después de que ya se reseteó.
      remote.demora = Completer<void>();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Reintentar'));
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      remote.demora!.complete();
      await tester.pumpAndSettle();

      expect(remote.llamadasRegistrar, 2, reason: 'una sola llamada más, no dos');
    });
  });

  group('Desde el login', () {
    testWidgets('"Registrate" abre RegistroPage', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
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
