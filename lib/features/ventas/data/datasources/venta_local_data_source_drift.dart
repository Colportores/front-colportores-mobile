import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/entities/venta.dart';
import '../../domain/entities/venta_abierta.dart';
import '../../domain/entities/venta_item.dart';
import '../../domain/repositories/venta_que_crece_repository.dart' show CitasDeLaVenta;
import '../../domain/repositories/venta_repository.dart';
import '../../domain/services/reglas_de_venta.dart';
import '../../domain/services/reglas_de_venta_que_crece.dart';
import '../models/venta_model.dart';
import 'estado_de_devolucion.dart';
import 'estado_de_entrega.dart';

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

/// La venta a la que se quería sumar un libro ya no está abierta, o ya no está (HU-VEN-001, «Venta
/// cerrada»).
final class VentaCerradaException extends VentaRechazadaException {
  const VentaCerradaException();

  @override
  String toString() => 'VentaCerradaException';
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
    await _encolador.encolar(
      'venta',
      OperacionSync.insert,
      VentaModel.toJson(venta, itemsEsperados: items.length),
    );
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

  // --- «Venta crece» (HU-VEN-001, 42B·09) ------------------------------------------------------

  /// Ver `VentaQueCreceRepository.observarAbiertasDe`. Vuelve a leer cuando cambia cualquier tabla de
  /// las que deciden si una venta está abierta; un cambio mientras lee pide otra lectura al terminar.
  Stream<List<VentaAbierta>> observarAbiertasDe(String personaId) {
    final cambios = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.ventas,
        _db.ventaItems,
        _db.cobranzas,
        _db.entregas,
        _db.devoluciones,
        _db.espacioPersonas,
      ]),
    );
    StreamSubscription<void>? suscripcion;
    late final StreamController<List<VentaAbierta>> salida;
    var leyendo = false;
    var otraVez = false;
    Future<void> leer() async {
      if (leyendo) {
        otraVez = true;
        return;
      }
      leyendo = true;
      try {
        do {
          otraVez = false;
          final lista = await abiertasDe(personaId);
          if (!salida.isClosed) salida.add(lista);
        } while (otraVez && !salida.isClosed);
      } on Object catch (error, pila) {
        if (!salida.isClosed) salida.addError(error, pila);
      } finally {
        leyendo = false;
      }
    }

    salida = StreamController<List<VentaAbierta>>(
      onListen: () {
        suscripcion = cambios.listen((_) => unawaited(leer()));
        unawaited(leer());
      },
      onCancel: () => suscripcion?.cancel(),
    );
    return salida.stream;
  }

  /// Las ventas abiertas de la persona [personaId], de la más reciente a la más vieja.
  Future<List<VentaAbierta>> abiertasDe(String personaId) => _db.transaction(() async {
    final vinculos = _db.selectOnly(_db.espacioPersonas)
      ..addColumns([_db.espacioPersonas.id])
      ..where(
        _db.espacioPersonas.personaId.equals(personaId) & _db.espacioPersonas.deletedAt.isNull(),
      );
    final filas = await (_db.select(
      _db.ventas,
    )..where((v) => v.espacioPersonaId.isInQuery(vinculos) & v.deletedAt.isNull())).get();
    final abiertas = <VentaAbierta>[];
    for (final fila in filas) {
      final abierta = await _abierta(fila);
      if (abierta != null) abiertas.add(abierta);
    }
    return ReglasDeVentaQueCrece.masRecientePrimero(abiertas);
  });

  /// La venta [fila] como [VentaAbierta], o `null` si está cerrada (`ReglasDeVentaQueCrece`).
  Future<VentaAbierta?> _abierta(VentaFila fila) async {
    final devoluciones = await EstadoDeDevolucion.resumenDe(_db, fila.id);
    final cobrado = await CobroValido.cobradoDe(_db, fila.id);
    final cuenta = devoluciones.cuentaDe(
      montoTotalCentavos: fila.montoTotal,
      cobradoCentavos: cobrado,
    );
    final entregada = await EstadoDeEntrega.estaEntregada(_db, fila.id);
    final abierta = ReglasDeVentaQueCrece.estaAbierta(
      borrada: fila.deletedAt != null,
      todoDevuelto: devoluciones.todoDevuelto,
      cuenta: cuenta,
      entregada: entregada,
    );
    if (!abierta) return null;
    final renglones = await _renglonesYaVendidos(fila.id);
    return VentaAbierta(
      ventaId: fila.id,
      espacioPersonaId: fila.espacioPersonaId,
      numeroTalonario: fila.numeroTalonario,
      fecha: fila.fecha,
      montoTotalCentavos: fila.montoTotal,
      cobradoCentavos: cobrado,
      devueltoCentavos: cuenta.devueltoCentavos,
      entregada: entregada,
      entregadaEl: entregada ? await _ultimaEntrega(fila.id) : null,
      motivoMontoManual: fila.motivoMontoManual,
      renglones: renglones,
      descripcion: _descripcion(renglones),
    );
  }

  /// La fecha real de la última entrega de la venta, o `null` si no tiene ninguna.
  Future<DateTime?> _ultimaEntrega(String ventaId) async {
    final filas =
        await (_db.select(_db.entregas)
              ..where(
                (e) =>
                    e.ventaId.equals(ventaId) &
                    e.deletedAt.isNull() &
                    e.pendiente.equals(false) &
                    e.fechaEntrega.isNotNull(),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.fechaEntrega)])
              ..limit(1))
            .get();
    return filas.isEmpty ? null : filas.single.fechaEntrega;
  }

  /// Lo que la venta ya tiene, renglón por renglón, con los nombres de la réplica del catálogo (aunque
  /// el producto esté dado de baja: lo ya vendido lo sigue nombrando).
  Future<List<RenglonYaVendido>> _renglonesYaVendidos(String ventaId) async {
    final items =
        await (_db.select(_db.ventaItems)
              ..where((i) => i.ventaId.equals(ventaId) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
            .get();
    final componentes = {
      for (final item in items)
        item.id: VentaItemModel.componentesDesdeJson(item.componentes) ?? const [],
    };
    final productoIds = {
      for (final item in items) ?item.productoId,
      for (final lista in componentes.values)
        for (final c in lista) c.productoId,
    };
    final comboIds = {for (final item in items) ?item.coleccionId};
    final nombres = <String, String>{};
    if (productoIds.isNotEmpty) {
      final filas = await (_db.select(_db.productos)..where((p) => p.id.isIn(productoIds))).get();
      for (final p in filas) {
        nombres[p.id] = p.nombre.trim();
      }
    }
    if (comboIds.isNotEmpty) {
      final filas = await (_db.select(_db.colecciones)..where((c) => c.id.isIn(comboIds))).get();
      for (final c in filas) {
        nombres[c.id] = c.nombre.trim();
      }
    }
    return [
      for (final item in items)
        RenglonYaVendido(
          nombre: nombres[item.coleccionId ?? item.productoId] ?? '',
          cantidad: item.cantidad,
          precioUnitarioCentavos: item.precioUnitario,
          subtotalCentavos: item.subtotal,
          esCombo: item.coleccionId != null,
          librosDelCombo: componentes[item.id]!.fold(0, (a, c) => a + c.cantidad),
          componentes: [
            for (final c in componentes[item.id]!)
              if ((nombres[c.productoId] ?? '').isNotEmpty) nombres[c.productoId]!,
          ],
        ),
    ];
  }

  /// Qué se vendió, en una línea («Colección de 1 libro · Vida Feliz × 2»), como en «¿Qué venta?».
  static String _descripcion(List<RenglonYaVendido> renglones) {
    final partes = <String>[];
    var sinNombre = 0;
    for (final r in renglones) {
      if (r.esCombo) {
        partes.add(
          r.librosDelCombo == 1
              ? 'Colección de 1 libro'
              : 'Colección de ${r.librosDelCombo} libros',
        );
      } else if (r.nombre.isEmpty) {
        sinNombre += r.cantidad;
      } else {
        partes.add(r.cantidad == 1 ? r.nombre : '${r.nombre} × ${r.cantidad}');
      }
    }
    if (sinNombre > 0) partes.add(sinNombre == 1 ? '1 producto' : '$sinNombre productos');
    return partes.join(' · ');
  }

  /// Ver `VentaQueCreceRepository.citasDe`.
  Future<CitasDeLaVenta> citasDe(String ventaId) async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId))).getSingleOrNull();
    if (venta == null) return (cobranzaAgendada: false, entregaAgendada: false);
    final citas =
        await (_db.select(_db.agendas)..where(
              (a) =>
                  a.estado.equals(EstadoAgenda.programada.codigo) &
                  a.deletedAt.isNull() &
                  (a.ventaId.equals(ventaId) |
                      (a.ventaId.isNull() & a.espacioPersonaId.equals(venta.espacioPersonaId))),
            ))
            .get();
    return (
      cobranzaAgendada: citas.any((c) => c.tipo == TipoAgenda.cobranza.codigo),
      entregaAgendada: citas.any(
        (c) => c.tipo == TipoAgenda.entrega.codigo && c.ventaId == ventaId,
      ),
    );
  }

  /// Ver `VentaQueCreceRepository.sumar`. Lanza [VentaCerradaException] si la venta ya no está
  /// abierta o ya no está.
  Future<VentaQueCrecio> sumar(
    String ventaId,
    List<VentaItem> itemsNuevos, {
    required int sumadoCentavos,
    required DateTime ahora,
    String? motivoMontoManual,
    int? diferenciaCentavos,
  }) => _db.transaction(() async {
    final instante = instanteMs(ahora);
    final fila = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId))).getSingleOrNull();
    if (fila == null || fila.deletedAt != null) throw const VentaCerradaException();

    if (itemsNuevos.isNotEmpty) {
      final ids = [for (final i in itemsNuevos) i.id];
      final yaEstan =
          await (_db.select(_db.ventaItems)
                ..where((i) => i.id.isIn(ids))
                ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
              .get();
      if (yaEstan.isNotEmpty) {
        // Un segundo toque o un reintento con los mismos renglones: no se escribe nada y la respuesta
        // dice lo mismo que la primera.
        return VentaQueCrecio(
          venta: _aVenta(fila),
          items: [for (final f in yaEstan) _aItem(f)],
          totalAnteriorCentavos: fila.montoTotal - sumadoCentavos,
          sumadoEl: yaEstan.first.createdAt,
          yaEstaba: true,
        );
      }
    }

    // Se vuelve a mirar acá, en la misma transacción: entre que se abrió la pantalla y ahora la venta
    // pudo quedar pagada y entregada (o devuelta), y una venta cerrada no crece («Venta cerrada»).
    if (await _abierta(fila) == null) throw const VentaCerradaException();

    final vivos =
        await (_db.selectOnly(_db.ventaItems)
              ..addColumns([_db.ventaItems.id.count()])
              ..where(_db.ventaItems.ventaId.equals(ventaId) & _db.ventaItems.deletedAt.isNull()))
            .map((r) => r.read(_db.ventaItems.id.count()) ?? 0)
            .getSingle();
    final anterior = fila.montoTotal;
    final motivo = motivoMontoManual ?? fila.motivoMontoManual;
    await (_db.update(_db.ventas)..where((v) => v.id.equals(ventaId))).write(
      VentasCompanion(
        montoTotal: Value(anterior + sumadoCentavos),
        motivoMontoManual: Value(motivo),
        updatedAt: Value(instante),
      ),
    );
    final venta = _aVenta(
      (await (_db.select(_db.ventas)..where((v) => v.id.equals(ventaId))).getSingle()),
    );
    // Primero la venta con el total nuevo y cuántos renglones lleva ahora, después los renglones: con
    // los renglones por llegar el servidor no juzga el total (backend 0158, «Total arriba»).
    await _encolador.encolar(
      'venta',
      OperacionSync.update,
      VentaModel.toJson(venta, itemsEsperados: vivos + itemsNuevos.length),
    );
    for (final item in itemsNuevos) {
      await _db.into(_db.ventaItems).insert(_aFilaItem(item));
      await _encolador.encolar('venta_item', OperacionSync.insert, VentaItemModel.toJson(item));
    }

    if (diferenciaCentavos != null) {
      // Como en el alta: solo el id de la venta y la diferencia, nunca el motivo.
      await _db
          .into(_db.auditLogLocal)
          .insert(
            AuditLogLocalCompanion.insert(
              evento: EventoAuditoriaLocal.ventaMontoManual,
              uuid: venta.id,
              motivo: Value('diferencia_centavos:$diferenciaCentavos'),
              creadoEn: instante,
            ),
          );
    }

    await _recalcular(venta);
    return VentaQueCrecio(
      venta: venta,
      items: itemsNuevos,
      totalAnteriorCentavos: anterior,
      sumadoEl: instante,
    );
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
    // Sin distinguir mayúsculas ni espacios de los bordes (decisión de Cristian, 03/11, «Talonario =»):
    // se compara en Dart y no con `=` de SQL, que sí las distingue, ni con `lower()` de SQLite, que
    // solo conoce las letras ASCII.
    final filas =
        await (_db.select(_db.ventas)
              ..where((v) => v.colportorId.equals(colportorId) & v.deletedAt.isNull())
              ..orderBy([(v) => OrderingTerm.desc(v.fecha)]))
            .get();
    for (final fila in filas) {
      if (!ReglasDeVenta.mismoTalonario(fila.numeroTalonario, numero)) continue;
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
