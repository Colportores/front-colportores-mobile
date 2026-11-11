// Las reglas puras de una devolución (HU-VEN-004, ADR-002): la ventana de 72 h, qué libros salen de lo
// elegido, cuánto vale lo devuelto y que una venta saldada no acepta devoluciones (nunca queda plata a
// favor del cliente, decisión de Cristian del 03/11). Los números son los del canvas
// 31: una venta de $ 4.500 con «Salud y Hogar» ($ 2.600) y «Nuestros Hijos» ($ 1.900).
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_devolucion.dart';
import 'package:test/test.dart';

const _salud = RenglonDeLaVenta(
  ventaItemId: 'i-salud',
  titulo: 'Salud y Hogar',
  productoId: 'p-salud',
  cantidad: 1,
  precioUnitarioCentavos: 260000,
);
const _hijos = RenglonDeLaVenta(
  ventaItemId: 'i-hijos',
  titulo: 'Nuestros Hijos',
  productoId: 'p-hijos',
  cantidad: 1,
  precioUnitarioCentavos: 190000,
);

VentaParaDevolver _venta({
  int cobrado = 450000,
  List<RenglonDeLaVenta> renglones = const [_salud, _hijos],
}) => VentaParaDevolver(
  ventaId: 'v-1',
  numeroTalonario: '0042',
  fecha: DateTime.utc(2026, 10, 12, 21, 20),
  montoTotalCentavos: 450000,
  cobradoCentavos: cobrado,
  renglones: renglones,
);

