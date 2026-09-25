import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [VerificacionEmailPage] aislada (sin [ColportoresApp]) — mismo criterio que
/// `login_page_test.dart`/`registro_page_test.dart`.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPagina(
  WidgetTester tester, {
  ThemeData? tema,
  String email = 'lucia.silva@correo.com',
  String? password,
  EstadoVerificacionEmail estadoInicial = EstadoVerificacionEmail.pendiente,
  required AuthRemoteDataSourceEnMemoria remote,
  double escalaTexto = 1,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(
      theme: tema ?? temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escalaTexto)),
        child: child!,
      ),
      home: VerificacionEmailPage(email: email, password: password, estadoInicial: estadoInicial),
    ),
  ),
);

/// Arranca en una pantalla inicial y empuja [VerificacionEmailPage] arriba, para poder verificar
/// que "Continuar"/"Volver al login" hacen `pop` de vuelta a ella.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPilaConPantallaInicial(
  WidgetTester tester, {
  required EstadoVerificacionEmail estadoInicial,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('abrir_verificacion'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VerificacionEmailPage(
                    email: 'lucia.silva@correo.com',
                    estadoInicial: estadoInicial,
                  ),
                ),
              ),
              child: const Text('abrir verificación'),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('VerificacionEmailPage — diseño', () {
    for (final estado in EstadoVerificacionEmail.values) {
      testWidgets('estado $estado: renderiza sin overflow en 390x844', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
        );

        await _montarPagina(tester, estadoInicial: estado, password: 'Secreto123', remote: remote);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Hueco de accesibilidad preexistente, anotado en la revisión de #106/#110 (issue #108): este
  // archivo no tenía `meetsGuideline` ni cobertura de `textScaler` alto. Misma convención que
  // jornada_page_test.dart / registro_page_test.dart.
  group('VerificacionEmailPage — accesibilidad', () {
    // El bug de contraste 2.30 en "VERIFICACIÓN DE EMAIL" (`colores.oro` fijo, #115) se resolvió
    // con la paleta única 1b (#121): ya no hace falta saltear el tema claro.
    for (final estado in EstadoVerificacionEmail.values) {
      testWidgets('estado $estado: tamaño de toque, etiquetas y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
        );

        await _montarPagina(tester, estadoInicial: estado, password: 'Secreto123', remote: remote);
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }

    // El campo de email editable (`_CampoEmail`) solo aparece sin `email` conocido (link de
    // verificación abierto sin sesión) — ninguno de los tests de arriba lo ejercita, así que el
    // tap-target de #115 (el `TextField` quedaba en 41, ya arreglado) no estaba cubierto.
    testWidgets('sin email conocido: tamaño de toque, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );

      await _montarPagina(tester, email: '', remote: remote);
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    for (final estado in EstadoVerificacionEmail.values) {
      testWidgets('estado $estado: sin overflow con el texto al 200 % en 360x740', (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
        );

        await _montarPagina(
          tester,
          estadoInicial: estado,
          password: 'Secreto123',
          remote: remote,
          escalaTexto: 2,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('VerificacionEmailPage — estado pendiente', () {
    testWidgets('muestra el email y ofrece reenviar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      expect(find.textContaining('lucia.silva@correo.com'), findsWidgets);
      expect(find.byKey(const Key('verificacion_email_reenviar')), findsOneWidget);
    });

    testWidgets('sin contraseña conocida, no ofrece "Ya verifiqué mi email"', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_ya_verifique')), findsNothing);
    });

    testWidgets(
      '"Ya verifiqué mi email": antes de confirmar avisa, después de confirmar pasa a verificado',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await remote.registrar(
          nombre: 'Lucía',
          apellido: 'Silva',
          cedula: '12345678',
          email: 'lucia.silva@correo.com',
          password: 'Secreto123',
        );

        await _montarPagina(tester, remote: remote, password: 'Secreto123');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('verificacion_email_ya_verifique')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('verificacion_email_error_general')), findsOneWidget);
        expect(find.textContaining('verificar tu correo'), findsOneWidget);

        remote.confirmarEmail('lucia.silva@correo.com');
        await tester.tap(find.byKey(const Key('verificacion_email_ya_verifique')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('verificacion_email_continuar')), findsOneWidget);
      },
    );

    // Issue #84, arreglado: la decisión de Cristian (23/09) fue un deep link propio
    // (`ConfigSupabase.redirectVerificacionEmail`, path `/verificado`) escuchado desde la RAÍZ de
    // la app (`ColportoresApp`), simétrico al listener de errores — no algo que
    // [VerificacionEmailPage] resuelva mirando su propio estado. El test que antes vivía acá
    // (skip, montaba la página sola y llamaba `remote.confirmarEmail`, que no dispara ningún
    // stream) probaba una hipótesis de arreglo distinta a la que se terminó decidiendo. La
    // cobertura real —deep link válido → `ColportoresApp` navega a esta pantalla en estado
    // "verificado", con el texto literal de la HU, incluyendo el caso de arranque en frío— está
    // en `test/widget/app_test.dart`, grupo "ColportoresApp — deep link de verificación exitosa".

    testWidgets('reenviar: éxito muestra el aviso y arranca el cooldown de 60s', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_mensaje_reenvio')), findsOneWidget);
      expect(remote.reenviosPorEmail['lucia.silva@correo.com'], 1);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('verificacion_email_reenviar')))
            .onPressed,
        isNull,
        reason: 'deshabilitado mientras dura el cooldown',
      );

      await tester.pump(const Duration(seconds: 60));

      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('verificacion_email_reenviar')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('reenviar: rate limit de Supabase muestra el mensaje traducido, sin cooldown', (
      tester,
    ) async {
      final remote =
          AuthRemoteDataSourceEnMemoria(
              credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
            )
            ..fallaAlReenviar = const ServidorException(
              mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
            );
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_error_general')), findsOneWidget);
      expect(
        find.text('Demasiados intentos. Esperá unos minutos y volvé a probar.'),
        findsOneWidget,
      );
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
    });
  });

  group('VerificacionEmailPage — estado expirado', () {
    testWidgets('sin email conocido: permite escribirlo y reenviar a esa dirección', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(
        tester,
        remote: remote,
        email: '',
        estadoInicial: EstadoVerificacionEmail.expirado,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_campo')), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_ya_verifique')), findsNothing);

      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), 'nueva@correo.com');
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(remote.reenviosPorEmail.containsKey('nueva@correo.com'), isTrue);
    });

    testWidgets('con email conocido, no lo pide de nuevo', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, estadoInicial: EstadoVerificacionEmail.expirado);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_campo')), findsNothing);
    });
  });

  group('VerificacionEmailPage — estado verificado', () {
    testWidgets('muestra el mensaje de éxito y "Continuar" cierra la pantalla', (tester) async {
      await _montarPilaConPantallaInicial(
        tester,
        estadoInicial: EstadoVerificacionEmail.verificado,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('abrir_verificacion')));
      await tester.pumpAndSettle();

      expect(
        find.text('Email verificado. Esperá la asignación de tu coordinador.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('verificacion_email_continuar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('abrir_verificacion')), findsOneWidget);
    });
  });
}
