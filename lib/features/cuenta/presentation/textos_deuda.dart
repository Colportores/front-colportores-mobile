import 'dart:math' as math;

import '../domain/entities/deuda_con_la_casa.dart';
import '../domain/entities/resumen_de_cuenta.dart' show CifraDeCuenta;
import 'providers/deuda_casa_providers.dart' show FalloDeLaDeuda;
import 'textos_cuenta.dart';

/// Los textos de la deuda con la casa editora (vista 33B, HU-CTA-002). Los del canvas van tal cual;
/// los demás los dan las decisiones de Cristian y la del agente de decisiones (04/11, mapa §2).
abstract final class TextosDeuda {
  // --- Del canvas (33A·01, 33B·01 a 33B·03) ---
  static const eyebrow = 'MI CUENTA';
  static const titulo = 'Deuda con la casa editora';
  static const rotuloTarjeta = 'DEUDA CON LA CASA EDITORA';
  static const total = 'TOTAL';
  static const pedidosConSaldo = 'PEDIDOS CON SALDO';
  static const sinDeuda = 'No le debés nada a la casa editora';
  static const errorTraer = 'No pudimos traer tus pedidos.';
  static const reintentar = 'Reintentar';

  // --- Los que el canvas no dibuja ---

  /// Sin conexión y sin nada guardado (decisión del 04/11, convención «Necesitás conexión para …»).
  static const necesitasConexion = 'Necesitás conexión para ver tu deuda con la casa editora.';
  static const volver = 'Volver';

  /// Lo que lee el lector de pantalla mientras se pide (33A·03 lo dibuja sin texto).
  static const cargando = 'Cargando tu deuda con la casa editora';

  /// La tarjeta de Mi Cuenta con la primera lectura que falla en la red (decisión del orquestador,
  /// 04/11, por el mapa: estados que no se saben): el mismo tono que 33B·03, con lo que falta.
  static const tarjetaNoDisponible = 'No pudimos traer tu deuda con la casa editora.';

  /// Decisión de Cristian (25/10, «Pago de más»): la deuda no queda en $ 0, se ve «a favor $ X».
  static const aFavor = 'A favor';

  /// Qué pasa con lo pagado de más (decisión de Cristian, 25/10): se descuenta de la próxima deuda.
  static const aFavorExplica = 'Se descuenta de tu próxima deuda con la casa editora.';

  /// Decisión de Cristian (03/11, «Pagado ped.»): el total es la deuda real y la pantalla aclara
  /// cuando los saldos de los pedidos no lo explican.
  static const saldosNoDanElTotal =
      'La suma de los saldos no da el total: una transferencia o el alquiler movieron tu deuda. '
      'El total de arriba es el real.';
}

/// Cómo se escribe la deuda con la casa editora.
abstract final class FormatoDeuda {
  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// «02/10», el día y el mes del pedido en la hora del teléfono.
  static String diaYMes(DateTime fecha) {
    final local = fecha.toLocal();
    return '${_dos(local.day)}/${_dos(local.month)}';
  }

  /// «PEDIDO DEL 02/10».
  static String rotuloDelPedido(PedidoConSaldo pedido) =>
      'PEDIDO DEL ${diaYMes(pedido.fechaPedido)}';

  /// «Saldo $ 15.400».
  static String saldo(PedidoConSaldo pedido) =>
      'Saldo ${FormatoCuenta.monto(pedido.saldoCentavos)}';

  /// «Salud y Hogar × 10 · Nuestros Hijos × 6»; vacío si el pedido no tiene líneas.
  static String productos(PedidoConSaldo pedido) =>
      pedido.lineas.map((l) => '${l.nombre} × ${l.cantidad}').join(' · ');

  /// «Pedido $ 37.400 · pagado $ 22.000».
  static String montoYPagado(PedidoConSaldo pedido) =>
      'Pedido ${FormatoCuenta.monto(pedido.montoCentavos)} · '
      'pagado ${FormatoCuenta.monto(pedido.pagadoCentavos)}';

  /// El total de arriba: «$ 18.400», o «A favor $ 1.200» cuando se pagó de más.
  static String total(DeudaConLaCasa deuda) => deuda.aFavor
      ? '${TextosDeuda.aFavor} ${FormatoCuenta.monto(-deuda.deudaTotalCentavos)}'
      : FormatoCuenta.monto(deuda.deudaTotalCentavos);

  /// Lo mismo para el lector de pantalla.
  static String totalHablado(DeudaConLaCasa deuda) => deuda.aFavor
      ? 'Total, a favor ${FormatoCuenta.monto(-deuda.deudaTotalCentavos)}'
      : 'Total, ${FormatoCuenta.monto(deuda.deudaTotalCentavos)}';

  /// La cifra de la deuda contra la de hace 7 días, con el formato de las otras tarjetas de Mi Cuenta:
  /// «▼ $ 2.100 contra la semana pasada» o «Sin datos de la semana anterior» (33A·01 y 33A·04).
  /// Quedar a favor cuenta como deuda negativa: la diferencia es siempre `hoy − hace 7 días`.
  static CifraDeCuenta cifraDeLaVariacion(DeudaConLaCasa deuda) => CifraDeCuenta(
    totalCentavos: math.max(0, deuda.deudaTotalCentavos),
    variacionCentavos: deuda.variacionCentavos,
  );

  /// La línea de abajo del total de la tarjeta (33A·01).
  static String lineaDeVariacion(DeudaConLaCasa deuda) =>
      FormatoCuenta.lineaDeVariacion(cifraDeLaVariacion(deuda));

  /// Lo mismo para el lector de pantalla: «Bajó $ 2.100 contra la semana pasada».
  static String variacionHablada(DeudaConLaCasa deuda) =>
      FormatoCuenta.variacionHablada(cifraDeLaVariacion(deuda));

  /// Lo que dice el lector de pantalla de un pedido, de una vez.
  static String pedidoHablado(PedidoConSaldo pedido) {
    final productos = FormatoDeuda.productos(pedido);
    return 'Pedido del ${diaYMes(pedido.fechaPedido)}. ${saldo(pedido)}. '
        '${productos.isEmpty ? '' : '$productos. '}${montoYPagado(pedido)}.';
  }

  /// «de hoy», «de ayer» o «del 03/11», según cuándo llegó lo guardado.
  static String _cuando(DateTime leidaEn, DateTime ahora) {
    final momento = leidaEn.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(momento.year, momento.month, momento.day);
    return switch (hoy.difference(dia).inDays) {
      0 => 'de hoy',
      1 => 'de ayer',
      _ => 'del ${_dos(dia.day)}/${_dos(dia.month)}',
    };
  }

  /// El aviso de lo guardado, con su hora (33A·02: «de ayer a las 21:00»). Sin conexión: «Sin
  /// conexión. Esta deuda es de ayer a las 21:00.»; con el servidor caído: «No pudimos actualizarla.
  /// Esta deuda es de ayer a las 21:00.»
  static String avisoDeLoGuardado(FalloDeLaDeuda fallo, DateTime leidaEn, DateTime ahora) {
    final momento = leidaEn.toLocal();
    final cuando = '${_cuando(leidaEn, ahora)} a las ${_dos(momento.hour)}:${_dos(momento.minute)}';
    final inicio = switch (fallo) {
      FalloDeLaDeuda.sinConexion => TextosCuenta.avisoSinConexion,
      FalloDeLaDeuda.noDisponible => 'No pudimos actualizarla',
    };
    return '$inicio. Esta deuda es $cuando.';
  }
}
