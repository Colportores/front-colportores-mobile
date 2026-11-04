import 'package:equatable/equatable.dart';

/// Una cobranza sin cobrar de una ubicación: lo que el aviso de bloqueo de la baja dice («$U 1.450
/// (2.ª cuota)», canvas 09·02).
final class CobranzaPendiente extends Equatable {
  const CobranzaPendiente({
    required this.montoCentavos,
    this.numeroCuota,
    this.ventaId,
    this.espacioId,
    this.espacioPersonaId,
  });

  /// En centavos, como `Cobranza.montoCentavos` (flutter-clean-arch.md, regla 6).
  final int montoCentavos;

  /// La cuota que se debe, si la venta tiene un plan de cuotas; `null` si se cobra libre (el aviso no
  /// inventa un «N.ª cuota» que la venta no tiene).
  final int? numeroCuota;

  /// La venta que se debe y la casa y el vínculo de esa venta: lo que necesita «Ir a la cobranza»
  /// para abrir el cobro. Sin ellos no hay a dónde ir y la hoja no ofrece el botón.
  final String? ventaId;
  final String? espacioId;
  final String? espacioPersonaId;

  /// Hay a dónde ir a cobrar: la venta y la casa se saben.
  bool get tieneDestino => ventaId != null && espacioId != null;

  @override
  List<Object?> get props => [montoCentavos, numeroCuota, ventaId, espacioId, espacioPersonaId];
}

/// Por qué una ubicación no se puede dar de baja (HU-UBI-005, «No se puede dar de baja»).
sealed class BloqueoBaja extends Equatable {
  const BloqueoBaja();
}

/// Tiene una cobranza pendiente: el aviso dice cuánto y de qué cuota, y ofrece «Ir a la cobranza».
final class BloqueoPorCobranza extends BloqueoBaja {
  const BloqueoPorCobranza(this.cobranza);

  final CobranzaPendiente cobranza;

  @override
  List<Object?> get props => [cobranza];
}

/// Tiene alguna venta (con o sin cobranza pendiente) o una visita registrada por otro colportor
/// (decisión de Cristian, 02/10): el aviso manda a avisarle al coordinador.
final class BloqueoPorVentasOVisitasAjenas extends BloqueoBaja {
  const BloqueoPorVentasOVisitasAjenas();

  @override
  List<Object?> get props => const [];
}

/// Lo que una ubicación tiene y que la baja toca o impide (HU-UBI-005).
///
/// Lo sabe el teléfono: lo que no subió todavía cuenta igual. Lo lee `PendientesUbicacionDrift`; sin
/// base abierta o sin sesión queda `PendientesUbicacionSinFuente`, que devuelve la falla de revisión.
/// El servidor es quien hace valer el bloqueo.
final class PendientesUbicacion extends Equatable {
  const PendientesUbicacion({
    this.visitasPropiasPendientes = 0,
    this.cobranzaPendiente,
    this.tieneVentas = false,
    this.tieneVisitasDeOtros = false,
    this.entrevistasAgendadas = const [],
  });

  static const ninguno = PendientesUbicacion();

  /// Visitas pendientes del propio colportor: no bloquean, piden una segunda confirmación.
  final int visitasPropiasPendientes;

  /// Los `agenda.id` de las entrevistas agendadas (`PROGRAMADA`) de la ubicación, de la réplica de la
  /// agenda del teléfono. No bloquean: piden la segunda confirmación y la baja las cancela en su
  /// misma transacción (decisión de Cristian, 21/10; no se borra nada y quedan canceladas al
  /// reactivar).
  final List<String> entrevistasAgendadas;

  /// Una cobranza sin cobrar. Cuelga de una venta (`cobranza.venta_id` NOT NULL), así que siempre
  /// va con [tieneVentas].
  final CobranzaPendiente? cobranzaPendiente;

  /// Tiene cualquier tipo de venta.
  final bool tieneVentas;

  /// Hay una visita registrada por otro colportor.
  final bool tieneVisitasDeOtros;

  /// Lo que impide la baja, o `null` si se puede. La cobranza pendiente gana: tiene su propio aviso,
  /// con la salida «Ir a la cobranza».
  BloqueoBaja? get bloqueo {
    final cobranza = cobranzaPendiente;
    if (cobranza != null) return BloqueoPorCobranza(cobranza);
    if (tieneVentas || tieneVisitasDeOtros) return const BloqueoPorVentasOVisitasAjenas();
    return null;
  }

  /// Hay algo que confirmar por segunda vez antes de la baja: visitas pendientes propias o entrevistas
  /// agendadas.
  bool get hayPendientes => visitasPropiasPendientes > 0 || entrevistasAgendadas.isNotEmpty;

  /// El aviso de la segunda confirmación: el literal de la HU («Esta ubicación tiene 2 visitas
  /// pendientes. Si la das de baja, no podrás registrar nuevas visitas, pero el historial se
  /// conserva.») y el de la decisión de Cristian del 21/10 («Esta casa tiene 1 entrevista agendada.
  /// Si la das de baja, se cancela.»). Vacío si no hay pendientes.
  List<String> get resumen => [
    if (entrevistasAgendadas.length == 1)
      'Esta casa tiene 1 entrevista agendada. Si la das de baja, se cancela.'
    else if (entrevistasAgendadas.length > 1)
      'Esta casa tiene ${entrevistasAgendadas.length} entrevistas agendadas. '
          'Si la das de baja, se cancelan.',
    if (visitasPropiasPendientes > 0)
      'Esta ubicación tiene $visitasPropiasPendientes '
          '${visitasPropiasPendientes == 1 ? 'visita pendiente' : 'visitas pendientes'}. '
          'Si la das de baja, no podrás registrar nuevas visitas, pero el historial se conserva.',
  ];

  @override
  List<Object?> get props => [
    visitasPropiasPendientes,
    cobranzaPendiente,
    tieneVentas,
    tieneVisitasDeOtros,
    entrevistasAgendadas,
  ];
}
