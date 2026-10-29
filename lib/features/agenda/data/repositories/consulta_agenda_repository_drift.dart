import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../mapa/data/models/ubicacion_model.dart';
import '../../domain/entities/agenda.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/item_agenda.dart';
import '../../domain/entities/rango_de_campania.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/repositories/consulta_agenda_repository.dart';

/// [ConsultaAgendaRepository] sobre la DB cifrada: une `agenda` con el vínculo persona ↔ espacio, la
/// persona, el espacio y las ubicaciones (la de la casa y la alternativa) en **una sola consulta
/// reactiva**. Drift la vuelve a emitir cuando cambia cualquiera de esas tablas.
///
/// Todos los joins son `LEFT`: una agenda cuya persona, espacio o ubicación todavía no llegó al
/// teléfono (un pull incompleto, `agenda` no tiene claves foráneas locales) se muestra igual, sin
/// ese dato. Una cita nunca desaparece de la agenda por una fila que falta.
///
/// **Agenda baja** (decisión de Cristian, 27/10): la agenda de un espacio (depto) o de una ubicación
/// (casa) dados de baja no se lee —queda guardada, no se borra ni se cancela, y vuelve sola si se
/// reactiva—; con la **persona** de baja la cita se lee igual, sin nombre. Vale para las dos lecturas
/// de acá, y por ende para la pestaña y para los conteos de los días.
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
    return _leer(
      colportorId,
      (agendas) =>
          agendas.fechaProgramada.isSmallerThanValue(conversor.toSql(hasta)) &
          // La ventana, o una programada de antes: la atrasada no se pierde (P3).
          (agendas.fechaProgramada.isBiggerOrEqualValue(conversor.toSql(desde)) |
              agendas.estado.equals(EstadoAgenda.programada.codigo)),
      ascendente: true,
    );
  }

  @override
  Stream<List<ItemAgenda>> observarCampania({required String colportorId, required DateTime hoy}) {
    late final StreamController<List<ItemAgenda>> salida;
    StreamSubscription<RangoDeCampania>? rangos;
    StreamSubscription<List<ItemAgenda>>? agendas;

    // Cada vez que cambia el rango de la campaña se deja de mirar el anterior y se pasa al nuevo.
    void mirar(RangoDeCampania rango) {
      unawaited(agendas?.cancel());
      agendas = _leerRango(colportorId, rango).listen(salida.add, onError: salida.addError);
    }

    salida = StreamController<List<ItemAgenda>>(
      onListen: () {
        rangos = _observarRango(
          colportorId,
          hoy,
        ).distinct().listen(mirar, onError: salida.addError);
      },
      onCancel: () async {
        await rangos?.cancel();
        await agendas?.cancel();
      },
    );
    return salida.stream;
  }

  /// El rango de la campaña en curso de [colportorId] a [hoy]: de la fecha de inicio más temprana al
  /// fin más tardío de las campañas en que está inscripto y que ya empezaron y no terminaron. Las
  /// fechas de la campaña son días de calendario: arrancan a medianoche local. Sin ninguna campaña en
  /// curso en el teléfono, o con una sin fecha de fin (permanente), el lado que no se conoce queda
  /// abierto.
  Stream<RangoDeCampania> _observarRango(String colportorId, DateTime hoy) {
    final dia = '${_cuatro(hoy.year)}-${_dos(hoy.month)}-${_dos(hoy.day)}';
    final inscripciones = _db.campaniasColportor;
    final campanias = _db.campanias;
    final consulta =
        _db.select(campanias).join([
          innerJoin(inscripciones, inscripciones.campaniaId.equalsExp(campanias.id)),
        ])..where(
          inscripciones.usuarioId.equals(colportorId) &
              inscripciones.deletedAt.isNull() &
              campanias.deletedAt.isNull() &
              campanias.fechaInicio.isSmallerOrEqualValue(dia) &
              (campanias.fechaFin.isNull() | campanias.fechaFin.isBiggerOrEqualValue(dia)),
        );
    return consulta.watch().map((filas) {
      if (filas.isEmpty) return RangoDeCampania.sinLimite;
      DateTime? primero;
      DateTime? ultimo;
      var abierta = false;
      for (final fila in filas) {
        final campania = fila.readTable(campanias);
        final inicio = _diaLocal(campania.fechaInicio);
        if (primero == null || inicio.isBefore(primero)) primero = inicio;
        final fin = campania.fechaFin;
        if (fin == null) {
          abierta = true;
        } else {
          final siguiente = _diaLocal(fin, sumarDias: 1);
          if (ultimo == null || siguiente.isAfter(ultimo)) ultimo = siguiente;
        }
      }
      return RangoDeCampania(desde: primero?.toUtc(), hasta: abierta ? null : ultimo?.toUtc());
    });
  }

  /// Todas las agendas de [colportorId] dentro de [rango], de la más nueva a la más vieja.
  Stream<List<ItemAgenda>> _leerRango(String colportorId, RangoDeCampania rango) {
    const conversor = FechaUtcConverter();
    final desde = rango.desde;
    final hasta = rango.hasta;
    return _leer(
      colportorId,
      (agendas) =>
          (desde == null
              ? const Constant<bool>(true)
              : agendas.fechaProgramada.isBiggerOrEqualValue(conversor.toSql(desde))) &
          (hasta == null
              ? const Constant<bool>(true)
              : agendas.fechaProgramada.isSmallerThanValue(conversor.toSql(hasta))),
      ascendente: false,
    );
  }

  /// `AAAA-MM-DD` de la campaña como medianoche local (más [sumarDias]).
  static DateTime _diaLocal(String fecha, {int sumarDias = 0}) {
    final partes = fecha.split('-').map(int.parse).toList();
    return DateTime(partes[0], partes[1], partes[2] + sumarDias);
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _cuatro(int n) => n.toString().padLeft(4, '0');

  Stream<List<ItemAgenda>> _leer(
    String colportorId,
    Expression<bool> Function($AgendasTable agendas) filtro, {
    required bool ascendente,
  }) {
    final agendas = _db.agendas;
    final vinculos = _db.espacioPersonas;
    final personas = _db.personas;
    final espacios = _db.espacios;
    final casas = _db.ubicaciones;
    final alternativas = _db.alias(_db.ubicaciones, 'alternativa');

    final consulta =
        _db.select(agendas).join([
            leftOuterJoin(vinculos, vinculos.id.equalsExp(agendas.espacioPersonaId)),
            // Una persona de baja no sale: la cita sigue, «sin persona».
            leftOuterJoin(
              personas,
              personas.id.equalsExp(vinculos.personaId) & personas.deletedAt.isNull(),
            ),
            leftOuterJoin(espacios, espacios.id.equalsExp(agendas.espacioId)),
            leftOuterJoin(casas, casas.id.equalsExp(espacios.ubicacionId)),
            leftOuterJoin(alternativas, alternativas.id.equalsExp(agendas.ubicacionAltId)),
          ])
          ..where(
            agendas.colportorId.equals(colportorId) &
                agendas.deletedAt.isNull() &
                // Agenda baja: con el depto o la casa de baja la agenda se oculta (si la fila no
                // llegó, el `LEFT JOIN` deja `NULL` y la cita se muestra).
                espacios.deletedAt.isNull() &
                casas.deletedAt.isNull() &
                filtro(agendas),
          )
          ..orderBy([
            ascendente
                ? OrderingTerm.asc(agendas.fechaProgramada)
                : OrderingTerm.desc(agendas.fechaProgramada),
            ascendente ? OrderingTerm.asc(agendas.id) : OrderingTerm.desc(agendas.id),
          ]);

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
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
