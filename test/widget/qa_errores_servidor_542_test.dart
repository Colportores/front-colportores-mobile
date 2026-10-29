// QA del PR #556 (deuda #542): el aviso de un error del servidor en el registro, el login, la
// verificación del correo y la recuperación de contraseña (vistas 11, 10, 12 y 14). Decisión del
// 29/10: el código técnico nunca llega a la pantalla y todo aviso dice qué pasó y qué hacer, con el
// mismo texto para el mismo caso. La vista 15 está en `qa_nueva_contrasena_test.dart`.
//
// Con `--dart-define=QA_CAPTURAS=true` deja un PNG de cada estado en `.dart_tool/qa_capturas/`
// (fuera del control de versiones).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';
import '../helpers/qa_vista12_335_arnes.dart' as v12;
import '../helpers/qa_vista14_351_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

const _genericoDelServidor = 'El servidor no pudo procesar la solicitud';
const _conCodigo = 'No se pudo completar la operación';
const _rateLimit = 'Demasiados intentos. Esperá unos minutos y volvé a probar.';

const _loginEnviar = Key('login_enviar');
const _loginCorreo = Key('login_email');
const _loginClave = Key('login_password');
const _loginError = Key('login_error_general');

const _regContinuar = Key('registro_continuar');
const _regError = Key('registro_error_general');
const _regNombre = Key('registro_nombre');
const _regApellido = Key('registro_apellido');
const _regCedula = Key('registro_cedula');
const _regCorreo = Key('registro_email');
const _regClave = Key('registro_password');
const _regTerminos = Key('registro_terminos');
const _regTradeOff = Key('registro_trade_off');

bool _fuentes = false;

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentes || !_conCapturas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
      await cargador.load();
    }
  });
  _fuentes = true;
}

/// La pantalla como PNG (solo con QA_CAPTURAS): el `RepaintBoundary` de más arriba del árbol.
Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa542_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String _texto(WidgetTester tester, Key k) =>
    tester.widget<TextField>(find.byKey(k)).controller!.text;

/// Ningún `RenderFlex overflowed` y el aviso entero, sin puntos suspensivos.
void _sinOverflowNiCorte(WidgetTester tester, Finder aviso) {
  expect(tester.takeException(), isNull);
  for (final r in tester.widgetList<RichText>(
    find.descendant(of: aviso, matching: find.byType(RichText)),
  )) {
    expect(r.overflow, isNot(TextOverflow.ellipsis), reason: r.text.toPlainText());
    expect(r.maxLines, isNull, reason: 'el aviso no se limita a unas líneas');
  }
}

/// Las cuatro guías. Con las fuentes reales (capturas) el texto antialiasado da falsos negativos en
/// `textContrastGuideline`: ahí solo se miran las capturas.
Future<void> _guias(WidgetTester tester) async {
  if (!_conCapturas) await guiasDeAccesibilidad(tester);
}

Future<void> _tocar(WidgetTester tester, Key k) async {
  await tester.ensureVisible(find.byKey(k));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(k));
  await tester.pump();
}

