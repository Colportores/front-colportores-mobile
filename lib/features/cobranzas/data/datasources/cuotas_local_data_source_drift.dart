import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/error/failure.dart' show MotivoPlanDeCuotas;
import '../../../../core/sync/encolador_sync.dart';
import '../../../agenda/data/datasources/agenda_local_data_source_drift.dart';
import '../../../agenda/data/models/agenda_model.dart';
import '../../../agenda/domain/entities/agenda.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/cuota.dart';
import '../../domain/entities/pedido_de_plan.dart';
import '../../domain/entities/venta_con_saldo.dart';
import '../../domain/services/reparto_de_cuotas.dart';
import 'cobro_valido.dart';

/// La persistencia rechazó el plan o el cambio de cuotas: el repositorio lo traduce a un `Failure`.
final class CuotasRechazadasException implements Exception {
  const CuotasRechazadasException(this.motivo);

  final MotivoPlanDeCuotas motivo;

  @override
  String toString() => 'CuotasRechazadasException(${motivo.name})';
}

/// El plan de cuotas de una venta, sobre las tablas `agenda`, `cobranza` y `venta` de la DB cifrada.
///
/// Decisión «Plan cuotas» (Cristian, 23/10): **no hay tablas de plan ni de cuotas**. Cada cuota es
/// una cita de cobranza de la agenda con su venta y su `monto_previsto`, y sube por el motor como
/// cualquier cita. Lo pagado de cada cuota sale de los cobros ([RepartoDeCuotas.estadoDe]); lo único
/// que se escribe al cobrar es pasar a `CUMPLIDA` las citas que el cobro cubre.
///
/// Cada escritura es **una transacción de Drift** (el encolado va adentro, igual que en los cobros y
/// las agendas) y recalcula el color de la casa. Las tres de este archivo que se llaman desde otras
/// transacciones ([cerrarLasCubiertas], [trasladarLaCancelada], [leerPlan]) no abren una propia.
final class CuotasLocalDataSourceDrift {
  CuotasLocalDataSourceDrift(this._db, {required this._encolador, required this._estadoDeLasCasas});

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Lo más que admite el servidor por venta (AG001): 12 citas `PROGRAMADA` o `CUMPLIDA` con monto.
  static const _tope = RepartoDeCuotas.maximo;

  // ---- Lecturas ----------------------------------------------------------------------------------

