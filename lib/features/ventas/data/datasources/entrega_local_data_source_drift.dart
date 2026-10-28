import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/domain/entities/color_house_status.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../models/entrega_model.dart';

/// La persistencia no pudo entregar: la venta de la entrega no está en el teléfono (o está dada de
/// baja). El repositorio la traduce a su `Failure`.
final class EntregaSinVentaException implements Exception {
  const EntregaSinVentaException();

  @override
  String toString() => 'EntregaSinVentaException';
}

/// [EntregaRepository] sobre las tablas `entrega` y `venta` de la DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): las filas de la entrega, su encolado y el recálculo
/// del color de la casa (R-UB08). Drift serializa las transacciones: un doble toque ve una lo que
/// dejó la otra, así que la venta no se entrega dos veces por carrera.
final class EntregaLocalDataSourceDrift {
  /// [_encolador] y [_estadoDeLasCasas] se pasan como `encolador:` y `estadoDeLasCasas:`.
  EntregaLocalDataSourceDrift(
    this._db, {
    required this._encolador,
    required this._estadoDeLasCasas,
  });

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Ver [EntregaRepository.entregarAhora]. Lanza [EntregaSinVentaException] si la venta no está.
  Future<EntregaRegistrada> entregarAhora(String ventaId, List<Entrega> filas) =>
      _db.transaction(() async {
        final venta = await (_db.select(
          _db.ventas,
        )..where((v) => v.id.equals(ventaId))).getSingleOrNull();
        if (venta == null || venta.deletedAt != null) throw const EntregaSinVentaException();

        final existentes = await _vivas(ventaId);
        if (existentes.isNotEmpty) {
          // Un segundo toque o un reintento: no se escribe nada y la respuesta dice lo mismo que la
          // primera.
          return EntregaRegistrada(
            entregas: existentes,
            colorDeLaCasa: await _colorActual(venta.espacioPersonaId),
            yaEstaba: true,
          );
        }

        for (final fila in filas) {
          await _db.into(_db.entregas).insert(_aFila(fila));
          await _encolador.encolar('entrega', OperacionSync.insert, EntregaModel.toJson(fila));
        }
        final color = await _recalcular(
          venta.espacioPersonaId,
          ahora: filas.isEmpty ? venta.updatedAt : filas.first.auditoria.updatedAt,
          colportorId: venta.colportorId,
        );
        return EntregaRegistrada(entregas: await _vivas(ventaId), colorDeLaCasa: color);
      });

  /// Ver [EntregaRepository.deLaVenta].
  Future<List<Entrega>> deLaVenta(String ventaId) => _vivas(ventaId);

  Future<List<Entrega>> _vivas(String ventaId) async {
    final filas =
        await (_db.select(_db.entregas)
              ..where((e) => e.ventaId.equals(ventaId) & e.deletedAt.isNull())
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt), (e) => OrderingTerm.asc(e.id)]))
            .get();
    return [for (final fila in filas) _aEntrega(fila)];
  }

  /// La ubicación del vínculo persona ↔ espacio, o `null` si no está en el teléfono.
  Future<String?> _ubicacionDe(String espacioPersonaId) async {
    final consulta =
        _db.selectOnly(_db.espacioPersonas).join([
            innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
          ])
          ..addColumns([_db.espacios.ubicacionId])
          ..where(_db.espacioPersonas.id.equals(espacioPersonaId));
    final fila = await consulta.getSingleOrNull();
    return fila?.read(_db.espacios.ubicacionId);
  }

  /// Recalcula el color de la casa de la venta. Si la ubicación no está en el teléfono no hay casa que
  /// pintar: la entrega se guarda igual, porque no se pierde una entrega por una fila que falta.
  Future<ColorHouseStatus?> _recalcular(
    String espacioPersonaId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    final ubicacionId = await _ubicacionDe(espacioPersonaId);
    if (ubicacionId == null) return null;
    final estado = await _estadoDeLasCasas.recalcular(
      ubicacionId,
      ahora: ahora,
      colportorId: colportorId,
    );
    return estado?.color;
  }

  Future<ColorHouseStatus?> _colorActual(String espacioPersonaId) async {
    final ubicacionId = await _ubicacionDe(espacioPersonaId);
    if (ubicacionId == null) return null;
    final fila = await (_db.select(
      _db.houseStatuses,
    )..where((h) => h.ubicacionId.equals(ubicacionId))).getSingleOrNull();
    if (fila == null || fila.deletedAt != null) return null;
    return ColorHouseStatus.desdeCodigo(fila.color);
  }

  static Entrega _aEntrega(EntregaFila fila) => Entrega(
    id: fila.id,
    ventaId: fila.ventaId,
    productoId: fila.productoId,
    cantidad: fila.cantidad,
    pendiente: fila.pendiente,
    fechaEntrega: fila.fechaEntrega,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static EntregasCompanion _aFila(Entrega e) => EntregasCompanion.insert(
    id: e.id,
    ventaId: e.ventaId,
    productoId: e.productoId,
    cantidad: e.cantidad,
    pendiente: Value(e.pendiente),
    fechaEntrega: Value(e.fechaEntrega),
    createdAt: e.auditoria.createdAt,
    updatedAt: e.auditoria.updatedAt,
    createdBy: Value(e.auditoria.createdBy),
    deletedAt: Value(e.auditoria.deletedAt),
    syncVersion: Value(e.auditoria.syncVersion),
  );
}
