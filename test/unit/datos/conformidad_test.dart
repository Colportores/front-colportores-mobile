// La suite de conformidad del contrato de sync (§8), en el CI de la app: no alcanza con que el
// motor esté bien, hay que verificar que la app lo declaró bien. Es la garantía técnica de la
// Ley 18.331 (I2, #181): `persona` y `nota` son `local`, y un `stage()` sobre ellas lanza.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/adaptadores_sync.dart';
import 'package:drift/native.dart';
import 'package:sync_engine/conformance.dart';

import '../../helpers/logger_mudo.dart';

const _auditoria = {
  'created_at': '2026-10-16T12:00:00.000Z',
  'updated_at': '2026-10-16T12:30:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 3,
};

/// Una fila del cloud por entidad: la que se usa para el ida y vuelta de cada adaptador.
const _filas = <String, Map<String, Object?>>{
  'jornada': {
    'id': 'jor-1',
    'colportor_id': 'col-1',
    'inicio': '2026-10-16T08:00:00.000Z',
    'fin': '2026-10-16T20:00:00.000Z',
    'acompaniante_id': null,
    'tipo_acompaniamiento': null,
    'total_visitas': 7,
    'total_ventas': 2,
    ..._auditoria,
  },
  'ubicacion': {
    'id': 'ub-1',
    'tipo': 'CASA',
    'calle': 'Av. Ñandú',
    'numero': '1234 bis',
    'lat': -34.9,
    'lon': -56.16,
    'ciudad_id': 'ciu-1',
    'zona_id': null,
    ..._auditoria,
  },
  'espacio': {
    'id': 'esp-1',
    'ubicacion_id': 'ub-1',
    'numero_depto': '3B',
    'piso': '3',
    'descripcion': null,
    ..._auditoria,
  },
  'campania_ciudad': {'id': 'cc-1', 'campania_id': 'cam-1', 'ciudad_id': 'ciu-1', ..._auditoria},
  'zona': {
    'id': 'zon-1',
    'nombre': 'Centro',
    'campania_ciudad_id': 'cc-1',
    'tipo_forma': 'RADIAL',
    'centro_lat': -34.9,
    'centro_lon': -56.16,
    'radio_m': 500,
    'poligono_geojson': {
      'type': 'Polygon',
      'coordinates': [
        [
          [-56.2, -34.9],
          [-56.1, -34.9],
          [-56.1, -34.8],
          [-56.2, -34.9],
        ],
      ],
    },
    'color': '#3366FF',
    ..._auditoria,
  },
  'zona_vertice': {
    'id': 'v-1',
    'zona_id': 'zon-1',
    'orden': 0,
    'lat': -34.9,
    'lon': -56.2,
    'calle_a': 'Rivera',
    'calle_b': 'Bulevar Artigas',
    ..._auditoria,
  },
  'ubicacion_par_decidido': {
    'id': 'par-1',
    'ubicacion_a_id': 'ub-1',
    'ubicacion_b_id': 'ub-2',
    'decision': 'CONSERVAR_AMBOS',
    'decidido_en': '2026-10-16T12:00:00.000Z',
    ..._auditoria,
  },
  'pais': {'id': 'pa-1', 'nombre': 'Uruguay', 'iso_code': 'UY', ..._auditoria},
  'ciudad': {
    'id': 'ciu-1',
    'nombre': 'Montevideo',
    'pais_id': 'pa-1',
    'lat_centro': -34.9,
    'lon_centro': -56.16,
    'zoom_inicial': 13,
    'bbox_oeste': -56.4,
    'bbox_sur': -34.95,
    'bbox_este': -56.0,
    'bbox_norte': -34.7,
    ..._auditoria,
  },
  'campania': {
    'id': 'cam-1',
    'nombre': 'Verano',
    'tipo': 'VERANO',
    'fecha_inicio': '2026-12-01',
    'fecha_fin': null,
    'coordinador_id': 'coord-1',
    ..._auditoria,
  },
  'campania_colportor': {
    'id': 'ins-1',
    'campania_id': 'cam-1',
    'usuario_id': 'col-1',
    'zona_id': 'zon-1',
    'meta_libros': 120,
    ..._auditoria,
  },
  'producto': {
    'id': 'pro-1',
    'nombre': 'El Deseado de todas las gentes',
    'descripcion': null,
    'tipo': 'LIBRO',
    'es_bonificable': true,
    'es_misionero': false,
    'precio_base_compra': 450,
    'casa_editora': 'ACES',
    'imagen_url': null,
    ..._auditoria,
  },
  'coleccion': {'id': 'col-1', 'nombre': 'Salud', ..._auditoria},
  'producto_coleccion': {
    'id': 'pc-1',
    'producto_id': 'pro-1',
    'coleccion_id': 'col-1',
    ..._auditoria,
  },
  'precio_por_ciudad': {
    'id': 'pre-1',
    'campania_ciudad_id': 'cc-1',
    'producto_id': 'pro-1',
    'coleccion_id': null,
    'precio_venta': 1200,
    'valido_desde': '2026-12-01',
    'valido_hasta': null,
    ..._auditoria,
  },
};

void main() {
  final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
  final tablas = db.allTables.map((t) => t.actualTableName).toSet();
  // Las tablas del motor no son entidades del contrato: no se declaran (`catalogo.dart`).
  final entidades = tablas.difference(tablasDelMotor);

  runConformanceSuite(
    ConformanceFixture(
      specs: specsDeLaApp,
      allEntities: entidades,
      adapters: adaptadoresDeLaApp,
      samples: {
        for (final a in adaptadoresDeLaApp)
          if (_filas[a.remoteName] case final fila?) a.remoteName: [a.fromSyncJson(fila)],
      },
    ),
  );
}
