// Así se ve el uso de la suite publicada desde el CI de la app (§8).
//
// En `front-colportores-mobile` este archivo es prácticamente igual: cambian
// los `Tables.*` de Drift por los strings, y los adaptadores de mentira por los
// de verdad. Que esté acá adentro es la prueba de que la suite corre.

import 'package:sync_engine/conformance.dart';

/// La declaración de §3, tal cual la escribe la app.
final _specs = <SyncSpec>[
  SyncSpec.pull('producto', realtime: true),
  SyncSpec.pull('coleccion'),
  SyncSpec.pull('precio_por_zona', realtime: true),
  SyncSpec.pull('campania'),
  SyncSpec.pull('zona'),
  SyncSpec.pull('ciudad'),
  SyncSpec.pull('pais'),
  SyncSpec.push('venta', critical: true),
  SyncSpec.push('venta_item', critical: true),
  SyncSpec.push('entrega'),
  SyncSpec.push('cobranza', critical: true),
  SyncSpec.push('visita'),
  SyncSpec.push('agenda'),
  SyncSpec.push('jornada', critical: true),
  SyncSpec.push('ubicacion', alsoPull: true),
  SyncSpec.push('espacio', alsoPull: true),
  SyncSpec.push('house_status', alsoPull: true),
  SyncSpec.local('persona'),
  SyncSpec.local('nota'),
];

/// Una venta, del lado de la app.
class Venta {
  const Venta({
    required this.id,
    required this.total,
    required this.syncVersion,
    required this.pkUbicacion,
  });

  final String id;
  final String total; // decimal como String: nunca double en montos
  final int syncVersion;
  final String pkUbicacion;
}

class VentaAdapter extends SyncTableAdapter<Venta> {
  const VentaAdapter();

  @override
  String get remoteName => 'venta';

  @override
  Map<String, Object?> toSyncJson(Venta row) => {
        'id': row.id,
        'total': row.total,
        'sync_version': row.syncVersion,
        'pk_ubicacion': row.pkUbicacion,
      };

  @override
  Venta fromSyncJson(Map<String, Object?> json) => Venta(
        id: json['id']! as String,
        total: json['total']! as String,
        syncVersion: json['sync_version']! as int,
        pkUbicacion: json['pk_ubicacion']! as String,
      );

  @override
  Object pkOf(Venta row) => row.id;

  @override
  int syncVersionOf(Venta row) => row.syncVersion;
}

/// Adaptador genérico para las entidades que en el repo real tienen el suyo.
/// Acá alcanza con que exista: la suite verifica el round-trip, no el modelo.
class MapaAdapter extends SyncTableAdapter<Map<String, Object?>> {
  const MapaAdapter(this.remoteName);

  @override
  final String remoteName;

  @override
  Map<String, Object?> toSyncJson(Map<String, Object?> row) => {...row};

  @override
  Map<String, Object?> fromSyncJson(Map<String, Object?> json) => {...json};

  @override
  Object pkOf(Map<String, Object?> row) => row['id']!;

  @override
  int syncVersionOf(Map<String, Object?> row) => row['sync_version']! as int;
}

const _remotas = [
  'producto',
  'coleccion',
  'precio_por_zona',
  'campania',
  'zona',
  'ciudad',
  'pais',
  'venta_item',
  'entrega',
  'cobranza',
  'visita',
  'agenda',
  'jornada',
  'ubicacion',
  'espacio',
  'house_status',
];

void main() => runConformanceSuite(ConformanceFixture(
      specs: _specs,
      allEntities: {..._specs.map((s) => s.entity)},
      adapters: [
        const VentaAdapter(),
        for (final e in _remotas) MapaAdapter(e),
      ],
      samples: {
        'venta': const [
          Venta(
            id: '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c90',
            total: '1200.00',
            syncVersion: 3,
            pkUbicacion: '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c91',
          )
        ],
        for (final e in _remotas)
          e: [
            {'id': 'x-1', 'sync_version': 1}
          ],
      },
    ));
