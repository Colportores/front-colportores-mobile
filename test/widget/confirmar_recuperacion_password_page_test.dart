// HU-AUTH-005 — pantalla de la contraseña nueva (#51). Un test por escenario de aceptación con el
// texto literal de la HU, los estados, la validación de cada campo y la accesibilidad (tamaño de
// toque, etiquetas, contraste y texto al 200 %). La app entera, con los fakes en memoria: el enlace
// llega por el mismo camino que en producción (la raíz escucha los enlaces de recuperación).
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
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

/// Almacén de sesión que no puede borrar la sesión: el cierre de sesión falla del lado local.
final class _LocalQueNoBorra implements AuthLocalDataSource {
  SesionModel? _sesion;
  bool fallar = true;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async => _sesion = sesion;

  @override
  Future<void> borrarSesion() async {
    if (fallar) throw Exception('keystore');
    _sesion = null;
  }
}

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
  AuthLocalDataSource? local,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_auth),
      authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
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

String _texto(WidgetTester tester, String campo) =>
    tester.widget<TextField>(find.byKey(Key('confirmar_recuperacion_$campo'))).controller!.text;

Finder _req(String cual) => find.byKey(Key('confirmar_recuperacion_req_$cual'));

Future<void> _completar(WidgetTester tester, String nueva, {String? repetida}) async {
  await tester.enterText(find.byKey(const Key('confirmar_recuperacion_nueva')), nueva);
  await tester.enterText(
    find.byKey(const Key('confirmar_recuperacion_repetida')),
    repetida ?? nueva,
  );
  await tester.pump();
}

Finder get _irAlLoginExito => find.byKey(const Key('confirmar_recuperacion_exito_ir_al_login'));

Future<void> _irAlLogin(WidgetTester tester) async {
  await tester.ensureVisible(_irAlLoginExito);
  await tester.tap(_irAlLoginExito);
  await tester.pumpAndSettle();
}

