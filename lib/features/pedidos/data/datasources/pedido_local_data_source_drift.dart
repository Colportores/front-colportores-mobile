import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../../datos/sync_queue_table.dart';
import '../../domain/entities/pedido.dart';
import '../models/pedido_model.dart';

/// La persistencia no dejó cancelar el pedido: no es de quien cancela, ya no está por autorizar o no existe.
/// El repositorio la traduce a `FailurePedidoNoCancelable`.
final class PedidoNoCancelableException implements Exception {
  const PedidoNoCancelableException();

  @override
  String toString() => 'PedidoNoCancelableException';
}

/// Lee y escribe los pedidos en `pedido_casa_editora` y `pedido_item` de la DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama adentro,
/// así que si falla se revierte todo): el pedido, sus líneas y los jobs de sync. El pedido se encola **antes**
/// que sus líneas, que es el orden en que suben (una línea antes que su pedido vuelve `42501`).
///
/// **Lo que el servidor rechazó** (#748): un pedido cuya alta quedó `INVALID` en `sync_queue` y que nunca
/// llegó (sin número) se lee como [EstadoDelPedido.noSeEnvio], con la causa del código del rechazo. La cola
/// no se toca: si se reintenta y el servidor lo acepta, el pedido vuelve a «por autorizar» solo.
final class PedidoLocalDataSourceDrift {
  PedidoLocalDataSourceDrift(this._db, {required this._encolador});

  final AppDatabase _db;
  final EncoladorSync _encolador;

