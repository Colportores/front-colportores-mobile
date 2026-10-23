import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../domain/entities/estado_casa.dart';
import '../formato_lista_ubicaciones.dart';
import '../widgets/piezas_lista_ubicaciones.dart' show ColoresLista;

/// Cómo se ve una casa en el mapa (vista 39, M·01 y M·02): uno de los ocho estados de la lista
/// (vista 05) o el símbolo del edificio, que es lo que dibuja el canvas para un edificio al que
/// todavía no se le registró nada.
///
/// Un edificio **con** estado toma el de su depto más urgente (decisión de Cristian del 23/10,
/// «Color edificio»): ahí la variante es la del estado, igual que la de una casa.
enum VarianteMarcador {
  sinVisita(EstadoCasa.sinVisita),
  noContesto(EstadoCasa.noContesto),
  entrevistaAgendada(EstadoCasa.entrevistaAgendada),
  entrevistaHecha(EstadoCasa.entrevistaHecha),
  ventaCompleta(EstadoCasa.ventaCompleta),
  cobranzaPendiente(EstadoCasa.cobranzaPendiente),
  entregaYPago(EstadoCasa.entregaYPago),
  rechazo(EstadoCasa.rechazo),
  edificio(null);

  const VarianteMarcador(this.estado);

  /// El estado de la lista que representa; `null` en el edificio sin estado.
  final EstadoCasa? estado;

  /// La variante de una casa con [estado] (`null` = no se sabe, se dibuja como «Sin visita»). Un
  /// [edificio] sin visita se dibuja con su símbolo; con estado, con el del estado.
  static VarianteMarcador de(EstadoCasa? estado, {bool edificio = false}) {
    final e = estado ?? EstadoCasa.sinVisita;
    if (e == EstadoCasa.sinVisita) return edificio ? VarianteMarcador.edificio : sinVisita;
    return values.firstWhere((v) => v.estado == e);
  }

  /// Es el aspecto de una casa a la que no le pasó nada: «Sin visita» o el edificio sin estado.
  bool get esNeutra => this == sinVisita || this == edificio;

  /// Va en cuadrado redondeado (los estados de la venta y el edificio) y no en círculo (los de la
  /// visita): canvas, «Círculo: estados de la visita. Cuadrado: estados de la venta».
  bool get esCuadrada => this == edificio || (estado?.esDeVenta ?? false);

  Color get fondo => switch (this) {
    sinVisita || edificio => const Color(0xFFFFFFFF),
    noContesto => ColoresLista.grisEstado,
    entrevistaAgendada => ColoresLista.ambar,
    entrevistaHecha || ventaCompleta => ColoresLista.verde,
    cobranzaPendiente || entregaYPago => ColoresLista.azul,
    rechazo => ColoresLista.rojo,
  };

  /// El color del símbolo y del número sobre [fondo].
  Color get tinta => switch (this) {
    sinVisita => ColoresLista.grisEstado,
    edificio => ColoresLista.grisTexto,
    entrevistaAgendada => ColoresLista.tinta,
    _ => const Color(0xFFFFFFFF),
  };

  /// El color del número de puerta sobre [fondo]: [tinta], salvo en «Sin visita», donde el gris del
  /// símbolo no llega a leerse bien como texto sobre el blanco y el número va en el azul oscuro.
  Color get tintaNumero => this == sinVisita ? ColoresLista.grisTexto : tinta;

  /// El color del contorno: el del fondo en los estados con relleno; en «Sin visita» y en el
  /// edificio, el gris que los distingue del fondo blanco.
  Color get borde => switch (this) {
    sinVisita => ColoresLista.grisEstado,
    edificio => ColoresLista.grisTexto,
    _ => fondo,
  };

  /// El grosor del contorno de los neutros; los demás no tienen.
  double get grosorBorde => switch (this) {
    sinVisita => 2.5,
    edificio => 2,
    _ => 0,
  };

  /// Lo que dice un lector de pantalla del estado.
  String get rotulo => estado == null ? 'Edificio' : FormatoListaUbicaciones.estado(estado!);
}

