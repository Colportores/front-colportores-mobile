import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/entities/venta.dart';
import '../../domain/entities/venta_item.dart';
import '../../domain/repositories/venta_repository.dart';
import '../../domain/services/reglas_de_venta.dart';
import '../models/venta_model.dart';

/// La persistencia rechazó la venta: el repositorio la traduce a un `Failure`.
sealed class VentaRechazadaException implements Exception {
  const VentaRechazadaException();
}

/// El número de talonario ya está en la venta [ventaDel] del mismo colportor el mismo año.
final class TalonarioRepetidoException extends VentaRechazadaException {
  const TalonarioRepetidoException({required this.numero, required this.ventaDel});

  final String numero;
  final DateTime ventaDel;

  @override
  String toString() => 'TalonarioRepetidoException';
}

/// El vínculo persona ↔ espacio de la venta no está en el teléfono (o está dado de baja).
final class VentaSinPersonaException extends VentaRechazadaException {
  const VentaSinPersonaException();

  @override
  String toString() => 'VentaSinPersonaException';
}

/// [VentaRepository] sobre las tablas `venta` y `venta_item` de la DB cifrada.
///
/// Cada operación es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): la venta y sus ítems, su encolado (la venta primero y
/// después los ítems, que apuntan a ella), la nota del monto manual en el `audit_log` local y el
/// recálculo del color de la casa (R-UB08). Drift serializa las transacciones: un doble toque o dos
/// ventas seguidas ven una lo que dejó la otra, así que el talonario no se puede repetir por carrera.
final class VentaLocalDataSourceDrift {
  /// [_encolador] y [_estadoDeLasCasas] se pasan como `encolador:` y `estadoDeLasCasas:`.
  VentaLocalDataSourceDrift(this._db, {required this._encolador, required this._estadoDeLasCasas});

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Ver [VentaRepository.registrar]. Lanza una [VentaRechazadaException] si la venta no entra.
  Future<VentaGuardada> registrar(
    Venta venta,
    List<VentaItem> items, {
    int? diferenciaCentavos,
    AntesDeGuardarLaVenta? antesDeGuardar,
  }) => _db.transaction(() async {
    final existente = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(venta.id))).getSingleOrNull();
    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo
      // mismo que la primera.
      final filas = await (_db.select(
        _db.ventaItems,
      )..where((i) => i.ventaId.equals(venta.id))).get();
      return VentaGuardada(
        venta: _aVenta(existente),
        items: [for (final fila in filas) _aItem(fila)],
        yaEstaba: true,
      );
    }

    await _exigirVinculo(venta.espacioPersonaId);
    final repetida = await _ventaDelTalonario(
      venta.colportorId,
      venta.numeroTalonario,
      venta.fecha,
    );
    if (repetida != null) {
      throw TalonarioRepetidoException(
        numero: venta.numeroTalonario,
        ventaDel: ReglasDeVenta.diaDeMontevideo(repetida.fecha),
      );
    }

    // Primero lo que el servidor necesita antes que la venta (la visita de la entrevista).
    await antesDeGuardar?.call();

    await _db.into(_db.ventas).insert(_aFilaVenta(venta));
    await _encolador.encolar('venta', OperacionSync.insert, VentaModel.toJson(venta));
    for (final item in items) {
      await _db.into(_db.ventaItems).insert(_aFilaItem(item));
      await _encolador.encolar('venta_item', OperacionSync.insert, VentaItemModel.toJson(item));
    }

    if (diferenciaCentavos != null) {
      // «Diferencia anotada en audit_log_local» (HU-VEN-001, S38): solo el id de la venta y el número,
      // nunca el motivo que escribió la colportora (ese viaja con la venta).
      await _db
          .into(_db.auditLogLocal)
          .insert(
            AuditLogLocalCompanion.insert(
              evento: EventoAuditoriaLocal.ventaMontoManual,
              uuid: venta.id,
              motivo: Value('diferencia_centavos:$diferenciaCentavos'),
              creadoEn: instanteMs(venta.fecha),
            ),
          );
    }

    await _recalcular(venta);
    return VentaGuardada(venta: venta, items: items);
  });

  /// Ver [VentaRepository.talonarioUsado].
  Future<VentaDelTalonario?> talonarioUsado({
    required String colportorId,
    required String numero,
    required DateTime fecha,
  }) => _ventaDelTalonario(colportorId, numero.trim(), fecha);

  Future<VentaDelTalonario?> _ventaDelTalonario(
    String colportorId,
    String numero,
    DateTime fecha,
  ) async {
    final anio = ReglasDeVenta.anioDeMontevideo(fecha);
    final filas =
        await (_db.select(_db.ventas)
              ..where(
                (v) =>
                    v.colportorId.equals(colportorId) &
                    v.numeroTalonario.equals(numero) &
                    v.deletedAt.isNull(),
              )
              ..orderBy([(v) => OrderingTerm.desc(v.fecha)]))
            .get();
    for (final fila in filas) {
      if (ReglasDeVenta.anioDeMontevideo(fila.fecha) == anio) {
        return VentaDelTalonario(ventaId: fila.id, fecha: fila.fecha);
      }
    }
    return null;
  }

  Future<void> _exigirVinculo(String espacioPersonaId) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((e) => e.id.equals(espacioPersonaId))).getSingleOrNull();
    if (vinculo == null || vinculo.deletedAt != null) throw const VentaSinPersonaException();
  }

  /// Recalcula el color de la casa de la venta. Si la ubicación del espacio no está en el teléfono no
  /// hay casa que pintar: la venta se guarda igual, porque no se pierde una venta por una fila que
  /// falta.
  Future<void> _recalcular(Venta venta) async {
    final consulta =
        _db.selectOnly(_db.espacioPersonas).join([
            innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
          ])
          ..addColumns([_db.espacios.ubicacionId])
          ..where(_db.espacioPersonas.id.equals(venta.espacioPersonaId));
    final fila = await consulta.getSingleOrNull();
    final ubicacionId = fila?.read(_db.espacios.ubicacionId);
    if (ubicacionId == null) return;
    await _estadoDeLasCasas.recalcular(
      ubicacionId,
      ahora: venta.auditoria.updatedAt,
      colportorId: venta.colportorId,
    );
  }

  static Venta _aVenta(VentaFila fila) => Venta(
    id: fila.id,
    espacioPersonaId: fila.espacioPersonaId,
    numeroTalonario: fila.numeroTalonario,
    montoTotalCentavos: fila.montoTotal,
    fecha: fila.fecha,
    colportorId: fila.colportorId,
    visitaId: fila.visitaId,
    motivoMontoManual: fila.motivoMontoManual,
    auditoria: _auditoria(
      fila.createdAt,
      fila.updatedAt,
      fila.createdBy,
      fila.deletedAt,
      fila.syncVersion,
    ),
  );

  static VentaItem _aItem(VentaItemFila fila) => VentaItem(
    id: fila.id,
    ventaId: fila.ventaId,
    productoId: fila.productoId,
    coleccionId: fila.coleccionId,
    componentes: VentaItemModel.componentesDesdeJson(fila.componentes),
    cantidad: fila.cantidad,
    precioUnitarioCentavos: fila.precioUnitario,
    subtotalCentavos: fila.subtotal,
    auditoria: _auditoria(
      fila.createdAt,
      fila.updatedAt,
      fila.createdBy,
      fila.deletedAt,
      fila.syncVersion,
    ),
  );

  static Auditoria _auditoria(
    DateTime creada,
    DateTime actualizada,
    String? creadaPor,
    DateTime? baja,
    int version,
  ) => Auditoria(
    createdAt: creada,
    updatedAt: actualizada,
    createdBy: creadaPor,
    deletedAt: baja,
    syncVersion: version,
  );

  static VentasCompanion _aFilaVenta(Venta v) => VentasCompanion.insert(
    id: v.id,
    espacioPersonaId: v.espacioPersonaId,
    numeroTalonario: v.numeroTalonario,
    montoTotal: v.montoTotalCentavos,
    fecha: v.fecha,
    colportorId: v.colportorId,
    visitaId: Value(v.visitaId),
    motivoMontoManual: Value(v.motivoMontoManual),
    createdAt: v.auditoria.createdAt,
    updatedAt: v.auditoria.updatedAt,
    createdBy: Value(v.auditoria.createdBy),
    deletedAt: Value(v.auditoria.deletedAt),
    syncVersion: Value(v.auditoria.syncVersion),
  );

  static VentaItemsCompanion _aFilaItem(VentaItem i) => VentaItemsCompanion.insert(
    id: i.id,
    ventaId: i.ventaId,
    productoId: Value(i.productoId),
    coleccionId: Value(i.coleccionId),
    cantidad: i.cantidad,
    precioUnitario: i.precioUnitarioCentavos,
    subtotal: i.subtotalCentavos,
    componentes: Value(VentaItemModel.componentesAJson(i.componentes)),
    createdAt: i.auditoria.createdAt,
    updatedAt: i.auditoria.updatedAt,
    createdBy: Value(i.auditoria.createdBy),
    deletedAt: Value(i.auditoria.deletedAt),
    syncVersion: Value(i.auditoria.syncVersion),
  );
}
