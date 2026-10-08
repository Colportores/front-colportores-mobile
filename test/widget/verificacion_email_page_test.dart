import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';

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
  DateTime Function()? ahora,
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
      theme: tema ?? temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escalaTexto)),
        child: child!,
      ),
      home: VerificacionEmailPage(
        email: email,
        password: password,
        estadoInicial: estadoInicial,
        ahora: ahora ?? DateTime.now,
      ),
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
      // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
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

      expect(find.text('Reenviar email'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('verificacion_email_reenviar')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('doble toque en "Reenviar" manda un solo email', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();

      final boton = find.byKey(const Key('verificacion_email_reenviar'));
      await tester.tap(boton);
      await tester.tap(boton);
      await tester.pumpAndSettle();

      expect(remote.reenviosPorEmail['lucia.silva@correo.com'], 1);
    });

    testWidgets(
      'al volver a primer plano la cuenta regresiva sigue la hora real y el aviso se va',
      (tester) async {
        var ahora = DateTime(2026, 9, 29, 10);
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
        );
        await _montarPagina(tester, remote: remote, password: 'Secreto123', ahora: () => ahora);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
        await tester.pumpAndSettle();
        expect(find.text('Reenviar en 60s'), findsOneWidget);

        ahora = ahora.add(const Duration(seconds: 45));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(find.text('Reenviar en 15s'), findsOneWidget);

        ahora = ahora.add(const Duration(seconds: 30));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(find.text('Reenviar email'), findsOneWidget);
        expect(find.byKey(const Key('verificacion_email_mensaje_reenvio')), findsNothing);
      },
    );

    testWidgets('el aviso de reenvío se va cuando termina la cuenta regresiva', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('verificacion_email_mensaje_reenvio')), findsOneWidget);

      await tester.pump(const Duration(seconds: 60));

      expect(find.byKey(const Key('verificacion_email_mensaje_reenvio')), findsNothing);
    });

    testWidgets('reenviar: rate limit (429) bloquea el botón con candado una hora, con el texto '
        'de Cristian', (tester) async {
      var ahora = DateTime(2026, 9, 29, 10);
      final remote =
          AuthRemoteDataSourceEnMemoria(
              credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
            )
            ..fallaAlReenviar = const ServidorException(
              status: 429,
              mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
            );
      await _montarPagina(tester, remote: remote, password: 'Secreto123', ahora: () => ahora);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_limite')), findsOneWidget);
      expect(find.text('Demasiados intentos. Probá nuevamente en una hora.'), findsOneWidget);
      expect(find.text('Demasiados intentos. Esperá unos minutos y volvé a probar.'), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(find.text('Reenviar email'), findsOneWidget);
      final boton = tester.widget<OutlinedButton>(
        find.byKey(const Key('verificacion_email_reenviar')),
      );
      expect(boton.onPressed, isNull, reason: 'bloqueado, sin cuenta regresiva de 60 s');
      expect(find.byKey(const Key('verificacion_email_progreso')), findsNothing);

      // A los 59 minutos sigue bloqueado; a los 60 se libera.
      ahora = ahora.add(const Duration(minutes: 59));
      await tester.pump(const Duration(minutes: 59));
      expect(find.byKey(const Key('verificacion_email_limite')), findsOneWidget);

      ahora = ahora.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.byKey(const Key('verificacion_email_limite')), findsNothing);
      final libre = tester.widget<OutlinedButton>(
        find.byKey(const Key('verificacion_email_reenviar')),
      );
      expect(libre.onPressed, isNotNull);
    });

    testWidgets('un servidor caído (sin 429) no bloquea el reenvío', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..fallaAlReenviar = const ServidorException(status: 500);
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_limite')), findsNothing);
      expect(find.byKey(const Key('verificacion_email_error_general')), findsOneWidget);
    });
  });

  // HU-AUTH-002, vista 12-A06 (#249): el candado de una hora tras el rechazo por límite es por
  // dirección de correo y se guarda en el teléfono, no en la memoria de la pantalla.
  group('VerificacionEmailPage — candado por correo y persistente (#249)', () {
    final base = DateTime(2026, 10, 8, 10);
    const lucia = 'lucia.silva@correo.com';
    const textoLimite = 'Demasiados intentos. Probá nuevamente en una hora.';
    const unaHora = Duration(minutes: 60);

    final aviso = find.byKey(const Key('verificacion_email_limite'));
    final botonReenviar = find.byKey(const Key('verificacion_email_reenviar'));
    final campo = find.byKey(const Key('verificacion_email_campo'));

    AuthRemoteDataSourceEnMemoria remotoSano() =>
        AuthRemoteDataSourceEnMemoria(credenciales: const {lucia: 'Secreto123'});

    AuthRemoteDataSourceEnMemoria remotoConLimite() => remotoSano()
      ..fallaAlReenviar = const ServidorException(
        status: 429,
        mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
      );

    bool habilitado(WidgetTester tester) =>
        tester.widget<ButtonStyleButton>(botonReenviar).onPressed != null;

    /// La pantalla sobre una inicial: se abre, se vuelve atrás y se reentra con el mismo teléfono.
    Future<void> montarPila(
      WidgetTester tester, {
      required AuthRemoteDataSourceEnMemoria remote,
      required BloqueoReenvioVerificacionRepository bloqueos,
      DateTime Function()? ahora,
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(bloqueos),
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
                        email: lucia,
                        password: 'Secreto123',
                        ahora: ahora ?? DateTime.now,
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

    group('lo que se ve al abrir', () {
      testWidgets('dado un candado guardado de este correo, cuando se abre la pantalla, el '
          'reenvío sale bloqueado con el texto de la vista (A06)', (tester) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({lucia: base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 30)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
        expect(find.text(textoLimite), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsWidgets);
        expect(habilitado(tester), isFalse);
        expect(find.byKey(const Key('verificacion_email_progreso')), findsNothing);
      });

      testWidgets('el correo se compara sin mayúsculas ni espacios', (tester) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({lucia: base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          email: ' Lucia.Silva@Correo.COM ',
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 5)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);
      });

      testWidgets('dado el candado de OTRA dirección, cuando se abre, este correo sigue libre', (
        tester,
      ) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({'ana@correo.com': base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 5)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);
      });

      testWidgets('a los 59 min 59 s el candado sigue; a los 60 min exactos ya no', (tester) async {
        var ahora = base.add(const Duration(minutes: 59, seconds: 59));
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({lucia: base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => ahora,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);

        ahora = base.add(unaHora);
        await tester.pump(const Duration(seconds: 1));

        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);
      });

      testWidgets('un candado ya vencido en el teléfono no bloquea', (tester) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({lucia: base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => base.add(const Duration(hours: 3)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);
      });

      testWidgets('con muchos candados guardados de otras direcciones, solo se bloquea la '
          'propia', (tester) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({
          for (var i = 0; i < 300; i++) 'persona$i@correo.com': base.add(unaHora),
        });
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 1)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();
        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);

        await bloqueos.guardar(lucia, base.add(unaHora), ahora: base);
        await _desmontar(tester);
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 1)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
      });

      testWidgets('el candado vence con la pantalla abierta, el de otra dirección no la '
          'desbloquea antes', (tester) async {
        var ahora = base.add(const Duration(minutes: 1));
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({
          'ana@correo.com': base.add(const Duration(minutes: 20)),
          lucia: base.add(const Duration(minutes: 50)),
        });
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => ahora,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);

        // Vence el de Ana (el primero): el de Lucia sigue.
        ahora = base.add(const Duration(minutes: 20));
        await tester.pump(const Duration(minutes: 19));
        expect(aviso, findsOneWidget);

        ahora = base.add(const Duration(minutes: 50));
        await tester.pump(const Duration(minutes: 30));
        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);
      });

      testWidgets('al volver a primer plano con el reloj adelantado, el candado vencido se '
          'libera', (tester) async {
        var ahora = base.add(const Duration(minutes: 10));
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({lucia: base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => ahora,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);

        ahora = base.add(const Duration(minutes: 61));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);
      });
    });

    group('el rechazo por límite (429) se guarda', () {
      testWidgets('dado un 429, cuando se reenvía, el candado queda guardado con el correo '
          'normalizado y vence a la hora', (tester) async {
        final bloqueos = _BloqueosEspiados();
        await _montarPagina(
          tester,
          remote: remotoConLimite(),
          email: 'Lucia.Silva@Correo.com',
          password: 'Secreto123',
          ahora: () => base,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);
        expect(await bloqueos.leer(), {lucia: base.add(unaHora).toUtc()});
      });

      testWidgets('dado un 429, cuando se sale de la pantalla y se vuelve a entrar, sigue '
          'bloqueado', (tester) async {
        final bloqueos = _BloqueosEspiados();
        var ahora = base;
        await montarPila(tester, remote: remotoConLimite(), bloqueos: bloqueos, ahora: () => ahora);
        await tester.tap(find.byKey(const Key('abrir_verificacion')));
        await tester.pumpAndSettle();
        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);

        await tester.tap(find.byKey(const Key('verificacion_email_volver_login')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('abrir_verificacion')), findsOneWidget);

        ahora = base.add(const Duration(minutes: 10));
        await tester.tap(find.byKey(const Key('abrir_verificacion')));
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);
      });

      testWidgets('dado un 429, cuando se reinicia la app (almacén seguro), el candado sigue '
          'vigente y "borrar datos" lo limpia', (tester) async {
        final almacen = AlmacenSeguroEnMemoria();
        var ahora = base;
        await _montarPagina(
          tester,
          remote: remotoConLimite(),
          password: 'Secreto123',
          ahora: () => ahora,
          bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
        );
        await tester.pumpAndSettle();
        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);
        expect(almacen.contenido.keys, [ClaveSegura.bloqueoReenvioVerificacion]);

        // La app se cierra y se abre media hora después, con otra instancia sobre el mismo almacén.
        await _desmontar(tester);
        ahora = base.add(const Duration(minutes: 30));
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => ahora,
          bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
        );
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);

        // Pasada la hora, libre.
        ahora = base.add(const Duration(minutes: 61));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);

        // «Borrar datos»: sin el valor del almacén, no hay candado.
        await almacen.borrar(ClaveSegura.bloqueoReenvioVerificacion);
        await _desmontar(tester);
        await _montarPagina(
          tester,
          remote: remotoSano(),
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 30)),
          bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
        );
        await tester.pumpAndSettle();
        expect(aviso, findsNothing);
      });

      testWidgets('con el almacén roto, el 429 igual bloquea mientras la pantalla está abierta', (
        tester,
      ) async {
        final almacen = AlmacenSeguroEnMemoria()..simularFalla = true;
        await _montarPagina(
          tester,
          remote: remotoConLimite(),
          password: 'Secreto123',
          ahora: () => base,
          bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
        );
        await tester.pumpAndSettle();
        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);

        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);
        expect(tester.takeException(), isNull);
      });
    });

    group('casos límite', () {
      testWidgets('doble toque con el 429 en vuelo: se guarda un solo candado', (tester) async {
        final bloqueos = _BloqueosEspiados();
        final remote = remotoConLimite()..demoraReenvio = Completer<void>();
        await _montarPagina(
          tester,
          remote: remote,
          password: 'Secreto123',
          ahora: () => base,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        await tester.tap(botonReenviar);
        await tester.pump();
        await tester.tap(botonReenviar, warnIfMissed: false);
        await tester.pump();
        remote.demoraReenvio!.complete();
        await tester.pumpAndSettle();

        expect(bloqueos.guardados, [lucia]);
        expect(aviso, findsOneWidget);
      });

      testWidgets('falla a mitad (500): sin candado, el botón vuelve a habilitarse y se puede '
          'reintentar', (tester) async {
        final bloqueos = _BloqueosEspiados();
        final remote = remotoSano()..fallaAlReenviar = const ServidorException(status: 500);
        await _montarPagina(
          tester,
          remote: remote,
          password: 'Secreto123',
          ahora: () => base,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('verificacion_email_error_general')), findsOneWidget);
        expect(aviso, findsNothing);
        expect(bloqueos.guardados, isEmpty);
        expect(habilitado(tester), isTrue);

        remote.fallaAlReenviar = null;
        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();

        expect(remote.reenviosPorEmail[lucia], 1);
        expect(bloqueos.guardados, isEmpty);
      });

      testWidgets('sin conexión (A08): sin candado y el botón sigue habilitado', (tester) async {
        final bloqueos = _BloqueosEspiados();
        final remote = remotoSano()..simularSinConexion = true;
        await _montarPagina(
          tester,
          remote: remote,
          password: 'Secreto123',
          ahora: () => base,
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();

        expect(aviso, findsNothing);
        expect(bloqueos.guardados, isEmpty);
        expect(habilitado(tester), isTrue);
      });

      testWidgets('el 429 llega con la pantalla ya cerrada: el candado se guarda igual y al '
          'reentrar está', (tester) async {
        final bloqueos = _BloqueosEspiados();
        final remote = remotoConLimite()..demoraReenvio = Completer<void>();
        await montarPila(tester, remote: remote, bloqueos: bloqueos, ahora: () => base);
        await tester.tap(find.byKey(const Key('abrir_verificacion')));
        await tester.pumpAndSettle();

        await tester.tap(botonReenviar);
        await tester.pump();
        await tester.tap(find.byKey(const Key('verificacion_email_volver_login')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('abrir_verificacion')), findsOneWidget);

        remote.demoraReenvio!.complete();
        await tester.pumpAndSettle();
        expect(bloqueos.guardados, [lucia]);

        await tester.tap(find.byKey(const Key('abrir_verificacion')));
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('un reenvío pedido mientras se leen los candados espera: con la dirección '
          'bloqueada no se manda ningún correo', (tester) async {
        final bloqueos = _BloqueosEspiados({lucia: base.add(unaHora)})
          ..demoraLectura = Completer<void>();
        final remote = remotoSano();
        await _montarPagina(
          tester,
          remote: remote,
          password: 'Secreto123',
          ahora: () => base.add(const Duration(minutes: 5)),
          bloqueos: bloqueos,
        );
        await tester.pump();
        expect(aviso, findsNothing, reason: 'todavía no se sabe');

        await tester.tap(botonReenviar);
        await tester.pump();
        bloqueos.demoraLectura!.complete();
        await tester.pumpAndSettle();

        expect(remote.reenviosPorEmail, isEmpty);
        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);
      });

      testWidgets('un reenvío pedido mientras se leen los candados, con la dirección libre, '
          'sale cuando termina la lectura', (tester) async {
        final bloqueos = _BloqueosEspiados()..demoraLectura = Completer<void>();
        final remote = remotoSano();
        await _montarPagina(
          tester,
          remote: remote,
          password: 'Secreto123',
          ahora: () => base,
          bloqueos: bloqueos,
        );
        await tester.pump();

        await tester.tap(botonReenviar);
        await tester.pump();
        bloqueos.demoraLectura!.complete();
        await tester.pumpAndSettle();

        expect(remote.reenviosPorEmail[lucia], 1);
        expect(find.byKey(const Key('verificacion_email_mensaje_reenvio')), findsOneWidget);
      });

      testWidgets('textScaler 2.0 y un correo larguísimo con el candado: sin overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const largo =
            'nombre.muy.largo.de.un.colportor.con.apellido.compuesto@organizacion-con-dominio-'
            'largo.com.uy';
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({largo: base.add(unaHora)});
        await _montarPagina(
          tester,
          remote: remotoSano(),
          email: largo,
          password: 'Secreto123',
          escalaTexto: 2,
          ahora: () => base.add(const Duration(minutes: 1)),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        expect(aviso, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('sin correo conocido (el enlace expiró y se escribe a mano)', () {
      Future<void> montarSinCorreo(
        WidgetTester tester, {
        required AuthRemoteDataSourceEnMemoria remote,
        required BloqueoReenvioVerificacionRepository bloqueos,
        DateTime Function()? ahora,
      }) => _montarPagina(
        tester,
        remote: remote,
        email: '',
        estadoInicial: EstadoVerificacionEmail.expirado,
        ahora: ahora ?? () => base,
        bloqueos: bloqueos,
      );

      testWidgets('el candado sigue a la dirección que se escribe: la bloqueada, bloqueada; otra, '
          'libre', (tester) async {
        final bloqueos = BloqueoReenvioVerificacionEnMemoria({'ana@correo.com': base.add(unaHora)});
        await montarSinCorreo(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();
        expect(aviso, findsNothing, reason: 'sin dirección escrita no hay candado');

        await tester.enterText(campo, 'ana@correo.com');
        await tester.pump();
        expect(aviso, findsOneWidget);
        expect(habilitado(tester), isFalse);

        await tester.enterText(campo, '  ANA@Correo.com ');
        await tester.pump();
        expect(aviso, findsOneWidget);

        await tester.enterText(campo, 'luis@correo.com');
        await tester.pump();
        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);

        await tester.enterText(campo, 'ana@correo.com');
        await tester.pump();
        expect(aviso, findsOneWidget);
      });

      testWidgets('dos reenvíos seguidos a direcciones distintas: cada 429 bloquea la suya', (
        tester,
      ) async {
        final bloqueos = _BloqueosEspiados();
        await montarSinCorreo(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {})
            ..fallaAlReenviar = const ServidorException(status: 429),
          bloqueos: bloqueos,
        );
        await tester.pumpAndSettle();

        await tester.enterText(campo, 'ana@correo.com');
        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);

        await tester.enterText(campo, 'luis@correo.com');
        await tester.pump();
        expect(aviso, findsNothing);
        expect(habilitado(tester), isTrue);
        await tester.tap(botonReenviar);
        await tester.pumpAndSettle();
        expect(aviso, findsOneWidget);

        await tester.enterText(campo, 'ana@correo.com');
        await tester.pump();
        expect(aviso, findsOneWidget);
        expect(bloqueos.guardados, ['ana@correo.com', 'luis@correo.com']);
      });

      testWidgets('cambiar la dirección con el reenvío en vuelo: el 429 bloquea la que se envió, '
          'no la que se ve', (tester) async {
        final bloqueos = _BloqueosEspiados();
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
          ..fallaAlReenviar = const ServidorException(status: 429)
          ..demoraReenvio = Completer<void>();
        await montarSinCorreo(tester, remote: remote, bloqueos: bloqueos);
        await tester.pumpAndSettle();

        await tester.enterText(campo, 'ana@correo.com');
        await tester.tap(botonReenviar);
        await tester.pump();
        await tester.enterText(campo, 'luis@correo.com');
        await tester.pump();
        remote.demoraReenvio!.complete();
        await tester.pumpAndSettle();

        expect(bloqueos.guardados, ['ana@correo.com']);
        expect(aviso, findsNothing, reason: 'la que se ve (Luis) está libre');
        expect(habilitado(tester), isTrue);

        await tester.enterText(campo, 'ana@correo.com');
        await tester.pump();
        expect(aviso, findsOneWidget);
      });
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

  group('VerificacionEmailPage — vista 12', () {
    testWidgets('A01 pendiente: correo destacado en una tarjeta, textos del diseño y acciones al '
        'pie', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();

      expect(find.text('VERIFICACIÓN DE EMAIL'), findsOneWidget);
      expect(find.text('Verificá tu cuenta'), findsOneWidget);
      expect(find.text('Te enviamos un correo a'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('verificacion_email_tarjeta')),
          matching: find.text('lucia.silva@correo.com'),
        ),
        findsOneWidget,
      );
      expect(find.text('Abrí el enlace para verificar tu cuenta.'), findsOneWidget);
      expect(find.text('Si no lo encontrás, revisá la carpeta de spam.'), findsOneWidget);
      expect(find.text('Ya verifiqué mi email'), findsOneWidget);
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(find.text('Volver al login'), findsOneWidget);
      // Las acciones van al pie, en este orden.
      final ya = tester.getTopLeft(find.byKey(const Key('verificacion_email_ya_verifique'))).dy;
      final reenviar = tester.getTopLeft(find.byKey(const Key('verificacion_email_reenviar'))).dy;
      final volver = tester.getTopLeft(find.byKey(const Key('verificacion_email_volver_login'))).dy;
      expect(ya, lessThan(reenviar));
      expect(reenviar, lessThan(volver));
      expect(volver, greaterThan(650));
    });

    testWidgets('A02 reenviado: el aviso de éxito reemplaza el texto y la cuenta regresiva muestra '
        'su barra de avance', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('verificacion_email_progreso')), findsNothing);

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(find.text('Te reenviamos el correo. Puede tardar unos minutos.'), findsOneWidget);
      expect(find.text('Te enviamos un correo a'), findsNothing);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      final progreso = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('verificacion_email_progreso')),
      );
      expect(progreso.value, 1);

      await tester.pump(const Duration(seconds: 15));
      expect(find.text('Reenviar en 45s'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(find.byKey(const Key('verificacion_email_progreso')))
            .value,
        0.75,
      );
    });

    testWidgets('A08 sin conexión al reenviar: dice qué pasa y qué hacer, sin cooldown', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..simularSinConexion = true;
      await _montarPagina(tester, remote: remote, password: 'Secreto123');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('verificacion_email_reenviar')));
      await tester.pumpAndSettle();

      expect(
        find.text('Necesitás conexión para reenviar el email. Conectate y probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_progreso')), findsNothing);
    });

    testWidgets('A04 enlace expirado: título, apoyo con el correo y "Reenviar email de '
        'verificación"', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote, estadoInicial: EstadoVerificacionEmail.expirado);
      await tester.pumpAndSettle();

      expect(find.text('El enlace expiró'), findsOneWidget);
      expect(
        find.text(
          'Pedí uno nuevo y abrilo desde este teléfono. Lo mandamos a lucia.silva@correo.com.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(find.text('Volver al login'), findsOneWidget);
    });

    testWidgets(
      'A07 verificado: sin la etiqueta de verificación, con el mensaje literal de la HU',
      (tester) async {
        await _montarPilaConPantallaInicial(
          tester,
          estadoInicial: EstadoVerificacionEmail.verificado,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('abrir_verificacion')));
        await tester.pumpAndSettle();

        expect(find.text('Email verificado'), findsOneWidget);
        expect(find.text('VERIFICACIÓN DE EMAIL'), findsNothing);
        expect(find.text('Continuar'), findsOneWidget);
      },
    );
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

/// Saca la pantalla del árbol (como cerrar la app) para volver a montarla desde cero.
Future<void> _desmontar(WidgetTester tester) => tester.pumpWidget(const SizedBox());

/// Candados en memoria que anotan qué se guardó y que pueden demorar la lectura, para probar el
/// reenvío mientras la pantalla todavía está leyendo lo que guardó el teléfono.
final class _BloqueosEspiados implements BloqueoReenvioVerificacionRepository {
  _BloqueosEspiados([Map<String, DateTime> inicial = const {}])
    : _real = BloqueoReenvioVerificacionEnMemoria(inicial);

  final BloqueoReenvioVerificacionEnMemoria _real;

  /// Los correos que se guardaron, en orden.
  final List<String> guardados = [];

  /// Si no es `null`, [leer] no sigue hasta que el test lo complete.
  Completer<void>? demoraLectura;

  @override
  Future<Map<String, DateTime>> leer() async {
    await demoraLectura?.future;
    return _real.leer();
  }

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) {
    guardados.add(correo);
    return _real.guardar(correo, vence, ahora: ahora);
  }
}
