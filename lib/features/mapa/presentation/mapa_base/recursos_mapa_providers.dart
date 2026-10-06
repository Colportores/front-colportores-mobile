import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/preparador_recursos_mapa.dart';

/// Dónde está el estilo de backend dentro de los assets de la app.
const rutaEstiloBaseMapa = 'assets/mapa/estilo/colportores.json';

/// Lo que necesita la vista nativa de MapLibre para armar el estilo: el JSON de backend y el
/// directorio con los glyphs y sprites ya copiados al almacenamiento interno.
final class RecursosMapa extends Equatable {
  const RecursosMapa({required this.directorio, required this.estiloBase});

  final String directorio;
  final String estiloBase;

  @override
  List<Object?> get props => [directorio, estiloBase];
}

/// Copia los glyphs y sprites empaquetados al almacenamiento interno. Un test lo reemplaza.
final preparadorRecursosMapaProvider = Provider<PreparadorRecursosMapa>(
  (ref) => PreparadorRecursosMapa(directorioBase: getApplicationSupportDirectory),
);

/// Los recursos del mapa listos para usar (se prepara una sola vez por ejecución). Falla si no se
/// pudieron copiar (disco lleno, por ejemplo): la vista deja el fondo liso y no revienta.
final recursosMapaProvider = FutureProvider<RecursosMapa>((ref) async {
  final directorio = await ref.watch(preparadorRecursosMapaProvider).preparar();
  final estiloBase = await rootBundle.loadString(rutaEstiloBaseMapa);
  return RecursosMapa(directorio: directorio, estiloBase: estiloBase);
});
