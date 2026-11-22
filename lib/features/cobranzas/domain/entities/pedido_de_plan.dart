import 'package:equatable/equatable.dart';

/// Una cuota nueva de un plan que se arma: el id de su cita, cuándo y cuánto.
final class NuevaCuota extends Equatable {
  const NuevaCuota({required this.agendaId, required this.fecha, required this.montoCentavos});

  /// El `agenda.id` de la cita: lo genera quien abre la pantalla y se repite en los reintentos, así
  /// un doble toque o un reintento tras una falla no agenda dos veces.
  final String agendaId;
  final DateTime fecha;
  final int montoCentavos;

  @override
  List<Object?> get props => [agendaId, fecha, montoCentavos];
}

/// El plan que se arma para una venta con saldo (30A-01): sus cuotas, cada una una cobranza por
/// agendar. Todo o nada.
final class NuevoPlanDeCuotas extends Equatable {
  const NuevoPlanDeCuotas({
    required this.ventaId,
    required this.colportorId,
    required this.cuotas,
    required this.ahora,
  });

  final String ventaId;
  final String colportorId;

  /// Las cuotas en orden de fecha.
  final List<NuevaCuota> cuotas;

  /// El instante en que se arma: la creación de las citas.
  final DateTime ahora;

  @override
  List<Object?> get props => [ventaId, colportorId, cuotas, ahora];
}

/// El nuevo monto de una cuota que todavía no está cubierta (30A-09).
final class CambioDeCuota extends Equatable {
  const CambioDeCuota({required this.agendaId, required this.montoCentavos});

  final String agendaId;
  final int montoCentavos;

  @override
  List<Object?> get props => [agendaId, montoCentavos];
}

/// Los montos nuevos de las cuotas abiertas de una venta.
final class ModificacionDeCuotas extends Equatable {
  const ModificacionDeCuotas({required this.ventaId, required this.cambios, required this.ahora});

  final String ventaId;
  final List<CambioDeCuota> cambios;
  final DateTime ahora;

  @override
  List<Object?> get props => [ventaId, cambios, ahora];
}
