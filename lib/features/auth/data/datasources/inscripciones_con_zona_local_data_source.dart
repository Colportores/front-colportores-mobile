import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/dia_de_calendario.dart';
import '../../domain/entities/inscripcion_con_zona.dart';
import 'inscripciones_con_zona_data_source.dart';

/// [InscripcionesConZonaDataSource] sobre las réplicas locales del pull de catálogos
/// (`campania_colportor`, `campania` y `zona`): lee solo del teléfono, sin red (HU-CAM-006, #251,
/// adaptador de front-colportores-mobile#274).
///
/// - Emite al suscribirse y cada vez que un pull escribe en una de las tres tablas. Una lectura que
///   falla llega como error del *stream*, no al suscribirse.
/// - **Incluye las inscripciones dadas de baja** (el detector las anota sin avisar), pero solo las de
///   campañas que no terminaron: sin baja y con `fecha_fin` vacía o de hoy en adelante, la misma regla
///   con la que el servidor le baja el mapa (backend-supabase 0013). "Hoy" es el día de calendario de
///   Montevideo (`diaDeCalendario`), y se vuelve a mirar en cada emisión.
/// - La inscripción cuya campaña todavía no llegó se saltea (no hay nombre con qué avisar); cuando
///   llegue, la tabla vuelve a emitir.
/// - [InscripcionConZona.zonaNombre] sale de la réplica de `zona` solo si la zona está viva; con
///   [InscripcionConZona.zonaId] y sin nombre, el detector espera a que la zona llegue.
///
/// Sin la base abierta (no hay sesión) no hay nada que avisar: emite una lista vacía.
final class InscripcionesConZonaLocal implements InscripcionesConZonaDataSource {
  InscripcionesConZonaLocal(this._db, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AppDatabase? _db;
  final DateTime Function() _ahora;

  @override
  Stream<List<InscripcionConZona>> observar(String usuarioId) {
    final db = _db;
    if (db == null) return Stream.value(const <InscripcionConZona>[]);
    final inscripcion = db.campaniasColportor;
    final campania = db.campanias;
    final zona = db.zonas;
    final consulta =
        db.select(inscripcion).join([
            innerJoin(campania, campania.id.equalsExp(inscripcion.campaniaId)),
            leftOuterJoin(zona, zona.id.equalsExp(inscripcion.zonaId)),
          ])
          ..where(inscripcion.usuarioId.equals(usuarioId))
          ..orderBy([OrderingTerm.asc(inscripcion.createdAt), OrderingTerm.asc(inscripcion.id)]);
    return consulta.watch().map((filas) {
      final hoy = diaDeCalendario(_ahora());
      return [
        for (final fila in filas)
          if (_noTermino(fila.readTable(campania), hoy))
            _aInscripcion(
              fila.readTable(inscripcion),
              fila.readTable(campania),
              fila.readTableOrNull(zona),
            ),
      ];
    });
  }

  static bool _noTermino(CampaniaFila campania, String hoy) {
    final fin = campania.fechaFin;
    return campania.deletedAt == null && (fin == null || fin.compareTo(hoy) >= 0);
  }

  static InscripcionConZona _aInscripcion(
    CampaniaColportorFila inscripcion,
    CampaniaFila campania,
    ZonaFila? zona,
  ) => InscripcionConZona(
    id: inscripcion.id,
    campaniaId: inscripcion.campaniaId,
    campaniaNombre: campania.nombre,
    zonaId: inscripcion.zonaId,
    zonaNombre: zona != null && zona.deletedAt == null ? zona.nombre : null,
    dadaDeBaja: inscripcion.deletedAt != null,
  );
}
