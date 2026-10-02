import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../auth/domain/entities/campania_colportor.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/inscripciones_colportor.dart';
import '../../domain/value_objects/coordenadas.dart';

// Puertos del alta de ubicación (HU-UBI-001) cuya fuente real todavía no existe. **Ninguno es la
// regla de la HU**: se reemplazan cuando llegue lo que les falta.

/// Sin réplica local de las ciudades de la campaña (el catálogo y las campañas del colportor llegan
/// con el pull del sync, #178): no hay ciudad que proponer ni lista que mostrar. El alta muestra el
/// aviso «Tu campaña todavía no tiene ciudades» y no deja registrar: no se inventa una ciudad.
final class CiudadesParaAltaSinFuente implements CiudadesParaAlta {
  CiudadesParaAltaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  void _avisar() => _log.warn(
    LogModulo.map,
    'CIUDADES_SIN_FUENTE',
    'no hay ciudades de la campaña en el teléfono (falta la réplica local del catálogo)',
  );

  @override
  Future<Either<Failure, PropuestaCiudad>> proponer({
    required String colportorId,
    Coordenadas? punto,
  }) async {
    _avisar();
    return const Right(CampaniaSinCiudades());
  }

  @override
  Future<Either<Failure, List<CiudadCatalogo>>> deMiCampania(String colportorId) async {
    _avisar();
    return const Right([]);
  }
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
