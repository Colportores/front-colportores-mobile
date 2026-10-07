// QA del acceso (login y registro), ronda 2 del PR #295 (#265): casos adversariales sobre lo que
// arregló la ronda 1: los avisos que se anuncian, los topes de largo (60 / 254 / 72 bytes UTF-8) y el
// foco al primer error. Cada test falla si el arreglo se rompe; los que documentan un hallazgo
// nuevo llevan `skip` con el motivo arriba.
import 'dart:async';
import 'dart:convert';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';
import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;

const _topeLargo = 'Es demasiado larga. Acortala.';
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
const _correoNuevo = 'lucia.silva@correo.com';

/// «👨‍👩‍👧»: una familia es 1 carácter visible, 5 puntos de código y 18 bytes en UTF-8.
const _familia = '\u{1F468}‍\u{1F469}‍\u{1F467}';

int _bytes(String texto) => utf8.encode(texto).length;

String _tam(Size t) => '${t.width.toInt()}x${t.height.toInt()}';

String _texto(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).controller!.text;

bool _tieneFoco(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).focusNode?.hasFocus ?? false;

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

Future<void> _tocarReintentar(WidgetTester tester) async {
  final boton = find.widgetWithText(FilledButton, 'Reintentar');
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  await tester.pump();
}

Future<RemotoQueFalla> _montarLogin(
  WidgetTester tester, {
  Size? tamano,
  double escala = 1,
  RemotoQueFalla? remoto,
}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final r = remoto ?? RemotoQueFalla();
  await montarAcceso(tester, home: const LoginPage(), remoto: r, escala: escala);
  await tester.pumpAndSettle();
  return r;
}

/// El registro se abre desde el login, como en la app: un envío exitoso tiene a dónde volver.
Future<RemotoQueFalla> _montarRegistro(
  WidgetTester tester, {
  Size? tamano,
  double escala = 1,
}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final remoto = RemotoQueFalla();
  await montarAcceso(tester, home: const LoginPage(), remoto: remoto, escala: escala);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
  await tester.tap(find.byKey(const Key('login_ir_a_registro')));
  await tester.pumpAndSettle();
  return remoto;
}

Future<void> _completar(
  WidgetTester tester, {
  String clave = 'Secreto123',
  String correo = _correoNuevo,
  bool terminos = true,
  bool tradeOff = true,
}) async {
  await _escribir(tester, _nombre, 'Lucía');
  await _escribir(tester, _apellido, 'Silva');
  await _escribir(tester, _cedula, '4.812.309-2');
  await _escribir(tester, _correo, correo);
  await _escribir(tester, _clave, clave);
  if (terminos) await _tocar(tester, _terminos);
  if (tradeOff) await _tocar(tester, _tradeOff);
}

Future<void> _enviarRegistro(WidgetTester tester) async {
  await _tocar(tester, _continuar);
  await tester.pumpAndSettle();
}

/// Dispara «Continuar» sin pasar por el toque: con un campo enfocado el arnés recentra el cursor y
/// puede dejar el botón fuera de la pantalla justo antes del toque.
Future<void> _enviarSinTocar(WidgetTester tester) async {
  tester.widget<FilledButton>(find.byKey(_continuar)).onPressed!();
  await tester.pumpAndSettle();
}

Future<void> _iniciarSesionConFalla(WidgetTester tester) async {
  await tester.enterText(find.byKey(_loginCorreo), correoAna);
  await tester.enterText(find.byKey(_loginClave), claveAna);
  await tester.ensureVisible(find.byKey(_loginEntrar));
  await tester.tap(find.byKey(_loginEntrar));
  await tester.pumpAndSettle();
}

/// Los nodos de semántica que llevan [texto] en su etiqueta: dos nodos con el mismo aviso hacen que
/// el lector de pantalla lo lea (o lo anuncie) dos veces.
SemanticsFinder _nodosCon(String texto) => find.semantics.byLabel(RegExp(RegExp.escape(texto)));

