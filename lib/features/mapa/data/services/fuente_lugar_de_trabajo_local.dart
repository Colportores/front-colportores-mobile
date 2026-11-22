import 'package:dartz/dartz.dart';

import '../../../../core/database/dia_de_calendario.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../tiles/domain/entities/lugar_de_trabajo.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart';
import '../../../tiles/domain/services/fuente_lugar_de_trabajo.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../datasources/campanias_del_colportor_local_data_source.dart';
import '../datasources/lugar_de_trabajo_local_data_source.dart';

/// [FuenteLugarDeTrabajo] sobre las réplicas locales del pull de catálogos: dónde trabaja el colportor
/// para ofrecerle sus mapas en «Mapas offline» (HU-SYNC-010, front-colportores-mobile#619). Lee solo
/// del teléfono, sin red.
///
/// **La ciudad no se resuelve acá.** Sale de [CiudadesParaAlta.proponer], el mismo resolvedor que usan
/// el mapa de la vista 06 y «Nueva ubicación», sin punto del GPS: gana la ciudad de su zona asignada
/// aunque esté lejos (Cristian, «Zona lejos», 03/11) y, sin zona, la única ciudad de su campaña. Así
/// «Mapas offline» y el mapa nunca discrepan sobre la ciudad de la colportora.
///
/// **La zona** es la que tiene asignada en esa ciudad (con varias inscripciones en la misma ciudad,
/// la de menor id: el mismo desempate que el servidor). **El departamento** es el de esa ciudad, como
/// `ambito_id` del paquete: su nombre normalizado («Área depto», Cristian, 23/10).
///
/// **Qué es «no sé».** Una `Left` ([FailureLugarDeTrabajoNoDisponible]) es que no se pudo saber la
/// ciudad: no hay sesión ni base abierta, el teléfono todavía no bajó el catálogo, la campaña no tiene
/// ciudades. Con varias ciudades y nada que decida entre ellas (sin el punto del GPS no se elige: no
/// se adivina) la `Left` dice por qué: [FailureLugarSinZonaConVariasCiudades] o
/// [FailureLugarZonasEnVariasCiudades]. Una zona `null` en el [LugarDeTrabajo] es que se leyó y no
/// tiene zona asignada en esa ciudad: «Mi zona» se muestra apagada y «Mi ciudad» y «Mi departamento»,
/// no.
final class FuenteLugarDeTrabajoLocal implements FuenteLugarDeTrabajo {
  FuenteLugarDeTrabajoLocal({
    required this._colportorId,
    required this._ciudades,
    required this._campanias,
    required this._lugares,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  /// Sin sesión o sin la base local abierta: no hay de dónde leer, así que todo es «no sé».
  FuenteLugarDeTrabajoLocal.sinFuente({AppLogger? logger})
    : _colportorId = null,
      _ciudades = null,
      _campanias = null,
      _lugares = null,
      _ahora = DateTime.now,
      _log = logger ?? AppLogger.instance;

  final String? _colportorId;
  final CiudadesParaAlta? _ciudades;
  final CampaniasDelColportorLocalDataSource? _campanias;
  final LugarDeTrabajoLocalDataSource? _lugares;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async {
    final colportorId = _colportorId;
    final ciudades = _ciudades;
    final campanias = _campanias;
    final lugares = _lugares;
    if (colportorId == null || ciudades == null || campanias == null || lugares == null) {
      _log.warn(LogModulo.map, 'LUGAR_SIN_BASE', 'no hay sesión o base local abierta: no se sabe');
      return const Left(FailureLugarDeTrabajoNoDisponible());
    }
    try {
      final propuesta = await ciudades.proponer(colportorId: colportorId);
      final lectura = propuesta.fold<PropuestaCiudad?>((_) => null, (p) => p);
      // Varias ciudades y nada que decida entre ellas: no es una falla de lectura, y el aviso dice
      // por qué (sin zona, o zonas en más de una ciudad) en lugar de ofrecer un «Reintentar» inútil.
      if (lectura is FaltaElPunto) return Left(await _porQueFaltaElPunto(colportorId, campanias));
      final ciudad = switch (lectura) {
        CiudadPropuesta(:final ciudad) => ciudad,
        _ => null,
      };
      if (ciudad == null) {
        _log.warn(LogModulo.map, 'LUGAR_SIN_CIUDAD', 'no se pudo saber la ciudad de la colportora');
        return const Left(FailureLugarDeTrabajoNoDisponible());
      }
      final leidas = await campanias.leer(colportorId, hoy: diaDeCalendario(_ahora()));
      if (leidas == null) return const Left(FailureLugarDeTrabajoNoDisponible());
      final zonasEnLaCiudad = {
        for (final i in leidas.inscripciones)
          if (i.zonaId != null && i.ciudadDeLaZonaId == ciudad.id) i.zonaId!,
      };
      final datos = await lugares.leer(zonaIds: zonasEnLaCiudad, ciudadId: ciudad.id);
      final zonas = datos.nombresDeZonas.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final zonaId = zonas.firstOrNull;
      // Un departamento en blanco es «sin cargar»: no se ofrece un mapa de nombre vacío.
      final departamentoId = normalizarDepartamento(datos.departamento ?? '');
      return Right(
        LugarDeTrabajo(
          ambito: AmbitoTrabajo(
            zonaId: zonaId,
            ciudadId: ciudad.id,
            departamentoId: departamentoId.isEmpty ? null : departamentoId,
          ),
          zonaNombre: zonaId == null ? null : datos.nombresDeZonas[zonaId],
          ciudadNombre: ciudad.nombre,
        ),
      );
    } on Object catch (e, st) {
      _log.error(
        LogModulo.map,
        'LUGAR_LEER_FAIL',
        'no se pudo leer dónde trabaja la colportora',
        const {},
        e,
        st,
      );
      return const Left(FailureLugarDeTrabajoNoDisponible());
    }
  }

  /// Por qué el resolvedor no pudo elegir entre varias ciudades: la colportora no tiene zona
  /// ([FailureLugarSinZonaConVariasCiudades]) o la tiene en más de una ciudad
  /// ([FailureLugarZonasEnVariasCiudades]). Si no se pueden leer sus inscripciones, no se sabe.
  Future<Failure> _porQueFaltaElPunto(
    String colportorId,
    CampaniasDelColportorLocalDataSource campanias,
  ) async {
    final leidas = await campanias.leer(colportorId, hoy: diaDeCalendario(_ahora()));
    if (leidas == null) return const FailureLugarDeTrabajoNoDisponible();
    final tieneZona = leidas.inscripciones.any((i) => i.ciudadDeLaZonaId != null);
    _log.info(
      LogModulo.map,
      'LUGAR_VARIAS_CIUDADES',
      'varias ciudades y nada que decida entre ellas',
      {'con_zona': tieneZona},
    );
    return tieneZona
        ? const FailureLugarZonasEnVariasCiudades()
        : const FailureLugarSinZonaConVariasCiudades();
  }
}
