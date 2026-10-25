// HU-VIS-005 · vista 39 (#412): el color y el símbolo de cada estado de la casa en el mapa. De lejos
// (M·01) la insignia de 22 dp; acercado (M·02) el cuadrado de 40 dp con el símbolo chico abajo a la
// derecha, y el aro del seleccionado. Se pintan una vez por variante y la vista nativa las registra.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_cercano.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decodificar(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<List<int>> _pixel(ui.Image imagen, int x, int y) async {
  final datos = (await imagen.toByteData())!;
  final desde = (y * imagen.width + x) * 4;
  return [for (var i = 0; i < 4; i++) datos.getUint8(desde + i)];
}

void main() {
  group('VarianteMarcador.de', () {
    test('dado cada estado de la lista, cuando se pide su variante, entonces es la suya', () {
      for (final estado in EstadoCasa.values) {
        expect(VarianteMarcador.de(estado).estado, estado, reason: estado.name);
      }
    });

    test('dado un estado que no se conoce, cuando se pide, entonces se dibuja «Sin visita»', () {
      expect(VarianteMarcador.de(null), VarianteMarcador.sinVisita);
    });

    test('dado un edificio, cuando no tiene estado, entonces lleva su símbolo; con estado, el '
        'del estado (el más urgente de sus deptos)', () {
      expect(VarianteMarcador.de(null, edificio: true), VarianteMarcador.edificio);
      expect(VarianteMarcador.de(EstadoCasa.sinVisita, edificio: true), VarianteMarcador.edificio);
      expect(
        VarianteMarcador.de(EstadoCasa.cobranzaPendiente, edificio: true),
        VarianteMarcador.cobranzaPendiente,
      );
    });

    test('dados los ocho estados, cuando se compara el color, entonces ninguno se parece a otro '
        'solo por el color (el símbolo los distingue) y los neutros son blancos', () {
      expect(VarianteMarcador.sinVisita.fondo, VarianteMarcador.edificio.fondo);
      expect(VarianteMarcador.sinVisita.esNeutra, isTrue);
      expect(VarianteMarcador.edificio.esNeutra, isTrue);
      expect(VarianteMarcador.rechazo.esNeutra, isFalse);
      // Círculo en los estados de la visita; cuadrado en los de la venta y en el edificio.
      expect(VarianteMarcador.noContesto.esCuadrada, isFalse);
      expect(VarianteMarcador.rechazo.esCuadrada, isFalse);
      expect(VarianteMarcador.ventaCompleta.esCuadrada, isTrue);
      expect(VarianteMarcador.entregaYPago.esCuadrada, isTrue);
      expect(VarianteMarcador.edificio.esCuadrada, isTrue);
    });

    test('cada variante tiene un rótulo para el lector de pantalla', () {
      for (final v in VarianteMarcador.values) {
        expect(v.rotulo, isNotEmpty, reason: v.name);
      }
      expect(VarianteMarcador.edificio.rotulo, 'Edificio');
      expect(VarianteMarcador.ventaCompleta.rotulo, 'Venta completa');
    });
  });

  group('MarcadorEstado.numeroEnDosRenglones', () {
    test('dados hasta tres caracteres, cuando se parte, entonces va en un solo renglón', () {
      expect(MarcadorEstado.numeroEnDosRenglones('7'), '7');
      expect(MarcadorEstado.numeroEnDosRenglones('s/n'), 's/n');
      expect(MarcadorEstado.numeroEnDosRenglones('120'), '120');
    });

    test('dados cuatro o más caracteres, cuando se parte, entonces van en dos renglones', () {
      expect(MarcadorEstado.numeroEnDosRenglones('3307'), '33\n07');
      expect(MarcadorEstado.numeroEnDosRenglones('1234'), '12\n34');
      expect(MarcadorEstado.numeroEnDosRenglones('12345'), '123\n45');
    });

    test('dado un número larguísimo, cuando se parte, entonces se corta con «…» y no pasa de '
        'dos renglones', () {
      final partido = MarcadorEstado.numeroEnDosRenglones('1234567890123');
      final renglones = partido.split('\n');

      expect(renglones, hasLength(2));
      expect(renglones.first.length, lessThanOrEqualTo(MarcadorEstado.caracteresPorRenglon));
      expect(renglones.last.length, lessThanOrEqualTo(MarcadorEstado.caracteresSegundoRenglon));
      expect(partido, endsWith('…'));
    });

    test('dado un número de seis a ocho caracteres, cuando se parte, entonces el primer renglón '
        'lleva lo que el segundo no puede (el símbolo ocupa su esquina)', () {
      expect(MarcadorEstado.numeroEnDosRenglones('123456'), '1234\n56');
      expect(MarcadorEstado.numeroEnDosRenglones('1234567'), '1234\n5…');
      expect(MarcadorEstado.numeroEnDosRenglones('12345678'), '1234\n5…');
    });

    test('dado un número con emoji, cuando se parte, entonces no se corta un carácter por el '
        'medio', () {
      expect(MarcadorEstado.numeroEnDosRenglones('12🏠3'), '12\n🏠3');
      expect(MarcadorEstado.numeroEnDosRenglones('🏠🏠🏠🏠🏠🏠🏠'), '🏠🏠🏠🏠\n🏠…');
    });

    test('dado un número con espacios alrededor, cuando se parte, entonces no cuentan', () {
      expect(MarcadorEstado.numeroEnDosRenglones(' 3307 '), '33\n07');
    });
  });

  group('los nombres de las imágenes', () {
    test('hay uno por variante y no chocan entre sí ni con la etiqueta de «cerca tuyo»', () {
      final nombres = {
        for (final v in VarianteMarcador.values) MarcadorEstado.nombreInsignia(v),
        for (final v in VarianteMarcador.values) MarcadorEstado.nombreCuadrado(v),
        MarcadorEstado.nombreAro,
        MarcadorCercano.nombre('12'),
        MarcadorCercano.nombre('12', VarianteMarcador.rechazo),
      };

      expect(nombres, hasLength(VarianteMarcador.values.length * 2 + 3));
    });

    test('«Sin visita» conserva el nombre de siempre de la etiqueta de «cerca tuyo»', () {
      expect(
        MarcadorCercano.nombre('12', VarianteMarcador.sinVisita),
        MarcadorCercano.nombre('12'),
      );
    });
  });

  group('MarcadorEstado.dibujarInsignia', () {
    testWidgets('dado cada variante, cuando se pinta, entonces es un PNG del tamaño de la '
        'insignia por la escala', (tester) async {
      for (final v in VarianteMarcador.values) {
        for (final escala in [1.0, 2.625]) {
          final png = (await tester.runAsync(
            () => MarcadorEstado.dibujarInsignia(v, escala: escala),
          ))!;
          final imagen = (await tester.runAsync(() => _decodificar(png)))!;

          expect(png.take(4), [0x89, 0x50, 0x4E, 0x47], reason: v.name);
          const lado = MarcadorEstado.ladoInsignia + 2 * MarcadorEstado.margen;
          expect(imagen.width, (lado * escala).ceil(), reason: '${v.name} a $escala');
          expect(imagen.height, (lado * escala).ceil(), reason: '${v.name} a $escala');
          imagen.dispose();
        }
      }
    });

    testWidgets('dado «Sin visita», cuando se pinta, entonces es blanca con borde gris; y '
        '«Rechazo» es roja', (tester) async {
      final sin = (await tester.runAsync(
        () => MarcadorEstado.dibujarInsignia(VarianteMarcador.sinVisita),
      ))!;
      final rechazo = (await tester.runAsync(
        () => MarcadorEstado.dibujarInsignia(VarianteMarcador.rechazo),
      ))!;
      final imgSin = (await tester.runAsync(() => _decodificar(sin)))!;
      final imgRechazo = (await tester.runAsync(() => _decodificar(rechazo)))!;

      // Arriba del círculo, lejos del símbolo: el fondo de cada uno.
      expect((await tester.runAsync(() => _pixel(imgSin, 14, 7)))!, [0xFF, 0xFF, 0xFF, 0xFF]);
      expect((await tester.runAsync(() => _pixel(imgRechazo, 14, 7)))!, [0xA8, 0x31, 0x2A, 0xFF]);
      // Las esquinas de la imagen no se pintan.
      expect((await tester.runAsync(() => _pixel(imgRechazo, 0, 0)))![3], lessThan(8));
      imgSin.dispose();
      imgRechazo.dispose();
    });

    testWidgets('dado un estado de la venta, cuando se pinta, entonces es un cuadrado '
        'redondeado y no un círculo', (tester) async {
      final png = (await tester.runAsync(
        () => MarcadorEstado.dibujarInsignia(VarianteMarcador.ventaCompleta),
      ))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      // Cerca de la esquina del cuadrado (3 + 2): pintada. En un círculo ahí no habría nada.
      expect((await tester.runAsync(() => _pixel(imagen, 6, 6)))!, [0x1F, 0x6E, 0x3A, 0xFF]);
      imagen.dispose();
    });

    testWidgets('dado un estado de la visita, cuando se pinta, entonces es un círculo: la '
        'esquina queda vacía', (tester) async {
      final png = (await tester.runAsync(
        () => MarcadorEstado.dibujarInsignia(VarianteMarcador.entrevistaHecha),
      ))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      expect((await tester.runAsync(() => _pixel(imagen, 5, 5)))![3], lessThan(8));
      imagen.dispose();
    });

    testWidgets('pintar dos veces la misma variante da la misma imagen', (tester) async {
      final a = (await tester.runAsync(
        () => MarcadorEstado.dibujarInsignia(VarianteMarcador.cobranzaPendiente),
      ))!;
      final b = (await tester.runAsync(
        () => MarcadorEstado.dibujarInsignia(VarianteMarcador.cobranzaPendiente),
      ))!;

      expect(a, b);
    });

    testWidgets('dados los nueve, cuando se comparan, entonces no hay dos iguales (se distinguen '
        'también por el símbolo, no solo por el color)', (tester) async {
      final vistos = <String>{};
      for (final v in VarianteMarcador.values) {
        final png = (await tester.runAsync(() => MarcadorEstado.dibujarInsignia(v)))!;
        expect(vistos.add(png.join(',')), isTrue, reason: v.name);
      }
    });
  });

  group('MarcadorEstado.dibujarCuadrado', () {
    testWidgets('dada una variante, cuando se pinta, entonces mide 40 dp más el aire', (
      tester,
    ) async {
      final png = (await tester.runAsync(
        () => MarcadorEstado.dibujarCuadrado(VarianteMarcador.ventaCompleta, escala: 2),
      ))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      const lado = MarcadorEstado.ladoCuadrado + 2 * MarcadorEstado.margen;
      expect(imagen.width, (lado * 2).ceil());
      expect(imagen.height, (lado * 2).ceil());
      imagen.dispose();
    });

    testWidgets('dado «Venta completa», cuando se pinta, entonces el cuadrado es verde y el '
        'símbolo chico va abajo a la derecha, sin tocar el lugar del número', (tester) async {
      final png = (await tester.runAsync(
        () => MarcadorEstado.dibujarCuadrado(VarianteMarcador.ventaCompleta),
      ))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      // Arriba a la izquierda, donde va el número: fondo liso.
      expect((await tester.runAsync(() => _pixel(imagen, 14, 14)))!, [0x1F, 0x6E, 0x3A, 0xFF]);
      expect((await tester.runAsync(() => _pixel(imagen, 20, 20)))!, [0x1F, 0x6E, 0x3A, 0xFF]);
      // El centro de la estrella, abajo a la derecha: blanco.
      expect((await tester.runAsync(() => _pixel(imagen, 32, 32)))!, [0xFF, 0xFF, 0xFF, 0xFF]);
      imagen.dispose();
    });

    testWidgets('dado «Sin visita», cuando se pinta, entonces es blanco con borde gris', (
      tester,
    ) async {
      final png = (await tester.runAsync(
        () => MarcadorEstado.dibujarCuadrado(VarianteMarcador.sinVisita),
      ))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      expect((await tester.runAsync(() => _pixel(imagen, 20, 20)))!, [0xFF, 0xFF, 0xFF, 0xFF]);
      // El borde, a 3 + 1 del lado izquierdo, al medio.
      expect((await tester.runAsync(() => _pixel(imagen, 4, 23)))!, [0x6B, 0x76, 0x88, 0xFF]);
      imagen.dispose();
    });

    testWidgets('dados los nueve, cuando se comparan, entonces no hay dos iguales', (tester) async {
      final vistos = <String>{};
      for (final v in VarianteMarcador.values) {
        final png = (await tester.runAsync(() => MarcadorEstado.dibujarCuadrado(v)))!;
        expect(vistos.add(png.join(',')), isTrue, reason: v.name);
      }
    });
  });

  group('MarcadorEstado.dibujarAro', () {
    testWidgets('es un aro azul por fuera y blanco por dentro (el cuadrado va encima)', (
      tester,
    ) async {
      final png = (await tester.runAsync(MarcadorEstado.dibujarAro))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      const lado = MarcadorEstado.ladoAro + 2 * MarcadorEstado.margen;
      expect(imagen.width, lado.ceil());
      // El borde de afuera, azul; adentro, el blanco que el cuadrado deja a la vista.
      expect((await tester.runAsync(() => _pixel(imagen, 4, 29)))!, [0x00, 0x28, 0x56, 0xFF]);
      expect((await tester.runAsync(() => _pixel(imagen, 7, 29)))!, [0xFF, 0xFF, 0xFF, 0xFF]);
      // Las esquinas, afuera, tampoco.
      expect((await tester.runAsync(() => _pixel(imagen, 0, 0)))![3], lessThan(8));
      imagen.dispose();
    });
  });

  group('MarcadorCercano con estado', () {
    testWidgets('dada una variante, cuando se pinta la etiqueta, entonces la punta y el círculo '
        'toman el color del estado', (tester) async {
      final png = (await tester.runAsync(
        () => MarcadorCercano.dibujar('1234', variante: VarianteMarcador.rechazo),
      ))!;
      final imagen = (await tester.runAsync(() => _decodificar(png)))!;

      final punta = (await tester.runAsync(
        () => _pixel(imagen, imagen.width ~/ 2, imagen.height - 3),
      ))!;
      expect(punta, [0xA8, 0x31, 0x2A, 0xFF]);
      final circulo = (await tester.runAsync(() => _pixel(imagen, 25, 17)))!;
      expect(circulo, [0xA8, 0x31, 0x2A, 0xFF]);
      imagen.dispose();
    });

    testWidgets('dada «Sin visita» o ninguna variante, cuando se pinta, entonces es la imagen de '
        'siempre', (tester) async {
      final base = (await tester.runAsync(() => MarcadorCercano.dibujar('1234')))!;
      final sin = (await tester.runAsync(
        () => MarcadorCercano.dibujar('1234', variante: VarianteMarcador.sinVisita),
      ))!;

      expect(sin, base);
    });
  });
}
