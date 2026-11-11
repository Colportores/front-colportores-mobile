import 'package:dartz/dartz.dart';

import '../../../../core/database/dia_de_calendario.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/zona_ubicable.dart';
import '../../domain/repositories/zona_repository.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/zona_por_posicion.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../datasources/campanias_del_colportor_local_data_source.dart';

/// [CiudadesParaAlta] sobre las réplicas locales del pull de catálogos (`campania_colportor`,
/// `campania`, `campania_ciudad`, `ciudad`, `zona` y `zona_vertice`): lee solo del teléfono, sin red
/// (HU-UBI-001 y HU-UBI-003, front-colportores-mobile#274).
///
/// **Qué campañas.** Las del colportor con inscripción viva que no terminaron (en curso o por
/// empezar), la misma regla con la que el servidor le baja el mapa y las casas. Con más de una, las
/// ciudades son la unión de todas; nunca las de una campaña en la que no está inscripto.
///
/// **Qué ciudad se propone** ([proponer]), en este orden (decisión de Cristian, 02/10, en
/// front-colportores-mobile#267):
/// 1. la de la zona de sus campañas que contiene el punto ([OrigenPropuesta.detectada]), con la
///    misma regla que el servidor para ubicar un punto (`ZonaPorPosicion`);
/// 2. la de su zona asignada ([OrigenPropuesta.deZona]), si sus zonas asignadas son de una sola ciudad;
/// 3. la única ciudad de sus campañas ([OrigenPropuesta.deCampania]);
/// 4. con varias, la de centro más cercano al punto ([OrigenPropuesta.deCampania]); sin punto,
///    [FaltaElPunto].
///
/// **Qué es «no sé».** Una `Left` ([FailureCiudadesNoDisponibles]) es que no se pudo leer: la base no
/// está abierta, falló la lectura, o el teléfono todavía no bajó el catálogo (ningún pull terminó, o
/// falta una campaña o una ciudad a la que apunta una fila). [CampaniaSinCiudades] y la lista vacía son
/// solo para cuando se leyó y de verdad no hay: una fuente que no sabe nunca contesta eso, porque
/// mandaría al colportor a molestar al coordinador por algo que no es de la campaña.
final class CiudadesParaAltaLocal implements CiudadesParaAlta {
  CiudadesParaAltaLocal({
    required this._campanias,
    required this._zonas,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  /// Sin la base local abierta (no hay sesión): no hay de dónde leer, así que todo es «no sé».
  CiudadesParaAltaLocal.sinBaseAbierta({AppLogger? logger})
    : _campanias = null,
      _zonas = null,
      _ahora = DateTime.now,
      _log = logger ?? AppLogger.instance;

  final CampaniasDelColportorLocalDataSource? _campanias;
  final ZonaRepository? _zonas;
  final DateTime Function() _ahora;
  final AppLogger _log;

  static const _regla = ZonaPorPosicion();

  @override
  Future<Either<Failure, PropuestaCiudad>> proponer({
    required String colportorId,
    Coordenadas? punto,
  }) async {
    try {
      final campanias = await _leer(colportorId);
      if (campanias == null) return const Left(FailureCiudadesNoDisponibles());
      if (campanias.ciudades.isEmpty) return const Right(CampaniaSinCiudades());
      return await _proponerCon(campanias, punto);
    } on Object catch (e, st) {
      return _noSe(e, st);
    }
  }

  @override
  Future<Either<Failure, List<CiudadCatalogo>>> deMiCampania(String colportorId) async {
    try {
      final campanias = await _leer(colportorId);
      if (campanias == null) return const Left(FailureCiudadesNoDisponibles());
      return Right([
        for (final c in campanias.ciudades) CiudadCatalogo(id: c.id, nombre: c.nombre),
      ]);
    } on Object catch (e, st) {
      return _noSe(e, st);
    }
  }

  Future<Either<Failure, PropuestaCiudad>> _proponerCon(
    CampaniasDelColportor campanias,
    Coordenadas? punto,
  ) async {
    final ciudades = campanias.ciudades;
    CiudadPropuesta propuesta(CiudadDeCampania c, OrigenPropuesta origen) =>
        CiudadPropuesta(CiudadCatalogo(id: c.id, nombre: c.nombre), origen);

    // 1. La zona de sus campañas que contiene el punto. Si las zonas no se pueden leer no se sabe si el
    // punto cae en una, y proponer otra ciudad sería inventar una detección que no se hizo.
    if (punto != null) {
      final detectada = await _ciudadDeLaZonaQueContiene(punto, campanias);
      final ciudadId = detectada.fold<String?>((_) => null, (id) => id);
      if (detectada.isLeft()) return const Left(FailureCiudadesNoDisponibles());
      if (ciudadId != null) {
        return Right(
          propuesta(ciudades.firstWhere((c) => c.id == ciudadId), OrigenPropuesta.detectada),
        );
      }
    }

    // 2. La ciudad de su zona asignada, si todas sus zonas asignadas son de la misma ciudad.
    final deSusZonas = {for (final i in campanias.inscripciones) ?i.ciudadDeLaZonaId};
    if (deSusZonas.length == 1) {
      final ciudad = ciudades.where((c) => c.id == deSusZonas.single).firstOrNull;
      if (ciudad != null) return Right(propuesta(ciudad, OrigenPropuesta.deZona));
    }

    // 3. La única ciudad de sus campañas.
    if (ciudades.length == 1) return Right(propuesta(ciudades.single, OrigenPropuesta.deCampania));

    // 4. Con varias, la de centro más cercano al punto. Sin punto no hay con qué elegir.
    if (punto == null) return const Right(FaltaElPunto());
    var elegida = ciudades.first;
    var distancia = punto.distanciaMetrosA(Coordenadas(lat: elegida.lat, lon: elegida.lon));
    for (final c in ciudades.skip(1)) {
      final d = punto.distanciaMetrosA(Coordenadas(lat: c.lat, lon: c.lon));
      if (d < distancia) {
        elegida = c;
        distancia = d;
      }
    }
    return Right(propuesta(elegida, OrigenPropuesta.deCampania));
  }

  /// La ciudad de la zona (viva) de las campañas del colportor que cubre [punto], o `null` si ninguna
  /// lo cubre. Con varias gana la misma que elige el servidor: campaña preferida y, después, menor id.
  /// `Left` si las zonas de alguna ciudad no se pueden leer.
  Future<Either<Failure, String?>> _ciudadDeLaZonaQueContiene(
    Coordenadas punto,
    CampaniasDelColportor c,
  ) async {
    final campaniasVigentes = {for (final i in c.inscripciones) i.campaniaId};
    final preferidas = campaniasVigentes.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    String? zonaElegida;
    String? ciudadElegida;
    for (final ciudad in c.ciudades) {
      final leidas = await _zonas!.vivasDeCiudad(ciudad.id);
      final zonas = leidas.fold<List<ZonaUbicable>?>((_) => null, (z) => z);
      if (zonas == null) return const Left(FailureCiudadesNoDisponibles());
      final zonaId = _regla.zonaDe(
        punto,
        ciudadId: ciudad.id,
        zonas: zonas,
        campaniasVigentes: campaniasVigentes,
        campaniasPreferidas: preferidas,
      );
      if (zonaId == null) continue;
      if (zonaElegida == null || zonaId.toLowerCase().compareTo(zonaElegida.toLowerCase()) < 0) {
        zonaElegida = zonaId;
        ciudadElegida = ciudad.id;
      }
    }
    return Right(ciudadElegida);
  }

  Future<CampaniasDelColportor?> _leer(String colportorId) async {
    final fuente = _campanias;
    if (fuente == null) {
      _log.warn(LogModulo.map, 'CIUDADES_SIN_BASE', 'no hay base local abierta: no hay ciudades');
      return null;
    }
    final leidas = await fuente.leer(colportorId, hoy: diaDeCalendario(_ahora()));
    if (leidas == null) {
      _log.warn(
        LogModulo.map,
        'CIUDADES_REPLICA_SIN_BAJAR',
        'el teléfono todavía no bajó las campañas y las ciudades del colportor',
      );
    }
    return leidas;
  }

  Left<Failure, T> _noSe<T>(Object e, StackTrace st) {
    _log.error(
      LogModulo.map,
      'CIUDADES_LEER_FAIL',
      'no se pudieron leer las ciudades de la campaña',
      const {},
      e,
      st,
    );
    return const Left(FailureCiudadesNoDisponibles());
  }
}
