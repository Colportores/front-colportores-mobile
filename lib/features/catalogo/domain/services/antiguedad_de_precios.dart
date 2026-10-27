/// Cuánto hace que el teléfono bajó los precios y cuándo el aviso se pone fuerte (decisión de
/// Cristian, 23/10, «Precio viejo»): a los N días el aviso de 26·09 le pide conectarse para
/// actualizar, **pero la deja vender**. Nunca frena una venta.
abstract final class AntiguedadDePrecios {
  /// Los N por defecto: es el valor de la fila sembrada de `parametro_global`
  /// (`dias_antiguedad_precios`, backend-supabase 0070) y lo que rige mientras esa fila no llegó al
  /// teléfono.
  static const diasPorDefecto = 15;

  /// Días enteros desde [ultimaBajada] hasta [ahora]; un reloj corrido hacia atrás da 0.
  static int dias(DateTime ultimaBajada, DateTime ahora) {
    final dias = ahora.difference(ultimaBajada).inDays;
    return dias < 0 ? 0 : dias;
  }

  /// `true` desde que pasaron [umbral] días enteros.
  static bool esFuerte(DateTime ultimaBajada, DateTime ahora, {int umbral = diasPorDefecto}) =>
      dias(ultimaBajada, ahora) >= umbral;
}
