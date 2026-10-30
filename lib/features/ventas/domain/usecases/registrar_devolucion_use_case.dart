import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/devolucion.dart';
import '../repositories/devolucion_repository.dart';
import '../services/reglas_de_devolucion.dart';

/// Parámetros de [RegistrarDevolucionUseCase].
final class RegistrarDevolucionParams extends Equatable {
  const RegistrarDevolucionParams({
    required this.devolucionId,
    required this.ventaId,
    required this.colportorId,
    required this.unidadesPorRenglon,
    this.queHacer,
    this.motivo,
  });

  /// El id de la devolución: la pantalla lo genera una vez y lo repite en los reintentos con los
  /// mismos datos, así que un doble toque no registra dos.
  final String devolucionId;

  final String ventaId;

  /// Quién registra: el `created_by` de la fila.
  final String colportorId;

  /// Cuántas unidades de cada renglón vuelven: `venta_item.id` → unidades.
  final Map<String, int> unidadesPorRenglon;

  /// Qué hace con la plata de más, si el cliente pagó de más.
  final QueHacerConLaDiferencia? queHacer;

  /// El motivo tal como se escribió; se limpia acá.
  final String? motivo;

  @override
  List<Object?> get props => [
    devolucionId,
    ventaId,
    colportorId,
    unidadesPorRenglon,
    queHacer,
    motivo,
  ];
}

/// HU-VEN-004: registra la devolución de una venta —parcial o total— sin anularla ni tocarla, y deja
/// la casa del color que corresponde, todo en una sola transacción (ADR-002).
///
/// 1. No guarda nada si faltan los ids o no se eligió ninguna unidad.
/// 2. Limpia el motivo (sin espacios en los bordes, `null` si queda en blanco, tope de 500).
/// 3. Pone la hora de ahora como fecha de la devolución y como punto de las 72 h.
/// 4. Lo guarda por [DevolucionRepository.registrar], que es idempotente y comprueba la venta, el plazo
///    y lo elegido dentro de la transacción.
///
/// En V1 no hay stock ni beca (el stock y la beca son V2, decisión del 23/10, docs-organizacion#69): la
/// devolución guarda los productos y las cantidades para que V2 los recalcule sin perder nada.
final class RegistrarDevolucionUseCase
    implements UseCase<DevolucionRegistrada, RegistrarDevolucionParams> {
  RegistrarDevolucionUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final DevolucionRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, DevolucionRegistrada>> call(RegistrarDevolucionParams params) async {
    if (params.devolucionId.trim().isEmpty ||
        params.ventaId.trim().isEmpty ||
        params.colportorId.trim().isEmpty) {
      return const Left(FailureDevolucionNoGuardada(causa: 'faltan_ids'));
    }
    if (!params.unidadesPorRenglon.values.any((n) => n > 0)) {
      return const Left(FailureDevolucionInvalida(causa: 'sin_productos'));
    }
    return _repository.registrar(
      PedidoDeDevolucion(
        id: params.devolucionId.trim(),
        ventaId: params.ventaId.trim(),
        colportorId: params.colportorId.trim(),
        unidadesPorRenglon: {
          for (final MapEntry(:key, :value) in params.unidadesPorRenglon.entries)
            if (value != 0) key: value,
        },
        queHacer: params.queHacer,
        motivo: ReglasDeDevolucion.motivo(params.motivo),
        ahora: _ahora().toUtc(),
      ),
    );
  }
}
