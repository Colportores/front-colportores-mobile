import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../../../cobranzas/domain/entities/cobranza.dart' show MedioCobranza;
import '../../../cobranzas/domain/services/reparto_de_cuotas.dart' show CuotasDeUnCobro;
import 'ficha_de_persona.dart' show LineaDeFicha;

/// Con quién fue algo que pasó en la casa (la persona del vínculo de la visita o de la venta). Puede
/// estar dada de baja: lo que pasó con ella no se esconde.
///
/// **PII**: lleva el nombre; no se imprime ni va a los logs (`stringify` apagado).
class PersonaDelEvento extends Equatable {
  const PersonaDelEvento({required this.nombre, this.apellido = ''});

  final String nombre;
  final String apellido;

  /// «Pedro Gómez»; solo el nombre si no tiene apellido; vacío si no tiene ninguno.
  String get nombreCompleto =>
      [nombre, apellido].map((p) => p.trim()).where((p) => p.isNotEmpty).join(' ');

  /// «Pedro»: el nombre de pila, con el que se le habla en una fila («$ 600 en efectivo · Pedro»).
  String get nombreDePila => nombre.trim();

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [nombre, apellido];
}

/// Algo que pasó en una casa (vista 39, C·03 «Historial del lugar»): una visita, una venta o un cobro.
/// Se ordenan por [fecha], el más nuevo primero.
///
/// **PII**: llevan nombres y notas; no se imprimen ni van a los logs (`stringify` apagado).
sealed class EventoDeLaCasa extends Equatable {
  const EventoDeLaCasa({required this.id, required this.fecha});

  final String id;

  /// Cuándo pasó (UTC).
  final DateTime fecha;

  @override
  bool? get stringify => false;
}

/// Una visita (`visita`) con su resultado: «Entrevista dada», «No contestó», «Rechazo» o «Cobranza».
///
/// Una visita `VENTA` que tiene su venta no llega como visita: se ve como la venta, con la nota de la
/// visita (C·03 dibuja «VENTA 0038 … ✎ quiere Nuestros Hijos» y no dos filas). Llega sola si su venta
/// no está (dada de baja o no bajó).
final class VisitaDeLaCasa extends EventoDeLaCasa {
  const VisitaDeLaCasa({
    required super.id,
    required super.fecha,
    required this.resultado,
    this.persona,
    this.nota,
    this.duracion,
  });

  final TipoResultadoVisita resultado;

  /// Con quién fue; `null` si fue de la casa sin persona («No contestó», «Rechazo», una entrevista sin
  /// nombre).
  final PersonaDelEvento? persona;

  /// La nota de la visita (`nota` con `target_type = VISITA`), solo en el teléfono; `null` si no tiene.
  final String? nota;

  /// Cuánto duró la entrevista (salida menos entrada). `null` mientras la visita no guarde las horas
  /// (#466) o si no es una entrevista: no se inventa.
  final Duration? duracion;

  @override
  List<Object?> get props => [id, fecha, resultado, persona, nota, duracion];
}

/// Una venta (`venta`) de la casa con lo que se vendió, lo cobrado y la nota de su visita.
final class VentaDeLaCasa extends EventoDeLaCasa {
  const VentaDeLaCasa({
    required super.id,
    required super.fecha,
    required this.numeroTalonario,
    required this.montoCentavos,
    required this.pagadoCentavos,
    required this.lineas,
    this.persona,
    this.espacioPersonaId,
    this.nota,
  });

  /// El número del talonario («0038»).
  final String numeroTalonario;

  final int montoCentavos;

  /// Lo cobrado de esta venta: la suma de sus cobros válidos.
  final int pagadoCentavos;

  /// Lo que falta cobrar; nunca negativo (una venta cobrada de más no debe nada).
  int get saldoCentavos => montoCentavos > pagadoCentavos ? montoCentavos - pagadoCentavos : 0;

  final List<LineaDeFicha> lineas;

  final PersonaDelEvento? persona;

  /// El vínculo persona–espacio (`espacio_persona`) de la venta: el cliente con el que «Ver la venta»
  /// abre sus cuotas (vista 30 A). `null` si no se sabe.
  final String? espacioPersonaId;

  /// La nota de la visita de la venta, si la tiene.
  final String? nota;

  @override
  List<Object?> get props => [
    id,
    fecha,
    numeroTalonario,
    montoCentavos,
    pagadoCentavos,
    lineas,
    persona,
    espacioPersonaId,
    nota,
  ];
}

/// Un cobro (`cobranza`) de una venta de la casa.
final class CobroDeLaCasa extends EventoDeLaCasa {
  const CobroDeLaCasa({
    required super.id,
    required super.fecha,
    required this.montoCentavos,
    required this.medio,
    required this.ventaId,
    this.numeroTalonario,
    this.persona,
    this.cuotas,
  });

  final int montoCentavos;
  final MedioCobranza medio;

  /// La venta que se cobró. El talonario se puede repetir entre años: lo que une un cobro con su venta
  /// es este `id`, no el número.
  final String ventaId;

  /// El número de la venta que se cobró («0038»).
  final String? numeroTalonario;

  /// A quién se le cobró (la persona de la venta).
  final PersonaDelEvento? persona;

  /// Qué cuotas del plan de la venta cubrió este cobro, calculado con los cobros de la venta hasta
  /// este (`RepartoDeCuotas.cuotasDeCadaCobro`). `null` si la venta no tiene plan.
  final CuotasDeUnCobro? cuotas;

  @override
  List<Object?> get props => [
    id,
    fecha,
    montoCentavos,
    medio,
    ventaId,
    numeroTalonario,
    persona,
    cuotas,
  ];
}
