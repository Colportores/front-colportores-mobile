import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/estado_agenda.dart';
import '../entities/cuota.dart';

/// Por qué el monto de una cuota no sirve (30A-02C y los casos que el canvas no dibuja).
enum ProblemaDeCuota {
  /// Vacío o cero: toda cuota espera cobrar algo.
  sinMonto,

  /// Mayor que el saldo de la venta (30A-02C): «El saldo es $ 2.500: la cuota no puede ser mayor.».
  superaElSaldo,

  /// No deja ni un peso para cada cuota que sigue: las siguientes se reparten lo que queda.
  noDejaParaLasSiguientes,

  /// Menor que lo que ya se cobró de esa cuota (al modificar un plan con pagos parciales).
  menorQueLoPagado,
}

/// El resultado de cambiar el monto de una cuota (30A-02B): los montos de todas y cuáles se ajustaron
/// solas.
final class MontosReajustados extends Equatable {
  const MontosReajustados({required this.montos, required this.ajustadas, required this.problemas});

  /// El monto de cada cuota, en centavos, en el orden del plan. Con un problema, las que siguen a la
  /// cuota con el problema quedan en cero (30A-02C).
  final List<int> montos;

  /// Los lugares (desde 0) de las cuotas que se ajustaron solas: «Se ajustó».
  final Set<int> ajustadas;

  /// Los lugares con un monto que no sirve, y por qué.
  final Map<int, ProblemaDeCuota> problemas;

  bool get esValido => problemas.isEmpty;

  @override
  List<Object?> get props => [montos, ajustadas, problemas];
}

/// Qué le pasa a cada cuota cuando entra un pago (30A-05).
final class ParteDePago extends Equatable {
  const ParteDePago({required this.cuota, required this.aplicadoCentavos});

  final Cuota cuota;

  /// Lo que del pago va a esa cuota.
  final int aplicadoCentavos;

  /// Con este pago la cuota queda cubierta.
  bool get completa => aplicadoCentavos >= cuota.faltanCentavos;

  /// Lo que falta de la cuota después del pago.
  int get faltaDespuesCentavos => cuota.faltanCentavos - aplicadoCentavos;

  @override
  List<Object?> get props => [cuota, aplicadoCentavos];
}

/// A qué cuotas va un pago (decisión «Plan cuotas»: a la cita pendiente más próxima; un pago de más
/// pasa a la siguiente y uno de menos deja la cuota activa con lo que falta).
final class AplicacionDePago extends Equatable {
  const AplicacionDePago({required this.partes, required this.sobranteCentavos});

  /// Las cuotas que tocó, en orden.
  final List<ParteDePago> partes;

  /// Lo que no fue a ninguna cuota (el pago supera lo que falta del plan): queda como pago libre.
  final int sobranteCentavos;

  bool get esVacia => partes.isEmpty;

  /// Las cuotas que el pago deja cubiertas.
  List<ParteDePago> get completadas => [
    for (final p in partes)
      if (p.completa) p,
  ];

  /// La cuota que el pago toca sin cubrir (a lo sumo una: la última).
  ParteDePago? get adelanto {
    if (partes.isEmpty || partes.last.completa) return null;
    return partes.last;
  }

  /// El número de la primera cuota a la que va el pago (lo que se guarda en `cobranza.numero_cuota`).
  int? get primeraCuota => partes.isEmpty ? null : partes.first.cuota.numero;

  @override
  List<Object?> get props => [partes, sobranteCentavos];
}

/// Una cita de cobranza con monto, tal cual está guardada, para armar las cuotas.
final class CitaDeCuota extends Equatable {
  const CitaDeCuota({
    required this.agendaId,
    required this.fecha,
    required this.montoCentavos,
    required this.estado,
    required this.creadaEn,
    required this.actualizadaEn,
  });

  final String agendaId;
  final DateTime fecha;
  final int montoCentavos;
  final EstadoAgenda estado;
  final DateTime creadaEn;