  /// Ver [PedidoRepository.enviar].
  Future<PedidoEnviado> enviar(Pedido pedido) => _db.transaction(() async {
    final existente = await (_db.select(
      _db.pedidosCasaEditora,
    )..where((p) => p.id.equals(pedido.id))).getSingleOrNull();
    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo mismo.
      return PedidoEnviado(pedido: await _leer(existente), yaEstaba: true);
    }
    await _db
        .into(_db.pedidosCasaEditora)
        .insert(
          PedidosCasaEditoraCompanion.insert(
            id: pedido.id,
            colportorId: pedido.colportorId,
            fechaPedido: pedido.fecha,
            estado: pedido.estado.codigo,
            montoTotal: Value(pedido.montoCentavos),
            excedeLimite: Value(pedido.excedeLimite),
            createdAt: pedido.auditoria.createdAt,
            updatedAt: pedido.auditoria.updatedAt,
            createdBy: Value(pedido.auditoria.createdBy),
          ),
        );
    await _encolador.encolar(
      'pedido_casa_editora',
      OperacionSync.insert,
      PedidoModel.encabezadoAJson(pedido.id, pedido.estado, pedido.auditoria),
    );
    for (final l in pedido.lineas) {
      await _db
          .into(_db.pedidoItems)
          .insert(
            PedidoItemsCompanion.insert(
              id: l.id,
              pedidoId: pedido.id,
              productoId: l.productoId,
              cantidad: l.cantidad,
              precioUnitario: Value(l.precioUnitarioCentavos),
              createdAt: pedido.auditoria.createdAt,
              updatedAt: pedido.auditoria.updatedAt,
              createdBy: Value(pedido.auditoria.createdBy),
            ),
          );
      await _encolador.encolar(
        'pedido_item',
        OperacionSync.insert,
        PedidoModel.lineaAJson(l, pedido.id, pedido.auditoria),
      );
    }
    return PedidoEnviado(pedido: pedido);
  });

  /// Ver [PedidoRepository.cancelar]. Lanza [PedidoNoCancelableException] si no se puede.
  Future<Pedido> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) => _db.transaction(() async {
    final fila = await (_db.select(
      _db.pedidosCasaEditora,
    )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).getSingleOrNull();
    if (fila == null || fila.colportorId != colportorId) {
      throw const PedidoNoCancelableException();
    }
    final actual = await _leer(fila);
    // Ya cancelado: un segundo toque o un reintento responde lo mismo sin escribir nada.
    if (actual.estado == EstadoDelPedido.cancelado) return actual;
    if (!actual.estado.sePuedeCancelar) throw const PedidoNoCancelableException();
    await (_db.update(_db.pedidosCasaEditora)..where((p) => p.id.equals(id))).write(
      PedidosCasaEditoraCompanion(
        estado: Value(EstadoDelPedido.cancelado.codigo),
        updatedAt: Value(ahora),
      ),
    );
    final auditoria = Auditoria(
      createdAt: actual.auditoria.createdAt,
      updatedAt: ahora,
      createdBy: actual.auditoria.createdBy,
      deletedAt: actual.auditoria.deletedAt,
      syncVersion: actual.auditoria.syncVersion,
    );
    await _encolador.encolar(
      'pedido_casa_editora',
      OperacionSync.update,
      PedidoModel.encabezadoAJson(id, EstadoDelPedido.cancelado, auditoria),
    );
    return Pedido(
      id: actual.id,
      colportorId: actual.colportorId,
      estado: EstadoDelPedido.cancelado,
      lineas: actual.lineas,
      fecha: actual.fecha,
      montoCentavos: actual.montoCentavos,
      excedeLimite: actual.excedeLimite,
      montoAutorizadoCentavos: actual.montoAutorizadoCentavos,
      motivoRechazo: actual.motivoRechazo,
      numero: actual.numero,
      auditoria: auditoria,
    );
  });

  /// Ver [PedidoRepository.observar].
  Stream<List<Pedido>> observar(String colportorId) {
    final consulta = _db.customSelect(
      'SELECT 1 AS cambio_de_pedidos FROM pedido_casa_editora '
      'UNION ALL SELECT 1 FROM pedido_item '
      'UNION ALL SELECT 1 FROM sync_queue',
      readsFrom: {_db.pedidosCasaEditora, _db.pedidoItems, _db.syncQueue},
    );
    // Cada cambio de estas tablas vuelve a leer todo: son pocas filas. La cola de sync cambia con cada
    // operación de la app, así que solo se emite cuando la lista de pedidos cambió de verdad.
    return consulta.watch().asyncMap((_) => _leerDe(colportorId)).distinct(_mismosPedidos);
  }

  static bool _mismosPedidos(List<Pedido> a, List<Pedido> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<List<Pedido>> _leerDe(String colportorId) => _db.transaction(() async {
    final filas =
        await (_db.select(_db.pedidosCasaEditora)..where(
              (p) =>
                  p.colportorId.equals(colportorId) &
                  p.deletedAt.isNull() &
                  // Un borrador no se muestra: el teléfono nunca lo crea.
                  p.estado.isNotValue('BORRADOR'),
            ))
            .get();
    final lineas = await _lineasDe([for (final f in filas) f.id]);
    final rechazos = await _rechazosDe([for (final f in filas) f.id]);
    final todos = [for (final f in filas) _aPedido(f, lineas[f.id] ?? const [], rechazos[f.id])];
    // El más nuevo primero; el que todavía no subió se ordena por la hora de este teléfono.
    todos.sort((a, b) {
      final porFecha = b.fecha.compareTo(a.fecha);
      return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
    });
    return todos;
  });

  Future<Pedido> _leer(PedidoCasaEditoraFila fila) async {
    final lineas = await _lineasDe([fila.id]);
    final rechazos = await _rechazosDe([fila.id]);
    return _aPedido(fila, lineas[fila.id] ?? const [], rechazos[fila.id]);
  }

  /// Los pedidos de [ids] cuyo alta el servidor rechazó (`INVALID` en la cola), con el código del rechazo.
  /// Solo el alta del pedido: lo que rechaza una línea de un pedido que sí llegó no lo marca (queda para
  /// una decisión).
  Future<Map<String, String>> _rechazosDe(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final filas =
        await (_db.select(_db.syncQueue)
              ..where(
                (q) =>
                    q.entity.equals('pedido_casa_editora') &
                    q.op.equals(OperacionSync.insert.name) &
                    q.state.equals(EstadoJob.invalid) &
                    q.rowPk.isIn(ids),
              )
              // Si hubiera más de uno, vale el más nuevo.
              ..orderBy([(q) => OrderingTerm.asc(q.createdAt), (q) => OrderingTerm.asc(q.id)]))
            .get();
    return {for (final q in filas) q.rowPk!: q.code};
  }

  Future<Map<String, List<LineaDelPedido>>> _lineasDe(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final filas =
        await (_db.select(_db.pedidoItems)
              ..where((l) => l.pedidoId.isIn(ids) & l.deletedAt.isNull())
              ..orderBy([(l) => OrderingTerm.asc(l.createdAt), (l) => OrderingTerm.asc(l.id)]))
            .get();
    final porPedido = <String, List<LineaDelPedido>>{};
    for (final l in filas) {
      (porPedido[l.pedidoId] ??= []).add(
        LineaDelPedido(
          id: l.id,
          productoId: l.productoId,
          cantidad: l.cantidad,
          cantidadAutorizada: l.cantidadAutorizada,
          precioUnitarioCentavos: l.precioUnitario,
        ),
      );
    }
    return porPedido;
  }

  static Pedido _aPedido(PedidoCasaEditoraFila f, List<LineaDelPedido> lineas, String? rechazo) {
    final estado = EstadoDelPedido.desdeCodigo(f.estado);
    // Solo un pedido que todavía espera su alta y que nunca llegó (sin número) puede no haberse enviado.
    final noSeEnvio = rechazo != null && estado == EstadoDelPedido.porAutorizar && f.numero == null;
    return _construir(
      f,
      lineas,
      noSeEnvio ? EstadoDelPedido.noSeEnvio : estado,
      noSeEnvio ? CausaDelRechazoAlEnviar.desdeCodigo(rechazo) : null,
    );
  }

  static Pedido _construir(
    PedidoCasaEditoraFila f,
    List<LineaDelPedido> lineas,
    EstadoDelPedido estado,
    CausaDelRechazoAlEnviar? rechazoAlEnviar,
  ) => Pedido(
    id: f.id,
    colportorId: f.colportorId,
    estado: estado,
    rechazoAlEnviar: rechazoAlEnviar,
    lineas: lineas,
    fecha: f.fechaPedido,
    montoCentavos: f.montoTotal,
    excedeLimite: f.excedeLimite,
    montoAutorizadoCentavos: f.montoAutorizado,
    motivoRechazo: f.motivoRechazo,
    numero: f.numero,
    auditoria: Auditoria(
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
      createdBy: f.createdBy,
      deletedAt: f.deletedAt,
      syncVersion: f.syncVersion,
    ),
  );
}
