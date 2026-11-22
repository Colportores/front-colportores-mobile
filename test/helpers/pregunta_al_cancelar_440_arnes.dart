// Arnés de las guías de accesibilidad de la pregunta «¿María no te pagó?» (decisión de Cristian, 03/11,
// #440): lleva el diálogo a cada uno de sus estados con el flujo real, en cualquier tamaño y escala.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agenda_repositorio_falso.dart';
import 'agendar_visita_arnes.dart' show asentarAgendar;
import 'cobrar_desde_la_casa_arnes.dart';
import 'persona_falsos.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408;

/// Cada estado del diálogo.
enum EstadoPregunta440 {
  conNombre('«¿Pedro no te pagó?»'),
  nombreLargo('«¿María Guadalupe del Carmen no te pagó?»'),
  sinNombre('«¿No te pagaron?» (la persona ya no está en la casa)'),
  guardando('Anotando la visita…'),
  falla('No pudimos guardar la visita');

  const EstadoPregunta440(this.rotulo);
  final String rotulo;
}

/// Monta el flujo, toca «Cancelar» en C·08 y lleva el diálogo a [estado].
Future<AgendaRepositorioFalso> llegarAPregunta440(
  WidgetTester tester,
  EstadoPregunta440 estado, {
  required Size tamano,
  required double escala,
}) async {
  await cargarFuentes408(tester);
  final agenda = AgendaRepositorioFalso();
  if (estado == EstadoPregunta440.guardando) agenda.compuerta = Completer<void>();
  if (estado == EstadoPregunta440.falla) {
    agenda.resultados.add(const FailureInesperado(causa: 'StateError'));
  }
  await montarCobrarDesdeLaCasa(
    tester,
    repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
    agenda: agenda,
    personas: switch (estado) {
      EstadoPregunta440.nombreLargo => [
        clienteDePersonas('p1', 'María Guadalupe del Carmen', apellido: 'Fernández'),
      ],
      EstadoPregunta440.sinNombre => const [],
      _ => null,
    },
    escala: escala,
    tamano: tamano,
  );
  await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));
  if (estado == EstadoPregunta440.guardando || estado == EstadoPregunta440.falla) {
    final si = find.text('Sí, anotar la visita');
    await tester.ensureVisible(si);
    await tester.pump();
    await tester.tap(si);
    await asentarAgendar(tester);
  }
  return agenda;
}

/// Suelta un guardado que quedó esperando, para que el test no deje nada pendiente.
Future<void> liberarPregunta440(WidgetTester tester, AgendaRepositorioFalso agenda) async {
  final compuerta = agenda.compuerta;
  if (compuerta != null && !compuerta.isCompleted) {
    compuerta.complete();
    await asentarAgendar(tester);
  }
}
