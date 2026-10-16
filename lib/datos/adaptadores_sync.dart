import 'package:sync_engine/sync_engine.dart';

import '../catalogo.dart';
import '../features/jornada/data/models/jornada_model.dart';
import '../features/mapa/data/models/campania_ciudad_model.dart';
import '../features/mapa/data/models/espacio_model.dart';
import '../features/mapa/data/models/ubicacion_model.dart';
import '../features/mapa/data/models/zona_model.dart';
import '../features/mapa/data/models/zona_vertice_model.dart';

/// Un [SyncTableAdapter] armado con las funciones del modelo de la app (contrato §3).
///
/// Los modelos ya tienen la forma del cloud: `toJson()` es el payload que encola la capa `data`
/// y `fromJson` es lo que lee del delta. Envolverlos acá es lo que deja que la suite de conformidad
/// (§8) verifique el ida y vuelta de cada entidad en el CI de la app.
final class AdaptadorDeModelo<T> extends SyncTableAdapter<T> {
  /// Los campos privados se pasan con su nombre sin `_` (parámetros nombrados privados,
  /// Dart ≥ 3.10): `aJson:`, `desdeJson:`, `pk:` y `version:`.
  const AdaptadorDeModelo({
    required this.remoteName,
    required this._aJson,
    required this._desdeJson,
    required this._pk,
    required this._version,
  });

  @override
  final String remoteName;
  final Map<String, Object?> Function(T) _aJson;
  final T Function(Map<String, Object?>) _desdeJson;
  final String Function(T) _pk;
  final int Function(T) _version;

  @override
  Map<String, Object?> toSyncJson(T row) => _aJson(row);

  @override
  T fromSyncJson(Map<String, Object?> json) => _desdeJson(json);

  @override
  Object pkOf(T row) => _pk(row);

  @override
  int syncVersionOf(T row) => _version(row);
}

/// Para las entidades que todavía no tienen modelo en la app (las réplicas del catálogo hasta
/// HU-CAT-006, y `ubicacion_par_decidido` hasta que su tabla tenga `id`): la fila es el mapa del
/// cloud tal cual. El ida y vuelta es la identidad, y lo que la vigila es la identidad
/// cloud → DB → fila de `drift_local_store_test`.
final class AdaptadorDeFila extends SyncTableAdapter<Map<String, Object?>> {
  const AdaptadorDeFila(this.remoteName, {this.pk = 'id'});

  @override
  final String remoteName;

  final String pk;

  @override
  Map<String, Object?> toSyncJson(Map<String, Object?> row) => row;

  @override
  Map<String, Object?> fromSyncJson(Map<String, Object?> json) => json;

  @override
  Object pkOf(Map<String, Object?> row) => row[pk]!;

  @override
  int syncVersionOf(Map<String, Object?> row) => (row['sync_version'] as num?)?.toInt() ?? 0;
}

/// Los modelos que ya existen, con su adaptador.
final _deModelo = <SyncTableAdapter<Object?>>[
  AdaptadorDeModelo<JornadaModel>(
    remoteName: 'jornada',
    aJson: (m) => m.toJson(),
    desdeJson: JornadaModel.fromJson,
    pk: (m) => m.id,
    version: (m) => m.auditoria.syncVersion,
  ),
  AdaptadorDeModelo<UbicacionModel>(
    remoteName: 'ubicacion',
    aJson: (m) => m.toJson(),
    desdeJson: UbicacionModel.fromJson,
    pk: (m) => m.id,
    version: (m) => m.auditoria.syncVersion,
  ),
  AdaptadorDeModelo<EspacioModel>(
    remoteName: 'espacio',
    aJson: (m) => m.toJson(),
    desdeJson: EspacioModel.fromJson,
    pk: (m) => m.id,
    version: (m) => m.auditoria.syncVersion,
  ),
  AdaptadorDeModelo<CampaniaCiudadModel>(
    remoteName: 'campania_ciudad',
    aJson: (m) => m.toJson(),
    desdeJson: CampaniaCiudadModel.fromJson,
    pk: (m) => m.id,
    version: (m) => m.auditoria.syncVersion,
  ),
  AdaptadorDeModelo<ZonaModel>(
    remoteName: 'zona',
    aJson: (m) => m.toJson(),
    desdeJson: ZonaModel.fromJson,
    pk: (m) => m.id,
    version: (m) => m.auditoria.syncVersion,
  ),
  AdaptadorDeModelo<ZonaVerticeModel>(
    remoteName: 'zona_vertice',
    aJson: (m) => m.toJson(),
    desdeJson: ZonaVerticeModel.fromJson,
    pk: (m) => m.id,
    version: (m) => m.auditoria.syncVersion,
  ),
];

/// Un adaptador por cada entidad `push` o `pull` de [specsDeLaApp]: el de su modelo si lo tiene,
/// y si no, el de fila.
final adaptadoresDeLaApp = <SyncTableAdapter<Object?>>[
  ..._deModelo,
  for (final s in specsDeLaApp)
    if (s.policy != SyncPolicy.local && !_deModelo.any((a) => a.remoteName == s.entity))
      AdaptadorDeFila(s.entity, pk: s.pk),
];
