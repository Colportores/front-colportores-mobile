// Ronda 1 de la revisión del PR #295 (#265): lo que se agregó al login y al registro tras la QA, con
// su test propio. Los hallazgos de la QA mismos están en `qa_acceso_*_295_test.dart`.
//
// - Topes de largo (decisión del 02/10): nombre y apellido 60, correo 254 (registro y login), sin
//   contador a la vista; la contraseña del registro, 72 bytes UTF-8 con aviso y «Continuar»
//   deshabilitado; la del login, sin tope.
// - Login: etiqueta «CORREO», el 5xx con «Reintentar» y el spinner con nombre.
// - Registro: el primer campo con error queda a la vista y con el foco (360x640).
// - Casillas: relleno solo con la casilla marcada.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';

const _tope72 = 'Es demasiado larga. Acortala.';
const _servicioCaido = 'Servicio temporalmente no disponible, reintentá en unos minutos';

// Login
const _loginCorreo = Key('login_email');
const _loginClave = Key('login_password');
const _loginEntrar = Key('login_enviar');
const _loginError = Key('login_error_general');

// Registro
const _nombre = Key('registro_nombre');
const _apellido = Key('registro_apellido');
const _cedula = Key('registro_cedula');
const _correo = Key('registro_email');
const _clave = Key('registro_password');
const _terminos = Key('registro_terminos');
const _tradeOff = Key('registro_trade_off');
const _continuar = Key('registro_continuar');
const _errorGeneral = Key('registro_error_general');

String _texto(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).controller!.text;

bool _tieneFoco(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).focusNode!.hasFocus;

Future<void> _escribir(WidgetTester tester, Key campo, String texto) async {
  await tester.ensureVisible(find.byKey(campo));
  await tester.enterText(find.byKey(campo), texto);
}

Future<void> _tocar(WidgetTester tester, Key k) async {
  await tester.ensureVisible(find.byKey(k));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(k));
  await tester.pump();
}

Future<void> _reintentar(WidgetTester tester) async {
  final boton = find.widgetWithText(FilledButton, 'Reintentar');
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
}

Future<RemotoQueFalla> _montarLogin(WidgetTester tester, {Size? tamano}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final remoto = RemotoQueFalla();
  await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
  await tester.pumpAndSettle();
  return remoto;
}

Future<RemotoQueFalla> _montarRegistro(WidgetTester tester, {Size? tamano}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final remoto = RemotoQueFalla();
  await montarAcceso(tester, home: const RegistroPage(), remoto: remoto);
  await tester.pumpAndSettle();
  return remoto;
}

/// Como en la app: el registro se abre desde el login, así un envío exitoso tiene a dónde volver.
Future<RemotoQueFalla> _montarRegistroDesdeLogin(WidgetTester tester) async {
  final remoto = RemotoQueFalla();
  await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
  await tester.tap(find.byKey(const Key('login_ir_a_registro')));
  await tester.pumpAndSettle();
  return remoto;
}

Future<void> _completar(
  WidgetTester tester, {
  String clave = 'Secreto123',
  bool terminos = true,
  bool tradeOff = true,
}) async {
  await _escribir(tester, _nombre, 'Lucía');
  await _escribir(tester, _apellido, 'Silva');
  await _escribir(tester, _cedula, '4.812.309-2');
  await _escribir(tester, _correo, 'lucia.silva@correo.com');
  await _escribir(tester, _clave, clave);
  if (terminos) await _tocar(tester, _terminos);
  if (tradeOff) await _tocar(tester, _tradeOff);
}

Future<void> _enviarRegistro(WidgetTester tester) async {
  await _tocar(tester, _continuar);
  await tester.pumpAndSettle();
}

bool _dentroDeLaPantalla(WidgetTester tester, Finder f, double alto) {
  final r = tester.getRect(f);
  return r.top >= 0 && r.bottom <= alto;
}

