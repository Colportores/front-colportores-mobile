import '../../agenda/presentation/formato_agendar_visita.dart';
import '../domain/entities/venta_para_devolver.dart';
import '../domain/services/reglas_de_devolucion.dart';
import 'formato_venta.dart';

/// Los textos de la vista 31 (Devolución de una venta, HU-VEN-004): los del canvas tal cual, y los que
/// el canvas no dibuja marcados «A confirmar» (mapa §2: texto).
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
  static const agendarElDinero = 'Agendar la devolución del dinero';
  static const seQuedaCon = 'Se queda con';
  static const yaPago = 'Ya pagó';
  static const pagoDeMas = 'Pagó de más';
  static const saldoNuevo = 'Saldo nuevo';
  static const totalDeLaVenta = 'Total de la venta';
  static const saldo = 'Saldo';
  static const deboAlCliente = 'Debo al cliente';
  static const ahora = 'Se lo devuelvo ahora';
  static const ahoraSub = 'Se resta de tu dinero en mano';
  static const retengo = 'Lo retengo';
  static const retengoSub = 'Como compensación; el saldo queda en cero';
  static const despues = 'Se lo devuelvo después';
  static const despuesSub = 'Queda como «Debo al cliente»';
  static const elegiAlMenosUno = 'Elegí al menos un producto.';
  static const elegiQueHaces = 'Elegí qué hacés con la diferencia.';
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
  static const devuelve = 'Devuelve';
  static const leDevolves = 'Le devolvés ahora';
  static const retenes = 'Retenés';
  static const eligeAhora = 'Registrá la devolución para ver cómo queda.';

  /// «DEVOLUCIÓN · VENTA 0042».
  static String eyebrow(String talonario) => 'DEVOLUCIÓN · VENTA $talonario';

  /// «VENTA 0042» (la pantalla de fuera de plazo).
  static String eyebrowSolo(String talonario) => 'VENTA $talonario';

  /// «¿QUÉ HACÉS CON $ 1.900?».
  static String queHaces(int centavos) => '¿QUÉ HACÉS CON ${FormatoVenta.monto(centavos)}?';

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
