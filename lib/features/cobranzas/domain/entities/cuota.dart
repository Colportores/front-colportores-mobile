import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/estado_agenda.dart';
import 'cobranza.dart' show MedioCobranza;
import 'venta_con_saldo.dart';

/// Cada cuánto vence una cuota del plan (HU-COB-004: semanal o mensual).
enum FrecuenciaDeCuotas {
  semanal,
  mensual;

  /// Cuántas cuotas dice el rótulo de «PLAN · 3 CUOTAS SEMANALES» (30A-04).
  String get adjetivoPlural => this == semanal ? 'SEMANALES' : 'MENSUALES';
}

/// Cómo está una cuota del plan en la lista (30A-04, 30A-06).
enum SituacionDeCuota {
  /// Cubierta del todo (la cita está `CUMPLIDA`).
  pagada,

  /// Se pagó una parte y falta el resto.
  parcial,

  /// Agendada, sin nada pagado, y todavía no venció.
  agendada,

  /// Venció (su día ya pasó) y no está cubierta.
  vencida,
}

/// Una cuota del plan de una venta: una cita de cobranza de la agenda con su fecha y el monto que se
/// espera cobrar (decisión «Plan cuotas» del 23/10: no hay tablas de plan ni de cuotas). Todo en
/// centavos.
///
/// Es una lectura del teléfono: nunca viaja al servidor. Lo que sube es la cita.
final class Cuota extends Equatable {
  const Cuota({
    required this.agendaId,
    required this.numero,
    required this.fecha,
    required this.montoCentavos,
    required this.estado,
    this.pagadoCentavos = 0,
    this.cubiertaEl,
    this.medios = const [],
  });

  /// `agenda.id` de la cita.
  final String agendaId;

  /// Su lugar en el plan, desde 1, por orden de fecha (las canceladas no cuentan).
  final int numero;

  /// Cuándo se espera cobrar (hora del teléfono).
  final DateTime fecha;

  /// Lo que se espera cobrar en la cuota (`monto_previsto`).
  final int montoCentavos;

  /// `PROGRAMADA` (abierta) o `CUMPLIDA` (cubierta).
  final EstadoAgenda estado;

  /// Lo que ya se cobró de esta cuota (los pagos se aplican a la más próxima). Una cuota cubierta
  /// lleva su monto entero.
  final int pagadoCentavos;

  /// El día en que pagó el cliente el cobro que la completó; `null` si no está cubierta o si los
  /// cobros no dicen cómo se cubrió (la cita se cerró de otro modo).
  final DateTime? cubiertaEl;

  /// Los medios de los cobros que la cubrieron, sin repetir y en el orden en que llegaron.
  final List<MedioCobranza> medios;

  bool get estaCubierta => estado == EstadoAgenda.cumplida;

  /// Lo que falta cobrar de la cuota: cero si está cubierta.
  int get faltanCentavos {
    if (estaCubierta) return 0;
    final falta = montoCentavos - pagadoCentavos;
    return falta > 0 ? falta : 0;
  }

  /// Si se puede cambiar su monto (30A-09): la que no está cerrada.
  bool get sePuedeModificar => !estaCubierta;

  /// Cómo se ve la cuota hoy. «Venció» se mide por día: la cuota de hoy todavía no venció.
  SituacionDeCuota situacion(DateTime ahora) {
    if (estaCubierta) return SituacionDeCuota.pagada;
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    if (dia.isBefore(hoy)) return SituacionDeCuota.vencida;
    return pagadoCentavos > 0 ? SituacionDeCuota.parcial : SituacionDeCuota.agendada;
  }

  @override
  List<Object?> get props => [
    agendaId,
    numero,
    fecha,
    montoCentavos,
    estado,
    pagadoCentavos,
    cubiertaEl,
    medios,
  ];
}

/// El plan de cuotas de una venta, tal como está hoy: la venta con su saldo y sus cuotas por orden de
/// fecha. Sin cuotas, la venta se cobra libre (HU-COB-004: «plan opcional»).
final class PlanDeCuotas extends Equatable {
  const PlanDeCuotas({
    required this.venta,
    required this.espacioId,
    required this.espacioPersonaId,
    required this.colportorId,
    required this.cuotas,
  });

  final VentaConSaldo venta;

  /// La casa de la venta: de ahí cuelgan las citas de las cuotas.
  final String espacioId;

  /// El vínculo de la venta: la persona de las citas.
  final String espacioPersonaId;

  final String colportorId;

  /// Las cuotas vivas del plan, `PROGRAMADA` o `CUMPLIDA`, por fecha.
  final List<Cuota> cuotas;

  bool get tienePlan => cuotas.isNotEmpty;

  /// Las que se pueden cambiar.
  List<Cuota> get abiertas => [
    for (final c in cuotas)
      if (c.sePuedeModificar) c,
  ];

  /// Hay plan y todavía quedan cuotas por cobrar.
  bool get tieneCuotasAbiertas => abiertas.isNotEmpty;

  /// La cuota a la que va el próximo pago: la abierta más próxima.
  Cuota? get proxima => abiertas.isEmpty ? null : abiertas.first;

  /// Se puede armar un plan nuevo: hay saldo y no queda ninguna cuota por cobrar.
  bool get sePuedeArmar => venta.tieneSaldo && !tieneCuotasAbiertas;

  @override
  List<Object?> get props => [venta, espacioId, espacioPersonaId, colportorId, cuotas];
}
