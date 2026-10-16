import 'package:equatable/equatable.dart';

/// Una cobranza sin cobrar de una ubicación: lo que el aviso de bloqueo de la baja dice («$U 1.450
/// (2.ª cuota)», canvas 09·02).
final class CobranzaPendiente extends Equatable {
  const CobranzaPendiente({required this.montoCentavos, required this.numeroCuota});

  /// En centavos, como `Cobranza.montoCentavos` (flutter-clean-arch.md, regla 6).
  final int montoCentavos;

  final int numeroCuota;

  @override
  List<Object?> get props => [montoCentavos, numeroCuota];
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
/// Lo sabe el teléfono: lo que no subió todavía cuenta igual. Las visitas y las ventas todavía no
/// existen en la DB local, así que hasta que lleguen el adaptador de producción devuelve la falla de
/// revisión (ver `PendientesUbicacionSinFuente`); el servidor es quien hace valer el bloqueo.
final class PendientesUbicacion extends Equatable {
  const PendientesUbicacion({
    this.visitasPropiasPendientes = 0,
    this.cobranzaPendiente,
    this.tieneVentas = false,
    this.tieneVisitasDeOtros = false,
  });

  static const ninguno = PendientesUbicacion();

  /// Visitas pendientes del propio colportor: no bloquean, piden una segunda confirmación.
  final int visitasPropiasPendientes;

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

  /// Hay algo que confirmar por segunda vez antes de la baja: visitas pendientes propias.
  bool get hayPendientes => visitasPropiasPendientes > 0;

  /// El aviso de la segunda confirmación, el literal de la HU («Esta ubicación tiene 2 visitas
  /// pendientes. Si la das de baja, no podrás registrar nuevas visitas, pero el historial se
  /// conserva.»). Vacío si no hay pendientes.
  List<String> get resumen => [
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
  ];
}
