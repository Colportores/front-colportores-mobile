import '../entities/linea_de_venta.dart';

/// Las reglas puras de una venta (HU-VEN-001), sin pantalla ni base: el total, el talonario y el
/// motivo del monto a mano.
abstract final class ReglasDeVenta {
  /// Lo más largo que puede ser el número de talonario. La HU no fija el largo (es el número impreso
  /// en el papel); el tope evita que un pegado por error llene la pantalla.
  static const largoMaximoTalonario = 30;

  /// Lo más largo que puede ser el motivo del monto a mano, en **puntos de código** (`runes`), la misma
  /// medida que el servidor (`char_length`, backend 0071).
  static const largoMaximoMotivo = 500;

  /// El total calculado de [lineas], en centavos: la suma de lo que cobra cada una. Lo que se regala
  /// («Entregarlos sin cobrar») no suma.
  static int totalCalculado(Iterable<LineaDeVenta> lineas) =>
      lineas.fold(0, (suma, linea) => suma + linea.subtotalCentavos);

  /// El talonario sin los espacios de los bordes. Vacío = falta.
  static String talonario(String texto) => texto.trim();

  /// El motivo listo para guardar: sin espacios ni saltos de línea en los bordes, `null` si queda en
  /// blanco y cortado en [largoMaximoMotivo] puntos de código. **Una venta nunca se rechaza por el
  /// motivo** (decisión de Cristian, 23/10, en backend-supabase#138).
  static String? motivo(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return null;
    final puntos = limpio.runes.toList();
    if (puntos.length <= largoMaximoMotivo) return limpio;
    return String.fromCharCodes(puntos.take(largoMaximoMotivo)).trim();
  }

  /// El año de [instante] en Montevideo: el que usa «talonario único por colportor y año» (Uruguay es
  /// UTC−3 todo el año, sin horario de verano). El 31/12 a las 23:30 en Uruguay ya es el 01/01 en UTC.
  static int anioDeMontevideo(DateTime instante) =>
      instante.toUtc().subtract(const Duration(hours: 3)).year;

  /// El día de Montevideo de [instante], como fecha sin hora (para «venta del 12/03»).
  static DateTime diaDeMontevideo(DateTime instante) {
    final d = instante.toUtc().subtract(const Duration(hours: 3));
    return DateTime(d.year, d.month, d.day);
  }
}
