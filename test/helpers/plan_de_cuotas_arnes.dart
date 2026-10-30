// Un plan de cuotas en memoria para probar los casos de uso y las pantallas de la vista 30 A
// (HU-COB-004, #166) sin base de datos: aplica las mismas reglas que la persistencia (saldo, tope de
// 12, cuotas cerradas) y emite el plan cada vez que cambia.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza;
import 'package:colportores_mobile/features/cobranzas/domain/entities/cuota.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/pedido_de_plan.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/repositories/plan_de_cuotas_repository.dart';
import 'package:colportores_mobile/features/cobranzas/domain/services/reparto_de_cuotas.dart';
import 'package:dartz/dartz.dart';

/// El plan de una venta que vive en memoria.
final class PlanDeCuotasEnMemoria implements PlanDeCuotasRepository {
  PlanDeCuotasEnMemoria({
    int montoCentavos = 250000,
    int cobradoCentavos = 0,
    List<Cuota> cuotas = const [],
    this.talonario = '0042',
  }) : _monto = montoCentavos,
       _cobrado = cobradoCentavos,
       _cuotas = [...cuotas];

  final String talonario;
  final int _monto;
  int _cobrado;
  List<Cuota> _cuotas;
  final _controlador = StreamController<PlanDeCuotas?>.broadcast();

  /// Las veces que se pidió crear / modificar (con o sin éxito).
  int pedidosDeCrear = 0;
  int pedidosDeModificar = 0;

  /// Las cuotas que se crearon en el último pedido.
  NuevoPlanDeCuotas? ultimoPlan;
  ModificacionDeCuotas? ultimoCambio;

  /// Si no es `null`, el próximo pedido de crear / modificar falla con eso una vez.
  Failure? fallaAlCrear;
  Failure? fallaAlModificar;

  /// Retiene el pedido de crear hasta que se complete (para probar el doble toque en vuelo).
  Completer<void>? retenerElCrear;

  /// Retiene la primera lectura del plan hasta que se complete (para ver el estado «cargando»).
  Completer<void>? retenerLaLectura;

  /// Si es `true`, leer y observar fallan.
  bool fallaAlLeer = false;

  /// Si es `true`, la venta no está en el teléfono.
  bool ventaAusente = false;

  PlanDeCuotas get actual => PlanDeCuotas(
    venta: VentaConSaldo(
      ventaId: 'v-1',
      numeroTalonario: talonario,
      fecha: DateTime.utc(2026, 10, 12, 15),
      montoTotalCentavos: _monto,
      cobradoCentavos: _cobrado,
    ),
    espacioId: 'esp-1',
    espacioPersonaId: 'ep-1',
    colportorId: 'col-1',
    cuotas: _cuotas,
  );

  /// Pone el estado de las cuotas y lo cobrado, y avisa.
  void poner({List<Cuota>? cuotas, int? cobradoCentavos}) {
    if (cuotas != null) _cuotas = [...cuotas];
    if (cobradoCentavos != null) _cobrado = cobradoCentavos;
    _controlador.add(ventaAusente ? null : actual);
  }

  @override
  Future<Either<Failure, PlanDeCuotas>> crear(NuevoPlanDeCuotas plan) async {
    pedidosDeCrear++;
    ultimoPlan = plan;
    final espera = retenerElCrear;
    if (espera != null) await espera.future;
    final falla = fallaAlCrear;
    if (falla != null) {
      fallaAlCrear = null;
      return Left(falla);
    }
    if (_cuotas.any((c) => c.agendaId == plan.cuotas.first.agendaId)) return Right(actual);
    if (_cuotas.any((c) => !c.estaCubierta)) {
      return const Left(FailurePlanDeCuotas(MotivoPlanDeCuotas.yaArmado));
    }
    final saldo = _monto - _cobrado;
    if (saldo <= 0) return const Left(FailurePlanDeCuotas(MotivoPlanDeCuotas.sinSaldo));
    if (!RepartoDeCuotas.montosValidos([for (final c in plan.cuotas) c.montoCentavos], saldo)) {
      return const Left(FailurePlanDeCuotas(MotivoPlanDeCuotas.montos));
    }
    _cuotas = [
      ..._cuotas,
      for (var i = 0; i < plan.cuotas.length; i++)
        Cuota(
          agendaId: plan.cuotas[i].agendaId,
          numero: _cuotas.length + i + 1,
          fecha: plan.cuotas[i].fecha,
          montoCentavos: plan.cuotas[i].montoCentavos,
          estado: EstadoAgenda.programada,
        ),
    ];
    _controlador.add(actual);
    return Right(actual);
  }

  @override
  Future<Either<Failure, PlanDeCuotas>> modificar(ModificacionDeCuotas cambios) async {
    pedidosDeModificar++;
    ultimoCambio = cambios;
    final falla = fallaAlModificar;
    if (falla != null) {
      fallaAlModificar = null;
      return Left(falla);
    }
    final porId = {for (final c in cambios.cambios) c.agendaId: c.montoCentavos};
    _cuotas = [
      for (final c in _cuotas)
        if (porId.containsKey(c.agendaId) && c.sePuedeModificar)
          Cuota(
            agendaId: c.agendaId,
            numero: c.numero,
            fecha: c.fecha,
            montoCentavos: porId[c.agendaId]!,
            estado: c.estado,
            pagadoCentavos: c.pagadoCentavos,
          )
        else
          c,
    ];
    _controlador.add(actual);
    return Right(actual);
  }

  @override
  Future<Either<Failure, PlanDeCuotas?>> leer(String ventaId) async {
    if (fallaAlLeer) return const Left(FailureCuotasNoDisponibles());
    return Right(ventaAusente ? null : actual);
  }

  @override
  Stream<PlanDeCuotas?> observar(String ventaId) async* {
    if (fallaAlLeer) throw const FailureCuotasNoDisponibles();
    final espera = retenerLaLectura;
    if (espera != null) await espera.future;
    yield ventaAusente ? null : actual;
    yield* _controlador.stream;
  }

  Future<void> cerrar() => _controlador.close();
}

/// Una cuota para armar un plan de prueba.
Cuota cuotaDe(
  int numero, {
  required int dia,
  int mes = 11,
  required int monto,
  int pagado = 0,
  bool cubierta = false,
  DateTime? cubiertaEl,
  List<MedioCobranza> medios = const [MedioCobranza.efectivo],
}) => Cuota(
  agendaId: 'q-$numero',
  numero: numero,
  fecha: DateTime(2026, mes, dia, 10),
  montoCentavos: monto,
  estado: cubierta ? EstadoAgenda.cumplida : EstadoAgenda.programada,
  pagadoCentavos: cubierta ? monto : pagado,
  cubiertaEl: cubierta ? (cubiertaEl ?? DateTime(2026, 10, 26, 12)) : null,
  medios: cubierta ? medios : const [],
);
