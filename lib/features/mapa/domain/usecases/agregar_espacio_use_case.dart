import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio.dart';
import '../repositories/espacio_repository.dart';

/// Parámetros de [AgregarEspacioUseCase].
final class AgregarEspacioParams extends Equatable {
  const AgregarEspacioParams({
    required this.id,
    required this.ubicacionId,
    required this.colportorId,
    required this.numeroDepto,
  });

  /// El `id` (UUID v7) de este alta: la pantalla lo genera una vez por formulario
  /// ([AgregarEspacioUseCase.nuevoId]) y lo repite en cada intento, así que un doble toque no crea
  /// dos espacios.
  final String id;

  final String ubicacionId;

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  /// Obligatorio: el espacio sin número es el default de la casa y no se crea desde acá.
  final String numeroDepto;

  @override
  List<Object?> get props => [id, ubicacionId, colportorId, numeroDepto];
}

/// HU-UBI-007 — Alta de un espacio (departamento, local) dentro de una ubicación.
///
/// 1. Sin `id`, ubicación, colportor o número de departamento (en blanco cuenta como vacío):
///    `Left(FailureValidacion)` con el detalle por campo.
/// 2. Arma el espacio —`id` UUID v7 del alta, `numero_depto` sin espacios en los bordes, auditoría
///    con el colportor como `created_by`— y se lo pasa al repositorio, que en una sola transacción
///    valida que la ubicación exista, esté activa y no sea una `CASA`, que el número no repita el
///    de otro espacio activo de la ubicación, y guarda y encola el sync.
///
/// Todo es local: sin red el alta se completa y el sync queda en la cola. La ubicación ya se
/// encoló cuando se creó, así que en la cola siempre va antes que su espacio.
final class AgregarEspacioUseCase implements UseCase<Espacio, AgregarEspacioParams> {
  AgregarEspacioUseCase(
    this._repository, {
    required String Function() generarId,
    DateTime Function()? ahora,
  }) : _generarId = generarId,
       _ahora = ahora ?? DateTime.now;

  final EspacioRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Un `id` nuevo para un formulario de alta (ver [AgregarEspacioParams.id]).
  String nuevoId() => _generarId();

  @override
  Future<Either<Failure, Espacio>> call(AgregarEspacioParams params) {
    final id = params.id.trim();
    final ubicacionId = params.ubicacionId.trim();
    final colportorId = params.colportorId.trim();
    final numeroDepto = params.numeroDepto.trim();

    final campos = <String, String>{
      if (id.isEmpty) 'id': 'Falta el identificador del alta del espacio',
      if (ubicacionId.isEmpty) 'ubicacionId': 'Falta la ubicación del espacio',
      if (colportorId.isEmpty) 'colportorId': 'No hay un colportor para registrar el espacio',
      if (numeroDepto.isEmpty) 'numeroDepto': 'Ingresá el número o nombre del espacio.',
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));

    final ahora = _ahora();
    return _repository.agregar(
      Espacio(
        id: id,
        ubicacionId: ubicacionId,
        numeroDepto: numeroDepto,
        auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId),
      ),
    );
  }
}
