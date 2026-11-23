// Arnés de la QA de #516 (PR #736, vista 24 grupo B con la sección AVISOS): los estados del canvas
// 24B·01–06 y los que salen de cruzarlo con el issue (error al leer, sin conexión, horas límite),
// llevados a un tamaño y a una escala de texto.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notificaciones_arnes.dart';

typedef Tamano736 = ({String nombre, double ancho, double alto});

const tamano360x640 = (nombre: '360x640', ancho: 360.0, alto: 640.0);

const tamanos736 = <Tamano736>[tamano360x640, (nombre: '412x915', ancho: 412, alto: 915)];

/// El tamaño chico de reserva del checklist de otras QA (teléfonos de gama baja).
const tamanoChico736 = (nombre: '320x568', ancho: 320.0, alto: 568.0);

const escalas736 = <double>[1.0, 2.0];

final pedidos736 = find.byKey(const Key('aviso_pedidos_interruptor'));
final tickets736 = find.byKey(const Key('aviso_tickets_interruptor'));
final cuotas736 = find.byKey(const Key('aviso_cuotas_interruptor'));
final asignaciones736 = find.byKey(const Key('aviso_asignaciones_interruptor'));
final horaCuota736 = find.byKey(const Key('aviso_cuotas_hora'));
final horaCuotaValor736 = find.byKey(const Key('aviso_cuotas_hora_valor'));
final horaAgenda736 = find.byKey(const Key('aviso_agenda_hora'));
final horaAgendaValor736 = find.byKey(const Key('aviso_agenda_hora_valor'));
final recordatorios736 = find.byKey(const Key('pref_recordatorios_interruptor'));
final errorGuardar736 = find.byKey(const Key('avisos_error_guardar'));
final reintentarGuardar736 = find.byKey(const Key('avisos_error_reintentar'));
final errorLeer736 = find.byKey(const Key('avisos_error_leer'));
final reintentarLeer736 = find.byKey(const Key('avisos_reintentar_leer'));
final cargando736 = find.byKey(const Key('avisos_cargando'));
final atras736 = find.byKey(const Key('notificaciones_atras'));
final pagina736 = find.byKey(const Key('notificaciones_pagina'));

const textoError736 = 'No pudimos guardar el cambio. El interruptor volvió a como estaba.';
const textoErrorHora736 = 'No pudimos guardar la hora. Volvió a como estaba.';
const textoErrorVarios736 = 'No pudimos guardar los cambios. Volvieron a como estaban.';
const textoSinConexion736 =
    'Sin conexión: no pudimos guardar el cambio. Volvió a como estaba. Probá de nuevo cuando '
    'tengas conexión.';
const textoLeerSinConexion736 =
    'Sin conexión: no pudimos leer tus avisos. Probá de nuevo cuando tengas conexión.';

Telefono activado736() => Telefono(estado: EstadoSistemaNotificaciones.activadas);

bool prendido736(WidgetTester tester, Finder f) => tester.widget<SwitchListTile>(f).value;

/// Trae [f] a la vista y lo toca (la pantalla es más alta que el teléfono).
Future<void> tocar736(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

/// Abre la pantalla en [tamano] y [escala].
Future<void> abrir736(
  WidgetTester tester,
  Telefono telefono, {
  Tamano736 tamano = tamano360x640,
  double escala = 1,
}) async {
  fijarTamano(tester, tamano: Size(tamano.ancho, tamano.alto), texto: escala);
  await abrirPantalla(tester, telefono, const NotificacionesPage());
}

/// Los estados de la vista 24 grupo B (sección AVISOS) que se miran en cada tamaño y escala.
enum Estado736 {
  preferencias('24B·01 preferencias'),
  recordatoriosApagados('24B·02 recordatorios apagados'),
  permisoApagado('24B·04 permiso del teléfono apagado'),
  cargando('24B·05 cargando'),
  errorGuardar('24B·06 error al guardar (un interruptor)'),
  errorGuardarSinConexion('24B·06 sin conexión al guardar'),
  errorGuardarHora('24B·06 error al guardar una hora'),
  errorGuardarVarios('24B·06 error al guardar varios cambios'),
  errorLeer('error al leer los avisos'),
  errorLeerSinConexion('sin conexión al leer los avisos'),
  todoApagado('todos los avisos apagados'),
  horasLimite('horas 00:00 y 23:59');

  const Estado736(this.rotulo);

  final String rotulo;

  String get id => name;
}

/// Lleva la pantalla a [estado] en [tamano] y [escala].
Future<Telefono> llevarAlEstado736(
  WidgetTester tester,
  Estado736 estado, {
  Tamano736 tamano = tamano360x640,
  double escala = 1,
}) async {
  final telefono = switch (estado) {
    Estado736.permisoApagado => Telefono(),
    _ => activado736(),
  };
  switch (estado) {
    case Estado736.recordatoriosApagados:
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
    case Estado736.cargando:
      telefono.avisos.lecturaDemorada = Completer<void>();
    case Estado736.errorLeer:
      telefono.avisos.fallaAlLeer = const AvisosServidorException();
    case Estado736.errorLeerSinConexion:
      telefono.avisos.fallaAlLeer = const AvisosSinConexionException();
    case Estado736.todoApagado:
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      telefono.avisos.avisos = const AvisosDelServidor(
        pedidos: false,
        tickets: false,
        cuotas: false,
        asignaciones: false,
        agenda: false,
      );
    case Estado736.horasLimite:
      telefono.avisos.avisos = const AvisosDelServidor(
        horaCuota: HoraDelAviso(0, 0),
        horaAgenda: HoraDelAviso(23, 59),
      );
    default:
      break;
  }
  fijarTamano(tester, tamano: Size(tamano.ancho, tamano.alto), texto: escala);
  if (estado == Estado736.cargando) {
    await abrirPantallaSinEsperar(tester, telefono, const NotificacionesPage());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return telefono;
  }
  await abrirPantalla(tester, telefono, const NotificacionesPage());
  switch (estado) {
    case Estado736.errorGuardar:
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, pedidos736);
      await tester.pumpAndSettle();
    case Estado736.errorGuardarSinConexion:
      telefono.avisos.fallaAlGuardar = const AvisosSinConexionException();
      await tocar736(tester, cuotas736);
      await tester.pumpAndSettle();
    case Estado736.errorGuardarHora:
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 7, 30);
    case Estado736.errorGuardarVarios:
      final demora = Completer<void>();
      telefono.avisos
        ..guardadoDemorado = demora
        ..fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, pedidos736);
      await tester.pump();
      await tocar736(tester, tickets736);
      await tester.pump();
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();
    default:
      break;
  }
  return telefono;
}

/// Elige [hora]:[minuto] en el selector del sistema (escribiéndola) y confirma.
Future<void> elegirHora736(WidgetTester tester, int hora, int minuto) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final campos = find.byType(TextField);
  await tester.enterText(campos.at(0), '$hora');
  await tester.enterText(campos.at(1), '$minuto');
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Cada control de la pantalla, para recorrerla de punta a punta.
List<Finder> controles736() => [
  recordatorios736,
  horaAgenda736,
  pedidos736,
  tickets736,
  cuotas736,
  horaCuota736,
  asignaciones736,
];
