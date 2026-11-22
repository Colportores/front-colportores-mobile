import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/paquete_tiles.dart';
import '../textos_mapas_offline.dart';
import 'tiles_providers.dart';

/// Los mapas que hay en el teléfono, al día con cada descarga y cada borrado. Sin el repositorio
/// cableado (la app sin tiles) no emite nada.
final mapasDescargadosProvider = StreamProvider.autoDispose<List<PaqueteDescargado>>(
  (ref) => ref.watch(paquetesTilesRepositoryProvider).observarDescargados(),
);

/// El renglón de la fila «Mapas offline» de Configuración (vista 16): «Zona Centro descargada ·
/// 14 MB». Mientras se lee, o si no se pudo leer, no afirma que no haya nada: queda en blanco.
final resumenMapasDescargadosProvider = Provider.autoDispose<String>((ref) {
  final descargados = ref.watch(mapasDescargadosProvider).value;
  if (descargados == null) return '';
  if (descargados.isEmpty) return TextosMapasOffline.sinMapasDescargados;
  final total = descargados.fold<int>(0, (suma, d) => suma + d.paquete.tamanoBytes);
  if (descargados.length > 1) {
    return '${descargados.length} mapas descargados · ${TextosMapasOffline.peso(total)}';
  }
  final paquete = descargados.single.paquete;
  final nombre = paquete.nombre;
  return nombre == null
      ? 'Mapa descargado · ${TextosMapasOffline.peso(total)}'
      : '$nombre descargado · ${TextosMapasOffline.peso(total)}';
});
