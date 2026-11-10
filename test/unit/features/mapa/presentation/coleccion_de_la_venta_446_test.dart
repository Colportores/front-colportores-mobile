// Cómo se nombra lo vendido en el Historial de la casa (vista 39, #446): «Colección de N libros» en el
// título de la fila (C·03, decisión del 10/11, QA ronda 3) y en el detalle (C·04), con N contando
// libros: un combo suma los suyos (decisión del 10/11, rev 1120). Las filas «Libro» nombran cada libro.
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_historial_de_la_casa.dart';
import 'package:flutter_test/flutter_test.dart';

const _pedro = PersonaDelEvento(nombre: 'Pedro', apellido: 'Gómez');

/// Un combo de 5 libros: 3 distintos, uno de ellos × 3 por unidad.
const _comboDe5 = LineaDeFicha(
  nombre: 'Colección Familia',
  cantidad: 1,
  libros: [
    LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
    LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
    LineaDeFicha(nombre: 'Vida Feliz', cantidad: 3),
  ],
);

VentaDeLaCasa _venta(List<LineaDeFicha> lineas) => VentaDeLaCasa(
  id: 'ven-1',
  fecha: DateTime.utc(2026, 10, 12, 14),
  numeroTalonario: '0038',
  montoCentavos: 480000,
  pagadoCentavos: 0,
  lineas: lineas,
  persona: _pedro,
);

void main() {
  group('cuántos libros', () {
    test('un libro suelto cuenta su cantidad', () {
      expect(
        FormatoHistorialDeLaCasa.coleccion(const [
          LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
        ]),
        'Colección de 1 libro',
      );
      expect(
        FormatoHistorialDeLaCasa.coleccion(const [
          LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 3),
          LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 12),
        ]),
        'Colección de 15 libros',
      );
    });

    test('un combo de 5 libros cuenta 5, no 1', () {
      expect(FormatoHistorialDeLaCasa.coleccion(const [_comboDe5]), 'Colección de 5 libros');
    });

    test('dos combos iguales cuentan sus libros por la cantidad del renglón', () {
      const dos = LineaDeFicha(
        nombre: 'Colección Familia',
        cantidad: 2,
        libros: [
          LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
          LineaDeFicha(nombre: 'Vida Feliz', cantidad: 4),
        ],
      );

      expect(FormatoHistorialDeLaCasa.coleccion(const [dos]), 'Colección de 10 libros');
    });

    test('un combo y un libro suelto se suman', () {
      expect(
        FormatoHistorialDeLaCasa.coleccion(const [
          _comboDe5,
          LineaDeFicha(nombre: 'El Deseado', cantidad: 1),
        ]),
        'Colección de 6 libros',
      );
    });

    test('un combo que no dice sus libros cuenta uno por unidad: nunca «0 libros»', () {
      expect(
        FormatoHistorialDeLaCasa.coleccion(const [
          LineaDeFicha(nombre: 'Colección Familia', cantidad: 2, libros: []),
        ]),
        'Colección de 2 libros',
      );
    });
  });

  group('el título de la fila (C·03)', () {
    test('dice «Colección de N libros · <persona>», como el canvas', () {
      expect(
        FormatoHistorialDeLaCasa.titulo(
          _venta(const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)]),
        ),
        'Colección de 1 libro · Pedro',
      );
      expect(
        FormatoHistorialDeLaCasa.titulo(_venta(const [_comboDe5])),
        'Colección de 5 libros · Pedro',
      );
    });

    test('una venta sin renglones dice «Venta · Pedro», sin «0 libros»', () {
      expect(FormatoHistorialDeLaCasa.titulo(_venta(const [])), 'Venta · Pedro');
    });

    test('el cobro no cambia: «\$ 600 en efectivo · Pedro»', () {
      final cobro = CobroDeLaCasa(
        id: 'cob-1',
        fecha: DateTime.utc(2026, 10, 25),
        montoCentavos: 60000,
        medio: MedioCobranza.efectivo,
        ventaId: 'ven-1',
        persona: _pedro,
      );

      expect(FormatoHistorialDeLaCasa.titulo(cobro), endsWith('en efectivo · Pedro'));
    });
  });

  group('las filas «Libro» del detalle (C·04)', () {
    test('un combo nombra cada libro, con « × k» si es más de uno', () {
      expect(FormatoHistorialDeLaCasa.filasDeLibros(const [_comboDe5]), [
        ('Libro', 'Salud y Hogar'),
        ('Libro', 'Nuestros Hijos'),
        ('Libro', 'Vida Feliz × 3'),
      ]);
    });

    test('dos unidades del combo multiplican la cantidad de cada libro', () {
      const dos = LineaDeFicha(
        nombre: 'Colección Familia',
        cantidad: 2,
        libros: [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
      );

      expect(FormatoHistorialDeLaCasa.filasDeLibros(const [dos]), [('Libro', 'Salud y Hogar × 2')]);
    });

    test('un libro del combo sin nombre en el catálogo va como «Combo · <nombre del combo>»', () {
      const conUnoSinNombre = LineaDeFicha(
        nombre: 'Colección Familia',
        cantidad: 1,
        libros: [
          LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
          LineaDeFicha(nombre: '', cantidad: 2),
          LineaDeFicha(nombre: '', cantidad: 1),
        ],
      );

      expect(FormatoHistorialDeLaCasa.filasDeLibros(const [conUnoSinNombre]), [
        ('Libro', 'Salud y Hogar'),
        ('Combo', 'Colección Familia'),
      ]);
    });

    test('un combo sin libros y un libro suelto', () {
      expect(
        FormatoHistorialDeLaCasa.filasDeLibros(const [
          LineaDeFicha(nombre: 'Colección Familia', cantidad: 1, libros: []),
          LineaDeFicha(nombre: 'El Deseado', cantidad: 2),
        ]),
        [('Combo', 'Colección Familia'), ('Libro', 'El Deseado × 2')],
      );
    });
  });
}
