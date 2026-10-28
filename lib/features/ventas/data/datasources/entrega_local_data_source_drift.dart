import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../agenda/data/datasources/agenda_local_data_source_drift.dart';
import '../../../agenda/data/models/agenda_model.dart';
import '../../../agenda/domain/entities/agenda.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/texto_recordatorio.dart';
import '../../../mapa/domain/entities/color_house_status.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/entities/entrega_diferida.dart';
import '../../domain/entities/entrega_pendiente.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../models/entrega_model.dart';

/// La persistencia no pudo entregar: la venta de la entrega no está en el teléfono (o está dada de
/// baja). El repositorio la traduce a su `Failure`.
final class EntregaSinVentaException implements Exception {
  const EntregaSinVentaException();

  @override
  String toString() => 'EntregaSinVentaException';
}

/// La casa de la venta no está en el teléfono (su vínculo persona ↔ espacio falta o está dado de
/// baja): la cita de la agenda cuelga del espacio y sin él no se puede agendar. No se guarda nada.
final class EntregaSinCasaException implements Exception {
  const EntregaSinCasaException();

  @override
  String toString() => 'EntregaSinCasaException';
}

/// La venta no tiene nada pendiente de entregar (ya se entregó todo, o no tiene filas de entrega).
final class EntregaSinPendientesException implements Exception {
  const EntregaSinPendientesException({this.sinFilas = false});

  /// La venta no tiene ninguna fila de entrega (nunca se dejó para otro día ni se entregó).
  final bool sinFilas;

  @override
  String toString() => 'EntregaSinPendientesException';
}

/// Una de las filas pedidas no es de la venta (o no existe): no se entrega nada.
final class EntregaAjenaException implements Exception {
  const EntregaAjenaException();

  @override
  String toString() => 'EntregaAjenaException';
}

