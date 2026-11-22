import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/zona_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/zonas_del_mapa_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/geometria_zona.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/zonas_del_mapa_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Una zona cuadrada de [lado] grados con la esquina sudoeste en ([lat], [lon]).
ZonaDelMapa zonaCuadrada(
  String id, {
  String? nombre,
  bool propia = false,
  double lat = -34.90,
  double lon = -56.20,
  double lado = .05,
  String? color = '#1F6E3A',
}) => ZonaDelMapa(
  id: id,
  nombre: nombre ?? id,
  propia: propia,
  color: color,
  geometria: GeometriaZona.desdeGeojson({
    'type': 'Polygon',
    'coordinates': [
      [
        [lon, lat],
        [lon + lado, lat],
        [lon + lado, lat + lado],
        [lon, lat + lado],
        [lon, lat],
      ],
    ],
  })!,
);

/// El repositorio de zonas del mapa para los tests de widgets: emite la lista que se le diga, como lo
/// hace la base local (la actual al suscribirse y una nueva cada vez que un pull cambia algo).
final class ZonasDelMapaFalsas implements ZonasDelMapaRepository {
  ZonasDelMapaFalsas([List<ZonaDelMapa> zonas = const []]) : _zonas = zonas;

  List<ZonaDelMapa> _zonas;
  final _activos = <MultiStreamController<List<ZonaDelMapa>>>[];

  /// Si no es `null`, la primera emisión de cada suscripción es este error en vez de la lista.
  Object? fallaAlSuscribir;

  /// Cuántas suscripciones se abrieron en total y para qué colportor.
  final pedidos = <String>[];

  int get suscripciones => pedidos.length;

  /// Reemplaza las zonas y se las emite a quien esté suscripto (un pull que las cambia).
  void emitir(List<ZonaDelMapa> zonas) {
    _zonas = zonas;
    for (final c in [..._activos]) {
      c.add(zonas);
    }
  }

  /// Una lectura que falla a mitad de camino: el flujo avisa el error y sigue vivo.
  void fallar([Object error = 'la lectura falló']) {
    for (final c in [..._activos]) {
      c.addError(error);
    }
  }

  @override
  Stream<List<ZonaDelMapa>> observar(String colportorId) {
    pedidos.add(colportorId);
    return Stream.multi((c) {
      _activos.add(c);
      c.onCancel = () => _activos.remove(c);
      final falla = fallaAlSuscribir;
      if (falla != null) {
        c.addError(falla);
      } else {
        c.add(_zonas);
      }
    });
  }

  Override get sobrescribe => zonasDelMapaRepositoryProvider.overrideWithValue(this);
}
