import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/espacio.dart';
import '../entities/ubicacion.dart';

/// Un espacio junto con la ubicación a la que pertenece.
typedef EspacioConUbicacion = ({Espacio espacio, Ubicacion ubicacion});

/// Persistencia de los espacios de una ubicación (HU-UBI-007, ADR-001).
///
/// Cada escritura corre en **una transacción** que también encola el sync de la fila
/// (contrato-sync-engine §3). Las reglas que dependen del estado de la DB (ubicación existente,
/// activa y no-casa; `numero_depto` sin repetir) se validan dentro de esa transacción y salen como
/// `FailureValidacion`.
abstract interface class EspacioRepository {
  /// Guarda [espacio]. Si ya hay uno con el mismo `id`, no escribe nada y devuelve el que estaba
  /// (idempotente ante doble toque).
  Future<Either<Failure, Espacio>> agregar(Espacio espacio);

  /// Cambia el `numero_depto` del espacio [id] a [numeroDepto]. Sin cambios, no escribe ni
  /// encola.
  Future<Either<Failure, Espacio>> modificar(
    String id, {
    required String numeroDepto,
    required DateTime ahora,
  });

  /// Baja lógica (R-UB04). Si ya estaba de baja, devuelve el espacio sin escribir.
  Future<Either<Failure, Espacio>> darDeBaja(String id, {required DateTime ahora});

  /// Deshace la baja lógica. Si ya estaba activo, devuelve el espacio sin escribir.
  Future<Either<Failure, Espacio>> restaurar(String id, {required DateTime ahora});

  /// El espacio [id] con su ubicación, o `null` si no existe.
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id);

  /// Espacios de [ubicacionId], por `numero_depto`. Solo los activos, salvo [incluirBajas].
  Future<Either<Failure, List<Espacio>>> listar(String ubicacionId, {bool incluirBajas = false});

  /// Cuántos espacios activos tiene [ubicacionId].
  Future<Either<Failure, int>> contarActivos(String ubicacionId);
}
