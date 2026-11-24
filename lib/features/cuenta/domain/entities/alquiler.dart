import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../../depositos/domain/entities/deposito.dart';

/// En qué punto está un pago de alquiler (HU-CTA-007: «lista de depósitos de alquiler con fecha, monto
/// y estado»). Sale de las columnas del servidor del depósito (`validado_en`, `rechazado_en` y
/// `anulado_at`, backend-supabase 0129, 0152 y 0167).
enum EstadoDePagoDeAlquiler {
  /// El coordinador todavía no lo validó: no baja el saldo.
  porValidar,

  /// Lo validó el coordinador: baja el saldo.
  validado,

  /// Un retiro que la coordinadora rechazó (0152): no baja el saldo y se carga de nuevo.
  rechazado,

  /// Un pago validado que el coordinador devolvió (0167): la plata volvió al colportor y no cuenta.
  devuelto,
}

/// Un depósito con concepto «alquiler» de una campaña (HU-CTA-007, vista 38C): lo que una fila de
/// «PAGOS» necesita.
///
/// No lleva el coordinador que lo validó ni el número de operación: es lo que se ve en una fila.
final class PagoDeAlquiler extends Equatable {
  const PagoDeAlquiler({
    required this.montoCentavos,
    required this.fecha,
    required this.destino,
    required this.estado,
    this.motivoDelRechazo,
  });

  /// Lo depositado, en centavos.
  final int montoCentavos;

  /// Cuándo se depositó (UTC).
  final DateTime fecha;

  final DestinoDeDeposito destino;
  final EstadoDePagoDeAlquiler estado;

  /// Lo que escribió la coordinadora al rechazarlo; solo con [EstadoDePagoDeAlquiler.rechazado] y si
  /// escribió algo. Texto libre: nunca va a un log.
  final String? motivoDelRechazo;

  /// Suma al saldo pagado: solo lo validado y no devuelto.
  bool get cuentaComoPagado => estado == EstadoDePagoDeAlquiler.validado;

  @override
  List<Object?> get props => [montoCentavos, fecha, destino, estado, motivoDelRechazo];
}

/// El alquiler del colportor en una campaña (HU-CTA-007, vista 38C): el monto fijo que cobra la
/// campaña, lo pagado y lo que falta. Una deuda aparte de la de la casa editora: **no bloquea nada**.
///
/// Todo en centavos. El saldo es el monto menos lo pagado **validado** (lo «por validar» se muestra
/// aparte y no lo baja) y nunca queda negativo: lo pagado de más no queda «a favor» sino que baja la
/// deuda con la casa editora (decisión de Cristian, 28/10, «Alquiler fav»; backend-supabase 0152). Cuánto
/// bajó lo dice el servidor en `cuenta_colportor.alquiler_trasladado` ([AlquilerDelColportor.trasladadoCentavos]):
/// el teléfono no lo calcula.
final class AlquilerDeCampania extends Equatable {
  const AlquilerDeCampania({
    required this.campaniaId,
    required this.campania,
    required this.montoCentavos,
    required this.pagos,
  }) : assert(montoCentavos > 0, 'una campaña sin alquiler no tiene AlquilerDeCampania');

  final String campaniaId;

  /// El nombre de la campaña («Primavera 2026»).
  final String campania;

  /// Lo que cobra la campaña a cada inscripto, mayor que cero.
  final int montoCentavos;

  /// Los pagos de alquiler a esta campaña, el más nuevo primero.
  final List<PagoDeAlquiler> pagos;

  /// Lo pagado y validado.
  int get pagadoCentavos => _suma(EstadoDePagoDeAlquiler.validado);

  /// Lo pagado que espera la validación del coordinador.
  int get porValidarCentavos => _suma(EstadoDePagoDeAlquiler.porValidar);

  /// Lo que falta pagar; 0 si ya está pago (o de más).
  int get saldoCentavos => math.max(0, montoCentavos - pagadoCentavos);

  /// No falta nada.
  bool get estaPago => saldoCentavos == 0;

  int _suma(EstadoDePagoDeAlquiler estado) =>
      pagos.where((p) => p.estado == estado).fold<int>(0, (suma, p) => suma + p.montoCentavos);

  @override
  List<Object?> get props => [campaniaId, campania, montoCentavos, pagos];
}

/// «Mi alquiler» de todo el colportor: una entrada por cada campaña en la que está inscripto y que
/// cobra alquiler (si está en dos, cada saldo va por separado: decisión de Cristian, 25/10, «Alq.
/// campaña»).
final class AlquilerDelColportor extends Equatable {
  const AlquilerDelColportor({required this.campanias, this.bajadoEn, this.trasladadoCentavos = 0});

  /// El colportor no está en ninguna campaña que cobre alquiler.
  static const vacio = AlquilerDelColportor(campanias: []);

  /// Las campañas que cobran alquiler, la más nueva primero.
  final List<AlquilerDeCampania> campanias;

  /// La última vez que el teléfono bajó datos del servidor (de donde salen el monto y la validación de
  /// cada pago); `null` si todavía no bajó nada.
  final DateTime? bajadoEn;

  /// Hay algo que mostrar: si ninguna campaña cobra alquiler, la línea de Mi Cuenta no aparece.
  bool get hayAlquiler => campanias.isNotEmpty;

  /// Lo que falta pagar entre todas las campañas.
  int get saldoCentavos => campanias.fold<int>(0, (suma, c) => suma + c.saldoCentavos);

  /// Lo que falta pagar y todavía espera validación, entre todas las campañas.
  int get porValidarCentavos => campanias.fold<int>(0, (suma, c) => suma + c.porValidarCentavos);

  /// Lo pagado de más que el servidor ya pasó a la deuda con la casa editora, en todas las campañas
  /// (`cuenta_colportor.alquiler_trasladado`, backend-supabase 0152): una sola cifra, la que baja con
  /// el sync. 0 si no hay traslado o el teléfono todavía no bajó la cuenta.
  final int trasladadoCentavos;

  /// Hay un traslado que contar (el aviso «Pagaste $ X de más»).
  bool get hayTraslado => trasladadoCentavos > 0;

  @override
  List<Object?> get props => [campanias, bajadoEn, trasladadoCentavos];
}
