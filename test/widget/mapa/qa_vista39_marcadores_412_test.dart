// QA de #412 / PR #467 · HU-VIS-005 · vista 39 (M·01 «De lejos» y M·02 «Acercado»): lo que el
// implementador no midió. El mapa nativo no se dibuja en `flutter test`, así que acá se prueban las
// imágenes que `MarcadorEstado` le entrega (pintadas de verdad, pixel a pixel) y los textos que lleva
// encima: el contraste del número sobre cada cuadrado, que el estado no dependa solo del color, el
// número de puerta con caracteres que no son un dígito, la
// leyenda «Referencias» con las fuentes reales.
//
// Las capturas (`QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas/` (gitignored, fuera del commit).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_cercano.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart'
    show ColoresLista;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _escala = 3.0;

/// El contraste WCAG entre dos colores opacos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++, dir = dir.parent) {
    final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
      return;
    }
  }
}

/// Un PNG de [MarcadorEstado] decodificado: sus píxeles RGBA y su tamaño.
final class _Imagen {
  _Imagen(this.imagen, this.rgba);
  final ui.Image imagen;
  final ByteData rgba;

  int get ancho => imagen.width;
  int get alto => imagen.height;

  /// El color del píxel ([x], [y]) mezclado sobre [fondo] (lo que se ve en el mapa).
  Color pixel(int x, int y, {Color fondo = const Color(0xFFEDEBE4)}) {
    final i = (y * ancho + x) * 4;
    final a = rgba.getUint8(i + 3) / 255;
    int mezcla(int c, int f) => (c * a + f * (1 - a)).round();
    return Color.fromARGB(
      255,
      mezcla(rgba.getUint8(i), (fondo.r * 255).round()),
      mezcla(rgba.getUint8(i + 1), (fondo.g * 255).round()),
      mezcla(rgba.getUint8(i + 2), (fondo.b * 255).round()),
    );
  }
}

Future<_Imagen> _decodificar(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final cuadro = await codec.getNextFrame();
  final rgba = (await cuadro.image.toByteData())!;
  return _Imagen(cuadro.image, rgba);
}

