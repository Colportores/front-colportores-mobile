import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../agenda/domain/services/recordatorios.dart';
import '../entities/componente_vendido.dart';
import '../entities/entrega.dart';
import '../repositories/entrega_repository.dart';

/// Parámetros de [EntregarAhoraUseCase].
final class EntregarAhoraParams extends Equatable {
  const EntregarAhoraParams({
    required this.ventaId,
    required this.colportorId,
    this.aEntregar,
    this.quedanPendientes = const [],
    this.soloDesde,
  });

  final String ventaId;

  /// Quién entrega: el `created_by` de las filas.
  final String colportorId;

  /// Lo que se entrega ahora (lo que la colportora dejó tildado en «Entregar ahora», 27B·01). Con
  /// `null` se entrega todo lo que falta de la venta; si viene, no puede estar vacío.
  final List<ComponenteVendido>? aEntregar;

  /// Lo que destildó: queda pendiente para otro día. Solo cuenta con [aEntregar].
  final List<ComponenteVendido> quedanPendientes;

  /// Solo cuenta lo que se sumó a una venta abierta desde este instante (42B·09D, «Venta crece»): lo
  /// de antes no se toca. Solo con [aEntregar].
  final DateTime? soloDesde;

  @override
  List<Object?> get props => [ventaId, colportorId, aEntregar, quedanPendientes, soloDesde];
}

/// HU-VEN-002: «Entregar ahora». Marca como entregado todo lo vendido en la venta —una fila por
/// producto, un combo en una fila por componente— y deja la casa del color que corresponde, todo en
/// una sola transacción.
///
/// 1. No guarda nada si faltan los ids.
/// 2. Pone la hora de ahora como fecha de la entrega.
/// 3. Lo guarda por [EntregaRepository.entregarAhora], que es idempotente: un doble toque o un
///    reintento tras una falla no entrega dos veces.
///
/// Con [EntregarAhoraParams.aEntregar] (la pantalla 27B·01) entrega solo lo tildado y deja pendiente
/// lo destildado, validando y armando **una fila por producto**: las entregadas llevan la hora de
/// ahora y `pendiente = false`; las pendientes, sin fecha y `pendiente = true`. Las guarda por
/// [EntregaRepository.registrarEntrega], idempotente por venta.
///
/// Si la venta tenía entregas **pendientes** (HU-VEN-003), «Entregar ahora» las cumple en vez de
/// duplicarlas ([EntregaRepository.entregarAhora]); la cita de esa entrega queda cumplida y, con
/// [Recordatorios], se le saca el aviso **después** de guardar (nunca hace fallar la entrega).
///
/// En V1 no hay stock: la app confía en lo que lleva la colportora (decisión del 23/10, el stock es
/// V2, HU-STK-007).
final class EntregarAhoraUseCase implements UseCase<EntregaRegistrada, EntregarAhoraParams> {
  EntregarAhoraUseCase(
    this._repository, {
    required this._generarId,
    DateTime Function()? ahora,
    this._recordatorios,
  }) : _ahora = ahora ?? DateTime.now;

  final EntregaRepository _repository;
  final Recordatorios? _recordatorios;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Lo más que se puede entregar de un producto (igual que lo más que se vende de una línea).
  static const maximoPorProducto = 99999;

  @override
  Future<Either<Failure, EntregaRegistrada>> call(EntregarAhoraParams params) async {
    if (params.ventaId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return const Left(FailureEntregaNoGuardada(causa: 'faltan_ids'));
    }
    if (params.aEntregar != null) return _loTildado(params, params.aEntregar!);
    final entregada = await _repository.entregarAhora(
      params.ventaId.trim(),
      colportorId: params.colportorId.trim(),
      ahora: _ahora().toUtc(),
      generarId: _generarId,
    );
    final cita = entregada.fold<String?>((_) => null, (r) => r.citaCumplidaId);
    if (cita != null) await _sacarRecordatorio(cita);
    return entregada;
  }

  /// La entrega ya está guardada: una falla del plugin de avisos no la deshace.
  Future<void> _sacarRecordatorio(String agendaId) async {
    try {
      await _recordatorios?.cancelar(agendaId);
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREGA_RECORDATORIO',
        'no se pudo sacar el recordatorio de la entrega cumplida',
        {'agenda_id': agendaId, 'error': e.runtimeType.toString()},
      );
    }
  }

  Future<Either<Failure, EntregaRegistrada>> _loTildado(
    EntregarAhoraParams params,
    List<ComponenteVendido> aEntregar,
  ) {
    final entregar = _sumar(aEntregar);
    final pendientes = _sumar(params.quedanPendientes);
    if (entregar.isEmpty) {
      return Future.value(
        const Left(
          FailureValidacion(campos: {'productos': 'Elegí al menos un producto para entregar.'}),
        ),
      );
    }
    final cantidades = [...entregar.values, ...pendientes.values];
    if (cantidades.any((c) => c < 1 || c > maximoPorProducto)) {
      return Future.value(
        const Left(
          FailureValidacion(campos: {'productos': 'La cantidad de un producto no es válida.'}),
        ),
      );
    }

    final ventaId = params.ventaId.trim();
    final colportorId = params.colportorId.trim();
    final ahora = _ahora().toUtc();
    Auditoria auditoria() => Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId);
    final filas = [
      for (final MapEntry(:key, :value) in entregar.entries)
        Entrega(
          id: _generarId(),
          ventaId: ventaId,
          productoId: key,
          cantidad: value,
          pendiente: false,
          fechaEntrega: ahora,
          auditoria: auditoria(),
        ),
      for (final MapEntry(:key, :value) in pendientes.entries)
        Entrega(
          id: _generarId(),
          ventaId: ventaId,
          productoId: key,
          cantidad: value,
          pendiente: true,
          auditoria: auditoria(),
        ),
    ];
    return _repository.registrarEntrega(ventaId, filas, soloDesde: params.soloDesde);
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
