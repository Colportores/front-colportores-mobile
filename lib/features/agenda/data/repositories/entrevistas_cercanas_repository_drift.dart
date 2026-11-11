import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../../mapa/domain/value_objects/coordenadas.dart';
import '../../domain/entities/entrevista_cercana.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/repositories/entrevistas_cercanas_repository.dart';

/// [EntrevistasCercanasRepository] sobre la DB cifrada: las agendas `ENTREVISTA` y `PROGRAMADA` del
/// colportor, unidas a la ubicación de su espacio, dentro de una caja alrededor de la casa (el filtro
/// grueso lo hace SQL) y después con la distancia exacta (haversine, [Coordenadas.distanciaMetrosA]).
///
/// Un `LEFT JOIN` no sirve acá: una entrevista cuya casa no llegó al teléfono no tiene coordenadas,
/// así que no se puede saber si está cerca y no cuenta. Las de una casa o un depto dados de baja
/// tampoco (la agenda queda guardada y vuelve si se reactivan, como en las otras lecturas).
final class EntrevistasCercanasRepositoryDrift implements EntrevistasCercanasRepository {
  EntrevistasCercanasRepositoryDrift(this._db);

  final AppDatabase _db;

  /// Metros por grado de latitud (casi constante en todo el globo).
  static const _metrosPorGrado = 111000.0;

  @override
  Future<List<EntrevistaCercana>> leer({
    required String colportorId,
    required String espacioId,
    required DateTime desde,
    double radioMetros = radioDeEntrevistasCercanasMetros,
  }) async {
    final espacios = _db.espacios;
    final ubicaciones = _db.ubicaciones;
    final referencia =
        await (_db.select(espacios).join([
              innerJoin(ubicaciones, ubicaciones.id.equalsExp(espacios.ubicacionId)),
            ])..where(
              espacios.id.equals(espacioId) &
                  espacios.deletedAt.isNull() &
                  ubicaciones.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (referencia == null) return const [];
    final casa = referencia.readTable(ubicaciones);
    final centro = Coordenadas(lat: casa.lat, lon: casa.lon);
    if (!centro.estanEnRango || centro.sonCero) return const [];

    final agendas = _db.agendas;
    const conversor = FechaUtcConverter();
    final deLat = radioMetros / _metrosPorGrado;
    final deLon =
        radioMetros / (_metrosPorGrado * math.max(0.01, math.cos(centro.lat * math.pi / 180)));
    final filas =
        await (_db.select(agendas).join([
                innerJoin(espacios, espacios.id.equalsExp(agendas.espacioId)),
                innerJoin(ubicaciones, ubicaciones.id.equalsExp(espacios.ubicacionId)),
              ])
              ..where(
                agendas.colportorId.equals(colportorId) &
                    agendas.tipo.equals(TipoAgenda.entrevista.codigo) &
                    agendas.estado.equals(EstadoAgenda.programada.codigo) &
                    agendas.deletedAt.isNull() &
                    espacios.deletedAt.isNull() &
                    ubicaciones.deletedAt.isNull() &
                    agendas.fechaProgramada.isBiggerOrEqualValue(conversor.toSql(desde)) &
                    ubicaciones.lat.isBetweenValues(centro.lat - deLat, centro.lat + deLat) &
                    ubicaciones.lon.isBetweenValues(centro.lon - deLon, centro.lon + deLon),
              )
              ..orderBy([OrderingTerm.asc(agendas.fechaProgramada), OrderingTerm.asc(agendas.id)]))
            .get();

    return [
      for (final fila in filas)
        if (centro.distanciaMetrosA(
              Coordenadas(
                lat: fila.readTable(ubicaciones).lat,
                lon: fila.readTable(ubicaciones).lon,
              ),
            ) <
            radioMetros)
          EntrevistaCercana(
            fecha: fila.readTable(agendas).fechaProgramada,
            slotCodigo: fila.readTable(agendas).slotCodigo,
          ),
    ];
  }
}
