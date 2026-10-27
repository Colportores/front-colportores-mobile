import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/services/lector_entrevistas_de_personas.dart';

/// [LectorEntrevistasDePersonas] sobre la tabla `visita` de la DB cifrada: la última visita con
/// `tipo_resultado = ENTREVISTA` (que no esté dada de baja) de cada vínculo `espacio_persona`.
///
/// Solo lee. La fecha es la de la visita (`fecha`), no la de cuando se guardó.
final class EntrevistasDePersonasLocalDataSourceDrift implements LectorEntrevistasDePersonas {
  EntrevistasDePersonasLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Cuántos ids lleva cada consulta: SQLite admite 32.766 variables por sentencia, pero una hoja
  /// nunca llega ni cerca; el tope es solo un resguardo.
  static const _porConsulta = 500;

  @override
  Future<Map<String, DateTime>> ultimaEntrevistaDe(Iterable<String> vinculoIds) async {
    final ids = vinculoIds.toSet().toList();
    final ultimas = <String, DateTime>{};
    for (var desde = 0; desde < ids.length; desde += _porConsulta) {
      final lote = ids.sublist(desde, (desde + _porConsulta).clamp(0, ids.length));
      final filas =
          await (_db.select(_db.visitas)..where(
                (v) =>
                    v.espacioPersonaId.isIn(lote) &
                    v.tipoResultado.equals('ENTREVISTA') &
                    v.deletedAt.isNull(),
              ))
              .get();
      for (final fila in filas) {
        final vinculo = fila.espacioPersonaId;
        if (vinculo == null) continue;
        final actual = ultimas[vinculo];
        if (actual == null || fila.fecha.isAfter(actual)) ultimas[vinculo] = fila.fecha;
      }
    }
    return ultimas;
  }
}
