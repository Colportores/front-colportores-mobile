// QA del login tras sacar el ingreso con Google (#265, PR #295), ronda 1: HU-AUTH-003 y el
// artboard «1a · Login» de `disenio-vistas/mobile/Login Colportor.dc.html`.
//
// Los tests con `skip:` documentan un hallazgo del comentario de QA del PR #295: el implementador
// saca el `skip` cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';

const _enviar = Key('login_enviar');
const _correo = Key('login_email');
const _clave = Key('login_password');
const _errorGeneral = Key('login_error_general');

const _reingreso = DatosReingreso(
  motivo: MotivoExpiracion.inactividad,
  email: 'lucia.silva@correo.com',
  nombre: 'Lucía',
);

enum _Estado {
  inicial('inicial'),
  erroresDeCampo('errores de campo'),
  credencialesIncorrectas('credenciales incorrectas'),
  sinConexion('sin conexión'),
  cargando('cargando'),
  sesionVencida('«Sesión vencida» con aviso');

  const _Estado(this.nombre);

  final String nombre;
}

/// Monta el login y lo lleva a [estado]. Devuelve el remoto para seguir operando.
Future<RemotoQueFalla> _llegarA(WidgetTester tester, _Estado estado, {double escala = 1}) async {
  final remoto = RemotoQueFalla();
  await montarAcceso(
    tester,
    home: const LoginPage(),
    remoto: remoto,
    escala: escala,
    reingreso: estado == _Estado.sesionVencida ? _reingreso : null,
  );
  await tester.pumpAndSettle();
  switch (estado) {
    case _Estado.inicial:
      break;
    case _Estado.erroresDeCampo:
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();
    case _Estado.credencialesIncorrectas:
      await _escribir(tester, clave: 'incorrecta1');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();
    case _Estado.sinConexion:
      remoto.falla = const SinConexionException();
      await _escribir(tester);
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();
    case _Estado.cargando:
      remoto.demora = Completer<void>();
      await _escribir(tester);
      await _tocarEntrar(tester);
      await tester.pump();
    case _Estado.sesionVencida:
      ProviderScope.containerOf(
        tester.element(find.byType(LoginPage)),
      ).read(avisoSesionProvider.notifier).mostrar(const FailureSesionExpiradaPorInactividad());
      await tester.pumpAndSettle();
  }
  return remoto;
}

Future<void> _escribir(
  WidgetTester tester, {
  String correo = correoAna,
  String clave = claveAna,
}) async {
  await tester.enterText(find.byKey(_correo), correo);
  await tester.enterText(find.byKey(_clave), clave);
}

Future<void> _tocarEntrar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_enviar));
  await tester.tap(find.byKey(_enviar));
}

String _texto(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).controller!.text;

String _tam(Size t) => '${t.width.toInt()}x${t.height.toInt()}';

