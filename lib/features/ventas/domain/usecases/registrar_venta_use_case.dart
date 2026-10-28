import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/linea_de_venta.dart';
import '../entities/nueva_venta.dart';
import '../entities/venta.dart';
import '../entities/venta_item.dart';
import '../repositories/venta_repository.dart';
import '../services/reglas_de_venta.dart';

/// Parámetros de [RegistrarVentaUseCase].
final class RegistrarVentaParams extends Equatable {
  const RegistrarVentaParams({required this.venta, this.antesDeGuardar});

  final NuevaVenta venta;

  /// Lo que hay que escribir en la misma transacción antes de la venta (la visita `VENTA` de la
  /// entrevista, R·06). Si falla, la venta tampoco se guarda.
  final AntesDeGuardarLaVenta? antesDeGuardar;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [venta, antesDeGuardar];
}

/// HU-VEN-001: registra una venta con su talonario, sus productos y su monto.
///
/// 1. Valida lo que cargó la colportora y **no guarda nada** si algo está mal: talonario, al menos un
///    ítem (esquema-datos: «una venta debe tener al menos un `venta_item`»), cantidades, componentes
///    de cada combo y un total que entre en el entero del servidor.
/// 2. Arma los ítems con la **foto del precio** al vender y, en un combo, lo que traía una unidad.
/// 3. El monto es el calculado, salvo que la colportora lo haya cambiado a mano: entonces se guarda el
///    suyo, el motivo (obligatorio, de 1 a 500 caracteres) y la diferencia queda en el `audit_log`
///    local (supuesto S38). Un total a mano igual al calculado no es un cambio y no pide motivo.
///    Una venta solo de misioneros vale $ 0 y no admite monto a mano.
/// 4. Lo guarda por [VentaRepository.registrar], que escribe todo o nada, rechaza un talonario ya
///    usado el mismo año y encola el sync sin dato del cliente.
///
/// Con el mismo `ventaId` es idempotente: un doble toque o un reintento no la guarda dos veces.
final class RegistrarVentaUseCase implements UseCase<VentaGuardada, RegistrarVentaParams> {
  RegistrarVentaUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final VentaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Lo más que cabe en el `integer` del servidor (`monto_total`, `subtotal`), en centavos.
  static const maximoCentavos = 2147483647;

  /// Lo más que se puede vender de una sola línea (el servidor admite hasta el entero; esto evita un
  /// total absurdo por un teclazo).
  static const maximoPorLinea = 99999;

  @override
  Future<Either<Failure, VentaGuardada>> call(RegistrarVentaParams params) async {
    final v = params.venta;
    final talonario = ReglasDeVenta.talonario(v.numeroTalonario);
    final calculado = ReglasDeVenta.totalCalculado(v.lineas);
    final cobradoAMano = ReglasDeVenta.soloMisioneros(v.lineas) ? null : v.totalCobradoCentavos;

    final errorDeLasLineas = v.lineas.isEmpty
        ? 'Agregá al menos un producto a la venta'
        : v.lineas.any(_cantidadInvalida)
        ? 'Revisá las cantidades de la venta'
        : v.lineas.any(_precioInvalido)
        ? 'Un precio de la venta no es válido'
        : v.lineas.any(_comboSinComponentes)
        ? 'Un combo no tiene sus productos'
        : null;
    final errorDelTotal = calculado > maximoCentavos
        ? 'El total de la venta es demasiado grande'
        : cobradoAMano != null && (cobradoAMano < 0 || cobradoAMano > maximoCentavos)
        ? 'El monto de la venta no es válido'
        : null;

    final campos = <String, String>{
      if (v.ventaId.trim().isEmpty) 'ids': 'Falta el identificador de la venta',
      if (v.colportorId.trim().isEmpty)
        'colportorId': 'No hay un colportor para registrar la venta',
      if (v.espacioPersonaId.trim().isEmpty) 'persona': 'Falta la persona a la que se le vendió',
      if (talonario.isEmpty)
        'talonario': 'Escribí el número del talonario'
      else if (talonario.runes.length > ReglasDeVenta.largoMaximoTalonario)
        'talonario': 'El número del talonario es muy largo',
      'lineas': ?errorDeLasLineas,
      'total': ?errorDelTotal,
      if (errorDelTotal == null &&
          ReglasDeVenta.faltaElMotivo(
            calculado: calculado,
            cobrado: cobradoAMano,
            motivo: v.motivoMontoManual,
          ))
        'motivo': 'Escribí por qué cambiaste el monto',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final ahora = _ahora();
    Auditoria auditoria() =>
        Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: v.colportorId.trim());

    final cobrado = cobradoAMano;
    final aMano = cobrado != null && cobrado != calculado;
    final ventaId = v.ventaId.trim();
    final visitaId = v.visitaId?.trim();

    final venta = Venta(
      id: ventaId,
      espacioPersonaId: v.espacioPersonaId.trim(),
      numeroTalonario: talonario,
      montoTotalCentavos: aMano ? cobrado : calculado,
      fecha: ahora,
      colportorId: v.colportorId.trim(),
      visitaId: visitaId == null || visitaId.isEmpty ? null : visitaId,
      motivoMontoManual: aMano ? ReglasDeVenta.motivo(v.motivoMontoManual) : null,
      auditoria: auditoria(),
    );
    final items = [
      for (final linea in v.lineas)
        switch (linea) {
          LineaDeProducto() => VentaItem(
            id: _generarId(),
            ventaId: ventaId,
            productoId: linea.productoId,
            cantidad: linea.cantidad,
            precioUnitarioCentavos: linea.precioUnitarioGuardado,
            subtotalCentavos: linea.subtotalCentavos,
            auditoria: auditoria(),
          ),
          LineaDeCombo() => VentaItem(
            id: _generarId(),
            ventaId: ventaId,
            productoId: null,
            coleccionId: linea.comboId,
            componentes: linea.componentes,
            cantidad: linea.cantidad,
            precioUnitarioCentavos: linea.precioUnitarioGuardado,
            subtotalCentavos: linea.subtotalCentavos,
            auditoria: auditoria(),
          ),
        },
    ];

    return _repository.registrar(
      venta,
      items,
      diferenciaCentavos: aMano ? cobrado - calculado : null,
      antesDeGuardar: params.antesDeGuardar,
    );
  }

  static bool _cantidadInvalida(LineaDeVenta l) =>
      l.cantidad < 1 ||
      l.cantidad > maximoPorLinea ||
      (l is LineaDeCombo &&
          l.componentes.any((c) => c.cantidad < 1 || c.cantidad > maximoPorLinea));

  static bool _precioInvalido(LineaDeVenta l) =>
      l.precioCentavos < 0 || l.precioCentavos > maximoCentavos;

  static bool _comboSinComponentes(LineaDeVenta l) =>
      l is LineaDeCombo &&
      (l.componentes.isEmpty || l.componentes.any((c) => c.productoId.trim().isEmpty));
}
