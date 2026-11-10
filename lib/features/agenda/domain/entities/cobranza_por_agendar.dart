import 'package:equatable/equatable.dart';

/// Una venta con saldo que no tiene ninguna cobranza agendada: la que quedó «Sin fecha» en
/// «¿Cuándo volvés a cobrar?» (vista 42, 42B·01G). La Agenda la muestra en el grupo «Sin fecha», al
/// final, con «Poner fecha» (decisión del 10/11, P4 del PR #681).
///
/// [personaNombre], [personaApellido] y la dirección son datos personales (R-UB09): viven solo en el
/// teléfono y nunca van a un log ni al `toString` (por eso `stringify` está apagado).
class CobranzaPorAgendar extends Equatable {
  const CobranzaPorAgendar({
    required this.ventaId,
    required this.numeroTalonario,
    required this.espacioId,
    required this.espacioPersonaId,
    required this.saldoCentavos,
    this.personaNombre,
    this.personaApellido,
    this.calle,
    this.numero,
  });

  final String ventaId;
  final String numeroTalonario;
  final String espacioId;
  final String espacioPersonaId;

  /// Lo que todavía se debe de la venta, en centavos (siempre más que 0).
  final int saldoCentavos;
  final String? personaNombre;
  final String? personaApellido;
  final String? calle;
  final String? numero;

  /// «Pedro Gómez», o vacío si la persona no está en el teléfono.
  String get nombrePersona => [
    for (final p in [personaNombre, personaApellido])
      if (p != null && p.trim().isNotEmpty) p.trim(),
  ].join(' ');

  /// «Grecia 3307», o vacío si la casa no llegó al teléfono.
  String get direccion => [
    for (final p in [calle, numero])
      if (p != null && p.trim().isNotEmpty) p.trim(),
  ].join(' ');

  @override
  List<Object?> get props => [
    ventaId,
    numeroTalonario,
    espacioId,
    espacioPersonaId,
    saldoCentavos,
    personaNombre,
    personaApellido,
    calle,
    numero,
  ];

  @override
  bool? get stringify => false;
}
