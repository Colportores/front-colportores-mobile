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
      estados: const [EstadoAgenda.programada, EstadoAgenda.cumplida, EstadoAgenda.noCumplida],
    );
    // Cuándo se guardó el resultado de las que ya se resolvieron (la visita que las cumple).
    final visitaIds = {
      for (final f in filas)
        if (f.agenda.estado != EstadoAgenda.programada.codigo && f.agenda.visitaId != null)
          f.agenda.visitaId!,
    };
    final resultados = visitaIds.isEmpty
        ? const <String, DateTime>{}
        : {
            for (final v in await (_db.select(
              _db.visitas,
            )..where((v) => v.id.isIn(visitaIds))).get())
              v.id: v.fecha,
          };
    return [
      for (final (:agenda, :direccion) in filas)
        if (_sonoSegunLaAgenda(agenda, anticipacion, resultados)) _visita(agenda, direccion),
    ];
  }

  /// Si el recordatorio de [agenda] valía a la hora de su aviso (HU-NOT-005, #416):
  /// - `PROGRAMADA`: la agenda ya existía a la hora del aviso (`created_at`); si se guardó después,
  ///   esa visita nunca tuvo recordatorio: «Falta menos de N min para la visita: no hay
  ///   recordatorio». Editarla después del aviso (una nota, un cambio que llega por sync) no la
  ///   descarta (decisión del 27/10, QA P2).
  /// - `CUMPLIDA` / `NO_CUMPLIDA`: ya existía a la hora del aviso y su resultado se guardó después
  ///   (el instante de la visita que la cumple o, sin ella, el último cambio de la agenda). Una
  ///   `CANCELADA` nunca cuenta.
  static bool _sonoSegunLaAgenda(
    AgendaFila agenda,
    Duration anticipacion,
    Map<String, DateTime> resultados,
  ) {
    final avisoEn = agenda.fechaProgramada.subtract(anticipacion);
    if (agenda.estado == EstadoAgenda.programada.codigo) return agenda.createdAt.isBefore(avisoEn);
    final resultadoEn = resultados[agenda.visitaId] ?? agenda.updatedAt;
    return agenda.createdAt.isBefore(avisoEn) && resultadoEn.isAfter(avisoEn);
  }

  /// Las agendas de [colportorId] en alguno de [estados] (`PROGRAMADA` por defecto), sin baja, que
  /// cumplen [filtro], por fecha, con la dirección de cada una.
  Future<List<({AgendaFila agenda, String direccion})>> _leer(
    String colportorId,
    Expression<bool> Function($AgendasTable agendas) filtro, {
    List<EstadoAgenda> estados = const [EstadoAgenda.programada],
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
                agendas.estado.isIn([for (final e in estados) e.codigo]) &
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