/// [EntregaRepository] sobre las tablas `entrega`, `venta` y `agenda` de la DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): las filas de la entrega, su encolado y el recálculo
/// del color de la casa (R-UB08). Drift serializa las transacciones: un doble toque ve una lo que
/// dejó la otra, así que la venta no se entrega dos veces por carrera.
///
/// La entrega diferida (HU-VEN-003) escribe también la cita `ENTREGA` de la agenda y la encola en esa
/// misma transacción, **después** de las filas de entrega a las que apunta (`agenda.entrega_id` es una
/// clave foránea en el servidor).
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

  /// Ver [EntregaRepository.diferir]. Lanza [EntregaSinVentaException], [EntregaSinCasaException] o
  /// [EntregaSinPendientesException].
  Future<EntregaDiferida> diferir(
    String ventaId, {
    required DateTime fechaPrevista,
    required DateTime ahora,
    required List<Entrega> filasNuevas,
    required String idDeLaCita,
  }) => _db.transaction(() async {
    final venta = await _ventaViva(ventaId);
    final espacioId = await _espacioDe(venta.espacioPersonaId);
    if (espacioId == null) throw const EntregaSinCasaException();
    final cuando = instanteMs(fechaPrevista);

    var cambio = false;
    final previas = await _vivas(ventaId);
    if (previas.isEmpty) {
      // Sin filas y sin productos que dejar: no hay entrega que agendar.
      if (filasNuevas.isEmpty) throw const EntregaSinPendientesException(sinFilas: true);
      for (final fila in filasNuevas) {
        await _db.into(_db.entregas).insert(_aFila(fila));
        await _encolador.encolar('entrega', OperacionSync.insert, EntregaModel.toJson(fila));
      }
      cambio = true;
    } else {
      final pendientes = previas.where((e) => e.pendiente).toList();
      if (pendientes.isEmpty) throw const EntregaSinPendientesException();
      for (final fila in pendientes) {
        if (fila.fechaPrevista == cuando) continue;
        await _actualizar(fila.editada(ahora: ahora, fechaPrevista: cuando));
        cambio = true;
      }
    }
    final filas = await _vivas(ventaId);
    // La cita apunta a una fila de la entrega: la primera de las pendientes.
    final ancla = filas.firstWhere((e) => e.pendiente);

    final previa = await _citaViva(ventaId);
    final Agenda cita;
    if (previa == null) {
      cita = await _crearCita(
        id: idDeLaCita,
        venta: venta,
        espacioId: espacioId,
        cuando: cuando,
        ancla: ancla,
        ahora: ahora,
      );
      cambio = true;
    } else if (previa.fechaProgramada != cuando || previa.entregaId != ancla.id) {
      cita = await _escribirCita(
        previa.id,
        AgendasCompanion(
          fechaProgramada: Value(cuando),
          entregaId: Value(ancla.id),
          updatedAt: Value(instanteMs(ahora)),
        ),
      );
      cambio = true;
    } else {
      cita = previa;
    }

    final color = await _recalcularEspacio(espacioId, ahora: ahora, colportorId: venta.colportorId);
    return EntregaDiferida(
      entregas: filas,
      cita: cita,
      direccion: await _direccionDe(espacioId),
      colorDeLaCasa: color,
      yaEstaba: !cambio,
      citaNueva: previa == null,
    );
  });

  /// Ver [EntregaRepository.cumplir]. Lanza [EntregaSinVentaException],
  /// [EntregaSinPendientesException] (`sinFilas` si la venta no tiene ninguna fila) o
  /// [EntregaAjenaException].
  Future<EntregaCumplida> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
  }) => _db.transaction(() async {
    final venta = await _ventaViva(ventaId);
    final previas = await _vivas(ventaId);
    if (previas.isEmpty) throw const EntregaSinPendientesException(sinFilas: true);
    if (entregaIds != null && !entregaIds.every((id) => previas.any((e) => e.id == id))) {
      throw const EntregaAjenaException();
    }
    final espacioId = await _espacioDe(venta.espacioPersonaId);

    final aEntregar = [
      for (final fila in previas)
        if (fila.pendiente && (entregaIds == null || entregaIds.contains(fila.id))) fila,
    ];
    if (aEntregar.isEmpty) {
      // Sin nada pendiente que se haya pedido entregar: ya estaba entregado (un segundo toque o un
      // reintento), con ids o sin ellos. «Marcar de nuevo lo hecho» no es un error (QA #433, P2).
      return EntregaCumplida(
        entregas: previas,
        entregadas: const [],
        cita: await _citaViva(ventaId),
        direccion: espacioId == null ? '' : await _direccionDe(espacioId),
        colorDeLaCasa: espacioId == null ? null : await _colorDelEspacio(espacioId),
        yaEstaba: true,
      );
    }

    for (final fila in aEntregar) {
      await _actualizar(fila.editada(ahora: ahora, pendiente: false, fechaEntrega: ahora));
    }
    final restantes = [
      for (final fila in previas)
        if (fila.pendiente && !aEntregar.any((e) => e.id == fila.id)) fila,
    ];
    final cuando = nuevaFecha == null ? null : instanteMs(nuevaFecha);
    for (final fila in restantes) {
      // Lo que queda lleva la fecha nueva, o ninguna: la vieja ya pasó sin entregarse.
      if (fila.fechaPrevista == cuando) continue;
      await _actualizar(
        fila.editada(ahora: ahora, fechaPrevista: cuando, sinFechaPrevista: cuando == null),
      );
    }

    var cita = await _citaViva(ventaId);
    var cumplida = false;
    var conFechaNueva = false;
    final sigueConFecha = restantes.isNotEmpty && cuando != null;
    if (!sigueConFecha) {
      // Nada pendiente, o lo que queda quedó sin fecha: la visita de la entrega se hizo.
      if (cita != null) {
        cita = await _escribirCita(
          cita.id,
          AgendasCompanion(
            estado: Value(EstadoAgenda.cumplida.codigo),
            updatedAt: Value(instanteMs(ahora)),
          ),
        );
        cumplida = true;
      }
    } else if (cita != null) {
      cita = await _escribirCita(
        cita.id,
        AgendasCompanion(
          fechaProgramada: Value(cuando),
          entregaId: Value(restantes.first.id),
          updatedAt: Value(instanteMs(ahora)),
        ),
      );
      conFechaNueva = true;
    } else if (espacioId != null) {
      // Lo que quedó salió de una entrega que no tenía cita (inmediata parcial, o la cita se
      // canceló a mano): la fecha nueva le agenda una.
      cita = await _crearCita(
        id: idDeLaCita,
        venta: venta,
        espacioId: espacioId,
        cuando: cuando,
        ancla: restantes.first,
        ahora: ahora,
      );
      conFechaNueva = true;
    }

    final color = espacioId == null
        ? null
        : await _recalcularEspacio(espacioId, ahora: ahora, colportorId: venta.colportorId);
    final filas = await _vivas(ventaId);
    return EntregaCumplida(
      entregas: filas,
      entregadas: [
        for (final fila in filas)
          if (aEntregar.any((e) => e.id == fila.id)) fila,
      ],
      cita: cita,
      citaCumplida: cumplida,
      citaConFechaNueva: conFechaNueva,
      direccion: espacioId == null ? '' : await _direccionDe(espacioId),
      colorDeLaCasa: color,
    );
  });

  /// Ver [EntregaRepository.observarPendientes].
  Stream<List<EntregaPendiente>> observarPendientes({String? espacioPersonaId}) {
    final entregas = _db.entregas;
    final ventas = _db.ventas;
    final agendas = _db.agendas;
    final consulta =
        _db.select(entregas).join([
            innerJoin(ventas, ventas.id.equalsExp(entregas.ventaId)),
            leftOuterJoin(
              agendas,
              agendas.ventaId.equalsExp(ventas.id) &
                  agendas.tipo.equals(TipoAgenda.entrega.codigo) &
                  agendas.estado.equals(EstadoAgenda.programada.codigo) &
                  agendas.deletedAt.isNull(),
            ),
          ])
          ..where(
            entregas.pendiente.equals(true) &
                entregas.deletedAt.isNull() &
                ventas.deletedAt.isNull() &
                (espacioPersonaId == null
                    ? const Constant(true)
                    : ventas.espacioPersonaId.equals(espacioPersonaId)),
          )
          ..orderBy([OrderingTerm.asc(entregas.createdAt), OrderingTerm.asc(entregas.id)]);
    return consulta.watch().map((filas) {
      final porVenta = <String, _VentaPendiente>{};
      for (final fila in filas) {
        final venta = fila.readTable(ventas);
        final entrega = fila.readTable(entregas);
        final cita = fila.readTableOrNull(agendas);
        final acumulada = porVenta.putIfAbsent(
          venta.id,
          () => _VentaPendiente(venta.id, venta.espacioPersonaId, venta.fecha),
        );
        acumulada.lineas.putIfAbsent(
          entrega.id,
          () => LineaPendiente(
            entregaId: entrega.id,
            productoId: entrega.productoId,
            cantidad: entrega.cantidad,
          ),
        );
        final fecha = entrega.fechaPrevista;
        if (fecha != null && (acumulada.fecha == null || fecha.isBefore(acumulada.fecha!))) {
          acumulada.fecha = fecha;
        }
        final agendaId = acumulada.agendaId;
        if (cita != null && (agendaId == null || cita.id.compareTo(agendaId) < 0)) {
          acumulada.agendaId = cita.id;
        }
      }
      final lista = porVenta.values.toList()..sort(_VentaPendiente.comparar);
      return [for (final v in lista) v.aEntidad()];
    });
  }

  /// La venta [ventaId] sin baja, o [EntregaSinVentaException].
  Future<VentaFila> _ventaViva(String ventaId) async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId))).getSingleOrNull();
    if (venta == null || venta.deletedAt != null) throw const EntregaSinVentaException();
    return venta;
  }

  /// El espacio (la casa o el depto) del vínculo [espacioPersonaId], o `null` si el vínculo o el
  /// espacio no están en el teléfono o están dados de baja.
  Future<String?> _espacioDe(String espacioPersonaId) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(espacioPersonaId))).getSingleOrNull();
    if (vinculo == null || vinculo.deletedAt != null) return null;
    final espacio = await (_db.select(
      _db.espacios,
    )..where((e) => e.id.equals(vinculo.espacioId))).getSingleOrNull();
    return espacio == null || espacio.deletedAt != null ? null : espacio.id;
  }

  /// La cita `ENTREGA` `PROGRAMADA` más antigua de la venta, o `null`.
  Future<Agenda?> _citaViva(String ventaId) async {
    final filas =
        await (_db.select(_db.agendas)
              ..where(
                (a) =>
                    a.ventaId.equals(ventaId) &
                    a.tipo.equals(TipoAgenda.entrega.codigo) &
                    a.estado.equals(EstadoAgenda.programada.codigo) &
                    a.deletedAt.isNull(),
              )
              ..orderBy([(a) => OrderingTerm.asc(a.createdAt), (a) => OrderingTerm.asc(a.id)])
              ..limit(1))
            .get();
    return filas.isEmpty ? null : AgendaLocalDataSourceDrift.aAgenda(filas.first);
  }

  /// Agenda la entrega de [venta] para [cuando], apuntando a la fila [ancla], y encola el alta.
  Future<Agenda> _crearCita({
    required String id,
    required VentaFila venta,
    required String espacioId,
    required DateTime cuando,
    required Entrega ancla,
    required DateTime ahora,
  }) async {
    final cita = Agenda(
      id: id,
      espacioId: espacioId,
      espacioPersonaId: venta.espacioPersonaId,
      tipo: TipoAgenda.entrega,
      fechaProgramada: cuando,
      colportorId: venta.colportorId,
      ventaId: venta.id,
      entregaId: ancla.id,
      auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: venta.colportorId),
    );
    await _db.into(_db.agendas).insert(AgendaLocalDataSourceDrift.aFilaAgenda(cita));
    await _encolador.encolar('agenda', OperacionSync.insert, AgendaModel.fromEntity(cita).toJson());
    return cita;
  }

  /// Aplica [cambios] a la cita [id], la lee y encola su `update` con la fila entera.
  Future<Agenda> _escribirCita(String id, AgendasCompanion cambios) async {
    await (_db.update(_db.agendas)..where((a) => a.id.equals(id))).write(cambios);
    final cita = AgendaLocalDataSourceDrift.aAgenda(
      await (_db.select(_db.agendas)..where((a) => a.id.equals(id))).getSingle(),
    );
    await _encolador.encolar('agenda', OperacionSync.update, AgendaModel.fromEntity(cita).toJson());
    return cita;
  }

  /// Escribe el estado y las fechas de la fila [e] y encola su `update` con la fila entera.
  Future<void> _actualizar(Entrega e) async {
    await (_db.update(_db.entregas)..where((x) => x.id.equals(e.id))).write(
      EntregasCompanion(
        pendiente: Value(e.pendiente),
        fechaPrevista: Value(e.fechaPrevista),
        fechaEntrega: Value(e.fechaEntrega),
        updatedAt: Value(e.auditoria.updatedAt),
      ),
    );
    await _encolador.encolar('entrega', OperacionSync.update, EntregaModel.toJson(e));
  }

  /// «Av. Italia 1234»: la dirección de la ubicación del espacio, vacía si no está en el teléfono.
  Future<String> _direccionDe(String espacioId) async {
    final consulta =
        _db.selectOnly(_db.espacios).join([
            innerJoin(_db.ubicaciones, _db.ubicaciones.id.equalsExp(_db.espacios.ubicacionId)),
          ])
          ..addColumns([_db.ubicaciones.calle, _db.ubicaciones.numero])
          ..where(_db.espacios.id.equals(espacioId));
    final fila = await consulta.getSingleOrNull();
    if (fila == null) return '';
    return TextoRecordatorio.direccionDe(
      fila.read(_db.ubicaciones.calle),
      fila.read(_db.ubicaciones.numero),
    );
  }

  Future<String?> _ubicacionDelEspacio(String espacioId) async {
    final consulta = _db.selectOnly(_db.espacios)
      ..addColumns([_db.espacios.ubicacionId])
      ..where(_db.espacios.id.equals(espacioId));
    return (await consulta.getSingleOrNull())?.read(_db.espacios.ubicacionId);
  }

  /// El color guardado de la casa del espacio [espacioId], o `null` si no tiene.
  Future<ColorHouseStatus?> _colorDelEspacio(String espacioId) async {
    final ubicacionId = await _ubicacionDelEspacio(espacioId);
    if (ubicacionId == null) return null;
    return _colorGuardado(ubicacionId);
  }

  /// Recalcula el color de la casa del espacio [espacioId]. Si la ubicación no está en el teléfono no
  /// hay casa que pintar: se guarda igual.
  Future<ColorHouseStatus?> _recalcularEspacio(
    String espacioId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    final ubicacionId = await _ubicacionDelEspacio(espacioId);
    if (ubicacionId == null) return null;
    final estado = await _estadoDeLasCasas.recalcular(
      ubicacionId,
      ahora: ahora,
      colportorId: colportorId,
    );
    return estado?.color;
  }

  Future<List<Entrega>> _vivas(String ventaId) async {
    final filas =
        await (_db.select(_db.entregas)
              ..where((e) => e.ventaId.equals(ventaId) & e.deletedAt.isNull())
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt), (e) => OrderingTerm.asc(e.id)]))
            .get();
    return [for (final fila in filas) EntregaModel.desdeFila(fila)];
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
    return _colorGuardado(ubicacionId);
  }

  Future<ColorHouseStatus?> _colorGuardado(String ubicacionId) async {
    final fila = await (_db.select(
      _db.houseStatuses,
    )..where((h) => h.ubicacionId.equals(ubicacionId))).getSingleOrNull();
    if (fila == null || fila.deletedAt != null) return null;
    return ColorHouseStatus.desdeCodigo(fila.color);
  }

  static EntregasCompanion _aFila(Entrega e) => EntregasCompanion.insert(
    id: e.id,
    ventaId: e.ventaId,
    productoId: e.productoId,
    cantidad: e.cantidad,
    pendiente: Value(e.pendiente),
    fechaPrevista: Value(e.fechaPrevista),
    fechaEntrega: Value(e.fechaEntrega),
    createdAt: e.auditoria.createdAt,
    updatedAt: e.auditoria.updatedAt,
    createdBy: Value(e.auditoria.createdBy),
    deletedAt: Value(e.auditoria.deletedAt),
    syncVersion: Value(e.auditoria.syncVersion),
  );
}