/// Los marcadores de estado del mapa (vista 39), pintados como imágenes que la vista nativa registra
/// en el estilo: el mapa no dibuja widgets, y los símbolos de una capa se eligen por nombre.
///
/// - **De lejos (M·01)**: la insignia de 22 dp, un círculo (estados de la visita) o un cuadrado
///   redondeado (estados de la venta y edificio) con el símbolo del estado adentro, además del color.
/// - **Acercado (M·02)**: el cuadrado de 40 dp con el color del estado y el símbolo chico abajo a la
///   derecha; el número va encima, como texto de la capa (dos renglones).
/// - El aro del cuadrado seleccionado.
///
/// Hay una imagen por variante (nueve), no una por casa ni por número: el mapa de una cuadra de cien
/// casas registra las mismas diecinueve imágenes que el de una sola.
abstract final class MarcadorEstado {
  /// El diámetro de la insignia de lejos (canvas: 22).
  static const ladoInsignia = 22.0;

  /// El lado del cuadrado de cerca (M·02: «un cuadrado de 40 px»).
  static const ladoCuadrado = 40.0;

  /// El lado del aro del seleccionado: 6 dp más que el cuadrado a cada lado (3 de azul y 3 de blanco).
  static const ladoAro = 52.0;

  /// El aire alrededor de cada forma para la sombra.
  static const margen = 3.0;

  /// El radio de las esquinas del cuadrado de 40 dp.
  static const radioCuadrado = 8.0;

  /// Lo que se separa el símbolo chico del cuadrado de los bordes de abajo y de la derecha.
  static const margenSimbolo = 5.0;

  /// El tamaño del símbolo chico del cuadrado.
  static const ladoSimbolo = 12.0;

  /// El azul del aro (el mismo del aro del seleccionado de lejos, `ColoresMapa.aroSeleccion`).
  static const _azulDelAro = ui.Color(0xFF002856);

  /// Cuántos caracteres entran en un renglón del cuadrado a 12 dp (el número largo se corta con «…»:
  /// la dirección completa está en la hoja de la casa).
  static const caracteresPorRenglon = 4;

  /// El número de puerta como va dentro del cuadrado (M·02: «el número adentro en dos renglones, 20 /
  /// 44»): «2044» es «20» y «44». Hasta tres caracteres («s/n», «12», «120») va en un renglón; más,
  /// se parte a la mitad (el primer renglón con el que sobra); y más de ocho, se corta con «…».
  static String numeroEnDosRenglones(String etiqueta) {
    final numero = etiqueta.trim();
    if (numero.length <= 3) return numero;
    const tope = caracteresPorRenglon * 2;
    final corto = numero.length > tope ? '${numero.substring(0, tope - 1)}…' : numero;
    final mitad = (corto.length + 1) ~/ 2;
    return '${corto.substring(0, mitad)}\n${corto.substring(mitad)}';
  }

  static String nombreInsignia(VarianteMarcador variante) => 'colportores:estado:${variante.name}';

  static String nombreCuadrado(VarianteMarcador variante) =>
      'colportores:cuadrado:${variante.name}';

  static const nombreAro = 'colportores:cuadrado-aro';

  static const _medidaInsignia = ui.Size(ladoInsignia + 2 * margen, ladoInsignia + 2 * margen);
  static const _medidaCuadrado = ui.Size(ladoCuadrado + 2 * margen, ladoCuadrado + 2 * margen);
  static const _medidaAro = ui.Size(ladoAro + 2 * margen, ladoAro + 2 * margen);

