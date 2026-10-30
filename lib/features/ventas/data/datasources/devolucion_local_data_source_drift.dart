import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../../mapa/domain/entities/color_house_status.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/devolucion.dart';
import '../../domain/entities/venta_para_devolver.dart';
import '../../domain/services/reglas_de_devolucion.dart';
import '../models/devolucion_model.dart';
import '../models/venta_model.dart';
import 'estado_de_devolucion.dart';

/// La persistencia rechazó la devolución: el repositorio la traduce a un `Failure`.
sealed class DevolucionRechazadaException implements Exception {
  const DevolucionRechazadaException();
}

/// La venta de la devolución no está en el teléfono (o está dada de baja).
final class DevolucionSinVentaException extends DevolucionRechazadaException {
  const DevolucionSinVentaException();

  @override
  String toString() => 'DevolucionSinVentaException';
}

/// Pasaron más de 72 h desde la venta: la registra el coordinador.
final class DevolucionFueraDePlazoException extends DevolucionRechazadaException {
  const DevolucionFueraDePlazoException();

  @override
  String toString() => 'DevolucionFueraDePlazoException';
}

/// Lo pedido no se puede registrar: nada elegido (`sin_productos`), más de lo que queda por devolver
/// (`de_mas`) o plata de más sin decir qué hacer con ella (`sin_eleccion`).
final class DevolucionInvalidaException extends DevolucionRechazadaException {
  const DevolucionInvalidaException(this.causa);

  final String causa;

  @override
  String toString() => 'DevolucionInvalidaException($causa)';
}

/// Lee y escribe las devoluciones en las tablas `devolucion`, `venta`, `venta_item` y `cobranza` de la
/// DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): se mide lo que queda por devolver, se comprueban el
/// plazo y lo elegido, se inserta y se encola la devolución, y el color de la casa se recalcula (R-UB08).
/// Drift serializa las transacciones: un doble toque ve una lo que dejó la otra, así que la devolución
/// no se registra dos veces ni se devuelve más de lo vendido por carrera.
final class DevolucionLocalDataSourceDrift {
  /// [_encolador] y [_estadoDeLasCasas] se pasan como `encolador:` y `estadoDeLasCasas:`.
  DevolucionLocalDataSourceDrift(
    this._db, {
    required this._encolador,
    required this._estadoDeLasCasas,
  });

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Ver `DevolucionRepository.ventaParaDevolver`.
  Future<VentaParaDevolver?> ventaParaDevolver(String ventaId) async {
    final venta = await _venta(ventaId);
    return venta == null ? null : _leer(venta);
  }

  /// Ver `DevolucionRepository.registrar`. Lanza una [DevolucionRechazadaException] si no entra.
  Future<DevolucionRegistrada> registrar(PedidoDeDevolucion pedido) => _db.transaction(() async {
    final venta = await _venta(pedido.ventaId);
    if (venta == null) throw const DevolucionSinVentaException();

    final existente = await (_db.select(
      _db.devoluciones,
    )..where((d) => d.id.equals(pedido.id))).getSingleOrNull();
    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo
      // mismo que la primera.
      final ahora = await _leer(venta);
      return DevolucionRegistrada(
        devolucion: _aDevolucion(existente),
        totalCentavos: ahora.seQuedaConCentavos,
        saldoCentavos: ahora.saldoCentavos,
        deboAlClienteCentavos: ahora.deboAlClienteCentavos,
        eraTotal: ahora.estaTodoDevuelto,
        colorDeLaCasa: await _colorActual(venta.espacioPersonaId),
        yaEstaba: true,
      );
    }

    if (ReglasDeDevolucion.estaFueraDePlazo(venta.fecha, pedido.ahora)) {
      throw const DevolucionFueraDePlazoException();
    }
    final antes = await _leer(venta);
    if (!pedido.unidadesPorRenglon.values.any((n) => n > 0)) {
      throw const DevolucionInvalidaException('sin_productos');
    }
    if (!ReglasDeDevolucion.esValida(antes, pedido.unidadesPorRenglon)) {
      throw const DevolucionInvalidaException('de_mas');
    }
    final cuenta = ReglasDeDevolucion.cuenta(antes, pedido.unidadesPorRenglon);
    final destino = ReglasDeDevolucion.destinoDeLaDiferencia(
      cuenta.pagoDeMasCentavos,
      pedido.queHacer,
    );
    if (destino == null) throw const DevolucionInvalidaException('sin_eleccion');

    final devolucion = Devolucion(
      id: pedido.id,
      ventaId: pedido.ventaId,
      productos: ReglasDeDevolucion.productosDe(antes, pedido.unidadesPorRenglon),
      dineroRetenidoCentavos: destino.retenido,
      montoReembolsadoCentavos: destino.reembolsado,
      motivo: pedido.motivo,
      fechaDevolucion: pedido.ahora,
      auditoria: Auditoria(
        createdAt: pedido.ahora,
        updatedAt: pedido.ahora,
        createdBy: pedido.colportorId,
      ),
    );
    await _db.into(_db.devoluciones).insert(_aFila(devolucion));
    await _encolador.encolar(
      'devolucion',
      OperacionSync.insert,
      DevolucionModel.toJson(devolucion),
    );
    // `audit_log_local` con el motivo siempre (HU-VEN-004): una fila por devolución, con o sin motivo,
    // en la misma transacción. Solo el id de la devolución y lo que escribió la colportora.
    await _db
        .into(_db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.devolucionRegistrada,
            uuid: devolucion.id,
            motivo: Value(devolucion.motivo),
            creadoEn: devolucion.fechaDevolucion,
          ),
        );
    final color = await _recalcular(
      venta.espacioPersonaId,
      ahora: pedido.ahora,
      colportorId: pedido.colportorId,
    );

