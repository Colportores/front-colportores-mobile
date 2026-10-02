import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/activador_gps.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proveedor_gps.dart';
import 'package:colportores_mobile/features/mapa/domain/services/solicitador_alta_ciudad.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'ubicacion_sin_modificar.dart';
import 'zonas_falsas.dart';

/// Av. Italia, Montevideo: el punto de los artboards de la vista 03.
const puntoItalia = Coordenadas(lat: -34.88761, lon: -56.13024);

const montevideo = CiudadCatalogo(id: 'ciu-mvd', nombre: 'Montevideo');
const canelones = CiudadCatalogo(id: 'ciu-can', nombre: 'Canelones');

LecturaGps lecturaGps(double precision, {Coordenadas punto = puntoItalia}) =>
    LecturaGps(coordenadas: punto, precisionMetros: precision);

/// El GPS del teléfono, que el test controla: qué devuelve, cuánto tarda y qué se activó.
final class GpsFalso implements ProveedorGps, ActivadorGps {
  GpsFalso([Either<Failure, LecturaGps>? respuesta])
    : respuesta = respuesta ?? Right(lecturaGps(6));

  Either<Failure, LecturaGps> respuesta;

  /// Si no es `null`, la lectura espera a que se complete.
  Completer<void>? bloqueo;

  var lecturas = 0;
  final activaciones = <MotivoSinGps>[];

  /// Qué hace «Activar GPS»: por ejemplo, cambiar [respuesta].
  void Function()? alActivar;

  @override
  Future<Either<Failure, LecturaGps>> posicionActual() async {
    lecturas++;
    final espera = bloqueo;
    if (espera != null) await espera.future;
    return respuesta;
  }

  @override
  Future<void> activar(MotivoSinGps motivo) async {
    activaciones.add(motivo);
    alActivar?.call();
  }
}

/// El geocodificador inverso: devuelve [respuesta] para cada punto y guarda lo pedido.
final class GeocodificadorFalso implements GeocodificadorInverso {
  GeocodificadorFalso([this.respuesta]);

  DireccionDelPunto? Function(Coordenadas punto)? respuesta;
  final pedidos = <Coordenadas>[];
  Completer<void>? bloqueo;

  @override
  Future<DireccionDelPunto?> direccionDe(Coordenadas punto) async {
    pedidos.add(punto);
    final espera = bloqueo;
    if (espera != null) await espera.future;
    return respuesta?.call(punto);
  }
}

/// El catálogo de ciudades en memoria.
final class CiudadesFalsas implements CiudadesParaAlta {
  CiudadesFalsas({
    this.detecta = _siempreMontevideo,
    this.catalogo = const [montevideo, canelones],
    this.miZona = montevideo,
  });

  static DeteccionCiudad _siempreMontevideo(Coordenadas _) => const CiudadDetectada(montevideo);

  DeteccionCiudad Function(Coordenadas punto) detecta;
  List<CiudadCatalogo> catalogo;
  CiudadCatalogo? miZona;
  Failure? fallaTodas;
  Completer<void>? bloqueoTodas;
  var consultasTodas = 0;

  @override
  Future<Either<Failure, DeteccionCiudad>> detectar(Coordenadas punto) async =>
      Right(detecta(punto));

  @override
  Future<Either<Failure, List<CiudadCatalogo>>> todas() async {
    consultasTodas++;
    final espera = bloqueoTodas;
    if (espera != null) await espera.future;
    return fallaTodas != null ? Left(fallaTodas!) : Right(catalogo);
  }

  @override
  Future<Either<Failure, CiudadCatalogo?>> deMiZona(String colportorId) async => Right(miZona);
}

final class SolicitadorFalso implements SolicitadorAltaCiudad {
  Failure? falla;
  Completer<void>? bloqueo;
  final puntos = <Coordenadas>[];

  @override
  Future<Either<Failure, Unit>> solicitar({
    required String colportorId,
    required Coordenadas punto,
  }) async {
    puntos.add(punto);
    final espera = bloqueo;
    if (espera != null) await espera.future;
    return falla != null ? Left(falla!) : const Right(unit);
  }
}

