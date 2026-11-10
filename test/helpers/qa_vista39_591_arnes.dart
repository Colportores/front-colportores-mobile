// Arnés de los tests de QA de «la cuota que toca» en la hoja de la casa (vista 39, C·01 y C·02, HU-COB-005,
// #591, PR #634): lleva la hoja a cada estado de la línea «Debe $ 1.200 · cuota sáb 24/10», en la matriz
// de tamaños y escalas de texto, y saca capturas (solo con `--dart-define=QA_CAPTURAS=true`, a
// `.dart_tool/qa_capturas/591_*.png`, gitignored: nunca se commitean).
//
// Las fechas son relativas a «hoy» de la hoja (`ahoraLista`) y se arman con componentes locales, así que
// los tests dan igual en cualquier huso horario.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hoja_casa_falsos.dart' show notaDelCanvas, pedroGomez;
import 'lista_ubicaciones_falsos.dart' show ahoraLista;
import 'persona_falsos.dart';
import 'qa_vista39_445_arnes.dart';

export 'qa_vista39_445_arnes.dart'
    show
        Montaje445,
        cargarFuentes205,
        montarHoja445,
        t320x568,
        t360x640,
        t412x915,
        asentar445,
        sufijo445;

const conCapturas591 = bool.fromEnvironment('QA_CAPTURAS');

/// «Hoy» de la hoja en hora local.
final hoy591 = ahoraLista.toLocal();

/// El día [delta] días de «hoy» (negativo = pasado) a las [hora].
DateTime dia591(int delta, {int hora = 10}) =>
    DateTime(hoy591.year, hoy591.month, hoy591.day + delta, hora);

/// «sáb 24/10», armado a mano (sin usar el formato de producción).
String corto591(DateTime d) {
  const dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dias[d.weekday - 1]} ${dos(d.day)}/${dos(d.month)}';
}

String dm591(DateTime d) => corto591(d).substring(4);

final luis591 = clienteDePersonas('p-luis', 'Luis', apellido: 'Pérez', minutos: 2);

enum Estado591 { proxima, vencida, hoy, sinPlan, sinSaldoConCuota, mixta, larga, sesentaConCuota }

ContextoDeLaCasa contexto591(Estado591 e) {
  switch (e) {
    case Estado591.proxima:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [pedroGomez, ana445],
        saldosCentavos: const {'p-pedro': 120000},
        proximaCuotaDe: {'p-pedro': dia591(4)},
        ultimaEntrevistaDe: {'p-ana': DateTime(2026, 10, 5, 12)},
        nota: notaDelCanvas,
      );
    case Estado591.vencida:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [pedroGomez, ana445],
        saldosCentavos: const {'p-pedro': 120000},
        proximaCuotaDe: {'p-pedro': dia591(-2)},
        ultimaEntrevistaDe: {'p-ana': DateTime(2026, 10, 5, 12)},
        nota: notaDelCanvas,
      );
    case Estado591.hoy:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [pedroGomez],
        saldosCentavos: const {'p-pedro': 120000},
        proximaCuotaDe: {'p-pedro': dia591(0, hora: 9)},
      );
    case Estado591.sinPlan:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [pedroGomez, ana445],
        saldosCentavos: const {'p-pedro': 120000},
        ultimaEntrevistaDe: {'p-ana': DateTime(2026, 10, 5, 12)},
      );
    case Estado591.sinSaldoConCuota:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [pedroGomez, ana445],
        proximaCuotaDe: {'p-pedro': dia591(4), 'p-ana': dia591(-2)},
      );
    case Estado591.mixta:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [pedroGomez, luis591, ana445],
        saldosCentavos: const {'p-pedro': 120000, 'p-luis': 50050},
        proximaCuotaDe: {'p-pedro': dia591(-2), 'p-luis': dia591(4)},
        ultimaEntrevistaDe: {'p-ana': DateTime(2026, 10, 5, 12)},
      );
    case Estado591.larga:
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: [
          clienteDePersonas(
            'p-larga',
            'Maximiliano Alejandro Bartolomé',
            apellido: 'Rodríguez de la Santísima Trinidad y Tobago',
          ),
          ana445,
        ],
        saldosCentavos: const {'p-larga': 123456700},
        proximaCuotaDe: {'p-larga': dia591(-2)},
      );
    case Estado591.sesentaConCuota:
      final filas = [
        for (var i = 0; i < 60; i++)
          clienteDePersonas('p$i', 'Persona', apellido: 'Número ${i + 1}', minutos: i),
      ];
      return ContextoDeLaCasa(
        espacioId: 'esp-1',
        personas: filas,
        saldosCentavos: {for (final f in filas) f.persona.id: 100000 + 100},
        proximaCuotaDe: {
          for (var i = 0; i < filas.length; i++) filas[i].persona.id: dia591(i.isEven ? -2 : 4),
        },
      );
  }
}

Future<Montaje445> llegarA591(
  WidgetTester tester,
  Estado591 estado, {
  required Size tamano,
  required double escala,
  required bool arriba,
}) => montarHoja445(
  tester,
  contexto: contexto591(estado),
  arriba: arriba,
  tamano: tamano,
  escala: escala,
);

Future<void> capturar591(WidgetTester tester, String nombre) async {
  if (!conCapturas591) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/591_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
