// Arnés del QA de «Cobro con tarjeta y por transferencia» (vista 29, HU-COB-002 y HU-COB-003, #164):
// lleva la pantalla a cada artboard del canvas (29A·01, 29A·02, 29A·04, 29A·05, 29B·01 a 29B·04) y a los
// estados que el canvas no dibuja, en cualquier tamaño y con cualquier escala de texto. Las capturas
// solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas` (fuera de git).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show asentarAgendar;
import 'cobro_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico164 = Size(360, 640);
const grande164 = Size(412, 915);

String sufijo164(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

/// Cada estado al que se puede llegar. `aNN` y `bNN` son los artboards del canvas; el resto, los que
/// el canvas no dibuja.
enum Estado164 {
  a01Tarjeta('29A·01 Cobro con tarjeta'),
  a01Otra('29A·01 con «Otra» marca escrita'),
  a02Registrada('29A·02 Tarjeta registrada (V1), venta pagada'),
  a02Parcial('29A·02 Tarjeta registrada, con saldo'),
  a04Mayor('29A·04 Monto mayor al saldo'),
  a05Error('29A·05 Error al guardar'),
  b01Transferencia('29B·01 Cobro por transferencia'),
  b01ConBanco('29B·01 con banco y referencia'),
  b02Banco('29B·02 Banco de origen'),
  b02Otro('29B·02 Banco de origen con «Otro» escrito'),
  b03Registrada('29B·03 Transferencia registrada'),
  b03Parcial('29B·03 Transferencia registrada, con saldo'),
  b04SinConexion('29B·04 Sin conexión (registra igual)'),
  registrando('Registrando con tarjeta'),
  errorTransferencia('Error al guardar con transferencia'),
  cargando('Cargando la venta'),
  ausente('La venta ya no está'),
  errorLectura('Error de lectura'),
  sinSaldo('Venta sin saldo al abrir'),
  descartar('Aviso «¿Descartar lo que escribiste?» con datos del medio');

  const Estado164(this.rotulo);
  final String rotulo;
}

Finder medio164(int i) => find.byKey(Key('cobro_medio_$i'));
final tarjeta164 = medio164(1);
final transferencia164 = medio164(2);
Finder campo164(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));
final banco164 = find.byKey(const Key('cobro_banco'));
Finder bancoDeLaHoja164(String b) => find.byKey(Key('cobro_banco_$b'));
final bancoListo164 = find.byKey(const Key('cobro_banco_listo'));
final listo164 = find.byKey(const Key('cobro_listo'));

Future<void> escribir164(WidgetTester tester, String clave, String texto) async {
  await traerAlAlcance(tester, campo164(clave));
  await tester.enterText(campo164(clave), texto);
  await asentarAgendar(tester, 3);
}