  /// La última vez que se tocó la cita: en una `CUMPLIDA`, cuándo se cubrió.
  final DateTime actualizadaEn;

  @override
  List<Object?> get props => [agendaId, fecha, montoCentavos, estado, creadaEn, actualizadaEn];
}

/// Un cobro vivo de la venta, para saber cuánto se cobró desde que se armó el plan.
final class CobroDelPlan extends Equatable {
  const CobroDelPlan({required this.montoCentavos, required this.creadoEn});

  final int montoCentavos;
  final DateTime creadoEn;

  @override
  List<Object?> get props => [montoCentavos, creadoEn];
}

/// Las cuotas tal como están hoy y las que un cobro deja cubiertas.
final class EstadoDeLasCuotas extends Equatable {
  const EstadoDeLasCuotas({required this.cuotas, required this.aCerrar});

  /// Las cuotas vivas por fecha, con lo pagado de cada una. Las que el cobro cubrió figuran cubiertas.
  final List<Cuota> cuotas;

  /// Los `agenda.id` de las citas que están cubiertas y todavía figuran `PROGRAMADA`: hay que
  /// pasarlas a `CUMPLIDA`.
  final List<String> aCerrar;

  @override
  List<Object?> get props => [cuotas, aCerrar];
}

/// Las reglas puras del plan de cuotas (HU-COB-004; decisiones de Cristian del 23/10, «Plan cuotas» y
/// «Reparto»): cuántas, cada cuánto, cuánto vale cada una, qué pasa si se cambia una y a qué cuota va
/// cada pago. Sin pantalla ni base.
abstract final class RepartoDeCuotas {
  /// De 2 a 12 cuotas por plan.
  static const minimo = 2;
  static const maximo = 12;

  /// La hora de la cobranza que se agenda para cada cuota (30A-04: «Agendada · 09/11 10:00»).
  static const horaDeLaCobranza = 10;

  /// El saldo en [cantidad] partes iguales **en pesos enteros**, con la diferencia del redondeo en la
  /// última (30A-01: $ 2.500 en 3 son 833 + 833 + 834). Si no alcanza un peso por cuota, reparte en
  /// centavos. Con [cantidad] menor que uno, vacío.
  static List<int> partesIguales(int totalCentavos, int cantidad) {
    if (cantidad < 1) return const [];
    final cruda = totalCentavos ~/ cantidad;
    final base = cruda >= 100 ? cruda ~/ 100 * 100 : cruda;
    return [for (var i = 0; i < cantidad - 1; i++) base, totalCentavos - base * (cantidad - 1)];
  }

  /// Las fechas de [cantidad] cuotas desde [primera] (solo cuenta el día), a las
  /// [horaDeLaCobranza]. Semanal: cada 7 días. Mensual: el mismo día del mes siguiente; si ese mes no
  /// llega a ese día, el último (31/01 → 28/02), contando siempre desde el día de la primera.
  static List<DateTime> fechas({
    required DateTime primera,
    required int cantidad,
    required FrecuenciaDeCuotas frecuencia,
  }) {
    return [
      for (var i = 0; i < cantidad; i++)
        switch (frecuencia) {
          FrecuenciaDeCuotas.semanal => DateTime(
            primera.year,
            primera.month,
            primera.day + 7 * i,
            horaDeLaCobranza,
          ),
          FrecuenciaDeCuotas.mensual => _mesesDespues(primera, i),
        },
    ];
  }

  static DateTime _mesesDespues(DateTime base, int meses) {
    final indice = base.month - 1 + meses;
    final anio = base.year + indice ~/ 12;
    final mes = indice % 12 + 1;
    final ultimo = DateTime(anio, mes + 1, 0).day;
    final dia = base.day > ultimo ? ultimo : base.day;
    return DateTime(anio, mes, dia, horaDeLaCobranza);
  }

