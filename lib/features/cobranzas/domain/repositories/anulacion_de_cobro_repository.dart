import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/cobranza.dart';
import '../entities/detalle_del_cobro.dart';

/// Leer un cobro y anularlo (HU-COB-006, #422). La anulación es **todo o nada**, en una transacción
/// local: marca el cobro, lo encola para el sync, deja el `audit_log` y recalcula el color de la casa.
abstract interface class AnulacionDeCobroRepository {
  /// El cobro [cobranzaId] con su venta y su cliente, o `null` si no está (o está dado de baja).
  Future<Either<Failure, DetalleDelCobro?>> detalle(String cobranzaId);

  /// Anula el cobro [cobranzaId] con la hora [ahora] del teléfono.
  ///
  /// - Si ya está anulado, no escribe nada y devuelve cómo está (idempotente ante un doble toque o un
  ///   reintento), aunque la ventana ya haya pasado.
  /// - Pasadas las 72 h desde el cobro es [FailureAnulacionFueraDePlazo]; un cobro que no está,
  ///   [FailureCobroAusente]; cualquier otra falla, [FailureCobroNoAnulado]. Si falla, el cobro sigue
  ///   como estaba.
  /// - [justificacion] es lo que escribió con «Otro»: se queda en el `audit_log` local, no sube.
  Future<Either<Failure, AnulacionHecha>> anular({
    required String cobranzaId,
    required MotivoDeAnulacion motivo,
    required String colportorId,
    required DateTime ahora,
    String? justificacion,
  });
}