/// Lo que se junta de una venta mientras se recorren las filas de la consulta de pendientes.
final class _VentaPendiente {
  _VentaPendiente(this.ventaId, this.espacioPersonaId, this.vendidaEl);

  final String ventaId;
  final String espacioPersonaId;
  final DateTime vendidaEl;
  final lineas = <String, LineaPendiente>{};
  DateTime? fecha;
  String? agendaId;

  EntregaPendiente aEntidad() => EntregaPendiente(
    ventaId: ventaId,
    espacioPersonaId: espacioPersonaId,
    lineas: lineas.values.toList(),
    fechaPrevista: fecha,
    agendaId: agendaId,
  );

  /// Primero las que tienen fecha, de la más próxima a la más lejana; después las que no, de la venta
  /// más vieja a la más nueva. El desempate final es el id, para que el orden no dependa del azar.
  static int comparar(_VentaPendiente a, _VentaPendiente b) {
    final fa = a.fecha;
    final fb = b.fecha;
    if (fa != null && fb == null) return -1;
    if (fa == null && fb != null) return 1;
    if (fa != null && fb != null) {
      final c = fa.compareTo(fb);
      if (c != 0) return c;
    }
    final c = a.vendidaEl.compareTo(b.vendidaEl);
    return c != 0 ? c : a.ventaId.compareTo(b.ventaId);
  }
}
