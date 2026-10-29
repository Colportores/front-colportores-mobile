import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../../ventas/data/models/venta_model.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../domain/entities/cobranza.dart';
import '../../domain/entities/venta_con_saldo.dart';
import '../models/cobranza_model.dart';

/// La persistencia rechazó el cobro: el repositorio la traduce a un `Failure`.
sealed class CobroRechazadoException implements Exception {
  const CobroRechazadoException();
}

/// El cobro es mayor que lo que debe la venta.
final class CobroMayorAlSaldoException extends CobroRechazadoException {
  const CobroMayorAlSaldoException({required this.saldoCentavos});

  final int saldoCentavos;

  @override
  String toString() => 'CobroMayorAlSaldoException';
}

/// La venta del cobro no está en el teléfono (o está dada de baja).
final class CobroSinVentaException extends CobroRechazadoException {
  const CobroSinVentaException();

  @override
  String toString() => 'CobroSinVentaException';
}

/// La fecha del cobro es anterior a la de la venta.
final class CobroFechaAnteriorException extends CobroRechazadoException {
  const CobroFechaAnteriorException();

  @override
  String toString() => 'CobroFechaAnteriorException';
}

/// Lee y escribe los cobros en las tablas `cobranza` y `venta` de la DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): el saldo se mide y el cobro se inserta en la misma
/// transacción, y Drift las serializa, así que dos cobros seguidos nunca suman más que la venta. El
/// color de la casa se recalcula también adentro (R-UB08).
final class CobranzaLocalDataSourceDrift {
  /// [_encolador] y [_estadoDeLasCasas] se pasan como `encolador:` y `estadoDeLasCasas:`.
  CobranzaLocalDataSourceDrift(
    this._db, {
    required this._encolador,
    required this._estadoDeLasCasas,
  });

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Ver [CobranzaRepository.registrar]. Lanza una [CobroRechazadoException] si el cobro no entra.
  Future<CobroRegistrado> registrar(Cobranza cobro) => _db.transaction(() async {
    final existente = await (_db.select(
      _db.cobranzas,
    )..where((c) => c.id.equals(cobro.id))).getSingleOrNull();
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(cobro.ventaId))).getSingleOrNull();
    if (venta == null || venta.deletedAt != null) throw const CobroSinVentaException();

    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo
      // mismo que la primera.
      return CobroRegistrado(
        cobranza: _aCobranza(existente),
        venta: await _conSaldo(venta),
        yaEstaba: true,
      );
    }

    final antes = await _conSaldo(venta);
    if (cobro.montoCentavos > antes.saldoCentavos) {
      throw CobroMayorAlSaldoException(saldoCentavos: antes.saldoCentavos);
    }
    final diaDelCobro = ReglasDeVenta.diaDeMontevideo(cobro.fecha);
    if (diaDelCobro.isBefore(ReglasDeVenta.diaDeMontevideo(venta.fecha))) {
      throw const CobroFechaAnteriorException();
    }

    await _db.into(_db.cobranzas).insert(_aFila(cobro));
    await _encolador.encolar('cobranza', OperacionSync.insert, CobranzaModel.toJson(cobro));
    await _recalcular(venta.espacioPersonaId, cobro);

    return CobroRegistrado(cobranza: cobro, venta: await _conSaldo(venta));
  });

  /// Ver [CobranzaRepository.ventaConSaldo].
  Future<VentaConSaldo?> ventaConSaldo(String ventaId) async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId) & v.deletedAt.isNull())).getSingleOrNull();
    return venta == null ? null : _conSaldo(venta);
  }

  /// Ver [CobranzaRepository.ventasConSaldoDe].
  Future<List<VentaConSaldo>> ventasConSaldoDe(String personaId) async {
    final vinculos = _db.selectOnly(_db.espacioPersonas)
      ..addColumns([_db.espacioPersonas.id])
      ..where(
        _db.espacioPersonas.personaId.equals(personaId) & _db.espacioPersonas.deletedAt.isNull(),
      );
    final filas =
        await (_db.select(_db.ventas)
              ..where((v) => v.espacioPersonaId.isInQuery(vinculos) & v.deletedAt.isNull())
              ..orderBy([(v) => OrderingTerm.asc(v.fecha), (v) => OrderingTerm.asc(v.id)]))
            .get();
    final salida = <VentaConSaldo>[];
    for (final fila in filas) {
      final venta = await _conSaldo(fila);
      if (venta.tieneSaldo) salida.add(venta);
    }
    return salida;
  }

  /// El saldo de cada venta viva de las personas [personaIds] que debe algo, sumado por persona.
  Future<Map<String, int>> saldosPorPersona(Iterable<String> personaIds) async {
    final salida = <String, int>{};
    for (final personaId in personaIds) {
      final deuda = (await ventasConSaldoDe(personaId)).fold<int>(0, (a, v) => a + v.saldoCentavos);
      if (deuda > 0) salida[personaId] = deuda;
    }
    return salida;
  }

  Future<VentaConSaldo> _conSaldo(VentaFila venta) async {
    final suma = _db.cobranzas.monto.sum();
    final fila =
        await (_db.selectOnly(_db.cobranzas)
              ..addColumns([suma])
              ..where(_db.cobranzas.ventaId.equals(venta.id) & _db.cobranzas.deletedAt.isNull()))
            .getSingle();
    return VentaConSaldo(
      ventaId: venta.id,
      numeroTalonario: venta.numeroTalonario,
      fecha: venta.fecha,
      montoTotalCentavos: venta.montoTotal,
      cobradoCentavos: fila.read(suma) ?? 0,
      descripcion: await _descripcion(venta.id),
    );
  }

  /// Qué se vendió, en una línea (C·08 de la vista 39): «Vida Feliz × 2», «Colección de 1 libro».
  ///
  /// Un producto va con su nombre de la réplica del catálogo (#180) —con « × N» si se vendieron
  /// varias—, aunque esté dado de baja: las ventas que ya lo llevan lo siguen resolviendo. Un
  /// combo, con la cuenta de sus libros. Si el producto no está en el teléfono (el catálogo todavía
  /// no bajó) se cuenta aparte como «N productos»: la línea nunca queda sin decir algo.
  Future<String> _descripcion(String ventaId) async {
    final items =
        await (_db.select(_db.ventaItems)
              ..where((i) => i.ventaId.equals(ventaId) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
            .get();
    final productoIds = {
      for (final item in items)
        if (item.coleccionId == null && item.productoId != null) item.productoId!,
    };
    final nombres = <String, String>{};
    if (productoIds.isNotEmpty) {
      final filas = await (_db.select(_db.productos)..where((p) => p.id.isIn(productoIds))).get();
      for (final fila in filas) {
        if (fila.nombre.trim().isNotEmpty) nombres[fila.id] = fila.nombre.trim();
      }
    }
    final partes = <String>[];
    var sinNombre = 0;
    for (final item in items) {
      if (item.coleccionId != null) {
        final libros = (VentaItemModel.componentesDesdeJson(item.componentes) ?? const [])
            .fold<int>(0, (a, c) => a + c.cantidad);
        partes.add(libros == 1 ? 'Colección de 1 libro' : 'Colección de $libros libros');
        continue;
      }
      final nombre = nombres[item.productoId];
      if (nombre == null) {
        sinNombre += item.cantidad;
      } else {
        partes.add(item.cantidad == 1 ? nombre : '$nombre × ${item.cantidad}');
      }
    }
    if (sinNombre > 0) partes.add(sinNombre == 1 ? '1 producto' : '$sinNombre productos');
    return partes.join(' · ');
  }

  /// Recalcula el color de la casa del cobro. Si la ubicación del espacio no está en el teléfono no
  /// hay casa que pintar: el cobro se guarda igual, porque no se pierde un cobro por una fila que
  /// falta.
  Future<void> _recalcular(String espacioPersonaId, Cobranza cobro) async {
    final consulta =
        _db.selectOnly(_db.espacioPersonas).join([
            innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
          ])
          ..addColumns([_db.espacios.ubicacionId])
          ..where(_db.espacioPersonas.id.equals(espacioPersonaId));
    final fila = await consulta.getSingleOrNull();
    final ubicacionId = fila?.read(_db.espacios.ubicacionId);
    if (ubicacionId == null) return;
    await _estadoDeLasCasas.recalcular(
      ubicacionId,
      ahora: cobro.auditoria.updatedAt,
      colportorId: cobro.auditoria.createdBy ?? '',
    );
  }

  static Cobranza _aCobranza(CobranzaFila fila) => Cobranza(
    id: fila.id,
    ventaId: fila.ventaId,
    montoCentavos: fila.monto,
    medio: CobranzaModel.medioDesdeCodigo(fila.medio),
    fecha: fila.fecha,
    numeroCuota: fila.numeroCuota,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static CobranzasCompanion _aFila(Cobranza c) => CobranzasCompanion.insert(
    id: c.id,
    ventaId: c.ventaId,
    monto: c.montoCentavos,
    medio: CobranzaModel.codigoDelMedio(c.medio),
    fecha: c.fecha,
    numeroCuota: Value(c.numeroCuota),
    createdAt: c.auditoria.createdAt,
    updatedAt: c.auditoria.updatedAt,
    createdBy: Value(c.auditoria.createdBy),
    deletedAt: Value(c.auditoria.deletedAt),
    syncVersion: Value(c.auditoria.syncVersion),
  );
}
