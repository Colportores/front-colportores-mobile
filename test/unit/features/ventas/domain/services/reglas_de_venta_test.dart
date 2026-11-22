import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/linea_de_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_venta.dart';
import 'package:test/test.dart';

void main() {
  group('totalCalculado', () {
    test('tres libros a \$ 500 suman \$ 1.500 (HU-VEN-001, venta simple)', () {
      const lineas = [LineaDeProducto(productoId: 'p', cantidad: 3, precioCentavos: 50000)];

      expect(ReglasDeVenta.totalCalculado(lineas), 150000);
    });

    test('un combo es un solo ítem con el precio del combo, por su cantidad', () {
      const lineas = [
        LineaDeCombo(
          comboId: 'c',
          cantidad: 2,
          precioCentavos: 120000,
          componentes: [ComponenteVendido(productoId: 'p')],
        ),
        LineaDeProducto(productoId: 'r', cantidad: 1, precioCentavos: 12000),
      ];

      expect(ReglasDeVenta.totalCalculado(lineas), 252000);
    });

    test('lo que se regala (misioneros sin cobrar) no suma, y el ítem queda con precio 0', () {
      const regalo = LineaDeProducto(
        productoId: 'm',
        cantidad: 3,
        precioCentavos: 15000,
        sinCobrar: true,
      );

      expect(regalo.subtotalCentavos, 0);
      expect(regalo.precioUnitarioGuardado, 0);
      expect(ReglasDeVenta.totalCalculado([regalo]), 0);
    });

    test('solo misioneros: no cuenta como venta; con algo más, sí', () {
      const regalo = LineaDeProducto(
        productoId: 'm',
        cantidad: 3,
        precioCentavos: 0,
        sinCobrar: true,
      );
      const libro = LineaDeProducto(productoId: 'l', cantidad: 1, precioCentavos: 5000);

      expect(ReglasDeVenta.soloMisioneros([regalo, regalo]), isTrue);
      expect(ReglasDeVenta.soloMisioneros([regalo, libro]), isFalse);
      expect(ReglasDeVenta.soloMisioneros([libro]), isFalse);
      expect(ReglasDeVenta.soloMisioneros(const []), isFalse);
    });

    test('sin líneas el total es 0', () {
      expect(ReglasDeVenta.totalCalculado(const []), 0);
    });
  });

  group('motivo del monto a mano', () {
    test('falta si el total cambió y el motivo está en blanco; con el calculado no hace falta', () {
      bool falta(int? cobrado, String motivo) =>
          ReglasDeVenta.faltaElMotivo(calculado: 8900, cobrado: cobrado, motivo: motivo);

      expect(falta(8500, ''), isTrue);
      expect(falta(8500, '  \n '), isTrue);
      expect(falta(9000, ''), isTrue, reason: 'subir el total también es un cambio');
      expect(falta(8500, 'descuento'), isFalse);
      expect(falta(8500, ' x '), isFalse, reason: 'un solo carácter alcanza');
      expect(falta(8900, ''), isFalse, reason: 'el monto calculado no es un cambio');
      expect(falta(null, ''), isFalse);
    });

    test('recorta los espacios y saltos de línea de los bordes', () {
      expect(
        ReglasDeVenta.motivo('  \n descuento por pago en efectivo \n '),
        contains('descuento'),
      );
      expect(ReglasDeVenta.motivo('  \n descuento \n '), 'descuento');
    });

    test('en blanco es null', () {
      expect(ReglasDeVenta.motivo(''), isNull);
      expect(ReglasDeVenta.motivo('   \n\t '), isNull);
    });

    test('frena en 500 puntos de código, no en bytes ni en unidades UTF-16', () {
      final justo = 'á' * 500;
      final emoji = '😀' * 501;

      expect(ReglasDeVenta.motivo(justo), justo);
      expect(ReglasDeVenta.motivo(emoji)!.runes.length, 500);
      expect(ReglasDeVenta.motivo('${'a' * 499} z')!.runes.length, lessThanOrEqualTo(500));
    });
  });

  group('año de Montevideo (talonario único por colportor y año)', () {
    test(
      'el 31/12 a las 23:30 en Uruguay ya es el 01/01 en UTC pero sigue siendo el año viejo',
      () {
        final finDeAnio = DateTime.utc(2027, 1, 1, 2, 30);

        expect(ReglasDeVenta.anioDeMontevideo(finDeAnio), 2026);
      },
    );

    test('el 01/01 a las 00:10 en Uruguay es el año nuevo', () {
      expect(ReglasDeVenta.anioDeMontevideo(DateTime.utc(2027, 1, 1, 3, 10)), 2027);
    });

    test('el día de Montevideo es el que se muestra en «venta del 12/03»', () {
      final dia = ReglasDeVenta.diaDeMontevideo(DateTime.utc(2026, 3, 13, 1));

      expect([dia.day, dia.month], [12, 3]);
    });
  });
}