void main() {
  // Item 6 del checklist: tamaño de toque (Android e iOS), etiquetas y contraste en cada estado y
  // en los tres teléfonos. `login_page_test.dart` no corría ninguna de las cuatro guías.
  group('Login — accesibilidad: toque, etiquetas y contraste', () {
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

    for (final estado in [
      _Estado.inicial,
      _Estado.credencialesIncorrectas,
      _Estado.sesionVencida,
    ]) {
      testWidgets('${estado.nombre} con el texto al 200 % a 360x640', (tester) async {
        final semantica = tester.ensureSemantics();
        fijarPantalla(tester, tamanosAcceso.first);
        await _llegarA(tester, estado, escala: 2);

        await guiasDeAccesibilidad(tester);
        semantica.dispose();
      });
    }
  });

  group('Login — los errores se anuncian al lector de pantalla', () {
    // skip: QA #265: login_error_general («Email o contraseña incorrectos») no es liveRegion: el lector de pantalla no anuncia el fallo
    testWidgets('el error de credenciales es una región viva (liveRegion)', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.credencialesIncorrectas);

      expect(tester.getSemantics(find.byKey(_errorGeneral)), isSemantics(isLiveRegion: true));
      semantica.dispose();
    }, skip: true);

    // skip: QA #265: el aviso sin conexión del login (login_error_general) no es liveRegion: el lector de pantalla no lo anuncia
    testWidgets('el aviso sin conexión es una región viva (liveRegion)', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.sinConexion);

      expect(tester.getSemantics(find.byKey(_errorGeneral)), isSemantics(isLiveRegion: true));
      semantica.dispose();
    }, skip: true);

    // skip: QA #265: con el envío en vuelo «Entrar» solo muestra el spinner y queda sin nombre accesible
    testWidgets('«Entrar» ocupado conserva un nombre para el lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.cargando);

      expect(tester.getSemantics(find.byKey(_enviar)).label, isNotEmpty);
      semantica.dispose();
    }, skip: true);
  });

  // Item 7 y 5b: tamaños, texto grande y teclado abierto.
  group('Login — tamaños, texto grande y teclado', () {
    for (final tamano in tamanosAcceso) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('sin overflow y «Entrar» alcanzable a ${_tam(tamano)}, texto ×$escala, con '
            'error', (tester) async {
          fijarPantalla(tester, tamano);
          await _llegarA(tester, _Estado.credencialesIncorrectas, escala: escala);

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(_enviar));
          await tester.pumpAndSettle();
          expect(find.byKey(_enviar).hitTestable(), findsOneWidget);
          expect(find.byKey(_errorGeneral), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets('con el teclado abierto (360x640, texto ×$escala) el campo y «Entrar» quedan '
          'sobre el teclado', (tester) async {
        fijarPantalla(tester, tamanosAcceso.first);
        await _llegarA(tester, _Estado.inicial, escala: escala);

        // Como en el teléfono: primero el foco y después sube el teclado.
        await tester.ensureVisible(find.byKey(_clave));
        await tester.tap(find.byKey(_clave));
        await tester.pumpAndSettle();
        abrirTeclado(tester, 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byKey(_clave)).bottom,
          lessThanOrEqualTo(640 - 300),
          reason: 'el campo que se está escribiendo no queda tapado por el teclado',
        );

        await tester.ensureVisible(find.byKey(_enviar));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_enviar)).bottom, lessThanOrEqualTo(640 - 300));
        expect(find.byKey(_enviar).hitTestable(), findsOneWidget);
      });
    }

    testWidgets('texto pegado muy largo en el correo y la contraseña: sin overflow (360x640 ×2)', (
      tester,
    ) async {
      fijarPantalla(tester, tamanosAcceso.first);
      await _llegarA(tester, _Estado.inicial, escala: 2);

      await _escribir(tester, correo: '${'a' * 5000}@example.com', clave: 'C1${'x' * 3000}');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Login — validación de entradas', () {
    testWidgets('vacío: avisa qué falta en cada campo y no llama al remoto', (tester) async {
      final remoto = await _llegarA(tester, _Estado.erroresDeCampo);

      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(remoto.llamadasIniciarSesion, 0);
    });

    testWidgets('el correo con solo espacios cuenta como vacío', (tester) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _escribir(tester, correo: '     ');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(remoto.llamadasIniciarSesion, 0);
    });

    for (final invalido in ['ana', 'ana@', '@example.com', 'ana@example', 'ana @example.com']) {
      testWidgets('el correo «$invalido» no es válido y no sale del teléfono', (tester) async {
        final remoto = await _llegarA(tester, _Estado.inicial);

        await _escribir(tester, correo: invalido);
        await _tocarEntrar(tester);
        await tester.pumpAndSettle();

        expect(find.text('El email no es válido'), findsOneWidget);
        expect(remoto.llamadasIniciarSesion, 0);
      });
    }

    testWidgets('una contraseña de 7 caracteres dice cuántos hacen falta', (tester) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _escribir(tester, clave: 'abcdefg');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      expect(find.text('La contraseña tiene al menos 8 caracteres'), findsOneWidget);
      expect(remoto.llamadasIniciarSesion, 0);
    });

    testWidgets('HU-AUTH-003 caso borde: el correo con mayúsculas y espacios entra igual', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.inicial);

      await _escribir(tester, correo: '  ANA@Example.COM  ');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      expect(remoto.llamadasIniciarSesion, 1);
      final container = ProviderScope.containerOf(tester.element(find.byType(LoginPage)));
      expect(container.read(sesionProvider).value?.email, correoAna);
    });

    testWidgets('una contraseña con emoji, ñ y espacios viaja intacta (sin trim)', (tester) async {
      final remoto = RemotoQueFalla(
        AuthRemoteDataSourceEnMemoria(credenciales: const {correoAna: ' Clave ñ😀 123 '}),
      );
      await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
      await tester.pumpAndSettle();

      await _escribir(tester, clave: ' Clave ñ😀 123 ');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(LoginPage)));
      expect(container.read(sesionProvider).value?.email, correoAna);
    });

    testWidgets('un correo con emoji no revienta: llega al servidor y vuelve «incorrectos»', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.inicial);

      await _escribir(tester, correo: 'ana😀@example.com');
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('después de un error no se pierde lo tipeado', (tester) async {
      await _llegarA(tester, _Estado.credencialesIncorrectas);

      expect(_texto(tester, _correo), correoAna);
      expect(_texto(tester, _clave), 'incorrecta1');
      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
    });

    testWidgets('al reintentar, el aviso anterior desaparece mientras corre el nuevo envío', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.credencialesIncorrectas);
      remoto.demora = Completer<void>();

      await _tocarEntrar(tester);
      await tester.pump();

      expect(find.byKey(_errorGeneral), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      remoto.demora!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('Login — estados y casos límite', () {
    testWidgets('cargando: «Entrar» deshabilitado con spinner y los campos conservan lo escrito', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.cargando);

      expect(tester.widget<FilledButton>(find.byKey(_enviar)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_texto(tester, _correo), correoAna);

      remoto.demora!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Entrar por teclado (acción «listo») con el envío en vuelo no manda un segundo '
        'inicio de sesión', (tester) async {
      final remoto = await _llegarA(tester, _Estado.cargando);

      await tester.tap(find.byKey(_clave));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(remoto.llamadasIniciarSesion, 1);
      remoto.demora!.complete();
      await tester.pumpAndSettle();
      expect(remoto.llamadasIniciarSesion, 1);
    });

    testWidgets('acciones superpuestas: falla la primera, el segundo toque llega después y entra', (
      tester,
    ) async {
      final remoto = await _llegarA(tester, _Estado.inicial);
      remoto
        ..demora = Completer<void>()
        ..falla = const SinConexionException();
      await _escribir(tester);

      await _tocarEntrar(tester);
      await tester.pump();
      await tester.tap(find.byKey(_enviar), warnIfMissed: false);
      remoto.demora!.complete();
      await tester.pumpAndSettle();
      expect(remoto.llamadasIniciarSesion, 1, reason: 'el segundo toque se ignora en vuelo');
      expect(tester.widget<FilledButton>(find.byKey(_enviar)).onPressed, isNotNull);

      remoto
        ..demora = null
        ..falla = null;
      await _tocarEntrar(tester);
      await tester.pumpAndSettle();
      expect(remoto.llamadasIniciarSesion, 2);
    });

    testWidgets('sin conexión: texto literal de HU-AUTH-003 y el botón sigue disponible', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.sinConexion);

      expect(
        find.text('Necesitás conexión para iniciar sesión por primera vez en este dispositivo.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(find.byKey(_enviar)).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // skip: QA #265: el 5xx del login muestra «El servidor no pudo procesar la solicitud» sin decir qué hacer (convenciones §10)
    testWidgets('una falla del servidor (5xx) dice qué hacer (convenciones §10)', (tester) async {
      final remoto = await _llegarA(tester, _Estado.inicial);
      remoto.falla = const ServidorException(status: 503);
      await _escribir(tester);

      await _tocarEntrar(tester);
      await tester.pumpAndSettle();

      final aviso = tester.widget<Text>(find.byKey(_errorGeneral)).data!;
      expect(aviso.toLowerCase(), contains('reintent'), reason: aviso);
    }, skip: true);

    testWidgets('«¿Olvidaste tu clave?» lleva el correo tipeado y al volver el login lo conserva', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.credencialesIncorrectas);

      await tester.ensureVisible(find.byKey(const Key('login_olvidaste_clave')));
      await tester.tap(find.byKey(const Key('login_olvidaste_clave')));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      expect(find.text(correoAna), findsWidgets);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(_texto(tester, _correo), correoAna);
      expect(_texto(tester, _clave), 'incorrecta1');
    });

    testWidgets('«Atrás» del sistema desde el registro vuelve al login con el error a la vista', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.credencialesIncorrectas);

      await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
      await tester.tap(find.byKey(const Key('login_ir_a_registro')));
      await tester.pumpAndSettle();
      expect(find.byType(RegistroPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(RegistroPage), findsNothing);
      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
    });

    testWidgets('«Sesión vencida»: el aviso se cierra y el saludo con «Recuperar acceso» queda', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.sesionVencida);

      expect(find.text('Hola de nuevo, Lucía'), findsOneWidget);
      expect(find.text('Recuperar acceso'), findsOneWidget);
      expect(_texto(tester, _correo), 'lucia.silva@correo.com');

      await tester.tap(find.byKey(const Key('login_aviso_sesion_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_aviso_sesion')), findsNothing);
      expect(find.text('Hola de nuevo, Lucía'), findsOneWidget);
    });
  });

  group('Login — contraseña visible y casilla «Mantener sesión»', () {
    testWidgets('el ojo muestra y oculta la contraseña sin perder lo escrito', (tester) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.inicial);
      await _escribir(tester);

      TextField campo() => tester.widget<TextField>(find.byKey(_clave));
      expect(campo().obscureText, isTrue);
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);

      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();
      expect(campo().obscureText, isFalse);
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      expect(_texto(tester, _clave), claveAna);
      semantica.dispose();
    });

    testWidgets('la casilla «Mantener sesión» tiene nombre y rol de casilla para el lector', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _llegarA(tester, _Estado.inicial);

      expect(
        tester.getSemantics(find.byType(Checkbox)),
        isSemantics(label: 'Mantener sesión', hasCheckedState: true, isChecked: true),
      );
      semantica.dispose();
    });
  });
}
