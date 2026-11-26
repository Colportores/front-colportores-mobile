import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/transferencia.dart';
import '../repositories/transferencia_repository.dart';

/// Parámetros de [CancelarTransferenciaUseCase].
final class CancelarTransferenciaParams extends Equatable {
  const CancelarTransferenciaParams({required this.transferenciaId, required this.colportorId});

  final String transferenciaId;

  /// Quien cancela: tiene que ser quien la pidió.
  final String colportorId;

  @override
  List<Object?> get props => [transferenciaId, colportorId];
}

/// «Cancelar tr.» (decisión de Cristian, 28/10): quien pidió la transferencia la pasa a «Cancelada»
/// mientras está por autorizar. Autorizada o rechazada, ya no; la ajena tampoco. Se cancela en el
/// teléfono y sube después; si la coordinadora la decidió mientras tanto, el servidor lo dice y la
/// transferencia queda como la decidió.
final class CancelarTransferenciaUseCase
    implements UseCase<Transferencia, CancelarTransferenciaParams> {
  CancelarTransferenciaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final TransferenciaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Transferencia>> call(CancelarTransferenciaParams params) {
    if (params.transferenciaId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return Future.value(const Left(FailureTransferenciaNoCancelable()));
    }
    return _repository.cancelar(
      id: params.transferenciaId.trim(),
      colportorId: params.colportorId.trim(),
      ahora: _ahora().toUtc(),
    );
  }
}
