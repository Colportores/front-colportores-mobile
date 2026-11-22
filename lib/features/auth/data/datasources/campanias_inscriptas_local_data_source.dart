import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/campania_inscripta.dart';
import 'campanias_inscriptas_data_source.dart';

/// [CampaniasInscriptasDataSource] sobre las réplicas locales del pull de catálogos: lee solo del
/// teléfono, sin red.
///
/// - Emite al suscribirse y cada vez que un pull escribe en una de las tablas que lee.
/// - Solo cuentan las inscripciones sin baja y las campañas sin baja.
/// - **`null` si falta en la réplica la campaña de una inscripción** (el pull todavía no la trajo): no
///   se sabe en qué punto está la cuenta, y la app no frena ni afirma nada.
/// - La zona y su ciudad salen de la réplica solo si están vivas; sin ellas, `null` (la inscripción
///   está «sin zona» o la zona todavía no llegó).
///
/// Sin la base abierta (no hay sesión) no hay nada que leer: emite una lista vacía.
final class CampaniasInscriptasLocal implements CampaniasInscriptasDataSource {
  CampaniasInscriptasLocal(this._db);

  final AppDatabase? _db;

  @override
  Stream<List<CampaniaInscripta>?> observar(String usuarioId) {
    final db = _db;
    if (db == null) return Stream.value(const <CampaniaInscripta>[]);
    final inscripcion = db.campaniasColportor;
    final campania = db.campanias;
    final zona = db.zonas;
    final vinculo = db.campaniasCiudad;
    final ciudad = db.ciudades;
    final consulta =
        db.select(inscripcion).join([
            leftOuterJoin(campania, campania.id.equalsExp(inscripcion.campaniaId)),
            leftOuterJoin(zona, zona.id.equalsExp(inscripcion.zonaId) & zona.deletedAt.isNull()),
            leftOuterJoin(
              vinculo,
              vinculo.id.equalsExp(zona.campaniaCiudadId) & vinculo.deletedAt.isNull(),
            ),
            leftOuterJoin(
              ciudad,
              ciudad.id.equalsExp(vinculo.ciudadId) & ciudad.deletedAt.isNull(),
            ),
          ])
          ..where(inscripcion.usuarioId.equals(usuarioId) & inscripcion.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(inscripcion.createdAt), OrderingTerm.asc(inscripcion.id)]);
    return consulta.watch().map((filas) {
      final campanias = <CampaniaInscripta>[];
      for (final fila in filas) {
        final c = fila.readTableOrNull(campania);
        if (c == null) return null;
        if (c.deletedAt != null) continue;
        campanias.add(
          CampaniaInscripta(
            campaniaId: c.id,
            nombre: c.nombre,
            fechaInicio: c.fechaInicio,
            fechaFin: c.fechaFin,
            zona: _conTexto(fila.readTableOrNull(zona)?.nombre),
            ciudad: _conTexto(fila.readTableOrNull(ciudad)?.nombre),
          ),
        );
      }
      return campanias;
    });
  }

  static String? _conTexto(String? texto) {
    final limpio = texto?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }
}
