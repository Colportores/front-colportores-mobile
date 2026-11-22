import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio.dart';
import '../repositories/espacio_repository.dart';

/// Parámetros de [ModificarEspacioUseCase]: el valor final, no un delta.
final class ModificarEspacioParams extends Equatable {
  const ModificarEspacioParams({required this.id, required this.numeroDepto, this.piso});

  final String id;

  final String numeroDepto;

  /// El piso que queda: `null` o en blanco lo deja sin piso (vista 11, «Piso · opcional»).
  final String? piso;

  @override
  List<Object?> get props => [id, numeroDepto, piso];
}

/// HU-UBI-007 — Modificar el `numero_depto` y el `piso` de un espacio.
///
/// Editarlo con personas asociadas es válido: es solo una etiqueta visual (caso borde de la HU).
/// Sin `id` o con el número en blanco: `Left(FailureValidacion)`. El repositorio valida en la
/// transacción que el espacio exista y esté activo, que su ubicación no sea una `CASA` (el espacio
/// default no se edita) y que el número no repita el de otro espacio activo. Si ni el número ni el
/// piso cambian, no escribe ni encola nada.
final class ModificarEspacioUseCase implements UseCase<Espacio, ModificarEspacioParams> {
  ModificarEspacioUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final EspacioRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Espacio>> call(ModificarEspacioParams params) {
    final id = params.id.trim();
    final numeroDepto = params.numeroDepto.trim();
    final piso = params.piso?.trim();

    final campos = <String, String>{
      if (id.isEmpty) 'id': 'Falta el espacio a modificar',
      if (numeroDepto.isEmpty) 'numeroDepto': 'Ingresá el número o nombre del espacio.',
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));

    return _repository.modificar(
      id,
      numeroDepto: numeroDepto,
      piso: piso == null || piso.isEmpty ? null : piso,
      ahora: _ahora(),
    );
  }
}
