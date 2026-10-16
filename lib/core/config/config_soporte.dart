/// Contacto de soporte de la app (vista 13, A06 «Contactar a soporte», decisión de Cristian del
/// 30/09). El número va en la configuración, no fijo en los widgets: se cambia en compilación con
/// `--dart-define` (README § Desarrollo) sin tocar código.
abstract final class ConfigSoporte {
  /// WhatsApp de soporte, en el formato de `wa.me`: código de país y número, sin `+`, espacios ni
  /// guiones. En Argentina los celulares llevan el 9 después del 54 (+54 3751 530020 →
  /// `5493751530020`). Verificado: `https://wa.me/5493751530020` abre el chat con ese número.
  static const String whatsappNumero = String.fromEnvironment(
    'SOPORTE_WHATSAPP',
    defaultValue: '5493751530020',
  );

  /// El mismo número, como se le muestra al usuario cuando no se pudo abrir WhatsApp.
  static const String whatsappVisible = String.fromEnvironment(
    'SOPORTE_WHATSAPP_VISIBLE',
    defaultValue: '+54 3751 530020',
  );

  /// El mensaje ya escrito: lleva el [codigoError] y ningún dato personal.
  static String mensajeWhatsapp(String codigoError) =>
      'Hola, necesito ayuda con la app Colportores. Código del error: $codigoError';

  /// El enlace que abre el chat de soporte con [mensajeWhatsapp] escrito.
  static Uri enlaceWhatsapp(String codigoError, {String numero = whatsappNumero}) =>
      Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(mensajeWhatsapp(codigoError))}');
}
