import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// A qué campaña paga el alquiler que deposita el colportor (decisión «Alq. campaña»: el saldo de
/// alquiler es uno por campaña, y el servidor exige `campania_id` con el concepto alquiler).
///
/// Lee la réplica local de `campania` y `campania_colportor`: la campaña en curso en la que está
/// inscripto el colportor ([hoy] entre su inicio y su fin, o sin fin). Si está en más de una, la que
/// empezó última (la más reciente). Sin ninguna en curso, `null`: el alquiler no se puede registrar.
final class CampaniaDelAlquilerDrift {
  const CampaniaDelAlquilerDrift(this._db);

  final AppDatabase _db;

  /// [hoy] es el día de calendario de Montevideo (sin hora).
  Future<String?> leer(String colportorId, DateTime hoy) async {
    final dia = '${_cuatro(hoy.year)}-${_dos(hoy.month)}-${_dos(hoy.day)}';
    final campanias = _db.campanias;
    final inscripciones = _db.campaniasColportor;
    final consulta =
        _db.select(campanias).join([
            innerJoin(inscripciones, inscripciones.campaniaId.equalsExp(campanias.id)),
          ])
          ..where(
            inscripciones.usuarioId.equals(colportorId) &
                inscripciones.deletedAt.isNull() &
                campanias.deletedAt.isNull() &
                campanias.fechaInicio.isSmallerOrEqualValue(dia) &
                (campanias.fechaFin.isNull() | campanias.fechaFin.isBiggerOrEqualValue(dia)),
          )
          ..orderBy([OrderingTerm.desc(campanias.fechaInicio), OrderingTerm.asc(campanias.id)])
          ..limit(1);
    final fila = await consulta.getSingleOrNull();
    return fila?.readTable(campanias).id;
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _cuatro(int n) => n.toString().padLeft(4, '0');
}
