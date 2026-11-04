import '../../agenda/presentation/formato_agendar_visita.dart';
import '../domain/entities/venta_para_devolver.dart';
import '../domain/services/reglas_de_devolucion.dart';
import 'formato_venta.dart';

/// Los textos de la vista 31 (Devolución de una venta, HU-VEN-004): los del canvas tal cual, y los que
/// el canvas no dibuja marcados «A confirmar» (mapa §2: texto).
///
/// Desde el 03/11 («Devol. saldo», decisión de Cristian) nunca queda plata a favor del cliente: no
/// están «Lo retengo», «Se lo devuelvo ahora», «Se lo devuelvo después», «Pagó de más», «Debo al
/// cliente» ni «Agendar la devolución del dinero» (31-02, 31-03, y la parte de 31-04 y 31-05).
abstract final class TextosDevolucion {
  // --- Del canvas (31-01 a 31-10) ---
  static const titulo = '¿Qué te devuelve?';
  static const tituloTodo = 'Devuelve todo';
  static const tituloFueraDePlazo = 'Devolución';
  static const tituloRegistrada = 'Devolución registrada';
  static const seguir = 'Seguir';
  static const registrarDevolucion = 'Registrar devolución';
  static const reintentar = 'Reintentar';
  static const listo = 'Listo';
  static const volver = 'Volver';
  static const seQuedaCon = 'Se queda con';
  static const yaPago = 'Ya pagó';
  static const saldoNuevo = 'Saldo nuevo';
  static const totalDeLaVenta = 'Total de la venta';
  static const saldo = 'Saldo';
  static const elegiAlMenosUno = 'Elegí al menos un producto.';
  static const hojaTitulo = '¿Registrar la devolución?';
  static const laVentaNoSeBorra = 'La venta original no se borra: queda con la devolución anotada.';
  static const errorAlGuardar = 'No pudimos registrar la devolución. No cambió nada.';
  static const fueraDePlazo =
      'Pasaron más de 72 h desde la venta. La devolución la registra tu coordinador.';
  // De la HU («Solo el coordinador puede registrar devoluciones > 72h»).
  static const soloElCoordinador = 'Solo el coordinador puede registrar devoluciones > 72h';

  // --- De las decisiones de Cristian (23/10 y 27/10) ---
  static const motivo = 'MOTIVO (OPCIONAL)';
  static const avisoMotivo = TextosVenta.avisoMotivo;

  // --- A confirmar (mapa §2: texto), no dibujado en el canvas ---
  static const enLaVenta = 'EN LA VENTA';
  static const motivoHint = 'Por qué te lo devuelve';
  static const cargandoLaVenta = 'Cargando la venta';
  static const registrando = 'Registrando…';
  static const errorDeLectura = 'No pudimos leer la venta guardada en tu teléfono.';
  static const sinLaVenta = 'Esta venta ya no está en tu teléfono. Volvé atrás y elegí otra.';
  static const yaDevuelta = 'Esta venta ya se devolvió por completo. No queda nada para devolver.';

  /// Decisión de Cristian, 03/11, «Devol. saldo»: «si la compra está cerrada (pagó toda la deuda) no se
  /// aceptan devoluciones». Es el texto del servidor (migración 0157, `23514`): la pantalla dice por qué
  /// en vez de dejar empezar.
  static const ventaSaldada =
      'Esta venta ya está saldada: el cliente pagó todo lo que se queda comprando, así que no se '
      'puede devolver nada. Si hay un error, pedile a tu coordinador que lo revise.';
  static const devuelve = 'Devuelve';
  static const eligeAhora = 'Registrá la devolución para ver cómo queda.';

  /// «DEVOLUCIÓN · VENTA 0042».
  static String eyebrow(String talonario) => 'DEVOLUCIÓN · VENTA $talonario';

  /// «VENTA 0042» (la pantalla de fuera de plazo).
  static String eyebrowSolo(String talonario) => 'VENTA $talonario';

