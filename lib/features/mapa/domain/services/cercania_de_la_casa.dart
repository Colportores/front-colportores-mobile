import 'criterio_duplicado_ubicacion.dart';

/// Cuándo una casa está «lejos» de quien la toca (vista 39, E·05 «Estás a 650 m de esta casa.»).
///
/// Decisión de Cristian del 23/10 («Aviso lejos»): **desde 100 m**, el mismo número de «cerca» de los
/// duplicados de dirección ([CriterioDuplicadoUbicacion.radioMismaDireccionMetros]) y de la Lista: un
/// solo número para «estar en la casa». A 100 m justos ya es lejos, como en los duplicados a 100 m ya
/// son dos lugares.
abstract final class CercaniaDeLaCasa {
  /// La distancia desde la cual la casa cuenta como lejos, en metros.
  static const umbralLejosMetros = CriterioDuplicadoUbicacion.radioMismaDireccionMetros;

  /// ¿Está lejos una casa a [metros] del GPS? Sin distancia (sin GPS) o con una que no existe (NaN,
  /// infinita, negativa) no se afirma nada: `false`.
  static bool estaLejos(double? metros) =>
      metros != null && metros.isFinite && metros >= umbralLejosMetros;
}
