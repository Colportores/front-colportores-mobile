import '../entities/nota_de_texto.dart';

/// Cuánto vive una nota de persona en «Ver borradas» (HU-UBI-012, decisión de Cristian del 27/10): 90
/// días desde que se borró, como el historial del centro de notificaciones. Pasado ese plazo la nota se
/// borra para siempre del teléfono.
///
/// Una sola regla para los tres que la usan: la limpieza (`LimpiarNotasBorradasUseCase`), lo que
/// «Ver borradas» deja de mostrar y el «Se borra el 25/01» de cada nota.
abstract final class RetencionNotasBorradas {
  /// Los 90 días.
  static const duracion = Duration(days: 90);

  /// El instante en que se va una nota borrada en [borradaEl]: 90 días después.
  static DateTime seVaEl(DateTime borradaEl) => borradaEl.add(duracion);

  /// La nota borrada en [borradaEl] ya pasó de los 90 días a la hora [ahora]: no se muestra y la
  /// limpieza la borra. Justo a los 90 días todavía está.
  static bool vencida(DateTime borradaEl, DateTime ahora) => ahora.isAfter(seVaEl(borradaEl));

  /// La nota está en «Ver borradas» a la hora [ahora]: borrada y todavía dentro de los 90 días.
  static bool estaEnBorradas(NotaDeTexto nota, DateTime ahora) {
    final borrada = nota.auditoria.deletedAt;
    return borrada != null && !vencida(borrada, ahora);
  }

  /// El corte de la limpieza: las borradas **antes** de este instante ya pasaron de los 90 días.
  static DateTime corte(DateTime ahora) => ahora.subtract(duracion);
}
