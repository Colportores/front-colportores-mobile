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

/// Una fila del cloud para cada entidad que tiene modelo en la app: la que se usa para el ida y
/// vuelta de su adaptador. Las demás usan el adaptador de fila, cuyo ida y vuelta es la identidad,
/// y les alcanza con una fila cualquiera ([_filaMinima]).
const _filas = <String, Map<String, Object?>>{
  'jornada': {
    'id': 'jor-1',
    'colportor_id': 'col-1',
    'inicio': '2026-10-16T08:00:00.000Z',
    'fin': '2026-10-16T20:00:00.000Z',
    'acompaniante_id': null,
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
};

/// La fila de ejemplo de una entidad sin modelo: su clave y las columnas de sync.
Map<String, Object?> _filaMinima(SyncTableAdapter<Object?> adaptador, String pk) => {
  pk: '${adaptador.remoteName}-1',
  ..._auditoria,
};

void main() {
  final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
  final tablas = db.allTables.map((t) => t.actualTableName).toSet();
  // Las tablas del motor no son entidades del contrato: no se declaran (`catalogo.dart`).
  final entidades = tablas.difference(tablasDelMotor);
  final pkDe = {for (final s in specsDeLaApp) s.entity: s.pk};

  runConformanceSuite(
    ConformanceFixture(
      specs: specsDeLaApp,
      allEntities: entidades,
      adapters: adaptadoresDeLaApp,
      samples: {
        for (final a in adaptadoresDeLaApp)
          a.remoteName: [
            a.fromSyncJson(_filas[a.remoteName] ?? _filaMinima(a, pkDe[a.remoteName] ?? 'id')),
          ],
      },
    ),
  );
}
