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
}
