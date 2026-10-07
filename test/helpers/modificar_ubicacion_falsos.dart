import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';

import 'alta_ubicacion_falsos.dart';
import 'ubicacion_sin_modificar.dart';

/// Cuándo se creó y se tocó por última vez la ubicación de los tests de la vista 07: el 12 de agosto
/// (el «creada el 12/08» del canvas).
final creadaEl12DeAgosto = DateTime.utc(2026, 8, 12, 15);
final tocadaElUltimoDia = DateTime.utc(2026, 9, 30, 11);

/// La ubicación que se edita en los tests: «Av. Italia 1234», una casa de Montevideo, en el punto de
/// los artboards de la vista 03.
Ubicacion ubicacionGuardada({
  String id = 'ubi-1',
  TipoUbicacion tipo = TipoUbicacion.casa,
  String? calle = 'Av. Italia',
  String? numero = '1234',
  Coordenadas punto = puntoItalia,
  String ciudadId = 'ciu-mvd',
  String? zonaId,
  String creadaPor = 'col-1',
  DateTime? creada,
  DateTime? actualizada,
  DateTime? deBajaDesde,
}) => Ubicacion(
  id: id,
  tipo: tipo,
  calle: calle,
  numero: numero,
  lat: punto.lat,
  lon: punto.lon,
  ciudadId: ciudadId,
  zonaId: zonaId,
  auditoria: Auditoria(
    createdAt: creada ?? creadaEl12DeAgosto,
    updatedAt: actualizada ?? tocadaElUltimoDia,
    createdBy: creadaPor,
    deletedAt: deBajaDesde,
  ),
);

/// Una escritura que llegó al repositorio.
typedef EscrituraEdicion = ({
  Ubicacion nueva,
  DateTime baseUpdatedAt,
  CriterioDuplicadoUbicacion? duplicados,
  bool reduceAUnEspacio,
});

/// El repositorio de ubicaciones de la edición: guarda la ubicación en memoria y deja que el test
/// decida qué se lee, cuántos espacios tiene y cómo termina cada `modificar`.
final class RepoEdicionFalso with UbicacionRepositorySinModificar implements UbicacionRepository {
  RepoEdicionFalso(this.actual, {this.espacios = 2, this.numeroDepto});

  /// Lo que hay en el teléfono; `null` = la ubicación no está.
  Ubicacion? actual;
  int espacios;

  /// El `numero_depto` del único espacio (solo se devuelve si [espacios] es 1).
  String? numeroDepto;

  /// Si no es `null`, `obtener` devuelve esta falla (o lanza [lanzaAlLeer]).
  Failure? fallaAlLeer;
  Object? lanzaAlLeer;

  /// Si no es `null`, `obtener` espera a que se complete.
  Completer<void>? bloqueoLectura;

  Failure? fallaAlContar;

  /// Si no es `null`, `numeroDelUnicoDepto` devuelve esta falla.
  Failure? fallaAlLeerDepto;

  /// Si no es `null`, `modificar` espera a que se complete.
  Completer<void>? bloqueoEscritura;

  /// Qué devuelve `modificar` en la llamada [numero] (la primera es la 1). Por defecto la deja
  /// guardada y devuelve `UbicacionModificada`.
  Future<Either<Failure, ResultadoModificacionUbicacion>> Function(
    Ubicacion nueva,
    int numero,
    CriterioDuplicadoUbicacion? duplicados,
  )?
  comportamiento;

  var lecturas = 0;
  final escrituras = <EscrituraEdicion>[];

  @override
  Future<Either<Failure, Ubicacion?>> obtener(String id) async {
    lecturas++;
    final espera = bloqueoLectura;
    if (espera != null) await espera.future;
    final lanza = lanzaAlLeer;
    if (lanza != null) throw lanza;
    final falla = fallaAlLeer;
    if (falla != null) return Left(falla);
    final leida = actual;
    return Right(leida != null && leida.id == id ? leida : null);
  }

  @override
  Future<Either<Failure, int>> contarEspaciosActivos(String ubicacionId) async {
    final falla = fallaAlContar;
    return falla != null ? Left(falla) : Right(espacios);
  }

  @override
  Future<Either<Failure, String?>> numeroDelUnicoDepto(String ubicacionId) async {
    final falla = fallaAlLeerDepto;
    return falla != null ? Left(falla) : Right(espacios == 1 ? numeroDepto : null);
  }

  @override
  Future<Either<Failure, ResultadoModificacionUbicacion>> modificar(
    Ubicacion nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
    bool reduceAUnEspacio = false,
  }) async {
    escrituras.add((
      nueva: nueva,
      baseUpdatedAt: baseUpdatedAt,
      duplicados: duplicados,
      reduceAUnEspacio: reduceAUnEspacio,
    ));
    final espera = bloqueoEscritura;
    if (espera != null) await espera.future;
    final f = comportamiento;
    if (f != null) return f(nueva, escrituras.length, duplicados);
    actual = nueva;
    return Right(UbicacionModificada(ubicacion: nueva));
  }

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();

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
