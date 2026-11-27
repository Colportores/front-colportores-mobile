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

/// Qué decidió el coordinador con lo pagado de alquiler por quien se dio de baja (HU-CTA-007; backend-supabase
/// 0159, 0167 y 0201). Una decisión por todo lo que estaba por decidir hasta ese momento.
enum DestinoDeLoPagado {
  /// Los pagos de alquiler quedaron anulados: la plata volvió al colportor. No se deshace.
  devolverAlColportor('DEVOLVER_AL_COLPORTOR'),

  /// Queda a cuenta de su próximo depósito: bajó su deuda con la casa editora. Se deshace si vuelve a la
  /// campaña.
  aCuentaDelProximoDeposito('A_CUENTA_PROXIMO_DEPOSITO'),

  /// Se lo queda el coordinador (la campaña). Se deshace si vuelve a la campaña.
  seLoQuedaElCoordinador('SE_LO_QUEDA_EL_COORDINADOR');

  const DestinoDeLoPagado(this.codigo);

  /// El valor que guarda el servidor en `alquiler_decision.decision`.
  final String codigo;

  /// El destino de un código del servidor, o `null` si esta versión de la app no lo conoce: no se
  /// inventa un destino que nadie decidió.
  static DestinoDeLoPagado? desdeCodigo(String codigo) {
    for (final d in values) {
      if (d.codigo == codigo) return d;
    }
    return null;
  }

  /// Esta decisión descuenta de lo «por decidir» (la cuenta de `alquiler_calculado()`, 0167). «Devolver» no
  /// resta: sus pagos ya quedaron anulados y no cuentan como pagados.
  bool get restaDeLoPorDecidir => this != devolverAlColportor;
}

/// Una decisión vigente del coordinador sobre lo pagado de alquiler de una baja (`alquiler_decision`).
/// Sin texto libre: nunca hay una nota del coordinador.
final class DecisionDeAlquiler extends Equatable {
  const DecisionDeAlquiler({
    required this.destino,
    required this.montoCentavos,
    required this.decididaEn,
  });

  final DestinoDeLoPagado destino;

  /// Lo decidido en ese paso, en centavos.
  final int montoCentavos;

  /// Cuándo se decidió (UTC): `created_at` de la decisión, la hora real de su transacción (0181).
  final DateTime decididaEn;

  @override
  List<Object?> get props => [destino, montoCentavos, decididaEn];
}

/// El alquiler de UNA campaña de la que el colportor se dio de baja (HU-CTA-007, 38C con la decisión del
/// coordinador): lo que pagó y qué se decidió con eso. No tiene saldo: quien se da de baja deja de deber el
/// alquiler (decisión «Alq. de baja», 27/10), y lo pagado lo decide el coordinador.
final class AlquilerDeBaja extends Equatable {
  const AlquilerDeBaja({
    required this.campaniaId,
    required this.campania,
    required this.pagos,
    this.decisiones = const [],
  });

  final String campaniaId;

  /// El nombre de la campaña («Otoño 2026»).
  final String campania;

  /// Los pagos de alquiler a esta campaña, el más nuevo primero.
  final List<PagoDeAlquiler> pagos;

  /// Las decisiones vigentes del coordinador, la más nueva primero. Las deshechas (la persona volvió a la
  /// campaña) no están.
  final List<DecisionDeAlquiler> decisiones;

  /// Lo pagado y validado que todavía cuenta (los devueltos no).
  int get pagadoCentavos => pagos
      .where((p) => p.estado == EstadoDePagoDeAlquiler.validado)
      .fold<int>(0, (suma, p) => suma + p.montoCentavos);

  /// Lo que el coordinador todavía tiene que decidir, con la cuenta del servidor (`alquiler_calculado()`,
  /// 0167, y `cuenta_alquiler.alquiler_por_decidir`): lo pagado validado y vigente menos lo ya decidido «a
  /// cuenta» o «se lo queda», sin bajar de 0. Si pagó después de la última decisión, esa diferencia vuelve a
  /// quedar por decidir.
  int get porDecidirCentavos {
    final decidido = decisiones
        .where((d) => d.destino.restaDeLoPorDecidir)
        .fold<int>(0, (suma, d) => suma + d.montoCentavos);
    return math.max(0, pagadoCentavos - decidido);
  }

  /// Algo espera la decisión del coordinador.
  bool get hayPorDecidir => porDecidirCentavos > 0;

  @override
  List<Object?> get props => [campaniaId, campania, pagos, decisiones];
}

/// «Mi alquiler» de todo el colportor: una entrada por cada campaña en la que está inscripto y que
/// cobra alquiler (si está en dos, cada saldo va por separado: decisión de Cristian, 25/10, «Alq.
/// campaña»).
final class AlquilerDelColportor extends Equatable {
  const AlquilerDelColportor({
    required this.campanias,
    this.bajas = const [],
    this.bajadoEn,
    this.trasladadoCentavos = 0,
  });

  /// El colportor no está en ninguna campaña que cobre alquiler.
  static const vacio = AlquilerDelColportor(campanias: []);

  /// Las campañas que cobran alquiler, la más nueva primero.
  final List<AlquilerDeCampania> campanias;

  /// Las campañas de las que se dio de baja y en las que pagó alquiler o el coordinador decidió algo, la
  /// más nueva primero (HU-CTA-007, #740).
  final List<AlquilerDeBaja> bajas;

  /// La última vez que el teléfono bajó datos del servidor (de donde salen el monto y la validación de
  /// cada pago); `null` si todavía no bajó nada.
  final DateTime? bajadoEn;

  /// Hay algo que mostrar: si ninguna campaña cobra alquiler ni hay una baja con lo pagado, la línea de Mi
  /// Cuenta no aparece.
  bool get hayAlquiler => campanias.isNotEmpty || bajas.isNotEmpty;

  /// Lo que falta pagar entre todas las campañas.
  int get saldoCentavos => campanias.fold<int>(0, (suma, c) => suma + c.saldoCentavos);

  /// Lo que espera la decisión del coordinador, sumado entre todas las campañas de baja.
  int get porDecidirCentavos => bajas.fold<int>(0, (suma, b) => suma + b.porDecidirCentavos);

  /// Lo que falta pagar y todavía espera validación, entre todas las campañas.
  int get porValidarCentavos => campanias.fold<int>(0, (suma, c) => suma + c.porValidarCentavos);

  /// Lo pagado de más que el servidor ya pasó a la deuda con la casa editora, en todas las campañas
  /// (`cuenta_colportor.alquiler_trasladado`, backend-supabase 0152): una sola cifra, la que baja con
  /// el sync. 0 si no hay traslado o el teléfono todavía no bajó la cuenta.
  final int trasladadoCentavos;

  /// Hay un traslado que contar (el aviso «Pagaste $ X de más»).
  bool get hayTraslado => trasladadoCentavos > 0;

  @override
  List<Object?> get props => [campanias, bajas, bajadoEn, trasladadoCentavos];
}
