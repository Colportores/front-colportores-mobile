import '../../agenda/presentation/formato_agendar_visita.dart';
import '../domain/entities/cobranza.dart';
import '../domain/entities/detalle_del_cobro.dart';
import 'textos_medio_de_cobro.dart';

/// Los textos de la vista 30 B (Detalle del cobro y Anular un cobro, HU-COB-006): los del canvas tal
/// cual, los que cambió una decisión de Cristian, y los que el canvas no dibuja marcados «A confirmar»
/// (mapa §2: texto).
abstract final class TextosAnularCobro {
  // --- Del canvas (30B-01 a 30B-08) ---
  static const eyebrowDetalle = 'COBRO';
  static const eyebrowAnular = 'ANULAR COBRO';
  static const tituloAnular = '¿Por qué lo anulás?';
  static const fecha = 'Fecha';
  static const medio = 'Medio';
  static const estado = 'Estado';
  static const registrado = 'Registrado';
  static const anularCobro = 'Anular cobro';
  static const motivo = 'MOTIVO';
  static const contanosQuePaso = 'CONTANOS QUÉ PASÓ';
  static const eligeElMotivo = 'Elegí el motivo para seguir.';
  static const siAnular = 'Sí, anular';
  static const noVolver = 'No, volver';
  static const reintentar = 'Reintentar';
  static const ticketValidado = 'El ticket de este cobro ya lo validó tu coordinador.';
  static const errorAlAnular = 'No pudimos anular el cobro. Sigue registrado como estaba.';

  /// 30B-06, con la decisión de Cristian del 23/10 («Anular 72 h»): pasadas las 72 h no anula nadie, ni
  /// siquiera el coordinador, así que el canvas ya no dice «desde la app».
  static const fueraDePlazo = 'Pasaron más de 72 h desde el cobro: ya no se puede anular.';

  /// El motivo de la lista tal cual se muestra (30B-02).
  static String motivoDe(MotivoDeAnulacion m) => m.codigo;

  /// «$ 600 en efectivo» (el título de 30B-01).
  static String titulo(String monto, MedioCobranza medio) => switch (medio) {
    MedioCobranza.efectivo => '$monto en efectivo',
    MedioCobranza.tarjeta => '$monto con tarjeta',
    MedioCobranza.transferencia => '$monto por transferencia',
  };

  /// «María Fernández · venta 0042».
  static String subtituloDetalle(String? cliente, String talonario) =>
      '${cliente == null ? '' : '$cliente · '}venta $talonario';

  /// «$ 600 · hoy 14:10 · María Fernández» (la línea de 30B-02).
  static String subtituloAnular(String monto, String cuando, String? cliente) =>
      '$monto · $cuando${cliente == null ? '' : ' · $cliente'}';

  /// «¿Anular el cobro de $ 600?» (30B-04).
  static String confirmarTitulo(String monto) => '¿Anular el cobro de $monto?';

  /// 30B-04: «El saldo de la venta vuelve a $ 1.200 y se resta $ 600 de tu dinero en mano. No se puede
  /// deshacer.» Un cobro con tarjeta o transferencia se resta del dinero depositado (A confirmar,
  /// mapa §2: texto; el canvas solo dibuja el cobro en efectivo).
  static String confirmarTexto(String saldoNuevo, String monto, MedioCobranza medio) {
    final dinero = medio == MedioCobranza.efectivo ? 'en mano' : 'depositado';
    return 'El saldo de la venta vuelve a $saldoNuevo y se resta $monto de tu dinero $dinero. '
        'No se puede deshacer.';
  }

  /// 30B-05: «Cobro anulado. El saldo volvió a $ 1.200.»
  static String anulado(String saldo) => 'Cobro anulado. El saldo volvió a $saldo.';

  /// «Anulado · Monto equivocado» (el estado en 30B-05).
  static String estadoAnulado(MotivoDeAnulacion? motivo) =>
      motivo == null ? 'Anulado' : 'Anulado · ${motivo.codigo}';

