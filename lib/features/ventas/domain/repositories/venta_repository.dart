import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/nueva_venta.dart';
import '../entities/venta.dart';
import '../entities/venta_item.dart';

/// Lo que hay que hacer en la misma transacción que escribe la venta, **antes** de escribirla: la
/// entrevista que termina en esta venta guarda su visita `VENTA` (el servidor exige que `visita`
/// llegue antes que `venta`). Si lanza, la venta tampoco se guarda (R44: venta sin completar, el
/// resultado no se guarda).
typedef AntesDeGuardarLaVenta = Future<void> Function();

/// Persistencia de las ventas del colportor (BACK-HU-VEN-001, #423).
///
/// Cada operación es **todo o nada**, en una transacción local: la venta, sus ítems, el encolado de
/// todo para el sync (sin dato del cliente), la nota del monto manual en el `audit_log` local y el
/// recálculo del color de la casa (`house_status`, R-UB08).
abstract interface class VentaRepository {
  /// Guarda [venta] con sus [items].
  ///
  /// - Si ya hay una venta con ese `id`, no escribe nada y devuelve la que estaba (idempotente ante un
  ///   doble toque o un reintento).
  /// - Un talonario ya usado por el mismo colportor el mismo año (de Montevideo) es
  ///   [FailureTalonarioRepetido]; el vínculo persona ↔ espacio ausente, un `FailureValidacion` con el
  ///   campo `persona`. Cualquier otra falla es [FailureVentaNoGuardada].
  /// - [diferenciaCentavos] (total cobrado menos total calculado, `null` si no se cambió a mano)
  ///   deja una fila en el `audit_log` local, sin texto de la colportora.
  /// - [antesDeGuardar] corre dentro de la misma transacción antes de escribir la venta.
  Future<Either<Failure, VentaGuardada>> registrar(
    Venta venta,
    List<VentaItem> items, {
    int? diferenciaCentavos,
    AntesDeGuardarLaVenta? antesDeGuardar,
  });

  /// Las ventas vivas del colportor [colportorId] que usan el talonario [numero] el año de Montevideo
  /// de [fecha] (ver [VentaDelTalonario]); `null` si nadie lo usó. Solo lee: es el aviso de 27A·11
  /// mientras escribe, y la guarda de verdad es la de [registrar].
  Future<Either<Failure, VentaDelTalonario?>> talonarioUsado({
    required String colportorId,
    required String numero,
    required DateTime fecha,
  });
}

/// La venta que ya usó un número de talonario.
final class VentaDelTalonario {
  const VentaDelTalonario({required this.ventaId, required this.fecha});

  final String ventaId;
  final DateTime fecha;
}