Future<void> _tocarGuardarSinEsperar(WidgetTester tester) async {
  await tester.ensureVisible(_guardar);
  await tester.tap(_guardar);
  await tester.pump();
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
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_dbLocal.llamadas, isNot(contains('envolver')));

      await _irAlLogin(tester);
      expect(_login, findsOneWidget);
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

    // skip (15-A07, lo cubre front-colportores-mobile#247): Supabase manda el mismo `otp_expired` para un enlace vencido y para uno ya usado, así
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

    testWidgets(
      'dos enlaces distintos seguidos SIN que el usuario haga nada en el medio (la raíz los '
      'resuelve sola con popUntil+push): una sola pantalla, con el segundo enlace, y suelta la '
      'sesión que había dejado el primero',
      (tester) async {
        await _montar(tester);
        expect(_guardar, findsOneWidget, reason: 'primer enlace: válido, formulario a la vista');

        _recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
        await tester.pumpAndSettle();

        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);
        expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsOneWidget);
        expect(_guardar, findsNothing);
        expect(_recuperacion.abandonos, 1, reason: 'suelta la sesión que dejó el enlace válido');
      },
    );
  });

  group('Validación de la contraseña nueva', () {
    bool guardarHabilitado(WidgetTester tester) =>
        tester.widget<FilledButton>(_guardar).onPressed != null;

    testWidgets('vacía: «Guardar contraseña» deshabilitado y nada se envía', (tester) async {
      await _montar(tester);

      expect(guardarHabilitado(tester), isFalse);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_recuperacion.actualizaciones, isEmpty);
    });

    testWidgets('sin la política del registro: los requisitos que faltan van con ✕ y el botón '
        'sigue deshabilitado', (tester) async {
      await _montar(tester);

      await _completar(tester, 'corta');
      await tester.pump();

      expect(guardarHabilitado(tester), isFalse);
      expect(find.descendant(of: _req('largo'), matching: find.text('✕')), findsOneWidget);
      expect(find.descendant(of: _req('mayuscula'), matching: find.text('✕')), findsOneWidget);
      expect(find.descendant(of: _req('numero'), matching: find.text('✕')), findsOneWidget);
    });

    testWidgets('mayúscula con tilde o Ñ: «Ñandú2026» y «Élan2026» cumplen y se puede guardar', (
      tester,
    ) async {
      await _montar(tester);
      for (final clave in ['Ñandú2026', 'Élan2026']) {
        await _completar(tester, clave);

        expect(
          find.descendant(of: _req('mayuscula'), matching: find.text('✓')),
          findsOneWidget,
          reason: clave,
        );
        expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull, reason: clave);
      }
      await _completar(tester, 'ñandú2026');
      expect(find.descendant(of: _req('mayuscula'), matching: find.text('✕')), findsOneWidget);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNull);
    });

    testWidgets('el largo cuenta caracteres visibles: un emoji es 1', (tester) async {
      await _montar(tester);

      await _completar(tester, 'Ab1😀😀😀😀');
      expect(find.textContaining('faltan 1', findRichText: true), findsOneWidget);
      expect(find.descendant(of: _req('largo'), matching: find.text('✕')), findsOneWidget);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNull);

      await _completar(tester, 'Ab1😀😀😀😀😀');
      expect(find.descendant(of: _req('largo'), matching: find.text('✓')), findsOneWidget);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);
    });

    testWidgets('15-A03: «faltan N» baja al escribir y los requisitos se tildan de a uno', (
      tester,
    ) async {
      await _montar(tester);
      final campo = find.byKey(const Key('confirmar_recuperacion_nueva'));

      await tester.enterText(campo, 'lucia');
      await tester.pump();
      expect(find.textContaining('faltan 3', findRichText: true), findsOneWidget);
      expect(find.descendant(of: _req('largo'), matching: find.text('✕')), findsOneWidget);

      await tester.enterText(campo, 'Lucia1');
      await tester.pump();
      expect(find.textContaining('faltan 2', findRichText: true), findsOneWidget);
      expect(find.descendant(of: _req('mayuscula'), matching: find.text('✓')), findsOneWidget);
      expect(find.descendant(of: _req('numero'), matching: find.text('✓')), findsOneWidget);

      await tester.enterText(campo, 'Lucia1234');
      await tester.pump();
      expect(find.textContaining('faltan', findRichText: true), findsNothing);
      expect(find.descendant(of: _req('largo'), matching: find.text('✓')), findsOneWidget);
      expect(find.text('CONTRASEÑA NUEVA · ✓ CUMPLE LOS REQUISITOS'), findsOneWidget);
    });

    testWidgets('con el campo vacío los requisitos quedan neutros, sin ✕', (tester) async {
      await _montar(tester);

      expect(find.text('✕'), findsNothing);
      expect(find.text('○'), findsNWidgets(3));
    });

    testWidgets('las dos no coinciden: lo dice en el campo y el botón no se habilita', (
      tester,
    ) async {
      await _montar(tester);

      await _completar(tester, 'NuevaClave1', repetida: 'NuevaClave2');
      await tester.pump();

      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(guardarHabilitado(tester), isFalse);
      expect(find.textContaining('✓ COINCIDEN'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('confirmar_recuperacion_repetida')),
        'NuevaClave1',
      );
      await tester.pump();

      expect(find.text('Las contraseñas no coinciden'), findsNothing);
      expect(find.text('REPETIR CONTRASEÑA · ✓ COINCIDEN'), findsOneWidget);
      expect(guardarHabilitado(tester), isTrue);
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

      expect(find.text('Mostrar contraseña'), findsNWidgets(2));
      await tester.tap(find.text('Mostrar contraseña').first);
      await tester.pump();

      expect(campo().obscureText, isFalse);
      expect(find.text('Ocultar contraseña'), findsOneWidget);
      expect(find.text('Mostrar contraseña'), findsOneWidget, reason: 'el otro sigue oculto');
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
      await _irAlLogin(tester);
      expect(_login, findsOneWidget);
    });

    testWidgets('15-A08 sin conexión: «Sin conexión» con qué hacer, conserva lo escrito y deja '
        'reintentar', (tester) async {
      await _montar(tester);
      _recuperacion.simularSinConexion = true;
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(
        find.text('Conectate para guardar la contraseña. No perdés lo que escribiste.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);
      expect(_texto(tester, 'nueva'), 'NuevaClave1');
      expect(_texto(tester, 'repetida'), 'NuevaClave1');

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
      expect(find.text('Sin conexión'), findsOneWidget);
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
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      await _irAlLogin(tester);
      expect(_login, findsOneWidget);
    });

    testWidgets('si falla el cierre de sesión tras cambiar la contraseña, lo dice y da la salida', (
      tester,
    ) async {
      final container = await _montar(tester, conSesion: true, local: _LocalQueNoBorra());
      expect(container.read(sesionProvider).value, isNotNull);

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(
        find.text(
          'Cambiaste la contraseña, pero no pudimos cerrar la sesión en este teléfono. Cerrala '
          'desde Configuración.',
        ),
        findsOneWidget,
      );
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsNothing);
      expect(container.read(sesionProvider).value, isNotNull, reason: 'la sesión sigue abierta');
      expect(_recuperacion.passwordActual, 'NuevaClave1', reason: 'la contraseña sí cambió');
      expect(find.byKey(const Key('confirmar_recuperacion_guardando')), findsNothing);
      expect(find.text('Ir al login'), findsNothing, reason: 'no manda a un login que no se ve');

      // La salida lleva a la pantalla principal (hay sesión), desde donde se llega a Configuración.
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('con el cierre de sesión bien hecho no aparece el aviso de la sesión abierta', (
      tester,
    ) async {
      await _montar(tester, conSesion: true);

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(find.textContaining('no pudimos cerrar la sesión'), findsNothing);
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

  group('Vista 15 — inventario de artboards', () {
    void conBaseLocal() {
      final dek = Uint8List.fromList(List<int>.filled(32, 77));
      _dbLocal
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = dek
        ..dekEnAlmacen = dek
        ..envoltorio = (dek: dek, password: 'Vieja1234');
    }

    testWidgets('15-A01 sin base local: aviso de sesiones completo y nada sobre datos', (
      tester,
    ) async {
      await _montar(tester);

      expect(
        find.text(
          'Al guardarla se cierran tus sesiones en todos tus teléfonos: vas a entrar de nuevo con '
          'la contraseña nueva.',
        ),
        findsOneWidget,
      );
      expect(find.text('Tus datos guardados en este teléfono se conservan.'), findsNothing);
      expect(find.text('Restaurar'), findsNothing);
      expect(find.text('Borrar'), findsNothing);
    });

    testWidgets('15-A02 con base local: agrega «Tus datos guardados en este teléfono se '
        'conservan.», sin tarjetas, y «Guardar contraseña» funciona directo', (tester) async {
      conBaseLocal();
      await _montar(tester);

      expect(find.text('Tus datos guardados en este teléfono se conservan.'), findsOneWidget);
      expect(find.text('Se cierran tus sesiones en todos tus teléfonos.'), findsOneWidget);
      expect(find.textContaining('Restaurar'), findsNothing);
      expect(find.textContaining('Borrar'), findsNothing);

      await _completar(tester, 'NuevaClave1');
      await tester.pump();
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);
      await _tocarGuardar(tester);

      expect(_recuperacion.actualizaciones, ['NuevaClave1']);
      expect(_dbLocal.envoltorio!.password, 'NuevaClave1');
    });

    testWidgets('15-A04 guardando: campos deshabilitados, botón «Guardando…» y sin reenvío', (
      tester,
    ) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.pump();

      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();

      expect(find.text('Guardando…'), findsOneWidget);
      for (final campo in ['nueva', 'repetida']) {
        expect(
          tester.widget<TextField>(find.byKey(Key('confirmar_recuperacion_$campo'))).enabled,
          isFalse,
        );
      }

      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('15-A05 error genérico: el aviso dice qué hacer y el botón vuelve a habilitarse', (
      tester,
    ) async {
      await _montar(tester);
      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      await _completar(tester, 'NuevaClave1');

      await _tocarGuardar(tester);

      expect(find.text('No pudimos guardar la contraseña. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Guardando…'), findsNothing);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);
      expect(_texto(tester, 'nueva'), 'NuevaClave1', reason: 'no pierde lo escrito');

      _recuperacion.fallaAlActualizar = null;
      await _tocarGuardar(tester);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });

    testWidgets('15-A06 enlace vencido: «ENLACE VENCIDO» y las dos salidas', (tester) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      expect(find.text('ENLACE VENCIDO'), findsOneWidget);
      expect(find.text('Solicitar un enlace nuevo'), findsOneWidget);
      expect(find.text('Volver al login'), findsOneWidget);
    });

    testWidgets('15-A09 éxito: pantalla con «Ir al login»; el atrás del sistema también lleva al '
        'login', (tester) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(find.text('Ir al login'), findsOneWidget);
      expect(find.byKey(const Key('confirmar_recuperacion_atras')), findsNothing);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(_recuperacion.abandonos, 0, reason: 'la sesión ya se cerró al guardar');
    });
  });

  group('Vista 15 — casos límite', () {
    testWidgets('doble tap en «Guardar contraseña» y «Listo» del teclado: una sola actualización', (
      tester,
    ) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.pump();

      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.tap(_guardar, warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();

      expect(_recuperacion.actualizaciones, ['NuevaClave1']);
      expect(_recuperacion.sesionesCerradas, 1);
    });

    testWidgets('falla a mitad y reintento inmediato: nada queda trabado ni se pisa', (
      tester,
    ) async {
      await _montar(tester);
      _recuperacion.simularSinConexion = true;
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(find.text('Sin conexión'), findsOneWidget);

      _recuperacion.simularSinConexion = false;
      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      await _tocarGuardar(tester);
      expect(find.text('Sin conexión'), findsNothing, reason: 'el aviso anterior se reemplaza');
      expect(find.text('No pudimos guardar la contraseña. Probá de nuevo.'), findsOneWidget);

      _recuperacion.fallaAlActualizar = null;
      await _tocarGuardar(tester);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_recuperacion.actualizaciones.last, 'NuevaClave1');
    });

    testWidgets('editar después de un error de campo lo limpia', (tester) async {
      await _montar(tester);
      await _completar(tester, 'Vieja1234');
      await _tocarGuardar(tester);
      expect(find.text('Tiene que ser distinta de la anterior.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('confirmar_recuperacion_nueva')), 'Vieja12345');
      await tester.pump();

      expect(find.text('Tiene que ser distinta de la anterior.'), findsNothing);
    });

    testWidgets('volver atrás y reentrar con otro enlace: el formulario arranca vacío', (
      tester,
    ) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.tap(find.byKey(const Key('confirmar_recuperacion_atras')));
      await tester.pumpAndSettle();

      _recuperacion.simularEnlace(EnlaceRecuperacion.valido);
      await tester.pumpAndSettle();

      expect(_texto(tester, 'nueva'), isEmpty);
      expect(_texto(tester, 'repetida'), isEmpty);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNull);
    });

    testWidgets('contraseña larguísima con espacios y símbolos: se acepta tal cual', (
      tester,
    ) async {
      await _montar(tester);
      final larga = 'Aa1 ${'ñ#' * 120}';

      await _completar(tester, larga);
      await _tocarGuardar(tester);

      expect(_recuperacion.actualizaciones, [larga]);
    });

    testWidgets('sin conexión y luego vencido: pasa a «El enlace expiró» sin dejar el aviso', (
      tester,
    ) async {
      await _montar(tester);
      _recuperacion.simularSinConexion = true;
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(find.text('Sin conexión'), findsOneWidget);

      _recuperacion.simularSinConexion = false;
      _recuperacion.vencerSesionDeRecuperacion();
      await _tocarGuardar(tester);

      expect(find.text('El enlace expiró. Solicitá uno nuevo.'), findsOneWidget);
      expect(find.text('Sin conexión'), findsNothing);
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
          expect(tester.takeException(), isNull);
          await _completar(tester, 'NuevaClave1');
          await _tocarGuardar(tester);
          expect(find.text('Sin conexión'), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Vista 15 — estados a 200 % en 360x740', () {
    Future<void> escalar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('A01, A02 y A03 (débil, con datos largos): sin overflow', (tester) async {
      await escalar(tester);
      await _montarSolo(tester, EnlaceRecuperacion.valido);
      await _completar(tester, 'lucia', repetida: 'x' * 80);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _completar(tester, 'Primavera26');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_guardar);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
      await _tocarGuardar(tester);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
    });

    testWidgets('A02 con base local: sin overflow', (tester) async {
      final dek = Uint8List.fromList(List<int>.filled(32, 77));
      _dbLocal
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..dekEnAlmacen = dek;
      await escalar(tester);
      await _montarSolo(tester, EnlaceRecuperacion.valido);
      await _completar(tester, 'Primavera26');
      await tester.pumpAndSettle();

      expect(find.text('Tus datos guardados en este teléfono se conservan.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A04 guardando, A05 error y A09 éxito: sin overflow', (tester) async {
      await escalar(tester);
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montarSolo(tester, EnlaceRecuperacion.valido);
      await _completar(tester, 'Primavera26');
      await tester.pump();
      await _tocarGuardarSinEsperar(tester);
      expect(find.text('Guardando…'), findsOneWidget);
      expect(tester.takeException(), isNull);

      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_irAlLoginExito);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A05 error genérico y A08 sin conexión: sin overflow', (tester) async {
      await escalar(tester);
      await _montarSolo(tester, EnlaceRecuperacion.valido);
      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      await _completar(tester, 'Primavera26');
      await _tocarGuardar(tester);
      expect(find.text('No pudimos guardar la contraseña. Probá de nuevo.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      _recuperacion.fallaAlActualizar = null;
      _recuperacion.simularSinConexion = true;
      await _tocarGuardar(tester);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Vista 15 — accesibilidad de los estados nuevos', () {
    testWidgets('requisitos con etiqueta, éxito y aviso de error: toque, etiquetas y contraste', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _montar(tester);

      await _completar(tester, 'lucia', repetida: '');
      await tester.pump();
      expect(
        tester.getSemantics(_req('largo')).label,
        'Al menos 8 caracteres, faltan 3: no cumple',
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      await _completar(tester, 'Primavera26');
      await _tocarGuardar(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      _recuperacion.fallaAlActualizar = null;
      await _tocarGuardar(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  test('los textos de la HU no cambian sin querer', () {
    expect(TextosConfirmacionRecuperacion.exito, 'Contraseña actualizada. Iniciá sesión.');
    expect(
      TextosConfirmacionRecuperacion.vencido,
      const FailureEnlaceRecuperacionVencido().mensaje,
    );
  });
}
