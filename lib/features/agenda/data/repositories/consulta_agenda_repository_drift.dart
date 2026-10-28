import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../mapa/data/models/ubicacion_model.dart';
import '../../domain/entities/agenda.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/item_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/repositories/consulta_agenda_repository.dart';

/// [ConsultaAgendaRepository] sobre la DB cifrada: une `agenda` con el vínculo persona ↔ espacio, la
/// persona, el espacio y las ubicaciones (la de la casa y la alternativa) en **una sola consulta
/// reactiva**. Drift la vuelve a emitir cuando cambia cualquiera de esas tablas.
///
/// Todos los joins son `LEFT`: una agenda cuya persona, espacio o ubicación todavía no llegó al
/// teléfono (un pull incompleto, `agenda` no tiene claves foráneas locales) se muestra igual, sin
/// ese dato. Una cita nunca desaparece de la agenda por una fila que falta.
final class ConsultaAgendaRepositoryDrift implements ConsultaAgendaRepository {
  ConsultaAgendaRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<List<ItemAgenda>> observar({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
  }) {
    const conversor = FechaUtcConverter();
    final agendas = _db.agendas;
    final vinculos = _db.espacioPersonas;
    final personas = _db.personas;
    final espacios = _db.espacios;
    final casas = _db.ubicaciones;
    final alternativas = _db.alias(_db.ubicaciones, 'alternativa');

    final consulta =
        _db.select(agendas).join([
            leftOuterJoin(vinculos, vinculos.id.equalsExp(agendas.espacioPersonaId)),
            leftOuterJoin(personas, personas.id.equalsExp(vinculos.personaId)),
            leftOuterJoin(espacios, espacios.id.equalsExp(agendas.espacioId)),
            leftOuterJoin(casas, casas.id.equalsExp(espacios.ubicacionId)),
            leftOuterJoin(alternativas, alternativas.id.equalsExp(agendas.ubicacionAltId)),
          ])
          ..where(
            agendas.colportorId.equals(colportorId) &
                agendas.deletedAt.isNull() &
                agendas.fechaProgramada.isSmallerThanValue(conversor.toSql(hasta)) &
                // La ventana, o una programada de antes: la atrasada no se pierde (P3).
                (agendas.fechaProgramada.isBiggerOrEqualValue(conversor.toSql(desde)) |
                    agendas.estado.equals(EstadoAgenda.programada.codigo)),
          )
          ..orderBy([OrderingTerm.asc(agendas.fechaProgramada), OrderingTerm.asc(agendas.id)]);

    return consulta.watch().map(
      (filas) => [
        for (final fila in filas)
          () {
            final persona = fila.readTableOrNull(personas);
            final espacio = fila.readTableOrNull(espacios);
            final casa = fila.readTableOrNull(casas);
            final alternativa = fila.readTableOrNull(alternativas);
            return ItemAgenda(
              agenda: _aAgenda(fila.readTable(agendas)),
              personaNombre: persona?.nombre,
              personaApellido: persona?.apellido,
              casa: casa == null ? null : _aDireccion(casa),
              numeroDepto: espacio?.numeroDepto,
              alternativa: alternativa == null ? null : _aDireccion(alternativa),
            );
          }(),
      ],
    );
  }

  static DireccionDeAgenda _aDireccion(UbicacionFila fila) => DireccionDeAgenda(
    ubicacionId: fila.id,
    tipo: UbicacionModel.tipoDesdeCodigo(fila.tipo),
    calle: fila.calle,
    numero: fila.numero,
  );

  static Agenda _aAgenda(AgendaFila fila) => Agenda(
    id: fila.id,
    espacioId: fila.espacioId,
    espacioPersonaId: fila.espacioPersonaId,
    tipo: TipoAgenda.desdeCodigo(fila.tipo),
    fechaProgramada: fila.fechaProgramada,
    slotCodigo: fila.slotCodigo,
    esEstricta: fila.esEstricta,
    ubicacionAltId: fila.ubicacionAltId,
    estado: EstadoAgenda.desdeCodigo(fila.estado),
    colportorId: fila.colportorId,
    visitaId: fila.visitaId,
    ventaId: fila.ventaId,
    entregaId: fila.entregaId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
