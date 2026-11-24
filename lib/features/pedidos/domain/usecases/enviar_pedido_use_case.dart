import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/armado_del_pedido.dart';
import '../entities/pedido.dart';
import '../repositories/pedido_repository.dart';
import '../services/calculador_del_pedido.dart';

/// Parámetros de [EnviarPedidoUseCase].
final class EnviarPedidoParams extends Equatable {
  const EnviarPedidoParams({
    required this.pedidoId,
    required this.colportorId,
    required this.cantidades,
    required this.productos,
    required this.idsDeLineas,
    this.excedeLimite = false,
  });

  /// El id del pedido: lo genera quien abre la pantalla y se repite en los reintentos, así un doble toque o
  /// un reintento tras una falla no manda dos pedidos.
  final String pedidoId;

  final String colportorId;

  /// `productoId → unidades` de lo armado.
  final Map<String, int> cantidades;

  /// Los productos que se pueden pedir: de ahí salen el precio de compra y la validación.
  final List<ProductoPedible> productos;

  /// Un id por producto pedido, también estables entre reintentos (`productoId → id de la línea`).
  final Map<String, String> idsDeLineas;

  /// La pantalla avisó que el pedido pasaba el límite: se guarda para mostrarlo en el detalle sin conexión.
  /// No sube (el servidor lo mide solo) y no cambia lo que se puede enviar.
  final bool excedeLimite;

  @override
  List<Object?> get props => [
    pedidoId,
    colportorId,
    cantidades,
    productos,
    idsDeLineas,
    excedeLimite,
  ];
}

/// HU-STK-009: la colportora envía su pedido a la casa editora.
///
/// 1. Valida lo que el servidor rechazaría (`23514`, `23505`): al menos un producto, cantidades enteras de
///    1 a [maximoPorLinea], sin productos repetidos, solo productos que se pueden pedir. **No guarda nada**
///    si algo está mal.
/// 2. Lo guarda **por autorizar** con [PedidoRepository.enviar], que escribe todo o nada y encola el sync
///    (el pedido antes que sus líneas). Sin conexión queda en la cola y sube solo.
///
/// **El límite de deuda solo avisa: este caso de uso no lo mira** (decisión de Cristian, 21/10 y 25/10; el
/// servidor lo mide al llegar y el coordinador decide). El precio de cada línea lo pone el servidor: acá solo
/// se estima el monto para mostrarlo.
final class EnviarPedidoUseCase implements UseCase<PedidoEnviado, EnviarPedidoParams> {
  EnviarPedidoUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PedidoRepository _repository;
  final DateTime Function() _ahora;

  /// Lo más que cabe en una línea (el mismo tope del selector de la venta).
  static const maximoPorLinea = 999;

  /// Por qué [params] no se puede guardar, o `null` si se puede.
  static Failure? validar(EnviarPedidoParams params) {
    if (params.pedidoId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return const FailurePedidoInvalido();
    }
    final armadas = params.cantidades.entries.where((e) => e.value != 0).toList();
    if (armadas.isEmpty) return const FailurePedidoInvalido();
    final conocidos = {for (final p in params.productos) p.id};
    for (final e in armadas) {
      final idLinea = params.idsDeLineas[e.key];
      if (!conocidos.contains(e.key) ||
          e.value < 1 ||
          e.value > maximoPorLinea ||
          idLinea == null ||
          idLinea.trim().isEmpty) {
        return const FailurePedidoInvalido();
      }
    }
    return null;
  }

  @override
  Future<Either<Failure, PedidoEnviado>> call(EnviarPedidoParams params) async {
    final falla = validar(params);
    if (falla != null) return Left(falla);
    final ahora = _ahora().toUtc();
    final colportor = params.colportorId.trim();
    final lineas = <LineaDelPedido>[
      for (final p in params.productos)
        if ((params.cantidades[p.id] ?? 0) > 0)
          LineaDelPedido(
            id: params.idsDeLineas[p.id]!.trim(),
            productoId: p.id,
            cantidad: params.cantidades[p.id]!,
            precioUnitarioCentavos: p.precioDeCompraCentavos,
          ),
    ];
    return _repository.enviar(
      Pedido(
        id: params.pedidoId.trim(),
        colportorId: colportor,
        estado: EstadoDelPedido.porAutorizar,
        lineas: lineas,
        fecha: ahora,
        montoCentavos: CalculadorDelPedido.montoDe(params.cantidades, params.productos),
        excedeLimite: params.excedeLimite,
        auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportor),
      ),
    );
  }
}
