// HU-CAT-006: la regla de precios (excepción de la ciudad o precio general), el orden, la búsqueda,
// el día de Montevideo, la ciudad de entrada y la antigüedad de los precios.
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/antiguedad_de_precios.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/resolvedor_de_precios.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/selector_de_ciudad_inicial.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/precios_falsos.dart';

const _hoy = '2026-10-28';

List<ItemDePrecio> _resolver(CatalogoLocal c, {String dia = _hoy}) =>
    ResolvedorDePrecios.resolver(c, dia: dia);

PrecioDeProducto _producto(List<ItemDePrecio> items, String id) =>
    items.whereType<PrecioDeProducto>().firstWhere((p) => p.id == id);

void main() {
  group('precio de un producto', () {
    test('la excepción de la ciudad gana al precio general', () {
      final deseado = _producto(_resolver(catalogoDeLaVista26()), 'p-deseado');
      expect(deseado.centavos, 480000);
      expect(deseado.origen, OrigenDelPrecio.ciudad);
    });

    test('sin excepción rige el precio general', () {
      final camino = _producto(_resolver(catalogoDeLaVista26()), 'p-camino');
      expect(camino.centavos, 120000);
      expect(camino.origen, OrigenDelPrecio.general);
    });

    test('sin ningún precio vigente no se ofrece', () {
      final ids = _resolver(catalogoDeLaVista26()).map((i) => i.id);
      expect(ids, isNot(contains('p-sin-precio')));
    });

    test('una excepción vencida cede al precio general', () {
      const c = CatalogoLocal(
        productos: [ProductoDelCatalogo(id: 'a', nombre: 'A', tipo: TipoDeProducto.libro)],
        excepciones: [
          PrecioDelCatalogo(
            id: 'e',
            productoId: 'a',
            centavos: 100,
            validoDesde: '2026-01-01',
            validoHasta: '2026-10-27',
          ),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g', productoId: 'a', centavos: 200, validoDesde: '2026-01-01'),
        ],
      );
      expect(_producto(_resolver(c), 'a').centavos, 200);
      // El último día de vigencia todavía vale.
      expect(_producto(_resolver(c, dia: '2026-10-27'), 'a').centavos, 100);
    });

    test('un precio que empieza mañana todavía no vale', () {
      const c = CatalogoLocal(
        productos: [ProductoDelCatalogo(id: 'a', nombre: 'A', tipo: TipoDeProducto.libro)],
        generales: [
          PrecioDelCatalogo(id: 'g', productoId: 'a', centavos: 200, validoDesde: '2026-10-29'),
        ],
      );
      expect(_resolver(c), isEmpty);
      expect(_resolver(c, dia: '2026-10-29'), hasLength(1));
    });

    test('si por un dato roto valen dos, gana el que empezó después, siempre el mismo', () {
      const c = CatalogoLocal(
        productos: [ProductoDelCatalogo(id: 'a', nombre: 'A', tipo: TipoDeProducto.libro)],
        generales: [
          PrecioDelCatalogo(id: 'g1', productoId: 'a', centavos: 100, validoDesde: '2026-01-01'),
          PrecioDelCatalogo(id: 'g2', productoId: 'a', centavos: 200, validoDesde: '2026-05-01'),
          PrecioDelCatalogo(id: 'g3', productoId: 'a', centavos: 300, validoDesde: '2026-05-01'),
        ],
      );
      expect(_producto(_resolver(c), 'a').centavos, 300);
    });

    test('el material de trabajo, el tipo desconocido y los dados de baja no se ofrecen', () {
      const c = CatalogoLocal(
        productos: [
          ProductoDelCatalogo(id: 'm', nombre: 'Material', tipo: TipoDeProducto.material),
          ProductoDelCatalogo(id: 'o', nombre: 'Otro', tipo: TipoDeProducto.otro),
          ProductoDelCatalogo(
            id: 'b',
            nombre: 'Baja',
            tipo: TipoDeProducto.libro,
            dadoDeBaja: true,
          ),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g1', productoId: 'm', centavos: 1, validoDesde: '2026-01-01'),
          PrecioDelCatalogo(id: 'g2', productoId: 'o', centavos: 1, validoDesde: '2026-01-01'),
          PrecioDelCatalogo(id: 'g3', productoId: 'b', centavos: 1, validoDesde: '2026-01-01'),
        ],
      );
      expect(_resolver(c), isEmpty);
    });

    test('un código en blanco es sin código', () {
      const c = CatalogoLocal(
        productos: [
          ProductoDelCatalogo(id: 'a', nombre: 'A', tipo: TipoDeProducto.libro, codigoEditor: '  '),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g', productoId: 'a', centavos: 1, validoDesde: '2026-01-01'),
        ],
      );
      expect(_producto(_resolver(c), 'a').codigoEditor, isNull);
    });
  });

  group('combos', () {
    test('un combo es un solo ítem con su precio y lo que lleva', () {
      final items = _resolver(catalogoDeLaVista26());
      final combo = items.whereType<PrecioDeCombo>().firstWhere((c) => c.id == 'k-2');
      expect(combo.centavos, 890000);
      expect(combo.origen, OrigenDelPrecio.ciudad);
      expect(combo.librosAElegir, 2);
      expect(combo.componentes.map((c) => c.nombre), [
        'Misionero Esperanza',
        'Revista Vida y Salud',
      ]);
    });

    test('van primero, de menos a más libros a elegir, y después los productos por nombre', () {
      final items = _resolver(catalogoDeLaVista26());
      expect(items.map((i) => i.id), [
        'k-fijo',
        'k-2',
        'p-camino',
        'p-deseado',
        'p-misionero',
        'p-revista',
      ]);
    });

    test('un componente cuyo producto no llegó se omite y el combo se ofrece igual', () {
      const c = CatalogoLocal(
        combos: [
          ComboDelCatalogo(
            id: 'k',
            nombre: 'K',
            componentes: [ComponenteDelCombo(productoId: 'no-llego')],
          ),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g', comboId: 'k', centavos: 5, validoDesde: '2026-01-01'),
        ],
      );
      final combo = _resolver(c).single as PrecioDeCombo;
      expect(combo.componentes, isEmpty);
    });

    test('un combo sin precio vigente o dado de baja no se ofrece', () {
      const c = CatalogoLocal(
        combos: [
          ComboDelCatalogo(id: 'k1', nombre: 'Sin precio'),
          ComboDelCatalogo(id: 'k2', nombre: 'Baja', dadoDeBaja: true),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g', comboId: 'k2', centavos: 5, validoDesde: '2026-01-01'),
        ],
      );
      expect(_resolver(c), isEmpty);
    });
  });

  group('pestañas', () {
    final items = _resolver(catalogoDeLaVista26());

    test('Colecciones solo tiene combos', () {
      expect(
        ResolvedorDePrecios.deLaCategoria(items, CategoriaDePrecios.colecciones).map((i) => i.id),
        ['k-fijo', 'k-2'],
      );
    });

    test('Libros, Misioneros y Revistas', () {
      List<String> ids(CategoriaDePrecios c) =>
          ResolvedorDePrecios.deLaCategoria(items, c).map((i) => i.id).toList();
      expect(ids(CategoriaDePrecios.libros), ['p-camino', 'p-deseado']);
      expect(ids(CategoriaDePrecios.misioneros), ['p-misionero']);
      expect(ids(CategoriaDePrecios.revistas), ['p-revista']);
    });

    test('un libro marcado misionero va en Misioneros', () {
      const c = CatalogoLocal(
        productos: [
          ProductoDelCatalogo(id: 'a', nombre: 'A', tipo: TipoDeProducto.libro, esMisionero: true),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g', productoId: 'a', centavos: 1, validoDesde: '2026-01-01'),
        ],
      );
      expect(
        ResolvedorDePrecios.deLaCategoria(_resolver(c), CategoriaDePrecios.misioneros),
        hasLength(1),
      );
    });
  });

  group('búsqueda', () {
    final libros = ResolvedorDePrecios.deLaCategoria(
      _resolver(catalogoDeLaVista26()),
      CategoriaDePrecios.libros,
    );

    test('por nombre, sin importar mayúsculas ni tildes', () {
      expect(ResolvedorDePrecios.buscar(libros, 'DESEADO').map((i) => i.id), ['p-deseado']);
      expect(ResolvedorDePrecios.buscar(libros, 'camíno').map((i) => i.id), ['p-camino']);
    });

    test('por código', () {
      expect(ResolvedorDePrecios.buscar(libros, 'aces-02').map((i) => i.id), ['p-deseado']);
    });

    test('todas las palabras tienen que estar, en cualquier orden', () {
      expect(ResolvedorDePrecios.buscar(libros, 'cristo camino').map((i) => i.id), ['p-camino']);
      expect(ResolvedorDePrecios.buscar(libros, 'cristo deseado'), isEmpty);
    });

    test('una consulta en blanco deja todo; sin coincidencias, nada', () {
      expect(ResolvedorDePrecios.buscar(libros, '   '), libros);
      expect(ResolvedorDePrecios.buscar(libros, 'zzz'), isEmpty);
    });

    test('la ñ cuenta como n', () {
      expect(ResolvedorDePrecios.normalizar('  Año  Nuevo '), 'ano nuevo');
    });
  });

  group('día de Montevideo', () {
    test('es UTC-3 todo el año', () {
      expect(ResolvedorDePrecios.diaDeMontevideo(DateTime.utc(2026, 10, 28, 2, 59)), '2026-10-27');
      expect(ResolvedorDePrecios.diaDeMontevideo(DateTime.utc(2026, 10, 28, 3)), '2026-10-28');
      expect(ResolvedorDePrecios.diaDeMontevideo(DateTime.utc(2026, 1, 1, 1)), '2025-12-31');
    });
  });

  group('ciudad de entrada', () {
    const contexto = ContextoDeCiudades(
      ciudades: [cMontevideo, cCanelones],
      ciudadDeMiZonaId: 'ciu-mvd',
    );

    test('donde está, si el GPS la ubica en una ciudad de sus campañas', () {
      final r = SelectorDeCiudadInicial.elegir(contexto: contexto, ciudadDelGpsId: 'ciu-can');
      expect(r.ciudad, cCanelones);
      expect(r.origen, OrigenDeLaCiudad.gps);
    });

    test('sin GPS, la ciudad de su zona', () {
      final r = SelectorDeCiudadInicial.elegir(contexto: contexto);
      expect(r.ciudad, cMontevideo);
      expect(r.origen, OrigenDeLaCiudad.zona);
    });

    test('un GPS fuera de sus campañas es como no tener GPS', () {
      final r = SelectorDeCiudadInicial.elegir(contexto: contexto, ciudadDelGpsId: 'ciu-otra');
      expect(r.origen, OrigenDeLaCiudad.zona);
    });

    test('sin zona ni GPS no hay ciudad: la elige ella', () {
      final r = SelectorDeCiudadInicial.elegir(
        contexto: const ContextoDeCiudades(ciudades: [cMontevideo, cCanelones]),
      );
      expect(r.ciudad, isNull);
      expect(r.origen, isNull);
    });

    test('una zona de una ciudad que ya no es de sus campañas tampoco cuenta', () {
      final r = SelectorDeCiudadInicial.elegir(
        contexto: const ContextoDeCiudades(ciudades: [cCanelones], ciudadDeMiZonaId: 'ciu-mvd'),
      );
      expect(r.ciudad, isNull);
    });
  });

  group('antigüedad de los precios', () {
    final bajada = DateTime(2026, 10, 1, 12);

    test('cuenta días enteros', () {
      expect(AntiguedadDePrecios.dias(bajada, DateTime(2026, 10, 1, 23)), 0);
      expect(AntiguedadDePrecios.dias(bajada, DateTime(2026, 10, 16, 12)), 15);
    });

    test('el aviso se pone fuerte justo a los N días', () {
      expect(AntiguedadDePrecios.esFuerte(bajada, DateTime(2026, 10, 16, 11, 59)), isFalse);
      expect(AntiguedadDePrecios.esFuerte(bajada, DateTime(2026, 10, 16, 12)), isTrue);
      expect(AntiguedadDePrecios.esFuerte(bajada, DateTime(2026, 10, 6, 12), umbral: 5), isTrue);
    });

    test('un reloj corrido hacia atrás da 0 y nunca es fuerte', () {
      final ahora = DateTime(2026, 9, 1);
      expect(AntiguedadDePrecios.dias(bajada, ahora), 0);
      expect(AntiguedadDePrecios.esFuerte(bajada, ahora), isFalse);
    });
  });
}
