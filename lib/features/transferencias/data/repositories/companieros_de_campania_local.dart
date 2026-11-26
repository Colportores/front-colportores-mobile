import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/companiero_de_campania.dart';
import '../../domain/repositories/companieros_de_campania_repository.dart';

/// Los compañeros de campaña, leídos del teléfono: la tabla `campania_companiero` (de solo bajada, que el
/// servidor llena con los nombres, el apellido y la ciudad de quienes están en las mismas campañas,
/// backend-supabase 0208, «Nombres camp.» de Cristian, 24/11, #769) y la campaña en curso del colportor.
///
/// La campaña es la más reciente de las que están en curso ([hoy] entre su inicio y su fin, o sin fin)
/// y en las que el colportor está inscripto. Sin ninguna en el teléfono no hay de dónde sacar la lista:
/// [FailureCompanierosNoDisponibles] (la pantalla dice que no pudo traerlos). Con campaña y sin
/// compañeros, la lista es vacía (40A·09), no un error. No aparece quien pregunta ni quien dejó la
/// campaña (`deleted_at`).
final class CompanierosDeCampaniaLocal implements CompanierosDeCampaniaRepository {
  const CompanierosDeCampaniaLocal(this._db, this._hoy);

  final AppDatabase _db;

  /// El día de calendario de Montevideo, sin hora.
  final DateTime Function() _hoy;

  @override
  Future<Either<Failure, CompanierosDeCampania>> listar(String colportorId) async {
    try {
      final campania = await _campaniaEnCurso(colportorId);
      if (campania == null) return const Left(FailureCompanierosNoDisponibles());

      final c = _db.campaniaCompanieros;
      final ciudades = _db.ciudades;
      final consulta =
          _db.select(c).join([leftOuterJoin(ciudades, ciudades.id.equalsExp(c.ciudadId))])
            ..where(
              c.campaniaId.equals(campania.id) &
                  c.deletedAt.isNull() &
                  c.usuarioId.equals(colportorId).not(),
            )
            ..orderBy([
              OrderingTerm.asc(c.nombre),
              OrderingTerm.asc(c.apellido),
              OrderingTerm.asc(c.usuarioId),
            ]);
      final vistos = <String>{};
      final companieros = <CompanieroDeCampania>[];
      for (final fila in await consulta.get()) {
        final persona = fila.readTable(c);
        // Una persona con dos filas (dos inscripciones) se muestra una sola vez.
        if (!vistos.add(persona.usuarioId)) continue;
        final nombre = '${persona.nombre} ${persona.apellido}'.trim();
        companieros.add(
          CompanieroDeCampania(
            id: persona.usuarioId,
            nombre: nombre,
            lugar: fila.readTableOrNull(ciudades)?.nombre,
          ),
        );
      }
      return Right(CompanierosDeCampania(campania: campania.nombre, companieros: companieros));
    } on Object {
      return const Left(FailureCompanierosNoDisponibles());
    }
  }

  Future<CampaniaFila?> _campaniaEnCurso(String colportorId) async {
    final hoy = _hoy();
    final dia =
        '${hoy.year.toString().padLeft(4, '0')}-${hoy.month.toString().padLeft(2, '0')}-'
        '${hoy.day.toString().padLeft(2, '0')}';
    final campanias = _db.campanias;
    final inscripciones = _db.campaniasColportor;
    final consulta =
        _db.select(campanias).join([
            innerJoin(inscripciones, inscripciones.campaniaId.equalsExp(campanias.id)),
          ])
          ..where(
            inscripciones.usuarioId.equals(colportorId) &
                inscripciones.deletedAt.isNull() &
                campanias.deletedAt.isNull() &
                campanias.fechaInicio.isSmallerOrEqualValue(dia) &
                (campanias.fechaFin.isNull() | campanias.fechaFin.isBiggerOrEqualValue(dia)),
          )
          ..orderBy([OrderingTerm.desc(campanias.fechaInicio), OrderingTerm.asc(campanias.id)])
          ..limit(1);
    final filas = await consulta.get();
    return filas.isEmpty ? null : filas.first.readTable(campanias);
  }
}
