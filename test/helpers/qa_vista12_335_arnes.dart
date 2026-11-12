// Arnés de la QA de #335 (vista 12 «Verificá tu cuenta», la cuenta regresiva «Reenviar en Ns» como
// relleno del botón): monta la pantalla con las fuentes reales del proyecto, un reloj que el test
// mueve a mano y cada estado del canvas (A01 a A08, más A01b y las variantes de A04), y lee píxeles de
// lo que se pinta de verdad.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

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

import 'acceso_qa_arnes.dart' show fijarPantalla;
import 'db_local_repository_en_memoria.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

const lucia = 'lucia.silva@correo.com';
final base = DateTime(2026, 10, 16, 14, 35);

/// Los colores del canvas (`12 Verificacion Email.dc.html`).
const rellenoDelCanvas = Color(0xFFF3F1EA);
const grisDelCanvas = Color(0xFF5B6B82);
const cremaDelCanvas = Color(0xFFFAFAF7);
const bordeDelBotonApagado = Color(0xFFE3E7EE);
const navyDelCanvas = Color(0xFF002856);

/// Los teléfonos de la matriz: el más chico, el del diseño, el de 740 y el grande.
const tamanos = [Size(320, 568), Size(360, 640), Size(360, 740), Size(390, 844), Size(412, 915)];
const escalas = [1.0, 2.0];

/// Cada artboard del canvas 12 (y las variantes de la HU que no tienen artboard).
enum Estado12 {
  a01('A01 pendiente'),
  a01b('A01b pendiente tras el alta'),
  a02('A02 reenviado con éxito'),
  a03('A03 cuenta regresiva activa'),
  a04('A04 enlace expirado'),
  a04Cuenta('A04 expirado con la cuenta corriendo'),
  a04b('A04b expirado sin correo conocido'),
  a04bCuenta('A04b sin correo conocido con la cuenta corriendo'),
  a05('A05 ya verificado'),
  a06('A06 límite de reenvíos'),
  a07('A07 verificado'),
  a08('A08 sin conexión al reenviar'),
  inutil('enlace inútil (HU caso 3)'),
  inutilCuenta('enlace inútil con la cuenta corriendo');

  const Estado12(this.rotulo);

  final String rotulo;

  String get id => name;
}

final llave = GlobalKey();
final boton = find.byKey(const Key('verificacion_email_reenviar'));
final relleno = find.byKey(const Key('verificacion_email_progreso'));
final barra = find.byKey(const Key('verificacion_email_barra'));
final mensajeReenvio = find.byKey(const Key('verificacion_email_mensaje_reenvio'));
final avisoLimite = find.byKey(const Key('verificacion_email_limite'));
final errorGeneral = find.byKey(const Key('verificacion_email_error_general'));
final campo = find.byKey(const Key('verificacion_email_campo'));
final yaVerifique = find.byKey(const Key('verificacion_email_ya_verifique'));
final volverLogin = find.byKey(const Key('verificacion_email_volver_login'));

bool _fuentesCargadas = false;

/// `false` solo para la guía de contraste de Flutter: lee los colores del texto de la captura y con
/// las fuentes reales (trazos de 1 px, suavizados) da falsos negativos; con las cajas de Ahem lee el
/// color de verdad.
bool usarFuentesReales = true;

/// Sin las fuentes del proyecto `flutter_test` pinta cajas (Ahem) y las medidas no son las reales.
Future<void> cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales) return;
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

/// Reloj que el test mueve a mano: [pasar] hace correr los `Timer` de la pantalla de a 1 s, y
/// asignar [ahora] sin pasar es saltar la hora del teléfono (o volver de segundo plano).
final class Reloj {
  Reloj([DateTime? ahora]) : ahora = ahora ?? base;

  DateTime ahora;

  DateTime leer() => ahora;

