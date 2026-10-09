import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/espacio.dart';
import '../entities/espacios_activos.dart';
import '../entities/marcador_mapa.dart';
import '../entities/resultado_alta_ubicacion.dart';
import '../entities/resultado_modificacion_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../entities/ubicacion_con_resumen.dart';
import '../services/criterio_duplicado_ubicacion.dart';
import '../value_objects/area_mapa.dart';
import '../value_objects/punto_capturado.dart';

/// La ubicación como quedó después de [UbicacionRepository.cambiarBaja], y si se escribió: `false`
/// cuando ya estaba como se pedía (dos toques que se pisaron).
typedef CambioDeBaja = ({Ubicacion ubicacion, bool escribio});

/// Persistencia de las ubicaciones y sus espacios (ADR-001).
abstract interface class UbicacionRepository {
  /// Guarda [ubicacion] y, si viene, su [espacio] default, en **una sola transacción** que también
  /// encola el sync de las dos filas (contrato-sync-engine §3).
  ///
  /// - Si ya existe una ubicación con el mismo `id`, no escribe nada y devuelve
  ///   [AltaRegistrada] con la que estaba (alta idempotente ante doble toque, HU-UBI-001).
  /// - Si llega [duplicados], busca candidatas con ese criterio **dentro de la misma
  ///   transacción** (HU-UBI-001) y, si hay, no escribe nada y devuelve [AltaConDuplicados].
  ///   "Crear igual" (el colportor ya vio las candidatas y eligió seguir) llega como
  ///   `CriterioDuplicadoUbicacion.alSeguirIgual`: `null`, o un criterio que solo frena las
  ///   candidatas que no admiten conservar las dos.
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

  /// Los espacios sin baja de [ubicacionId] —cuántos son y, si es uno solo, su `numero_depto`—,
  /// como stream: emite la cuenta de ahora al suscribirse y de nuevo cada vez que cambia (un espacio
  /// que llega del sync, que se da de baja o al que se le cambia el número), sin repetir un valor
  /// igual al anterior. Es lo que la hoja de edición mira mientras está abierta para avisar antes
  /// de guardar que el cambio de tipo está bloqueado (dos o más) o que le quita el número al único
  /// depto (S17); el que decide al guardar es [modificar].
  ///
  /// Si la lectura falla, el stream emite el error.
  Stream<EspaciosActivos> observarEspaciosActivos(String ubicacionId);

  /// Guarda [nueva] —la ubicación ya modificada: mismo `id`, `updated_at` nuevo— y encola el
  /// `update` para el sync, en **una sola transacción** (HU-UBI-004; contrato-sync-engine §3).
  ///
  /// - [baseUpdatedAt] es el `updated_at` de la ubicación tal como la leyó quien la editó. Si la
  ///   fila ya cambió (otra edición, o el sync entrante), no escribe nada y devuelve
  ///   [FailureUbicacionCambio]. Si la fila no existe, [FailureUbicacionInexistente].
  /// - Si llega [duplicados], busca candidatas con ese criterio **dentro de la misma
  ///   transacción** y, si hay, no escribe nada y devuelve [ModificacionConDuplicados]. "Seguir
  ///   igual" (el colportor ya las vio) llega como `CriterioDuplicadoUbicacion.alSeguirIgual`.
  ///
  /// `sync_version` de [nueva] tiene que ser la que la fila ya tiene: es la versión base del
  /// compare-and-swap del servidor, que es quien la incrementa (backend-supabase 0002).
  ///
  /// [reduceAUnEspacio] es `true` cuando la edición deja a la ubicación con un solo espacio: de
  /// `EDIFICIO` a `CASA` o `NEGOCIO`, o de `NEGOCIO` a `CASA` (S17). Dentro de la misma transacción se cuentan los espacios activos: con dos o más
  /// no escribe nada y devuelve [FailureUbicacionConEspacios]; con exactamente uno, ese depto pasa a
  /// ser el espacio de la casa y se le quita el `numero_depto` (decisión de Cristian, 07/10), y el
  /// `update` del espacio se encola junto al de la ubicación. Contar acá y no antes evita que un
  /// espacio que aparece entre la lectura y la escritura quede con número en una casa.
  Future<Either<Failure, ResultadoModificacionUbicacion>> modificar(
    Ubicacion nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
    bool reduceAUnEspacio = false,
  });

  /// Da de baja ([baja] `true`, `deleted_at` = [ahora]) o reactiva ([baja] `false`) la ubicación
  /// [id] y encola el tombstone (`delete`) o el `update`, en **una sola transacción**
  /// (HU-UBI-005). Devuelve la ubicación como quedó y si se escribió ([CambioDeBaja]): si ya
  /// estaba como se pide, no escribe, no encola ni deja el evento de auditoría. Los espacios y las
  /// personas no se tocan.
  ///
  /// [baseUpdatedAt] es el `updated_at` con el que quien la pidió cargó la ubicación: si la fila
  /// cambió, no escribe y devuelve [FailureUbicacionCambio]. Sin fila, [FailureUbicacionInexistente].
  /// Con [conservadaId], esa otra ubicación tiene que seguir activa en la misma transacción (la que
  /// se conserva al marcar un duplicado): si no está, [FailureUbicacionInexistente]; si está de
  /// baja, [FailureUbicacionCambio]; en los dos casos no escribe.
  /// [conMotivo] solo va al log (`ubicacion_baja`, R-UB09): el motivo es texto libre y no se
  /// registra.
  Future<Either<Failure, CambioDeBaja>> cambiarBaja(
    String id, {
    required bool baja,
    required DateTime baseUpdatedAt,
    required DateTime ahora,
    bool conMotivo = false,
    String? conservadaId,
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

  /// Las ubicaciones del colportor [colportorId] (`created_by`) con su número de espacios sin baja y
  /// su estado de casa, para la lista (HU-UBI-002): lo mismo que [observarDelColportor] más lo que
  /// la fila muestra al lado de la dirección, en una sola lectura (no hay que combinar streams).
  /// Reactivo: emite de nuevo ante cualquier cambio de ubicaciones o espacios. Trae las de baja solo
  /// si [incluirBajas].
  ///
  /// `UbicacionConResumen.estado` es siempre `null` hasta que exista la cache local de
  /// `house_status` (HU-VIS-005, #151).
  ///
  /// Si la lectura falla, el stream termina con el error.
  Stream<List<UbicacionConResumen>> observarListaDelColportor({
    required String colportorId,
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
