// QA de la vista 15 completa (HU-AUTH-005, y la precarga del correo de HU-AUTH-007), a partir del
// PR #264 (#247): las salidas de 15-A06 «enlace que no sirve», su lector de pantalla y los datos
// locales y el correo tras el cambio de contraseña. Complementa `qa_vista15_a06_test.dart` (A06 en
// los tamaños del checklist) y `confirmar_recuperacion_password_page_test.dart` (los criterios).
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _textoA06 = TextosConfirmacionRecuperacion.vencido;
const _rotuloA06 = TextosConfirmacionRecuperacion.rotuloEnlaceNoValido;

late RecuperacionPasswordEnMemoria _recuperacion;
late DbLocalRepositoryEnMemoria _dbLocal;
late AuthRemoteDataSourceEnMemoria _auth;

Finder get _login => find.byKey(const Key('login_enviar'));
Finder get _pedirOtro => find.byKey(const Key('confirmar_recuperacion_pedir_otro'));
Finder get _guardar => find.byKey(const Key('confirmar_recuperacion_guardar'));

/// La app entera con los fakes en memoria; el enlace llega por el mismo camino que en producción.
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

Future<void> _completar(WidgetTester tester, String nueva) async {
  await tester.enterText(find.byKey(const Key('confirmar_recuperacion_nueva')), nueva);
  await tester.enterText(find.byKey(const Key('confirmar_recuperacion_repetida')), nueva);
  await tester.pump();
}

Future<void> _tocarGuardar(WidgetTester tester) async {
  await tester.ensureVisible(_guardar);
  await tester.tap(_guardar);
  await tester.pumpAndSettle();
}

