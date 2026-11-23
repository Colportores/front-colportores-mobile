import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../domain/entities/deuda_con_la_casa.dart';
import '../../domain/services/calculador_de_la_deuda.dart';

/// Lo que bajó con la sincronización para contar la deuda, y cuándo bajó.
typedef BajadaDeLaDeuda = ({InsumosDeLaDeuda insumos, DateTime ultimaBajada});

/// De dónde sale la deuda con la casa editora: las tablas que baja la sincronización.
abstract interface class DeudaConLaCasaLocalDataSource {
  /// Lo que bajó para [colportorId], o `null` si el teléfono todavía no sincronizó nunca.
  Future<BajadaDeLaDeuda?> leer(String colportorId);

  /// Un evento por cada cambio de alguna de las tablas que cuenta la deuda.
  Stream<void> get cambios;
}

/// Estados de un pedido que cargan la deuda: autorizado, despachado y recibido (backend-supabase 0164).
const estadosQueCarganLaDeuda = ['AUTORIZADO', 'DESPACHADO', 'RECIBIDO'];

/// [DeudaConLaCasaLocalDataSource] sobre la DB cifrada. Reproduce, con las filas locales, las lecturas de
/// `mi_deuda_con_la_casa_editora()` (backend-supabase 0164, 0165 y 0168). La base local ya trae solo lo
/// de la propia colportora (el pull filtra por dueña), pero cada lectura filtra igual por [colportorId]:
/// cambiar de cuenta en el mismo teléfono no mezcla deudas.
final class DeudaConLaCasaLocalDrift implements DeudaConLaCasaLocalDataSource {
  DeudaConLaCasaLocalDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<void> get cambios => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.cuentasColportor,
          _db.cuentaDeudaHistoriales,
          _db.pedidosCasaEditora,
          _db.pedidoItems,
          _db.depositos,
          _db.tickets,
          _db.productos,
          _db.syncMetas,
        ]),
      )
      .map((_) {});

  @override
  Future<BajadaDeLaDeuda?> leer(String colportorId) => _db.transaction(() async {
    final ultimaBajada = (await DriftSyncMeta(_db).read()).lastPullAt;
    if (ultimaBajada == null) return null;

    final cuenta = await (_db.select(
      _db.cuentasColportor,
    )..where((c) => c.usuarioId.equals(colportorId) & c.deletedAt.isNull())).getSingleOrNull();

    final historial = await (_db.select(
      _db.cuentaDeudaHistoriales,
    )..where((h) => h.usuarioId.equals(colportorId) & h.deletedAt.isNull())).get();

    final depositos =
        await (_db.select(_db.depositos)..where(
              (d) =>
                  d.concepto.equals('CASA_EDITORA') &
                  d.validadoEn.isNotNull() &
                  d.deletedAt.isNull(),
            ))
            .get();

    final tarjetas =
        await (_db.select(_db.tickets)..where(
              (t) =>
                  t.tipo.equals('COBRO_TARJETA') &
                  t.estado.equals('VALIDADO') &
                  t.deletedAt.isNull(),
            ))
            .get();

    final pedidos =
        await (_db.select(_db.pedidosCasaEditora)..where(
              (p) =>
                  p.colportorId.equals(colportorId) &
                  p.estado.isIn(estadosQueCarganLaDeuda) &
                  p.deletedAt.isNull(),
            ))
            .get();

    final lineasPorPedido = await _lineas([for (final p in pedidos) p.id]);

    return (
      insumos: InsumosDeLaDeuda(
        deudaTotalCentavos: cuenta?.deudaTotal ?? 0,
        historial: [
          for (final h in historial)
            CambioDeLaDeuda(desde: h.desde, deudaCentavos: h.deuda, id: h.id),
        ],
        pedidos: [
          for (final p in pedidos)
            PedidoDeLaDeuda(
              pedidoId: p.id,
              numero: p.numero,
              fechaPedido: p.fechaPedido,
              montoCentavos: p.montoAutorizado ?? p.montoTotal,
              lineas: lineasPorPedido[p.id] ?? const [],
            ),
        ],
        depositosValidadosCentavos: depositos.fold<int>(0, (s, d) => s + d.monto),
        tarjetasValidadasCentavos: tarjetas.fold<int>(0, (s, t) => s + (t.monto ?? 0)),
      ),
      ultimaBajada: ultimaBajada,
    );
  });

  /// Las líneas de cada pedido: vivas, con algo que entregar (lo autorizado, o lo pedido si no se redujo)
  /// y con el nombre del producto (una línea de un producto que todavía no bajó no se lista), por nombre.
  Future<Map<String, List<LineaDePedido>>> _lineas(List<String> pedidoIds) async {
    if (pedidoIds.isEmpty) return const {};
    final items = await (_db.select(
      _db.pedidoItems,
    )..where((i) => i.pedidoId.isIn(pedidoIds) & i.deletedAt.isNull())).get();
    if (items.isEmpty) return const {};
    final productos = await (_db.select(
      _db.productos,
    )..where((p) => p.id.isIn({for (final i in items) i.productoId}))).get();
    final nombres = {for (final p in productos) p.id: p.nombre};

    final porPedido = <String, List<({String nombre, String productoId, int cantidad})>>{};
    for (final i in items) {
      final nombre = nombres[i.productoId];
      final cantidad = i.cantidadAutorizada ?? i.cantidad;
      if (nombre == null || cantidad <= 0) continue;
      (porPedido[i.pedidoId] ??= []).add((
        nombre: nombre,
        productoId: i.productoId,
        cantidad: cantidad,
      ));
    }
    return {
      for (final e in porPedido.entries)
        e.key: [
          for (final l
              in (e.value..sort((a, b) {
                final porNombre = a.nombre.compareTo(b.nombre);
                return porNombre != 0 ? porNombre : a.productoId.compareTo(b.productoId);
              })))
            LineaDePedido(nombre: l.nombre, cantidad: l.cantidad),
        ],
    };
  }
}
