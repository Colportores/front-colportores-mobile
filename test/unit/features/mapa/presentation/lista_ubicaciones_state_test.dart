// HU-UBI-002 / vista 05: los filtros de la lista y lo que cuentan en el botón «Filtros».
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FiltrosLista', () {
    test('dado sin filtros, entonces no hay nada que limpiar y el contador es 0', () {
      const f = FiltrosLista();

      expect(f.cantidadActivos, 0);
      expect(f.hayFiltros, isFalse);
      expect(f.hayFiltrosOBusqueda, isFalse);
      expect(f.limite, ConsultaListaUbicaciones.tamanoPagina);
    });

    test('dado un chip por cada filtro, entonces el contador suma tipos, estados, ciudad, '
        'proximidad y bajas, pero no la búsqueda ni el orden', () {
      const f = FiltrosLista(
        tipos: {TipoUbicacion.casa, TipoUbicacion.negocio},
        estados: {EstadoCasa.rechazo},
        ciudadId: 'ciu-mvd',
        proximidad: ProximidadLista.trescientos,
        incluirBajas: true,
        busqueda: 'rivadavia',
        orden: OrdenListaUbicaciones.cercania,
      );

      expect(f.cantidadActivos, 6);
      expect(f.hayFiltros, isTrue);
    });

    test(
      'dado solo una búsqueda, entonces no es un filtro de la hoja pero sí hay algo que limpiar',
      () {
        const f = FiltrosLista(busqueda: '  col ');

        expect(f.hayFiltros, isFalse);
        expect(f.hayFiltrosOBusqueda, isTrue);
        expect(const FiltrosLista(busqueda: '   ').hayFiltrosOBusqueda, isFalse);
      },
    );

    test(
      'dado copyWith, cuando se pasa sinCiudad, entonces quita la ciudad; sin ese flag, un null no la toca',
      () {
        const f = FiltrosLista(ciudadId: 'ciu-mvd');

        expect(f.copyWith().ciudadId, 'ciu-mvd');
        expect(f.copyWith(ciudadId: 'ciu-can').ciudadId, 'ciu-can');
        expect(f.copyWith(sinCiudad: true).ciudadId, isNull);
      },
    );

    test('dado sinFiltros, entonces conserva la búsqueda y el orden', () {
      final f = const FiltrosLista(
        tipos: {TipoUbicacion.casa},
        busqueda: 'col',
        orden: OrdenListaUbicaciones.cercania,
        incluirBajas: true,
      ).sinFiltros();

      expect(f.cantidadActivos, 0);
      expect(f.busqueda, 'col');
      expect(f.orden, OrdenListaUbicaciones.cercania);
    });

    test('dado la consulta, entonces lleva el radio de la proximidad y puede pisar el límite', () {
      const posicion = Coordenadas(lat: -34.9, lon: -56.15);
      const f = FiltrosLista(
        tipos: {TipoUbicacion.edificio},
        proximidad: ProximidadLista.unKilometro,
        busqueda: 'x',
        limite: 100,
      );

      final c = f.consulta(colportorId: 'col-1', posicion: posicion);
      final uno = f.consulta(colportorId: 'col-1', posicion: posicion, limite: 1);

      expect(c.radioMaxMetros, 1000);
      expect(c.tipos, {TipoUbicacion.edificio});
      expect(c.posicion, posicion);
      expect(c.limite, 100);
      expect(uno.limite, 1);
      expect(const FiltrosLista().consulta(colportorId: 'col-1').radioMaxMetros, isNull);
    });

    test('dos filtros iguales son iguales (para no reabrir la lista por nada)', () {
      expect(
        FiltrosLista(
          tipos: {TipoUbicacion.values.byName('casa')},
          estados: {EstadoCasa.values.byName('rechazo')},
        ),
        FiltrosLista(
          tipos: {TipoUbicacion.values.byName('casa')},
          estados: {EstadoCasa.values.byName('rechazo')},
        ),
      );
      expect(const FiltrosLista(), isNot(const FiltrosLista(incluirBajas: true)));
    });
  });

  group('ProximidadLista', () {
    test('ofrece 100 m, 300 m y 1 km, y «cualquiera» no filtra', () {
      expect([for (final p in ProximidadLista.values) p.metros], [null, 100, 300, 1000]);
    });
  });

  group('ListaUbicacionesState', () {
    test('dado el arranque, entonces está cargando y sin GPS pedido', () {
      const s = ListaUbicacionesState();

      expect(s.cargando, isTrue);
      expect(s.gps, EstadoGpsLista.sinPedir);
      expect(s.posicion, isNull);
    });

    test('dado un error de lectura sin lista, entonces ya no está cargando', () {
      expect(const ListaUbicacionesState(fallaLectura: true).cargando, isFalse);
    });

    test('dado copyWith, cuando se pide borrar la lectura o el motivo, entonces se borran', () {
      const base = ListaUbicacionesState(gps: EstadoGpsLista.sinGps);

      expect(base.copyWith(gps: EstadoGpsLista.buscando, borrarMotivo: true).motivoSinGps, isNull);
      expect(base.copyWith(borrarLectura: true).lectura, isNull);
    });
  });
}
