import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../entities/cobranza.dart';
import '../entities/venta_con_saldo.dart';
import '../repositories/cobranza_repository.dart';

/// Parámetros de [RegistrarCobroUseCase].
final class RegistrarCobroParams extends Equatable {
  const RegistrarCobroParams({
    required this.cobroId,
    required this.ventaId,
    required this.montoCentavos,
    required this.colportorId,
    this.medio = MedioCobranza.efectivo,
    this.fecha,
    this.tarjetaTipo,
    this.tarjetaMarca,
    this.numeroAprobacion,
    this.referenciaTransferencia,
    this.bancoOrigen,
  });

  /// El id del cobro: lo genera quien abre la pantalla y se repite en los reintentos, así un doble
  /// toque o un reintento tras una falla no cobra dos veces.
  final String cobroId;

  final String ventaId;
  final int montoCentavos;
  final String colportorId;

  /// Cómo pagó el cliente. Sin decirlo, en efectivo.
  final MedioCobranza medio;

  /// Cuándo pagó el cliente; `null` = ahora (`fecha_pago` por defecto `now()`).
  final DateTime? fecha;

  /// Solo se guardan con [MedioCobranza.tarjeta]; con otro medio se descartan (HU-COB-002).
  final TipoTarjeta? tarjetaTipo;
  final String? tarjetaMarca;
  final String? numeroAprobacion;

  /// Solo se guardan con [MedioCobranza.transferencia]; con otro medio se descartan (HU-COB-003).
  final String? referenciaTransferencia;
  final String? bancoOrigen;

  @override
  List<Object?> get props => [
    cobroId,
    ventaId,
    montoCentavos,
    colportorId,
    medio,
    fecha,
    tarjetaTipo,
    tarjetaMarca,
    numeroAprobacion,
    referenciaTransferencia,
    bancoOrigen,
  ];
}

/// HU-COB-001, HU-COB-002 y HU-COB-003: registra un cobro de una venta, en efectivo, con tarjeta o
/// por transferencia.
///
/// 1. Valida lo que cargó la colportora y **no guarda nada** si algo está mal: un monto mayor que
///    cero que entre en el entero del servidor, una fecha que no sea de mañana y datos del medio que
///    entren en el largo que acepta el servidor.
/// 2. Arma el cobro con los datos del medio que corresponde: lo de la tarjeta solo con tarjeta y lo
///    de la transferencia solo con transferencia (el servidor rechaza cualquier otra mezcla), con los
///    textos sin espacios de más y los vacíos como «sin dato» (todos son opcionales).
/// 3. Lo guarda por [CobranzaRepository.registrar], que escribe todo o nada: rechaza un monto mayor
///    al saldo (no hay saldo a favor), baja el saldo de la venta, encola el sync sin dato del cliente
///    y recalcula el color de la casa.
///
/// Con el mismo `cobroId` es idempotente.
final class RegistrarCobroUseCase implements UseCase<CobroRegistrado, RegistrarCobroParams> {
  RegistrarCobroUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final CobranzaRepository _repository;
  final DateTime Function() _ahora;

  /// Lo más que cabe en el `integer` del servidor (`cobranza.monto`), en centavos.
  static const maximoCentavos = 2147483647;

  /// Lo más largo que acepta el servidor en cada dato del medio (migración 0072 del backend).
  static const maximoMarca = 40;
  static const maximoAprobacion = 40;
  static const maximoReferencia = 40;
  static const maximoBanco = 60;

  /// El texto sin espacios de más (los de los bordes, y una sola vez los del medio) y sin saltos de
  /// línea; `null` si no queda nada. Es lo que se guarda y lo que sube.
  static String? limpiar(String? texto) {
    if (texto == null) return null;
    final limpio = texto.replaceAll(RegExp(r'[\s\u00A0\u200B]+'), ' ').trim();
    return limpio.isEmpty ? null : limpio;
  }

  @override
  Future<Either<Failure, CobroRegistrado>> call(RegistrarCobroParams params) async {
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

    final conTarjeta = params.medio == MedioCobranza.tarjeta;
    final conTransferencia = params.medio == MedioCobranza.transferencia;
    final marca = conTarjeta ? limpiar(params.tarjetaMarca) : null;
    final aprobacion = conTarjeta ? limpiar(params.numeroAprobacion) : null;
    final referencia = conTransferencia ? limpiar(params.referenciaTransferencia) : null;
    final banco = conTransferencia ? limpiar(params.bancoOrigen) : null;
    if ((marca?.length ?? 0) > maximoMarca ||
        (aprobacion?.length ?? 0) > maximoAprobacion ||
        (referencia?.length ?? 0) > maximoReferencia ||
        (banco?.length ?? 0) > maximoBanco) {
      return const Left(FailureCobroDatoDelMedioInvalido());
    }

    final cobro = Cobranza(
      id: params.cobroId.trim(),
      ventaId: params.ventaId.trim(),
      montoCentavos: params.montoCentavos,
      medio: params.medio,
      fecha: fecha,
      tarjetaTipo: conTarjeta ? params.tarjetaTipo : null,
      tarjetaMarca: marca,
      numeroAprobacion: aprobacion,
      referenciaTransferencia: referencia,
      bancoOrigen: banco,
      auditoria: Auditoria(
        createdAt: ahora,
        updatedAt: ahora,
        createdBy: params.colportorId.trim(),
      ),
    );
    return _repository.registrar(cobro);
  }
}