  /// La insignia de [variante] como PNG, con [escala] píxeles por dp.
  static Future<Uint8List> dibujarInsignia(VarianteMarcador variante, {double escala = 1}) =>
      _png(_medidaInsignia, escala, (lienzo) {
        final centro = ui.Offset(_medidaInsignia.width / 2, _medidaInsignia.height / 2);
        final forma = _forma(centro, ladoInsignia, variante, 6 / 22);
        lienzo.drawRRect(
          forma.shift(const ui.Offset(0, 1)),
          ui.Paint()
            ..color = const ui.Color(0x400E1A2B)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1),
        );
        pintarInsignia(lienzo, centro, ladoInsignia, variante);
      });

  /// El cuadrado de [variante] (sin el número) como PNG, con [escala] píxeles por dp.
  static Future<Uint8List> dibujarCuadrado(VarianteMarcador variante, {double escala = 1}) =>
      _png(_medidaCuadrado, escala, (lienzo) {
        final centro = ui.Offset(_medidaCuadrado.width / 2, _medidaCuadrado.height / 2);
        final forma = ui.RRect.fromRectAndRadius(
          ui.Rect.fromCenter(center: centro, width: ladoCuadrado, height: ladoCuadrado),
          const ui.Radius.circular(radioCuadrado),
        );
        lienzo.drawRRect(
          forma.shift(const ui.Offset(0, 2)),
          ui.Paint()
            ..color = const ui.Color(0x4D0E1A2B)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
        );
        _pintarForma(lienzo, forma, variante);
        // El símbolo chico, abajo a la derecha.
        const desplazamiento = ladoCuadrado / 2 - margenSimbolo - ladoSimbolo / 2;
        _pintarGlifo(
          lienzo,
          variante,
          centro + const ui.Offset(desplazamiento, desplazamiento),
          ladoSimbolo,
          variante.tinta,
        );
      });

  /// El aro del cuadrado seleccionado: un anillo azul y otro blanco alrededor del cuadrado, que se
  /// dibuja encima.
  static Future<Uint8List> dibujarAro({double escala = 1}) => _png(_medidaAro, escala, (lienzo) {
    final centro = ui.Offset(_medidaAro.width / 2, _medidaAro.height / 2);
    final exterior = ui.RRect.fromRectAndRadius(
      ui.Rect.fromCenter(center: centro, width: ladoAro, height: ladoAro),
      const ui.Radius.circular(radioCuadrado + 5),
    );
    lienzo
      ..drawRRect(
        exterior.shift(const ui.Offset(0, 2)),
        ui.Paint()
          ..color = const ui.Color(0x590E1A2B)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
      )
      ..drawRRect(exterior, ui.Paint()..color = _azulDelAro)
      ..drawRRect(exterior.deflate(3), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  });

  /// Pinta la insignia de [variante] de [diametro] dp centrada en [centro], sin sombra. La usan la
  /// insignia de lejos y el círculo de la etiqueta de «cerca tuyo» (`MarcadorCercano`).
  static void pintarInsignia(
    ui.Canvas lienzo,
    ui.Offset centro,
    double diametro,
    VarianteMarcador variante,
  ) {
    _pintarForma(lienzo, _forma(centro, diametro, variante, 6 / 22), variante);
    _pintarGlifo(lienzo, variante, centro, diametro * .5, variante.tinta);
  }

  static ui.RRect _forma(
    ui.Offset centro,
    double lado,
    VarianteMarcador variante,
    double proporcionEsquina,
  ) => ui.RRect.fromRectAndRadius(
    ui.Rect.fromCenter(center: centro, width: lado, height: lado),
    ui.Radius.circular(variante.esCuadrada ? lado * proporcionEsquina : lado / 2),
  );

  /// El relleno y el contorno de [forma]. «Entrega y pago» lleva las franjas a 135° del canvas (4 dp
  /// de azul y 3 de azul claro).
  static void _pintarForma(ui.Canvas lienzo, ui.RRect forma, VarianteMarcador variante) {
    final grosor = variante.grosorBorde;
    if (grosor > 0) {
      lienzo
        ..drawRRect(forma, ui.Paint()..color = variante.borde)
        ..drawRRect(forma.deflate(grosor), ui.Paint()..color = variante.fondo);
      return;
    }
    lienzo.drawRRect(forma, ui.Paint()..color = variante.fondo);
    if (variante != VarianteMarcador.entregaYPago) return;
    lienzo
      ..save()
      ..clipRRect(forma);
    final franja = ui.Paint()
      ..color = ColoresLista.azulClaro
      ..strokeWidth = 3
      ..style = ui.PaintingStyle.stroke;
    // Franjas perpendiculares al degradado de 135° (de abajo a la izquierda hacia arriba a la
    // derecha), con 7 dp de período medidos en perpendicular: 7 √2 a lo largo de x.
    const paso = 7 * math.sqrt2;
    for (var x = forma.left - forma.height; x < forma.right; x += paso) {
      lienzo.drawLine(ui.Offset(x, forma.bottom), ui.Offset(x + forma.height, forma.top), franja);
    }
    lienzo.restore();
  }

  /// El símbolo de [variante] de [lado] dp centrado en [centro]. Son trazos (no letras de una
  /// fuente): se ven igual en cualquier teléfono, y los del canvas (– ✓ ✕ ◷ ★ ⇢ ▦) no están en todas
  /// las tipografías del sistema. Solo «$» es texto.
  static void _pintarGlifo(
    ui.Canvas lienzo,
    VarianteMarcador variante,
    ui.Offset centro,
    double lado,
    Color color,
  ) {
    ui.Paint trazo(double grosor) => ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = lado * grosor
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    ui.Offset p(double x, double y) => centro + ui.Offset(x * lado, y * lado);

    switch (variante) {
      case VarianteMarcador.sinVisita:
        return;
      case VarianteMarcador.noContesto:
        lienzo.drawLine(p(-.34, 0), p(.34, 0), trazo(.2));
      case VarianteMarcador.entrevistaHecha:
        lienzo.drawPath(
          ui.Path()
            ..moveTo(p(-.36, .02).dx, p(-.36, .02).dy)
            ..lineTo(p(-.1, .28).dx, p(-.1, .28).dy)
            ..lineTo(p(.38, -.28).dx, p(.38, -.28).dy),
          trazo(.2),
        );
      case VarianteMarcador.rechazo:
        lienzo
          ..drawLine(p(-.3, -.3), p(.3, .3), trazo(.2))
          ..drawLine(p(-.3, .3), p(.3, -.3), trazo(.2));
      case VarianteMarcador.entrevistaAgendada:
        lienzo
          ..drawCircle(centro, lado * .4, trazo(.13))
          ..drawLine(centro, p(0, -.22), trazo(.13))
          ..drawLine(centro, p(.16, .1), trazo(.13));
      case VarianteMarcador.ventaCompleta:
        final estrella = ui.Path();
        for (var i = 0; i < 10; i++) {
          final radio = (i.isEven ? .5 : .22) * lado;
          final angulo = -math.pi / 2 + i * math.pi / 5;
          final punto = centro + ui.Offset(radio * math.cos(angulo), radio * math.sin(angulo));
          if (i == 0) {
            estrella.moveTo(punto.dx, punto.dy);
          } else {
            estrella.lineTo(punto.dx, punto.dy);
          }
        }
        lienzo.drawPath(estrella..close(), ui.Paint()..color = color);
      case VarianteMarcador.cobranzaPendiente:
        final texto = TextPainter(
          text: TextSpan(
            text: r'$',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: lado * 1.05,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        texto.paint(lienzo, centro - ui.Offset(texto.width / 2, texto.height / 2));
        texto.dispose();
      case VarianteMarcador.entregaYPago:
        lienzo
          ..drawLine(p(-.4, 0), p(-.15, 0), trazo(.16))
          ..drawLine(p(-.02, 0), p(.28, 0), trazo(.16))
          ..drawPath(
            ui.Path()
              ..moveTo(p(.12, -.22).dx, p(.12, -.22).dy)
              ..lineTo(p(.4, 0).dx, p(.4, 0).dy)
              ..lineTo(p(.12, .22).dx, p(.12, .22).dy),
            trazo(.16),
          );
      case VarianteMarcador.edificio:
        lienzo
          ..drawRRect(
            ui.RRect.fromRectAndRadius(
              ui.Rect.fromCenter(center: centro, width: lado * .7, height: lado * .7),
              ui.Radius.circular(lado * .08),
            ),
            trazo(.1),
          )
          ..drawLine(p(0, -.35), p(0, .35), trazo(.1))
          ..drawLine(p(-.35, 0), p(.35, 0), trazo(.1));
    }
  }

  static Future<Uint8List> _png(
    ui.Size medida,
    double escala,
    void Function(ui.Canvas lienzo) pintar,
  ) async {
    final grabador = ui.PictureRecorder();
    final lienzo = ui.Canvas(grabador)..scale(escala);
    pintar(lienzo);
    final imagen = await grabador.endRecording().toImage(
      (medida.width * escala).ceil(),
      (medida.height * escala).ceil(),
    );
    try {
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      if (datos == null) throw StateError('no se pudo codificar el marcador');
      return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
    } finally {
      imagen.dispose();
    }
  }
}
