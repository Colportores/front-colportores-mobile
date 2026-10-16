/// La frase que se escribe para confirmar el borrado de datos locales (HU-AUTH-010, vista 19):
/// `BORRAR-DATOS-<NOMBRE>-<APELLIDO>`, en mayúsculas, sin tildes (`ñ` → `N`) y con guiones en
/// lugar de espacios. Se compara sin distinguir mayúsculas.
abstract final class FraseBorrado {
  static const prefijo = 'BORRAR-DATOS-';

  static const _sinTilde = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };

  static final _alfanumerico = RegExp('[a-z0-9]');
  static final _espacio = RegExp(r'\s');

  /// La frase para [nombreCompleto] («Lucía Silva» → `BORRAR-DATOS-LUCIA-SILVA`), o `null` si el
  /// nombre no tiene ninguna letra ni número (no hay con qué armarla).
  static String? para(String? nombreCompleto) {
    if (nombreCompleto == null) return null;
    final buffer = StringBuffer();
    for (final c in nombreCompleto.trim().toLowerCase().split('')) {
      final limpio = _sinTilde[c] ?? c;
      if (_alfanumerico.hasMatch(limpio)) {
        buffer.write(limpio.toUpperCase());
      } else if (_espacio.hasMatch(limpio) || limpio == '-') {
        buffer.write('-');
      }
    }
    final partes = buffer.toString().split('-').where((p) => p.isNotEmpty);
    if (partes.isEmpty) return null;
    return '$prefijo${partes.join('-')}';
  }

  /// Si [escrito] es la [esperada], sin distinguir mayúsculas y sin los espacios de los bordes.
  static bool coincide(String escrito, String esperada) =>
      escrito.trim().toUpperCase() == esperada.toUpperCase();
}
