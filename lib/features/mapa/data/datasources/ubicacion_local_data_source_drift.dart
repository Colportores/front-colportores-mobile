import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';
import 'espacios_table.dart';
import 'ubicacion_local_data_source.dart';
import 'ubicaciones_table.dart';

part 'ubicacion_local_data_source_drift.g.dart';

/// [UbicacionLocalDataSource] sobre las tablas `ubicacion` ([Ubicaciones]) y `espacio`
/// ([Espacios]) de la DB cifrada.
///
/// Es el DAO de las dos tablas (`@DriftAccessor`) y traduce modelos ↔ filas, como
/// `JornadaLocalDataSourceDrift`. El sync entra por [EncoladorSync], dentro de la misma
/// transacción que la escritura (contrato-sync-engine §3).
@DriftAccessor(tables: [Ubicaciones, Espacios])
final class UbicacionLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$UbicacionLocalDataSourceDriftMixin
    implements UbicacionLocalDataSource {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10).
  UbicacionLocalDataSourceDrift(super.attachedDatabase, {required this._encolador});

  final EncoladorSync _encolador;

  /// Metros por grado de latitud (y de longitud en el ecuador).
  static const _metrosPorGrado = 111320.0;

  /// Buscar, decidir y escribir van en una sola transacción: Drift no corre dos a la vez sobre la
  /// misma DB, así que dos altas casi simultáneas se serializan y la segunda ya ve la primera —como
  /// la misma ubicación (mismo `id`) o como candidata a duplicado—.
  @override
  Future<InsercionUbicacion> insertar(
    UbicacionModel ubicacion, {
    EspacioModel? espacio,
    CriterioDuplicadoUbicacion? duplicados,
  }) => transaction(() async {
    final existente = await (select(
      ubicaciones,
    )..where((u) => u.id.equals(ubicacion.id))).getSingleOrNull();
    if (existente != null) return (ubicacion: _aModelo(existente), yaEstaba: true);

    if (duplicados != null) {
      final cercanas = await _activasCerca(ubicacion, CriterioDuplicadoUbicacion.radioMetros);
      final candidatas = duplicados.candidatas(ubicacion, cercanas);
      if (candidatas.isNotEmpty) {
        throw UbicacionDuplicadaException([
          for (final candidata in candidatas) UbicacionModel.fromEntity(candidata),
        ]);
      }
    }

    await into(ubicaciones).insert(_aFila(ubicacion));
    await _encolador.encolar('ubicacion', OperacionSync.insert, ubicacion.toJson());
    if (espacio != null) {
      await into(espacios).insert(_aFilaEspacio(espacio));
      await _encolador.encolar('espacio', OperacionSync.insert, espacio.toJson());
    }
    return (ubicacion: ubicacion, yaEstaba: false);
  });

  @override
  Stream<List<UbicacionModel>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) {
    final consulta = select(ubicaciones)..where((u) => u.createdBy.equals(colportorId));
    if (ciudadId != null) consulta.where((u) => u.ciudadId.equals(ciudadId));
    if (!incluirBajas) consulta.where((u) => u.deletedAt.isNull());
    return consulta.watch().map((filas) => [for (final fila in filas) _aModelo(fila)]);
  }

  /// Ubicaciones activas de la misma ciudad dentro de un recuadro que contiene el círculo de
  /// [radioMetros] alrededor de [centro] (con margen). El filtro exacto por distancia lo hace el
  /// criterio; el recuadro solo acota lo que se lee, usando el índice `(ciudad_id, lat)`.
  Future<List<UbicacionModel>> _activasCerca(UbicacionModel centro, double radioMetros) async {
    final margen = radioMetros * 1.5;
    final dLat = margen / _metrosPorGrado;
    final cosLat = math.cos(centro.lat * math.pi / 180).abs();
    final consulta = select(ubicaciones)
      ..where(
        (u) =>
            u.ciudadId.equals(centro.ciudadId) &
            u.deletedAt.isNull() &
            u.lat.isBetweenValues(centro.lat - dLat, centro.lat + dLat),
      );
    // Cerca de los polos un grado de longitud mide casi nada: ahí no se acota por longitud.
    if (cosLat > 0.01) {
      final dLon = margen / (_metrosPorGrado * cosLat);
      consulta.where((u) => u.lon.isBetweenValues(centro.lon - dLon, centro.lon + dLon));
    }
    return [for (final fila in await consulta.get()) _aModelo(fila)];
  }

  static UbicacionesCompanion _aFila(UbicacionModel u) => UbicacionesCompanion.insert(
    id: u.id,
    tipo: UbicacionModel.codigoDeTipo(u.tipo),
    calle: Value(u.calle),
    numero: Value(u.numero),
    lat: u.lat,
    lon: u.lon,
    ciudadId: u.ciudadId,
    zonaId: Value(u.zonaId),
    createdAt: u.auditoria.createdAt,
    updatedAt: u.auditoria.updatedAt,
    createdBy: Value(u.auditoria.createdBy),
    deletedAt: Value(u.auditoria.deletedAt),
    syncVersion: Value(u.auditoria.syncVersion),
  );

  static EspaciosCompanion _aFilaEspacio(EspacioModel e) => EspaciosCompanion.insert(
    id: e.id,
    ubicacionId: e.ubicacionId,
    numeroDepto: Value(e.numeroDepto),
    piso: Value(e.piso),
    descripcion: Value(e.descripcion),
    createdAt: e.auditoria.createdAt,
    updatedAt: e.auditoria.updatedAt,
    createdBy: Value(e.auditoria.createdBy),
    deletedAt: Value(e.auditoria.deletedAt),
    syncVersion: Value(e.auditoria.syncVersion),
  );

  static UbicacionModel _aModelo(UbicacionFila fila) => UbicacionModel(
    id: fila.id,
    tipo: UbicacionModel.tipoDesdeCodigo(fila.tipo),
    calle: fila.calle,
    numero: fila.numero,
    lat: fila.lat,
    lon: fila.lon,
    ciudadId: fila.ciudadId,
    zonaId: fila.zonaId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
