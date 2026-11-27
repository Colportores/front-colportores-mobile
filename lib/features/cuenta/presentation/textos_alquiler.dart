import '../../depositos/domain/entities/deposito.dart';
import '../domain/entities/alquiler.dart';
import 'textos_cuenta.dart';

/// Los textos de «Mi alquiler» (vista 38C, HU-CTA-007). Los del canvas van tal cual; los que el canvas
/// no dibuja dicen «para confirmar» (mapa §2: texto).
abstract final class TextosAlquiler {
  // --- Del canvas (38C·01 a 38C·05, 33A·01) ---
  static const eyebrow = 'MI CUENTA';
  static const titulo = 'Alquiler';

  /// El rótulo de arriba de la cifra: lo que falta, no lo pagado.
  static const teFaltaPagar = 'TE FALTA PAGAR';
  static const alquilerDeLaCampania = 'Alquiler de la campaña';
  static const pagadoValidado = 'Pagado (validado)';
  static const noBloquea = 'Es una deuda: no te frena para vender, pedir ni cobrar.';
  static const pagos = 'PAGOS';
  static const cargarPago = 'Cargar pago de alquiler';
  static const sinAlquiler = 'Esta campaña no cobra alquiler';

  /// La fila de Mi Cuenta (33A·01, la lista de enlaces).
  static const filaDeCuenta = 'Alquiler';

  /// 38C·02: lo que pasa con lo que está por validar.
  static String porValidar(int centavos) =>
      'Tenés ${FormatoCuenta.monto(centavos)} por validar. Se descuentan cuando tu coordinador '
      'valide el ticket.';

  /// El subtítulo de cada campaña: «Primavera 2026 · monto fijo por campaña».
  static String subtitulo(String campania) => '$campania · monto fijo por campaña';

  // --- La campaña de la baja (#740, HU-CTA-007): los textos de la decisión del coordinador los dio el
  // issue (regla R1, 23/11); el resto no está en el canvas (para confirmar) ---

  /// Lo pagado que el coordinador todavía no decidió (o lo que pagó después de la última decisión).
  static const porDecidirDeLaBaja = 'Lo que pagaste queda por decidir: lo decide tu coordinador.';

  /// Lo que decidió el coordinador con lo pagado.
  static String decisionDelCoordinador(DestinoDeLoPagado destino) => switch (destino) {
    DestinoDeLoPagado.devolverAlColportor => 'Tu coordinador decidió devolvértelo.',
    DestinoDeLoPagado.aCuentaDelProximoDeposito =>
      'Tu coordinador lo dejó a cuenta de tu próximo depósito.',
    DestinoDeLoPagado.seLoQuedaElCoordinador => 'Tu coordinador decidió quedárselo.',
  };

  /// El subtítulo de una campaña de la que se dio de baja: no cobra más alquiler, solo queda lo pagado.
  static String subtituloDeBaja(String campania) => '$campania · inscripción dada de baja';

  /// Debajo de cada decisión, de cuánto fue y cuándo se decidió: con dos decisiones se sabe cuál es cuál.
  static String detalleDeLaDecision(DecisionDeAlquiler decision) =>
      '${FormatoCuenta.monto(decision.montoCentavos)} · ${FormatoCuenta.fecha(decision.decididaEn)}';

  /// Debajo de «por decidir», de cuánto es.
  static String detalleDeLoPorDecidir(int centavos) => FormatoCuenta.monto(centavos);

  // --- Los que el canvas no dibuja (para confirmar) ---
  static const volver = 'Volver';
  static const reintentar = 'Reintentar';

  /// Lo que lee el lector de pantalla mientras se arma (38C no dibuja la carga).
  static const cargando = 'Cargando tu alquiler';

  /// Decisión de Cristian (28/10, «Alquiler fav»): lo pagado de más no queda a favor, baja la deuda con
  /// la casa editora, y la pantalla dice de dónde viene.
  static String pagadoDeMas(int centavos) =>
      'Pagaste ${FormatoCuenta.monto(centavos)} de más. Se descontaron de tu deuda con la casa '
      'editora.';

  /// En la deuda con la casa editora (33B): de dónde sale ese descuento.
  static String descontadoPorAlquiler(int centavos) =>
      'Ya descontamos ${FormatoCuenta.monto(centavos)} que pagaste de más en el alquiler.';

