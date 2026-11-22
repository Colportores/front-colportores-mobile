import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/dia_de_calendario.dart';
import '../../domain/entities/zona_del_mapa.dart';
import '../../domain/repositories/zonas_del_mapa_repository.dart';
import '../../domain/value_objects/geometria_zona.dart';

/// [ZonasDelMapaRepository] sobre las réplicas locales del pull de catálogos (`zona`,
/// `campania_ciudad`, `campania` y `campania_colportor`): lee solo del teléfono, sin red.
///
/// «Vigente» es la regla con la que el servidor le baja el mapa al colportor (backend-supabase
/// 0013): inscripción y campaña sin baja, y sin fecha de fin o con `fecha_fin >= hoy`, donde «hoy» es
/// el día de calendario de Montevideo (`diaDeCalendario`) y se vuelve a mirar en cada emisión.
///
/// Sin la base abierta (no hay sesión) no hay nada que dibujar: emite una lista vacía.
final class ZonasDelMapaRepositoryImpl implements ZonasDelMapaRepository {
  ZonasDelMapaRepositoryImpl(this._db, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AppDatabase? _db;
  final DateTime Function() _ahora;

  @override
  Stream<List<ZonaDelMapa>> observar(String colportorId) {
    final db = _db;
    if (db == null) return Stream.value(const <ZonaDelMapa>[]);
    final zona = db.zonas;
    final vinculo = db.campaniasCiudad;
    final campania = db.campanias;
    final inscripcion = db.campaniasColportor;
    final consulta =
        db.select(zona).join([
            innerJoin(vinculo, vinculo.id.equalsExp(zona.campaniaCiudadId)),
            innerJoin(campania, campania.id.equalsExp(vinculo.campaniaId)),
            innerJoin(
              inscripcion,
              inscripcion.campaniaId.equalsExp(campania.id) &
                  inscripcion.usuarioId.equals(colportorId) &
                  inscripcion.deletedAt.isNull(),
            ),
          ])
          ..where(
            zona.deletedAt.isNull() & vinculo.deletedAt.isNull() & campania.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.asc(zona.id)]);
    return consulta.watch().map((filas) {
      final hoy = diaDeCalendario(_ahora());
      // Una zona puede salir de dos inscripciones (dos campañas con la misma ciudad no comparten
      // zona, pero la consulta no lo supone): se junta por id y la propia gana.
      final porId = <String, ZonaDelMapa>{};
      for (final fila in filas) {
        if (!_noTermino(fila.readTable(campania), hoy)) continue;
        final filaZona = fila.readTable(zona);
        final geometria = GeometriaZona.desdeGeojson(filaZona.poligonoGeojson);
        if (geometria == null) continue;
        final propia = fila.readTable(inscripcion).zonaId == filaZona.id;
        final anterior = porId[filaZona.id];
        if (anterior != null && anterior.propia) continue;
        porId[filaZona.id] = ZonaDelMapa(
          id: filaZona.id,
          nombre: filaZona.nombre,
          geometria: geometria,
          color: filaZona.color,
          propia: propia,
        );
      }
      return porId.values.toList(growable: false);
    });
  }

  static bool _noTermino(CampaniaFila campania, String hoy) {
    final fin = campania.fechaFin;
    return fin == null || fin.compareTo(hoy) >= 0;
  }
}
