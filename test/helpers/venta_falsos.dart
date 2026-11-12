// Semillas y dobles de las ventas (HU-VEN-001, #423) para los tests contra la DB real en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_que_crece_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_repository.dart';
import 'package:dartz/dartz.dart';

import 'campo_falsos.dart';

/// Una venta de `ep-1` (la persona de la casa sembrada) por $ 1.500 con el talonario [talonario].
Venta ventaDe(
  String id, {
  String talonario = 'T-100',
  int monto = 150000,
  DateTime? fecha,
  String colportor = 'col-1',
  String? visitaId,
  String? motivo,
  String vinculo = 'ep-1',
}) => Venta(
  id: id,
  espacioPersonaId: vinculo,
  numeroTalonario: talonario,
  montoTotalCentavos: monto,
  fecha: fecha ?? t0,
  colportorId: colportor,
  visitaId: visitaId,
  motivoMontoManual: motivo,
  auditoria: Auditoria(createdAt: fecha ?? t0, updatedAt: fecha ?? t0, createdBy: colportor),
);

/// Tres libros a $ 500 de la venta [ventaId].
VentaItem itemDe(
  String id,
  String ventaId, {
  String? productoId = 'prod-1',
  String? coleccionId,
  List<ComponenteVendido>? componentes,
  int cantidad = 3,
  int precio = 50000,
}) => VentaItem(
  id: id,
  ventaId: ventaId,
  productoId: productoId,
  coleccionId: coleccionId,
  componentes: componentes,
  cantidad: cantidad,
  precioUnitarioCentavos: precio,
  subtotalCentavos: cantidad * precio,
  auditoria: auditoriaDe(),
);

/// [VentaRepository] en memoria: guarda lo que le llega, o responde con [respuesta].
class VentasEnMemoria implements VentaRepository {
  VentasEnMemoria({this.respuesta});

  /// Si no es `null`, es lo que devuelve [registrar] (en vez de guardar).
  Failure? respuesta;

  /// Lo que llegó a [registrar], en orden.
  final recibidas = <({Venta venta, List<VentaItem> items, int? diferencia})>[];

  /// Si es `true`, [registrar] se queda esperando [salida].
  Future<void>? compuerta;

  VentaDelTalonario? talonario;

  @override
  Future<Either<Failure, VentaGuardada>> registrar(
    Venta venta,
    List<VentaItem> items, {
    int? diferenciaCentavos,
    AntesDeGuardarLaVenta? antesDeGuardar,
  }) async {
    recibidas.add((venta: venta, items: items, diferencia: diferenciaCentavos));
    await compuerta;
    final falla = respuesta;
    if (falla != null) return Left(falla);
    await antesDeGuardar?.call();
    return Right(VentaGuardada(venta: venta, items: items));
  }

  @override
  Future<Either<Failure, VentaDelTalonario?>> talonarioUsado({
    required String colportorId,
    required String numero,
    required DateTime fecha,
  }) async => Right(talonario);
}

/// [VentaQueCreceRepository] en memoria («Venta crece», #693): las ventas abiertas que se le dan y lo
/// que llega a [sumar], que responde con la venta con el total nuevo o con [respuesta].
class VentaQueCreceEnMemoria implements VentaQueCreceRepository {
  VentaQueCreceEnMemoria({this.abiertas = const [], this.citas});

  /// Las ventas abiertas que lee cualquier persona.
  List<VentaAbierta> abiertas;

  /// Si no es `null`, lo que devuelve [observarAbiertasDe] es este error.
  Object? errorAlLeer;

  /// Las citas que ya tiene cualquier venta; `null` = ninguna.
  CitasDeLaVenta? citas;

  /// Si no es `null`, lo que devuelve [sumar] (en vez de guardar). Se consume de a una.
  final respuestas = <Failure>[];

  /// Si no es `null`, [sumar] espera a que se complete.
  Completer<void>? compuerta;

  /// Lo que llegó a [sumar], en orden.
  final sumas =
      <({String ventaId, List<VentaItem> items, int sumado, String? motivo, int? diferencia})>[];

  @override
  Stream<List<VentaAbierta>> observarAbiertasDe(String personaId) {
    final error = errorAlLeer;
    if (error != null) return Stream.error(error);
    return Stream.value(abiertas);
  }

  @override
  Future<Either<Failure, CitasDeLaVenta>> citasDe(String ventaId) async =>
      Right(citas ?? (cobranzaAgendada: false));

  @override
  Future<Either<Failure, VentaQueCrecio>> sumar(
    String ventaId,
    List<VentaItem> itemsNuevos, {
    required String numeroTalonario,
    required int sumadoCentavos,
    required DateTime ahora,
    String? motivoMontoManual,
    int? diferenciaCentavos,
  }) async {
    sumas.add((
      ventaId: ventaId,
      items: itemsNuevos,
      sumado: sumadoCentavos,
      motivo: motivoMontoManual,
      diferencia: diferenciaCentavos,
    ));
    await compuerta?.future;
    if (respuestas.isNotEmpty) return Left(respuestas.removeAt(0));
    final abierta = abiertas.where((v) => v.ventaId == ventaId).firstOrNull;
    final anterior = abierta?.montoTotalCentavos ?? 0;
    return Right(
      VentaQueCrecio(
        venta: ventaDe(
          ventaId,
          talonario: numeroTalonario,
          monto: anterior + sumadoCentavos,
          vinculo: abierta?.espacioPersonaId ?? 'ep-1',
        ),
        items: itemsNuevos,
        totalAnteriorCentavos: anterior,
        sumadoEl: ahora,
      ),
    );
  }
}
