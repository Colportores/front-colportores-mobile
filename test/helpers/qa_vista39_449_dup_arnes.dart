// Arnés de la segunda ronda de QA del paso «¿Con quién?» (#449, PR #463): C·07 con nombres repetidos
// (la segunda línea que distingue a dos personas con el mismo nombre, punta e9b631e).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_con_quien_arnes.dart';
import 'persona_falsos.dart';
import 'qa_vista39_449_arnes.dart';

/// Una persona de la casa con teléfono y fecha de carga a elección.
PersonaDelEspacio persona449(
  String id,
  String nombre, {
  String apellido = '',
  String? telefono,
  DateTime? creada,
}) {
  final t = creada ?? DateTime.utc(2026, 10, 22, 15);
  final a = Auditoria(createdAt: t, updatedAt: t, createdBy: 'col-1');
  return PersonaDelEspacio(
    persona: Persona(id: id, nombre: nombre, apellido: apellido, telefono: telefono, auditoria: a),
    vinculo: EspacioPersona(id: 'ep-$id', espacioId: 'esp-1', personaId: id, auditoria: a),
  );
}

/// Los estados de C·07 con nombres repetidos.
enum EstadoDup449 { dosConTelefono, tresSinTelefonoConSaldo, mezclaLarga, treintaRepetidos }

List<PersonaDelEspacio> personasDup449(EstadoDup449 estado) => switch (estado) {
  EstadoDup449.dosConTelefono => [
    persona449('padre', 'Pedro', apellido: 'Gómez', telefono: '099 123 412'),
    persona449('hijo', 'Pedro', apellido: 'Gómez', telefono: '098 555 777'),
  ],
  EstadoDup449.tresSinTelefonoConSaldo => [
    persona449('a', 'Pedro', apellido: 'Gómez', creada: DateTime.utc(2026, 10, 20, 15)),
    persona449('b', 'Pedro', apellido: 'Gómez', creada: DateTime.utc(2026, 10, 21, 15)),
    persona449('c', 'Pedro', apellido: 'Gómez', creada: DateTime.utc(2026, 10, 22, 15)),
    persona449('d', 'Ana', apellido: 'Gómez'),
  ],
  EstadoDup449.mezclaLarga => [
    persona449(
      'l1',
      'María de los Ángeles Nombre Largo',
      apellido: 'Fernández de la Peña y Gómez-Ibáñez',
      telefono: '+598 99 123 456',
    ),
    persona449(
      'l2',
      'María de los Ángeles Nombre Largo',
      apellido: 'Fernández de la Peña y Gómez-Ibáñez',
    ),
    persona449('l3', 'Ana', apellido: 'Gómez', telefono: '099 000 111'),
  ],
  EstadoDup449.treintaRepetidos => [
    for (var i = 0; i < 30; i++)
      persona449(
        'r$i',
        'Pedro',
        apellido: 'Gómez',
        telefono: i.isEven ? '09${i % 10} 123 4${(10 + i)}' : null,
        creada: DateTime.utc(2026, 9, 1 + i, 15),
      ),
  ],
};

Map<String, int> saldosDup449(EstadoDup449 estado) => switch (estado) {
  EstadoDup449.tresSinTelefonoConSaldo => {'a': 120000, 'c': 5},
  EstadoDup449.mezclaLarga => {'l1': 123456789, 'l2': 150000},
  EstadoDup449.dosConTelefono => {'hijo': 120000},
  EstadoDup449.treintaRepetidos => {'r0': 120000},
};

Future<ResultadoConQuien> llegarADup449(
  WidgetTester tester,
  EstadoDup449 estado, {
  Size tamano = t412x915,
  double escala = 1,
}) => montar449(
  tester,
  repo: PersonaRepositorioFalso()..sembrar(personasDup449(estado)),
  saldos: SaldosFalsos(saldosDup449(estado)),
  tamano: tamano,
  escala: escala,
);