/// El atrás del sistema (el gesto o el botón de Android), sobre el navegador de la app.
Future<void> _atrasDelSistema(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  await navigator.maybePop();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
    _dbLocal = DbLocalRepositoryEnMemoria();
    _auth = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: 'Vieja1234'});
  });

  group('QA #247 — vista 15: las salidas de A06', () {
    for (final (clave, etiqueta) in const [
      ('confirmar_recuperacion_pedir_otro', '«Solicitar un enlace nuevo»'),
      ('confirmar_recuperacion_ir_al_login', '«Volver al login»'),
    ]) {
      testWidgets(
        'dado un teléfono chico con el texto al 200 %, cuando se baja hasta el pie de A06, '
        'entonces se alcanza $etiqueta',
        (tester) async {
          final salida = find.byKey(Key(clave));
          tester.view
            ..physicalSize = const Size(360, 640)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _montar(tester, enlace: EnlaceRecuperacion.vencido);

          await tester.ensureVisible(salida);
          await tester.pumpAndSettle();
          final rect = tester.getRect(salida);
          expect(rect.bottom, lessThanOrEqualTo(640));
          expect(rect.top, greaterThanOrEqualTo(0));

          await tester.tap(salida);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
        },
      );
    }

    testWidgets('dado que A06 llegó del enlace, cuando se toca dos veces «Solicitar un enlace '
        'nuevo», entonces se abre «Olvidé mi contraseña» una sola vez y el atrás lleva al login', (
      tester,
    ) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      await tester.tap(_pedirOtro);
      await tester.tap(_pedirOtro, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

      await _atrasDelSistema(tester);

      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(_login, findsOneWidget, reason: 'no queda otra «Olvidé mi contraseña» ni A06 detrás');
    });

    testWidgets('dado que el enlace venció a mitad del cambio, cuando se toca dos veces «Solicitar '
        'un enlace nuevo», entonces la sesión del enlace se suelta una sola vez', (tester) async {
      await _montar(tester);
      _recuperacion.rechazarSesionDeRecuperacion();
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(find.text(_textoA06), findsOneWidget);

      await tester.tap(_pedirOtro);
      await tester.tap(_pedirOtro, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_recuperacion.abandonos, 1);
      expect(_recuperacion.haySesionDeRecuperacion, isFalse);
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
    });

    testWidgets('dado que el enlace venció a mitad del cambio, cuando se sale con el atrás del '
        'sistema, entonces se suelta la sesión del enlace y queda el login', (tester) async {
      await _montar(tester);
      _recuperacion.rechazarSesionDeRecuperacion();
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(find.text(_textoA06), findsOneWidget);

      await _atrasDelSistema(tester);

      expect(_login, findsOneWidget);
      expect(_recuperacion.abandonos, 1);
      expect(_recuperacion.haySesionDeRecuperacion, isFalse);
    });

    for (final (nombre, salida) in [
      ('«Volver al login»', 'confirmar_recuperacion_ir_al_login'),
      ('«Solicitar un enlace nuevo»', 'confirmar_recuperacion_pedir_otro'),
    ]) {
      testWidgets('dado que ya había una sesión abierta y llega un enlace que no sirve, cuando se '
          'toca $nombre, entonces no se cierra la sesión de quien ya estaba adentro', (
        tester,
      ) async {
        final container = await _montar(
          tester,
          enlace: EnlaceRecuperacion.vencido,
          conSesion: true,
        );
        expect(find.text(_textoA06), findsOneWidget);

        await tester.tap(find.byKey(Key(salida)));
        await tester.pumpAndSettle();

        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
        expect(_recuperacion.abandonos, 0);
        expect(container.read(sesionProvider).value, isNotNull, reason: 'la sesión sigue abierta');
      });
    }

    testWidgets('dado que se estaba escribiendo la contraseña, cuando el enlace resulta vencido al '
        'guardar, entonces A06 reemplaza el formulario sin teclado ni campo con foco', (
      tester,
    ) async {
      await _montar(tester);
      _recuperacion.vencerSesionDeRecuperacion();
      await tester.showKeyboard(find.byKey(const Key('confirmar_recuperacion_nueva')));
      await tester.enterText(find.byKey(const Key('confirmar_recuperacion_nueva')), 'NuevaClave1');
      await tester.showKeyboard(find.byKey(const Key('confirmar_recuperacion_repetida')));
      await tester.enterText(
        find.byKey(const Key('confirmar_recuperacion_repetida')),
        'NuevaClave1',
      );
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(_textoA06), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse, reason: 'el teclado no queda abierto');
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
    });
  });

  group('QA #247 — vista 15: lector de pantalla en A06', () {
    testWidgets('el orden de lectura es rótulo, texto y las dos salidas; el texto se anuncia', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      final etiquetas = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.label)
          .where((e) => e.isNotEmpty)
          .toList();
      final posiciones = [
        _rotuloA06,
        _textoA06,
        'Solicitar un enlace nuevo',
        'Volver al login',
      ].map(etiquetas.indexOf).toList();

      expect(posiciones, everyElement(greaterThanOrEqualTo(0)), reason: '$etiquetas');
      expect(posiciones, orderedEquals([...posiciones]..sort()), reason: '$etiquetas');
      expect(
        tester.getSemantics(find.byKey(const Key('confirmar_recuperacion_vencido'))),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    });

    // Los títulos de la vista 15 (A01, A06, A09) son encabezados para el lector de pantalla, como
    // en las vistas vecinas (14, 17, 18, Configuración): se navega por encabezados (WCAG 1.3.1).
    testWidgets('los títulos de A01, A06 y A09 son encabezados, como en las vistas vecinas', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);
      expect(
        tester.getSemantics(find.text('Elegí una contraseña nueva')),
        isSemantics(isHeader: true),
        reason: 'A01',
      );
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(
        tester.getSemantics(find.byKey(const Key('confirmar_recuperacion_exito'))),
        isSemantics(isHeader: true),
        reason: 'A09',
      );
      await tester.tap(find.byKey(const Key('confirmar_recuperacion_exito_ir_al_login')));
      await tester.pumpAndSettle();
      _recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const Key('confirmar_recuperacion_vencido'))),
        isSemantics(isHeader: true),
        reason: 'A06',
      );
      semantica.dispose();
    });
  });

  group('QA #247 — vista 15: datos locales y correo tras el cambio con el enlace', () {
    testWidgets('dado que hay base local y una sesión abierta, cuando se cambia la contraseña con '
        'el enlace, entonces la base, su clave y el correo se conservan y el login lo trae '
        'puesto', (tester) async {
      final dek = Uint8List.fromList(List<int>.filled(32, 77));
      _dbLocal
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = dek
        ..dekEnAlmacen = dek
        ..envoltorio = (dek: dek, password: 'Vieja1234');
      final container = await _montar(tester, conSesion: true);
      expect(container.read(sesionProvider).value, isNotNull);

      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      await tester.tap(find.byKey(const Key('confirmar_recuperacion_exito_ir_al_login')));
      await tester.pumpAndSettle();

      expect(container.read(sesionProvider).value, isNull, reason: 'la app cerró la sesión');
      expect(_dbLocal.archivo, isTrue, reason: 'el archivo de la DB no se toca');
      expect(_dbLocal.claveDelArchivo, dek);
      expect(_dbLocal.dekEnAlmacen, dek, reason: 'la DEK sigue en el almacén seguro');
      expect(_dbLocal.marca, MarcaDbLocal.puesta);
      expect(_dbLocal.envoltorio!.password, 'NuevaClave1');
      expect(await container.read(ultimoCorreoRepositoryProvider).leer(), _email);
      expect(
        tester.widget<TextField>(find.byKey(const Key('login_email'))).controller!.text,
        _email,
      );
    });

    testWidgets('dado que el login trae el correo puesto, cuando la contraseña es incorrecta, '
        'entonces el aviso no pierde el correo', (tester) async {
      final container = await _montar(tester, conSesion: true);
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      await tester.tap(find.byKey(const Key('confirmar_recuperacion_exito_ir_al_login')));
      await tester.pumpAndSettle();
      expect(container.read(sesionProvider).value, isNull);

      await tester.enterText(find.byKey(const Key('login_password')), 'Equivocada9');
      await tester.pump();
      await tester.ensureVisible(_login);
      await tester.tap(_login);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byKey(const Key('login_email'))).controller!.text,
        _email,
        reason: 'después del error, lo tipeado no se pierde',
      );
      expect(container.read(sesionProvider).value, isNull);
    });
  });
}
