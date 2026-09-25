// HU-AUTH-009 — preparación de la DB local cifrada después del login (#27). Un test por escenario
// de aceptación con su título literal, los estados de la pantalla y la accesibilidad (tamaño de
// toque, etiquetas y contraste en 390x844; texto al 200 % en 360x740). La app entera con fakes: el
// login publica la sesión y la raíz no muestra la pantalla principal hasta que la DB está abierta.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/preparacion_db_local_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/password_para_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _password = 'Secreto123';

late DbLocalRepositoryEnMemoria _db;

Finder get _principal => find.byType(JornadaPage);
Finder get _preparacion => find.byType(PreparacionDbLocalPage);
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
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(_db),
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

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_boton(key));
  await tester.tap(_boton(key));
  await tester.pumpAndSettle();
}

/// Una DB ya creada en el teléfono, con su DEK en [dekEnAlmacen] (o sin ella, si el almacén la
/// perdió) y un envoltorio por contraseña si [conEnvoltorio].
void _dbExistente({required bool dekEnAlmacen, required bool conEnvoltorio}) {
  final dek = Uint8List.fromList(List<int>.filled(32, 9));
  _db
    ..marca = MarcaDbLocal.puesta
    ..archivo = true
    ..claveDelArchivo = dek
    ..dekEnAlmacen = dekEnAlmacen ? dek : null
    ..envoltorio = conEnvoltorio ? (dek: dek, password: _password) : null;
}

