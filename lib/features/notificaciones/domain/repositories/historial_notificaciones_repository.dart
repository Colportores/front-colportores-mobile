import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/notificacion.dart';
import '../entities/tipo_notificacion.dart';

/// Cuánto se guarda un aviso en el historial: 90 días (HU-NOT-005, supuesto S27). Después se purga.
const retencionHistorialNotificaciones = Duration(days: 90);

/// El historial de avisos del teléfono (HU-NOT-005, tabla local `notificacion_historial`).
///
/// **Solo local**: no sube (`SyncSpec.local`) y no se encola nada. Lo que se ve es siempre lo de los
/// últimos [retencionHistorialNotificaciones]; lo más viejo no se lee aunque la purga todavía no lo
/// haya borrado. Nunca devuelve ni registra el texto de un aviso en un `Failure`.
abstract interface class HistorialNotificacionesRepository {
  /// Guarda [notificacion]. `Right(true)` si era nueva y `Right(false)` si ya había un aviso con ese
  /// `id` (no escribe nada: registrar dos veces el mismo aviso deja uno solo). Después purga lo que
  /// pasó de los 90 días.
  Future<Either<Failure, bool>> registrar(Notificacion notificacion, {required DateTime ahora});

  /// Los avisos de los últimos 90 días, el más reciente primero, con el filtro por [tipo] si lo hay.
  /// Emite de nuevo con cada cambio. Si la lectura falla, el flujo termina en error.
  Stream<List<Notificacion>> observar({TipoNotificacion? tipo, required DateTime ahora});

  /// Cuántos avisos de los últimos 90 días siguen sin leer (el número de la campana).
  Stream<int> observarNoLeidas({required DateTime ahora});

  /// Marca [id] como leída en [ahora]. Si ya estaba leída o no existe, no escribe nada.
  Future<Either<Failure, Unit>> marcarLeida(String id, {required DateTime ahora});

  /// Marca como leídas todas las que siguen sin leer.
  Future<Either<Failure, Unit>> marcarTodasLeidas({required DateTime ahora});

  /// Borra el historial. Con [hasta], solo lo recibido hasta ese instante (inclusive): lo que llegó
  /// después, con la confirmación abierta, sobrevive. Sin [hasta], todo. Devuelve cuántos borró.
  Future<Either<Failure, int>> borrarTodas({DateTime? hasta});

  /// Borra lo que pasó de los 90 días contados hasta [ahora]. Devuelve cuántos borró.
  Future<Either<Failure, int>> purgarVencidas({required DateTime ahora});
}
