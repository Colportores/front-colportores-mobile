import '../entities/misionero_dejado.dart';

/// Los misioneros que se pueden anotar en «Lo que dejaste» (la hoja de término de la entrevista,
/// #608): los productos vivos de categoría MISIONEROS del catálogo del teléfono, por nombre.
abstract interface class MisionerosParaDejar {
  /// Los misioneros del catálogo, ordenados por nombre. Vacío si no hay ninguno; lanza si no se
  /// puede leer (quien lo usa salta el paso: guardar la entrevista no espera al catálogo).
  Future<List<MisioneroParaDejar>> leer();
}
