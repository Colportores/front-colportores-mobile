import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/sync_queue_table.dart';
import '../../domain/entities/jornada_rechazada.dart';

/// De dónde salen las jornadas que el servidor no aceptó por empezar antes del inicio de la campaña.
abstract interface class JornadasRechazadasDataSource {
  /// Las jornadas de [colportorId] cuyo alta volvió `invalid` con `42501` (la política
  /// `jornada_no_antes_del_inicio`), con la cantidad de visitas suyas que volvieron `invalid` con
  /// `23503`. De la más nueva a la más vieja. Reactivo: emite de nuevo cuando cambia la cola de sync.
  ///
  /// No lanza al suscribirse: una lectura que falla se reporta como error del *stream*.
  Stream<List<JornadaRechazada>> observar(String colportorId);
}

/// [JornadasRechazadasDataSource] sobre la cola de sync de la DB local (`sync_queue`): lee solo del
/// teléfono, y no cambia nada de lo que guarda.
///
/// Sin la base abierta (no hay sesión) no hay nada que avisar: emite una lista vacía.
final class JornadasRechazadasLocal implements JornadasRechazadasDataSource {
  JornadasRechazadasLocal(this._db);

  final AppDatabase? _db;

  /// El rechazo de la RLS (contrato-sync-engine §6): la jornada nueva antes del inicio de la campaña.
  static const codigoJornada = '42501';

  /// La FK a una jornada que el servidor no tiene.
  static const codigoVisita = '23503';

  @override
  Stream<List<JornadaRechazada>> observar(String colportorId) {
    final db = _db;
    if (db == null) return Stream.value(const <JornadaRechazada>[]);
    final jornada = db.jornadas;
    final altaJornada = db.syncQueue;
    final visita = db.visitas;
    final altaVisita = db.alias(db.syncQueue, 'alta_visita');
    final consulta =
        db.select(jornada).join([
            innerJoin(
              altaJornada,
              altaJornada.rowPk.equalsExp(jornada.id) &
                  altaJornada.entity.equals('jornada') &
                  altaJornada.op.equals('insert') &
                  altaJornada.state.equals(EstadoJob.invalid) &
                  altaJornada.code.equals(codigoJornada),
            ),
            leftOuterJoin(visita, visita.jornadaId.equalsExp(jornada.id)),
            leftOuterJoin(
              altaVisita,
              altaVisita.rowPk.equalsExp(visita.id) &
                  altaVisita.entity.equals('visita') &
                  altaVisita.state.equals(EstadoJob.invalid) &
                  altaVisita.code.equals(codigoVisita),
            ),
          ])
          ..where(jornada.colportorId.equals(colportorId) & jornada.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(jornada.inicio), OrderingTerm.asc(jornada.id)]);
    return consulta.watch().map((filas) {
      final visitasPorJornada = <String, Set<String>>{};
      final inicios = <String, DateTime>{};
      for (final fila in filas) {
        final j = fila.readTable(jornada);
        inicios[j.id] = j.inicio;
        final conVisitas = visitasPorJornada.putIfAbsent(j.id, () => <String>{});
        if (fila.readTableOrNull(altaVisita) != null) {
          conVisitas.add(fila.readTable(visita).id);
        }
      }
      return [
        for (final MapEntry(key: id, value: inicio) in inicios.entries)
          JornadaRechazada(id: id, inicio: inicio, visitas: visitasPorJornada[id]!.length),
      ];
    });
  }
}