  Future<void> pasar(WidgetTester tester, int segundos) async {
    for (var i = 0; i < segundos; i++) {
      ahora = ahora.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

/// La pantalla ya montada: el reloj, el remoto, los bloqueos y la escala viva del texto.
final class Escenario {
  Escenario({
    required this.reloj,
    required this.remoto,
    required this.bloqueos,
    required this.escala,
    required this.tam,
  });

  final Reloj reloj;
  final AuthRemoteDataSourceEnMemoria remoto;
  final BloqueoReenvioVerificacionRepository bloqueos;
  final ValueNotifier<double> escala;
  final Size tam;
}

AuthRemoteDataSourceEnMemoria remotoSano() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {lucia: 'Secreto123'});

/// Monta [VerificacionEmailPage] aislada. Devuelve el escenario para seguir manejándolo.
Future<Escenario> montar(
  WidgetTester tester, {
  Reloj? reloj,
  AuthRemoteDataSourceEnMemoria? remoto,
  BloqueoReenvioVerificacionRepository? bloqueos,
  String email = lucia,
  String? password = 'Secreto123',
  EstadoVerificacionEmail estado = EstadoVerificacionEmail.pendiente,
  DateTime? envioDelAlta,
  double escala = 1,
  Size tam = const Size(390, 844),
  double teclado = 0,
}) async {
  await cargarFuentes(tester);
  fijarPantalla(tester, tam, teclado: teclado);
  final esc = Escenario(
    reloj: reloj ?? Reloj(),
    remoto: remoto ?? remotoSano(),
    bloqueos: bloqueos ?? BloqueoReenvioVerificacionEnMemoria(),
    escala: ValueNotifier(escala),
    tam: tam,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(esc.remoto),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(esc.bloqueos),
      ],
      child: RepaintBoundary(
        key: llave,
        child: ValueListenableBuilder<double>(
          valueListenable: esc.escala,
          builder: (context, valor, _) => MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(valor)),
              child: child!,
            ),
            home: VerificacionEmailPage(
              email: email,
              password: password,
              estadoInicial: estado,
              envioDelAlta: envioDelAlta,
              ahora: esc.reloj.leer,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return esc;
}

/// Saca la pantalla del árbol (como cerrar la app) para que no quede ningún `Timer` vivo.
Future<void> cerrarApp(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> tocarReenviar(WidgetTester tester) async {
  await tester.ensureVisible(boton);
  await tester.tap(boton, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Lleva la pantalla al estado [e] del canvas, a tamaño [tam] y texto [escala]. Con la cuenta
/// corriendo deja pasar [segundos] después del reenvío.
Future<Escenario> llegarA(
  WidgetTester tester,
  Estado12 e, {
  Size tam = const Size(390, 844),
  double escala = 1,
  int segundos = 18,
  double teclado = 0,
}) async {
  final reloj = Reloj();
  switch (e) {
    case Estado12.a01:
      return montar(tester, reloj: reloj, tam: tam, escala: escala, teclado: teclado);
    case Estado12.a01b:
      return montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        envioDelAlta: base.subtract(const Duration(seconds: 12)),
      );
    case Estado12.a02:
      final esc = await montar(tester, reloj: reloj, tam: tam, escala: escala, teclado: teclado);
      await tocarReenviar(tester);
      return esc;
    case Estado12.a03:
      final esc = await montar(tester, reloj: reloj, tam: tam, escala: escala, teclado: teclado);
      await tocarReenviar(tester);
      await reloj.pasar(tester, segundos);
      return esc;
    case Estado12.a04:
    case Estado12.a04Cuenta:
      final esc = await montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      if (e == Estado12.a04Cuenta) {
        await tocarReenviar(tester);
        await reloj.pasar(tester, segundos);
      }
      return esc;
    case Estado12.a04b:
    case Estado12.a04bCuenta:
      final esc = await montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.enterText(campo, lucia);
      await tester.pump();
      if (e == Estado12.a04bCuenta) {
        await tocarReenviar(tester);
        await reloj.pasar(tester, segundos);
      }
      return esc;
    case Estado12.a05:
      return montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.yaVerificado,
      );
    case Estado12.a06:
      return montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        bloqueos: BloqueoReenvioVerificacionEnMemoria({
          lucia: base.add(const Duration(minutes: 4)),
        }),
      );
    case Estado12.a07:
      return montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        estado: EstadoVerificacionEmail.verificado,
      );
    case Estado12.a08:
      final esc = await montar(
        tester,
        reloj: reloj,
        remoto: remotoSano()..simularSinConexion = true,
        tam: tam,
        escala: escala,
        teclado: teclado,
      );
      await tocarReenviar(tester);
      return esc;
    case Estado12.inutil:
    case Estado12.inutilCuenta:
      final esc = await montar(
        tester,
        reloj: reloj,
        tam: tam,
        escala: escala,
        teclado: teclado,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.enlaceInutil,
      );
      if (e == Estado12.inutilCuenta) {
        await tester.enterText(campo, lucia);
        await tester.pump();
        await tocarReenviar(tester);
        await reloj.pasar(tester, segundos);
      }
      return esc;
  }
}

bool habilitado(WidgetTester tester) => tester.widget<ButtonStyleButton>(boton).onPressed != null;

/// Cuánto del botón está relleno: lo transcurrido de los 60 s, de 0 a 1.
double transcurrido(WidgetTester tester) =>
    tester.widget<FractionallySizedBox>(relleno).widthFactor!;

/// El botón tal como se ve (sin el margen de toque que le suma Material).
Finder get botonVisual => find.descendant(of: boton, matching: find.byType(Material)).first;

TextStyle estiloDelRotulo(WidgetTester tester, String texto) => tester
    .widget<RichText>(find.descendant(of: find.text(texto), matching: find.byType(RichText)))
    .text
    .style!;

double contraste(Color a, Color b) {
  final claro = a.computeLuminance() > b.computeLuminance() ? a : b;
  final oscuro = identical(claro, a) ? b : a;
  return (claro.computeLuminance() + 0.05) / (oscuro.computeLuminance() + 0.05);
}

/// Los píxeles de la pantalla tal como se pintan (1 px lógico = 1 px).
final class Pixeles {
  Pixeles(this.ancho, this.alto, this._datos);

  final int ancho;
  final int alto;
  final ByteData _datos;

  Color en(double x, double y) {
    final px = x.floor().clamp(0, ancho - 1);
    final py = y.floor().clamp(0, alto - 1);
    final i = (py * ancho + px) * 4;
    return Color.fromARGB(
      _datos.getUint8(i + 3),
      _datos.getUint8(i),
      _datos.getUint8(i + 1),
      _datos.getUint8(i + 2),
    );
  }
}

Future<Pixeles> leerPixeles(WidgetTester tester) async {
  final p = await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(llave));
    final img = await render.toImage();
    final datos = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return Pixeles(img.width, img.height, datos);
  });
  return p!;
}