    final despues = await _leer(venta);
    return DevolucionRegistrada(
      devolucion: devolucion,
      totalCentavos: despues.seQuedaConCentavos,
      saldoCentavos: despues.saldoCentavos,
      deboAlClienteCentavos: despues.deboAlClienteCentavos,
      eraTotal: cuenta.esTotal,
      colorDeLaCasa: color,
    );
  });

  Future<VentaFila?> _venta(String ventaId) async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId))).getSingleOrNull();
    return venta == null || venta.deletedAt != null ? null : venta;
  }

  /// La venta con lo vendido, lo pagado y lo que ya volvió.
  Future<VentaParaDevolver> _leer(VentaFila venta) async {
    final items =
        await (_db.select(_db.ventaItems)
              ..where((i) => i.ventaId.equals(venta.id) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
            .get();
    final previas = await EstadoDeDevolucion.resumenDe(_db, venta.id);
    final productoIds = {
      for (final i in items)
        if (i.productoId != null) i.productoId!,
    };
    final coleccionIds = {
      for (final i in items)
        if (i.coleccionId != null) i.coleccionId!,
    };
    final productos = productoIds.isEmpty
        ? const <ProductoFila>[]
        : await (_db.select(_db.productos)..where((p) => p.id.isIn(productoIds))).get();
    final colecciones = coleccionIds.isEmpty
        ? const <ColeccionFila>[]
        : await (_db.select(_db.colecciones)..where((c) => c.id.isIn(coleccionIds))).get();
    final nombreProducto = {for (final p in productos) p.id: p.nombre.trim()};
    final nombreColeccion = {for (final c in colecciones) c.id: c.nombre.trim()};

    final renglones = <RenglonDeLaVenta>[];
    for (final item in items) {
      final componentes = item.coleccionId == null
          ? null
          : VentaItemModel.componentesDesdeJson(item.componentes) ?? const [];
      final nombre = item.coleccionId == null
          ? nombreProducto[item.productoId]
          : nombreColeccion[item.coleccionId];
      renglones.add(
        RenglonDeLaVenta(
          ventaItemId: item.id,
          titulo: nombre == null || nombre.isEmpty
              ? (item.coleccionId == null ? 'Producto' : 'Colección')
              : nombre,
          productoId: item.productoId,
          componentes: componentes,
          cantidad: item.cantidad,
          precioUnitarioCentavos: item.precioUnitario,
          unidadesDevueltas: ReglasDeDevolucion.unidadesDevueltas(
            ventaItemId: item.id,
            productoId: item.productoId,
            componentes: componentes,
            devueltos: previas.productos,
          ),
        ),
      );
    }
    return VentaParaDevolver(
      ventaId: venta.id,
      numeroTalonario: venta.numeroTalonario,
      fecha: venta.fecha,
      montoTotalCentavos: venta.montoTotal,
      cobradoCentavos: await CobroValido.cobradoDe(_db, venta.id),
      reembolsadoCentavos: previas.reembolsadoCentavos,
      retenidoCentavos: previas.retenidoCentavos,
      renglones: renglones,
    );
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
  /// pintar: la devolución se guarda igual, porque no se pierde una devolución por una fila que falta.
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

  static Devolucion _aDevolucion(DevolucionFila fila) => Devolucion(
    id: fila.id,
    ventaId: fila.ventaId,
    productos: EstadoDeDevolucion.productosDe(fila),
    dineroRetenidoCentavos: fila.dineroRetenido,
    montoReembolsadoCentavos: fila.montoReembolsado,
    motivo: fila.motivo,
    fechaDevolucion: fila.fechaDevolucion,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static DevolucionesCompanion _aFila(Devolucion d) => DevolucionesCompanion.insert(
    id: d.id,
    ventaId: d.ventaId,
    productosDevueltos: DevolucionModel.productosAJson(d.productos),
    dineroRetenido: Value(d.dineroRetenidoCentavos),
    montoReembolsado: Value(d.montoReembolsadoCentavos),
    motivo: Value(d.motivo),
    fechaDevolucion: d.fechaDevolucion,
    createdAt: d.auditoria.createdAt,
    updatedAt: d.auditoria.updatedAt,
    createdBy: Value(d.auditoria.createdBy),
    deletedAt: Value(d.auditoria.deletedAt),
    syncVersion: Value(d.auditoria.syncVersion),
  );
}