  /// El plan de la venta [ventaId], o `null` si la venta no está o se dio de baja.
  Future<PlanDeCuotas?> leerPlan(String ventaId) async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId) & v.deletedAt.isNull())).getSingleOrNull();
    if (venta == null) return null;
    return _plan(venta);
  }

  /// El plan de [ventaId] cada vez que cambia la venta, sus cobros, sus citas o lo que se vendió.
  Stream<PlanDeCuotas?> observarPlan(String ventaId) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.ventas,
          _db.cobranzas,
          _db.agendas,
          _db.espacioPersonas,
          _db.ventaItems,
          _db.productos,
        },
      )
      .watch()
      .asyncMap((_) => leerPlan(ventaId))
      .distinct();

  // ---- Escrituras --------------------------------------------------------------------------------

  /// Ver [PlanDeCuotasRepository.crear]. Lanza una [CuotasRechazadasException] si el plan no entra.
  Future<PlanDeCuotas> crearPlan(NuevoPlanDeCuotas plan) => _db.transaction(() async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(plan.ventaId) & v.deletedAt.isNull())).getSingleOrNull();
    if (venta == null) throw const CuotasRechazadasException(MotivoPlanDeCuotas.sinVenta);
    if (plan.cuotas.isEmpty) {
      throw const CuotasRechazadasException(MotivoPlanDeCuotas.cantidad);
    }

    // Un segundo toque o un reintento con los mismos ids: no se escribe nada y se responde el plan
    // que quedó.
    final primera = await (_db.select(
      _db.agendas,
    )..where((a) => a.id.equals(plan.cuotas.first.agendaId))).getSingleOrNull();
    if (primera != null) return _plan(venta);

    final actual = await _plan(venta);
    if (actual.tieneCuotasAbiertas) {
      throw const CuotasRechazadasException(MotivoPlanDeCuotas.yaArmado);
    }
    if (!actual.venta.tieneSaldo) {
      throw const CuotasRechazadasException(MotivoPlanDeCuotas.sinSaldo);
    }
    if (actual.cuotas.length + plan.cuotas.length > _tope) {
      throw const CuotasRechazadasException(MotivoPlanDeCuotas.cantidad);
    }
    final montos = [for (final c in plan.cuotas) c.montoCentavos];
    if (!RepartoDeCuotas.montosValidos(montos, actual.venta.saldoCentavos)) {
      throw const CuotasRechazadasException(MotivoPlanDeCuotas.montos);
    }

    for (final cuota in plan.cuotas) {
      final agenda = Agenda(
        id: cuota.agendaId,
        espacioId: actual.espacioId,
        espacioPersonaId: actual.espacioPersonaId,
        tipo: TipoAgenda.cobranza,
        fechaProgramada: cuota.fecha,
        colportorId: plan.colportorId,
        ventaId: plan.ventaId,
        montoPrevistoCentavos: cuota.montoCentavos,
        auditoria: Auditoria(
          createdAt: plan.ahora,
          updatedAt: plan.ahora,
          createdBy: plan.colportorId,
        ),
      );
      await _db.into(_db.agendas).insert(AgendaLocalDataSourceDrift.aFila(agenda));
      await _encolador.encolar(
        'agenda',
        OperacionSync.insert,
        AgendaModel.fromEntity(agenda).toJson(),
      );
    }
    await _recalcular(actual.espacioId, plan.ahora, plan.colportorId);
    return _plan(venta);
  });

  /// Ver [PlanDeCuotasRepository.modificar]. Lanza una [CuotasRechazadasException] si no entra.
  Future<PlanDeCuotas> modificarCuotas(ModificacionDeCuotas pedido) => _db.transaction(() async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(pedido.ventaId) & v.deletedAt.isNull())).getSingleOrNull();
    if (venta == null) throw const CuotasRechazadasException(MotivoPlanDeCuotas.sinVenta);

    final actual = await _plan(venta);
    final porId = {for (final c in actual.cuotas) c.agendaId: c};
    final nuevos = <String, int>{};
    for (final cambio in pedido.cambios) {
      final cuota = porId[cambio.agendaId];
      if (cuota == null || !cuota.sePuedeModificar) {
        throw const CuotasRechazadasException(MotivoPlanDeCuotas.cuotaCerrada);
      }
      if (cambio.montoCentavos <= 0 || cambio.montoCentavos < cuota.pagadoCentavos) {
        throw const CuotasRechazadasException(MotivoPlanDeCuotas.montos);
      }
      nuevos[cambio.agendaId] = cambio.montoCentavos;
    }

    // Entre las abiertas se reparte lo que falta de la venta más lo que ya se les cobró.
    final abiertas = actual.abiertas;
    final porRepartir =
        actual.venta.saldoCentavos + abiertas.fold<int>(0, (a, c) => a + c.pagadoCentavos);
    var suma = 0;
    for (final cuota in abiertas) {
      final monto = nuevos[cuota.agendaId] ?? cuota.montoCentavos;
      if (monto > porRepartir) {
        throw const CuotasRechazadasException(MotivoPlanDeCuotas.montos);
      }
      suma += monto;
    }
    if (suma > porRepartir) throw const CuotasRechazadasException(MotivoPlanDeCuotas.montos);

    var escribio = false;
    for (final cuota in abiertas) {
      final monto = nuevos[cuota.agendaId];
      if (monto == null || monto == cuota.montoCentavos) continue;
      await _escribir(
        cuota.agendaId,
        AgendasCompanion(montoPrevisto: Value(monto), updatedAt: Value(instanteMs(pedido.ahora))),
      );
      escribio = true;
    }
    if (escribio) {
      await cerrarLasCubiertas(pedido.ventaId, ahora: pedido.ahora);
      await _recalcular(actual.espacioId, pedido.ahora, actual.colportorId);
    }
    return _plan(venta);
  });

  // ---- Para otras transacciones --------------------------------------------------------------------

  /// El plan de la venta [venta] tal como está dentro de la transacción en curso.
  Future<PlanDeCuotas> leerPlanDe(VentaFila venta) => _plan(venta);

  /// Pasa a `CUMPLIDA` las citas de cuota de [ventaId] que los cobros ya cubren, y las encola.
  /// Devuelve cuántas cerró. Se llama dentro de la transacción del cobro (o de la modificación).
  Future<int> cerrarLasCubiertas(String ventaId, {required DateTime ahora}) async {
    final estado = await _estado(ventaId);
    for (final id in estado.aCerrar) {
      await _escribir(
        id,
        AgendasCompanion(
          estado: Value(EstadoAgenda.cumplida.codigo),
          updatedAt: Value(instanteMs(ahora)),
        ),
      );
    }
    return estado.aCerrar.length;
  }

  /// La cuota [agendaId] se canceló: su monto pasa a las cuotas que siguen, que se reparten en
  /// partes iguales lo que queda («Plan cuotas» y «Reparto»). Sin cuotas después, no hay a quién
  /// pasárselo y el monto sale del plan (la deuda sigue en la venta). Se llama **antes** de pasar la
  /// cita a `CANCELADA`, dentro de la transacción de cancelar. Devuelve cuántas cuotas cambió.
  Future<int> trasladarLaCancelada(String agendaId, {required DateTime ahora}) async {
    final fila = await (_db.select(_db.agendas)..where((a) => a.id.equals(agendaId))).getSingle();
    final ventaId = fila.ventaId;
    final monto = fila.montoPrevisto;
    if (ventaId == null || monto == null || fila.tipo != TipoAgenda.cobranza.codigo) return 0;

    final estado = await _estado(ventaId);
    final cuota = estado.cuotas.where((c) => c.agendaId == agendaId).firstOrNull;
    if (cuota == null || cuota.estaCubierta) return 0;
    final siguientes = [
      for (final c in estado.cuotas)
        if (c.numero > cuota.numero && c.sePuedeModificar) c,
    ];
    if (siguientes.isEmpty) return 0;

    final total = siguientes.fold<int>(monto, (a, c) => a + c.montoCentavos);
    final partes = RepartoDeCuotas.partesIguales(total, siguientes.length);
    var cambiadas = 0;
    for (var i = 0; i < siguientes.length; i++) {
      if (siguientes[i].montoCentavos == partes[i]) continue;
      await _escribir(
        siguientes[i].agendaId,
        AgendasCompanion(montoPrevisto: Value(partes[i]), updatedAt: Value(instanteMs(ahora))),
      );
      cambiadas++;
    }
    return cambiadas;
  }

  // ---- Privados ------------------------------------------------------------------------------------

  Future<PlanDeCuotas> _plan(VentaFila venta) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((e) => e.id.equals(venta.espacioPersonaId))).getSingleOrNull();
    final estado = await _estado(venta.id);
    final cobrado = await CobroValido.cobradoDe(_db, venta.id);
    return PlanDeCuotas(
      venta: VentaConSaldo(
        ventaId: venta.id,
        numeroTalonario: venta.numeroTalonario,
        fecha: venta.fecha,
        montoTotalCentavos: venta.montoTotal,
        cobradoCentavos: cobrado,
      ),
      espacioId: vinculo?.espacioId ?? '',
      espacioPersonaId: venta.espacioPersonaId,
      colportorId: venta.colportorId,
      cuotas: estado.cuotas,
    );
  }

  Future<EstadoDeLasCuotas> _estado(String ventaId) async {
    final citas =
        await (_db.select(_db.agendas)..where(
              (a) =>
                  a.ventaId.equals(ventaId) &
                  a.tipo.equals(TipoAgenda.cobranza.codigo) &
                  a.montoPrevisto.isNotNull() &
                  a.deletedAt.isNull(),
            ))
            .get();
    if (citas.isEmpty) return const EstadoDeLasCuotas(cuotas: [], aCerrar: []);
    final cobros = await _db
        .customSelect(
          'SELECT c.monto AS monto, c.created_at AS creado FROM cobranza c '
          'WHERE c.venta_id = ? AND ${CobroValido.sql}',
          variables: [Variable<String>(ventaId)],
        )
        .get();
    return RepartoDeCuotas.estadoDe(
      citas: [
        for (final a in citas)
          CitaDeCuota(
            agendaId: a.id,
            fecha: a.fechaProgramada.toLocal(),
            montoCentavos: a.montoPrevisto!,
            estado: EstadoAgenda.desdeCodigo(a.estado),
            creadaEn: a.createdAt,
            actualizadaEn: a.updatedAt,
          ),
      ],
      cobros: [
        for (final c in cobros)
          CobroDelPlan(
            montoCentavos: c.read<int>('monto'),
            creadoEn: DateTime.fromMillisecondsSinceEpoch(c.read<int>('creado'), isUtc: true),
          ),
      ],
    );
  }

  /// Aplica [cambios] a la cita [id], lee la fila resultante y la encola como `update`.
  Future<void> _escribir(String id, AgendasCompanion cambios) async {
    await (_db.update(_db.agendas)..where((a) => a.id.equals(id))).write(cambios);
    final fila = await (_db.select(_db.agendas)..where((a) => a.id.equals(id))).getSingle();
    await _encolador.encolar(
      'agenda',
      OperacionSync.update,
      AgendaModel.fromEntity(AgendaLocalDataSourceDrift.desdeFila(fila)).toJson(),
    );
  }

  /// Recalcula el color de la casa del espacio [espacioId]. Si la ubicación no está en el teléfono no
  /// hay casa que pintar: las cuotas se guardan igual.
  Future<void> _recalcular(String espacioId, DateTime ahora, String colportorId) async {
    final consulta = _db.selectOnly(_db.espacios)
      ..addColumns([_db.espacios.ubicacionId])
      ..where(_db.espacios.id.equals(espacioId));
    final ubicacionId = (await consulta.getSingleOrNull())?.read(_db.espacios.ubicacionId);
    if (ubicacionId == null) return;
    await _estadoDeLasCasas.recalcular(ubicacionId, ahora: ahora, colportorId: colportorId);
  }
}
