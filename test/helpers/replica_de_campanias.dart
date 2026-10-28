import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';

/// El teléfono tal como lo deja el pull de catálogos: las filas entran por el mismo `DriftLocalStore`
/// del motor, con la forma que arma `sync.pull` (todas las columnas del cloud, los `timestamptz` en
/// ISO-8601, los `date` como `AAAA-MM-DD` y `xmin_w` de más). Lo usan los tests que leen las
/// réplicas de `ciudad`, `campania`, `campania_ciudad`, `campania_colportor` y `zona` (#274).
final class ReplicaDeCampanias {
  ReplicaDeCampanias(this.db) : _store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);

  final AppDatabase db;
  final DriftLocalStore _store;
  var _pulls = 0;

  /// Aplica un delta: `{'entidad': [filas…]}`, como lo baja el pull.
  Future<void> bajar(Map<String, List<Map<String, Object?>>> filas) =>
      _store.applyDelta(filas, scope: 'replica', watermark: 'w${++_pulls}');

  /// Un pull completo terminó: lo que el motor anota en `sync_meta` al cerrar el ciclo. Sin esto el
  /// teléfono no sabe si la réplica está vacía porque no bajó o porque no hay nada.
  Future<void> terminoUnPull([DateTime? cuando]) =>
      DriftSyncMeta(db).write(lastPullAt: cuando ?? DateTime.utc(2026, 10, 27, 12));
}

const _creada = '2026-10-01T12:00:00+00:00';

Map<String, Object?> _auditoria({bool deBaja = false}) => {
  'created_at': _creada,
  'updated_at': _creada,
  'created_by': null,
  'deleted_at': deBaja ? '2026-10-20T12:00:00+00:00' : null,
  'sync_version': 1,
  'xmin_w': '1',
};

/// Una fila de `ciudad` como la manda el servidor (con las columnas que la app todavía ignora).
Map<String, Object?> filaCiudad(
  String id,
  String nombre, {
  required double lat,
  required double lon,
  bool deBaja = false,
}) => {
  'id': id,
  'nombre': nombre,
  'pais_id': 'pais-uy',
  'lat_centro': lat,
  'lon_centro': lon,
  'zoom_inicial': 13,
  'departamento': 'Montevideo',
  'origen': 'OSM',
  ..._auditoria(deBaja: deBaja),
};

/// Una fila de `campania`: las fechas son `date`.
Map<String, Object?> filaCampania(
  String id,
  String nombre, {
  String inicio = '2026-10-01',
  String? fin = '2027-02-28',
  bool deBaja = false,
}) => {
  'id': id,
  'nombre': nombre,
  'tipo': 'VERANO',
  'fecha_inicio': inicio,
  'fecha_fin': fin,
  'coordinador_id': 'coord-1',
  ..._auditoria(deBaja: deBaja),
};

/// Una fila de `campania_colportor`: la inscripción de [usuario] en [campania], con su zona.
Map<String, Object?> filaInscripcion(
  String id, {
  required String campania,
  String usuario = 'col-1',
  String? zona,
  bool deBaja = false,
}) => {
  'id': id,
  'campania_id': campania,
  'usuario_id': usuario,
  'zona_id': zona,
  'meta_libros': 100,
  ..._auditoria(deBaja: deBaja),
};

/// Una fila de `campania_ciudad`: [ciudad] es una de las ciudades de [campania].
Map<String, Object?> filaCampaniaCiudad(
  String id, {
  required String campania,
  required String ciudad,
  bool deBaja = false,
}) => {'id': id, 'campania_id': campania, 'ciudad_id': ciudad, ..._auditoria(deBaja: deBaja)};

/// Una fila de `zona` rectangular (`ESQUINAS`) de [campaniaCiudad].
Map<String, Object?> filaZona(
  String id,
  String nombre, {
  required String campaniaCiudad,
  required double latSur,
  required double latNorte,
  required double lonOeste,
  required double lonEste,
  bool deBaja = false,
}) => {
  'id': id,
  'nombre': nombre,
  'campania_ciudad_id': campaniaCiudad,
  'tipo_forma': 'ESQUINAS',
  'centro_lat': null,
  'centro_lon': null,
  'radio_m': null,
  'poligono_geojson': {
    'type': 'Polygon',
    'coordinates': [
      [
        [lonOeste, latSur],
        [lonEste, latSur],
        [lonEste, latNorte],
        [lonOeste, latNorte],
        [lonOeste, latSur],
      ],
    ],
  },
  'color': '#336699',
  ..._auditoria(deBaja: deBaja),
};
