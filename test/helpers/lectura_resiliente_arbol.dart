// Helper compartido para tests que recorren el árbol de `lib/` y leen archivos `.dart`.
//
// Issue #83: `dominio_puro_test.dart` fallaba de forma intermitente por una carrera (TOCTOU)
// entre sacar una foto del árbol con `listSync(recursive: true)` y, en un segundo momento, leer
// cada archivo de esa foto con `readAsLinesSync()`. Si un archivo dejaba de existir o quedaba
// inaccesible entre los dos pasos, `readAsLinesSync()` lanzaba `FileSystemException` sin capturar
// y tiraba abajo el test.
//
// Decisión de Cristian (23/09, issue #83): un solo recorrido con `dir.list(recursive: true)`
// (stream), leyendo cada `.dart` en el momento en que aparece — no en una segunda pasada sobre
// una foto completa. Si la lectura falla con `FileSystemException`, se espera ~100 ms y se
// reintenta una vez: si el archivo ya no existe, se ignora (ya no es código); si existe y sigue
// fallando, el test falla — nunca se traga la excepción en silencio.
import 'dart:io';

import 'package:test/test.dart';

/// Un archivo `.dart` ya leído: su [path] y sus [lineas].
class ArchivoDartLeido {
  const ArchivoDartLeido(this.path, this.lineas);

  final String path;
  final List<String> lineas;
}

/// Firma de la función que lee las líneas de un archivo. Solo se inyecta un valor distinto del
/// default en el propio test de este helper, para simular una lectura que falla sin depender de
/// una carrera real del filesystem (no sería determinístico).
typedef LectorDeLineas = List<String> Function(File archivo);

/// Filtro por default: archivos `.dart` que no sean código generado (`.g.dart`).
bool esDartNoGenerado(File archivo) =>
    archivo.path.endsWith('.dart') && !archivo.path.endsWith('.g.dart');

List<String> _leerSync(File archivo) => archivo.readAsLinesSync();

/// Recorre [dir] con un solo pasada de `dir.list(recursive: true)` y lee cada archivo que cumpla
/// [incluir] en el momento en que aparece.
///
/// Si la lectura lanza [FileSystemException] (carrera entre el listado y la lectura), espera
/// [esperaReintento] y reintenta una vez:
/// - si el archivo ya no existe, se ignora — ya no es código;
/// - si existe y la lectura sigue fallando, el test falla vía [fail] con la ruta y el error.
Future<List<ArchivoDartLeido>> leerArbolDartResiliente(
  Directory dir, {
  bool Function(File archivo) incluir = esDartNoGenerado,
  LectorDeLineas leer = _leerSync,
  Duration esperaReintento = const Duration(milliseconds: 100),
}) async {
  final leidos = <ArchivoDartLeido>[];
  await for (final entidad in dir.list(recursive: true)) {
    if (entidad is! File || !incluir(entidad)) continue;
    final lineas = await _leerConReintento(entidad, leer, esperaReintento);
    if (lineas != null) leidos.add(ArchivoDartLeido(entidad.path, lineas));
  }
  return leidos;
}

Future<List<String>?> _leerConReintento(
  File archivo,
  LectorDeLineas leer,
  Duration esperaReintento,
) async {
  try {
    return leer(archivo);
  } on FileSystemException {
    await Future<void>.delayed(esperaReintento);
    if (!archivo.existsSync()) return null; // desapareció entre listar y leer: ya no es código
    try {
      return leer(archivo);
    } on FileSystemException catch (e) {
      fail('no pude leer ${archivo.path}: $e');
    }
  }
}
