import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/espacio.dart';
import '../entities/marcador_mapa.dart';
import '../entities/resultado_alta_ubicacion.dart';
import '../entities/resultado_modificacion_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../services/criterio_duplicado_ubicacion.dart';
import '../value_objects/area_mapa.dart';
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

  /// La ubicación [id], **con baja o sin ella**, o `null` si no está en el teléfono.
  Future<Either<Failure, Ubicacion?>> obtener(String id);

  /// Cuántos espacios sin baja tiene la ubicación [ubicacionId] (para bloquear el cambio de tipo,
  /// HU-UBI-004).
  Future<Either<Failure, int>> contarEspaciosActivos(String ubicacionId);

  /// Guarda [nueva] —la ubicación ya modificada: mismo `id`, `updated_at` nuevo— y encola el
  /// `update` para el sync, en **una sola transacción** (HU-UBI-004; contrato-sync-engine §3).
  ///
  /// - [baseUpdatedAt] es el `updated_at` de la ubicación tal como la leyó quien la editó. Si la
  ///   fila ya cambió (otra edición, o el sync entrante), no escribe nada y devuelve
  ///   [FailureUbicacionCambio]. Si la fila no existe, [FailureUbicacionInexistente].
  /// - Si llega [duplicados], busca candidatas con ese criterio **dentro de la misma
  ///   transacción** y, si hay, no escribe nada y devuelve [ModificacionConDuplicados]. `null` es
  ///   "seguir igual": el colportor ya las vio.
  ///
  /// `sync_version` de [nueva] tiene que ser la que la fila ya tiene: es la versión base del
  /// compare-and-swap del servidor, que es quien la incrementa (backend-supabase 0002).
  Future<Either<Failure, ResultadoModificacionUbicacion>> modificar(
    Ubicacion nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
  });

  /// Da de baja ([baja] `true`, `deleted_at` = [ahora]) o reactiva ([baja] `false`) la ubicación
  /// [id] y encola el tombstone (`delete`) o el `update`, en **una sola transacción**
  /// (HU-UBI-005). Devuelve la ubicación como quedó. Los espacios y las personas no se tocan.
  ///
  /// [baseUpdatedAt] es el `updated_at` con el que quien la pidió cargó la ubicación: si la fila
  /// cambió, no escribe y devuelve [FailureUbicacionCambio]. Sin fila, [FailureUbicacionInexistente].
  /// [conMotivo] solo va al log (`ubicacion_baja`, R-UB09): el motivo es texto libre y no se
  /// registra.
  Future<Either<Failure, Ubicacion>> cambiarBaja(
    String id, {
    required bool baja,
    required DateTime baseUpdatedAt,
    required DateTime ahora,
    bool conMotivo = false,
  });

  /// Las ubicaciones del colportor [colportorId] (`created_by`), como stream: emite de nuevo ante
  /// cualquier alta, baja o edición (HU-UBI-002, §8.8). Trae las de baja solo si [incluirBajas].
  /// Los demás filtros y el orden los aplica `ArmadorListaUbicaciones`.
  ///
  /// Si la lectura falla, el stream termina con el error (el caso de uso lo pasa tal cual).
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  });

  /// Los marcadores del mapa: ubicaciones **activas** (sin baja) del colportor [colportorId]
  /// (`created_by`) dentro de [area], con su número de espacios sin baja (HU-UBI-003). Reactivo:
  /// emite de nuevo ante cualquier cambio de ubicaciones o espacios. Un área no válida da lista
  /// vacía. Sin `house_status`: ver [MarcadorMapa].
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  });
}
