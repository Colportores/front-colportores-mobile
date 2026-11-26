import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/transferencia.dart';
import '../repositories/transferencia_repository.dart';

/// Un material pedido: qué producto y cuántas unidades.
final class MaterialPedido extends Equatable {
  const MaterialPedido({required this.productoId, required this.cantidad});

  final String productoId;
  final int cantidad;

  @override
  List<Object?> get props => [productoId, cantidad];
}

/// Parámetros de [PedirTransferenciaUseCase].
final class PedirTransferenciaParams extends Equatable {
  const PedirTransferenciaParams({
    required this.transferenciaId,
    required this.colportorId,
    required this.entregaId,
    required this.materiales,
    required this.idsDeLineas,
  });

  /// El id de la transferencia: lo genera quien abre la pantalla y se repite en los reintentos, así un
  /// doble toque o un reintento tras una falla no pide dos transferencias.
  final String transferenciaId;

  /// Quien pide y recibe: el `destino_id` y el `created_by`.
  final String colportorId;

  /// A quien se lo pide: quien entrega, el `origen_id`.
  final String entregaId;

  final List<MaterialPedido> materiales;

  /// Un id por línea, en el mismo orden que [materiales]; también estables entre reintentos.
  final List<String> idsDeLineas;

  @override
  List<Object?> get props => [transferenciaId, colportorId, entregaId, materiales, idsDeLineas];
}

/// HU-STK-005: el colportor le pide materiales a otro de su campaña.
///
/// 1. Valida lo que el servidor rechazaría (`23514`, `23505`): el compañero es otra persona, hay al menos
///    un material, ninguna cantidad es cero ni negativa y ningún producto se repite. **No guarda nada**
///    si algo está mal.
/// 2. La guarda **por autorizar** por [TransferenciaRepository.pedir], que escribe todo o nada y encola
///    el sync. No mueve stock ni deuda: eso pasa recién cuando la coordinadora la autoriza.
///
/// Con el mismo `transferenciaId` es idempotente. No mira el stock de quien entrega (lo mira el
/// servidor al autorizar, con el stock de ese momento) ni lleva texto libre: ningún texto del teléfono
/// sube sin decisión (backend 0139).
final class PedirTransferenciaUseCase
    implements UseCase<TransferenciaPedida, PedirTransferenciaParams> {
  PedirTransferenciaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final TransferenciaRepository _repository;
  final DateTime Function() _ahora;

  /// Lo más que cabe en una línea (el mismo tope del selector de la venta).
  static const maximoPorLinea = 999;

  /// Por qué [params] no se puede guardar, o `null` si se puede.
  static Failure? validar(PedirTransferenciaParams params) {
    if (params.transferenciaId.trim().isEmpty ||
        params.colportorId.trim().isEmpty ||
        params.entregaId.trim().isEmpty ||
        params.entregaId == params.colportorId ||
        params.materiales.isEmpty ||
        params.idsDeLineas.length != params.materiales.length ||
        params.idsDeLineas.any((id) => id.trim().isEmpty)) {
      return const FailureTransferenciaInvalida();
    }
    final vistos = <String>{};
    for (final m in params.materiales) {
      if (m.productoId.trim().isEmpty ||
          m.cantidad <= 0 ||
          m.cantidad > maximoPorLinea ||
          !vistos.add(m.productoId)) {
        return const FailureTransferenciaInvalida();
      }
    }
    return null;
  }

  @override
  Future<Either<Failure, TransferenciaPedida>> call(PedirTransferenciaParams params) async {
    final falla = validar(params);
    if (falla != null) return Left(falla);
    final ahora = _ahora().toUtc();
    final colportor = params.colportorId.trim();
    return _repository.pedir(
      Transferencia(
        id: params.transferenciaId.trim(),
        origenId: params.entregaId.trim(),
        destinoId: colportor,
        estado: EstadoDeTransferencia.porAutorizar,
        lineas: [
          for (var i = 0; i < params.materiales.length; i++)
            LineaDeTransferencia(
              id: params.idsDeLineas[i].trim(),
              productoId: params.materiales[i].productoId,
              cantidad: params.materiales[i].cantidad,
            ),
        ],
        auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportor),
      ),
    );
  }
}
