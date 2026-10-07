// QA del registro tras sacar el ingreso con Google (#265, PR #295), ronda 1: HU-AUTH-001 y el
// artboard «1a · Registro» de `disenio-vistas/mobile/Login Colportor.dc.html`.
//
// Los tests con `skip:` documentan un hallazgo del comentario de QA del PR #295: el implementador
// saca el `skip` cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';

const _continuar = Key('registro_continuar');
const _errorGeneral = Key('registro_error_general');
const _nombre = Key('registro_nombre');
const _apellido = Key('registro_apellido');
const _cedula = Key('registro_cedula');
const _correo = Key('registro_email');
const _clave = Key('registro_password');
const _terminos = Key('registro_terminos');
const _tradeOff = Key('registro_trade_off');
const _correoNuevo = 'lucia.silva@correo.com';
const _claveNueva = 'Secreto123';

enum _Estado {
  inicial('inicial'),
  erroresDeCampo('errores en todos los campos'),
  emailYaRegistrado('email ya registrado'),
  sinConexion('sin conexión'),
  servidor('fallo del servidor con «Reintentar»'),
  cargando('cargando');

  const _Estado(this.nombre);

  final String nombre;
}

String _tam(Size t) => '${t.width.toInt()}x${t.height.toInt()}';

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

Future<void> _completar(
  WidgetTester tester, {
  String correo = _correoNuevo,
  String clave = _claveNueva,
}) async {
  await _escribir(tester, _nombre, 'Lucía');
  await _escribir(tester, _apellido, 'Silva');
  await _escribir(tester, _cedula, '4.812.309-2');
  await _escribir(tester, _correo, correo);
  await _escribir(tester, _clave, clave);
  await _tocar(tester, _terminos);
  await _tocar(tester, _tradeOff);
}

Future<void> _enviar(WidgetTester tester) async {
  await _tocar(tester, _continuar);
  await tester.pumpAndSettle();
}

String _texto(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).controller!.text;

Future<RemotoQueFalla> _llegarA(
  WidgetTester tester,
  _Estado estado, {
  double escala = 1,
  // El registro se abre desde el login, como en la app: un envío exitoso vuelve a él.
  bool conLogin = true,
}) async {
  final remoto = RemotoQueFalla();
  await montarAcceso(
    tester,
    home: conLogin ? const LoginPage() : const RegistroPage(),
    remoto: remoto,
    escala: escala,
  );
  await tester.pumpAndSettle();
  if (conLogin) {
    await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
    await tester.tap(find.byKey(const Key('login_ir_a_registro')));
    await tester.pumpAndSettle();
  }
  switch (estado) {
    case _Estado.inicial:
      break;
    case _Estado.erroresDeCampo:
      await _enviar(tester);
    case _Estado.emailYaRegistrado:
      await _completar(tester, correo: correoAna);
      await _enviar(tester);
    case _Estado.sinConexion:
      remoto.falla = const SinConexionException();
      await _completar(tester);
      await _enviar(tester);
    case _Estado.servidor:
      remoto.falla = const ServidorException(status: 503);
      await _completar(tester);
      await _enviar(tester);
    case _Estado.cargando:
      remoto.demora = Completer<void>();
      await _completar(tester);
      await _tocar(tester, _continuar);
  }
  return remoto;
}

