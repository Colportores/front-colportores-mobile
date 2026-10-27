import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/texto_recordatorio.dart';
import '../../domain/repositories/preferencias_recordatorios_repository.dart';

/// [AgendasParaRecordar] sobre las tablas `agenda`, `espacio` y `ubicacion` de la DB cifrada.
///
/// Solo lee. La dirección es la de la ubicación del espacio de la agenda o, si es una cobranza en
/// otra dirección (`ubicacion_alt_id`) que está en el teléfono, la alternativa. Una ubicación que no
/// llegó (o sin calle ni número) deja la dirección vacía: el aviso sale sin «en …» pero sale.
final class AgendasParaRecordarDrift implements AgendasParaRecordar {
  AgendasParaRecordarDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<RecordatorioDeVisita>> pendientes({
    required String colportorId,
    required DateTime desde,
  }) async {
    final agendas = _db.agendas;
    final espacios = _db.espacios;
    final propia = _db.ubicaciones;
    final alternativa = _db.alias(_db.ubicaciones, 'alternativa');
    final consulta =
        _db.select(agendas).join([
            leftOuterJoin(espacios, espacios.id.equalsExp(agendas.espacioId)),
            leftOuterJoin(propia, propia.id.equalsExp(espacios.ubicacionId)),
            leftOuterJoin(alternativa, alternativa.id.equalsExp(agendas.ubicacionAltId)),
          ])
          ..where(
            agendas.colportorId.equals(colportorId) &
                agendas.estado.equals(EstadoAgenda.programada.codigo) &
                agendas.deletedAt.isNull() &
                agendas.fechaProgramada.isBiggerThanValue(const FechaUtcConverter().toSql(desde)),
          )
          ..orderBy([OrderingTerm.asc(agendas.fechaProgramada), OrderingTerm.asc(agendas.id)]);
    final filas = await consulta.get();
    return [
      for (final fila in filas)
        RecordatorioDeVisita(
          agendaId: fila.readTable(agendas).id,
          tipo: TipoAgenda.desdeCodigo(fila.readTable(agendas).tipo),
          direccion: _direccion(fila.readTableOrNull(alternativa) ?? fila.readTableOrNull(propia)),
          fechaProgramada: fila.readTable(agendas).fechaProgramada,
        ),
    ];
  }

  static String _direccion(UbicacionFila? ubicacion) =>
      ubicacion == null ? '' : TextoRecordatorio.direccionDe(ubicacion.calle, ubicacion.numero);
}
