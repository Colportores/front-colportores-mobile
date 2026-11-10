import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../domain/entities/ciudad_consultable.dart';

/// Lee del teléfono las ciudades de las campañas de una colportora para consultar precios
/// (HU-CAT-006, vista 26): réplicas de `campania_colportor`, `campania`, `campania_ciudad`, `ciudad`
/// y `zona` que baja el pull de catálogos (#274). Solo lee: la app nunca las escribe.
///
/// Arma valores del dominio ([ContextoDeCiudades]), no filas de Drift.
class CiudadesParaPreciosLocalDataSource {
  CiudadesParaPreciosLocalDataSource(this._db);

  final AppDatabase _db;

  /// Las ciudades de las campañas de [usuarioId] a [hoy] (`AAAA-MM-DD`, el día de Montevideo), o
  /// `null` si el teléfono **todavía no puede saberlo**: ningún pull terminó nunca, o falta en la
  /// réplica una campaña o una ciudad a la que apunta una fila. Un contexto sin ciudades quiere decir
  /// «se leyó y no hay».
  ///
  /// **Qué ciudades.** Las de las campañas con inscripción viva que no terminaron (sin fecha de fin o
  /// con `fecha_fin >= hoy`: en curso o por empezar), la misma regla con la que el servidor le baja el
  /// mapa y las casas (backend-supabase 0013). Las de una campaña en la que no está inscripta, o que
  /// ya terminó, no cuentan: sus precios ya no se usan (26·11).
  ///
  /// Todo se lee en una transacción: un pull que escribe en medio no deja una campaña a medio ver.
  Future<ContextoDeCiudades?> leer(String usuarioId, {required String hoy}) =>
      _db.transaction(() async {
        // Sin ningún pull terminado la réplica está vacía porque no bajó, no porque no haya nada.
        if ((await DriftSyncMeta(_db).read()).lastPullAt == null) return null;

        final inscripciones =
            await (_db.select(_db.campaniasColportor)
                  ..where((i) => i.usuarioId.equals(usuarioId) & i.deletedAt.isNull())
                  ..orderBy([(i) => OrderingTerm.asc(i.id)]))
                .get();
        if (inscripciones.isEmpty) return const ContextoDeCiudades();

        final campanias = {
          for (final c in await (_db.select(
            _db.campanias,
          )..where((c) => c.id.isIn({for (final i in inscripciones) i.campaniaId}))).get())
            c.id: c,
        };
        final vigentes = <CampaniaColportorFila>[];
        CampaniaTerminada? terminada;
        for (final inscripcion in inscripciones) {
          final campania = campanias[inscripcion.campaniaId];
          if (campania == null) return null;
          if (campania.deletedAt != null) continue;
          final fin = campania.fechaFin;
          if (fin == null || fin.compareTo(hoy) >= 0) {
            vigentes.add(inscripcion);
          } else {
            final fecha = DateTime.tryParse(fin);
            if (fecha != null && (terminada == null || fecha.isAfter(terminada.terminoEl))) {
              terminada = CampaniaTerminada(nombre: campania.nombre, terminoEl: fecha);
            }
          }
        }
        if (vigentes.isEmpty) return ContextoDeCiudades(campaniaTerminada: terminada);

        final ciudades = await _ciudadesDe(vigentes, campanias);
        if (ciudades == null) return null;
        final ciudadesDeSusZonas = await _ciudadesDeSusZonas(vigentes);
        return ContextoDeCiudades(
          ciudades: ciudades,
          // Con zonas en más de una ciudad no hay «la» ciudad de su zona: no se elige una por ella.
          ciudadDeMiZonaId: ciudadesDeSusZonas.length == 1 ? ciudadesDeSusZonas.single : null,
          campaniaTerminada: terminada,
        );
      });

  /// Las ciudades vivas de las campañas de [vigentes], una por `campania_ciudad`, por nombre; `null` si
  /// a una `campania_ciudad` le falta su ciudad en la réplica (el pull todavía no la trajo).
  Future<List<CiudadConsultable>?> _ciudadesDe(
    List<CampaniaColportorFila> vigentes,
    Map<String, CampaniaFila> campanias,
  ) async {
    final vinculos =
        await (_db.select(_db.campaniasCiudad)
              ..where(
                (v) =>
                    v.campaniaId.isIn({for (final i in vigentes) i.campaniaId}) &
                    v.deletedAt.isNull(),
              )
              ..orderBy([(v) => OrderingTerm.asc(v.id)]))
            .get();
    final ids = {for (final v in vinculos) v.ciudadId};
    final filas = {
      for (final c in await (_db.select(_db.ciudades)..where((c) => c.id.isIn(ids))).get()) c.id: c,
    };
    if (ids.any((id) => !filas.containsKey(id))) return null;
    final ciudades = <CiudadConsultable>[];
    for (final v in vinculos) {
      final ciudad = filas[v.ciudadId]!;
      if (ciudad.deletedAt != null) continue;
      ciudades.add(
        CiudadConsultable(
          campaniaCiudadId: v.id,
          ciudadId: ciudad.id,
          nombre: ciudad.nombre,
          campaniaNombre: campanias[v.campaniaId]!.nombre,
        ),
      );
    }
    ciudades.sort((a, b) {
      final porNombre = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      if (porNombre != 0) return porNombre;
      final porCampania = a.campaniaNombre.toLowerCase().compareTo(b.campaniaNombre.toLowerCase());
      return porCampania != 0 ? porCampania : a.campaniaCiudadId.compareTo(b.campaniaCiudadId);
    });
    return ciudades;
  }

  /// Las `ciudad.id` de las zonas vivas que tiene asignadas en [vigentes], sin repetir. Una zona dada
  /// de baja, o de una ciudad que ya no es de la campaña, no cuenta.
  Future<Set<String>> _ciudadesDeSusZonas(List<CampaniaColportorFila> vigentes) async {
    final porZona = {
      for (final i in vigentes)
        if (i.zonaId != null) i.zonaId!: i.campaniaId,
    };
    if (porZona.isEmpty) return const {};
    final zona = _db.zonas;
    final vinculo = _db.campaniasCiudad;
    final consulta = _db.select(zona).join([
      innerJoin(vinculo, vinculo.id.equalsExp(zona.campaniaCiudadId)),
    ])..where(zona.id.isIn(porZona.keys) & zona.deletedAt.isNull() & vinculo.deletedAt.isNull());
    return {
      for (final fila in await consulta.get())
        // La zona tiene que ser de la campaña de la inscripción que la asignó.
        if (porZona[fila.readTable(zona).id] == fila.readTable(vinculo).campaniaId)
          fila.readTable(vinculo).ciudadId,
    };
  }
}
