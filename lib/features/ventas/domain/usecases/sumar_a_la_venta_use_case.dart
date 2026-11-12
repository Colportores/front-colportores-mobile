import 'package:dartz/dartz.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/linea_de_venta.dart';
import '../entities/nueva_venta.dart';
import '../entities/venta_item.dart';
import '../repositories/venta_que_crece_repository.dart';
import '../services/reglas_de_venta.dart';
import 'registrar_venta_use_case.dart';

/// HU-VEN-001, «Venta crece» (decisión de Cristian del 10/11, con los casos límite del agente de
/// decisiones): suma otro libro a una venta **abierta** de la persona, sin otro talonario.
///
/// 1. Valida lo que se suma y **no guarda nada** si algo está mal: al menos un renglón, cantidades,
///    precios, combos con sus productos y un total que entre en el entero del servidor. Los misioneros
///    no se suman (no son venta: van por «Lo que dejaste»).
/// 2. Cada renglón lleva el precio de la ciudad de la casa **de hoy**; lo vendido antes no se
///    recalcula. El total nuevo es el que tenía la venta más lo sumado.
/// 3. Si la colportora cambió el monto de lo que suma, pide el motivo como en la venta («Monto
///    manual»). Si la venta ya tenía uno, se juntan los dos (decisión de Cristian del 11/11, «Dos
///    motivos»): queda `<viejo> · <nuevo>`, con el mismo tope de [ReglasDeVenta.largoMaximoMotivo]
///    caracteres medido sobre el texto unido. Si no entra, no se corta: se rechaza sin guardar y el
///    aviso dice cuántos caracteres le quedan para lo nuevo ([motivoNoEntra]).
/// 4. Lo guarda por [VentaQueCreceRepository.sumar], que vuelve a mirar en la misma transacción que
///    la venta siga abierta.
///
/// Con el mismo [SumaALaVenta.sumaId] es idempotente: es el id del primer renglón nuevo.
final class SumarALaVentaUseCase implements UseCase<VentaQueCrecio, SumaALaVenta> {
  SumarALaVentaUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final VentaQueCreceRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// El motivo nuevo no entra junto al que la venta ya tenía: le quedan [quedan] caracteres para lo
  /// nuevo. Texto a confirmar (mapa §2: texto).
  static String motivoNoEntra(int quedan) => quedan == 1
      ? 'Con el motivo que ya tiene la venta, para lo nuevo te queda 1 carácter: acortalo.'
      : 'Con el motivo que ya tiene la venta, para lo nuevo te quedan $quedan caracteres: acortalo.';

  @override
  Future<Either<Failure, VentaQueCrecio>> call(SumaALaVenta s) async {
    final calculado = ReglasDeVenta.totalCalculado(s.lineas);
    final cobrado = s.sumadoACobrarCentavos;
    final aMano = cobrado != null && cobrado != calculado;
    final sumado = aMano ? cobrado : calculado;
    const maximo = RegistrarVentaUseCase.maximoCentavos;

    final errorDeLasLineas =
        RegistrarVentaUseCase.problemaDeLasLineas(s.lineas) ??
        (s.lineas.any((l) => l is LineaDeProducto && l.sinCobrar)
            ? 'Los misioneros no se suman a una venta: anotalos en «Lo que dejaste»'
            : null);
    final errorDelTotal = calculado > maximo
        ? 'El total de la venta es demasiado grande'
        : cobrado != null && (cobrado < 0 || cobrado > maximo)
        ? 'El monto de lo que sumás no es válido'
        : s.venta.montoTotalCentavos + sumado > maximo
        ? 'El total de la venta es demasiado grande'
        : null;

    final campos = <String, String>{
      if (s.sumaId.trim().isEmpty) 'ids': 'Falta el identificador de lo que se suma',
      if (s.colportorId.trim().isEmpty) 'colportorId': 'No hay un colportor para sumar a la venta',
      if (s.venta.ventaId.trim().isEmpty) 'venta': 'Falta la venta a la que se suma',
      'lineas': ?errorDeLasLineas,
      'total': ?errorDelTotal,
      if (errorDelTotal == null &&
          ReglasDeVenta.faltaElMotivo(
            calculado: calculado,
            cobrado: cobrado,
            motivo: s.motivoMontoManual,
          ))
        'motivo': 'Escribí por qué cambiaste el monto'
      else if (errorDelTotal == null &&
          aMano &&
          ReglasDeVenta.motivoNoEntra(s.venta.motivoMontoManual, s.motivoMontoManual))
        'motivo': motivoNoEntra(ReglasDeVenta.lugarParaElMotivo(s.venta.motivoMontoManual)),
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final ahora = _ahora().toUtc();
    final colportorId = s.colportorId.trim();
    final ventaId = s.venta.ventaId.trim();
    Auditoria auditoria() => Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId);
    var primero = true;
    String id() {
      if (!primero) return _generarId();
      primero = false;
      return s.sumaId.trim();
    }

    final items = [
      for (final linea in s.lineas)
        switch (linea) {
          LineaDeProducto() => VentaItem(
            id: id(),
            ventaId: ventaId,
            productoId: linea.productoId,
            cantidad: linea.cantidad,
            precioUnitarioCentavos: linea.precioUnitarioGuardado,
            subtotalCentavos: linea.subtotalCentavos,
            auditoria: auditoria(),
          ),
          LineaDeCombo() => VentaItem(
            id: id(),
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

    return _repository.sumar(
      ventaId,
      items,
      numeroTalonario: s.venta.numeroTalonario,
      sumadoCentavos: sumado,
      ahora: ahora,
      motivoMontoManual: aMano
          ? ReglasDeVenta.motivoUnido(s.venta.motivoMontoManual, s.motivoMontoManual)
          : null,
      diferenciaCentavos: aMano ? cobrado - calculado : null,
    );
  }
}
