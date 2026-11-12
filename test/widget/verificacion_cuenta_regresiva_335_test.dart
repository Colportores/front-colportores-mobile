// «Reenviar en Ns» como relleno del botón, igual que el canvas de la vista 12 (A03 y A01b; #335,
// seguimiento de #325, decisión del 09/10): el botón apagado se rellena de izquierda a derecha con lo
// transcurrido de los 60 s, el rótulo va en JetBrains Mono y no hay barra de 3 px debajo. El texto no
// cambia. Todo con las fuentes reales del proyecto: sin ellas `flutter_test` pinta cuadrados y las
// medidas no son las de un teléfono.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/colores_colportaje.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart' show fijarPantalla;
import '../helpers/db_local_repository_en_memoria.dart';

const _lucia = 'lucia.silva@correo.com';
final _base = DateTime(2026, 10, 16, 14, 35);

/// Los colores del canvas (`12 Verificacion Email.dc.html`, A03): relleno `#F3F1EA`, texto `#5B6B82`.
const _rellenoDelCanvas = Color(0xFFF3F1EA);
const _textoDelCanvas = Color(0xFF5B6B82);

final _boton = find.byKey(const Key('verificacion_email_reenviar'));
final _relleno = find.byKey(const Key('verificacion_email_progreso'));
final _mensajeReenvio = find.byKey(const Key('verificacion_email_mensaje_reenvio'));
final _barra = find.byKey(const Key('verificacion_email_barra'));

final _llave = GlobalKey();