  /// Cambia el monto de la cuota [indice] a [nuevoMonto]: las cuotas anteriores no se tocan y las
  /// siguientes se reparten en partes iguales lo que queda del [saldo] (30A-02B). Si es la última,
  /// no hay a quién ajustar: queda como se puso (siempre que no supere el saldo).
  ///
  /// [pagados] (opcional, un monto por cuota) es lo ya cobrado de cada una: una cuota no baja de ahí.
  static MontosReajustados reajustar({
    required List<int> montos,
    required int indice,
    required int nuevoMonto,
    required int saldo,
    List<int>? pagados,
  }) {
    final nuevos = [...montos];
    nuevos[indice] = nuevoMonto;
    final problemas = <int, ProblemaDeCuota>{};
    final ajustadas = <int>{};

    final minimo = pagados == null ? 0 : pagados[indice];
    final siguientes = montos.length - indice - 1;
    final antes = [for (var i = 0; i < indice; i++) nuevos[i]].fold<int>(0, (a, b) => a + b);
    final queda = saldo - antes - nuevoMonto;

    if (nuevoMonto <= 0) {
      problemas[indice] = ProblemaDeCuota.sinMonto;
    } else if (nuevoMonto > saldo) {
      problemas[indice] = ProblemaDeCuota.superaElSaldo;
    } else if (nuevoMonto < minimo) {
      problemas[indice] = ProblemaDeCuota.menorQueLoPagado;
    } else if (siguientes > 0 && queda < siguientes) {
      problemas[indice] = ProblemaDeCuota.noDejaParaLasSiguientes;
    } else if (siguientes == 0 && antes + nuevoMonto > saldo) {
      problemas[indice] = ProblemaDeCuota.superaElSaldo;
    }

    if (siguientes > 0) {
      if (problemas.isEmpty) {
        final partes = partesIguales(queda, siguientes);
        for (var j = 0; j < siguientes; j++) {
          final lugar = indice + 1 + j;
          if (nuevos[lugar] != partes[j]) ajustadas.add(lugar);
          nuevos[lugar] = partes[j];
        }
      } else {
        for (var lugar = indice + 1; lugar < nuevos.length; lugar++) {
          nuevos[lugar] = 0;
        }
      }
    }
    return MontosReajustados(montos: nuevos, ajustadas: ajustadas, problemas: problemas);
  }

  /// La frecuencia de un plan ya armado, deducida de las fechas de sus cuotas: todas a 7 días
  /// (semanal) o todas al mes siguiente (mensual). `null` con menos de dos cuotas o fechas que se
  /// movieron a mano.
  static FrecuenciaDeCuotas? deducirFrecuencia(List<Cuota> cuotas) {
    if (cuotas.length < 2) return null;
    final dias = [for (final c in cuotas) DateTime(c.fecha.year, c.fecha.month, c.fecha.day)];
    for (final frecuencia in FrecuenciaDeCuotas.values) {
      final esperadas = fechas(primera: dias.first, cantidad: dias.length, frecuencia: frecuencia);
      var coincide = true;
      for (var i = 0; i < dias.length; i++) {
        final e = esperadas[i];
        if (dias[i] != DateTime(e.year, e.month, e.day)) coincide = false;
      }
      if (coincide) return frecuencia;
    }
    return null;
  }

  /// Si el plan armado se puede crear: de [minimo] a [maximo] cuotas, todas con monto, ninguna mayor
  /// que el [saldo] y entre todas no más que el saldo.
  static bool montosValidos(List<int> montos, int saldo) {
    if (montos.length < minimo || montos.length > maximo) return false;
    var suma = 0;
    for (final m in montos) {
      if (m <= 0 || m > saldo) return false;
      suma += m;
    }
    return suma <= saldo;
  }

