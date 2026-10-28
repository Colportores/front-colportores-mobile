import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/componente_vendido.dart';
import '../entities/entrega.dart';
import '../repositories/entrega_repository.dart';

/// Parámetros de [EntregarAhoraUseCase].
final class EntregarAhoraParams extends Equatable {
  const EntregarAhoraParams({
    required this.ventaId,
    required this.colportorId,
    required this.aEntregar,
    this.quedanPendientes = const [],
  });

  final String ventaId;

  /// Quién entrega: el `created_by` de las filas.
  final String colportorId;

  /// Lo que se entrega ahora (lo que la colportora dejó tildado). No puede estar vacío.
  final List<ComponenteVendido> aEntregar;

  /// Lo que destildó: queda pendiente para otro día.
  final List<ComponenteVendido> quedanPendientes;

  @override
  List<Object?> get props => [ventaId, colportorId, aEntregar, quedanPendientes];
}

/// HU-VEN-002: «Entregar ahora». Marca como entregado lo que la colportora tildó y deja pendiente lo
/// que destildó, todo en una sola transacción con el recálculo del color de la casa.
///
/// 1. Valida y **no guarda nada** si algo está mal: al menos un producto para entregar y cantidades de
///    1 o más.
/// 2. Arma **una fila por producto** (suma lo que el mismo producto cuenta en distintas filas de
///    pantalla): las entregadas llevan la hora de ahora y `pendiente = false`; las pendientes, sin
///    fecha y `pendiente = true`.
/// 3. Las guarda por [EntregaRepository.entregarAhora], que es idempotente por venta: un doble toque o
///    un reintento no entrega dos veces.
///
/// En V1 no hay stock: la app confía en lo que lleva la colportora (decisión del 23/10, el stock es
/// V2, HU-STK-007).
final class EntregarAhoraUseCase implements UseCase<EntregaRegistrada, EntregarAhoraParams> {
  EntregarAhoraUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final EntregaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Lo más que se puede entregar de un producto (igual que lo más que se vende de una línea).
  static const maximoPorProducto = 99999;

  @override
  Future<Either<Failure, EntregaRegistrada>> call(EntregarAhoraParams params) async {
    final entregar = _sumar(params.aEntregar);
    final pendientes = _sumar(params.quedanPendientes);
    if (entregar.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'productos': 'Elegí al menos un producto para entregar.'}),
      );
    }
    final cantidades = [...entregar.values, ...pendientes.values];
    if (cantidades.any((c) => c < 1 || c > maximoPorProducto)) {
      return const Left(
        FailureValidacion(campos: {'productos': 'La cantidad de un producto no es válida.'}),
      );
    }

    final ahora = _ahora();
    Auditoria auditoria() =>
        Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: params.colportorId);
    final filas = [
      for (final MapEntry(:key, :value) in entregar.entries)
        Entrega(
          id: _generarId(),
          ventaId: params.ventaId,
          productoId: key,
          cantidad: value,
          pendiente: false,
          fechaEntrega: ahora,
          auditoria: auditoria(),
        ),
      for (final MapEntry(:key, :value) in pendientes.entries)
        Entrega(
          id: _generarId(),
          ventaId: params.ventaId,
          productoId: key,
          cantidad: value,
          pendiente: true,
          auditoria: auditoria(),
        ),
    ];
    return _repository.entregarAhora(params.ventaId, filas);
  }

  /// Una cantidad por producto, en el orden en que aparecen.
  static Map<String, int> _sumar(List<ComponenteVendido> componentes) {
    final suma = <String, int>{};
    for (final c in componentes) {
      suma[c.productoId] = (suma[c.productoId] ?? 0) + c.cantidad;
    }
    return suma;
  }
}