/// La pantalla completa como PNG, fuera del repo (`.dart_tool/` no se commitea).
Future<void> _capturar(WidgetTester tester, String nombre) => tester.runAsync(() async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_llave));
  final img = await render.toImage();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
  File('${dir.path}/335_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

bool _fuentesCargadas = false;

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

/// Reloj que el test mueve a mano.
final class _Reloj {
  _Reloj(this.ahora);

  DateTime ahora;

  DateTime leer() => ahora;

  /// Pasa [segundos] de a uno, como los `Timer` de la pantalla, y deja el reloj en la hora nueva.
  Future<void> pasar(WidgetTester tester, int segundos) async {
    for (var i = 0; i < segundos; i++) {
      ahora = ahora.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

AuthRemoteDataSourceEnMemoria _remotoSano() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {_lucia: 'Secreto123'});

/// [VerificacionEmailPage] aislada, con el reloj y el lugar donde se recuerda la espera a mano.
Future<void> _montar(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  required BloqueoReenvioVerificacionRepository bloqueos,
  required DateTime Function() ahora,
  String email = _lucia,
  String? password = 'Secreto123',
  EstadoVerificacionEmail estado = EstadoVerificacionEmail.pendiente,
  DateTime? envioDelAlta,
  double escala = 1,
  Size tam = const Size(390, 844),
}) async {
  await _cargarFuentes(tester);
  fijarPantalla(tester, tam);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(bloqueos),
      ],
      child: RepaintBoundary(
        key: _llave,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: VerificacionEmailPage(
            email: email,
            password: password,
            estadoInicial: estado,
            envioDelAlta: envioDelAlta,
            ahora: ahora,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Saca la pantalla del árbol (como cerrar la app) para volver a montarla desde cero.
Future<void> _cerrarApp(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> _tocarReenviar(WidgetTester tester) async {
  await tester.ensureVisible(_boton);
  await tester.tap(_boton);
  await tester.pumpAndSettle();
}

bool _habilitado(WidgetTester tester) => tester.widget<ButtonStyleButton>(_boton).onPressed != null;

/// Cuánto del botón está relleno: lo transcurrido de los 60 s, de 0 a 1.
double _transcurrido(WidgetTester tester) =>
    tester.widget<FractionallySizedBox>(_relleno).widthFactor!;

/// El botón tal como se ve (sin el margen de toque que le suma Material).
Finder get _visual => find.descendant(of: _boton, matching: find.byType(Material)).first;

TextStyle _estiloDelRotulo(WidgetTester tester, String texto) => tester
    .widget<RichText>(find.descendant(of: find.text(texto), matching: find.byType(RichText)))
    .text
    .style!;

Color _colorDelRelleno(WidgetTester tester) => tester
    .widget<ColoredBox>(find.descendant(of: _relleno, matching: find.byType(ColoredBox)))
    .color;

/// Lo que se ve detrás del rótulo donde el relleno todavía no llegó: el fondo del botón (si lo tiene)
/// sobre el crema de la pantalla.
Color _fondoSinRellenar(WidgetTester tester) {
  final crema = Theme.of(tester.element(_boton)).scaffoldBackgroundColor;
  final propio = tester.widget<Material>(_visual).color ?? Colors.transparent;
  return Color.alphaBlend(propio, crema);
}

/// La forma del botón «Reenviar»: `'píldora'` o el radio de las esquinas del rectángulo.
Object _forma(WidgetTester tester) => switch (tester.widget<Material>(_visual).shape) {
  StadiumBorder() => 'píldora',
  RoundedRectangleBorder(:final borderRadius) => borderRadius,
  final otra => otra!.runtimeType,
};

/// Que el recorte del relleno sigue la forma del botón, con [radio] de esquina (lo que no entra en
/// la forma no se pinta): la esquina de arriba a la izquierda queda afuera y el medio del borde
/// izquierdo, adentro.
void _recorteSigueLaForma(WidgetTester tester, {required double radio}) {
  final recorte = find.descendant(of: _boton, matching: find.byType(ClipPath));
  expect(recorte, findsOneWidget);
  final tam = tester.getSize(recorte);
  final camino = tester.widget<ClipPath>(recorte).clipper!.getClip(tam);
  expect(camino.contains(const Offset(1, 1)), isFalse, reason: 'la esquina queda afuera');
  expect(
    camino.contains(Offset(0.5, tam.height / 2)),
    isTrue,
    reason: 'el medio del borde, adentro',
  );
  expect(camino.contains(Offset(radio, tam.height / 2)), isTrue);
  expect(
    camino.contains(Offset(tam.width - 1, 1)),
    isFalse,
    reason: 'la esquina de arriba a la derecha, afuera',
  );
}

double _contraste(Color a, Color b) {
  final claro = a.computeLuminance() > b.computeLuminance() ? a : b;
  final oscuro = identical(claro, a) ? b : a;
  return (claro.computeLuminance() + 0.05) / (oscuro.computeLuminance() + 0.05);
}

void main() {
  // Inventario del diseño (canvas 12) que toca la cuenta regresiva: A02 (60 s, sin relleno todavía),
  // A03 (42 s, 30 %), A01b (la espera cuenta desde el correo del alta). El resto de los artboards
  // (A01, A04, A04b, A05, A06, A07, A08) no cambian y siguen en sus tests.
  group('12-A03 · cuenta regresiva activa', () {
    testWidgets('dado «Reenviar en 42s» (18 s después de reenviar), el botón está relleno el 30 % '
        'de izquierda a derecha y no hay barra debajo', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);

      await reloj.pasar(tester, 18);

      expect(find.text('Reenviar en 42s'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      expect(_transcurrido(tester), closeTo(0.3, 1e-9));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // Geometría: el relleno nace en el borde izquierdo de adentro del botón, cubre todo su alto sin
      // tapar el borde y mide el 30 % del ancho de adentro.
      final boton = tester.getRect(_visual);
      final relleno = tester.getRect(_relleno);
      expect(relleno.left, closeTo(boton.left + 1.5, 0.01));
      expect(relleno.top, closeTo(boton.top + 1.5, 0.01));
      expect(relleno.height, closeTo(boton.height - 3, 0.01));
      expect(relleno.width, closeTo((boton.width - 3) * 0.3, 0.01));
      await _cerrarApp(tester);
    });

    testWidgets('el rótulo va en JetBrains Mono y, fuera de la cuenta, en Inter', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      expect(_estiloDelRotulo(tester, 'Reenviar email').fontFamily, 'Inter');

      await _tocarReenviar(tester);

      expect(_estiloDelRotulo(tester, 'Reenviar en 60s').fontFamily, 'JetBrainsMono');
      await reloj.pasar(tester, 60);
      expect(_estiloDelRotulo(tester, 'Reenviar email').fontFamily, 'Inter');
      await _cerrarApp(tester);
    });

    testWidgets('el relleno es el del canvas (#F3F1EA) y el rótulo, su gris (#5B6B82)', (
      tester,
    ) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 18);

      expect(_colorDelRelleno(tester), _rellenoDelCanvas);
      expect(ColoresColportaje.unica.rellenoSuave, _rellenoDelCanvas);
      expect(_estiloDelRotulo(tester, 'Reenviar en 42s').color, _textoDelCanvas);
      await _cerrarApp(tester);
    });

    testWidgets('el relleno avanza con cada segundo, sin saltos ni retrocesos, y el rótulo se lee '
        'a 4,5:1 sobre el relleno y sobre el fondo del botón en los 60 s', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      var anterior = -1.0;

      for (var s = 0; s < 60; s++) {
        if (s > 0) await reloj.pasar(tester, 1);
        expect(find.text('Reenviar en ${60 - s}s'), findsOneWidget);
        expect(_transcurrido(tester), closeTo(s / 60, 1e-9), reason: 'a los $s s');
        expect(_transcurrido(tester), greaterThan(anterior));
        anterior = _transcurrido(tester);
        final rotulo = _estiloDelRotulo(tester, 'Reenviar en ${60 - s}s').color!;
        expect(_contraste(rotulo, _colorDelRelleno(tester)), greaterThanOrEqualTo(4.5));
        expect(_contraste(rotulo, _fondoSinRellenar(tester)), greaterThanOrEqualTo(4.5));
      }
      expect(anterior, closeTo(59 / 60, 1e-9));
      await _cerrarApp(tester);
    });

    testWidgets('a los 60 s el relleno se va y «Reenviar email» vuelve a estar habilitado', (
      tester,
    ) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);

      await reloj.pasar(tester, 60);

      expect(find.text('Reenviar email'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(_relleno, findsNothing);
      await _cerrarApp(tester);
    });
  });

  group('12-A02 · reenviado con éxito', () {
    testWidgets(
      'dado el correo recién reenviado, el aviso de éxito se ve y el botón dice «Reenviar '
      'en 60s» sin relleno todavía',
      (tester) async {
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
        );

        await _tocarReenviar(tester);

        expect(_mensajeReenvio, findsOneWidget);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(_transcurrido(tester), 0);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await _cerrarApp(tester);
      },
    );
  });

  group('12-A01b · pendiente tras el alta', () {
    testWidgets('dado el correo del alta de hace 12 s, la espera cuenta desde ahí: «Reenviar en '
        '48s» y el 20 % relleno, sin el aviso «Te reenviamos el correo»', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        envioDelAlta: _base.subtract(const Duration(seconds: 12)),
      );

      expect(find.text('Reenviar en 48s'), findsOneWidget);
      expect(_transcurrido(tester), closeTo(0.2, 1e-9));
      expect(_estiloDelRotulo(tester, 'Reenviar en 48s').fontFamily, 'JetBrainsMono');
      expect(_mensajeReenvio, findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await _capturar(tester, 'a01b_390x844_x1.0');

      await reloj.pasar(tester, 48);
      expect(_habilitado(tester), isTrue);
      expect(_relleno, findsNothing);
      await _cerrarApp(tester);
    });
  });

  // 12-A04: el canvas dibuja el botón primario («Reenviar email de verificación») y no dibuja su cuenta
  // regresiva. Decisión del 16/10 (agente de decisiones, P1 de #335): queda la barra de 3 px, que
  // avanza con lo transcurrido como el relleno de A03, con el rótulo en JetBrains Mono y a 4,5:1
  // sobre el botón apagado.
  group('12-A04 · enlace expirado: la cuenta del botón primario', () {
    testWidgets(
      'dado el enlace expirado con el correo conocido, el botón primario sigue lleno y la '
      'cuenta va en la barra de 3 px, sin el relleno de A03',
      (tester) async {
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
          password: null,
          estado: EstadoVerificacionEmail.expirado,
        );
        expect(tester.widget(_boton), isA<FilledButton>());
        expect(find.text('Reenviar email de verificación'), findsOneWidget);
        expect(_barra, findsNothing);

        await _tocarReenviar(tester);
        await reloj.pasar(tester, 18);

        expect(find.text('Reenviar en 42s'), findsOneWidget);
        expect(_habilitado(tester), isFalse);
        expect(tester.widget<LinearProgressIndicator>(_barra).value, closeTo(0.3, 1e-9));
        expect(_relleno, findsNothing);

        await reloj.pasar(tester, 42);
        expect(find.text('Reenviar email de verificación'), findsOneWidget);
        expect(_habilitado(tester), isTrue);
        expect(_barra, findsNothing);
        await _cerrarApp(tester);
      },
    );

    testWidgets('sin el correo conocido (12-A04b), escrito el correo la cuenta también va en la '
        'barra y el campo sigue donde estaba', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), _lucia);
      await tester.pump();

      await _tocarReenviar(tester);
      await reloj.pasar(tester, 30);

      expect(find.text('Reenviar en 30s'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(_barra).value, closeTo(0.5, 1e-9));
      expect(_relleno, findsNothing);
      await _cerrarApp(tester);
    });

    testWidgets('la barra avanza con lo transcurrido, de 0 a 59/60, sin saltos ni retrocesos', (
      tester,
    ) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await _tocarReenviar(tester);
      var anterior = -1.0;

      for (var s = 0; s < 60; s++) {
        if (s > 0) await reloj.pasar(tester, 1);
        final valor = tester.widget<LinearProgressIndicator>(_barra).value!;
        expect(valor, closeTo(s / 60, 1e-9), reason: 'a los $s s');
        expect(valor, greaterThan(anterior));
        anterior = valor;
      }
      await _cerrarApp(tester);
    });

    testWidgets('el rótulo de la cuenta va en JetBrains Mono, de 60 s a 1 s, y fuera de ella en '
        'Inter', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      expect(_estiloDelRotulo(tester, 'Reenviar email de verificación').fontFamily, 'Inter');
      await _tocarReenviar(tester);

      for (var s = 0; s < 60; s++) {
        if (s > 0) await reloj.pasar(tester, 1);
        expect(
          _estiloDelRotulo(tester, 'Reenviar en ${60 - s}s').fontFamily,
          'JetBrainsMono',
          reason: 'a los $s s',
        );
      }
      await reloj.pasar(tester, 1);
      expect(_estiloDelRotulo(tester, 'Reenviar email de verificación').fontFamily, 'Inter');
      await _cerrarApp(tester);
    });

    for (final correoConocido in [true, false]) {
      final artboard = correoConocido ? '12-A04' : '12-A04b';
      testWidgets('el rótulo apagado de $artboard llega a 4,5:1 sobre el botón, a lo largo de la '
          'cuenta', (tester) async {
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
          email: correoConocido ? _lucia : '',
          password: null,
          estado: EstadoVerificacionEmail.expirado,
        );
        if (!correoConocido) {
          await tester.enterText(find.byKey(const Key('verificacion_email_campo')), _lucia);
          await tester.pump();
        }
        await _tocarReenviar(tester);

        for (var s = 0; s < 60; s += 15) {
          if (s > 0) await reloj.pasar(tester, 15);
          final rotulo = _estiloDelRotulo(tester, 'Reenviar en ${60 - s}s').color!;
          final fondo = tester.widget<Material>(_visual).color!;
          expect(fondo.a, 1, reason: 'opaco: el contraste no depende de lo que haya debajo');
          expect(_contraste(rotulo, fondo), greaterThanOrEqualTo(4.5), reason: 'a los $s s');
        }
        await _cerrarApp(tester);
      });
    }

    testWidgets('el botón sigue viéndose apagado: no es el azul del botón activo', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      final activo = tester.widget<Material>(_visual).color!;
      await _tocarReenviar(tester);

      final apagado = tester.widget<Material>(_visual).color!;
      expect(apagado, isNot(activo));
      expect(apagado, ColoresColportaje.unica.gris);
      await _capturar(tester, 'a04_390x844_x1.0');
      await _cerrarApp(tester);
    });

    testWidgets('a 360×640 con el texto al doble la cuenta entra en el botón primario sin '
        'desbordar', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
        tam: const Size(360, 640),
        escala: 2,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 18);

      expect(tester.takeException(), isNull);
      final boton = tester.getRect(_visual);
      final rotulo = tester.getRect(find.text('Reenviar en 42s'));
      expect(rotulo.left, greaterThanOrEqualTo(boton.left));
      expect(rotulo.right, lessThanOrEqualTo(boton.right));
      expect(boton.right, lessThanOrEqualTo(360));
      await _capturar(tester, 'a04_360x640_x2.0');
      await _cerrarApp(tester);
    });
  });

  group('12-A06 · límite de reenvíos', () {
    testWidgets('con el candado puesto el botón no lleva relleno, barra ni la letra de la cuenta: '
        'sigue con su candado y el rótulo de siempre', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({
          _lucia: _base.add(const Duration(minutes: 30)),
        }),
        ahora: reloj.leer,
      );

      expect(find.byKey(const Key('verificacion_email_limite')), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      expect(_relleno, findsNothing);
      expect(_barra, findsNothing);
      expect(_estiloDelRotulo(tester, 'Reenviar email').fontFamily, 'Inter');
      await _cerrarApp(tester);
    });
  });

  group('casos límite de la cuenta regresiva', () {
    testWidgets(
      'doble toque en «Reenviar email»: sale un solo correo y la cuenta arranca de cero',
      (tester) async {
        final remoto = _remotoSano()..demoraReenvio = Completer<void>();
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: remoto,
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
        );
        await tester.ensureVisible(_boton);

        await tester.tap(_boton);
        await tester.pump();
        // Con el reenvío en vuelo el botón está apagado, pero todavía no hay cuenta ni relleno.
        expect(_habilitado(tester), isFalse);
        expect(_relleno, findsNothing);
        expect(find.text('Reenviar email'), findsOneWidget);
        await tester.tap(_boton, warnIfMissed: false);
        await tester.pump();
        remoto.demoraReenvio!.complete();
        await tester.pumpAndSettle();

        expect(remoto.reenviosPorEmail[_lucia], 1);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(_transcurrido(tester), 0);
        await _cerrarApp(tester);
      },
    );

    testWidgets('tocar el botón con la cuenta corriendo no manda otro correo ni toca el relleno', (
      tester,
    ) async {
      final remoto = _remotoSano();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: remoto,
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 30);

      await tester.tap(_boton, warnIfMissed: false);
      await tester.pump();

      expect(remoto.reenviosPorEmail[_lucia], 1);
      expect(find.text('Reenviar en 30s'), findsOneWidget);
      expect(_transcurrido(tester), closeTo(0.5, 1e-9));
      await _cerrarApp(tester);
    });

    testWidgets('el reenvío falla (A08 sin conexión): sin relleno, el botón vuelve habilitado y '
        'reintentar arranca la cuenta', (tester) async {
      final remoto = _remotoSano()..simularSinConexion = true;
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: remoto,
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );

      await _tocarReenviar(tester);

      expect(find.text('Reenviar email'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(_relleno, findsNothing);
      remoto.simularSinConexion = false;
      await _tocarReenviar(tester);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(_transcurrido(tester), 0);
      await _cerrarApp(tester);
    });

    testWidgets('volver atrás y reentrar con la cuenta a medias retoma el relleno desde la hora '
        'guardada', (tester) async {
      final bloqueos = BloqueoReenvioVerificacionEnMemoria();
      final reloj = _Reloj(_base);
      await _montar(tester, remote: _remotoSano(), bloqueos: bloqueos, ahora: reloj.leer);
      await _tocarReenviar(tester);
      await _cerrarApp(tester);
      reloj.ahora = _base.add(const Duration(seconds: 20));

      await _montar(tester, remote: _remotoSano(), bloqueos: bloqueos, ahora: reloj.leer);

      expect(find.text('Reenviar en 40s'), findsOneWidget);
      expect(_transcurrido(tester), closeTo(1 / 3, 1e-9));
      await _cerrarApp(tester);
    });

    testWidgets('dos reenvíos seguidos: el relleno de la segunda cuenta vuelve a empezar de cero', (
      tester,
    ) async {
      final remoto = _remotoSano();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: remoto,
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 60);

      await _tocarReenviar(tester);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(_transcurrido(tester), 0);
      await reloj.pasar(tester, 10);

      expect(remoto.reenviosPorEmail[_lucia], 2);
      expect(find.text('Reenviar en 50s'), findsOneWidget);
      expect(_transcurrido(tester), closeTo(1 / 6, 1e-9));
      await _cerrarApp(tester);
    });

    testWidgets(
      'al volver de segundo plano con 30 s de reloj de más, el relleno sigue la hora real',
      (tester) async {
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
        );
        await _tocarReenviar(tester);
        await reloj.pasar(tester, 10);

        // Los `Timer` estuvieron pausados: la hora avanzó y la cuenta no.
        reloj.ahora = reloj.ahora.add(const Duration(seconds: 30));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump();

        expect(find.text('Reenviar en 20s'), findsOneWidget);
        expect(_transcurrido(tester), closeTo(40 / 60, 1e-9));
        await _cerrarApp(tester);
      },
    );
  });

  group('medidas con la letra real', () {
    for (final (tam, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(390, 844), 1.0),
      (const Size(412, 915), 2.0),
    ]) {
      final medida = '${tam.width.toInt()}×${tam.height.toInt()} y texto ×$escala';

      testWidgets('A03 a $medida: el rótulo cabe entero en una línea dentro del botón y el relleno '
          'queda por dentro del borde', (tester) async {
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
          tam: tam,
          escala: escala,
        );
        await _tocarReenviar(tester);
        await reloj.pasar(tester, 18);

        expect(tester.takeException(), isNull);
        final boton = tester.getRect(_visual);
        final rotulo = tester.getRect(find.text('Reenviar en 42s'));
        final relleno = tester.getRect(_relleno);
        expect(boton.left, greaterThanOrEqualTo(0));
        expect(boton.right, lessThanOrEqualTo(tam.width));
        expect(rotulo.left, greaterThanOrEqualTo(boton.left));
        expect(rotulo.right, lessThanOrEqualTo(boton.right));
        expect(rotulo.top, greaterThanOrEqualTo(boton.top));
        expect(rotulo.bottom, lessThanOrEqualTo(boton.bottom));
        expect(rotulo.height, lessThan(14.5 * escala * 1.6), reason: 'una sola línea');
        expect(relleno.left, closeTo(boton.left + 1.5, 0.01));
        expect(relleno.top, closeTo(boton.top + 1.5, 0.01));
        expect(relleno.bottom, closeTo(boton.bottom - 1.5, 0.01));
        expect(relleno.width, closeTo((boton.width - 3) * 0.3, 0.01));
        await _capturar(tester, 'a03_${tam.width.toInt()}x${tam.height.toInt()}_x$escala');
        await _cerrarApp(tester);
      });
    }

    testWidgets('con el texto normal la forma es píldora, antes, durante y después de la cuenta, y '
        'el recorte del relleno la sigue', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      expect(_forma(tester), 'píldora');

      await _tocarReenviar(tester);
      expect(_forma(tester), 'píldora');
      await reloj.pasar(tester, 18);
      expect(_forma(tester), 'píldora');
      _recorteSigueLaForma(
        tester,
        radio:
            tester.getSize(find.descendant(of: _boton, matching: find.byType(ClipPath))).height / 2,
      );
      await _capturar(tester, 'a03_390x844_x1.0_pantalla');

      await reloj.pasar(tester, 42);
      expect(_forma(tester), 'píldora');
      await _cerrarApp(tester);
    });

    testWidgets('con el texto al doble la forma es la de «Ya verifiqué mi email» (radio 16) antes, '
        'durante y después de la cuenta, y el recorte del relleno la sigue', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        tam: const Size(360, 640),
        escala: 2,
      );
      final radio16 = BorderRadius.circular(16);
      final yaVerifique = find.descendant(
        of: find.byKey(const Key('verificacion_email_ya_verifique')),
        matching: find.byType(Material),
      );
      expect(tester.widget<Material>(yaVerifique.first).shape, isA<RoundedRectangleBorder>());
      expect(
        (tester.widget<Material>(yaVerifique.first).shape! as RoundedRectangleBorder).borderRadius,
        radio16,
      );
      expect(_forma(tester), radio16);

      await _tocarReenviar(tester);
      expect(_forma(tester), radio16);
      await reloj.pasar(tester, 18);
      expect(_forma(tester), radio16);
      _recorteSigueLaForma(tester, radio: 14.5);

      await reloj.pasar(tester, 42);
      expect(_forma(tester), radio16, reason: 'no vuelve a píldora al terminar la espera');
      await _cerrarApp(tester);
    });

    for (final (escala, tam, radio) in [
      (1.0, const Size(390, 844), 'píldora'),
      (2.0, const Size(360, 640), BorderRadius.circular(16)),
    ]) {
      testWidgets('con el candado puesto (12-A06) la forma es la misma que sin él, a ×$escala', (
        tester,
      ) async {
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria({
            _lucia: _base.add(const Duration(minutes: 30)),
          }),
          ahora: reloj.leer,
          tam: tam,
          escala: escala,
        );

        expect(_forma(tester), radio);
        await _cerrarApp(tester);
      });
    }

    testWidgets('el botón apagado no tiene fondo propio: lo que no se rellenó es el crema de la '
        'pantalla, como el canvas', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);

      for (final s in [0, 18, 59]) {
        if (s > 0) await reloj.pasar(tester, s == 18 ? 18 : 41);
        final propio = tester.widget<Material>(_visual).color;
        expect(propio == null || propio.a == 0, isTrue, reason: 'a los $s s: $propio');
        expect(_fondoSinRellenar(tester), Theme.of(tester.element(_boton)).scaffoldBackgroundColor);
      }
      await _cerrarApp(tester);
    });
  });

  // Decisión del 16/10 (pendiente de la QA de #335, P1 §2): un solo anuncio al lector de pantalla
  // cuando la cuenta llega a cero y el botón vuelve a poder tocarse (AA 4.1.3); nada al empezar ni
  // segundo a segundo, y nada si el botón sigue bloqueado.
  group('el anuncio único al terminar la cuenta', () {
    const aviso = 'Ya podés reenviar el email.';

    List<String> anuncios(WidgetTester tester) =>
        tester.takeAnnouncements().map((a) => a.message).toList();

    testWidgets('12-A03: «Ya podés reenviar el email.» una sola vez, en el segundo 60, y ninguno '
        'antes ni después', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      anuncios(tester);

      for (var s = 1; s < 60; s++) {
        await reloj.pasar(tester, 1);
        expect(anuncios(tester), isEmpty, reason: 'a los $s s todavía corre la cuenta');
      }
      await reloj.pasar(tester, 1);
      expect(anuncios(tester), [aviso]);
      expect(_habilitado(tester), isTrue);

      await reloj.pasar(tester, 90);
      expect(anuncios(tester), isEmpty, reason: 'una sola vez');
      semantica.dispose();
      await _cerrarApp(tester);
    });

    testWidgets('12-A01b: con la espera que viene del alta, el anuncio llega a los 48 s y no al '
        'entrar', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        envioDelAlta: _base.subtract(const Duration(seconds: 12)),
      );
      expect(anuncios(tester), isEmpty, reason: 'al entrar con la cuenta corriendo no se anuncia');

      await reloj.pasar(tester, 47);
      expect(anuncios(tester), isEmpty);
      await reloj.pasar(tester, 1);
      expect(anuncios(tester), [aviso]);
      semantica.dispose();
      await _cerrarApp(tester);
    });

    for (final correoConocido in [true, false]) {
      final artboard = correoConocido ? '12-A04' : '12-A04b';
      testWidgets('$artboard: el botón primario también lo anuncia, una sola vez', (tester) async {
        final semantica = tester.ensureSemantics();
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
          email: correoConocido ? _lucia : '',
          password: null,
          estado: EstadoVerificacionEmail.expirado,
        );
        if (!correoConocido) {
          await tester.enterText(find.byKey(const Key('verificacion_email_campo')), _lucia);
          await tester.pump();
        }
        await _tocarReenviar(tester);
        anuncios(tester);

        await reloj.pasar(tester, 59);
        expect(anuncios(tester), isEmpty);
        await reloj.pasar(tester, 1);
        expect(anuncios(tester), [aviso]);
        await reloj.pasar(tester, 60);
        expect(anuncios(tester), isEmpty);
        semantica.dispose();
        await _cerrarApp(tester);
      });
    }

    testWidgets('con el candado del límite puesto no se anuncia: el botón sigue bloqueado', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({
          _lucia: _base.add(const Duration(minutes: 30)),
        }),
        ahora: reloj.leer,
        envioDelAlta: _base,
      );
      await tester.pumpAndSettle();
      expect(anuncios(tester), [
        'Demasiados intentos. Probá nuevamente en 30 minutos.',
      ], reason: 'el aviso del límite sí se anuncia, una vez, al entrar');

      await reloj.pasar(tester, 60);

      expect(_habilitado(tester), isFalse);
      expect(anuncios(tester), isEmpty);
      semantica.dispose();
      await _cerrarApp(tester);
    });

    testWidgets('con la pantalla ya verificada (cierre) no se anuncia: no hay botón de reenviar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 10);
      await tester.tap(find.byKey(const Key('verificacion_email_ya_verifique')));
      await tester.pumpAndSettle();
      expect(find.text('Email verificado'), findsOneWidget);
      anuncios(tester);

      await reloj.pasar(tester, 60);

      expect(anuncios(tester), isEmpty);
      expect(_boton, findsNothing);
      semantica.dispose();
      await _cerrarApp(tester);
    });

    testWidgets(
      'mientras se verifica («Ya verifiqué mi email» en curso) el botón sigue apagado y no '
      'se anuncia',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final remoto = _remotoSano()..demoraIniciarSesion = Completer<void>();
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: remoto,
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
        );
        await _tocarReenviar(tester);
        await tester.tap(find.byKey(const Key('verificacion_email_ya_verifique')));
        await tester.pump();
        anuncios(tester);

        await reloj.pasar(tester, 60);

        expect(_habilitado(tester), isFalse, reason: 'ocupado: verificando');
        expect(anuncios(tester), isEmpty);
        remoto.demoraIniciarSesion!.complete();
        await tester.pumpAndSettle();
        semantica.dispose();
        await _cerrarApp(tester);
      },
    );

    testWidgets('cerrada la pantalla antes del final, no se anuncia nada ni falla', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 30);
      anuncios(tester);

      await _cerrarApp(tester);
      await reloj.pasar(tester, 60);

      expect(anuncios(tester), isEmpty);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    testWidgets('cambiar la dirección con la cuenta corriendo no anuncia: no es el final de la '
        'cuenta', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), _lucia);
      await tester.pump();
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 20);
      anuncios(tester);

      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), 'otra@correo.com');
      await tester.pump();
      expect(_habilitado(tester), isTrue, reason: 'la espera era de la otra dirección');
      await reloj.pasar(tester, 60);

      expect(anuncios(tester), isEmpty);
      semantica.dispose();
      await _cerrarApp(tester);
    });

    testWidgets('dos cuentas seguidas: un anuncio al final de cada una', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      await reloj.pasar(tester, 60);
      expect(anuncios(tester), [aviso]);

      await _tocarReenviar(tester);
      expect(anuncios(tester), isEmpty, reason: 'al empezar la segunda tampoco');
      await reloj.pasar(tester, 59);
      expect(anuncios(tester), isEmpty);
      await reloj.pasar(tester, 1);
      expect(anuncios(tester), [aviso]);
      semantica.dispose();
      await _cerrarApp(tester);
    });
  });

  group('la cuenta regresiva y la accesibilidad', () {
    testWidgets('el relleno no entra en el árbol de accesibilidad: el botón se lee apagado con su '
        'cuenta y no se anuncia nada segundo a segundo', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await _tocarReenviar(tester);
      tester.takeAnnouncements();

      for (var s = 1; s < 60; s++) {
        await reloj.pasar(tester, 1);
        if (s % 15 == 0) {
          expect(
            tester.getSemantics(_boton),
            isSemantics(
              isButton: true,
              hasEnabledState: true,
              isEnabled: false,
              isLiveRegion: false,
              label: 'Reenviar en ${60 - s}s',
            ),
          );
        }
      }

      expect(tester.takeAnnouncements(), isEmpty, reason: 'ni un anuncio en toda la cuenta');
      expect(
        find.semantics.byLabel(RegExp('%|progress|avance', caseSensitive: false)),
        findsNothing,
        reason: 'el relleno es decorativo: la cuenta ya está en el botón',
      );
      semantica.dispose();
      await _cerrarApp(tester);
    });

    for (final (tam, escala) in [(const Size(390, 844), 1.0), (const Size(360, 640), 2.0)]) {
      testWidgets('con la cuenta corriendo a ${tam.width.toInt()}×${tam.height.toInt()} y texto '
          '×$escala: toque de 48 dp, etiquetas y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
          tam: tam,
          escala: escala,
        );
        await _tocarReenviar(tester);
        await reloj.pasar(tester, 18);
        expect(tester.takeException(), isNull);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expect(tester.getRect(_visual).height, greaterThanOrEqualTo(40));
        semantica.dispose();
        await _cerrarApp(tester);
      });
    }
  });
}
