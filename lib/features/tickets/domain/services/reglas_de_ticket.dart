import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../entities/ticket.dart';

/// Las reglas del ticket (HU-COB-007), las mismas con las que el servidor rechazaría la fila con
/// `23514` (backend-supabase 0067 y 0113): lo que no pasa acá no entra al teléfono.
abstract final class ReglasDeTicket {
  /// Lo más que cabe en el entero que usa la app para el dinero, en centavos.
  static const maximoCentavos = 2147483647;

  /// El largo máximo del número de autorización y de la marca de la tarjeta.
  static const largoMaximoTexto = 40;

  /// El tope de la foto que acepta el servidor (`foto-ticket`): 2 MiB.
  static const maximoBytesDeLaFoto = 2 * 1024 * 1024;

  /// El techo blando de la compresión (S42): la legibilidad del texto gana sobre este tamaño.
  static const objetivoBytesDeLaFoto = 200 * 1024;

  /// El texto sin espacios de más; `null` si no queda nada.
  static String? limpio(String? texto) {
    final limpio = texto?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  /// El monto es mayor que cero y entra en el entero de la app.
  static bool montoValido(int centavos) => centavos > 0 && centavos <= maximoCentavos;

  /// La fecha no es de mañana: se mide en días de Montevideo, así que sacar el ticket hoy a la noche
  /// no es del futuro.
  static bool fechaValida(DateTime fecha, DateTime ahora) => !ReglasDeVenta.diaDeMontevideo(
    fecha.toUtc(),
  ).isAfter(ReglasDeVenta.diaDeMontevideo(ahora.toUtc()));

  /// Un texto opcional (autorización, marca) cabe en lo que acepta el servidor.
  static bool textoValido(String? texto) => texto == null || texto.length <= largoMaximoTexto;

  /// El número de autorización es obligatorio en el ticket de tarjeta.
  static bool pideAutorizacion(TipoDeTicket tipo) => tipo == TipoDeTicket.cobroTarjeta;

  /// La tarjeta (crédito o débito) es obligatoria en el ticket de tarjeta.
  static bool pideTarjeta(TipoDeTicket tipo) => tipo == TipoDeTicket.cobroTarjeta;

  /// «Si el monto no coincide con el cobro, se avisa antes de subir (no se bloquea)» (HU-COB-007).
  static bool montoDistintoDelCobro({required int montoDelTicket, required int montoDelCobro}) =>
      montoDelTicket != montoDelCobro;

  /// La foto pesa algo y no pasa del tope que acepta el servidor.
  static bool fotoValida(int bytes) => bytes > 0 && bytes <= maximoBytesDeLaFoto;
}
