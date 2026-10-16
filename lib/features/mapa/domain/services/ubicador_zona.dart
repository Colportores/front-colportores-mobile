import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../repositories/zona_repository.dart';
import '../value_objects/coordenadas.dart';
import 'inscripciones_colportor.dart';
import 'zona_por_posicion.dart';

/// La zona de un punto para un colportor, y si es una de las suyas.
///
/// `esDeMisZonas` es lo que el servidor mira para dejar mover una ubicación ajena: la zona nueva
/// tiene que estar en `mis_zonas()` (las asignadas en sus inscripciones vigentes).
typedef ZonaDelPunto = ({String? zonaId, bool esDeMisZonas});

/// Junta lo que [ZonaPorPosicion] necesita para ubicar un punto que registra o mueve el colportor
/// `colportorId` (backend-supabase 0010, «al crear la ubicación o moverla»):
///
/// - las zonas vivas de la ciudad ([ZonaRepository]);
/// - como campañas preferidas (D2, provisoria: «la de la campaña del colportor»), las de sus
///   inscripciones vigentes ([InscripcionesColportor]), ordenadas por id como en el servidor.
///
/// **Vigencia.** El servidor toma las zonas de toda campaña vigente de la ciudad. El teléfono solo
/// recibe el mapa de las campañas en las que el colportor está inscripto (RLS de 0008), así que
/// acá las vigentes son las de sus inscripciones vigentes: fuera de esas no hay zonas que mirar.
/// Si alguna vez difieren, el servidor recalcula la zona y gana.
final class UbicadorZona {
  /// [_regla] se pasa como `regla:`.
  UbicadorZona(this._zonas, this._inscripciones, {this._regla = const ZonaPorPosicion()});

  final ZonaRepository _zonas;
  final InscripcionesColportor _inscripciones;
  final ZonaPorPosicion _regla;

  Future<Either<Failure, ZonaDelPunto>> ubicar(
    Coordenadas punto, {
    required String colportorId,
    required String ciudadId,
  }) async {
    final inscripciones = await _inscripciones.vigentesDe(colportorId);
    return inscripciones.fold<Future<Either<Failure, ZonaDelPunto>>>((falla) async => Left(falla), (
      vigentes,
    ) async {
      final leidas = await _zonas.vivasDeCiudad(ciudadId);
      return leidas.map((zonas) {
        final campanias = {for (final i in vigentes) i.campaniaId};
        final preferidas = campanias.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final zonaId = _regla.zonaDe(
          punto,
          ciudadId: ciudadId,
          zonas: zonas,
          campaniasVigentes: campanias,
          campaniasPreferidas: preferidas,
        );
        final misZonas = {for (final i in vigentes) ?i.zonaId};
        return (zonaId: zonaId, esDeMisZonas: zonaId != null && misZonas.contains(zonaId));
      });
    });
  }
}
