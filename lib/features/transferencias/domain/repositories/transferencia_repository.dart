import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/transferencia.dart';

/// Las transferencias de materiales del colportor (HU-STK-005): las que pidió, las que le piden y las
/// que armó su coordinadora, todas con su estado. Funciona sin conexión: se pide y se cancela en el
/// teléfono y sube después.
abstract interface class TransferenciaRepository {
  /// Guarda la transferencia **por autorizar** y la encola para subir, todo o nada. Con el mismo id es
  /// idempotente: un segundo toque o un reintento no escribe nada y responde lo mismo
  /// ([TransferenciaPedida.yaEstaba]).
  Future<Either<Failure, TransferenciaPedida>> pedir(Transferencia transferencia);

  /// Pasa a «Cancelada» la transferencia [id] que [colportorId] pidió y sigue por autorizar, y encola el
  /// cambio. Todo o nada. Idempotente: una ya cancelada responde bien sin escribir nada.
  /// [FailureTransferenciaNoCancelable] si no es suya, ya la decidió la coordinadora o no existe.
  Future<Either<Failure, Transferencia>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  });

  /// Todas las transferencias vivas de [colportorId] (las dos puntas), la más nueva primero, cada vez
  /// que cambian.
  Stream<List<Transferencia>> observar(String colportorId);
}
