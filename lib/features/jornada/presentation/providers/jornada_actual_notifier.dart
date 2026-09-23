import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/jornada.dart';
import '../../domain/usecases/iniciar_jornada_use_case.dart';
import '../../domain/usecases/obtener_jornada_activa_use_case.dart';
import 'jornada_providers.dart';

part 'jornada_actual_notifier.g.dart';

/// La jornada en curso del colportor [colportorId] (`null` = no tiene ninguna), para la pantalla
/// principal (HU-JOR-001).
///
/// Sin lógica de negocio (vive en los casos de uso): solo traduce resultados a estado. Si la
/// lectura falla, el estado queda en error con el [Failure] como causa; la pantalla ofrece
/// reintentar con `ref.invalidate`.
@riverpod
class JornadaActual extends _$JornadaActual {
  @override
  Future<Jornada?> build(String colportorId) async {
    final resultado = await ref.watch(obtenerJornadaActivaUseCaseProvider)(
      ObtenerJornadaActivaParams(colportorId: colportorId),
    );
    return resultado.fold((failure) => throw failure, (jornada) => jornada);
  }

  /// Inicia la jornada ahora, o a [hora] si el colportor la ajustó (hasta 30 min hacia atrás).
  ///
  /// Devuelve el [Failure] si no se pudo (para que la pantalla lo muestre) o `null` si se inició.
  /// Con [FailureJornadaActiva] —otra jornada se abrió mientras la pantalla mostraba "sin
  /// jornada", por ejemplo con dos toques seguidos— relee el estado para que la pantalla pase a
  /// "Jornada activa".
  Future<Failure?> iniciar({DateTime? hora}) async {
    final resultado = await ref.read(iniciarJornadaUseCaseProvider)(
      IniciarJornadaParams(colportorId: colportorId, hora: hora),
    );
    if (!ref.mounted) return resultado.fold((failure) => failure, (_) => null);

    return resultado.fold(
      (failure) {
        if (failure is FailureJornadaActiva) ref.invalidateSelf();
        return failure;
      },
      (jornada) {
        state = AsyncData(jornada);
        return null;
      },
    );
  }
}
