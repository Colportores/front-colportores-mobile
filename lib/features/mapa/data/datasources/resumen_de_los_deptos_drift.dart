import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/resumen_del_depto.dart';
import '../../domain/services/lector_resumen_de_los_deptos.dart';
import '../services/hechos_del_color_drift.dart';

/// [LectorResumenDeLosDeptos] sobre la DB local. El estado de cada depto es la cuenta del color de la
/// casa ([HechosDelColorDrift]) hecha con ese depto solo; la última visita es la de fecha más reciente
/// que no esté dada de baja, y la próxima entrevista, la `PROGRAMADA` de tipo `ENTREVISTA` más cercana
/// del colportor que todavía no pasó (la misma regla que la Lista, #491).
///
/// Vuelve a leer cuando cambia cualquiera de las tablas de las que sale el estado (espacios, agendas,
/// visitas, ventas y sus cobros, entregas y devoluciones). Dos avisos seguidos no se pisan: si llega
/// uno mientras lee, al terminar lee otra vez; y emite solo si algo cambió.
final class ResumenDeLosDeptosDrift implements LectorResumenDeLosDeptos {
  /// [_ahora] se pasa como `ahora:` (parámetro nombrado privado, Dart ≥ 3.10).
  ResumenDeLosDeptosDrift(this._db, {required this._ahora});

  final AppDatabase _db;
  final DateTime Function() _ahora;

  @override
  Stream<Map<String, ResumenDelDepto>> observar(String ubicacionId, {String? colportorId}) {
    late final StreamController<Map<String, ResumenDelDepto>> salida;
    StreamSubscription<Set<TableUpdate>>? alCambiar;
    var cancelado = false;
    var leyendo = false;
    var otraVez = false;
    Map<String, ResumenDelDepto>? ultimo;

    Future<void> leer() async {
      if (leyendo) {
        otraVez = true;
        return;
      }
      leyendo = true;
      try {
        do {
          otraVez = false;
          final leido = await _leer(ubicacionId, colportorId);
          if (cancelado) return;
          if (!_mismo(leido, ultimo)) {
            ultimo = leido;
            salida.add(leido);
          }
        } while (otraVez && !cancelado);
      } on Object catch (error, pila) {
        if (!cancelado) salida.addError(error, pila);
      } finally {
        leyendo = false;
      }
    }

    salida = StreamController<Map<String, ResumenDelDepto>>(
      onListen: () {
        // Se escucha antes de la primera lectura: un cambio a mitad de ella no se pierde.
        alCambiar = _db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                _db.espacios,
                _db.agendas,
                _db.visitas,
                _db.espacioPersonas,
                _db.ventas,
                _db.ventaItems,
                _db.cobranzas,
                _db.entregas,
                _db.devoluciones,
              ]),
            )
            .listen((_) => unawaited(leer()));
        unawaited(leer());
      },
      onCancel: () async {
        cancelado = true;
        await alCambiar?.cancel();
      },
    );
    return salida.stream;
  }

  Future<Map<String, ResumenDelDepto>> _leer(String ubicacionId, String? colportorId) async {
    final espacios = await (_db.select(
      _db.espacios,
    )..where((e) => e.ubicacionId.equals(ubicacionId) & e.deletedAt.isNull())).get();
    final hechos = HechosDelColorDrift(_db);
    final desde = const FechaUtcConverter().toSql(_ahora());
    final salida = <String, ResumenDelDepto>{};
    for (final espacio in espacios) {
      JoinedSelectStatement<HasResultSet, dynamic> solo() => _db.selectOnly(_db.espacios)
        ..addColumns([_db.espacios.id])
        ..where(_db.espacios.id.equals(espacio.id));
      final color = await hechos.color(activos: solo);
      final ultima =
          await (_db.select(_db.visitas)
                ..where((v) => v.espacioId.equals(espacio.id) & v.deletedAt.isNull())
                ..orderBy([(v) => OrderingTerm.desc(v.fecha)])
                ..limit(1))
              .getSingleOrNull();
      final proxima = colportorId == null
          ? null
          : await (_db.select(_db.agendas)
                  ..where(
                    (a) =>
                        a.espacioId.equals(espacio.id) &
                        a.colportorId.equals(colportorId) &
                        a.estado.equals(EstadoAgenda.programada.codigo) &
                        a.tipo.equals(TipoAgenda.entrevista.codigo) &
                        a.deletedAt.isNull() &
                        a.fechaProgramada.isBiggerOrEqualValue(desde),
                  )
                  ..orderBy([(a) => OrderingTerm.asc(a.fechaProgramada)])
                  ..limit(1))
                .getSingleOrNull();
      salida[espacio.id] = ResumenDelDepto(
        estado: EstadoCasa.desdeColor(color),
        ultimaVisita: ultima?.fecha,
        proximaEntrevista: proxima?.fechaProgramada,
      );
    }
    return salida;
  }

  static bool _mismo(Map<String, ResumenDelDepto> a, Map<String, ResumenDelDepto>? b) =>
      b != null && a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