/// Los píxeles del cuadrado bajo el texto del número más largo (arriba a la izquierda, donde la
/// capa del mapa lo pone: anclado en `top-left`, a 3 dp del borde).
Iterable<Color> _fondoDelNumero(_Imagen cuadrado) sync* {
  final cx = cuadrado.ancho ~/ 2;
  final cy = cuadrado.alto ~/ 2;
  for (final caja in MarcadorEstado.cajasDelNumero(
    MarcadorEstado.numeroEnDosRenglones('1234567'),
  )) {
    for (var dx = caja.left.ceil(); dx < caja.right.floor(); dx++) {
      for (var dy = caja.top.ceil(); dy < caja.bottom.floor(); dy++) {
        yield cuadrado.pixel((cx + (dx * _escala)).round(), (cy + (dy * _escala)).round());
      }
    }
  }
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 2);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/467_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  group('contraste (AA): el número de puerta y el símbolo sobre cada cuadrado del mapa', () {
    for (final v in VarianteMarcador.values) {
      test('dado el cuadrado «${v.name}», cuando se pinta el número, entonces el texto de 12 dp '
          'contrasta 4,5:1 con el fondo', () {
        expect(_contraste(v.tintaNumero, v.fondo), greaterThanOrEqualTo(4.5));
      });

      test('dado el cuadrado «${v.name}», cuando se pinta el símbolo, entonces contrasta 3:1 con '
          'el fondo (elemento gráfico)', () {
        if (v == VarianteMarcador.sinVisita) return; // sin símbolo
        expect(_contraste(v.tinta, v.fondo), greaterThanOrEqualTo(3));
      });
    }

    // La franja clara es #4D76B1 (4,6:1 con el blanco; el canvas pedía #5C82B8, 3,9:1). Decisión del
    // 23/10 al hallazgo 1 del QA: sigue siendo una franja visible contra el azul de fondo.
    test(
      'dado el cuadrado «Entrega y pago» con sus franjas, cuando se pinta el número, entonces el '
      'texto contrasta 4,5:1 también con la franja clara',
      () async {
        final png = await MarcadorEstado.dibujarCuadrado(
          VarianteMarcador.entregaYPago,
          escala: _escala,
        );
        final cuadrado = await _decodificar(png);
        final peor = _fondoDelNumero(cuadrado)
            .map((c) => _contraste(VarianteMarcador.entregaYPago.tintaNumero, c))
            .reduce((a, b) => a < b ? a : b);
        expect(peor, greaterThanOrEqualTo(4.5));
      },
    );

    test('dada la franja clara de «Entrega y pago», cuando se la compara con el azul del fondo, '
        'entonces sigue viéndose (más de 2:1) y es la misma de la lista', () {
      expect(ColoresLista.azulClaro, const Color(0xFF4D76B1));
      expect(_contraste(ColoresLista.azulClaro, ColoresLista.azul), greaterThan(2));
      expect(_contraste(Colors.white, ColoresLista.azulClaro), greaterThanOrEqualTo(4.5));
    });
  });

  group('el estado no depende solo del color (§8.4)', () {
    for (final v in VarianteMarcador.values) {
      test(
        'dado el cuadrado «${v.name}», cuando se pinta, entonces trae el color de su estado y '
        '${v == VarianteMarcador.sinVisita ? "va vacío" : "un símbolo abajo a la derecha"}',
        () async {
          final c = await _decodificar(await MarcadorEstado.dibujarCuadrado(v, escala: _escala));
          expect(c.ancho, (46 * _escala).ceil());
          expect(c.alto, (46 * _escala).ceil());
          final cx = c.ancho ~/ 2;
          final cy = c.alto ~/ 2;

          // El color: un punto del relleno lejos del símbolo y del borde (arriba a la izquierda).
          if (v != VarianteMarcador.entregaYPago) {
            final muestra = c.pixel((cx - 12 * _escala).round(), (cy - 12 * _escala).round());
            expect(muestra, v.fondo, reason: 'relleno de ${v.name}');
          }

          // El símbolo: píxeles que no son el relleno en el rincón de abajo a la derecha.
          var distintos = 0;
          for (var dx = 6; dx <= 14; dx++) {
            for (var dy = 6; dy <= 14; dy++) {
              final p = c.pixel((cx + dx * _escala).round(), (cy + dy * _escala).round());
              if (p != v.fondo && v != VarianteMarcador.entregaYPago) distintos++;
            }
          }
          if (v == VarianteMarcador.sinVisita) {
            expect(distintos, 0, reason: '«Sin visita» no lleva símbolo');
          } else if (v != VarianteMarcador.entregaYPago) {
            expect(distintos, greaterThan(6), reason: 'la insignia ${v.name} necesita su símbolo');
          }
        },
      );
    }

    test('dados los ocho estados, cuando se pintan las insignias de lejos, entonces ninguna se '
        'repite pixel a pixel (el color solo no las distingue)', () async {
      final huellas = <String, String>{};
      for (final v in VarianteMarcador.values) {
        final png = await MarcadorEstado.dibujarInsignia(v, escala: _escala);
        final img = await _decodificar(png);
        final huella = [
          for (var y = 0; y < img.alto; y += 2)
            for (var x = 0; x < img.ancho; x += 2) img.pixel(x, y).toARGB32(),
        ].join(',');
        expect(huellas[huella], isNull, reason: '${v.name} igual a ${huellas[huella]}');
        huellas[huella] = v.name;
      }
    });

    test('dadas las variantes de lejos, cuando se mira la forma, entonces los estados de la venta '
        'y el edificio son cuadrados redondeados y los de la visita círculos', () async {
      for (final v in VarianteMarcador.values) {
        final img = await _decodificar(await MarcadorEstado.dibujarInsignia(v, escala: _escala));
        // La esquina del rectángulo de 22 dp: transparente en el círculo, pintada en el cuadrado.
        final esquina = img.pixel(
          ((MarcadorEstado.margen + 1.2) * _escala).round(),
          ((MarcadorEstado.margen + 1.2) * _escala).round(),
          fondo: const Color(0xFFFF00FF),
        );
        final pintada = esquina != const Color(0xFFFF00FF);
        expect(pintada, v.esCuadrada, reason: v.name);
      }
    });
  });

  group('número de puerta en el cuadrado (M·02)', () {
    test('dados números de 0 a 13 caracteres, cuando se parte en renglones, entonces nunca '
        'quedan más de dos renglones ni uno de más de 4 caracteres', () {
      for (var n = 0; n <= 13; n++) {
        final partido = MarcadorEstado.numeroEnDosRenglones('1234567890123'.substring(0, n));
        final renglones = partido.split('\n');
        expect(renglones.length, lessThanOrEqualTo(2), reason: 'n=$n');
        for (final r in renglones) {
          expect(r.length, lessThanOrEqualTo(4), reason: 'n=$n «$partido»');
        }
      }
    });

    test('dado solo espacios, cuando se parte, entonces queda vacío (la capa no pinta basura)', () {
      expect(MarcadorEstado.numeroEnDosRenglones('   '), '');
    });

    test('dado «20 44» con espacio adentro, cuando se parte, entonces no hay un renglón en '
        'blanco', () {
      final r = MarcadorEstado.numeroEnDosRenglones('20 44').split('\n');
      expect(r.every((x) => x.trim().isNotEmpty), isTrue, reason: '$r');
    });

    test(
      'dado un número con emoji, cuando se parte en renglones, entonces ningún renglón queda con '
      'un sustituto UTF-16 huérfano',
      () {
        for (final entrada in ['12🏠3', '🏠🏠🏠🏠🏠', '1234🏠5678', 'A🏠BCD', '🏠🏠🏠']) {
          final partido = MarcadorEstado.numeroEnDosRenglones(entrada);
          for (var i = 0; i < partido.length; i++) {
            final u = partido.codeUnitAt(i);
            final alto = u >= 0xD800 && u <= 0xDBFF;
            final bajo = u >= 0xDC00 && u <= 0xDFFF;
            if (alto) {
              expect(
                i + 1 < partido.length &&
                    partido.codeUnitAt(i + 1) >= 0xDC00 &&
                    partido.codeUnitAt(i + 1) <= 0xDFFF,
                isTrue,
                reason: '«$entrada» → huérfano alto en $i de «${partido.replaceAll("\n", "/")}»',
              );
            }
            if (bajo) {
              expect(
                i > 0 && partido.codeUnitAt(i - 1) >= 0xD800 && partido.codeUnitAt(i - 1) <= 0xDBFF,
                isTrue,
                reason: '«$entrada» → huérfano bajo en $i de «${partido.replaceAll("\n", "/")}»',
              );
            }
          }
        }
      },
    );
  });

  group('número y símbolo nunca se pisan (decisión del 23/10, P2 del QA)', () {
    const cuadrado = Rect.fromLTWH(-20, -20, 40, 40);
    const casos = ['2044', '12345', '12345678', '1234567890123'];

    /// `true` si [a] y [b] no se tocan: hay al menos [aire] dp entre las dos cajas.
    bool separadas(Rect a, Rect b, double aire) =>
        a.right + aire <= b.left + 1e-9 ||
        b.right + aire <= a.left + 1e-9 ||
        a.bottom + aire <= b.top + 1e-9 ||
        b.bottom + aire <= a.top + 1e-9;

    for (final numero in casos) {
      test('dado el número «$numero», cuando se parte para el cuadrado, entonces la caja de cada '
          'renglón queda dentro del cuadrado y a 1 dp o más de la del símbolo', () {
        final partido = MarcadorEstado.numeroEnDosRenglones(numero);
        final simbolo = MarcadorEstado.cajaDelSimbolo;

        for (final caja in MarcadorEstado.cajasDelNumero(partido)) {
          expect(cuadrado.contains(caja.topLeft), isTrue, reason: '«$partido» $caja');
          expect(cuadrado.contains(caja.bottomRight), isTrue, reason: '«$partido» $caja');
          expect(
            separadas(caja, simbolo, MarcadorEstado.aireNumeroSimbolo),
            isTrue,
            reason: '«$partido» $caja toca el símbolo $simbolo',
          );
        }
      });
    }

    test('dado cada número de 1 a 13 caracteres, cuando se parte, entonces ninguna caja toca el '
        'símbolo', () {
      for (var n = 1; n <= 13; n++) {
        final partido = MarcadorEstado.numeroEnDosRenglones('1234567890123'.substring(0, n));
        for (final caja in MarcadorEstado.cajasDelNumero(partido)) {
          expect(
            separadas(caja, MarcadorEstado.cajaDelSimbolo, MarcadorEstado.aireNumeroSimbolo),
            isTrue,
            reason: 'n=$n «${partido.replaceAll("\n", "/")}»',
          );
        }
      }
    });

    testWidgets('dado el número con la letra real a 12 dp, cuando se mide cada renglón, entonces '
        'cabe en la caja que reserva el cálculo y no toca el símbolo', (tester) async {
      await _cargarFuentes();
      for (final numero in casos) {
        final partido = MarcadorEstado.numeroEnDosRenglones(numero);
        final cajas = MarcadorEstado.cajasDelNumero(partido);
        final renglones = partido.split('\n');
        for (var i = 0; i < renglones.length; i++) {
          final medido = TextPainter(
            text: TextSpan(
              text: renglones[i],
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: MarcadorEstado.tamanoNumero,
                fontWeight: FontWeight.w500,
                height: MarcadorEstado.interlineadoNumero,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final real = Rect.fromLTWH(cajas[i].left, cajas[i].top, medido.width, cajas[i].height);
          medido.dispose();

          expect(real.width, lessThanOrEqualTo(cajas[i].width), reason: '«${renglones[i]}»');
          expect(
            separadas(real, MarcadorEstado.cajaDelSimbolo, 0),
            isTrue,
            reason: '«${renglones[i]}» de $numero mide ${real.width} y toca el símbolo',
          );
        }
      }
    });

    test('dado el símbolo del estado, cuando se pinta, entonces ocupa la caja reservada: abajo a '
        'la derecha, a 5 dp de los bordes', () {
      final simbolo = MarcadorEstado.cajaDelSimbolo;
      expect(simbolo.right, 20 - MarcadorEstado.margenSimbolo);
      expect(simbolo.bottom, 20 - MarcadorEstado.margenSimbolo);
      expect(simbolo.width, MarcadorEstado.ladoSimbolo);
    });
  });

  group('imágenes que se registran en el estilo', () {
    test('dado el mapa de una cuadra de cien casas, cuando se arman los puntos, entonces las '
        'imágenes son las de las variantes y no una por casa', () {
      final nombres = {
        for (final v in VarianteMarcador.values) ...[
          MarcadorEstado.nombreInsignia(v),
          MarcadorEstado.nombreCuadrado(v),
        ],
        MarcadorEstado.nombreAro,
      };
      expect(nombres.length, 19);
    });

    test('dado el nombre de la etiqueta de «cerca tuyo», cuando el estado es «Sin visita» o '
        'no se sabe, entonces conserva el nombre de siempre y con estado lleva la variante', () {
      expect(MarcadorCercano.nombre('12'), 'colportores:cercano:12');
      expect(MarcadorCercano.nombre('12', VarianteMarcador.sinVisita), 'colportores:cercano:12');
      expect(
        MarcadorCercano.nombre('12', VarianteMarcador.rechazo),
        'colportores:cercano:rechazo:12',
      );
      // Dos casas con el mismo número y distinto estado no comparten imagen.
      expect(
        MarcadorCercano.nombre('12', VarianteMarcador.rechazo),
        isNot(MarcadorCercano.nombre('12', VarianteMarcador.ventaCompleta)),
      );
    });
  });

  group('revisión visual (capturas con QA_CAPTURAS=true)', () {
    testWidgets('lámina de los marcadores: insignias de lejos, cuadrados con su número y '
        'etiquetas de «cerca tuyo»', (tester) async {
      await _cargarFuentes();
      tester.view.physicalSize = const Size(420 * _escala, 760 * _escala);
      tester.view.devicePixelRatio = _escala;
      addTearDown(tester.view.reset);

      final insignias = <VarianteMarcador, ui.Image>{};
      final cuadrados = <VarianteMarcador, ui.Image>{};
      final etiquetas = <VarianteMarcador, ui.Image>{};
      await tester.runAsync(() async {
        for (final v in VarianteMarcador.values) {
          insignias[v] = (await _decodificar(
            await MarcadorEstado.dibujarInsignia(v, escala: _escala),
          )).imagen;
          cuadrados[v] = (await _decodificar(
            await MarcadorEstado.dibujarCuadrado(v, escala: _escala),
          )).imagen;
          etiquetas[v] = (await _decodificar(
            await MarcadorCercano.dibujar('3307', escala: _escala, variante: v),
          )).imagen;
        }
      });

      Widget imagen(ui.Image i) =>
          RawImage(image: i, scale: _escala, filterQuality: FilterQuality.high);

      Widget cuadradoConNumero(VarianteMarcador v, String numero) {
        final partido = MarcadorEstado.numeroEnDosRenglones(numero);
        return Stack(
          children: [
            imagen(cuadrados[v]!),
            // La capa de texto del mapa: 12 dp, interlineado 1,05, anclada arriba a la izquierda a
            // 3 dp del borde (la esquina de abajo a la derecha es del símbolo).
            Positioned(
              left: MarcadorEstado.margenNumero + MarcadorEstado.margen,
              top: MarcadorEstado.margenNumero + MarcadorEstado.margen,
              child: Text(
                partido,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: MarcadorEstado.tamanoNumero,
                  fontWeight: FontWeight.w500,
                  height: MarcadorEstado.interlineadoNumero,
                  color: v.tintaNumero,
                ),
              ),
            ),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            child: Material(
              color: const Color(0xFFEDEBE4),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('M·01 de lejos (22 dp)', style: TextStyle(fontSize: 11)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [for (final v in VarianteMarcador.values) imagen(insignias[v]!)],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'M·02 acercado (40 dp, número 2 renglones)',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final v in VarianteMarcador.values) cuadradoConNumero(v, '2044'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Número de 1 y de 3 y de 9 caracteres',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          cuadradoConNumero(VarianteMarcador.rechazo, '7'),
                          cuadradoConNumero(VarianteMarcador.noContesto, 's/n'),
                          cuadradoConNumero(VarianteMarcador.entrevistaAgendada, '120'),
                          cuadradoConNumero(VarianteMarcador.ventaCompleta, '12345'),
                          cuadradoConNumero(VarianteMarcador.entregaYPago, '123456789'),
                          cuadradoConNumero(VarianteMarcador.cobranzaPendiente, '1234567890123'),
                          cuadradoConNumero(VarianteMarcador.sinVisita, '3307'),
                          cuadradoConNumero(VarianteMarcador.edificio, '2044'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Etiqueta de «cerca tuyo» por estado',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final v in VarianteMarcador.values) imagen(etiquetas[v]!)],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _capturar(tester, 'marcadores');
    });

    for (final (nombre, tamano, escala) in const [
      ('360x640_x1', Size(360, 640), 1.0),
      ('360x640_x2', Size(360, 640), 2.0),
      ('412x915_x1', Size(412, 915), 1.0),
    ]) {
      testWidgets('la leyenda «Referencias» con sus ocho estados y las fuentes reales a $nombre', (
        tester,
      ) async {
        await _cargarFuentes();
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso([filaLista('a', estado: EstadoCasa.rechazo)]),
          tamano: tamano,
          escala: escala,
        );
        await tester.tap(chipReferencias);
        await asentarLista(tester);

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await _capturar(tester, 'leyenda_$nombre');
      });
    }
  });

  // Los colores de la lista y los del mapa son los mismos (una sola paleta para la insignia de la
  // vista 05, la 06 y la 39).
  test('dado cada estado, cuando se compara el color del mapa con el de la lista, entonces es el '
      'mismo', () {
    expect(VarianteMarcador.noContesto.fondo, ColoresLista.grisEstado);
    expect(VarianteMarcador.entrevistaAgendada.fondo, ColoresLista.ambar);
    expect(VarianteMarcador.entrevistaHecha.fondo, ColoresLista.verde);
    expect(VarianteMarcador.ventaCompleta.fondo, ColoresLista.verde);
    expect(VarianteMarcador.cobranzaPendiente.fondo, ColoresLista.azul);
    expect(VarianteMarcador.rechazo.fondo, ColoresLista.rojo);
  });

  test('dado un edificio, cuando el tipo es edificio sin estado, entonces la variante lleva el '
      'símbolo del edificio y con estado el del estado', () {
    expect(VarianteMarcador.de(null, edificio: true), VarianteMarcador.edificio);
    expect(VarianteMarcador.de(EstadoCasa.sinVisita, edificio: true), VarianteMarcador.edificio);
    expect(VarianteMarcador.de(EstadoCasa.rechazo, edificio: true), VarianteMarcador.rechazo);
    expect(TipoUbicacion.values, contains(TipoUbicacion.edificio));
  });
}
