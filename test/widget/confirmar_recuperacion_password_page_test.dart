// HU-AUTH-005 — pantalla de la contraseña nueva (#51). Un test por escenario de aceptación con el
// texto literal de la HU, los estados, la validación de cada campo y la accesibilidad (tamaño de
// toque, etiquetas, contraste y texto al 200 %). La app entera, con los fakes en memoria: el enlace
// llega por el mismo camino que en producción (la raíz escucha los enlaces de recuperación).
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/entities/politica_password.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';

late RecuperacionPasswordEnMemoria _recuperacion;
late DbLocalRepositoryEnMemoria _dbLocal;
late AuthRemoteDataSourceEnMemoria _auth;

Finder get _login => find.byKey(const Key('login_enviar'));
Finder get _guardar => find.byKey(const Key('confirmar_recuperacion_guardar'));

/// Monta la app sin sesión (o con una, si [conSesion]) y hace llegar [enlace].
Future<ProviderContainer> _montar(
  WidgetTester tester, {
  EnlaceRecuperacion enlace = EnlaceRecuperacion.valido,
  bool conSesion = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_auth),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
      dbLocalRepositoryProvider.overrideWithValue(_dbLocal),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  if (conSesion) {
    await container
        .read(sesionProvider.notifier)
        .iniciarSesion(email: _email, password: 'Vieja1234');
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  _recuperacion.simularEnlace(enlace);
  await tester.pumpAndSettle();
  return container;
}

/// Solo la pantalla, sin la app alrededor.
Future<void> _montarSolo(WidgetTester tester, EnlaceRecuperacion enlace) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(_auth),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
        dbLocalRepositoryProvider.overrideWithValue(_dbLocal),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: ConfirmarRecuperacionPasswordPage(enlace: enlace),
      ),
    ),
  );
  if (enlace == EnlaceRecuperacion.valido) _recuperacion.simularEnlace(enlace);
  await tester.pumpAndSettle();
}

Future<void> _completar(WidgetTester tester, String nueva, {String? repetida}) async {
  await tester.enterText(find.byKey(const Key('confirmar_recuperacion_nueva')), nueva);
  await tester.enterText(
    find.byKey(const Key('confirmar_recuperacion_repetida')),
    repetida ?? nueva,
  );
}

