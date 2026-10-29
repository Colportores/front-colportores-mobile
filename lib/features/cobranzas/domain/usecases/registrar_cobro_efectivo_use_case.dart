import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../entities/cobranza.dart';
import '../entities/venta_con_saldo.dart';
import '../repositories/cobranza_repository.dart';

/// Parámetros de [RegistrarCobroEfectivoUseCase].
final class RegistrarCobroEfectivoParams extends Equatable {
  const RegistrarCobroEfectivoParams({
    required this.cobroId,
    required this.ventaId,
    required this.montoCentavos,
    required this.colportorId,
    this.fecha,
  });

  /// El id del cobro: lo genera quien abre la pantalla y se repite en los reintentos, así un doble
  /// toque o un reintento tras una falla no cobra dos veces.
  final String cobroId;

  final String ventaId;
  final int montoCentavos;
  final String colportorId;

  /// Cuándo pagó el cliente; `null` = ahora (`fecha_pago` por defecto `now()`).
  final DateTime? fecha;

  @override
  List<Object?> get props => [cobroId, ventaId, montoCentavos, colportorId, fecha];
}

/// HU-COB-001: registra un cobro en efectivo de una venta.
///
/// 1. Valida lo que cargó la colportora y **no guarda nada** si algo está mal: un monto mayor que
///    cero que entre en el entero del servidor y una fecha que no sea de mañana.
/// 2. Lo guarda por [CobranzaRepository.registrar], que escribe todo o nada: rechaza un monto mayor
///    al saldo (no hay saldo a favor), baja el saldo de la venta, encola el sync sin dato del cliente
///    y recalcula el color de la casa.
///
/// Con el mismo `cobroId` es idempotente.
final class RegistrarCobroEfectivoUseCase
    implements UseCase<CobroRegistrado, RegistrarCobroEfectivoParams> {
  RegistrarCobroEfectivoUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final CobranzaRepository _repository;
  final DateTime Function() _ahora;

  /// Lo más que cabe en el `integer` del servidor (`cobranza.monto`), en centavos.
  static const maximoCentavos = 2147483647;

  @override
  Future<Either<Failure, CobroRegistrado>> call(RegistrarCobroEfectivoParams params) async {
    if (params.cobroId.trim().isEmpty ||
        params.ventaId.trim().isEmpty ||
        params.colportorId.trim().isEmpty) {
      return const Left(FailureCobroNoGuardado(causa: 'faltan_ids'));
    }
    if (params.montoCentavos <= 0 || params.montoCentavos > maximoCentavos) {
      return const Left(FailureCobroMontoInvalido());
    }
    final ahora = _ahora().toUtc();
    final fecha = (params.fecha ?? ahora).toUtc();
    // «Después de hoy» se mide en días de Montevideo: pagar hoy a la noche no es del futuro.
    if (ReglasDeVenta.diaDeMontevideo(fecha).isAfter(ReglasDeVenta.diaDeMontevideo(ahora))) {
      return const Left(FailureCobroFechaInvalida());
    }
    final cobro = Cobranza(
      id: params.cobroId.trim(),
      ventaId: params.ventaId.trim(),
      montoCentavos: params.montoCentavos,
      medio: MedioCobranza.efectivo,
      fecha: fecha,
      auditoria: Auditoria(
        createdAt: ahora,
        updatedAt: ahora,
        createdBy: params.colportorId.trim(),
      ),
    );
    return _repository.registrar(cobro);
  }
}
