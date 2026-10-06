import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/services/preparador_recursos_mapa.dart';

/// Dónde está el estilo de backend dentro de los assets de la app.
const rutaEstiloBaseMapa = 'assets/mapa/estilo/colportores.json';

/// Lo que necesita la vista nativa de MapLibre para armar el estilo: el JSON de backend y el
/// directorio con los glyphs y sprites ya copiados al almacenamiento interno.
final class RecursosMapa extends Equatable {
  const RecursosMapa({required this.directorio, required this.estiloBase});

  /// Donde están los glyphs y sprites copiados; `null` si no se pudieron copiar (el estilo se arma
  /// sin ellos: ver `ConstructorEstiloMapa.construirSinRecursos`).
  final String? directorio;
  final String estiloBase;

  @override
  List<Object?> get props => [directorio, estiloBase];
}

/// Copia los glyphs y sprites empaquetados al almacenamiento interno. Un test lo reemplaza.
final preparadorRecursosMapaProvider = Provider<PreparadorRecursosMapa>(
  (ref) => PreparadorRecursosMapa(directorioBase: getApplicationSupportDirectory),
);

/// Los recursos del mapa listos para usar. La copia de glyphs y sprites se hace una sola vez por
/// ejecución; si falla (disco lleno, por ejemplo) no se pierde el mapa: el estilo se arma sin ellos
/// (sin nombres de calles, pero con los puntos y el radio del GPS, que no los usan) y la copia se
/// vuelve a intentar la próxima vez que se abre un mapa (el proveedor se libera al cerrarlo; solo se
/// conserva mientras la copia salió bien).
final recursosMapaProvider = FutureProvider.autoDispose<RecursosMapa>((ref) async {
  final copia = _copiarRecursos(ref.watch(preparadorRecursosMapaProvider));
  final estiloBase = await rootBundle.loadString(rutaEstiloBaseMapa);
  final directorio = await copia;
  if (directorio != null && ref.mounted) ref.keepAlive();
  return RecursosMapa(directorio: directorio, estiloBase: estiloBase);
});

/// El directorio de los glyphs y sprites, o `null` si no se pudieron copiar (no lanza).
Future<String?> _copiarRecursos(PreparadorRecursosMapa preparador) async {
  try {
    return await preparador.preparar();
  } on Object catch (e, s) {
    AppLogger.instance.error(
      LogModulo.map,
      'recursos',
      'No se pudieron copiar los glyphs y sprites: el mapa va sin nombres',
      {},
      e,
      s,
    );
    return null;
  }
}