/// Escribe el monto y deja terminar la animación del botón (de apagado a encendido tarda 200 ms).
Future<void> escribirMonto164(WidgetTester tester, String texto) async {
  await escribirMonto(tester, texto);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Elige el medio con el segmento [medio] y escribe el monto.
Future<void> preparar164(WidgetTester tester, Finder medio, String monto) async {
  await tocarCobro(tester, medio);
  await escribirMonto164(tester, monto);
}

Future<void> registrar164(WidgetTester tester) => tocarCobro(tester, botonRegistrar);

/// Lleva la pantalla a [estado].
Future<ArnesCobro> llegarA164(
  WidgetTester tester,
  Estado164 estado, {
  Size tamano = chico164,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  Future<ArnesCobro> montar({CobranzasEnMemoria? repo, String ventaId = 'v-42'}) =>
      montarCobro(tester, repo: repo, ventaId: ventaId, escala: escala, tamano: tamano);

  switch (estado) {
    case Estado164.a01Tarjeta:
      final a = await montar();
      await preparar164(tester, tarjeta164, '800');
      return a;
    case Estado164.a01Otra:
      final a = await montar();
      await preparar164(tester, tarjeta164, '800');
      await tocarCobro(tester, find.byKey(const Key('cobro_marca_Otra')));
      await escribir164(tester, 'cobro_marca_otra', 'Maestro');
      await escribir164(tester, 'cobro_aprobacion', '004471');
      return a;
    case Estado164.a02Registrada:
      final a = await montar();
      await preparar164(tester, tarjeta164, '1200');
      await registrar164(tester);
      return a;
    case Estado164.a02Parcial:
      final a = await montar();
      await preparar164(tester, tarjeta164, '800');
      await registrar164(tester);
      return a;
    case Estado164.a04Mayor:
      final a = await montar();
      await preparar164(tester, tarjeta164, r'$ 1.500');
      return a;
    case Estado164.a05Error:
      final repo = CobranzasEnMemoria()..fallas.add(const FailureCobroNoGuardado());
      final a = await montar(repo: repo);
      await preparar164(tester, tarjeta164, '800');
      await registrar164(tester);
      return a;
    case Estado164.b01Transferencia:
      final a = await montar();
      await preparar164(tester, transferencia164, '800');
      return a;
    case Estado164.b01ConBanco:
      final a = await montar();
      await preparar164(tester, transferencia164, '800');
      await escribir164(tester, 'cobro_referencia', 'TX-12345');
      await tocarCobro(tester, banco164);
      await tocarCobro(tester, bancoDeLaHoja164('Itaú'));
      await tocarCobro(tester, bancoListo164);
      return a;
    case Estado164.b02Banco:
      final a = await montar();
      await preparar164(tester, transferencia164, '800');
      await tocarCobro(tester, banco164);
      return a;
    case Estado164.b02Otro:
      final a = await montar();
      await preparar164(tester, transferencia164, '800');
      await tocarCobro(tester, banco164);
      await tocarCobro(tester, bancoDeLaHoja164('Otro'));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('cobro_banco_otro')),
          matching: find.byType(TextField),
        ),
        'Banco Heritage',
      );
      await asentarAgendar(tester, 3);
      return a;
    case Estado164.b03Registrada:
      final a = await montar();
      await preparar164(tester, transferencia164, '1200');
      await escribir164(tester, 'cobro_referencia', '88213');
      await registrar164(tester);
      return a;
    case Estado164.b03Parcial:
      final a = await montar();
      await preparar164(tester, transferencia164, '500');
      await escribir164(tester, 'cobro_referencia', 'TX-12345');
      await registrar164(tester);
      return a;
    case Estado164.b04SinConexion:
      // El canvas no dibuja un estado propio: todo es local y sube después. Sin conexión se registra
      // igual y la pantalla es la de la transferencia registrada.
      final a = await montar();
      await preparar164(tester, transferencia164, '1200');
      await registrar164(tester);
      return a;
    case Estado164.registrando:
      final repo = CobranzasEnMemoria()..compuerta = Completer<void>();
      final a = await montar(repo: repo);
      await preparar164(tester, tarjeta164, '800');
      await registrar164(tester);
      return a;
    case Estado164.errorTransferencia:
      final repo = CobranzasEnMemoria()..fallas.add(const FailureCobroNoGuardado());
      final a = await montar(repo: repo);
      await preparar164(tester, transferencia164, '800');
      await escribir164(tester, 'cobro_referencia', 'TX-12345');
      await registrar164(tester);
      return a;
    case Estado164.cargando:
      final repo = CobranzasEnMemoria()..compuertaDeLectura = Completer<void>();
      return montar(repo: repo);
    case Estado164.ausente:
      return montar(ventaId: 'no-existe');
    case Estado164.errorLectura:
      final repo = CobranzasEnMemoria()..fallaDeLectura = const FailureInesperado();
      return montar(repo: repo);
    case Estado164.sinSaldo:
      return montar(repo: CobranzasEnMemoria(cobradoAntes: 450000));
    case Estado164.descartar:
      final a = await montar();
      await preparar164(tester, tarjeta164, '800');
      await escribir164(tester, 'cobro_aprobacion', '004471');
      await tester.drag(
        find.descendant(of: pagina, matching: find.byType(Scrollable)).first,
        const Offset(0, 5000),
      );
      await asentarAgendar(tester, 4);
      await tocarCobro(tester, cerrarCobro);
      return a;
  }
}

/// Suelta lo que dejó trabado el estado y deja correr los cuadros pendientes.
Future<void> liberar164(WidgetTester tester, ArnesCobro a) async {
  final compuerta = a.repo.compuerta;
  if (compuerta != null && !compuerta.isCompleted) compuerta.complete();
  final lectura = a.repo.compuertaDeLectura;
  if (lectura != null && !lectura.isCompleted) lectura.complete();
  await asentarAgendar(tester, 4);
}

/// La pantalla completa (incluidas las hojas) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar164(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/164_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado164(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Las fuentes reales solo se apagan en el archivo de las guías de Flutter.
void sinFuentesReales164() => usarFuentesReales408 = false;
