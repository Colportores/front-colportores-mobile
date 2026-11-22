import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../entities/deposito.dart';
import '../repositories/deposito_repository.dart';

/// Parámetros de [RegistrarDepositoUseCase].
final class RegistrarDepositoParams extends Equatable {
  const RegistrarDepositoParams({
    required this.depositoId,
    required this.colportorId,
    required this.montoCentavos,
    required this.destino,
    required this.concepto,
    this.fecha,
    this.campaniaId,
    this.ticketId,
  });

  /// El id del depósito: lo genera quien abre la pantalla y se repite en los reintentos, así un doble
  /// toque o un reintento tras una falla no registra dos depósitos.
  final String depositoId;

  /// Quién deposita: el `created_by` de la fila.
  final String colportorId;

  final int montoCentavos;
  final DestinoDeDeposito destino;
  final ConceptoDeDeposito concepto;

  /// Cuándo depositó; `null` = ahora.
  final DateTime? fecha;

  /// La campaña a la que paga; obligatoria con [ConceptoDeDeposito.alquiler].
  final String? campaniaId;

  /// El ticket del banco; obligatorio con banco u oficina, ausente en un retiro por el coordinador.
  final String? ticketId;

  @override
  List<Object?> get props => [
    depositoId,
    colportorId,
    montoCentavos,
    destino,
    concepto,
    fecha,
    campaniaId,
    ticketId,
  ];
}

/// HU-CTA-004: registra que el colportor depositó efectivo (en el banco, en la oficina o
/// entregándoselo al coordinador) y para qué era.
///
/// 1. Valida lo que cargó y **no guarda nada** si algo está mal, con las mismas reglas con las que el
///    servidor rechazaría la fila (`23514`): un monto mayor que cero que entre en el entero de la
///    app, una fecha que no sea de mañana (día de Montevideo), el ticket que corresponde al destino
///    (banco y oficina lo llevan, el retiro por el coordinador no) y la campaña cuando el concepto
///    es el alquiler.
/// 2. Lo guarda por [DepositoRepository.registrar], que escribe todo o nada y encola el sync.
///
/// Con el mismo `depositoId` es idempotente. El depósito nace **«por validar»**: no suma a
/// «Depositado» ni baja la deuda hasta que lo valida el coordinador (decisión «Acredita V1»). No
/// marca qué cobros incluye (decisión «Cobro en dep.»).
final class RegistrarDepositoUseCase
    implements UseCase<DepositoRegistrado, RegistrarDepositoParams> {
  RegistrarDepositoUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final DepositoRepository _repository;
  final DateTime Function() _ahora;

  /// Lo más que cabe en el entero que usa la app para el dinero (el mismo tope del cobro), en
  /// centavos.
  static const maximoCentavos = 2147483647;

  /// El texto sin espacios de más; `null` si no queda nada.
  static String? _limpio(String? texto) {
    final limpio = texto?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  /// Por qué [params] no se puede guardar, con las mismas reglas con las que el servidor rechazaría la
  /// fila (`23514`), o `null` si se puede. [ahora] es el «hoy» contra el que se mide la fecha. La usa
  /// también el registro con el ticket del banco (`RegistrarDepositoConTicketUseCase`) para no escribir
  /// el ticket de un depósito que no va a entrar.
  static Failure? validar(RegistrarDepositoParams params, DateTime ahora) {
    if (params.depositoId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return const FailureDepositoNoGuardado(causa: 'faltan_ids');
    }
    if (params.montoCentavos <= 0 || params.montoCentavos > maximoCentavos) {
      return const FailureDepositoMontoInvalido();
    }
    final hoy = ahora.toUtc();
    final fecha = (params.fecha ?? hoy).toUtc();
    // «Después de hoy» se mide en días de Montevideo: depositar hoy a la noche no es del futuro.
    if (ReglasDeVenta.diaDeMontevideo(fecha).isAfter(ReglasDeVenta.diaDeMontevideo(hoy))) {
      return const FailureDepositoFechaInvalida();
    }
    final ticketId = _limpio(params.ticketId);
    if (params.destino.llevaTicket && ticketId == null) return const FailureDepositoSinTicket();
    if (!params.destino.llevaTicket && ticketId != null) {
      return const FailureDepositoRetiroConTicket();
    }
    if (params.concepto == ConceptoDeDeposito.alquiler && _limpio(params.campaniaId) == null) {
      return const FailureDepositoSinCampania();
    }
    return null;
  }

  @override
  Future<Either<Failure, DepositoRegistrado>> call(RegistrarDepositoParams params) async {
    final ahora = _ahora().toUtc();
    final falla = validar(params, ahora);
    if (falla != null) return Left(falla);
    final fecha = (params.fecha ?? ahora).toUtc();
    final ticketId = _limpio(params.ticketId);
    final campaniaId = _limpio(params.campaniaId);

    return _repository.registrar(
      Deposito(
        id: params.depositoId.trim(),
        montoCentavos: params.montoCentavos,
        fecha: fecha,
        destino: params.destino,
        concepto: params.concepto,
        campaniaId: campaniaId,
        ticketId: ticketId,
        auditoria: Auditoria(
          createdAt: ahora,
          updatedAt: ahora,
          createdBy: params.colportorId.trim(),
        ),
      ),
    );
  }
}
