// Cómo se arma la lista de deptos de un edificio (vista 11·01, HU-UBI-007): grupos por piso, orden
// natural y «Sin número» al final de cada piso.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/services/agrupador_espacios.dart';
import 'package:test/test.dart';

Espacio _e(String id, String? numero, {String? piso, int minuto = 0}) => Espacio(
  id: id,
  ubicacionId: 'u',
  numeroDepto: numero,
  piso: piso,
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 20, 10, minuto),
    updatedAt: DateTime.utc(2026, 10, 20, 10, minuto),
  ),
);

List<String> _ids(GrupoDePiso g) => [for (final e in g.espacios) e.id];

void main() {
  group('Espacio.claveDeNumero', () {
    test('no distingue mayúsculas ni cuenta espacios, tabs o saltos', () {
      expect(Espacio.claveDeNumero('3B'), '3b');
      expect(Espacio.claveDeNumero(' 3 b '), '3b');
      expect(Espacio.claveDeNumero('PB\tA'), 'pba');
      expect(Espacio.claveDeNumero('pb  a'), Espacio.claveDeNumero('PB A'));
    });

    test('«PB-A», «pb a» y «PBA» son el mismo número (canvas 11)', () {
      expect(Espacio.claveDeNumero('PB-A'), 'pba');
      expect(Espacio.claveDeNumero('PB-A'), Espacio.claveDeNumero('pb a'));
      expect(Espacio.claveDeNumero('PB-A'), Espacio.claveDeNumero('PBA'));
    });

    test('los guiones largos que pone el autocorrector (– y —) cuentan como guion', () {
      final largos = '${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}';
      expect(Espacio.claveDeNumero('PB${largos}A'), Espacio.claveDeNumero('PB-A'));
      expect(Espacio.claveDeNumero('PB ${String.fromCharCode(0x2013)} A'), 'pba');
    });

    test('los puntos y las barras siguen contando', () {
      expect(Espacio.claveDeNumero('1.2'), isNot(Espacio.claveDeNumero('12')));
      expect(Espacio.claveDeNumero('1/2'), isNot(Espacio.claveDeNumero('12')));
    });

    test('un número que es solo guiones no tiene clave: es «Sin número»', () {
      expect(Espacio.claveDeNumero('-'), isNull);
      expect(Espacio.claveDeNumero(' - - '), isNull);
    });

    test('sin número (nulo, vacío o en blanco) no hay clave', () {
      expect(Espacio.claveDeNumero(null), isNull);
      expect(Espacio.claveDeNumero(''), isNull);
      expect(Espacio.claveDeNumero('   '), isNull);
      expect(_e('x', '  ').sinNumero, isTrue);
      expect(_e('x', '1').sinNumero, isFalse);
    });
  });

  group('AgrupadorEspacios.porPiso', () {
    test('sin espacios no hay grupos', () {
      expect(AgrupadorEspacios.porPiso(const []), isEmpty);
    });

    test('agrupa por piso y deja «sin piso» al final', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('a', '201', piso: '2'),
        _e('b', '9'),
        _e('c', '101', piso: '1'),
        _e('d', '102', piso: '1'),
      ]);

      expect(grupos.map((g) => g.piso), ['1', '2', null]);
      expect(grupos.last.sinPiso, isTrue);
      expect(_ids(grupos[0]), ['c', 'd']);
      expect(_ids(grupos[1]), ['a']);
      expect(_ids(grupos[2]), ['b']);
    });

    test('los pisos van en orden natural: «PB» primero y después 1, 2, 10', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('a', '1', piso: 'PB'),
        _e('b', '1', piso: '10'),
        _e('c', '1', piso: '2'),
        _e('d', '1', piso: '1'),
      ]);

      expect(grupos.map((g) => g.piso), ['PB', '1', '2', '10']);
    });

    test('«PB» (sin importar mayúsculas) va antes que el piso 1; los otros textos, después de '
        'los números y de la A a la Z; «Sin piso» al final', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('a', '1'),
        _e('b', '1', piso: 'Terraza'),
        _e('c', '1', piso: '10'),
        _e('d', '1', piso: 'azotea'),
        _e('e', '1', piso: '1'),
        _e('f', '1', piso: 'pb'),
      ]);

      expect(grupos.map((g) => g.piso), ['pb', '1', '10', 'azotea', 'Terraza', null]);
    });

    test('el guion del piso cuenta: «-1» no es el piso «1»', () {
      final grupos = AgrupadorEspacios.porPiso([_e('a', '1', piso: '-1'), _e('b', '2', piso: '1')]);

      expect(grupos, hasLength(2));
    });

    test(
      'los espacios y las mayúsculas no cuentan: «1» y « 1 », «pb» y «PB» son el mismo piso',
      () {
        final grupos = AgrupadorEspacios.porPiso([
          _e('a', '1', piso: '1'),
          _e('b', '2', piso: ' 1 '),
          _e('c', '3', piso: 'pb'),
          _e('d', '4', piso: 'PB'),
        ]);

        expect(grupos, hasLength(2));
        expect(_ids(grupos[0]), ['c', 'd']);
        expect(_ids(grupos[1]), ['a', 'b']);
      },
    );

    test('un piso en blanco es «sin piso»', () {
      final grupos = AgrupadorEspacios.porPiso([_e('a', '1', piso: '   '), _e('b', '2')]);

      expect(grupos, hasLength(1));
      expect(grupos.single.sinPiso, isTrue);
    });

    test('dentro de un piso, los números van en orden natural: 2B antes que 10A', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('a', '10A', piso: '1'),
        _e('b', '2B', piso: '1'),
        _e('c', '2A', piso: '1'),
        _e('d', '100', piso: '1'),
        _e('e', '99', piso: '1'),
      ]);

      expect(
        [for (final e in grupos.single.espacios) e.numeroDepto],
        ['2A', '2B', '10A', '99', '100'],
      );
    });

    test('los sin número van después de los numerados, en el orden en que se dieron de alta', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('s2', null, piso: '1', minuto: 5),
        _e('n', '5', piso: '1', minuto: 9),
        _e('s1', null, piso: '1', minuto: 2),
        _e('s3', '  ', piso: '1', minuto: 7),
      ]);

      expect(_ids(grupos.single), ['n', 's1', 's2', 's3']);
    });

    test('dos con el mismo número (datos viejos) quedan juntos, por orden de alta', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('b', '3', piso: '1', minuto: 8),
        _e('a', '3', piso: '1', minuto: 1),
      ]);

      expect(_ids(grupos.single), ['a', 'b']);
    });

    test('números larguísimos no rompen la comparación', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('a', '99999999999999999999999', piso: '1'),
        _e('b', '100000000000000000000000', piso: '1'),
        _e('c', '000000000000000000000007', piso: '1'),
      ]);

      expect(_ids(grupos.single), ['c', 'a', 'b']);
    });

    test('cada grupo conserva el piso como se escribió el primero', () {
      final grupos = AgrupadorEspacios.porPiso([
        _e('a', '1', piso: 'Pb'),
        _e('b', '2', piso: 'PB'),
      ]);

      expect(grupos.single.piso, 'Pb');
    });
  });
}
