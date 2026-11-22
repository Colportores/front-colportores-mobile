import 'package:equatable/equatable.dart';

import 'ubicacion.dart' show TipoUbicacion;

/// Una cobranza sin cobrar de una ubicación: lo que el aviso de bloqueo de la baja dice («$U 1.450
/// (2.ª cuota)», canvas 09·02). Si la ubicación tiene varias ventas con saldo, es la más antigua y
/// [cantidad] dice cuántas son (decisión del 04/11, P4).
final class CobranzaPendiente extends Equatable {
  const CobranzaPendiente({
    required this.montoCentavos,
    this.cantidad = 1,
    this.numeroCuota,
    this.ventaId,
    this.espacioId,
    this.espacioPersonaId,
  });

  /// En centavos, como `Cobranza.montoCentavos` (flutter-clean-arch.md, regla 6).
  final int montoCentavos;

  /// Cuántas ventas de la ubicación tienen saldo (1 o más). Con 2 o más, el aviso lo dice.
  final int cantidad;

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
  List<Object?> get props => [
    montoCentavos,
    cantidad,
    numeroCuota,
    ventaId,
    espacioId,
    espacioPersonaId,
  ];
}

/// Por qué una ubicación no se puede dar de baja (HU-UBI-005, «No se puede dar de baja»).
sealed class BloqueoBaja extends Equatable {
  const BloqueoBaja();
}

/// Tiene una cobranza pendiente: el aviso dice cuánto y de qué cuota, y ofrece «Ir a la cobranza».
/// [tipo] es el de la ubicación: el aviso dice «Una casa», «Un edificio» o «Un negocio».
final class BloqueoPorCobranza extends BloqueoBaja {
  const BloqueoPorCobranza(this.cobranza, {this.tipo = TipoUbicacion.casa});

  final CobranzaPendiente cobranza;
  final TipoUbicacion tipo;

  @override
  List<Object?> get props => [cobranza, tipo];
}

/// Tiene alguna venta (con o sin cobranza pendiente) o una visita registrada por otro colportor
/// (decisión de Cristian, 02/10): el aviso manda a avisarle al coordinador. El aviso dice cuál de las
/// dos cosas es —solo [ventas], solo [visitasDeOtros] o las dos— y el [tipo] de la ubicación
/// (decisión del 04/11, QA P1).
final class BloqueoPorVentasOVisitasAjenas extends BloqueoBaja {
  const BloqueoPorVentasOVisitasAjenas({
    this.ventas = true,
    this.visitasDeOtros = false,
    this.tipo = TipoUbicacion.casa,
  });

  /// Tiene alguna venta, propia o de otro.
  final bool ventas;

  /// Hay una visita registrada por otro colportor.
  final bool visitasDeOtros;
  final TipoUbicacion tipo;

  @override
  List<Object?> get props => [ventas, visitasDeOtros, tipo];
}

/// Lo que una ubicación tiene y que la baja toca o impide (HU-UBI-005).
///
/// Lo sabe el teléfono: lo que no subió todavía cuenta igual. Lo lee `PendientesUbicacionDrift`; sin
/// base abierta o sin sesión queda `PendientesUbicacionSinFuente`, que devuelve la falla de revisión.
/// El servidor es quien hace valer el bloqueo.
final class PendientesUbicacion extends Equatable {
  const PendientesUbicacion({
    this.tipo = TipoUbicacion.casa,
    this.cobranzaPendiente,
    this.tieneVentas = false,
    this.tieneVisitasDeOtros = false,
    this.entrevistasAgendadas = const [],
  });

  static const ninguno = PendientesUbicacion();

  /// De qué tipo es la ubicación: el aviso de las entrevistas dice «Esta casa», «Este edificio» o «Este
  /// negocio» (decisión del 04/11, P2).
  final TipoUbicacion tipo;

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
    if (cobranza != null) return BloqueoPorCobranza(cobranza, tipo: tipo);
    if (tieneVentas || tieneVisitasDeOtros) {
      return BloqueoPorVentasOVisitasAjenas(
        ventas: tieneVentas,
        visitasDeOtros: tieneVisitasDeOtros,
        tipo: tipo,
      );
    }
    return null;
  }

  /// Hay algo que confirmar por segunda vez antes de la baja: entrevistas agendadas. En el teléfono una
  /// «visita pendiente» propia ES una entrevista agendada: no hay otra fuente (decisión del 04/11, P3).
  bool get hayPendientes => entrevistasAgendadas.isNotEmpty;

  /// El aviso de la segunda confirmación: el de la decisión de Cristian del 21/10 («Esta casa tiene 1
  /// entrevista agendada. Si la das de baja, se cancela.»), con «Este edificio» o «Este negocio» según
  /// el tipo (decisión del 04/11, P2). Vacío si no hay pendientes.
  List<String> get resumen {
    final n = entrevistasAgendadas.length;
    if (n == 0) return const [];
    final sujeto = switch (tipo) {
      TipoUbicacion.casa => 'Esta casa',
      TipoUbicacion.edificio => 'Este edificio',
      TipoUbicacion.negocio => 'Este negocio',
    };
    return [
      n == 1
          ? '$sujeto tiene 1 entrevista agendada. Si la das de baja, se cancela.'
          : '$sujeto tiene $n entrevistas agendadas. Si la das de baja, se cancelan.',
    ];
  }

  @override
  List<Object?> get props => [
    tipo,
    cobranzaPendiente,
    tieneVentas,
    tieneVisitasDeOtros,
    entrevistasAgendadas,
  ];
}
