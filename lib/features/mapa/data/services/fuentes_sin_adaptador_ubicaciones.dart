import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../auth/domain/entities/campania_colportor.dart';
import '../../domain/entities/pendientes_ubicacion.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/consultor_pendientes_ubicacion.dart';
import '../../domain/services/inscripciones_colportor.dart';
import '../../domain/value_objects/coordenadas.dart';

// Puertos del alta de ubicación (HU-UBI-001) cuya fuente real todavía no existe. **Ninguno es la
// regla de la HU**: se reemplazan cuando llegue lo que les falta.

/// Sin réplica local de las ciudades de la campaña (`ciudad` y `campania_colportor` llegan con el
/// pull de catálogos, #180 y #181; el adaptador real es front-colportores-mobile#274): no hay ciudad
/// que proponer ni lista que mostrar.
///
/// **No sabe, así que no afirma que la campaña no tiene ciudades**: devuelve la **falla de lectura**
/// ([FailureCiudadesNoDisponibles], «No pudimos leer las ciudades de tu campaña. Probá de nuevo.»,
/// con «Reintentar»). «Tu campaña todavía no tiene ciudades. Avisale a tu coordinador.»
/// ([CampaniaSinCiudades]) queda para una campaña que de verdad no las tiene (decisión del
/// orquestador, 02/10, en #267). Hasta que exista el adaptador toda alta cae en la falla de lectura:
/// la app no sale a producción con esta clase.
final class CiudadesParaAltaSinFuente implements CiudadesParaAlta {
  CiudadesParaAltaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  Left<Failure, T> _sinFuente<T>() {
    _log.warn(
      LogModulo.map,
      'CIUDADES_SIN_FUENTE',
      'no hay ciudades de la campaña en el teléfono (falta la réplica local del catálogo)',
    );
    return Left(const FailureCiudadesNoDisponibles());
  }

  @override
  Future<Either<Failure, PropuestaCiudad>> proponer({
    required String colportorId,
    Coordenadas? punto,
  }) async => _sinFuente();

  @override
  Future<Either<Failure, List<CiudadCatalogo>>> deMiCampania(String colportorId) async =>
      _sinFuente();
}

/// Sin inscripciones del colportor en el teléfono (coord#20): el alta se hace igual y queda sin zona
/// local. No pierde nada: el servidor vuelve a calcular la zona al recibir el alta y esa gana
/// (backend-supabase 0010).
final class InscripcionesColportorSinFuente implements InscripcionesColportor {
  InscripcionesColportorSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Either<Failure, List<CampaniaColportor>>> vigentesDe(String usuarioId) async {
    _log.warn(
      LogModulo.map,
      'INSCRIPCIONES_SIN_FUENTE',
      'no hay inscripciones en el teléfono: la zona la calcula el servidor',
    );
    return const Right([]);
  }
}

/// Sin visitas, ventas ni cobranzas en el teléfono (llegan con las HU de visitas y cobranzas y su
/// réplica; el adaptador real es front-colportores-mobile#330): **no sabe, así que no afirma que la
/// ubicación no tiene nada**. Devuelve la falla de revisión ([FailurePendientesNoDisponibles], «No
/// pudimos revisar la ubicación. Probá de nuevo.», con «Reintentar») y deja un `warn`
/// `PENDIENTES_SIN_FUENTE`: ante la duda se bloquea (decisión del agente de decisiones, 09/10, #205;
/// mismo criterio que `CiudadesParaAltaSinFuente`). Hasta que exista el adaptador, «Dar de baja»
/// no pasa de la revisión: la app no sale a producción con esta clase.
///
/// **No es la regla de la HU.** El servidor es quien hace valer el bloqueo (casa con ventas o con una
/// visita de otro colportor, decisión de Cristian del 02/10).
final class PendientesUbicacionSinFuente implements ConsultorPendientesUbicacion {
  PendientesUbicacionSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async {
    _log.warn(
      LogModulo.map,
      'PENDIENTES_SIN_FUENTE',
      'no hay visitas, ventas ni cobranzas en el teléfono: no se puede revisar la ubicación',
      {'ubicacion_id': ubicacionId},
    );
    return const Left(FailurePendientesNoDisponibles());
  }
}

/// Sin motor de sync en la app (#178): encolar falla a propósito. Un alta que no se puede encolar
/// no se guarda (la transacción se revierte) en vez de quedar en el teléfono sin subir nunca.
final class EncoladorSyncSinMotor implements EncoladorSync {
  const EncoladorSyncSinMotor();

  @override
  Future<void> encolar(
    String entidad,
    OperacionSync operacion,
    Map<String, Object?> payload,
  ) async {
    throw StateError('El motor de sync todavía no está en la app (#178)');
  }
}
