import '../../agenda/presentation/formato_agendar_visita.dart';

/// Los textos de la vista 28 (Cobro en efectivo, HU-COB-001): los del canvas tal cual, y los que el
/// canvas no dibuja marcados «A confirmar» (mapa §2: texto).
abstract final class TextosCobro {
  // --- Del canvas (28·01 a 28·09) ---
  static const eyebrow = 'COBRO EN EFECTIVO';
  static const titulo = 'Cobrar';
  static const tituloRegistrado = 'Cobro registrado';
  static const monto = 'MONTO';
  static const montoHint = r'$ 0';
  static const fecha = 'FECHA';
  static const cambiar = 'Cambiar';
  static const registrarCobro = 'Registrar cobro';
  static const registrando = 'Registrando…';
  static const reintentar = 'Reintentar';
  static const ingresaElMonto = 'Ingresá el monto que te pagaron.';
  static const hojaTitulo = '¿Cuándo te pagó?';
  static const listo = 'Listo';
  static const hoy = 'Hoy';
  static const ayer = 'Ayer';
  static const otroDia = 'Otro día…';
  static const pagado = 'Pagado';
  static const saldo = 'Saldo';
  static const agendarLaProxima = 'Agendar la próxima cobranza';
  static const ventaPagada = 'Venta pagada';
  static const saldoEnCero =
      'El saldo llegó a cero. Si ya entregaste todo, la casa queda como «Venta completa».';
  static const volverAlMapa = 'Volver al mapa';
  static const errorAlGuardar = 'No pudimos guardar el cobro. No se registró nada: probá de nuevo.';

  /// «El saldo es $ 1.200. Ingresá hasta ese monto.» (28·03).
  static String mayorAlSaldo(String saldo) => 'El saldo es $saldo. Ingresá hasta ese monto.';

  /// «No puede ser antes de la venta (12/10) ni después de hoy.» (28·04); [dia] es «12/10».
  static String fechaFueraDeRango(String dia) =>
      'No puede ser antes de la venta ($dia) ni después de hoy.';

  /// «Sumamos $ 600 a tu dinero en mano. Queda en mano hasta que lo deposites.» (28·06); el monto es
  /// el de ese cobro (decisión del 23/10, P2 de #163).
  static String sumamos(String monto) =>
      'Sumamos $monto a tu dinero en mano. Queda en mano hasta que lo deposites.';

  /// «Venta 0042 · 12/10»: la primera línea del resumen.
  static String ventaDel(String talonario, DateTime dia) =>
      'Venta $talonario · ${FormatoAgendarVisita.diaYMes(dia)}';

  // --- A confirmar (mapa §2: texto) ---
  static const cargandoLaVenta = 'Cargando la venta';
  static const errorDeLectura = 'No pudimos leer la venta guardada en tu teléfono.';
  static const sinSaldo = 'Esta venta no tiene saldo: ya está pagada. No queda nada para cobrar.';
  static const sinLaVenta = 'Esta venta ya no está en tu teléfono. Volvé atrás y elegí otra.';
  static const volver = 'Volver';
  static const cerrar = 'Cerrar';
  static const montoInvalido = 'Escribí un monto válido, por ejemplo 600.';
}

/// Cómo se escribe la fecha del cobro: siempre el día de Montevideo, sin `intl` (es-UY, `DD/MM`).
abstract final class FormatoCobro {
  /// El campo FECHA: «Hoy, 23/10», «Ayer, 22/10» o «Lun 21/10». [dia] y [hoy] son fechas sin hora.
  static String dia(DateTime dia, DateTime hoy) {
    if (FormatoAgendarVisita.mismoDia(dia, hoy)) {
      return '${TextosCobro.hoy}, ${FormatoAgendarVisita.diaYMes(dia)}';
    }
    if (FormatoAgendarVisita.mismoDia(dia, hoy.subtract(const Duration(days: 1)))) {
      return '${TextosCobro.ayer}, ${FormatoAgendarVisita.diaYMes(dia)}';
    }
    return FormatoAgendarVisita.diaCortoYMes(dia);
  }

  /// El mismo día [n] días antes, sin hora y sin saltos por cambio de horario.
  static DateTime diasAntes(DateTime dia, int n) => DateTime(dia.year, dia.month, dia.day - n);

  /// El instante del cobro de un día pasado: el mediodía de Montevideo (UTC-3), así no cae en otro día
  /// por el huso.
  static DateTime alMediodia(DateTime dia) => DateTime.utc(dia.year, dia.month, dia.day, 15);
}
