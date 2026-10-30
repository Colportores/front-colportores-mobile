import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/repositories/cobranzas_en_otra_ubicacion_repository.dart';

/// [CobranzasEnOtraUbicacionRepository] sobre la DB cifrada: une `agenda` con su espacio y descarta
/// las que se cobran en la misma ubicación del espacio (esas no vienen de «otra»). Un `LEFT` por si
/// el espacio todavía no llegó: la cobranza se cuenta igual, el indicador no depende de él.
final class CobranzasEnOtraUbicacionRepositoryDrift implements CobranzasEnOtraUbicacionRepository {
  CobranzasEnOtraUbicacionRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<Set<String>> observarUbicaciones({required String colportorId}) {
    final agendas = _db.agendas;
    final espacios = _db.espacios;
    final consulta =
        _db.select(agendas).join([
          leftOuterJoin(espacios, espacios.id.equalsExp(agendas.espacioId)),
        ])..where(
          agendas.colportorId.equals(colportorId) &
              agendas.tipo.equals(TipoAgenda.cobranza.codigo) &
              agendas.estado.equals(EstadoAgenda.programada.codigo) &
              agendas.deletedAt.isNull() &
              agendas.ubicacionAltId.isNotNull(),
        );
    return consulta.watch().map((filas) {
      final ubicaciones = <String>{};
      for (final fila in filas) {
        final alternativaId = fila.readTable(agendas).ubicacionAltId;
        if (alternativaId == null) continue;
        final propia = fila.readTableOrNull(espacios)?.ubicacionId;
        if (propia != alternativaId) ubicaciones.add(alternativaId);
      }
      return ubicaciones;
    });
  }
}
