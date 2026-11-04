// Arnés de la tercera ronda de QA del paso «¿Con quién?» (#449, PR #463, punta b79b6b9): C·07 cuando
// la segunda línea de dos homónimos también se repite y la fila suma la hora de alta.
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_con_quien_arnes.dart';
import 'persona_falsos.dart';
import 'qa_vista39_449_arnes.dart';
import 'qa_vista39_449_dup_arnes.dart';

/// Un instante en hora local (independiente del huso del contenedor).
DateTime local449(int dia, int hora, int minuto, [int segundo = 0]) =>
    DateTime(2026, 10, dia, hora, minuto, segundo);

/// «23/10» en hora local.
String diaMes449(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

/// «15:40» en hora local.
String hhmm449(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// «Cargada el 23/10 a las 15:40».
String cargadaALas449(DateTime d) => 'Cargada el ${diaMes449(d)} a las ${hhmm449(d)}';

/// Los estados de C·07 donde la segunda línea también se repite.
enum EstadoHora449 { sinTelefonoMismoDia, mismoTelefonoMismoDia, nombreLargoConTelefono, treinta }

List<PersonaDelEspacio> personasHora449(EstadoHora449 estado) => switch (estado) {
  EstadoHora449.sinTelefonoMismoDia => [
    persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40)),
    persona449('b', 'Pedro', apellido: 'Gómez', creada: local449(23, 16, 5)),
    persona449('c', 'Ana', apellido: 'Gómez', creada: local449(23, 16, 5)),
  ],
  EstadoHora449.mismoTelefonoMismoDia => [
    persona449(
      'a',
      'Pedro',
      apellido: 'Gómez',
      telefono: '099 123 412',
      creada: local449(23, 15, 40),
    ),
    persona449(
      'b',
      'Pedro',
      apellido: 'Gómez',
      telefono: '099 555 412',
      creada: local449(23, 16, 5),
    ),
  ],
  EstadoHora449.nombreLargoConTelefono => [
    persona449(
      'l1',
      'María de los Ángeles Nombre Largo',
      apellido: 'Fernández de la Peña y Gómez-Ibáñez',
      telefono: '+598 99 123 456',
      creada: local449(23, 9, 7),
    ),
    persona449(
      'l2',
      'María de los Ángeles Nombre Largo',
      apellido: 'Fernández de la Peña y Gómez-Ibáñez',
      telefono: '+598 98 777 456',
      creada: local449(23, 23, 59),
    ),
  ],
  EstadoHora449.treinta => [
    for (var i = 0; i < 30; i++)
      persona449('h$i', 'Pedro', apellido: 'Gómez', creada: local449(23, 8 + i ~/ 2, i * 2)),
  ],
};

Map<String, int> saldosHora449(EstadoHora449 estado) => switch (estado) {
  EstadoHora449.sinTelefonoMismoDia => {'a': 120000},
  EstadoHora449.nombreLargoConTelefono => {'l1': 123456789},
  _ => const {},
};

Future<ResultadoConQuien> llegarAHora449(
  WidgetTester tester,
  EstadoHora449 estado, {
  Size tamano = t412x915,
  double escala = 1,
}) => montar449(
  tester,
  repo: PersonaRepositorioFalso()..sembrar(personasHora449(estado)),
  saldos: SaldosFalsos(saldosHora449(estado)),
  tamano: tamano,
  escala: escala,
);