void main() {
  group('la ventana de 72 h', () {
    final venta = DateTime.utc(2026, 10, 12, 21, 20);

    test('dado que pasaron 71 h, cuando se pregunta, está en plazo', () {
      expect(
        ReglasDeDevolucion.estaFueraDePlazo(venta, venta.add(const Duration(hours: 71))),
        isFalse,
      );
    });

    test('dado que pasaron 72 h justas, cuando se pregunta, todavía se puede', () {
      expect(
        ReglasDeDevolucion.estaFueraDePlazo(venta, venta.add(const Duration(hours: 72))),
        isFalse,
      );
    });

    test('dado que pasaron 72 h y un milisegundo, cuando se pregunta, está fuera de plazo', () {
      expect(
        ReglasDeDevolucion.estaFueraDePlazo(
          venta,
          venta.add(const Duration(hours: 72, milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test(
      'dado la venta del canvas, cuando se calcula el límite, es el martes 15/10 a las 21:20',
      () {
        expect(ReglasDeDevolucion.limiteDelPlazo(venta), DateTime.utc(2026, 10, 15, 21, 20));
      },
    );
  });

  group('el motivo', () {
    test('dado un motivo con espacios y saltos en los bordes, cuando se limpia, los pierde', () {
      expect(ReglasDeDevolucion.motivo('  no le gustó \n'), 'no le gustó');
    });

    test('dado un motivo en blanco, cuando se limpia, es null', () {
      expect(ReglasDeDevolucion.motivo('   \n '), isNull);
      expect(ReglasDeDevolucion.motivo(null), isNull);
    });

    test('dado un motivo de 600 caracteres, cuando se limpia, se corta en 500', () {
      expect(ReglasDeDevolucion.motivo('a' * 600)!.length, 500);
    });
  });

  group('las cuentas de la devolución (canvas 31)', () {
    test(
      'dado que pagó todo y devuelve Nuestros Hijos, no se le devuelve plata: 1.900 sin devolver',
      () {
        final c = ReglasDeDevolucion.cuenta(_venta(), {'i-hijos': 1});

        expect(c.valorCentavos, 190000);
        expect(c.seQuedaConCentavos, 260000);
        expect(c.yaPagoCentavos, 450000);
        expect(c.sinDevolverCentavos, 190000);
        expect(c.haySinDevolver, isTrue);
        expect(c.saldoNuevoCentavos, 0);
        expect(c.esTotal, isFalse);
      },
    );

    test('31-06: dado que pagó 1.000 y devuelve Nuestros Hijos, queda un saldo de 1.600', () {
      final c = ReglasDeDevolucion.cuenta(_venta(cobrado: 100000), {'i-hijos': 1});

      expect(c.seQuedaConCentavos, 260000);
      expect(c.saldoNuevoCentavos, 160000);
      expect(c.sinDevolverCentavos, 0);
      expect(c.haySinDevolver, isFalse);
    });

    test(
      'dado que lo devuelto vale más que el saldo, el saldo queda en 0 y la diferencia no se devuelve',
      () {
        // Debe 1.200 (pagó 3.300 de 4.500) y devuelve un libro de 1.900: se descuenta hasta el saldo.
        final c = ReglasDeDevolucion.cuenta(_venta(cobrado: 330000), {'i-hijos': 1});

        expect(c.valorCentavos, 190000);
        expect(c.seQuedaConCentavos, 260000);
        expect(c.saldoNuevoCentavos, 0);
        expect(c.sinDevolverCentavos, 70000);
      },
    );

    test('dado que lo devuelto cabe justo en el saldo, la venta queda saldada sin diferencia', () {
      // Debe 1.900 (pagó 2.600) y devuelve el libro de 1.900.
      final c = ReglasDeDevolucion.cuenta(_venta(cobrado: 260000), {'i-hijos': 1});

      expect(c.saldoNuevoCentavos, 0);
      expect(c.sinDevolverCentavos, 0);
    });

    test('31-07: dado que devuelve todo, se queda con 0 y los 4.500 pagados no se devuelven', () {
      final c = ReglasDeDevolucion.cuenta(_venta(), {'i-salud': 1, 'i-hijos': 1});

      expect(c.seQuedaConCentavos, 0);
      expect(c.sinDevolverCentavos, 450000);
      expect(c.saldoNuevoCentavos, 0);
      expect(c.esTotal, isTrue);
    });

    test('dado que no pagó nada y devuelve todo, no hay plata sin devolver ni saldo', () {
      final c = ReglasDeDevolucion.cuenta(_venta(cobrado: 0), {'i-salud': 1, 'i-hijos': 1});

      expect(c.sinDevolverCentavos, 0);
      expect(c.saldoNuevoCentavos, 0);
      expect(c.esTotal, isTrue);
    });

    test('dado que nada elegido, la cuenta está vacía', () {
      final c = ReglasDeDevolucion.cuenta(_venta(), const {});

      expect(c.estaVacia, isTrue);
      expect(c.haySinDevolver, isFalse);
      expect(c.esTotal, isFalse);
    });

    test(
      'dado que ya devolvió Salud y Hogar y pagó 1.000, devolver lo que queda deja el saldo en 0',
      () {
        final c = ReglasDeDevolucion.cuenta(
          _venta(
            cobrado: 100000,
            renglones: const [
              RenglonDeLaVenta(
                ventaItemId: 'i-salud',
                titulo: 'Salud y Hogar',
                productoId: 'p-salud',
                cantidad: 1,
                precioUnitarioCentavos: 260000,
                unidadesDevueltas: 1,
              ),
              _hijos,
            ],
          ),
          {'i-hijos': 1},
        );

        expect(c.seQuedaConCentavos, 0);
        expect(c.saldoNuevoCentavos, 0);
        expect(c.sinDevolverCentavos, 100000);
      },
    );

    test('dado más unidades que las disponibles, la cuenta las recorta a lo que queda', () {
      final c = ReglasDeDevolucion.cuenta(_venta(), {'i-hijos': 5});

      expect(c.unidades, 1);
      expect(c.valorCentavos, 190000);
    });

    test('dado un renglón que no es de la venta, la cuenta lo ignora', () {
      final c = ReglasDeDevolucion.cuenta(_venta(), {'otro': 2});

      expect(c.estaVacia, isTrue);
    });

    test('dado el monto puesto a mano más bajo que los renglones, devolver todo deja en 0', () {
      final venta = VentaParaDevolver(
        ventaId: 'v-1',
        numeroTalonario: '0042',
        fecha: DateTime.utc(2026, 10, 12),
        montoTotalCentavos: 300000,
        cobradoCentavos: 300000,
        renglones: const [_salud, _hijos],
      );

      final c = ReglasDeDevolucion.cuenta(venta, {'i-salud': 1, 'i-hijos': 1});

      expect(c.seQuedaConCentavos, 0);
      expect(c.sinDevolverCentavos, 300000);
    });
  });

  group('las cuentas de la venta', () {
    test('dado una venta sin devoluciones, el saldo es el monto menos lo cobrado', () {
      const c = CuentaDeLaVenta(montoTotalCentavos: 450000, cobradoCentavos: 100000);

      expect(c.seQuedaConCentavos, 450000);
      expect(c.yaPagoCentavos, 100000);
      expect(c.saldoCentavos, 350000);
      expect(c.estaSaldada, isFalse);
    });

    test('dado una devolución, lo devuelto baja lo que se queda y con él el saldo', () {
      const c = CuentaDeLaVenta(
        montoTotalCentavos: 450000,
        cobradoCentavos: 100000,
        devueltoCentavos: 190000,
      );

      expect(c.seQuedaConCentavos, 260000);
      expect(c.saldoCentavos, 160000);
      expect(c.estaSaldada, isFalse);
    });

    test('dado que pagó todo lo que se queda, el saldo es 0 y la venta está saldada', () {
      const pagada = CuentaDeLaVenta(montoTotalCentavos: 450000, cobradoCentavos: 450000);
      const conDevolucion = CuentaDeLaVenta(
        montoTotalCentavos: 450000,
        cobradoCentavos: 260000,
        devueltoCentavos: 190000,
      );

      expect(pagada.saldoCentavos, 0);
      expect(pagada.estaSaldada, isTrue);
      expect(conDevolucion.saldoCentavos, 0);
      expect(conDevolucion.estaSaldada, isTrue);
    });

    test('dado más devuelto de lo que debía, nunca queda plata a favor: el saldo no baja de 0', () {
      const c = CuentaDeLaVenta(
        montoTotalCentavos: 450000,
        cobradoCentavos: 450000,
        devueltoCentavos: 190000,
      );

      expect(c.saldoCentavos, 0);
      expect(c.yaPagoCentavos, 450000);
    });

    test('dado una venta de \$ 0, está saldada (el servidor tampoco le acepta devoluciones)', () {
      const c = CuentaDeLaVenta(montoTotalCentavos: 0, cobradoCentavos: 0);

      expect(c.estaSaldada, isTrue);
    });

    test('dado más devuelto que vendido, lo que se queda no baja de cero', () {
      const c = CuentaDeLaVenta(
        montoTotalCentavos: 100000,
        cobradoCentavos: 0,
        devueltoCentavos: 500000,
      );

      expect(c.seQuedaConCentavos, 0);
      expect(c.saldoCentavos, 0);
    });

    test('dado una venta para devolver, su cuenta y su saldada salen de la misma fórmula', () {
      expect(_venta(cobrado: 100000).estaSaldada, isFalse);
      expect(_venta(cobrado: 100000).saldoCentavos, 350000);
      expect(_venta().estaSaldada, isTrue);
      expect(_venta().yaPagoCentavos, 450000);
    });
  });

  group('los libros que vuelven', () {
    test('dado un producto suelto, cuando devuelve 2, vuelve un elemento con cantidad 2', () {
      const renglon = RenglonDeLaVenta(
        ventaItemId: 'i-1',
        titulo: 'Vida Feliz',
        productoId: 'p-1',
        cantidad: 3,
        precioUnitarioCentavos: 50000,
      );

      expect(ReglasDeDevolucion.librosDe(renglon, 2), const [
        ProductoDevuelto(productoId: 'p-1', ventaItemId: 'i-1', cantidad: 2),
      ]);
    });

    test('dado un combo, cuando devuelve 2 unidades, vuelve cada libro con su cantidad por 2', () {
      const combo = RenglonDeLaVenta(
        ventaItemId: 'i-combo',
        titulo: 'Colección',
        componentes: [
          ComponenteVendido(productoId: 'p-a'),
          ComponenteVendido(productoId: 'p-b', cantidad: 2),
        ],
        cantidad: 3,
        precioUnitarioCentavos: 90000,
      );

      expect(ReglasDeDevolucion.librosDe(combo, 2), const [
        ProductoDevuelto(productoId: 'p-a', ventaItemId: 'i-combo', cantidad: 2),
        ProductoDevuelto(productoId: 'p-b', ventaItemId: 'i-combo', cantidad: 4),
      ]);
    });

    test('dado un combo con el mismo libro dos veces, es un solo elemento (par único)', () {
      const combo = RenglonDeLaVenta(
        ventaItemId: 'i-combo',
        titulo: 'Colección',
        componentes: [
          ComponenteVendido(productoId: 'p-a'),
          ComponenteVendido(productoId: 'p-a'),
        ],
        cantidad: 1,
        precioUnitarioCentavos: 90000,
      );

      expect(ReglasDeDevolucion.librosDe(combo, 1), const [
        ProductoDevuelto(productoId: 'p-a', ventaItemId: 'i-combo', cantidad: 2),
      ]);
    });

    test('dado 0 unidades, no vuelve ningún libro', () {
      expect(ReglasDeDevolucion.librosDe(_salud, 0), isEmpty);
    });

    test(
      'dado un combo devuelto del todo, las unidades devueltas son las veces que volvió entero',
      () {
        const componentes = [
          ComponenteVendido(productoId: 'p-a'),
          ComponenteVendido(productoId: 'p-b', cantidad: 2),
        ];

        expect(
          ReglasDeDevolucion.unidadesDevueltas(
            ventaItemId: 'i-combo',
            productoId: null,
            componentes: componentes,
            devueltos: const [
              ProductoDevuelto(productoId: 'p-a', ventaItemId: 'i-combo', cantidad: 2),
              ProductoDevuelto(productoId: 'p-b', ventaItemId: 'i-combo', cantidad: 4),
            ],
          ),
          2,
        );
      },
    );

    test('dado un combo devuelto a medias, no cuenta como unidad devuelta', () {
      expect(
        ReglasDeDevolucion.unidadesDevueltas(
          ventaItemId: 'i-combo',
          productoId: null,
          componentes: const [
            ComponenteVendido(productoId: 'p-a'),
            ComponenteVendido(productoId: 'p-b'),
          ],
          devueltos: const [
            ProductoDevuelto(productoId: 'p-a', ventaItemId: 'i-combo', cantidad: 1),
          ],
        ),
        0,
      );
    });

    test('dado libros de otro renglón, las unidades devueltas de este no los cuentan', () {
      expect(
        ReglasDeDevolucion.unidadesDevueltas(
          ventaItemId: 'i-1',
          productoId: 'p-1',
          componentes: null,
          devueltos: const [
            ProductoDevuelto(productoId: 'p-1', ventaItemId: 'i-otro', cantidad: 2),
            ProductoDevuelto(productoId: 'p-1', ventaItemId: 'i-1', cantidad: 1),
          ],
        ),
        1,
      );
    });

    test('dado varias devoluciones, los libros por producto suman los renglones', () {
      expect(
        ReglasDeDevolucion.librosPorProducto(const [
          ProductoDevuelto(productoId: 'p-1', ventaItemId: 'i-1', cantidad: 2),
          ProductoDevuelto(productoId: 'p-1', ventaItemId: 'i-2', cantidad: 1),
          ProductoDevuelto(productoId: 'p-2', ventaItemId: 'i-3', cantidad: 4),
        ]),
        {'p-1': 3, 'p-2': 4},
      );
    });
  });

  group('lo elegido', () {
    test('dado unidades dentro de lo disponible, es válido', () {
      expect(ReglasDeDevolucion.esValida(_venta(), {'i-hijos': 1}), isTrue);
    });

    test('dado nada elegido o solo ceros, no es válido', () {
      expect(ReglasDeDevolucion.esValida(_venta(), const {}), isFalse);
      expect(ReglasDeDevolucion.esValida(_venta(), {'i-hijos': 0}), isFalse);
    });

    test('dado más de lo disponible, un renglón ajeno o un negativo, no es válido', () {
      expect(ReglasDeDevolucion.esValida(_venta(), {'i-hijos': 2}), isFalse);
      expect(ReglasDeDevolucion.esValida(_venta(), {'otro': 1}), isFalse);
      expect(ReglasDeDevolucion.esValida(_venta(), {'i-hijos': -1}), isFalse);
    });

    test('dado una elección vieja, cuando se ajusta, pierde lo que ya no existe o ya volvió', () {
      final venta = _venta(
        renglones: const [
          RenglonDeLaVenta(
            ventaItemId: 'i-salud',
            titulo: 'Salud y Hogar',
            productoId: 'p-salud',
            cantidad: 1,
            precioUnitarioCentavos: 260000,
            unidadesDevueltas: 1,
          ),
          _hijos,
        ],
      );

      expect(ReglasDeDevolucion.ajustar(venta, {'i-salud': 1, 'i-hijos': 3, 'otro': 1}), {
        'i-hijos': 1,
      });
    });

    test('dado una elección, los productos salen en el orden de la venta', () {
      expect(ReglasDeDevolucion.productosDe(_venta(), {'i-hijos': 1, 'i-salud': 1}), const [
        ProductoDevuelto(productoId: 'p-salud', ventaItemId: 'i-salud', cantidad: 1),
        ProductoDevuelto(productoId: 'p-hijos', ventaItemId: 'i-hijos', cantidad: 1),
      ]);
    });
  });

  group('la venta para devolver', () {
    test('dado que todo volvió, está toda devuelta y el valor es el monto de la venta', () {
      final venta = _venta(
        renglones: const [
          RenglonDeLaVenta(
            ventaItemId: 'i-salud',
            titulo: 'Salud y Hogar',
            productoId: 'p-salud',
            cantidad: 1,
            precioUnitarioCentavos: 260000,
            unidadesDevueltas: 1,
          ),
          RenglonDeLaVenta(
            ventaItemId: 'i-hijos',
            titulo: 'Nuestros Hijos',
            productoId: 'p-hijos',
            cantidad: 1,
            precioUnitarioCentavos: 190000,
            unidadesDevueltas: 1,
          ),
        ],
      );

      expect(venta.estaTodoDevuelto, isTrue);
      expect(venta.devueltoCentavos, 450000);
      expect(venta.seQuedaConCentavos, 0);
      expect(venta.unidadesDisponibles, 0);
    });

    test('dado una venta sin renglones, no cuenta como devuelta del todo', () {
      expect(_venta(renglones: const []).estaTodoDevuelto, isFalse);
    });

    test('dado una devolución parcial, las unidades disponibles bajan', () {
      final venta = _venta(
        renglones: const [
          RenglonDeLaVenta(
            ventaItemId: 'i-1',
            titulo: 'Vida Feliz',
            productoId: 'p-1',
            cantidad: 3,
            precioUnitarioCentavos: 50000,
            unidadesDevueltas: 2,
          ),
        ],
      );

      expect(venta.unidadesDisponibles, 1);
      expect(venta.renglones.single.disponibles, 1);
      expect(venta.renglones.single.valorDevueltoCentavos, 100000);
    });
  });
}
