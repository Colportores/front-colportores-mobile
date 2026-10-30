import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/cobranza.dart';
import '../entities/detalle_del_cobro.dart';
import '../repositories/anulacion_de_cobro_repository.dart';
import 'registrar_cobro_use_case.dart';

/// Parámetros de [AnularCobroUseCase].
final class AnularCobroParams extends Equatable {
  const AnularCobroParams({
    required this.cobranzaId,
    required this.colportorId,
    required this.motivo,
    this.justificacion,
  });

  final String cobranzaId;

  /// UUID del usuario con la sesión iniciada: solo anula cobros propios.
  final String colportorId;

  final MotivoDeAnulacion? motivo;

  /// Lo que escribió con «Otro» («Contanos qué pasó»); con otro motivo se descarta.
  final String? justificacion;

  @override
  List<Object?> get props => [cobranzaId, colportorId, motivo, justificacion];
}

/// HU-COB-006: anula un cobro que se registró por error.
///
/// 1. Pide el motivo de la lista y, con «Otro», que cuente qué pasó; el texto va sin espacios de más y
///    con un tope de [maximoJustificacion] caracteres. Sin eso **no anula nada**.
/// 2. Lo anula por [AnulacionDeCobroRepository.anular] con la hora del teléfono: dentro de las 72 h desde
///    el cobro, una sola vez, y dejando el saldo y el color de la casa como si no hubiera existido.
final class AnularCobroUseCase implements UseCase<AnulacionHecha, AnularCobroParams> {
  AnularCobroUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AnulacionDeCobroRepository _repository;
  final DateTime Function() _ahora;

  /// Lo más largo que puede ser lo que se cuenta con «Otro» (es un texto del teléfono: no sube).
  static const maximoJustificacion = 200;

  @override
  Future<Either<Failure, AnulacionHecha>> call(AnularCobroParams params) async {
    if (params.cobranzaId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return const Left(FailureCobroNoAnulado(causa: 'faltan_ids'));
    }
    final motivo = params.motivo;
    if (motivo == null) return const Left(FailureAnulacionSinMotivo());
    String? justificacion;
    if (motivo == MotivoDeAnulacion.otro) {
      justificacion = RegistrarCobroUseCase.limpiar(params.justificacion);
      if (justificacion == null || justificacion.length > maximoJustificacion) {
        return const Left(FailureAnulacionSinMotivo());
      }
    }
    return _repository.anular(
      cobranzaId: params.cobranzaId.trim(),
      motivo: motivo,
      colportorId: params.colportorId.trim(),
      ahora: _ahora().toUtc(),
      justificacion: justificacion,
    );
  }
}