/// El repositorio de ubicaciones, con el resultado de `registrar` a gusto del test.
final class RepoAltaFalso with UbicacionRepositorySinModificar implements UbicacionRepository {
  /// Qué devuelve `registrar`. Por defecto, el alta hecha.
  Future<Either<Failure, ResultadoAltaUbicacion>> Function(Ubicacion ubicacion)? comportamiento;

  /// Lo que recibió cada llamada a `registrar`.
  final llamadas =
      <
        ({
          Ubicacion ubicacion,
          Espacio? espacio,
          OrigenCoordenadas origen,
          CriterioDuplicadoUbicacion? duplicados,
        })
      >[];

  Completer<void>? bloqueo;

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) async {
    llamadas.add((ubicacion: ubicacion, espacio: espacio, origen: origen, duplicados: duplicados));
    final espera = bloqueo;
    if (espera != null) await espera.future;
    final f = comportamiento;
    if (f != null) return f(ubicacion);
    return Right(AltaRegistrada(ubicacion: ubicacion, espacio: espacio));
  }

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => throw UnimplementedError();

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => Stream.value(const []);
}

/// Una candidata a duplicado, [metros] metros al norte de [puntoItalia].
CandidataDuplicado candidata(
  String id, {
  double metros = 12,
  String? calle = 'Av. Italia',
  String? numero = '1234',
  MotivoDuplicado motivo = MotivoDuplicado.mismaDireccion,
  bool admiteConservarAmbos = true,
  TipoUbicacion tipo = TipoUbicacion.casa,
  String ciudadId = 'ciu-mvd',
  DateTime? actualizada,
}) {
  final cuando = actualizada ?? DateTime.utc(2026, 9, 29, 12);
  return CandidataDuplicado(
    ubicacion: Ubicacion(
      id: id,
      tipo: tipo,
      calle: calle,
      numero: numero,
      lat: puntoItalia.lat + metros / 111320,
      lon: puntoItalia.lon,
      ciudadId: ciudadId,
      auditoria: Auditoria(createdAt: cuando, updatedAt: cuando, createdBy: 'col-2'),
    ),
    motivo: motivo,
    distanciaMetros: metros,
    admiteConservarAmbos: admiteConservarAmbos,
  );
}

/// Overrides de Riverpod para probar el alta sin plugins, red ni base de datos.
List<Override> overridesAlta({
  GpsFalso? gps,
  GeocodificadorFalso? geocodificador,
  CiudadesFalsas? ciudades,
  SolicitadorFalso? solicitador,
  RepoAltaFalso? repo,
  Duration espera = const Duration(milliseconds: 20),
  DateTime? ahora,
  List<MarcadorMapa> marcadores = const [],
}) {
  final gpsFalso = gps ?? GpsFalso();
  var secuencia = 0;
  return [
    proveedorGpsProvider.overrideWithValue(gpsFalso),
    activadorGpsProvider.overrideWithValue(gpsFalso),
    geocodificadorInversoProvider.overrideWithValue(geocodificador ?? GeocodificadorFalso()),
    ciudadesParaAltaProvider.overrideWithValue(ciudades ?? CiudadesFalsas()),
    solicitadorAltaCiudadProvider.overrideWithValue(solicitador ?? SolicitadorFalso()),
    ubicacionRepositoryProvider.overrideWithValue(repo ?? RepoAltaFalso()),
    ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
    esperaPuntoAltaProvider.overrideWithValue(espera),
    generadorIdUbicacionProvider.overrideWithValue(() => 'id-${++secuencia}'),
    relojAltaUbicacionProvider.overrideWithValue(() => ahora ?? DateTime.utc(2026, 10, 2, 14, 35)),
    marcadoresCercanosProvider.overrideWith((ref, consulta) => Stream.value(marcadores)),
  ];
}

/// Los parámetros de alta que usan los tests.
const parametrosAlta = ParametrosAlta(colportorId: 'col-1');