  /// 38C·05 con la hora de lo último que bajó el teléfono (el canvas dice «ayer a las 21:00»).
  static String sinConexion(DateTime? bajadoEn, DateTime ahora) => bajadoEn == null
      ? 'Sin conexión. Todavía no bajamos los datos de tu alquiler: conectate para verlos.'
      : 'Sin conexión. Es lo que sabíamos ${FormatoAlquiler.cuando(bajadoEn, ahora)}.';

  /// La fila de Mi Cuenta: lo que falta pagar entre todas las campañas, o que está al día, y si hay plata
  /// de una baja esperando la decisión del coordinador, «· $ X por decidir» (decisiones del 23/11 y 26/11
  /// sobre #740: no se le esconde nada a quien se dio de baja, también con saldo en otra campaña).
  static String resumenDeLaFila(AlquilerDelColportor alquiler) {
    final base = alquiler.saldoCentavos > 0
        ? '${FormatoCuenta.monto(alquiler.saldoCentavos)} por pagar'
        : 'Al día';
    final porDecidir = alquiler.porDecidirCentavos;
    return porDecidir > 0 ? '$base · ${FormatoCuenta.monto(porDecidir)} por decidir' : base;
  }

  // --- Los estados de un pago ---
  static const tagPorValidar = 'Por validar';
  static const tagValidado = 'Validado';
  static const tagRechazado = 'Rechazado';
  static const tagDevuelto = 'Devuelto';
}

/// Cómo se escribe el alquiler.
abstract final class FormatoAlquiler {
  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// «hoy a las 07:05», «ayer a las 21:00» o «el 28/10 a las 09:00», en la hora del teléfono.
  static String cuando(DateTime instante, DateTime ahora) {
    final momento = instante.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(momento.year, momento.month, momento.day);
    final dias = switch (hoy.difference(dia).inDays) {
      0 => 'hoy',
      1 => 'ayer',
      _ => 'el ${_dos(dia.day)}/${_dos(dia.month)}',
    };
    return '$dias a las ${_dos(momento.hour)}:${_dos(momento.minute)}';
  }

  /// «HOY · BANCO», «15/10 · RETIRO»: cuándo y dónde se hizo el pago.
  static String rotuloDelPago(PagoDeAlquiler pago, DateTime ahora) {
    final fecha = pago.fecha.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final esHoy = DateTime(fecha.year, fecha.month, fecha.day) == hoy;
    final cuando = esHoy ? 'HOY' : FormatoCuenta.fecha(pago.fecha);
    final donde = switch (pago.destino) {
      DestinoDeDeposito.banco => 'BANCO',
      DestinoDeDeposito.oficina => 'OFICINA',
      DestinoDeDeposito.retiroCoordinador => 'RETIRO',
    };
    return '$cuando · $donde';
  }

  /// La etiqueta del estado de un pago.
  static String tag(EstadoDePagoDeAlquiler estado) => switch (estado) {
    EstadoDePagoDeAlquiler.porValidar => TextosAlquiler.tagPorValidar,
    EstadoDePagoDeAlquiler.validado => TextosAlquiler.tagValidado,
    EstadoDePagoDeAlquiler.rechazado => TextosAlquiler.tagRechazado,
    EstadoDePagoDeAlquiler.devuelto => TextosAlquiler.tagDevuelto,
  };

  /// Qué pasó con el pago, y qué hacer si hace falta.
  static String explicacion(PagoDeAlquiler pago) => switch (pago.estado) {
    EstadoDePagoDeAlquiler.porValidar => 'Espera la validación de tu coordinador',
    EstadoDePagoDeAlquiler.validado => 'Se acreditó al alquiler',
    EstadoDePagoDeAlquiler.rechazado =>
      pago.motivoDelRechazo == null
          ? 'No se acreditó. Cargalo de nuevo'
          : 'No se acreditó: «${pago.motivoDelRechazo}». Cargalo de nuevo',
    EstadoDePagoDeAlquiler.devuelto => 'Te lo devolvieron: ya no cuenta',
  };

  /// El pago como lo lee el lector de pantalla.
  static String pagoHablado(PagoDeAlquiler pago, DateTime ahora) =>
      '${rotuloDelPago(pago, ahora).replaceAll(' · ', ', ')}. ${FormatoCuenta.monto(pago.montoCentavos)}. '
      '${tag(pago.estado)}. ${explicacion(pago)}.';

  /// La fila de Mi Cuenta como la lee el lector de pantalla.
  static String filaHablada(AlquilerDelColportor alquiler) =>
      '${TextosAlquiler.filaDeCuenta}, ${TextosAlquiler.resumenDeLaFila(alquiler)}';
}
