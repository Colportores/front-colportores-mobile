import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../auth/domain/entities/campania_colportor.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/inscripciones_colportor.dart';
import '../../domain/services/solicitador_alta_ciudad.dart';
import '../../domain/value_objects/coordenadas.dart';

// Puertos del alta de ubicación (HU-UBI-001) cuya fuente real todavía no existe. **Ninguno es la
// regla de la HU**: se reemplazan cuando llegue lo que les falta.

/// Sin catálogo de ciudades en el teléfono (HU-ADM / BFF, docs-organizacion#22): ninguna ciudad
/// se detecta ni se puede elegir. El alta muestra «ciudad no encontrada» y no deja registrar.
final class CiudadesParaAltaSinFuente implements CiudadesParaAlta {
  CiudadesParaAltaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  void _avisar() => _log.warn(
    LogModulo.map,
    'CIUDADES_SIN_FUENTE',
    'no hay catálogo de ciudades en el teléfono (docs-organizacion#22)',
  );

  @override
  Future<Either<Failure, DeteccionCiudad>> detectar(Coordenadas punto) async {
    _avisar();
    return const Right(CiudadNoEncontrada());
  }

  @override
  Future<Either<Failure, List<CiudadCatalogo>>> todas() async {
    _avisar();
    return const Right([]);
  }

  @override
  Future<Either<Failure, CiudadCatalogo?>> deMiZona(String colportorId) async {
    _avisar();
    return const Right(null);
  }
}

/// Sin dónde mandar el pedido de alta de ciudad: siempre [FailureSolicitudCiudadNoDisponible].
final class SolicitadorAltaCiudadSinFuente implements SolicitadorAltaCiudad {
  const SolicitadorAltaCiudadSinFuente();

  @override
  Future<Either<Failure, Unit>> solicitar({
    required String colportorId,
    required Coordenadas punto,
  }) async => const Left(FailureSolicitudCiudadNoDisponible());
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
