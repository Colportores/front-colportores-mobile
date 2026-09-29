import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/espacio.dart';
import '../entities/resultado_alta_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../services/criterio_duplicado_ubicacion.dart';
import '../value_objects/punto_capturado.dart';

/// Persistencia de las ubicaciones y sus espacios (ADR-001).
abstract interface class UbicacionRepository {
  /// Guarda [ubicacion] y, si viene, su [espacio] default, en **una sola transacción** que también
  /// encola el sync de las dos filas (contrato-sync-engine §3).
  ///
  /// - Si ya existe una ubicación con el mismo `id`, no escribe nada y devuelve
  ///   [AltaRegistrada] con la que estaba (alta idempotente ante doble toque, HU-UBI-001).
  /// - Si llega [duplicados], busca candidatas con ese criterio **dentro de la misma
  ///   transacción** (HU-UBI-001) y, si hay, no escribe nada y devuelve [AltaConDuplicados].
  ///   `null` es "crear igual": el colportor ya vio las candidatas y eligió seguir.
  ///
  /// Nunca devuelve [AltaConBajaPrecision]: eso lo decide el caso de uso antes de escribir.
  ///
  /// [origen] es el `coords_source` de HU-UBI-001 ("para auditoría"). La tabla `ubicacion` no
  /// tiene esa columna —ni local ni en el cloud—, así que hoy queda en el log del alta. Dónde se
  /// guarda está para decidir en #192.
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  });
}