void main() {
  setUp(() => _db = DbLocalRepositoryEnMemoria());

  group('HU-AUTH-009 — criterios de aceptación', () {
    testWidgets('Escenario: Inicialización exitosa — muestra el progreso ("Preparando tu espacio '
        'seguro… 1/3, 2/3, 3/3"), envuelve la DEK con mi contraseña, crea la DB y navega a la '
        'pantalla principal', (tester) async {
      _db.argon2idPendiente = Completer<void>();
      await _entrar(tester, esperar: false);
      await tester.pump();
      await tester.pump();

      expect(_preparacion, findsOneWidget);
      expect(find.text('Preparando tu espacio seguro… 2/3'), findsOneWidget);
      expect(_principal, findsNothing);

      _db.argon2idPendiente!.complete();
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
      expect(_db.abierta, isTrue);
      expect(_db.marca, MarcaDbLocal.puesta);
      expect(
        _db.llamadas,
        containsAllInOrder(['bloqueo', 'nivel', 'crearDek', 'envolver', 'abrir', 'marcar']),
      );
    });

    testWidgets('Escenario: Error -equipo sin bloqueo de pantalla — no inicializa la DB y explica '
        'por qué hace falta el bloqueo y cómo configurarlo', (tester) async {
      _db.bloqueoPantalla = false;
      await _entrar(tester);

      expect(find.text(const FailureSinBloqueoPantalla().mensaje), findsOneWidget);
      expect(_db.abierta, isFalse);
      expect(_db.llamadas, isNot(contains('crearDek')));

      _db.bloqueoPantalla = true;
      await _tocar(tester, 'preparacion_db_reintentar');

      expect(_principal, findsOneWidget);
    });

    testWidgets('Escenario: Keystore por software -consentimiento explícito — si acepta, sigue con '
        'el mismo almacén y registra la elección', (tester) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);

      expect(
        find.text(
          'Tu dispositivo tiene almacenamiento menos seguro. Los datos siguen cifrados pero el '
          'nivel de protección es menor.',
        ),
        findsOneWidget,
      );
      expect(find.text('Entiendo el riesgo y quiero continuar'), findsOneWidget);
      expect(_db.llamadas, isNot(contains('crearDek')));

      await _tocar(tester, 'preparacion_db_aceptar_riesgo');

      expect(_principal, findsOneWidget);
      expect(_db.consentimiento, isTrue);
    });

    testWidgets('Escenario: Keystore por software -consentimiento explícito — si declina, aborta '
        'con instrucción de cómo usar otro dispositivo', (tester) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_cancelar_riesgo');

      expect(find.text(TextosPreparacionDbLocal.otroCelular), findsOneWidget);
      expect(_db.llamadas, isNot(contains('crearDek')));
      expect(_db.consentimiento, isFalse);

      // Si cambia de idea, vuelve a la advertencia.
      await _tocar(tester, 'preparacion_db_continuar_con_este');
      expect(find.text('Entiendo el riesgo y quiero continuar'), findsOneWidget);
    });

    testWidgets('Escenario: Error -falla al escribir en secure_storage — mensaje accionable y el '
        'dispositivo no queda marcado como inicializado', (tester) async {
      _db.fallas['crearDek'] = const FailureAlmacenSeguro();
      await _entrar(tester);

      expect(
        find.text(
          'No pudimos preparar el almacenamiento seguro. Consultá a soporte antes de reinstalar '
          'la app.',
        ),
        findsOneWidget,
      );
      expect(_db.marca, MarcaDbLocal.ausente);
      expect(_db.dekEnAlmacen, isNull, reason: 'limpia cualquier estado parcial');
    });

    testWidgets('Escenario: Error -sin espacio en disco — aborta limpiamente con "No hay espacio '
        'suficiente para preparar el app" y borra el archivo parcial', (tester) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      await _entrar(tester);

      expect(find.text('No hay espacio suficiente para preparar el app'), findsOneWidget);
      expect(find.text(TextosPreparacionDbLocal.sinEspacioQueHacer), findsOneWidget);
      expect(_db.archivo, isFalse);
      expect(_db.marca, MarcaDbLocal.ausente);
    });

    testWidgets('Escenario: Edge -DB local con un esquema posterior al de la app — pantalla '
        'bloqueante con "Actualizar" y sin "empezar de nuevo"', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: true);
      _db.fallas['abrir'] = const FailureEsquemaPosterior();
      await _entrar(tester);

      expect(
        find.text(
          'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
          'datos.',
        ),
        findsOneWidget,
      );
      expect(_boton('preparacion_db_empezar_de_nuevo'), findsNothing);
      expect(_boton('preparacion_db_reintentar'), findsNothing);

      await _tocar(tester, 'preparacion_db_actualizar');

      expect(find.text(TextosPreparacionDbLocal.actualizarComo), findsOneWidget);
      expect(_db.archivo, isTrue, reason: 'ni migra ni borra');
    });
  });

  group('Cuenta con contraseña y DB sin envoltorio (revisión del PR #130)', () {
    testWidgets('dada una sesión restaurada sin DB, pide la contraseña antes de crear nada; con la '
        'correcta crea la DB con envoltorio', (tester) async {
      await _entrar(tester, restaurada: true);

      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
      expect(_db.llamadas, isNot(contains('crearDek')));

      await tester.enterText(_boton('preparacion_db_password'), 'equivocada');
      await _tocar(tester, 'preparacion_db_confirmar_password');
      expect(find.text(TextosPreparacionDbLocal.passwordIncorrecta), findsOneWidget);
      expect(_principal, findsNothing);

      await tester.enterText(_boton('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
    });

    testWidgets('dada una DB existente sin envoltorio, pide la contraseña antes de darla por lista '
        'y la protege sin tocar sus datos', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: false);
      await _entrar(tester, restaurada: true);

      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
      expect(_db.abierta, isFalse);

      await tester.enterText(_boton('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
      expect(_db.llamadas, isNot(contains('descartar')));
    });

    testWidgets('quien no recuerda la contraseña (entra con Google, por ejemplo) no queda '
        'encerrado: "¿Olvidaste tu contraseña?" lleva a restablecerla con el email de la sesión '
        '(N1)', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: false);
      await _entrar(tester, restaurada: true);
      expect(find.text(TextosPreparacionDbLocal.olvidePassword), findsOneWidget);

      await _tocar(tester, 'preparacion_db_olvide_password');

      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      final email = tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email')));
      expect(email.controller!.text, _email);
      expect(_db.llamadas, isNot(contains('descartar')), reason: 'no toca la DB del teléfono');

      await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
      await tester.pumpAndSettle();
      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
    });
  });

  group('Reintentar (#27)', () {
    testWidgets('dada una falla pasajera del almacén (un Keystore que no respondió a tiempo), '
        '"Reintentar" termina la preparación', (tester) async {
      _db.fallas['nivel'] = const FailureAlmacenSeguro();
      await _entrar(tester);
      expect(_principal, findsNothing);

      _db.fallas.remove('nivel');
      await _tocar(tester, 'preparacion_db_reintentar');

      expect(_principal, findsOneWidget);
    });

    testWidgets('el reintento después de liberar espacio también arma el envoltorio con la '
        'contraseña del login', (tester) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      await _entrar(tester);

      _db.fallas.remove('abrir');
      await _tocar(tester, 'preparacion_db_reintentar');

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
    });
  });

  group('Recuperación guiada (ADR-006)', () {
    testWidgets('dado que el almacén perdió la DEK y hay envoltorio, pide la contraseña y con la '
        'correcta abre la DB que ya estaba', (tester) async {
      _dbExistente(dekEnAlmacen: false, conEnvoltorio: true);
      await _entrar(tester);

      expect(
        find.text('Tu almacenamiento seguro falló. Ingresá tu contraseña para recuperar tus datos'),
        findsOneWidget,
      );

      await tester.enterText(_boton('preparacion_db_password'), 'otra');
      await _tocar(tester, 'preparacion_db_recuperar');
      expect(find.text(const FailurePasswordNoAbreDatos().mensaje), findsOneWidget);
      expect(_principal, findsNothing);

      await tester.enterText(_boton('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_recuperar');

      expect(_principal, findsOneWidget);
      expect(_db.archivo, isTrue, reason: 'nunca se borra');
    });

    testWidgets(
      'sin envoltorio, primero solo ofrece reintentar; "empezar de nuevo" aparece después '
      'de un reintento que vuelve a fallar',
      (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
        await _entrar(tester);

        expect(find.text(const FailureAlmacenSeguroSinRecuperacion().mensaje), findsOneWidget);
        expect(_boton('preparacion_db_reintentar'), findsOneWidget);
        expect(_boton('preparacion_db_empezar_de_nuevo'), findsNothing);

        await _tocar(tester, 'preparacion_db_reintentar');

        expect(_boton('preparacion_db_empezar_de_nuevo'), findsOneWidget);
        expect(_db.archivo, isTrue, reason: 'reintentar no borra nada');
      },
    );

    testWidgets(
      '"empezar de nuevo" pide confirmación: cancelar no borra; confirmar borra y prepara '
      'una DB nueva',
      (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_reintentar');

        await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
        expect(find.text(TextosPreparacionDbLocal.empezarDeNuevoDetalle), findsOneWidget);
        await _tocar(tester, 'preparacion_db_cancelar_empezar');
        expect(_db.llamadas, isNot(contains('descartar')));
        expect(_db.archivo, isTrue);

        await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
        await _tocar(tester, 'preparacion_db_confirmar_empezar');

        expect(_principal, findsOneWidget);
        expect(_db.llamadas, contains('descartar'));
        expect(
          _db.envoltorio!.password,
          _password,
          reason: 'la DB nueva ya tiene con qué recuperar',
        );
      },
    );
  });

  group('Cerrar sesión', () {
    testWidgets('desde una falla, vuelve al login sin tocar la DB', (tester) async {
      _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_cerrar_sesion');

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
      expect(_db.archivo, isTrue);
    });
  });

  group('Accesibilidad', () {
    // Cada estado de la pantalla, preparado sobre el fake.
    final estados = <String, Future<void> Function(WidgetTester)>{
      'progreso 2/3': (tester) async {
        _db.argon2idPendiente = Completer<void>();
        await _entrar(tester, esperar: false);
        await tester.pump();
        await tester.pump();
      },
      'sin bloqueo': (tester) async {
        _db.bloqueoPantalla = false;
        await _entrar(tester);
      },
      'consentimiento': (tester) async {
        _db.nivel = NivelAlmacenSeguro.software;
        await _entrar(tester);
      },
      'otro celular': (tester) async {
        _db.nivel = NivelAlmacenSeguro.software;
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_cancelar_riesgo');
      },
      'recuperación con error': (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: true);
        await _entrar(tester);
        await tester.enterText(_boton('preparacion_db_password'), 'otra');
        await _tocar(tester, 'preparacion_db_recuperar');
      },
      'sin recuperación, con empezar de nuevo': (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_reintentar');
      },
      'confirmar contraseña con error': (tester) async {
        await _entrar(tester, restaurada: true);
        await tester.enterText(_boton('preparacion_db_password'), 'equivocada');
        await _tocar(tester, 'preparacion_db_confirmar_password');
      },
      'sin espacio': (tester) async {
        _db.fallas['abrir'] = const FailureSinEspacio();
        await _entrar(tester);
      },
      'esquema posterior': (tester) async {
        _dbExistente(dekEnAlmacen: true, conEnvoltorio: true);
        _db.fallas['abrir'] = const FailureEsquemaPosterior();
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_actualizar');
      },
    };

    for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
      testWidgets('$nombre: tamaño de toque, etiquetas y contraste en 390x844', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await preparar(tester);

        expect(_preparacion, findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        _db.argon2idPendiente?.complete();
        handle.dispose();
      });

      testWidgets('$nombre: sin overflow con el texto al 200 % en 360x740', (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await preparar(tester);

        expect(_preparacion, findsOneWidget);
        expect(tester.takeException(), isNull);
        _db.argon2idPendiente?.complete();
      });
    }

    testWidgets('el diálogo de "empezar de nuevo": tamaño de toque, etiquetas y contraste', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
      await _entrar(tester);
      await _tocar(tester, 'preparacion_db_reintentar');
      await _tocar(tester, 'preparacion_db_empezar_de_nuevo');

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  test('los textos de la HU no cambian sin querer', () {
    expect(TextosPreparacionDbLocal.progreso(1), 'Preparando tu espacio seguro… 1/3');
    expect(TextosPreparacionDbLocal.aceptarRiesgo, 'Entiendo el riesgo y quiero continuar');
  });
}