  /// Arma las cuotas vivas de una venta a partir de sus citas con monto y sus cobros, y dice cuáles
  /// quedan cubiertas.
  ///
  /// Solo cuentan las citas `PROGRAMADA` y `CUMPLIDA` (una cancelada o no cumplida deja de ser cuota).
  /// Lo cobrado para el plan es lo que se cobró desde que se armó (los cobros anteriores bajaron el
  /// saldo que se repartió), menos lo de las cuotas que ya estaban cubiertas; se aplica a las abiertas
  /// en orden de fecha. Así nada se guarda de más: lo pagado de cada cuota sale de los cobros.
  static EstadoDeLasCuotas estadoDe({
    required Iterable<CitaDeCuota> citas,
    required Iterable<CobroDelPlan> cobros,
  }) {
    final vivas = [
      for (final c in citas)
        if (c.estado == EstadoAgenda.programada || c.estado == EstadoAgenda.cumplida) c,
    ]..sort(_porFecha);
    final abiertas = [
      for (final c in vivas)
        if (c.estado == EstadoAgenda.programada) c,
    ];

    var disponible = 0;
    if (abiertas.isNotEmpty) {
      final desde = abiertas.map((c) => c.creadaEn).reduce((a, b) => a.isBefore(b) ? a : b);
      final cobrado = cobros
          .where((c) => !c.creadoEn.isBefore(desde))
          .fold<int>(0, (a, c) => a + c.montoCentavos);
      final yaCubierto = vivas
          .where((c) => c.estado == EstadoAgenda.cumplida && !c.creadaEn.isBefore(desde))
          .fold<int>(0, (a, c) => a + c.montoCentavos);
      disponible = cobrado > yaCubierto ? cobrado - yaCubierto : 0;
    }

    final cuotas = <Cuota>[];
    final aCerrar = <String>[];
    for (var i = 0; i < vivas.length; i++) {
      final cita = vivas[i];
      if (cita.estado == EstadoAgenda.cumplida) {
        cuotas.add(
          _cuota(cita, i + 1, cita.montoCentavos, EstadoAgenda.cumplida, cita.actualizadaEn),
        );
        continue;
      }
      if (disponible >= cita.montoCentavos) {
        disponible -= cita.montoCentavos;
        aCerrar.add(cita.agendaId);
        cuotas.add(_cuota(cita, i + 1, cita.montoCentavos, EstadoAgenda.cumplida));
      } else {
        cuotas.add(_cuota(cita, i + 1, disponible, EstadoAgenda.programada));
        disponible = 0;
      }
    }
    return EstadoDeLasCuotas(cuotas: cuotas, aCerrar: aCerrar);
  }

  static Cuota _cuota(
    CitaDeCuota c,
    int numero,
    int pagado,
    EstadoAgenda estado, [
    DateTime? cubiertaEl,
  ]) => Cuota(
    agendaId: c.agendaId,
    numero: numero,
    fecha: c.fecha,
    montoCentavos: c.montoCentavos,
    estado: estado,
    pagadoCentavos: pagado,
    cubiertaEl: cubiertaEl,
  );

  static int _porFecha(CitaDeCuota a, CitaDeCuota b) {
    final porDia = a.fecha.compareTo(b.fecha);
    if (porDia != 0) return porDia;
    final porCreacion = a.creadaEn.compareTo(b.creadaEn);
    return porCreacion != 0 ? porCreacion : a.agendaId.compareTo(b.agendaId);
  }

  /// A qué cuotas va un pago de [montoCentavos]: a las abiertas en orden, cada una hasta lo que le
  /// falta (30A-05). Las cubiertas no reciben nada.
  static AplicacionDePago aplicarPago(Iterable<Cuota> cuotas, int montoCentavos) {
    var resto = montoCentavos;
    final partes = <ParteDePago>[];
    for (final cuota in cuotas) {
      if (resto <= 0) break;
      if (cuota.estaCubierta || cuota.faltanCentavos <= 0) continue;
      final aplicado = resto < cuota.faltanCentavos ? resto : cuota.faltanCentavos;
      partes.add(ParteDePago(cuota: cuota, aplicadoCentavos: aplicado));
      resto -= aplicado;
    }
    return AplicacionDePago(partes: partes, sobranteCentavos: resto > 0 ? resto : 0);
  }
}
