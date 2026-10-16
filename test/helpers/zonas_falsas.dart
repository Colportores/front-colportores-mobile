import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_colportor.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/zona_ubicable.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/zona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/inscripciones_colportor.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ubicador_zona.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/geometria_zona.dart';
import 'package:dartz/dartz.dart';

/// Las zonas del teléfono, en memoria. Con [falla], toda lectura la devuelve.
final class ZonasEnMemoria implements ZonaRepository {
  ZonasEnMemoria([List<ZonaUbicable>? zonas]) : zonas = zonas ?? [];

  final List<ZonaUbicable> zonas;
  Failure? falla;

  @override
  Future<Either<Failure, List<ZonaUbicable>>> vivasDeCiudad(String ciudadId) async =>
      falla != null ? Left(falla!) : Right([...zonas.where((z) => z.ciudadId == ciudadId)]);
}

/// Las inscripciones vigentes de cada colportor, en memoria. Con [falla], toda lectura la devuelve.
final class InscripcionesEnMemoria implements InscripcionesColportor {
  InscripcionesEnMemoria([List<CampaniaColportor>? inscripciones])
    : inscripciones = inscripciones ?? [];

  final List<CampaniaColportor> inscripciones;
  Failure? falla;

  @override
  Future<Either<Failure, List<CampaniaColportor>>> vigentesDe(String usuarioId) async =>
      falla != null
      ? Left(falla!)
      : Right([...inscripciones.where((i) => i.usuarioId == usuarioId)]);
}

/// Un [UbicadorZona] sin zonas ni inscripciones: todo punto queda fuera de zona.
UbicadorZona ubicadorSinZonas() => UbicadorZona(ZonasEnMemoria(), InscripcionesEnMemoria());

/// Una inscripción vigente de [usuarioId] en [campaniaId], con [zonaId] asignada (o sin zona).
CampaniaColportor inscripcion(String usuarioId, String campaniaId, {String? zonaId}) =>
    CampaniaColportor(
      id: 'insc-$usuarioId-$campaniaId',
      campaniaId: campaniaId,
      usuarioId: usuarioId,
      zonaId: zonaId,
      metaLibros: 100,
      auditoria: Auditoria(createdAt: DateTime.utc(2026, 9), updatedAt: DateTime.utc(2026, 9)),
    );

/// Un `Polygon` GeoJSON rectangular entre los dos puntos, en `[lon, lat]` y cerrado.
Map<String, Object?> rectanguloGeojson({
  required double latSur,
  required double latNorte,
  required double lonOeste,
  required double lonEste,
}) => {
  'type': 'Polygon',
  'coordinates': [
    [
      [lonOeste, latSur],
      [lonEste, latSur],
      [lonEste, latNorte],
      [lonOeste, latNorte],
      [lonOeste, latSur],
    ],
  ],
};

/// Una [ZonaUbicable] rectangular (ver [rectanguloGeojson]).
ZonaUbicable zonaRectangular(
  String zonaId, {
  String campaniaId = 'camp-1',
  String ciudadId = 'mvd',
  required double latSur,
  required double latNorte,
  required double lonOeste,
  required double lonEste,
}) => ZonaUbicable(
  zonaId: zonaId,
  campaniaId: campaniaId,
  ciudadId: ciudadId,
  geometria: GeometriaZona.desdeGeojson(
    rectanguloGeojson(latSur: latSur, latNorte: latNorte, lonOeste: lonOeste, lonEste: lonEste),
  )!,
);
