import '../entities/venta_con_saldo.dart';

/// Lo que se debe, calculado en el teléfono y al día solo (HU-COB-005).
///
/// `saldo = monto total de la venta − suma de los cobros válidos`, en centavos, nunca negativo: una
/// venta cobrada de más no resta de lo que deben las demás. Los cobros dados de baja no cuentan (y
/// los anulados tampoco, cuando HU-COB-006 los marque). Todo sale de la DB local: funciona sin
/// conexión y nunca lleva el dato de nadie al servidor.
///
/// Cada `Stream` emite el valor de ahora al suscribirse y uno nuevo **solo si cambió**: al registrar,
/// dar de baja o bajar por el pull una venta o un cobro, quien mira se actualiza sin recargar. Si la
/// base no se puede leer, el `Stream` falla con `FailureSaldoNoDisponible` y nunca emite 0: «no pude
/// calcular» no es «no debe nada».
abstract interface class SaldoPendienteRepository {
  /// La venta [ventaId] con lo cobrado y lo que debe, o `null` si no está o se dio de baja.
  Stream<VentaConSaldo?> observarVenta(String ventaId);

  /// Lo que debe la persona [personaId]: la suma de sus ventas vivas.
  Stream<int> observarDePersona(String personaId);

  /// Lo que se debe en la ubicación [ubicacionId]: la suma de las ventas de las personas de todos sus
  /// espacios.
  Stream<int> observarDeUbicacion(String ubicacionId);

  /// Lo que le deben al colportor [colportorId] en total: la suma de todas sus ventas vivas.
  Stream<int> observarTotal(String colportorId);
}
