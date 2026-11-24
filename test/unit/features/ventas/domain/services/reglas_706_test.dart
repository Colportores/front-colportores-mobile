// #706: las reglas puras de las dos decisiones de Cristian del 11/11 sobre «Venta crece»: «Dos
// motivos» (se juntan con « · », tope de 500 sobre el texto unido) y «Entrega cita» (una cita viva
// por cada grupo de libros diferido, atada a su grupo por la fecha prevista).
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_venta.dart';
import 'package:test/test.dart';

void main() {
  group('«Dos motivos»', () {
    test('une el viejo y el nuevo con « · », sin espacios en los bordes', () {
      expect(
        ReglasDeVenta.motivoUnido('  redondeo ', ' descuento del libro nuevo\n'),
        'redondeo · descuento del libro nuevo',
      );
    });

    test('sin viejo, el nuevo como siempre; sin nuevo, el viejo; los dos en blanco, null', () {
      expect(ReglasDeVenta.motivoUnido(null, ' descuento '), 'descuento');
      expect(ReglasDeVenta.motivoUnido('  ', 'descuento'), 'descuento');
      expect(ReglasDeVenta.motivoUnido('redondeo', '   '), 'redondeo');
      expect(ReglasDeVenta.motivoUnido(null, '  '), isNull);
    });

    test('lo que queda para lo nuevo: 500 menos el viejo y el separador, nunca negativo', () {
      expect(ReglasDeVenta.lugarParaElMotivo(null), 500);
      expect(ReglasDeVenta.lugarParaElMotivo('redondeo'), 500 - 8 - 3);
      expect(ReglasDeVenta.lugarParaElMotivo('v' * 497), 0);
      expect(ReglasDeVenta.lugarParaElMotivo('v' * 500), 0);
    });

    test('no entra si pasa de lo que queda; en el borde entra; sin viejo, nunca', () {
      final viejo = 'v' * 400;
      expect(ReglasDeVenta.motivoNoEntra(viejo, 'n' * 97), isFalse);
      expect(ReglasDeVenta.motivoNoEntra(viejo, 'n' * 98), isTrue);
      expect(ReglasDeVenta.motivoNoEntra(viejo, '  ${'n' * 97}  '), isFalse);
      expect(ReglasDeVenta.motivoNoEntra(null, 'n' * 900), isFalse);
    });

    test('cuenta caracteres visibles (puntos de código), no unidades UTF-16', () {
      expect(ReglasDeVenta.lugarParaElMotivo('😀' * 10), 500 - 10 - 3);
      expect(ReglasDeVenta.motivoNoEntra('😀' * 400, '😀' * 97), isFalse);
    });
  });

  group('«Entrega cita»: cada cita con su grupo', () {
    const sabado = 1000;
    const martes = 2000;

    test('cada cita va al grupo de su misma hora', () {
      expect(
        ReglasDeEntrega.repartirCitas(
          [(id: 'a-2', fecha: martes), (id: 'a-1', fecha: sabado)],
          [sabado, sabado, martes],
        ),
        {'a-2': martes, 'a-1': sabado},
      );
    });

    test('lo sin fecha no tiene cita', () {
      expect(ReglasDeEntrega.repartirCitas([(id: 'a-1', fecha: sabado)], [null, sabado]), {
        'a-1': sabado,
      });
      expect(ReglasDeEntrega.repartirCitas([(id: 'a-1', fecha: sabado)], [null]), isEmpty);
    });

    test('una cita que no coincide (movida fuera del teléfono) toma un grupo con fecha libre', () {
      expect(
        ReglasDeEntrega.repartirCitas(
          [(id: 'a-1', fecha: 1500), (id: 'a-2', fecha: martes)],
          [sabado, martes],
        ),
        {'a-2': martes, 'a-1': sabado},
      );
    });

    test('dos citas a la misma hora: el grupo es de la más antigua; la otra queda sin grupo', () {
      expect(
        ReglasDeEntrega.repartirCitas(
          [(id: 'a-1', fecha: sabado), (id: 'a-2', fecha: sabado)],
          [sabado],
        ),
        {'a-1': sabado},
      );
    });

    test('sin citas o sin pendientes, nada', () {
      expect(ReglasDeEntrega.repartirCitas(const [], [sabado]), isEmpty);
      expect(ReglasDeEntrega.repartirCitas([(id: 'a-1', fecha: sabado)], const []), isEmpty);
    });
  });
}
