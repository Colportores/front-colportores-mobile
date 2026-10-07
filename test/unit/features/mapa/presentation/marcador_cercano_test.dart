// HU-UBI-003 · vista 06 (#199, decisión del 07/10 en el #294, P4): la etiqueta de «cerca tuyo» del
// canvas (la píldora con el círculo del estado y el número de puerta) se pinta una vez por número en
// una imagen que el mapa nativo registra en el estilo.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_cercano.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decodificar(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Los cuatro bytes (rojo, verde, azul y opacidad) del píxel ([x], [y]).
Future<List<int>> _pixel(ui.Image imagen, int x, int y) async {
  final datos = (await imagen.toByteData())!;
  final desde = (y * imagen.width + x) * 4;
  return [for (var i = 0; i < 4; i++) datos.getUint8(desde + i)];
}

void main() {
  testWidgets('es un PNG', (tester) async {
    final png = (await tester.runAsync(() => MarcadorCercano.dibujar('1234')))!;

    expect(png.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('mide lo que dicen las medidas, por la escala de la pantalla', (tester) async {
    for (final escala in [1.0, 2.0, 2.625, 3.0]) {
      final png = (await tester.runAsync(() => MarcadorCercano.dibujar('1250', escala: escala)))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;
      final medidas = MarcadorCercano.medidas('1250');

      expect(imagen.width, (medidas.width * escala).ceil(), reason: 'ancho a $escala');
      expect(imagen.height, (medidas.height * escala).ceil(), reason: 'alto a $escala');
      imagen.dispose();
    }
  });

  testWidgets('crece con los caracteres del número y el alto es siempre el mismo', (tester) async {
    final sinNumero = MarcadorCercano.medidas('s/n');
    final corto = MarcadorCercano.medidas('12');
    final largo = MarcadorCercano.medidas('1234');
    final muyLargo = MarcadorCercano.medidas('12345678');

    expect(corto.width, lessThan(largo.width));
    expect(largo.width, lessThan(muyLargo.width));
    expect(sinNumero.width, lessThan(largo.width));
    for (final medida in [sinNumero, corto, largo, muyLargo]) {
      expect(medida.height, sinNumero.height);
    }
    // La píldora del canvas mide 32 dp de alto y la punta 7: con el aire de la sombra, arriba.
    expect(
      sinNumero.height,
      MarcadorCercano.margenSombra + MarcadorCercano.altoPildora + MarcadorCercano.altoPunta,
    );
  });

  testWidgets('el nombre de la imagen es único por número y no choca con las capas del estilo', (
    tester,
  ) async {
    expect(MarcadorCercano.nombre('1234'), isNot(MarcadorCercano.nombre('1236')));
    expect(MarcadorCercano.nombre('1234'), MarcadorCercano.nombre('1234'));
    expect(MarcadorCercano.nombre('s/n'), startsWith('colportores:cercano:'));
  });

  testWidgets('la punta de abajo, centrada, es del color del estado; el círculo del estado va '
      'vacío (sin visita); y las esquinas son transparentes', (tester) async {
    final png = (await tester.runAsync(() => MarcadorCercano.dibujar('1234')))!;
    final imagen = (await tester.runAsync(() => _decodificar(png)))!;

    // La punta: pegada al borde de abajo de la píldora, en el medio.
    final punta = (await tester.runAsync(
      () => _pixel(imagen, imagen.width ~/ 2, imagen.height - 3),
    ))!;
    expect(punta, [0x6B, 0x76, 0x88, 0xFF]);
    // El borde de la píldora, arriba en el medio.
    final borde = (await tester.runAsync(() => _pixel(imagen, imagen.width ~/ 2, 8)))!;
    expect(borde, [0x6B, 0x76, 0x88, 0xFF]);
    // El centro del círculo del estado: blanco («Sin visita» va vacío).
    final circulo = (await tester.runAsync(() => _pixel(imagen, 25, 24)))!;
    expect(circulo, [0xFF, 0xFF, 0xFF, 0xFF]);
    // Las esquinas no se pintan (a lo sumo el aire de la sombra).
    for (final (x, y) in [(0, 0), (imagen.width - 1, 0), (0, imagen.height - 1)]) {
      final esquina = (await tester.runAsync(() => _pixel(imagen, x, y)))!;
      expect(esquina[3], lessThan(8), reason: 'esquina ($x, $y)');
    }
    imagen.dispose();
  });

  testWidgets('pintar la misma etiqueta dos veces da la misma imagen (no guarda estado)', (
    tester,
  ) async {
    final a = (await tester.runAsync(() => MarcadorCercano.dibujar('s/n')))!;
    final b = (await tester.runAsync(() => MarcadorCercano.dibujar('s/n')))!;

    expect(a, b);
  });
}