bool mismoColor(Color a, Color b, {int tolerancia = 2}) {
  int c(double v) => (v * 255).round();
  return (c(a.r) - c(b.r)).abs() <= tolerancia &&
      (c(a.g) - c(b.g)).abs() <= tolerancia &&
      (c(a.b) - c(b.b)).abs() <= tolerancia;
}

String hex(Color c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
}

/// La pantalla completa como PNG, solo con `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(llave));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa335_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos. El campo
/// del correo no cuenta: es de una sola línea y se desplaza (su pista de ejemplo se acorta, y no es
/// información).
void sinTextoCortado(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// El texto de [boton] cabe entero dentro del botón (sin tocar el borde ni salirse).
void rotuloDentroDelBoton(WidgetTester tester, String texto) {
  final b = tester.getRect(botonVisual);
  final r = tester.getRect(find.text(texto));
  expect(r.left, greaterThanOrEqualTo(b.left), reason: '«$texto» se sale por la izquierda');
  expect(r.right, lessThanOrEqualTo(b.right), reason: '«$texto» se sale por la derecha');
  expect(r.top, greaterThanOrEqualTo(b.top), reason: '«$texto» se sale por arriba');
  expect(r.bottom, lessThanOrEqualTo(b.bottom), reason: '«$texto» se sale por abajo');
}

/// Vuelve de segundo plano: los `Timer` estuvieron pausados y la hora pudo cambiar.
Future<void> irAlFondoYVolver(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await tester.pump();
}
