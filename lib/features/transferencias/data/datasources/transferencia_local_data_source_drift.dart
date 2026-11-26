import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/transferencia.dart';
import '../models/transferencia_model.dart';

/// La persistencia no dejó cancelar la transferencia: no es de quien cancela, ya no está por autorizar o
/// no existe. El repositorio la traduce a [FailureTransferenciaNoCancelable].
final class TransferenciaNoCancelableException implements Exception {
  const TransferenciaNoCancelableException();

  @override
  String toString() => 'TransferenciaNoCancelableException';
}

/// Lee y escribe las transferencias en las tablas `transferencia_stock` y `transferencia_item` de la DB
/// cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): el encabezado, sus líneas y los jobs de sync. El
/// encabezado se encola **antes** que sus líneas, que es el orden en que suben.
final class TransferenciaLocalDataSourceDrift {
  /// [_encolador] se pasa como `encolador:`.
  TransferenciaLocalDataSourceDrift(this._db, {required this._encolador});

  final AppDatabase _db;
  final EncoladorSync _encolador;

  /// Ver [TransferenciaRepository.pedir].
  Future<TransferenciaPedida> pedir(Transferencia transferencia) => _db.transaction(() async {
    final existente = await (_db.select(
      _db.transferenciasStock,
    )..where((t) => t.id.equals(transferencia.id))).getSingleOrNull();
    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo mismo
      // que la primera.
      return TransferenciaPedida(transferencia: await _leer(existente), yaEstaba: true);
    }
    await _db.into(_db.transferenciasStock).insert(_aFila(transferencia));
    await _encolador.encolar(
      'transferencia_stock',
      OperacionSync.insert,
      TransferenciaModel.encabezadoAJson(transferencia),
    );
    for (final linea in transferencia.lineas) {
      await _db.into(_db.transferenciaItems).insert(_aFilaDeLinea(linea, transferencia));
      await _encolador.encolar(
        'transferencia_item',
        OperacionSync.insert,
        TransferenciaModel.lineaAJson(linea, transferencia),
      );
    }
    return TransferenciaPedida(transferencia: transferencia);
  });

  /// Ver [TransferenciaRepository.cancelar]. Lanza [TransferenciaNoCancelableException] si no se puede.
  Future<Transferencia> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) => _db.transaction(() async {
    final fila = await (_db.select(
      _db.transferenciasStock,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (fila == null) throw const TransferenciaNoCancelableException();
    final actual = await _leer(fila);
    if (!actual.laPidio(colportorId)) throw const TransferenciaNoCancelableException();
    // Ya cancelada: un segundo toque o un reintento responde lo mismo sin escribir nada.
    if (actual.estado == EstadoDeTransferencia.cancelada) return actual;
    if (actual.estado != EstadoDeTransferencia.porAutorizar) {
      throw const TransferenciaNoCancelableException();
    }
    final cancelada = Transferencia(
      id: actual.id,
      origenId: actual.origenId,
      destinoId: actual.destinoId,
      estado: EstadoDeTransferencia.cancelada,
      lineas: actual.lineas,
      solicitanteId: actual.solicitanteId,
      fechaSolicitud: actual.fechaSolicitud,
      numero: actual.numero,
      decididoEn: actual.decididoEn,
      motivoRechazo: actual.motivoRechazo,
      auditoria: Auditoria(
        createdAt: actual.auditoria.createdAt,
        updatedAt: ahora,
        createdBy: actual.auditoria.createdBy,
        deletedAt: actual.auditoria.deletedAt,
        syncVersion: actual.auditoria.syncVersion,
      ),
    );
    await (_db.update(_db.transferenciasStock)..where((t) => t.id.equals(id))).write(
      TransferenciasStockCompanion(
        estado: Value(TransferenciaModel.codigoDelEstado(EstadoDeTransferencia.cancelada)),
        updatedAt: Value(ahora),
      ),
    );
    await _encolador.encolar(
      'transferencia_stock',
      OperacionSync.update,
      TransferenciaModel.cancelacionAJson(cancelada),
    );
    return cancelada;
  });

  /// Ver [TransferenciaRepository.observar].
  Stream<List<Transferencia>> observar(String colportorId) {
    final t = _db.transferenciasStock;
    final i = _db.transferenciaItems;
    final consulta = _db.customSelect(
      'SELECT 1 AS cambio_de_transferencias FROM transferencia_stock '
      'UNION ALL SELECT 1 FROM transferencia_item',
      readsFrom: {t, i},
    );
    // Cada cambio de una de las dos tablas vuelve a leer todo: son pocas filas.
    return consulta.watch().asyncMap((_) => _leerDe(colportorId));
  }

  Future<List<Transferencia>> _leerDe(String colportorId) => _db.transaction(() async {
    final filas =
        await (_db.select(_db.transferenciasStock)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  (t.origenId.equals(colportorId) | t.destinoId.equals(colportorId)),
            ))
            .get();
    final lineas = await _lineasDe([for (final f in filas) f.id]);
    final todas = [for (final f in filas) _aTransferencia(f, lineas[f.id] ?? const [])];
    // La más nueva primero; la que todavía no subió se ordena por la hora de este teléfono.
    todas.sort((a, b) {
      final porFecha = b.pedidaEl.compareTo(a.pedidaEl);
      return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
    });
    return todas;
  });

  Future<Transferencia> _leer(TransferenciaStockFila fila) async {
    final lineas = await _lineasDe([fila.id]);
    return _aTransferencia(fila, lineas[fila.id] ?? const []);
  }

  Future<Map<String, List<LineaDeTransferencia>>> _lineasDe(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final filas =
        await (_db.select(_db.transferenciaItems)
              ..where((l) => l.transferenciaId.isIn(ids) & l.deletedAt.isNull())
              ..orderBy([(l) => OrderingTerm.asc(l.createdAt), (l) => OrderingTerm.asc(l.id)]))
            .get();
    final porTransferencia = <String, List<LineaDeTransferencia>>{};
    for (final l in filas) {
      (porTransferencia[l.transferenciaId] ??= []).add(
        LineaDeTransferencia(id: l.id, productoId: l.productoId, cantidad: l.cantidad),
      );
    }
    return porTransferencia;
  }

  static Transferencia _aTransferencia(
    TransferenciaStockFila f,
    List<LineaDeTransferencia> lineas,
  ) => Transferencia(
    id: f.id,
    origenId: f.origenId,
    destinoId: f.destinoId,
    estado: TransferenciaModel.estadoDesdeCodigo(f.estado),
    lineas: lineas,
    solicitanteId: f.solicitanteId,
    fechaSolicitud: f.fechaSolicitud,
    numero: f.numero,
    decididoEn: f.decididoEn,
    motivoRechazo: f.motivoRechazo,
    auditoria: Auditoria(
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
      createdBy: f.createdBy,
      deletedAt: f.deletedAt,
      syncVersion: f.syncVersion,
    ),
  );

  static TransferenciasStockCompanion _aFila(Transferencia t) =>
      TransferenciasStockCompanion.insert(
        id: t.id,
        origenId: t.origenId,
        destinoId: t.destinoId,
        estado: Value(TransferenciaModel.codigoDelEstado(t.estado)),
        createdAt: t.auditoria.createdAt,
        updatedAt: t.auditoria.updatedAt,
        createdBy: Value(t.auditoria.createdBy),
        deletedAt: Value(t.auditoria.deletedAt),
        syncVersion: Value(t.auditoria.syncVersion),
      );

  static TransferenciaItemsCompanion _aFilaDeLinea(LineaDeTransferencia l, Transferencia t) =>
      TransferenciaItemsCompanion.insert(
        id: l.id,
        transferenciaId: t.id,
        productoId: l.productoId,
        cantidad: l.cantidad,
        createdAt: t.auditoria.createdAt,
        updatedAt: t.auditoria.updatedAt,
        createdBy: Value(t.auditoria.createdBy),
        deletedAt: Value(t.auditoria.deletedAt),
        syncVersion: Value(t.auditoria.syncVersion),
      );
}