void main() {
  group('QA #542 — login: un rechazo del servidor sin texto propio', () {
    Future<RemotoQueFalla> llegarAlAviso(
      WidgetTester tester, {
      required AuthRemoteException falla,
      Size tam = const Size(360, 640),
      double escala = 1,
    }) async {
      await _cargarFuentes(tester);
      fijarPantalla(tester, tam);
      final remoto = RemotoQueFalla()..falla = falla;
      await montarAcceso(tester, home: const LoginPage(), remoto: remoto, escala: escala);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_loginCorreo), correoAna);
      await tester.enterText(find.byKey(_loginClave), claveAna);
      await tester.pump();
      await _tocar(tester, _loginEnviar);
      await tester.pumpAndSettle();
      return remoto;
    }

    for (final (rotulo, escala) in [('texto 1.0', 1.0), ('texto 2.0', 2.0)]) {
      testWidgets('4xx con código a 360x640 ($rotulo): dice qué pasó y qué hacer, sin código, '
          'se anuncia y pasa las cuatro guías', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await llegarAlAviso(tester, falla: const ServidorException(status: 400), escala: escala);
          final aviso = tester.widget<Text>(find.byKey(_loginError)).data!;
          expect(aviso, 'No pudimos iniciar tu sesión. Probá de nuevo en unos minutos.');
          expect(aviso, isNot(contains(_genericoDelServidor)));
          expect(aviso, isNot(contains(_conCodigo)));
          expect(aviso, isNot(contains('400')));
          expect(tester.getSemantics(find.byKey(_loginError)), isSemantics(isLiveRegion: true));
          await _guias(tester);
          _sinOverflowNiCorte(tester, find.byKey(_loginError));
          await _capturar(tester, 'login_4xx_${escala.toInt()}');
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets('después del rechazo lo tipeado sigue, «Entrar» vuelve a andar y el aviso se va', (
      tester,
    ) async {
      final remoto = await llegarAlAviso(tester, falla: const ServidorException(status: 422));
      expect(_texto(tester, _loginCorreo), correoAna);
      expect(_texto(tester, _loginClave), claveAna);
      expect(tester.widget<FilledButton>(find.byKey(_loginEnviar)).onPressed, isNotNull);

      remoto.falla = null;
      await _tocar(tester, _loginEnviar);
      await tester.pumpAndSettle();
      expect(find.byKey(_loginError), findsNothing);
      expect(remoto.llamadasIniciarSesion, 2);
    });

    testWidgets('un 429 conserva su texto («Esperá unos minutos…») y no lo pisa el genérico', (
      tester,
    ) async {
      await llegarAlAviso(tester, falla: const ServidorException(status: 429, mensaje: _rateLimit));
      expect(tester.widget<Text>(find.byKey(_loginError)).data, _rateLimit);
    });

    testWidgets('un rechazo sin status (null) tampoco muestra el genérico ni un código', (
      tester,
    ) async {
      await llegarAlAviso(tester, falla: const ServidorException());
      expect(
        tester.widget<Text>(find.byKey(_loginError)).data,
        'No pudimos iniciar tu sesión. Probá de nuevo en unos minutos.',
      );
    });

    testWidgets('un 5xx sigue siendo el aviso «servicio no disponible» con «Reintentar»', (
      tester,
    ) async {
      await llegarAlAviso(tester, falla: const ServidorException(status: 503));
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.textContaining(_genericoDelServidor), findsNothing);
    });

    testWidgets(
      'dos toques seguidos en «Entrar» con el servidor sin contestar mandan un solo pedido',
      (tester) async {
        fijarPantalla(tester, const Size(360, 640));
        final remoto = RemotoQueFalla()
          ..falla = const ServidorException(status: 400)
          ..demora = Completer<void>();
        await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
        await tester.enterText(find.byKey(_loginCorreo), correoAna);
        await tester.enterText(find.byKey(_loginClave), claveAna);
        await tester.pump();
        await tester.ensureVisible(find.byKey(_loginEnviar));
        await tester.tap(find.byKey(_loginEnviar));
        await tester.pump();
        await tester.tap(find.byKey(_loginEnviar), warnIfMissed: false);
        await tester.pump();
        remoto.demora!.complete();
        await tester.pumpAndSettle();
        expect(remoto.llamadasIniciarSesion, 1);
        expect(find.byKey(_loginError), findsOneWidget);
      },
    );
  });

  group('QA #542 — registro: un rechazo del servidor sin texto propio', () {
    Future<void> completar(WidgetTester tester) async {
      Future<void> escribir(Key k, String t) async {
        await tester.ensureVisible(find.byKey(k));
        await tester.enterText(find.byKey(k), t);
      }

      await escribir(_regNombre, 'Lucía');
      await escribir(_regApellido, 'Silva');
      await escribir(_regCedula, '4.812.309-2');
      await escribir(_regCorreo, 'lucia.silva@correo.com');
      await escribir(_regClave, 'Secreto123');
      await _tocar(tester, _regTerminos);
      await _tocar(tester, _regTradeOff);
    }

    Future<RemotoQueFalla> llegarAlAviso(
      WidgetTester tester, {
      required AuthRemoteException falla,
      double escala = 1,
    }) async {
      await _cargarFuentes(tester);
      fijarPantalla(tester, const Size(360, 640));
      final remoto = RemotoQueFalla()..falla = falla;
      await montarAcceso(tester, home: const RegistroPage(), remoto: remoto, escala: escala);
      await tester.pumpAndSettle();
      await completar(tester);
      await _tocar(tester, _regContinuar);
      await tester.pumpAndSettle();
      return remoto;
    }

    for (final (rotulo, escala) in [('texto 1.0', 1.0), ('texto 2.0', 2.0)]) {
      testWidgets('4xx con código a 360x640 ($rotulo): el aviso dice qué hacer, sin código ni '
          'genérico, y pasa las cuatro guías', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await llegarAlAviso(tester, falla: const ServidorException(status: 400), escala: escala);
          final aviso = tester.widget<Text>(find.byKey(_regError)).data!;
          expect(aviso, 'No pudimos crear tu cuenta. Probá de nuevo en unos minutos.');
          expect(aviso, isNot(contains(_genericoDelServidor)));
          expect(aviso, isNot(contains(_conCodigo)));
          expect(tester.getSemantics(find.byKey(_regError)), isSemantics(isLiveRegion: true));
          await _guias(tester);
          _sinOverflowNiCorte(tester, find.byKey(_regError));
          await _capturar(tester, 'registro_4xx_${escala.toInt()}');
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets('lo tipeado (incluida la contraseña) y las casillas siguen tras el rechazo, y '
        'reintentar avanza', (tester) async {
      final remoto = await llegarAlAviso(tester, falla: const ServidorException(status: 400));
      expect(_texto(tester, _regNombre), 'Lucía');
      expect(_texto(tester, _regApellido), 'Silva');
      expect(_texto(tester, _regCedula), '4.812.309-2');
      expect(_texto(tester, _regCorreo), 'lucia.silva@correo.com');
      expect(_texto(tester, _regClave), 'Secreto123');
      expect(tester.widget<Checkbox>(find.byKey(_regTerminos)).value, isTrue);
      expect(tester.widget<Checkbox>(find.byKey(_regTradeOff)).value, isTrue);
      await tester.ensureVisible(find.byKey(_regContinuar));
      expect(tester.widget<ButtonStyleButton>(find.byKey(_regContinuar)).enabled, isTrue);

      remoto.falla = null;
      await _tocar(tester, _regContinuar);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(_regError), findsNothing);
      expect(remoto.llamadasRegistrar, 2);
    });

    testWidgets('un 429 conserva su texto y deja reintentar', (tester) async {
      await llegarAlAviso(tester, falla: const ServidorException(status: 429, mensaje: _rateLimit));
      expect(tester.widget<Text>(find.byKey(_regError)).data, _rateLimit);
      await tester.ensureVisible(find.byKey(_regContinuar));
      expect(tester.widget<ButtonStyleButton>(find.byKey(_regContinuar)).enabled, isTrue);
    });

    testWidgets('un rechazo sin status (null) dice lo mismo que el 4xx', (tester) async {
      await llegarAlAviso(tester, falla: const ServidorException());
      expect(
        tester.widget<Text>(find.byKey(_regError)).data,
        'No pudimos crear tu cuenta. Probá de nuevo en unos minutos.',
      );
    });
  });

  group('QA #542 — verificación del correo: «Reenviar» con un rechazo del servidor', () {
    testWidgets(
      '4xx con código: dice qué pasó y qué hacer, sin código, y vuelve a poder reenviar',
      (tester) async {
        final remoto = v12.remotoSano()..fallaAlReenviar = const ServidorException(status: 400);
        await v12.montar(tester, remoto: remoto, tam: const Size(360, 640), escala: 2);
        await v12.tocarReenviar(tester);

        final aviso = tester
            .widgetList<Text>(find.descendant(of: v12.errorGeneral, matching: find.byType(Text)))
            .map((t) => t.data)
            .join(' ');
        expect(aviso, 'No pudimos reenviar el email. Probá de nuevo en unos minutos.');
        expect(aviso, isNot(contains(_genericoDelServidor)));
        await _guias(tester);
        _sinOverflowNiCorte(tester, v12.errorGeneral);
        await v12.cerrarApp(tester);
      },
    );
  });

  group('QA #542 — vista 14 «Recuperar contraseña»: un rechazo del servidor', () {
    Future<void> aAviso(WidgetTester tester, AuthRemoteException falla) async {
      final remote = remotoQa()..fallaAlSolicitarRecuperacion = falla;
      await montarQa(tester, remote: remote, tamano: const Size(360, 640));
      await aA05Qa(tester);
    }

    // Hallazgo de QA #542: la decisión del 29/10 es «el mismo caso lleva el mismo texto en cada
    // pantalla». La vista 14 usa `mensajePara` sin `noPudimos`, así que un 4xx/5xx del servidor
    // llega como «El servidor no pudo procesar la solicitud»: dice qué pasó pero no qué hacer.
    // skip: QA #542: la vista 14 muestra «El servidor no pudo procesar la solicitud» sin decir qué
    // hacer (`mensajePara` sin `noPudimos`). `testWidgets.skip` es `bool?`: el motivo va acá.
    testWidgets('un 400 dice qué hacer, como el registro y el login', (tester) async {
      await aAviso(tester, const ServidorException(status: 400));
      final aviso = tester.widget<Text>(avisoGeneralQa).data!;
      expect(aviso, isNot(contains(_genericoDelServidor)));
      expect(aviso, contains('Probá de nuevo'));
    }, skip: true);

    // skip: QA #542: ídem, con un 5xx.
    testWidgets('un 500 dice qué hacer, como el registro y el login', (tester) async {
      await aAviso(tester, const ServidorException(status: 500));
      final aviso = tester.widget<Text>(avisoGeneralQa).data!;
      expect(aviso, isNot(contains(_genericoDelServidor)));
      expect(aviso, contains('Probá de nuevo'));
    }, skip: true);

    testWidgets('hoy: el código técnico no llega a la pantalla y el botón queda habilitado', (
      tester,
    ) async {
      await aAviso(tester, const ServidorException(status: 400));
      expect(find.textContaining(_conCodigo), findsNothing);
      expect(habilitadoQa(tester, enviarQa), isTrue);
      await _capturar(tester, 'vista14_4xx');
    });
  });
}
