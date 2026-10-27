import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/texto_recordatorio.dart';
import '../../domain/repositories/conciliacion_recordatorios_repository.dart';
import '../../domain/repositories/preferencias_recordatorios_repository.dart';

/// [AgendasParaRecordar] sobre las tablas `agenda`, `espacio` y `ubicacion` de la DB cifrada.
///
/// Solo lee. La dirección es la de la ubicación del espacio de la agenda o, si es una cobranza en
/// otra dirección (`ubicacion_alt_id`) que está en el teléfono, la alternativa. Una ubicación que no
/// llegó (o sin calle ni número) deja la dirección vacía: el aviso sale sin «en …» pero sale.
final class AgendasParaRecordarDrift implements AgendasParaRecordar, AgendasConAvisoVencido {
  AgendasParaRecordarDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<RecordatorioDeVisita>> pendientes({
    required String colportorId,
    required DateTime desde,
  }) async => [
    for (final (:agenda, :direccion) in await _leer(
      colportorId,
      (agendas) =>
          agendas.fechaProgramada.isBiggerThanValue(const FechaUtcConverter().toSql(desde)),
    ))
      _visita(agenda, direccion),
  ];

  @override
  Future<List<RecordatorioDeVisita>> conAvisoEntre({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
    required int anticipacionMinutos,
  }) async {
    final anticipacion = Duration(minutes: anticipacionMinutos);
    const conversor = FechaUtcConverter();
    final filas = await _leer(
      colportorId,
      (agendas) =>
          agendas.fechaProgramada.isBiggerThanValue(conversor.toSql(desde.add(anticipacion))) &
          agendas.fechaProgramada.isSmallerOrEqualValue(conversor.toSql(hasta.add(anticipacion))),
    );
    return [
      for (final (:agenda, :direccion) in filas)
        // Una agenda guardada o cambiada después de la hora de su aviso no llegó a tener recordatorio.
        if (agenda.updatedAt.isBefore(agenda.fechaProgramada.subtract(anticipacion)))
          _visita(agenda, direccion),
    ];
  }

  /// Las agendas `PROGRAMADA` y sin baja de [colportorId] que cumplen [filtro], por fecha, con la
  /// dirección de cada una.
  Future<List<({AgendaFila agenda, String direccion})>> _leer(
    String colportorId,
    Expression<bool> Function($AgendasTable agendas) filtro,
  ) async {
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
                filtro(agendas),
          )
          ..orderBy([OrderingTerm.asc(agendas.fechaProgramada), OrderingTerm.asc(agendas.id)]);
    final filas = await consulta.get();
    return [
      for (final fila in filas)
        (
          agenda: fila.readTable(agendas),
          direccion: _direccion(fila.readTableOrNull(alternativa) ?? fila.readTableOrNull(propia)),
        ),
    ];
  }

  static RecordatorioDeVisita _visita(AgendaFila agenda, String direccion) => RecordatorioDeVisita(
    agendaId: agenda.id,
    tipo: TipoAgenda.desdeCodigo(agenda.tipo),
    direccion: direccion,
    fechaProgramada: agenda.fechaProgramada,
  );

  static String _direccion(UbicacionFila? ubicacion) =>
      ubicacion == null ? '' : TextoRecordatorio.direccionDe(ubicacion.calle, ubicacion.numero);
}
