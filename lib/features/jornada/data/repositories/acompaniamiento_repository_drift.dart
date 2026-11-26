import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/dia_de_calendario.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/acompaniante.dart';
import '../../domain/entities/tendencia_de_la_jornada.dart';
import '../../domain/repositories/acompaniamiento_repository.dart';

/// El acompañamiento de la jornada sobre la DB local cifrada (HU-JOR-003, #146): lee la lista de
/// coordinadores que bajó con la sincronización (`campania_coordinador`), escribe una fila de
/// `jornada_acompaniante` por acompañante y la encola para que suba con la jornada.
final class AcompaniamientoRepositoryDrift implements AcompaniamientoRepository {
  AcompaniamientoRepositoryDrift(
    this._db, {
    required this._encolador,
    this._generarId = _uuidV7,
    this._ahora = DateTime.now,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final String Function() _generarId;
  final DateTime Function() _ahora;
  final AppLogger _log;

  static const _entidadDeLaLista = 'campania_coordinador';

  @override
  Stream<List<CoordinadorDeCampania>> observarLista({
    required String colportorId,
    Set<String>? campaniaIds,
  }) {
    final coordinador = _db.campaniaCoordinadores;
    final fuera = _db.syncFueraDelArea;
    final consulta =
        _db.select(coordinador).join([
            // Lo que el pull avisó que dejó de contar (0200) se marca, no se borra: acá no se ofrece.
            leftOuterJoin(
              fuera,
              fuera.entidad.equals(_entidadDeLaLista) &
                  fuera.filaId.equalsExp(coordinador.id) &
                  fuera.confirmada.equals(true),
            ),
          ])
          ..where(
            coordinador.deletedAt.isNull() &
                coordinador.usuarioId.equals(colportorId).not() &
                fuera.filaId.isNull() &
                (campaniaIds == null
                    ? coordinador.id.isNotNull()
                    : coordinador.campaniaId.isIn(campaniaIds)),
          )
          ..orderBy([
            OrderingTerm.asc(coordinador.nombre),
            OrderingTerm.asc(coordinador.apellido),
            OrderingTerm.asc(coordinador.usuarioId),
          ]);
    return consulta.watch().map((filas) {
      final vistos = <String>{};
      return [
        for (final fila in filas)
          if (vistos.add(fila.readTable(coordinador).usuarioId))
            CoordinadorDeCampania(
              usuarioId: fila.readTable(coordinador).usuarioId,
              nombre: fila.readTable(coordinador).nombre,
              apellido: fila.readTable(coordinador).apellido,
            ),
      ];
    });
  }

  @override
  Stream<List<Acompaniante>> observarDe(String jornadaId) {
    final fila = _db.jornadaAcompaniantes;
    final coordinador = _db.campaniaCoordinadores;
    final consulta =
        _db.select(fila).join([
            leftOuterJoin(
              coordinador,
              coordinador.usuarioId.equalsExp(fila.acompanianteId) & coordinador.deletedAt.isNull(),
            ),
          ])
          ..where(fila.jornadaId.equals(jornadaId) & fila.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(fila.createdAt), OrderingTerm.asc(fila.id)]);
    return consulta.watch().map((filas) {
      final vistos = <String>{};
      return [
        for (final f in filas)
          if (vistos.add(f.readTable(fila).acompanianteId))
            Acompaniante(
              usuarioId: f.readTable(fila).acompanianteId,
              nombre: f.readTableOrNull(coordinador)?.nombre,
              apellido: f.readTableOrNull(coordinador)?.apellido,
            ),
      ];
    });
  }

  @override
  Future<Either<Failure, Unit>> guardar({
    required String jornadaId,
    required String colportorId,
    required Set<String> usuarioIds,
  }) async {
    try {
      final instante = _ahora().toUtc();
      final ahora = DateTime.fromMillisecondsSinceEpoch(
        instante.millisecondsSinceEpoch,
        isUtc: true,
      );
      final sinJornada = await _db.transaction<bool>(() async {
        final jornada = await (_db.select(
          _db.jornadas,
        )..where((j) => j.id.equals(jornadaId) & j.deletedAt.isNull())).getSingleOrNull();
        if (jornada == null) return true;
        final tabla = _db.jornadaAcompaniantes;
        final vivas = await (_db.select(
          tabla,
        )..where((f) => f.jornadaId.equals(jornadaId) & f.deletedAt.isNull())).get();
        final yaEstan = <String>{};
        for (final viva in vivas) {
          if (usuarioIds.contains(viva.acompanianteId) && yaEstan.add(viva.acompanianteId)) {
            continue;
          }
          // Ya no acompaña (o es un renglón repetido de la misma persona): se da de baja, no se borra.
          await (_db.update(tabla)..where((f) => f.id.equals(viva.id))).write(
            JornadaAcompaniantesCompanion(deletedAt: Value(ahora), updatedAt: Value(ahora)),
          );
          final dadaDeBaja = await (_db.select(
            tabla,
          )..where((f) => f.id.equals(viva.id))).getSingle();
          await _encolador.encolar(
            'jornada_acompaniante',
            OperacionSync.delete,
            _aJson(dadaDeBaja),
          );
        }
        for (final usuarioId in usuarioIds.toList()..sort()) {
          if (yaEstan.contains(usuarioId)) continue;
          final nueva = JornadaAcompaniantesCompanion.insert(
            id: _generarId(),
            jornadaId: jornadaId,
            acompanianteId: usuarioId,
            createdAt: ahora,
            updatedAt: ahora,
            createdBy: Value(colportorId),
          );
          await _db.into(tabla).insert(nueva);
          final fila = await (_db.select(
            tabla,
          )..where((f) => f.id.equals(nueva.id.value))).getSingle();
          await _encolador.encolar('jornada_acompaniante', OperacionSync.insert, _aJson(fila));
        }
        return false;
      });
      if (sinJornada) {
        return const Left(
          FailureValidacion(campos: {'jornada': 'La jornada ya no está en el teléfono'}),
        );
      }
      return const Right(unit);
    } on Object catch (e, st) {
      // Nunca el nombre ni el id de la persona al log: solo la jornada.
      _log.error(
        LogModulo.db,
        'ACOMPANIAMIENTO_GUARDAR_FAIL',
        'no se pudo guardar el acompañamiento',
        {'jornada_id': jornadaId},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Stream<TendenciaDeLaJornada?> observarTendencia({
    required String colportorId,
    required String jornadaId,
    required DateTime inicio,
    DateTime? fin,
    ({String desde, String? hasta})? campania,
  }) {
    if (campania == null) return Stream.value(null);
    return _db
        .customSelect('SELECT 1', readsFrom: {_db.visitas, _db.espacios, _db.ventas, _db.jornadas})
        .watch()
        .asyncMap((_) => _leerTendencia(colportorId, jornadaId, inicio, fin, campania));
  }

  Future<TendenciaDeLaJornada?> _leerTendencia(
    String colportorId,
    String jornadaId,
    DateTime inicio,
    DateTime? fin,
    ({String desde, String? hasta}) campania,
  ) async {
    try {
      final ahora = await _contar(colportorId, inicio, fin);
      final anteriores =
          await (_db.select(_db.jornadas)
                ..where(
                  (j) =>
                      j.colportorId.equals(colportorId) &
                      j.id.equals(jornadaId).not() &
                      j.fin.isNotNull() &
                      j.deletedAt.isNull() &
                      j.inicio.isSmallerThanValue(inicio.toUtc().millisecondsSinceEpoch),
                )
                ..orderBy([(j) => OrderingTerm.desc(j.inicio)])
                ..limit(400))
              .get();
      for (final anterior in anteriores) {
        final dia = diaDeCalendario(anterior.inicio);
        final dentro =
            dia.compareTo(campania.desde) >= 0 &&
            (campania.hasta == null || dia.compareTo(campania.hasta!) <= 0);
        if (!dentro) continue;
        final antes = await _contar(colportorId, anterior.inicio, anterior.fin);
        return TendenciaDeLaJornada(
          casasVisitadas: ahora.casas,
          ventas: ahora.ventas,
          casasVisitadasAntes: antes.casas,
          ventasAntes: antes.ventas,
        );
      }
      return TendenciaDeLaJornada(casasVisitadas: ahora.casas, ventas: ahora.ventas);
    } on Object catch (e, st) {
      // Sin tendencia es mejor que un número que no es: la pantalla se ve igual.
      _log.warn(LogModulo.db, 'TENDENCIA_JORNADA_FAIL', 'no se pudo armar la tendencia', {
        'tipo': e.runtimeType.toString(),
        'rastro': st.toString().split('\n').first,
      });
      return null;
    }
  }

  /// Casas distintas con una visita y ventas de la colportora entre [desde] y [hasta] (sin tope si es
  /// `null`: una jornada en curso). Los misioneros no son ventas (`visita_misionero` no es `venta`).
  Future<({int casas, int ventas})> _contar(
    String colportorId,
    DateTime desde,
    DateTime? hasta,
  ) async {
    final tope = hasta == null ? '' : ' AND x.fecha <= ?';
    final variables = <Variable<Object>>[
      Variable.withString(colportorId),
      Variable.withInt(desde.millisecondsSinceEpoch),
      if (hasta != null) Variable.withInt(hasta.millisecondsSinceEpoch),
    ];
    final casas = await _db
        .customSelect(
          'SELECT COUNT(DISTINCT e.ubicacion_id) AS n FROM visita x '
          'JOIN espacio e ON e.id = x.espacio_id '
          'WHERE x.colportor_id = ? AND x.deleted_at IS NULL AND x.fecha >= ?$tope',
          variables: variables,
        )
        .getSingle();
    final ventas = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM venta x '
          'WHERE x.colportor_id = ? AND x.deleted_at IS NULL AND x.fecha >= ?$tope',
          variables: variables,
        )
        .getSingle();
    return (casas: casas.read<int>('n'), ventas: ventas.read<int>('n'));
  }

  static Map<String, Object?> _aJson(JornadaAcompanianteFila f) => {
    'id': f.id,
    'jornada_id': f.jornadaId,
    'acompaniante_id': f.acompanianteId,
    'created_at': f.createdAt.toUtc().toIso8601String(),
    'updated_at': f.updatedAt.toUtc().toIso8601String(),
    'created_by': f.createdBy,
    'deleted_at': f.deletedAt?.toUtc().toIso8601String(),
    'sync_version': f.syncVersion,
  };
}

String _uuidV7() => const Uuid().v7();