void main() {
  group('Login — correo, topes y 5xx', () {
    testWidgets('el campo se llama «CORREO» (decisión del 02/10): ya no hay cédula', (
      tester,
    ) async {
      await _montarLogin(tester);

      expect(find.text('CORREO'), findsOneWidget);
      expect(find.text('CORREO O CÉDULA'), findsNothing);
    });

    testWidgets('el correo se corta en 254 caracteres y no muestra contador', (tester) async {
      await _montarLogin(tester);

      await _escribir(tester, _loginCorreo, '${'a' * 400}@example.com');

      expect(_texto(tester, _loginCorreo).length, 254);
      expect(find.text('254/254'), findsNothing);
      expect(find.textContaining('/254'), findsNothing);
    });

    testWidgets('la contraseña del login no tiene tope: la cuenta ya existe', (tester) async {
      await _montarLogin(tester);

      await _escribir(tester, _loginClave, 'C1${'x' * 300}');

      expect(_texto(tester, _loginClave).length, 302);
    });

    testWidgets('el 5xx dice qué hacer, y «Reintentar» vuelve a mandar el inicio de sesión', (
      tester,
    ) async {
      final remoto = await _montarLogin(tester);
      remoto.falla = const ServidorException(status: 503);
      await _escribir(tester, _loginCorreo, correoAna);
      await _escribir(tester, _loginClave, claveAna);

      await _tocar(tester, _loginEntrar);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(_loginError)).data, _servicioCaido);
      expect(remoto.llamadasIniciarSesion, 1);

      // Falla otra vez: el banner vuelve y «Reintentar» sigue disponible (nada queda trabado).
      await _reintentar(tester);
      await tester.pumpAndSettle();
      expect(remoto.llamadasIniciarSesion, 2);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_loginEntrar)).onPressed, isNotNull);

      // Vuelve el servidor: el aviso se va y entra.
      remoto.falla = null;
      await _reintentar(tester);
      await tester.pumpAndSettle();
      expect(remoto.llamadasIniciarSesion, 3);
      expect(find.byKey(_loginError), findsNothing);
    });

    testWidgets('mientras reintenta, el banner se va y «Entrar» queda ocupado y con nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final remoto = await _montarLogin(tester);
      remoto.falla = const ServidorException(status: 500);
      await _escribir(tester, _loginCorreo, correoAna);
      await _escribir(tester, _loginClave, claveAna);
      await _tocar(tester, _loginEntrar);
      await tester.pumpAndSettle();

      remoto
        ..falla = null
        ..demora = Completer<void>();
      await _reintentar(tester);
      await tester.pump();

      expect(find.byKey(_loginError), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(_loginEntrar)).onPressed, isNull);
      expect(tester.getSemantics(find.byKey(_loginEntrar)).label, 'Entrando…');
      expect(remoto.llamadasIniciarSesion, 2);

      remoto.demora!.complete();
      await tester.pumpAndSettle();
      semantica.dispose();
    });

    testWidgets('«¿Olvidaste tu clave?» entra a 360x640 con el texto al 200 %: sin overflow', (
      tester,
    ) async {
      fijarPantalla(tester, const Size(360, 640));
      await montarAcceso(tester, home: const LoginPage(), escala: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('login_olvidaste_clave')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_olvidaste_clave')).hitTestable(), findsOneWidget);
    });
  });

  group('Registro — topes de largo', () {
    testWidgets('nombre y apellido: 60 caracteres, correo: 254, sin contador a la vista', (
      tester,
    ) async {
      await _montarRegistro(tester);

      await _escribir(tester, _nombre, 'N' * 100);
      await _escribir(tester, _apellido, 'A' * 100);
      await _escribir(tester, _correo, '${'c' * 400}@example.com');

      expect(_texto(tester, _nombre).length, 60);
      expect(_texto(tester, _apellido).length, 60);
      expect(_texto(tester, _correo).length, 254);
      expect(find.textContaining('/60'), findsNothing);
      expect(find.textContaining('/254'), findsNothing);
    });

    testWidgets('la cédula no lleva tope de largo (el formato lo valida el dominio)', (
      tester,
    ) async {
      await _montarRegistro(tester);

      await _escribir(tester, _cedula, '1' * 80);

      expect(_texto(tester, _cedula).length, 80);
    });
  });

  group('Registro — contraseña de más de 72 bytes', () {
    for (final (descripcion, clave) in [
      ('73 caracteres ASCII', 'Aa1${'x' * 70}'),
      ('37 ñ (74 bytes en 37 caracteres)', 'ñ' * 37),
      ('emojis de 4 bytes: 21 caracteres, 75 bytes', 'Aa1${'😀' * 18}'),
    ]) {
      testWidgets('$descripcion: el campo avisa y «Continuar» queda deshabilitado', (tester) async {
        final remoto = await _montarRegistro(tester);

        await _completar(tester, clave: clave);

        expect(find.text(_tope72), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNull);
        expect(_texto(tester, _clave), clave, reason: 'nunca se recorta lo que escribió');

        await tester.tap(find.byKey(_continuar), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(remoto.llamadasRegistrar, 0);
      });
    }

    testWidgets('al acortarla a 72 bytes el aviso se va y «Continuar» vuelve a andar', (
      tester,
    ) async {
      final remoto = await _montarRegistroDesdeLogin(tester);
      await _completar(tester, clave: 'Aa1${'x' * 70}');
      expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNull);

      await _escribir(tester, _clave, 'Aa1${'x' * 69}');
      await tester.pumpAndSettle();

      expect(find.text(_tope72), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNotNull);
      await _enviarRegistro(tester);
      expect(remoto.llamadasRegistrar, 1);
    });

    testWidgets('Enter en el teclado con la contraseña de más de 72 bytes no envía', (
      tester,
    ) async {
      final remoto = await _montarRegistro(tester);
      await _completar(tester, clave: 'Aa1${'x' * 70}');

      await tester.tap(find.byKey(_clave));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(remoto.llamadasRegistrar, 0);
    });

    testWidgets('si el servidor la rechaza por larga, el campo dice lo mismo y se puede corregir', (
      tester,
    ) async {
      final remoto = await _montarRegistroDesdeLogin(tester);
      remoto.falla = const PasswordDemasiadoLargaException();
      await _completar(tester);

      await _enviarRegistro(tester);

      expect(remoto.llamadasRegistrar, 1);
      expect(find.text(_tope72), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNotNull);
      expect(_tieneFoco(tester, _clave), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      remoto.falla = null;
      await _enviarRegistro(tester);
      expect(remoto.llamadasRegistrar, 2);
    });
  });

  group('Registro — el primer error queda a la vista y con el foco (360x640)', () {
    const tamano = Size(360, 640);

    testWidgets('con el formulario vacío, vuelve al nombre y lo enfoca', (tester) async {
      await _montarRegistro(tester, tamano: tamano);

      await _enviarRegistro(tester);

      expect(find.text('Ingresá tu nombre'), findsOneWidget);
      expect(_dentroDeLaPantalla(tester, find.text('Ingresá tu nombre'), 640), isTrue);
      expect(_tieneFoco(tester, _nombre), isTrue);
    });

    testWidgets('si solo falta una casilla, baja hasta ella y la enfoca', (tester) async {
      await _montarRegistro(tester, tamano: tamano);
      await _completar(tester, terminos: false);

      await _enviarRegistro(tester);

      final error = find.byKey(const Key('registro_terminos_error'));
      expect(error, findsOneWidget);
      expect(_dentroDeLaPantalla(tester, error, 640), isTrue);
      expect(tester.widget<Checkbox>(find.byKey(_terminos)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('con un correo mal escrito y lo demás bien, enfoca el correo', (tester) async {
      await _montarRegistro(tester, tamano: tamano);
      await _completar(tester);
      await _escribir(tester, _correo, 'lucia');

      await _enviarRegistro(tester);

      expect(find.text('El email no es válido'), findsOneWidget);
      expect(_dentroDeLaPantalla(tester, find.text('El email no es válido'), 640), isTrue);
      expect(_tieneFoco(tester, _correo), isTrue);
    });

    testWidgets('sin errores por campo (sin conexión), el aviso general queda a la vista', (
      tester,
    ) async {
      final remoto = await _montarRegistro(tester, tamano: tamano);
      remoto.falla = const SinConexionException();
      await _completar(tester);

      await _enviarRegistro(tester);

      expect(_dentroDeLaPantalla(tester, find.byKey(_errorGeneral), 640), isTrue);
    });
  });

  group('Registro — avisos y botón mientras envía', () {
    testWidgets('«Continuar» ocupado se llama «Creando tu cuenta…» y el 5xx tiene el mismo texto '
        'que el del login', (tester) async {
      final semantica = tester.ensureSemantics();
      final remoto = await _montarRegistro(tester);
      remoto.demora = Completer<void>();
      await _completar(tester);
      await _tocar(tester, _continuar);

      expect(tester.getSemantics(find.byKey(_continuar)).label, 'Creando tu cuenta…');

      remoto
        ..falla = const ServidorException(status: 503)
        ..demora!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(_errorGeneral)).data, _servicioCaido);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('la flecha de volver se llama «Volver» y el glifo no se lee', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montarRegistro(tester);

      // El nombre viaja como `tooltip` (igual que el resto de los botones de ícono de la app).
      final nodo = tester.getSemantics(find.byKey(const Key('registro_atras')));
      expect(nodo.tooltip, 'Volver');
      expect(nodo.label.contains('‹'), isFalse);
      semantica.dispose();
    });
  });

  group('Casillas — relleno solo si están marcadas', () {
    testWidgets('el tema de la app pinta transparente la casilla sin marcar y azul la marcada', (
      tester,
    ) async {
      final tema = temaClaro();
      final relleno = tema.checkboxTheme.fillColor!;

      expect(relleno.resolve(<WidgetState>{}), Colors.transparent);
      expect(relleno.resolve(<WidgetState>{WidgetState.selected}), tema.colorScheme.primary);
      expect(relleno.resolve(<WidgetState>{WidgetState.disabled}), Colors.transparent);
    });
  });
}