bool _entraEnLaPantalla(WidgetTester tester, Finder f, {required double alto, double desde = 0}) {
  final r = tester.getRect(f);
  return r.top >= desde && r.bottom <= alto;
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  group('Avisos de error: una sola región viva con solo el texto del aviso', () {
    for (final (nombre, falla) in <(String, AuthRemoteException)>[
      ('credenciales incorrectas', const CredencialesInvalidasException()),
      ('sin conexión', const SinConexionException()),
      ('servidor caído con «Reintentar»', const ServidorException(status: 503)),
    ]) {
      testWidgets('login, $nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        final remoto = await _montarLogin(tester, tamano: const Size(390, 844));
        remoto.falla = falla;
        await _iniciarSesionConFalla(tester);

        final aviso = tester.widget<Text>(find.byKey(_loginError)).data!;
        final nodo = tester.getSemantics(find.byKey(_loginError));
        expect(nodo, isSemantics(isLiveRegion: true));
        expect(nodo.label, aviso, reason: 'ni «Reintentar» ni otro texto se mezclan en el aviso');
        expect(_nodosCon(aviso), findsOneWidget);
        semantica.dispose();
      });
    }

    for (final (nombre, falla) in <(String, AuthRemoteException)>[
      ('email ya registrado', const EmailYaRegistradoException()),
      ('sin conexión', const SinConexionException()),
      ('servidor caído con «Reintentar»', const ServidorException(status: 500)),
    ]) {
      testWidgets('registro, $nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        final remoto = await _montarRegistro(tester, tamano: const Size(390, 844));
        remoto.falla = falla;
        await _completar(tester);
        await _enviarRegistro(tester);

        final aviso = tester.widget<Text>(find.byKey(_errorGeneral)).data!;
        final nodo = tester.getSemantics(find.byKey(_errorGeneral));
        expect(nodo, isSemantics(isLiveRegion: true));
        expect(nodo.label, aviso, reason: 'los botones del aviso no se mezclan en la región viva');
        expect(_nodosCon(aviso), findsOneWidget);
        semantica.dispose();
      });
    }

    testWidgets('registro: los dos avisos de las casillas son regiones vivas distintas', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarRegistro(tester, tamano: const Size(390, 844));
      await _completar(tester, terminos: false, tradeOff: false);
      await _enviarRegistro(tester);

      for (final k in [
        const Key('registro_terminos_error'),
        const Key('registro_trade_off_error'),
      ]) {
        final aviso = tester.widget<Text>(find.byKey(k)).data!;
        expect(tester.getSemantics(find.byKey(k)), isSemantics(isLiveRegion: true));
        expect(_nodosCon(aviso), findsOneWidget, reason: aviso);
      }
      semantica.dispose();
    });

    testWidgets(
      'el aviso del 5xx se vuelve a anunciar en cada reintento que falla (nace de nuevo)',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final remoto = await _montarLogin(tester, tamano: const Size(390, 844));
        remoto.falla = const ServidorException(status: 503);
        await _iniciarSesionConFalla(tester);
        expect(_nodosCon(_servicioCaido), findsOneWidget);

        // Reintenta con el servidor todavía caído y la respuesta en vuelo: el aviso viejo no queda.
        remoto.demora = Completer<void>();
        await _tocarReintentar(tester);
        expect(_nodosCon(_servicioCaido), findsNothing, reason: 'un aviso viejo no puede quedar');
        expect(tester.widget<FilledButton>(find.byKey(_loginEntrar)).onPressed, isNull);

        remoto.demora!.complete();
        await tester.pumpAndSettle();
        expect(_nodosCon(_servicioCaido), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(_loginError)),
          isSemantics(isLiveRegion: true),
          reason: 'el aviso nuevo es otra región viva: se anuncia de nuevo',
        );
        semantica.dispose();
      },
    );

    testWidgets('cambia el aviso (5xx → sin conexión): queda uno solo, con el texto nuevo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final remoto = await _montarLogin(tester, tamano: const Size(390, 844));
      remoto.falla = const ServidorException(status: 503);
      await _iniciarSesionConFalla(tester);

      remoto.falla = const SinConexionException();
      await _tocarReintentar(tester);
      await tester.pumpAndSettle();

      expect(_nodosCon(_servicioCaido), findsNothing);
      final aviso = tester.widget<Text>(find.byKey(_loginError)).data!;
      expect(aviso, startsWith('Necesitás conexión'));
      expect(_nodosCon(aviso), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsNothing);
      semantica.dispose();
    });
  });

  group('Contraseña del registro: el tope es de 72 BYTES en UTF-8', () {
    // (descripción, contraseña de 72 bytes que cumple la política, y un byte de más).
    final casos = <(String, String)>[
      ('ASCII', 'Aa1${'x' * 69}'),
      ('ñ de 2 bytes', 'A1${'ñ' * 35}'),
      ('emojis de 4 bytes', 'A1${'😀' * 17}ñ'),
      ('familia con ZWJ (3 × 18 bytes)', 'A1${_familia * 3}${'x' * 16}'),
      ('«e» con tilde combinada (3 bytes por letra)', 'A1${'é' * 23}x'),
    ];

    for (final (descripcion, clave72) in casos) {
      testWidgets('$descripcion: 72 bytes entran y se mandan sin recortar', (tester) async {
        expect(_bytes(clave72), 72, reason: 'precondición del caso');
        final remoto = await _montarRegistro(tester);
        await _completar(tester, clave: clave72);

        expect(find.text(_topeLargo), findsNothing);
        expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNotNull);
        await _enviarRegistro(tester);

        expect(remoto.llamadasRegistrar, 1);
        // La cuenta quedó con la contraseña entera: con ella se puede entrar.
        await remoto.interno.iniciarSesion(email: _correoNuevo, password: clave72);
      });

      testWidgets('$descripcion: con un byte más avisa y no deja enviar', (tester) async {
        final clave73 = '${clave72}x';
        expect(_bytes(clave73), 73, reason: 'precondición del caso');
        final remoto = await _montarRegistro(tester);
        await _completar(tester, clave: clave73);

        expect(find.text(_topeLargo), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNull);
        expect(_texto(tester, _clave), clave73, reason: 'no se recorta lo que escribió');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(remoto.llamadasRegistrar, 0);
      });
    }

    testWidgets('la cuenta de caracteres NO decide: 40 caracteres de 2 bytes pasan el tope', (
      tester,
    ) async {
      // 40 caracteres visibles (muy por debajo de 72) pero 80 bytes.
      final clave = 'A1${'ñ' * 38}';
      expect(clave.characters.length, 40);
      expect(_bytes(clave), 78);
      await _montarRegistro(tester);

      await _completar(tester, clave: clave);

      expect(find.text(_topeLargo), findsOneWidget);
    });

    testWidgets('un texto pegado de 5000 caracteres y de 5000 emojis: aviso, sin overflow', (
      tester,
    ) async {
      await _montarRegistro(tester, tamano: const Size(360, 640), escala: 2);
      for (final pegado in ['Aa1${'x' * 5000}', '😀' * 5000]) {
        await _escribir(tester, _clave, pegado);
        await tester.pumpAndSettle();

        expect(find.text(_topeLargo), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNull);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('el aviso sigue al texto: largo → corto → largo → vacío, sin estado viejo', (
      tester,
    ) async {
      await _montarRegistro(tester);
      final cuando = <(String, bool)>[
        ('Aa1${'x' * 80}', true),
        ('Aa1${'x' * 10}', false),
        ('Aa1${'x' * 70}', true),
        ('', false),
        ('Aa1${'x' * 69}', false),
      ];
      for (final (clave, debeAvisar) in cuando) {
        await _escribir(tester, _clave, clave);
        await tester.pumpAndSettle();
        expect(
          find.text(_topeLargo),
          debeAvisar ? findsOneWidget : findsNothing,
          reason: '${_bytes(clave)} bytes',
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_continuar)).onPressed,
          debeAvisar ? isNull : isNotNull,
          reason: '${_bytes(clave)} bytes',
        );
      }
    });

    testWidgets('lo demás tipeado no se pierde cuando la contraseña pasa el tope', (tester) async {
      await _montarRegistro(tester);
      await _completar(tester, clave: 'Aa1${'x' * 80}');
      await tester.pumpAndSettle();

      expect(_texto(tester, _nombre), 'Lucía');
      expect(_texto(tester, _apellido), 'Silva');
      expect(_texto(tester, _cedula), '4.812.309-2');
      expect(_texto(tester, _correo), _correoNuevo);
      expect(tester.widget<Checkbox>(find.byKey(_terminos)).value, isTrue);
      expect(tester.widget<Checkbox>(find.byKey(_tradeOff)).value, isTrue);
    });

    // skip: QA #295 — tras un 5xx, si se edita la contraseña por encima de 72 bytes, «Reintentar» sigue
    // habilitado y su toque no hace nada (el guardián de `_enviar` sale en silencio); debería quedar
    // apagado como «Continuar» (registro_page.dart:469).
    testWidgets('«Reintentar» (5xx) se apaga si la contraseña editada pasa los 72 bytes', (
      tester,
    ) async {
      final remoto = await _montarRegistro(tester);
      remoto.falla = const ServidorException(status: 503);
      await _completar(tester);
      await _enviarRegistro(tester);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);

      await _escribir(tester, _clave, 'Aa1${'x' * 80}');
      await tester.pumpAndSettle();

      final reintentar = find.widgetWithText(FilledButton, 'Reintentar');
      expect(tester.widget<FilledButton>(reintentar).onPressed, isNull);
    }, skip: true);

    testWidgets('«Reintentar» con la contraseña de más de 72 bytes no manda nada al servidor', (
      tester,
    ) async {
      final remoto = await _montarRegistro(tester);
      remoto.falla = const ServidorException(status: 503);
      await _completar(tester);
      await _enviarRegistro(tester);
      await _escribir(tester, _clave, 'Aa1${'x' * 80}');
      await tester.pumpAndSettle();

      await _tocarReintentar(tester);
      await tester.pumpAndSettle();

      expect(remoto.llamadasRegistrar, 1, reason: 'solo el primer intento llegó al servidor');
    });
  });

  group('Topes de nombre, apellido y correo: se cuentan caracteres visibles', () {
    testWidgets('nombre: 100 emojis → 60 emojis enteros, ninguno partido', (tester) async {
      await _montarRegistro(tester);

      await _escribir(tester, _nombre, '😀' * 100);

      final texto = _texto(tester, _nombre);
      expect(texto.characters.length, 60);
      expect(texto.runes.length, 60, reason: 'ningún emoji quedó partido a la mitad');
    });

    testWidgets('apellido: 100 familias con ZWJ → 60 caracteres visibles', (tester) async {
      await _montarRegistro(tester);

      await _escribir(tester, _apellido, _familia * 100);

      final texto = _texto(tester, _apellido);
      expect(texto.characters.length, 60);
      expect(texto, _familia * 60);
    });

    testWidgets('pegar sobre lo ya escrito completa hasta el tope y no más', (tester) async {
      await _montarRegistro(tester);
      await _escribir(tester, _nombre, 'M' * 50);

      await _escribir(tester, _nombre, '${'M' * 50}${'ñ' * 30}');

      expect(_texto(tester, _nombre), '${'M' * 50}${'ñ' * 10}');
    });

    testWidgets('nombre de 60 exactos se manda entero', (tester) async {
      final remoto = await _montarRegistro(tester);
      await _completar(tester);
      await _escribir(tester, _nombre, 'Ñ' * 60);

      await _enviarRegistro(tester);

      expect(remoto.interno.usuariosRegistrados[_correoNuevo]!.nombre, 'Ñ' * 60);
    });

    testWidgets('correo: 5000 caracteres → 254, también en el login, y sin contador', (
      tester,
    ) async {
      await _montarLogin(tester);
      await tester.enterText(find.byKey(_loginCorreo), '${'a' * 5000}@example.com');
      expect(_texto(tester, _loginCorreo).length, 254);
      expect(find.textContaining('/254'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await _montarRegistro(tester);
      await _escribir(tester, _correo, '${'a' * 5000}@example.com');
      expect(_texto(tester, _correo).length, 254);
      expect(find.textContaining('/254'), findsNothing);
    });
  });

  group('Foco al primer error (registro)', () {
    const chico = Size(360, 640);

    testWidgets('con el teclado abierto (300 dp) el primer error queda sobre el teclado', (
      tester,
    ) async {
      await _montarRegistro(tester, tamano: chico);
      await _completar(tester, correo: 'lucia');
      await tester.ensureVisible(find.byKey(_clave));
      tester.widget<TextField>(find.byKey(_clave)).focusNode!.requestFocus();
      await tester.pump();
      abrirTeclado(tester, 300);
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      const error = 'El email no es válido';
      expect(find.text(error), findsOneWidget);
      expect(
        _entraEnLaPantalla(tester, find.text(error), alto: 640 - 300),
        isTrue,
        reason: '${tester.getRect(find.text(error))} queda tapado por el teclado',
      );
      expect(_tieneFoco(tester, _correo), isTrue);
    });

    testWidgets('con el teclado abierto y el formulario vacío, el foco va al nombre y se ve', (
      tester,
    ) async {
      await _montarRegistro(tester, tamano: chico);
      await tester.ensureVisible(find.byKey(_clave));
      tester.widget<TextField>(find.byKey(_clave)).focusNode!.requestFocus();
      await tester.pump();
      abrirTeclado(tester, 300);
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu nombre'), findsOneWidget);
      expect(_entraEnLaPantalla(tester, find.text('Ingresá tu nombre'), alto: 640 - 300), isTrue);
      expect(_tieneFoco(tester, _nombre), isTrue);
    });

    testWidgets('texto al 200 %: el primer error queda a la vista y con el foco', (tester) async {
      await _montarRegistro(tester, tamano: chico, escala: 2);
      await _enviarRegistro(tester);

      expect(_entraEnLaPantalla(tester, find.text('Ingresá tu nombre'), alto: 640), isTrue);
      expect(_tieneFoco(tester, _nombre), isTrue);
    });

    testWidgets('el foco sigue el orden visual: nombre, apellido, cédula, correo, contraseña', (
      tester,
    ) async {
      await _montarRegistro(tester, tamano: chico);
      await _enviarSinTocar(tester);
      expect(_tieneFoco(tester, _nombre), isTrue);

      await _escribir(tester, _nombre, 'Lucía');
      await _enviarSinTocar(tester);
      expect(_tieneFoco(tester, _apellido), isTrue);

      await _escribir(tester, _apellido, 'Silva');
      await _enviarSinTocar(tester);
      expect(_tieneFoco(tester, _cedula), isTrue);

      await _escribir(tester, _cedula, '4.812.309-2');
      await _enviarSinTocar(tester);
      expect(_tieneFoco(tester, _correo), isTrue);

      await _escribir(tester, _correo, _correoNuevo);
      await _enviarSinTocar(tester);
      expect(_tieneFoco(tester, _clave), isTrue);
      expect(_entraEnLaPantalla(tester, find.text('Ingresá tu contraseña'), alto: 640), isTrue);
    });

    testWidgets('si solo falta la casilla de la copia de seguridad, baja a ella y la enfoca', (
      tester,
    ) async {
      await _montarRegistro(tester, tamano: chico);
      await _completar(tester, tradeOff: false);

      await _enviarRegistro(tester);

      final error = find.byKey(const Key('registro_trade_off_error'));
      expect(error, findsOneWidget);
      expect(_entraEnLaPantalla(tester, error, alto: 640), isTrue);
      expect(tester.widget<Checkbox>(find.byKey(_tradeOff)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('con Tab el foco recorre el formulario en el orden de lo que se ve', (
      tester,
    ) async {
      await _montarRegistro(tester, tamano: const Size(390, 844));
      const orden = [
        'registro_atras',
        'registro_nombre',
        'registro_apellido',
        'registro_cedula',
        'registro_email',
        'registro_password',
        'registro_terminos',
        'registro_trade_off',
        'registro_continuar',
        'registro_ir_a_login',
      ];
      final visitadas = <String>[];
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final contexto = FocusManager.instance.primaryFocus?.context;
        if (contexto == null) continue;
        String? clave;
        contexto.visitAncestorElements((e) {
          final k = e.widget.key;
          if (k is ValueKey<String> && orden.contains(k.value)) {
            clave = k.value;
            return false;
          }
          return true;
        });
        if (clave != null && (visitadas.isEmpty || visitadas.last != clave)) visitadas.add(clave!);
      }

      expect(visitadas.take(orden.length).toList(), orden);
    });
  });

  group('Accesibilidad en los estados nuevos de la ronda 1', () {
    for (final tamano in tamanosAcceso) {
      testWidgets('registro con la contraseña de más de 72 bytes a ${_tam(tamano)}', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await _montarRegistro(tester, tamano: tamano);
        await _completar(tester, clave: 'Aa1${'x' * 80}');
        await tester.pumpAndSettle();
        expect(find.text(_topeLargo), findsOneWidget);

        await guiasDeAccesibilidad(tester);
        semantica.dispose();
      });

      testWidgets('login con el 5xx y «Reintentar» a ${_tam(tamano)}', (tester) async {
        final semantica = tester.ensureSemantics();
        final remoto = await _montarLogin(tester, tamano: tamano);
        remoto.falla = const ServidorException(status: 503);
        await _iniciarSesionConFalla(tester);
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);

        await guiasDeAccesibilidad(tester);
        semantica.dispose();
      });
    }

    testWidgets('registro con la contraseña de más de 72 bytes, texto al 200 % a 360x640', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarRegistro(tester, tamano: tamanosAcceso.first, escala: 2);
      await _completar(tester, clave: 'Aa1${'x' * 80}');
      await tester.pumpAndSettle();

      await guiasDeAccesibilidad(tester);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    // skip: QA #295 — a 200 % el error de un campo del registro se corta con puntos suspensivos
    // («Es demasiado larga. A...», «Ingresá t...»): `_CampoRegistro` no pone `errorMaxLines` (por
    // defecto es 1 línea) y se pierde justo lo que hay que hacer (registro_page.dart:611).
    testWidgets('registro, texto al 200 % a 360x640: los errores de campo se leen enteros', (
      tester,
    ) async {
      await cargarFuentesReales(); // con la fuente de prueba (cuadrados) el corte no es el real
      await _montarRegistro(tester, tamano: tamanosAcceso.first, escala: 2);
      await _escribir(tester, _clave, 'Aa1${'x' * 80}');
      await tester.pumpAndSettle();
      await _enviarSinTocar(tester);

      for (final texto in [_topeLargo, 'Ingresá tu nombre', 'Ingresá tu apellido']) {
        final aviso = tester.renderObject<RenderParagraph>(find.text(texto));
        expect(aviso.didExceedMaxLines, isFalse, reason: '«$texto» se corta a 2x');
      }
    }, skip: true);

    testWidgets('login con el 5xx, texto al 200 % a 360x640: aviso entero y «Reintentar» a tocar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final remoto = await _montarLogin(tester, tamano: tamanosAcceso.first, escala: 2);
      remoto.falla = const ServidorException(status: 503);
      await _iniciarSesionConFalla(tester);

      await guiasDeAccesibilidad(tester);
      final aviso = tester.renderObject<RenderParagraph>(find.byKey(_loginError));
      expect(aviso.didExceedMaxLines, isFalse);
      final boton = tester.getSize(find.widgetWithText(FilledButton, 'Reintentar'));
      expect(boton.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    Future<void> loginConEntrarAlBorde(WidgetTester tester) async {
      // Fuentes reales (y no las de prueba, que son cuadrados y envuelven de más): la geometría del
      // 200 % tiene que ser la que ve la persona. Va al final del archivo: con las reales,
      // `textContrastGuideline` da falsos negativos.
      await cargarFuentesReales();
      final remoto = await _montarLogin(tester, tamano: tamanosAcceso.first, escala: 2);
      remoto.falla = const ServidorException(status: 503);
      await tester.enterText(find.byKey(_loginCorreo), correoAna);
      await tester.enterText(find.byKey(_loginClave), claveAna);
      // La persona bajó hasta «Entrar» y lo tiene justo al borde de la pantalla.
      await Scrollable.ensureVisible(tester.element(find.byKey(_loginEntrar)), alignment: 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_loginEntrar));
      await tester.pumpAndSettle();
    }

    testWidgets('login 5xx a 360x640 al 200 % con «Entrar» al borde de abajo: el aviso se ve', (
      tester,
    ) async {
      await loginConEntrarAlBorde(tester);

      final aviso = find.byKey(_loginError);
      expect(
        _entraEnLaPantalla(tester, aviso, alto: 640),
        isTrue,
        reason: '${tester.getRect(aviso)}',
      );
    });

    // skip: QA #295 — con el texto al 200 % en 360x640 y «Entrar» al borde de abajo, el aviso del 5xx
    // se ve pero «Reintentar» queda debajo del borde (asoma cortado): el login no baja hasta el
    // aviso como sí hace el registro (login_page.dart, sin `ensureVisible` del error).
    testWidgets(
      'login 5xx a 360x640 al 200 % con «Entrar» al borde de abajo: «Reintentar» queda a la vista',
      (tester) async {
        await loginConEntrarAlBorde(tester);

        final boton = find.widgetWithText(FilledButton, 'Reintentar');
        expect(
          _entraEnLaPantalla(tester, boton, alto: 640),
          isTrue,
          reason: '${tester.getRect(boton)}',
        );
      },
      skip: true,
    );
  });

  group('Casillas sin marcar', () {
    // skip: QA #295 — el borde de la casilla sin marcar es `bordeInput` (#CFD6E1): 1,4:1 contra el
    // fondo, y el canvas dibuja #90A0B7 sobre blanco. WCAG 1.4.11 (AA) pide 3:1 para identificar el
    // componente; con el relleno transparente el borde es lo único que se ve (tema_colportaje.dart:99).
    testWidgets('el borde de la casilla sin marcar se distingue del fondo (WCAG 1.4.11, 3:1)', (
      tester,
    ) async {
      final tema = temaClaro();
      final borde = tema.checkboxTheme.side!.color;

      expect(
        _contraste(borde, tema.scaffoldBackgroundColor),
        greaterThanOrEqualTo(3),
        reason: 'borde $borde sobre ${tema.scaffoldBackgroundColor}',
      );
    }, skip: true);

    testWidgets('marcada y sin marcar se distinguen en las dos casillas del registro', (
      tester,
    ) async {
      await _montarRegistro(tester);
      final antes = tester.widget<Checkbox>(find.byKey(_terminos)).value;
      await _tocar(tester, _terminos);
      final despues = tester.widget<Checkbox>(find.byKey(_terminos)).value;

      expect(antes, isFalse);
      expect(despues, isTrue);
      expect(tester.widget<Checkbox>(find.byKey(_tradeOff)).value, isFalse);
    });
  });
}