void main() {
  group('Registro — accesibilidad: toque, etiquetas y contraste', () {
    for (final tamano in tamanosAcceso) {
      for (final estado in _Estado.values) {
        testWidgets('${estado.nombre} a ${_tam(tamano)}', (tester) async {
          final semantica = tester.ensureSemantics();
          fijarPantalla(tester, tamano);
          await _llegarA(tester, estado);

          await guiasDeAccesibilidad(tester);
          semantica.dispose();
        });
      }
    }

    for (final estado in [_Estado.inicial, _Estado.erroresDeCampo, _Estado.emailYaRegistrado]) {
      testWidgets('${estado.nombre} con el texto al 200 % a 360x640', (tester) async {
        final semantica = tester.ensureSemantics();
        fijarPantalla(tester, tamanosAcceso.first);
        await _llegarA(tester, estado, escala: 2);

        await guiasDeAccesibilidad(tester);
        semantica.dispose();
      });
    }
  });

  group('Registro — los errores se anuncian y los botones tienen nombre', () {
    // skip: QA #265: registro_error_general («Ya existe una cuenta…») no es liveRegion: el lector de pantalla no anuncia el fallo
    testWidgets('el error de «email ya registrado» es una región viva (liveRegion)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.emailYaRegistrado);

      expect(tester.getSemantics(find.byKey(_errorGeneral)), isSemantics(isLiveRegion: true));
      semantica.dispose();
    }, skip: true);

    // skip: QA #265: el aviso sin conexión del registro (registro_error_general) no es liveRegion: el lector de pantalla no lo anuncia
    testWidgets('el aviso sin conexión es una región viva (liveRegion)', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.sinConexion);

      expect(tester.getSemantics(find.byKey(_errorGeneral)), isSemantics(isLiveRegion: true));
      semantica.dispose();
    }, skip: true);

    // skip: QA #265: el aviso del 5xx del registro (BannerErrorConAccion) no es liveRegion: el lector de pantalla no lo anuncia
    testWidgets('el aviso del fallo del servidor (con «Reintentar») es una región viva', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.servidor);

      expect(tester.getSemantics(find.byKey(_errorGeneral)), isSemantics(isLiveRegion: true));
      semantica.dispose();
    }, skip: true);

    // skip: QA #265: «Tenés que aceptar los términos.» no es liveRegion: el lector de pantalla no lo anuncia
    testWidgets('«Tenés que aceptar los términos.» se anuncia (liveRegion)', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.erroresDeCampo);

      expect(
        tester.getSemantics(find.byKey(const Key('registro_terminos_error'))),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    }, skip: true);

    // skip: QA #265: la flecha de volver (registro_atras) se lee «‹»: sin tooltip ni Semantics.label «Volver»
    testWidgets('la flecha de volver se llama «Volver» para el lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.inicial);

      expect(tester.getSemantics(find.byKey(const Key('registro_atras'))).label, 'Volver');
      semantica.dispose();
    }, skip: true);

    testWidgets('la flecha de volver mide al menos 48x48', (tester) async {
      await _llegarA(tester, _Estado.inicial);

      final caja = tester.getSize(find.byKey(const Key('registro_atras')));
      expect(caja.width, greaterThanOrEqualTo(48));
      expect(caja.height, greaterThanOrEqualTo(48));
    });

    // skip: QA #265: con el envío en vuelo «Continuar» solo muestra el spinner y queda sin nombre accesible
    testWidgets('«Continuar» ocupado conserva un nombre para el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.cargando);

      expect(tester.getSemantics(find.byKey(_continuar)).label, isNotEmpty);
      semantica.dispose();
    }, skip: true);
  });

  group('Registro — tamaños, texto grande y teclado', () {
    for (final tamano in tamanosAcceso) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('sin overflow con todos los errores a ${_tam(tamano)}, texto ×$escala', (
          tester,
        ) async {
          fijarPantalla(tester, tamano);
          await _llegarA(tester, _Estado.erroresDeCampo, escala: escala);

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(_continuar));
          await tester.pumpAndSettle();
          expect(find.byKey(_continuar).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('sin overflow con «email ya registrado» a ${_tam(tamano)}, texto ×$escala', (
          tester,
        ) async {
          fijarPantalla(tester, tamano);
          await _llegarA(tester, _Estado.emailYaRegistrado, escala: escala);

          expect(tester.takeException(), isNull);
          for (final k in const [
            Key('registro_email_duplicado_ir_a_login'),
            Key('registro_email_duplicado_ir_a_recuperar'),
          ]) {
            await tester.ensureVisible(find.byKey(k));
            await tester.pumpAndSettle();
            expect(find.byKey(k).hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('con el teclado abierto (360x640) la contraseña y «Continuar» quedan sobre el '
        'teclado', (tester) async {
      fijarPantalla(tester, tamanosAcceso.first);
      await _llegarA(tester, _Estado.inicial);

      // Como en el teléfono: primero el foco y después sube el teclado.
      await tester.ensureVisible(find.byKey(_clave));
      await tester.tap(find.byKey(_clave));
      await tester.pumpAndSettle();
      abrirTeclado(tester, 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_clave)).bottom, lessThanOrEqualTo(640 - 300));

      await tester.ensureVisible(find.byKey(_continuar));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_continuar)).bottom, lessThanOrEqualTo(640 - 300));
      expect(find.byKey(_continuar).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // skip: QA #265: a 360x640, al tocar «Continuar» con el formulario vacío el error del primer campo queda fuera de pantalla y no se mueve el foco
    testWidgets('con los errores en pantalla, al tocar «Continuar» el primer error queda a la '
        'vista (360x640)', (tester) async {
      fijarPantalla(tester, tamanosAcceso.first);
      await _llegarA(tester, _Estado.inicial);

      await _tocar(tester, _continuar);
      await tester.pumpAndSettle();

      final nombre = tester.getRect(find.text('Ingresá tu nombre'));
      expect(
        nombre.top >= 0 && nombre.bottom <= 640,
        isTrue,
        reason: 'el error del primer campo queda fuera de la pantalla: ${nombre.top}',
      );
    }, skip: true);

    testWidgets(
      'texto pegado muy largo en nombre, correo y contraseña: sin overflow (360x640 ×2)',
      (tester) async {
        fijarPantalla(tester, tamanosAcceso.first);
        await _llegarA(tester, _Estado.inicial, escala: 2);

        await _escribir(tester, _nombre, 'N' * 5000);
        await _escribir(tester, _apellido, 'A' * 5000);
        await _escribir(tester, _correo, '${'a' * 5000}@example.com');
        await _escribir(tester, _clave, 'C1${'x' * 3000}');
        await _enviar(tester);

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Registro — validación de entradas', () {
    testWidgets('nombre y apellido con solo espacios cuentan como vacíos', (tester) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _completar(tester);
      await _escribir(tester, _nombre, '     ');
      await _escribir(tester, _apellido, '     ');
      await _enviar(tester);

      expect(find.text('Ingresá tu nombre'), findsOneWidget);
      expect(find.text('Ingresá tu apellido'), findsOneWidget);
      expect(remoto.llamadasRegistrar, 0);
    });

    for (final (cedula, vale) in [
      ('4.812.309-2', true),
      ('48123092', true),
      ('1234567', true),
      ('123456', false),
      ('123456789', false),
      ('ABC12345', false),
      ('4812309 2', false),
    ]) {
      testWidgets('la cédula «$cedula» ${vale ? 'se acepta' : 'se rechaza con un aviso'}', (
        tester,
      ) async {
        final remoto = await _llegarA(tester, _Estado.inicial);

        await _completar(tester);
        await _escribir(tester, _cedula, cedula);
        await _enviar(tester);

        expect(find.text('La cédula no es válida'), vale ? findsNothing : findsOneWidget);
        expect(remoto.llamadasRegistrar, vale ? 1 : 0);
      });
    }

    for (final invalida in ['Secreto', 'secreto123', 'Secretoabc', 'Sec1', '        ']) {
      testWidgets('la contraseña «$invalida» muestra los requisitos y no se envía', (tester) async {
        final remoto = await _llegarA(tester, _Estado.inicial);

        await _completar(tester, clave: invalida);
        await _enviar(tester);

        expect(find.text('Usá al menos 8 caracteres, una mayúscula y un número.'), findsOneWidget);
        expect(remoto.llamadasRegistrar, 0);
      });
    }

    for (final valida in ['Ñandú2026', 'Élan2026', 'Clave😀1234']) {
      testWidgets('la contraseña «$valida» cumple la política (decisión del 02/10, S1)', (
        tester,
      ) async {
        final remoto = await _llegarA(tester, _Estado.inicial);

        await _completar(tester, clave: valida);
        await _enviar(tester);

        expect(find.text('Usá al menos 8 caracteres, una mayúscula y un número.'), findsNothing);
        expect(remoto.llamadasRegistrar, 1);
      });
    }

    testWidgets('el correo con espacios y mayúsculas se normaliza (trim + minúsculas)', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _completar(tester, correo: '  Lucia.Silva@Correo.COM  ');
      await _enviar(tester);

      expect(remoto.interno.usuariosRegistrados.keys, ['lucia.silva@correo.com']);
    });

    testWidgets('nombre y apellido con tilde, ñ y emoji viajan como se escribieron', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _completar(tester);
      await _escribir(tester, _nombre, 'Ñandú José 😀');
      await _escribir(tester, _apellido, "D'Ávila-Müller");
      await _enviar(tester);

      final usuario = remoto.interno.usuariosRegistrados[_correoNuevo]!;
      expect(usuario.nombre, 'Ñandú José 😀');
      expect(usuario.apellido, "D'Ávila-Müller");
    });

    // skip: QA #265: nombre/apellido/correo no tienen tope de largo: un texto pegado de 5000 caracteres llega al servidor
    testWidgets('el nombre tiene un tope de largo (un texto pegado de 5000 caracteres no viaja)', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _completar(tester);
      await _escribir(tester, _nombre, 'N' * 5000);
      await _enviar(tester);

      expect(remoto.llamadasRegistrar, 0);
    }, skip: true);

    testWidgets('con errores a la vista, lo tipeado se conserva y las casillas siguen marcadas', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.inicial);

      await _completar(tester, clave: 'corta');
      await _enviar(tester);

      expect(_texto(tester, _nombre), 'Lucía');
      expect(_texto(tester, _correo), _correoNuevo);
      expect(_texto(tester, _clave), 'corta');
      expect(tester.widget<Checkbox>(find.byKey(_terminos)).value, isTrue);
      expect(tester.widget<Checkbox>(find.byKey(_tradeOff)).value, isTrue);
    });
  });

  group('Registro — estados y casos límite', () {
    testWidgets(
      'sin conexión: texto literal de HU-AUTH-001, datos conservados salvo la contraseña',
      (tester) async {
        await _llegarA(tester, _Estado.sinConexion);

        expect(find.text('Necesitás conexión para registrarte por primera vez'), findsOneWidget);
        expect(_texto(tester, _nombre), 'Lucía');
        expect(_texto(tester, _cedula), '4.812.309-2');
        expect(_texto(tester, _correo), _correoNuevo);
        expect(_texto(tester, _clave), isEmpty, reason: 'la contraseña no se conserva (HU)');
        expect(tester.widget<Checkbox>(find.byKey(_terminos)).value, isTrue);
        expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNotNull);
      },
    );

    testWidgets('sin conexión y después con conexión: se vuelve a escribir la contraseña y la '
        'cuenta se crea', (tester) async {
      final remoto = await _llegarA(tester, _Estado.sinConexion);

      remoto.falla = null;
      await _escribir(tester, _clave, _claveNueva);
      await _enviar(tester);

      expect(remoto.llamadasRegistrar, 2);
      expect(remoto.interno.usuariosRegistrados.keys, [_correoNuevo]);
      expect(find.byKey(_errorGeneral), findsNothing);
    });

    testWidgets('fallo del servidor: «Reintentar» crea la cuenta cuando el servidor vuelve', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.servidor);
      expect(
        find.text('Servicio temporalmente no disponible, reintentá en unos minutos'),
        findsOneWidget,
      );

      remoto.falla = null;
      await tester.ensureVisible(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(remoto.llamadasRegistrar, 2);
      expect(remoto.interno.usuariosRegistrados.keys, [_correoNuevo]);
    });

    testWidgets('«email ya registrado»: corregir el correo y reintentar crea la cuenta', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.emailYaRegistrado);
      expect(
        find.text(
          'Ya existe una cuenta con ese email. ¿Querés iniciar sesión o recuperar tu '
          'contraseña?',
        ),
        findsOneWidget,
      );

      await _escribir(tester, _correo, _correoNuevo);
      await _enviar(tester);

      expect(remoto.interno.usuariosRegistrados.keys, [_correoNuevo]);
      expect(find.byKey(_errorGeneral), findsNothing);
    });

    testWidgets('«email ya registrado»: «Recuperar contraseña» y volver conserva el formulario', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.emailYaRegistrado);

      await tester.ensureVisible(find.byKey(const Key('registro_email_duplicado_ir_a_recuperar')));
      await tester.tap(find.byKey(const Key('registro_email_duplicado_ir_a_recuperar')));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(_texto(tester, _correo), correoAna);
      expect(_texto(tester, _nombre), 'Lucía');
      expect(find.byKey(_errorGeneral), findsOneWidget);
    });

    testWidgets('«email ya registrado»: «Iniciar sesión» vuelve al login', (tester) async {
      await _llegarA(tester, _Estado.emailYaRegistrado, conLogin: true);

      await tester.ensureVisible(find.byKey(const Key('registro_email_duplicado_ir_a_login')));
      await tester.tap(find.byKey(const Key('registro_email_duplicado_ir_a_login')));
      await tester.pumpAndSettle();

      expect(find.byType(RegistroPage), findsNothing);
      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
    });

    testWidgets('el correo recién registrado pasa a «Verificá tu email» y «atrás» no vuelve al '
        'formulario lleno', (tester) async {
      final remoto = RemotoQueFalla(
        AuthRemoteDataSourceEnMemoria(
          credenciales: const {correoAna: claveAna},
          requiereVerificacionAlRegistrar: true,
        ),
      );
      await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
      await tester.tap(find.byKey(const Key('login_ir_a_registro')));
      await tester.pumpAndSettle();

      await _completar(tester);
      await _enviar(tester);

      expect(find.byType(VerificacionEmailPage), findsOneWidget);
      expect(find.byType(RegistroPage), findsNothing);
    });

    testWidgets('cargando: «Continuar» deshabilitado con spinner y el formulario intacto', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.cargando);

      expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_texto(tester, _correo), _correoNuevo);

      remoto.demora!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Continuar por teclado (acción «listo») con el envío en vuelo no registra dos '
        'veces', (tester) async {
      final remoto = await _llegarA(tester, _Estado.cargando);

      await tester.ensureVisible(find.byKey(_clave));
      await tester.tap(find.byKey(_clave));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(remoto.llamadasRegistrar, 1);
      remoto.demora!.complete();
      await tester.pumpAndSettle();
      expect(remoto.llamadasRegistrar, 1);
    });

    testWidgets('falla a mitad: el botón vuelve a habilitarse y no queda ningún spinner', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.cargando);
      remoto.falla = const SinConexionException();

      remoto.demora!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(_continuar)).onPressed, isNotNull);
      expect(find.byKey(_errorGeneral), findsOneWidget);
    });

    testWidgets('«Atrás» del sistema vuelve al login y el registro reabre vacío', (tester) async {
      await _llegarA(tester, _Estado.sinConexion, conLogin: true);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RegistroPage), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
      await tester.tap(find.byKey(const Key('login_ir_a_registro')));
      await tester.pumpAndSettle();
      expect(_texto(tester, _nombre), isEmpty);
      expect(find.byKey(_errorGeneral), findsNothing);
      expect(tester.widget<Checkbox>(find.byKey(_terminos)).value, isFalse);
    });
  });
}
