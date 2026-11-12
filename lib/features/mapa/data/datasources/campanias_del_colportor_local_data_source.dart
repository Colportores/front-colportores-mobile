import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/drift_sync_meta.dart';

/// Una ciudad de la campaña del colportor, con lo que hace falta para proponérsela.
typedef CiudadDeCampania = ({String id, String nombre, double lat, double lon});

/// Una inscripción viva del colportor en una campaña que no terminó.
///
/// [ciudadDeLaZonaId] es la ciudad de la zona asignada ([zonaId]); `null` si no tiene zona o si la
/// zona no se puede resolver (dada de baja, o su ciudad ya no es de la campaña).
typedef InscripcionDeCampania = ({String campaniaId, String? zonaId, String? ciudadDeLaZonaId});

/// Lo que el teléfono sabe de las campañas de un colportor (réplicas de `campania_colportor`,
/// `campania`, `campania_ciudad`, `ciudad` y `zona`).
final class CampaniasDelColportor extends Equatable {
  const CampaniasDelColportor({required this.inscripciones, required this.ciudades});

  /// Las inscripciones vivas en campañas que no terminaron (en curso o por empezar), por campaña.
  final List<InscripcionDeCampania> inscripciones;

  /// Las ciudades vivas de esas campañas, sin repetir y por nombre.
  final List<CiudadDeCampania> ciudades;

  @override
  List<Object?> get props => [inscripciones, ciudades];
}

/// Lectura local de las campañas de un colportor, para saber en qué ciudades trabaja.
abstract interface class CampaniasDelColportorLocalDataSource {
  /// Las campañas de [usuarioId] que no terminaron a [hoy] (`AAAA-MM-DD`), o `null` si el teléfono
  /// **todavía no puede saberlo**: ningún pull terminó nunca, o falta en la réplica una campaña o una
  /// ciudad a la que apunta una fila. Una lista vacía quiere decir «se leyó y no hay».
  ///
  /// «No terminó» es la regla del servidor para el mapa y las casas (backend-supabase 0013,
  /// `mis_inscripciones_no_terminadas()`): inscripción y campaña sin baja, y sin fecha de fin o con
  /// `fecha_fin >= hoy`.
  Future<CampaniasDelColportor?> leer(String usuarioId, {required String hoy});
}

/// [CampaniasDelColportorLocalDataSource] sobre la DB local (Drift). Lee todo en una transacción:
/// un pull que escribe en medio no deja una campaña a medio ver.
final class CampaniasDelColportorLocalDataSourceDrift
    implements CampaniasDelColportorLocalDataSource {
  CampaniasDelColportorLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  @override
  Future<CampaniasDelColportor?> leer(String usuarioId, {required String hoy}) =>
      _db.transaction(() async {
        // Sin ningún pull terminado la réplica está vacía porque no bajó, no porque no haya nada.
        if ((await DriftSyncMeta(_db).read()).lastPullAt == null) return null;

        final propias =
            await (_db.select(_db.campaniasColportor)
                  ..where((i) => i.usuarioId.equals(usuarioId) & i.deletedAt.isNull())
                  ..orderBy([(i) => OrderingTerm.asc(i.id)]))
                .get();
        if (propias.isEmpty) return const CampaniasDelColportor(inscripciones: [], ciudades: []);

        final campanias = {
          for (final c in await (_db.select(
            _db.campanias,
          )..where((c) => c.id.isIn({for (final i in propias) i.campaniaId}))).get())
            c.id: c,
        };
        final vigentes = <CampaniaColportorFila>[];
        for (final inscripcion in propias) {
          final campania = campanias[inscripcion.campaniaId];
          if (campania == null) return null;
          final fin = campania.fechaFin;
          if (campania.deletedAt == null && (fin == null || fin.compareTo(hoy) >= 0)) {
            vigentes.add(inscripcion);
          }
        }
        if (vigentes.isEmpty) return const CampaniasDelColportor(inscripciones: [], ciudades: []);

        final ciudades = await _ciudadesDe({for (final i in vigentes) i.campaniaId});
        if (ciudades == null) return null;
        final ciudadesPorZona = await _ciudadPorZona({
          for (final i in vigentes) ?i.zonaId,
        }, ciudades.map((c) => c.id).toSet());
        return CampaniasDelColportor(
          inscripciones: [
            for (final i in vigentes)
              (
                campaniaId: i.campaniaId,
                zonaId: i.zonaId,
                ciudadDeLaZonaId: i.zonaId == null ? null : ciudadesPorZona[i.zonaId],
              ),
          ],
          ciudades: ciudades,
        );
      });

  /// Las ciudades vivas de las [campaniaIds]; `null` si a una `campania_ciudad` le falta su ciudad
  /// en la réplica (el pull todavía no la trajo).
  Future<List<CiudadDeCampania>?> _ciudadesDe(Set<String> campaniaIds) async {
    final vinculos = await (_db.select(
      _db.campaniasCiudad,
    )..where((v) => v.campaniaId.isIn(campaniaIds) & v.deletedAt.isNull())).get();
    final ids = {for (final v in vinculos) v.ciudadId};
    final filas = {
      for (final c in await (_db.select(_db.ciudades)..where((c) => c.id.isIn(ids))).get()) c.id: c,
    };
    if (ids.any((id) => !filas.containsKey(id))) return null;
    final vivas = [
      for (final c in filas.values)
        if (c.deletedAt == null) (id: c.id, nombre: c.nombre, lat: c.latCentro, lon: c.lonCentro),
    ]..sort(_porNombre);
    return vivas;
  }

  /// La ciudad de cada zona de [zonaIds] que sigue viva y es de una de las [ciudadesDeLaCampania].
  Future<Map<String, String>> _ciudadPorZona(
    Set<String> zonaIds,
    Set<String> ciudadesDeLaCampania,
  ) async {
    if (zonaIds.isEmpty) return const {};
    final zona = _db.zonas;
    final vinculo = _db.campaniasCiudad;
    final consulta = _db.select(zona).join([
      innerJoin(vinculo, vinculo.id.equalsExp(zona.campaniaCiudadId)),
    ])..where(zona.id.isIn(zonaIds) & zona.deletedAt.isNull() & vinculo.deletedAt.isNull());
    return {
      for (final fila in await consulta.get())
        if (ciudadesDeLaCampania.contains(fila.readTable(vinculo).ciudadId))
          fila.readTable(zona).id: fila.readTable(vinculo).ciudadId,
    };
  }

  static int _porNombre(CiudadDeCampania a, CiudadDeCampania b) {
    final porNombre = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    return porNombre != 0 ? porNombre : a.id.compareTo(b.id);
  }
}