Future<void> _tocarGuardar(WidgetTester tester) async {
  await tester.ensureVisible(_guardar);
  await tester.tap(_guardar);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
    _dbLocal = DbLocalRepositoryEnMemoria();
    _auth = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: 'Vieja1234'});
  });

  group('HU-AUTH-005 — criterios de aceptación', () {
    testWidgets('Escenario: Cambio exitoso en dispositivo sin DB local previa — actualiza la '
        'contraseña, revoca los JWT y la UI navega al login con "Contraseña actualizada. Iniciá '
        'sesión."', (tester) async {
      await _montar(tester);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(_recuperacion.actualizaciones, ['NuevaClave1']);
      expect(_recuperacion.sesionesCerradas, 1, reason: 'todos los JWT activos quedan revocados');
      expect(_login, findsOneWidget);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_dbLocal.llamadas, isNot(contains('envolver')));
    });

    testWidgets('Escenario: Cambio en dispositivo CON DB local - se re-envuelve la DEK — la DB '
        'local queda intacta y accesible', (tester) async {
      final dek = Uint8List.fromList(List<int>.filled(32, 77));
      _dbLocal
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = dek
        ..dekEnAlmacen = dek
        ..envoltorio = (dek: dek, password: 'Vieja1234');
      await _montar(tester);

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(_dbLocal.envoltorio!.password, 'NuevaClave1');
      expect(_dbLocal.envoltorio!.dek, dek);
      expect(_dbLocal.archivo, isTrue);
      expect(_dbLocal.claveDelArchivo, dek);
      expect(_recuperacion.sesionesCerradas, 1);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });

    testWidgets('Escenario: Error -token expirado — la UI muestra "El enlace expiró. Solicitá uno '
        'nuevo." y ofrece volver a HU-AUTH-004', (tester) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsOneWidget);
      expect(_guardar, findsNothing);

      await tester.tap(find.byKey(const Key('confirmar_recuperacion_pedir_otro')));
      await tester.pumpAndSettle();

      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
    });

    // skip: Supabase manda el mismo `otp_expired` para un enlace vencido y para uno ya usado, así
    // que la app no puede mostrar "Este enlace ya fue utilizado" por separado: los dos casos caen
    // en "El enlace expiró. Solicitá uno nuevo.". Queda para decidir en #50 (como la heurística de
    // HU-AUTH-002 para la verificación). `testWidgets.skip` es `bool?`: el motivo va acá.
    testWidgets('Escenario: Error -token reutilizado — "Este enlace ya fue utilizado" y volver al '
        'login', (tester) async {
      fail('Supabase no distingue un enlace usado de uno vencido (#50)');
    }, skip: true);
  });

  group('Enlace vencido', () {
    testWidgets('"Volver al login" lleva al login sin tocar nada', (tester) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      await tester.tap(find.byKey(const Key('confirmar_recuperacion_ir_al_login')));
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(_recuperacion.abandonos, 0);
    });

    testWidgets('si la sesión del enlace vence mientras la pantalla está abierta, al guardar pasa '
        'a "El enlace expiró"', (tester) async {
      await _montar(tester);
      _recuperacion.vencerSesionDeRecuperacion();

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsOneWidget);
      expect(_recuperacion.actualizaciones, isEmpty);
    });

    for (final (boton, destino) in [
      ('confirmar_recuperacion_ir_al_login', 'el login'),
      ('confirmar_recuperacion_pedir_otro', 'pedir otro enlace'),
    ]) {
      testWidgets('dado que el servidor rechaza la sesión que el teléfono guarda, al ir a $destino '
          'la suelta: el próximo arranque no entra sin contraseña (revisión de #112)', (
        tester,
      ) async {
        await _montar(tester);
        _recuperacion.rechazarSesionDeRecuperacion();
        await _completar(tester, 'NuevaClave1');
        await _tocarGuardar(tester);
        expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsOneWidget);

        await tester.tap(find.byKey(Key(boton)));
        await tester.pumpAndSettle();

        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
        expect(_recuperacion.abandonos, 1);
        expect(_recuperacion.haySesionDeRecuperacion, isFalse);
      });
    }
  });

  group('Enlace sin conexión (revisión de #112)', () {
    testWidgets('dice qué pasa y qué hacer; "Volver al login" no suelta nada (no se abrió ninguna '
        'sesión)', (tester) async {
      await _montar(tester, enlace: EnlaceRecuperacion.sinConexion);

      expect(
        find.text(
          'Necesitás conexión para abrir el enlace. Cuando tengas señal, volvé a abrirlo desde el '
          'correo.',
        ),
        findsOneWidget,
      );
      expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsNothing);
      expect(_guardar, findsNothing);

      await tester.tap(find.byKey(const Key('confirmar_recuperacion_ir_al_login')));
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(_recuperacion.abandonos, 0);
    });
  });

  group('Enlaces repetidos (revisión de #112)', () {
    testWidgets('dado un segundo enlace válido sin cerrar la app, vuelve a abrir la pantalla', (
      tester,
    ) async {
      await _montar(tester);
      await tester.tap(find.byKey(const Key('confirmar_recuperacion_atras')));
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);

      _recuperacion.simularEnlace(EnlaceRecuperacion.valido);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);
    });

    testWidgets('dados dos enlaces vencidos seguidos, los dos avisan', (tester) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);
      await tester.tap(find.byKey(const Key('confirmar_recuperacion_ir_al_login')));
      await tester.pumpAndSettle();

      _recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
      await tester.pumpAndSettle();

      expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsOneWidget);
    });
  });

  group('Validación de la contraseña nueva', () {
    testWidgets('vacía: pide las dos', (tester) async {
      await _montar(tester);

      await _tocarGuardar(tester);

      expect(find.text('Ingresá la contraseña nueva'), findsOneWidget);
      expect(find.text('Repetí la contraseña nueva'), findsOneWidget);
      expect(_recuperacion.actualizaciones, isEmpty);
    });

    testWidgets('sin la política del registro: muestra los requisitos como error', (tester) async {
      await _montar(tester);

      await _completar(tester, 'corta');
      await _tocarGuardar(tester);

      // El requisito aparece como error del campo (y deja de ser la ayuda).
      expect(find.text(PoliticaPassword.requisitos), findsOneWidget);
      final campo = tester.widget<TextField>(find.byKey(const Key('confirmar_recuperacion_nueva')));
      expect(campo.decoration?.errorText, PoliticaPassword.requisitos);
    });

    testWidgets('las dos no coinciden', (tester) async {
      await _montar(tester);

      await _completar(tester, 'NuevaClave1', repetida: 'NuevaClave2');
      await _tocarGuardar(tester);

      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    });

    testWidgets('igual a la anterior: lo dice en el campo', (tester) async {
      await _montar(tester);

      await _completar(tester, 'Vieja1234');
      await _tocarGuardar(tester);

      expect(find.text('Tiene que ser distinta de la anterior.'), findsOneWidget);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);
    });

    testWidgets('mostrar/ocultar la contraseña', (tester) async {
      await _montar(tester);
      TextField campo() =>
          tester.widget<TextField>(find.byKey(const Key('confirmar_recuperacion_nueva')));
      expect(campo().obscureText, isTrue);

      await tester.tap(find.byTooltip('Mostrar contraseña').first);
      await tester.pump();

      expect(campo().obscureText, isFalse);
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    });
  });

  group('Estados', () {
    testWidgets('guardando: el botón se deshabilita con progreso y no se puede salir', (
      tester,
    ) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');

      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();

      expect(find.byKey(const Key('confirmar_recuperacion_guardando')), findsOneWidget);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNull);
      final popScope = tester.widget<PopScope<Object?>>(
        find.descendant(
          of: find.byType(ConfirmarRecuperacionPasswordPage),
          matching: find.byWidgetPredicate((w) => w is PopScope),
        ),
      );
      expect(popScope.canPop, isFalse);

      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    testWidgets('sin conexión: "Necesitás conexión para cambiar tu contraseña" y deja reintentar', (
      tester,
    ) async {
      await _montar(tester);
      _recuperacion.simularSinConexion = true;
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(find.text('Necesitás conexión para cambiar tu contraseña'), findsOneWidget);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);

      _recuperacion.simularSinConexion = false;
      await _tocarGuardar(tester);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });

    testWidgets('caso borde: se cortó la conexión pero Supabase ya había aceptado el cambio — el '
        'reintento termina bien, sin "Tiene que ser distinta de la anterior."', (tester) async {
      await _montar(tester);
      _recuperacion.pierdeLaRespuestaAlActualizar = true;
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);
      expect(find.text('Necesitás conexión para cambiar tu contraseña'), findsOneWidget);
      expect(_recuperacion.passwordActual, 'NuevaClave1', reason: 'el servidor ya la tiene');

      await _tocarGuardar(tester);

      expect(find.text('Tiene que ser distinta de la anterior.'), findsNothing);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_recuperacion.sesionesCerradas, 1);
    });

    testWidgets('error del servidor: muestra su mensaje', (tester) async {
      await _montar(tester);
      _recuperacion.fallaAlActualizar = const ServidorException(
        status: 429,
        mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
      );
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(
        find.text('Demasiados intentos. Esperá unos minutos y volvé a probar.'),
        findsOneWidget,
      );
    });

    testWidgets('error inesperado: dice qué pasó y qué hacer', (tester) async {
      await _montar(tester);
      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(find.text(TextosConfirmacionRecuperacion.errorInesperado), findsOneWidget);
    });

    testWidgets('éxito con una sesión iniciada en la app: también la cierra y queda el login', (
      tester,
    ) async {
      final container = await _montar(tester, conSesion: true);
      expect(container.read(sesionProvider).value, isNotNull);

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });

    testWidgets('si revocar las sesiones falla, igual termina bien: la contraseña ya cambió', (
      tester,
    ) async {
      _recuperacion.fallaAlCerrarSesiones = const SinConexionException();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });
  });

  group('Salir sin terminar', () {
    testWidgets('suelta la sesión que abrió el enlace', (tester) async {
      await _montar(tester);

      await tester.tap(find.byKey(const Key('confirmar_recuperacion_atras')));
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(_recuperacion.abandonos, 1);
    });

    testWidgets('después de guardar no la suelta dos veces', (tester) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(_recuperacion.abandonos, 0);
    });
  });

  group('Accesibilidad', () {
    // Paleta única 1b (#121): sin tema oscuro, así que ya no hace falta correr esto por brillo ni
    // saltear el contraste del error (el rojo de `ColorScheme.dark().error` sobre navy, que no
    // llegaba a 4.5:1, se fue junto con el tema oscuro).
    for (final enlace in EnlaceRecuperacion.values) {
      testWidgets('enlace ${enlace.name}: tamaño de toque, etiquetas y contraste', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _montar(tester, enlace: enlace);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        if (enlace == EnlaceRecuperacion.valido) {
          // Con los errores de cada campo y el error general a la vista.
          _recuperacion.simularSinConexion = true;
          await _completar(tester, 'corta', repetida: 'otra');
          await _tocarGuardar(tester);
          await _completar(tester, 'NuevaClave1');
          await _tocarGuardar(tester);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        handle.dispose();
      });
    }

    for (final enlace in EnlaceRecuperacion.values) {
      testWidgets('enlace ${enlace.name}: sin overflow con el texto al 200 % en 360x740', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // La página sola: el LoginPage de la raíz tiene su propio overflow al 200 % (no es de
        // esta pantalla).
        await _montarSolo(tester, enlace);
        if (enlace == EnlaceRecuperacion.valido) {
          _recuperacion.simularSinConexion = true;
          await _completar(tester, 'corta', repetida: 'otra');
          await _tocarGuardar(tester);
          await _completar(tester, 'NuevaClave1');
          await _tocarGuardar(tester);
          expect(find.text('Necesitás conexión para cambiar tu contraseña'), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      });
    }
  });

  test('los textos de la HU no cambian sin querer', () {
    expect(TextosConfirmacionRecuperacion.exito, 'Contraseña actualizada. Iniciá sesión.');
    expect(
      TextosConfirmacionRecuperacion.vencido,
      const FailureEnlaceRecuperacionVencido().mensaje,
    );
  });
}