  /// 30B-01: «Podés anularlo hasta el sábado 26/10 a las 14:10.» La hora es la de Montevideo.
  static String hastaCuando(DateTime limite) {
    final m = FormatoAnulacion.aMontevideo(limite);
    return 'Podés anularlo hasta el ${FormatoAgendarVisita.diaLargo(m).toLowerCase()} '
        'a las ${FormatoAgendarVisita.hora(m)}.';
  }

  // --- Cambiados por una decisión de Cristian ---

  /// 30B-07 con el ticket validado (decisión del 23/10, «Anular 72 h»): la colportora no anula sola, se
  /// lo pide al coordinador, que lo anula desde el panel. El canvas dejaba el botón con el aviso.
  static const pedirleAlCoordinador = 'Pedíselo a tu coordinador: él lo anula desde el panel.';

  // --- A confirmar (mapa §2: texto) ---
  static const tituloGenerico = 'Cobro';
  static const cargando = 'Cargando el cobro';
  static const errorDeLectura = 'No pudimos leer el cobro guardado en tu teléfono.';
  static const sinElCobro = 'Este cobro ya no está en tu teléfono. Volvé atrás y elegí otro.';
  static const volver = 'Volver';
  static const anulando = 'Anulando…';
  static const cuentanosParaSeguir = 'Contanos qué pasó para seguir.';
  static const contanosHint = 'Escribí qué pasó';

  /// La fecha del cobro en el detalle: «Hoy 14:10», «Ayer 09:30» o «Lun 21/10 14:10».
  static String fechaDelCobro(DateTime fecha, DateTime ahora) {
    final f = FormatoAnulacion.aMontevideo(fecha);
    final hoy = FormatoAnulacion.aMontevideo(ahora);
    final dia = DateTime(f.year, f.month, f.day);
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final hora = FormatoAgendarVisita.hora(f);
    if (dia == hoyDia) return 'Hoy $hora';
    if (dia == DateTime(hoyDia.year, hoyDia.month, hoyDia.day - 1)) return 'Ayer $hora';
    return '${FormatoAgendarVisita.diaCortoYMes(f)} $hora';
  }

  /// «hoy 14:10» / «ayer 09:30» / «lun 21/10 14:10»: la fecha de 30B-02, en minúscula.
  static String fechaEnLaLinea(DateTime fecha, DateTime ahora) {
    final texto = fechaDelCobro(fecha, ahora);
    return texto.replaceFirstMapped(RegExp(r'^[A-ZÁÉÍÓÚ]'), (m) => m[0]!.toLowerCase());
  }

  /// El medio, como se rotula en el detalle.
  static String medioDe(MedioCobranza medio) => switch (medio) {
    MedioCobranza.efectivo => TextosMedioDeCobro.efectivo,
    MedioCobranza.tarjeta => TextosMedioDeCobro.tarjeta,
    MedioCobranza.transferencia => TextosMedioDeCobro.transferencia,
  };
}

/// La hora de Montevideo (UTC-3, sin cambio de horario) para escribir un instante.
abstract final class FormatoAnulacion {
  /// Un `DateTime` cuyos campos (día, hora) son los de Montevideo en [instante]. Solo sirve para
  /// escribirlos, no para compararlo con otros instantes.
  static DateTime aMontevideo(DateTime instante) =>
      instante.toUtc().subtract(const Duration(hours: 3));

  /// El saldo de la venta una vez anulado [cobro]: lo que debía sumado a ese cobro, sin pasar del total.
  static int saldoSinElCobro(DetalleDelCobro detalle) {
    final saldo = detalle.venta.saldoCentavos + detalle.cobranza.montoCentavos;
    final total = detalle.venta.montoTotalCentavos;
    return saldo > total ? total : saldo;
  }
}
