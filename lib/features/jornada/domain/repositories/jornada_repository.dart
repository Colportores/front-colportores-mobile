import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/jornada.dart';

/// Persistencia de [Jornada] (HU-JOR-001). Interfaz de dominio: la implementación vive en `data`
/// (ADR-009) y es la que escribe en la DB local cifrada y encola el sync.
abstract interface class JornadaRepository {
  /// La jornada en curso del colportor ([Jornada.estaAbierta]: sin `fin` y sin soft delete), o
  /// `null` si no tiene ninguna.
  Future<Either<Failure, Jornada?>> obtenerActiva(String colportorId);

  /// Persiste una jornada nueva y devuelve la entidad guardada.
  ///
  /// Si el colportor ya tiene una jornada abierta devuelve `Left(FailureJornadaActiva)` aunque el
  /// llamador haya comprobado antes con [obtenerActiva]: esa comprobación y la escritura no son
  /// atómicas (dos toques seguidos en "Iniciar jornada"), así que la garantía de "una sola jornada
  /// activa" la cierra el almacenamiento, no el caso de uso.
  Future<Either<Failure, Jornada>> crear(Jornada jornada);

  /// Guarda el cierre de [jornada] (HU-JOR-002): su `fin` y su `updated_at`. [jornada] ya viene
  /// cerrada ([Jornada.finalizada]); el resto de sus campos no se escribe.
  ///
  /// Si la jornada ya no está abierta en el almacenamiento (la cerró un toque anterior, o no
  /// existe) devuelve `Left(FailureSinJornadaActiva)` y no pisa el `fin` que ya tenía: como en
  /// [crear], comprobar y escribir es atómico en el almacenamiento, no en el caso de uso.
  Future<Either<Failure, Jornada>> finalizar(Jornada jornada);
}
