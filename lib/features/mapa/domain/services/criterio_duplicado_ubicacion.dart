import 'dart:math' as math;

import '../entities/ubicacion.dart';

/// Heurística de duplicado de ubicación (RF-UB08, R-UB08; ADR-004, Supuesto S16 de HU-UBI-001).
///
/// Una ubicación existente es candidata a duplicado de una nueva si se cumplen **todas**:
///
/// 1. está activa (sin soft delete) y es otra fila (otro `id`);
/// 2. es de la misma ciudad (`ciudad_id`);
/// 3. está a [radioMetros] o menos;
/// 4. las dos tienen calle y número, el número es el mismo después de normalizar y la calle se
///    parece en [similitudMinimaCalle] o más (Levenshtein normalizado, ADR-004: "≥ 0.85").
///
/// La normalización ([normalizar]) es **solo para comparar**: pasa a minúsculas, saca acentos y
/// diéresis, `ñ → n` y colapsa los espacios. En la DB queda lo que escribió el colportor (caso
/// borde de HU-UBI-001).
///
/// Sin calle o sin número en alguna de las dos no hay candidata: la proximidad sola marcaría a
/// todos los vecinos (un frente mide menos que 30 m). Es la lectura conservadora de "misma
/// normalización de calle/número"; queda para confirmar en #192.
///
/// Dart puro y sin estado: la usa el alta (HU-UBI-001) dentro de su transacción y la reutiliza el
/// scan de duplicados de HU-UBI-006.
final class CriterioDuplicadoUbicacion {
  const CriterioDuplicadoUbicacion();

  /// HU-UBI-001: "radio ≤ 30 m".
  static const radioMetros = 30.0;

  /// ADR-004 / HU-UBI-006: "Levenshtein ≥ 0.85".
  static const similitudMinimaCalle = 0.85;

  /// `true` si [existente] es candidata a duplicado de [nueva].
  bool esDuplicado(Ubicacion nueva, Ubicacion existente) {
    if (existente.id == nueva.id || existente.estaBorrada) return false;
    if (existente.ciudadId != nueva.ciudadId) return false;
    if (existente.coordenadas.distanciaMetrosA(nueva.coordenadas) > radioMetros) return false;
    final calleNueva = nueva.calle, numeroNuevo = nueva.numero;
    final calleExistente = existente.calle, numeroExistente = existente.numero;
    if (calleNueva == null || numeroNuevo == null) return false;
    if (calleExistente == null || numeroExistente == null) return false;
    if (normalizar(numeroNuevo) != normalizar(numeroExistente)) return false;
    return similitud(normalizar(calleNueva), normalizar(calleExistente)) >= similitudMinimaCalle;
  }

  /// Las candidatas a duplicado de [nueva] entre [existentes], de la más cercana a la más lejana.
  List<Ubicacion> candidatas(Ubicacion nueva, Iterable<Ubicacion> existentes) {
    final encontradas = [
      for (final existente in existentes)
        if (esDuplicado(nueva, existente)) existente,
    ];
    double distancia(Ubicacion u) => u.coordenadas.distanciaMetrosA(nueva.coordenadas);
    encontradas.sort((a, b) => distancia(a).compareTo(distancia(b)));
    return encontradas;
  }

  static const _sinDiacriticos = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
    'ñ': 'n', 'ç': 'c',
  };

  static final _espacios = RegExp(r'\s+');

  /// [texto] en minúsculas, sin acentos ni diéresis, con `ñ → n` y los espacios colapsados.
  static String normalizar(String texto) {
    final minusculas = texto.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in minusculas.runes) {
      final caracter = String.fromCharCode(rune);
      buffer.write(_sinDiacriticos[caracter] ?? caracter);
    }
    return buffer.toString().trim().replaceAll(_espacios, ' ');
  }

  /// Similitud de Levenshtein normalizada: `1 − distancia / largo del más largo`, entre 0 y 1.
  /// Dos textos vacíos son iguales (1).
  static double similitud(String a, String b) {
    final largo = math.max(a.length, b.length);
    if (largo == 0) return 1;
    return 1 - _levenshtein(a, b) / largo;
  }

  /// Distancia de edición (inserciones, borrados y sustituciones) con dos filas de la matriz.
  static int _levenshtein(String a, String b) {
    var anterior = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final actual = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final costo = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        actual[j] = math.min(math.min(actual[j - 1] + 1, anterior[j] + 1), anterior[j - 1] + costo);
      }
      anterior = actual;
    }
    return anterior[b.length];
  }
}
