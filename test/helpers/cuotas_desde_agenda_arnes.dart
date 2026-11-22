// Arnés de los tests de #580 (abrir las cuotas desde la cobranza de la Agenda y desde su aviso): una
// cobranza que es cuota del plan de la venta `v-1`, el plan en memoria de esa venta y el detalle de la
// agenda montado con las dos cosas.
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'cuotas_arnes.dart' show hoyDeLasCuotas;
import 'detalle_agenda_arnes.dart';
import 'plan_de_cuotas_arnes.dart';

/// La cobranza de la cuota 2 del plan de la venta `v-1` (\$ 833).
Agenda agendaDeCuota({EstadoAgenda estado = EstadoAgenda.programada, String id = 'ag-1'}) =>
    agendaDelDetalle(
      id: id,
      tipo: TipoAgenda.cobranza,
      estado: estado,
      slot: null,
      ventaId: 'v-1',
      montoPrevistoCentavos: 83300,
    );

/// El plan de la venta `v-1`: tres cuotas semanales sin pagar.
PlanDeCuotasEnMemoria planDeLaVenta() => PlanDeCuotasEnMemoria(
  cuotas: [
    cuotaDe(1, dia: 2, monto: 83300),
    cuotaDe(2, dia: 9, monto: 83300),
    cuotaDe(3, dia: 16, monto: 83400),
  ],
);

/// Lo que hace falta para que la pantalla de cuotas funcione dentro de otra prueba: el plan de la
/// venta y el reloj del cobro.
List<Override> overridesDeLasCuotas(PlanDeCuotasEnMemoria plan) => [
  planDeCuotasRepositoryProvider.overrideWithValue(plan),
  relojCobroProvider.overrideWithValue(() => hoyDeLasCuotas),
];

/// El detalle de [agenda] (por defecto, una cobranza que es cuota) con su plan, ya abierto.
Future<({ArnesDetalle detalle, PlanDeCuotasEnMemoria plan})> montarDetalleDeCuota(
  WidgetTester tester, {
  Agenda? agenda,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final plan = planDeLaVenta();
  addTearDown(plan.cerrar);
  final detalle = await montarDetalle(
    tester,
    detalle: DetalleDeAgenda(agenda: agenda ?? agendaDeCuota()),
    extras: overridesDeLasCuotas(plan),
    escala: escala,
    tamano: tamano,
  );
  return (detalle: detalle, plan: plan);
}
