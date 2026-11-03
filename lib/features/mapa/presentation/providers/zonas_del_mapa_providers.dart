import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/repositories/zonas_del_mapa_repository_impl.dart';
import '../../domain/entities/zona_del_mapa.dart';
import '../../domain/repositories/zonas_del_mapa_repository.dart';
import '../formato_zonas_mapa.dart';
import '../mapa_base/zonas_mapa.dart';
import 'lista_ubicaciones_providers.dart' show relojListaUbicacionesProvider;

// Cableado de las zonas del mapa de ubicaciones (HU-UBI-003, #511): las que el teléfono ya tiene
// replicadas, sin red, dibujadas como guía visual. Nada se pide al servidor ni se escribe.

Duration? _sinReintentos(int intento, Object error) => null;

/// De dónde salen las zonas del mapa: las réplicas locales. Sin la base abierta emite vacío. Un test
/// lo reemplaza.
final zonasDelMapaRepositoryProvider = Provider<ZonasDelMapaRepository>(
  (ref) => ZonasDelMapaRepositoryImpl(
    ref.watch(dbLocalProvider),
    ahora: ref.watch(relojListaUbicacionesProvider),
  ),
);

/// Las zonas de las campañas vigentes del colportor [colportorId], al día con cada pull. Si la
/// lectura falla el flujo queda en error: [zonasParaElMapaProvider] conserva lo último que se leyó.
final zonasDelMapaProvider = StreamProvider.autoDispose.family<List<ZonaDelMapa>, String>(
  (ref, colportorId) => ref.watch(zonasDelMapaRepositoryProvider).observar(colportorId),
  retry: _sinReintentos,
);

/// Lo que la pestaña «Mapa» necesita de las zonas: lo que se dibuja y lo que se le dice al lector de
/// pantalla.
final class ZonasParaElMapa extends Equatable {
  const ZonasParaElMapa({this.dibujo = const [], this.paraElLector});

  /// Sin zonas: no se dibuja nada ni se agrega nada al nodo del mapa.
  static const vacias = ZonasParaElMapa();

  final List<ZonaMapa> dibujo;

  /// Lo que se suma a «Mapa de ubicaciones» para el lector de pantalla; `null` sin zonas.
  final String? paraElLector;

  @override
  List<Object?> get props => [dibujo, paraElLector];
}

/// Las zonas de [colportorId] ya resueltas para dibujar: vacías mientras se leen y si todavía no hay
/// ninguna. Una falla de lectura no tumba el mapa: se anota en el log (sin datos del colportor) y
/// el mapa sigue con las zonas que ya tenía, o sin ellas.
///
/// El resultado cambia solo cuando cambian las zonas: el mapa no se vuelve a armar por el resto.
final zonasParaElMapaProvider = Provider.autoDispose.family<ZonasParaElMapa, String>((
  ref,
  colportorId,
) {
  final proveedor = zonasDelMapaProvider(colportorId);
  ref.listen(proveedor, (_, nuevo) {
    if (nuevo.hasError) {
      AppLogger.instance.error(
        LogModulo.map,
        'zonas',
        'No se pudieron leer las zonas del mapa',
        {},
        nuevo.error,
        nuevo.stackTrace,
      );
    }
  });
  final zonas = ref.watch(proveedor).value;
  if (zonas == null || zonas.isEmpty) return ZonasParaElMapa.vacias;
  return ZonasParaElMapa(
    dibujo: [for (final zona in zonas) ZonaMapa.desde(zona)],
    paraElLector: TextosMapaZonas.paraElLector(zonas),
  );
});