  /// «Ya pagó $ 3.300, más de lo que se queda. Ese dinero no se devuelve: la venta queda saldada y
  /// nada queda a favor del cliente.» Va cuando lo devuelto vale más que lo que el cliente debía.
  static String sinDevolver(int centavos) =>
      'Ya pagó ${FormatoVenta.monto(centavos)} más de lo que se queda. Ese dinero no se devuelve: '
      'la venta queda saldada y nada queda a favor del cliente.';

  /// «Vendidos 1 · $ 2.600»; con lo que ya volvió: «Vendidos 3 · ya devolvió 1 · $ 2.600».
  static String vendidos(int cantidad, int devueltos, int precioCentavos) {
    final partes = ['Vendidos $cantidad'];
    if (devueltos > 0) partes.add('ya devolvió $devueltos');
    partes.add(FormatoVenta.monto(precioCentavos));
    return partes.join(' · ');
  }

  /// «María Fernández · pagó $ 4.500 de $ 4.500».
  static String pago(String? nombre, int pagoCentavos, int deQuedaCentavos) {
    final pago =
        'pagó ${FormatoVenta.monto(pagoCentavos)} de ${FormatoVenta.monto(deQuedaCentavos)}';
    return nombre == null || nombre.isEmpty ? _mayuscula(pago) : '$nombre · $pago';
  }

  static String _mayuscula(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  /// «Podés registrarla hasta el martes 15/10 a las 18:20 (72 h desde la venta).», en hora de
  /// Montevideo.
  static String plazo(DateTime fechaDeLaVenta) {
    final limite = ReglasDeDevolucion.limiteDelPlazo(
      fechaDeLaVenta,
    ).toUtc().subtract(const Duration(hours: 3));
    return 'Podés registrarla hasta el ${_enMinuscula(FormatoAgendarVisita.diaLargo(limite))} '
        'a las ${FormatoAgendarVisita.hora(limite)} (72 h desde la venta).';
  }

  static String _enMinuscula(String t) => t.isEmpty ? t : t[0].toLowerCase() + t.substring(1);

  /// «Devuelve Nuestros Hijos» (un renglón), «Devuelve Nuestros Hijos × 2», «Devuelve todo» o
  /// «Devuelve 3 productos» (varios renglones).
  static String tituloDeLaEleccion(
    VentaParaDevolver venta,
    Map<String, int> elegidas,
    bool esTotal,
  ) {
    if (esTotal) return tituloTodo;
    final renglones = [
      for (final r in venta.renglones)
        if ((elegidas[r.ventaItemId] ?? 0) > 0) r,
    ];
    if (renglones.length == 1) {
      final n = elegidas[renglones.single.ventaItemId]!;
      return n == 1
          ? '$devuelve ${renglones.single.titulo}'
          : '$devuelve ${renglones.single.titulo} × $n';
    }
    final unidades = renglones.fold<int>(0, (s, r) => s + elegidas[r.ventaItemId]!);
    return '$devuelve $unidades productos';
  }

  /// «Registramos la devolución de Nuestros Hijos.» (decisión de Cristian, 23/10); de varios
  /// renglones, la cuenta.
  static String registramos(List<String> titulos, {required bool todo}) {
    if (titulos.length == 1) return 'Registramos la devolución de ${titulos.single}.';
    if (todo) return 'Registramos la devolución de toda la venta.';
    return 'Registramos la devolución de ${titulos.length} productos.';
  }

  /// «Nuestros Hijos × 1 · Salud y Hogar × 2» para la hoja de confirmar.
  static String loQueVuelve(VentaParaDevolver venta, Map<String, int> elegidas) => [
    for (final r in venta.renglones)
      if ((elegidas[r.ventaItemId] ?? 0) > 0) '${r.titulo} × ${elegidas[r.ventaItemId]}',
  ].join('\n');
}
