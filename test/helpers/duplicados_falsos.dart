import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacios_activos.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_union_duplicados.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/pares_duplicados_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/encolador_marcar_duplicado.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'alta_ubicacion_falsos.dart' show overridesAlta;
import 'mapa_base_falso.dart' show FabricaMapaFalsa;
import 'ubicacion_sin_modificar.dart';

/// Una ubicación de prueba: la misma calle y número que las demás (`Av. Italia 1234`), así que dos
/// con `metrosAlNorte` distintos son un par del scan.
Ubicacion ubicacionDuplicable(
  String id, {
  double metrosAlNorte = 0,
  DateTime? creada,
  DateTime? deletedAt,
  String calle = 'Av. Italia',
  String numero = '1234',
  TipoUbicacion tipo = TipoUbicacion.casa,
}) {
  final t = creada ?? DateTime.utc(2026, 9, 1, 10);
  return Ubicacion(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: -34.891 + metrosAlNorte / 111195.08,
    lon: -56.125,
    ciudadId: 'mvd',
    zonaId: 'zona-1',
    auditoria: Auditoria(createdAt: t, updatedAt: t, createdBy: 'col-1', deletedAt: deletedAt),
  );
}

/// [EncoladorMarcarDuplicado] que anota lo que le piden. [fallarCon] simula un motor que rechaza el
/// trabajo: la unión local se tiene que revertir entera.
final class EncoladorMarcarDuplicadoFalso implements EncoladorMarcarDuplicado {
  EncoladorMarcarDuplicadoFalso({this.fallarCon});

  Object? fallarCon;
  final encolados = <({String duplicadaId, String conservadaId})>[];

  @override
  Future<void> encolarMarcarDuplicado({
    required String duplicadaId,
    required String conservadaId,
  }) async {
    final error = fallarCon;
    if (error != null) throw error;
    encolados.add((duplicadaId: duplicadaId, conservadaId: conservadaId));
  }
}

/// Las ubicaciones y las decisiones de la vista 10 en memoria y reactivas, para los tests de
/// pantalla: lo que se une o se decide cambia el stream de pares, como con la base real.
///
/// Se puede frenar la unión ([retenerUniones]) para probar dos acciones seguidas, fallarla
/// ([falloAlUnir]) o cambiar el reloj ([ahora]).
final class DuplicadosEnMemoria {
  DuplicadosEnMemoria({List<Ubicacion> ubicaciones = const [], Map<String, int>? espacios})
    : _ubicaciones = [...ubicaciones],
      _espacios = {...?espacios} {
    ubicacionesRepo = _Ubicaciones(this);
    paresRepo = _Pares(this);
  }

  final List<Ubicacion> _ubicaciones;
  final Map<String, int> _espacios;
  final Map<String, EstadoCasa> estados = {};
  Map<String, ParDecidido> decididos = {};
  var ahora = DateTime.utc(2026, 10, 9, 12);

  late final UbicacionRepository ubicacionesRepo;
  late final ParesDuplicadosRepository paresRepo;

  /// Falla de la próxima (y de las siguientes) uniones; `null` = anda.
  Failure? falloAlUnir;

  /// Si no es `null`, `unirDuplicada` lanza esto (un puerto roto).
  Object? lanzaAlUnir;

  /// Falla de lectura de la lista: el stream sale con error.
  Object? errorDeLectura;

  /// La lectura de la lista no responde nunca (el estado «cargando»).
  var lecturaColgada = false;

  /// Falla de [ParesDuplicadosRepository.decidir].
  Failure? falloAlDecidir;

  /// Mientras haya un completer, `unirDuplicada` no responde hasta que se complete.
  Completer<void>? retenerUniones;

  final uniones = <({String conservadaId, String duplicadaId})>[];
  final decisiones = <({String clave, DecisionParDuplicado decision})>[];
  var lecturas = 0;
  final _cambios = StreamController<void>.broadcast(sync: true);

  List<Ubicacion> get ubicaciones => List.unmodifiable(_ubicaciones);

  Ubicacion ubicacion(String id) => _ubicaciones.firstWhere((u) => u.id == id);

  void agregar(Ubicacion u, {int espacios = 1}) {
    _ubicaciones.add(u);
    _espacios[u.id] = espacios;
    _cambios.add(null);
  }

  void cambiarEspacios(String id, int cantidad) {
    _espacios[id] = cantidad;
    _cambios.add(null);
  }

  /// Da de baja `id` desde afuera (por ejemplo, el sync).
  void darDeBaja(String id) {
    final i = _ubicaciones.indexWhere((u) => u.id == id);
    final u = _ubicaciones[i];
    _ubicaciones[i] = Ubicacion(
      id: u.id,
      tipo: u.tipo,
      calle: u.calle,
      numero: u.numero,
      lat: u.lat,
      lon: u.lon,
      ciudadId: u.ciudadId,
      zonaId: u.zonaId,
      auditoria: Auditoria(
        createdAt: u.auditoria.createdAt,
        updatedAt: ahora,
        createdBy: u.auditoria.createdBy,
        deletedAt: ahora,
      ),
    );
    _cambios.add(null);
  }

  /// Un stream que emite `leer()` al suscribirse y con cada cambio, sin perder los que llegan en
  /// medio.
  Stream<T> _reactivo<T>(T Function() leer, {Object? error}) {
    late final StreamController<T> salida;
    StreamSubscription<void>? suscripcion;
    salida = StreamController<T>(
      onListen: () {
        if (error != null) {
          salida.addError(error);
          return;
        }
        salida.add(leer());
        suscripcion = _cambios.stream.listen((_) => salida.add(leer()));
      },
      onCancel: () => suscripcion?.cancel(),
    );
    return salida.stream;
  }

  Stream<List<UbicacionConResumen>> _lista() {
    lecturas++;
    if (lecturaColgada) return StreamController<List<UbicacionConResumen>>().stream;
    return _reactivo(
      () => [
        for (final u in _ubicaciones)
          if (!u.auditoria.estaBorrada)
            UbicacionConResumen(
              ubicacion: u,
              cantidadEspacios: _espacios[u.id] ?? 1,
              estado: estados[u.id],
            ),
      ],
      error: errorDeLectura,
    );
  }

  Stream<Map<String, ParDecidido>> _decididos() => _reactivo(() => decididos);

  Future<void> cerrar() => _cambios.close();
}

final class _Ubicaciones with UbicacionRepositorySinModificar implements UbicacionRepository {
  _Ubicaciones(this._d);

  final DuplicadosEnMemoria _d;

  @override
  Stream<List<UbicacionConResumen>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) => _d._lista();

  @override
  Future<Either<Failure, ResultadoUnionDuplicados>> unirDuplicada(
    String conservadaId,
    String duplicadaId, {
    required DateTime ahora,
  }) async {
    _d.uniones.add((conservadaId: conservadaId, duplicadaId: duplicadaId));
    final espera = _d.retenerUniones;
    if (espera != null) await espera.future;
    final lanza = _d.lanzaAlUnir;
    if (lanza != null) throw lanza;
    final falla = _d.falloAlUnir;
    if (falla != null) return Left(falla);
    final i = _d._ubicaciones.indexWhere((u) => u.id == duplicadaId);
    if (i < 0) return const Left(FailureUbicacionInexistente());
    final conservada = _d._ubicaciones.where((u) => u.id == conservadaId).firstOrNull;
    if (conservada == null) return const Left(FailureUbicacionInexistente());
    if (conservada.auditoria.estaBorrada) return const Left(FailureConservadaDeBaja());
    final pasados = _d._espacios[duplicadaId] ?? 1;
    _d._espacios[conservadaId] = (_d._espacios[conservadaId] ?? 1) + pasados;
    _d.darDeBaja(duplicadaId);
    return Right(ResultadoUnionDuplicados(escribio: true, espaciosPasados: pasados));
  }

  // Lo que la edición («Editar uno») lee de la ubicación que se abre.
  @override
  Future<Either<Failure, Ubicacion?>> obtener(String id) async =>
      Right(_d._ubicaciones.where((u) => u.id == id).firstOrNull);

  @override
  Future<Either<Failure, int>> contarEspaciosActivos(String ubicacionId) async =>
      Right(_d._espacios[ubicacionId] ?? 1);

  @override
  Stream<EspaciosActivos> observarEspaciosActivos(String ubicacionId) =>
      Stream.value((cantidad: _d._espacios[ubicacionId] ?? 1, numeroDeptoUnico: null));

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => throw UnimplementedError();
}

final class _Pares implements ParesDuplicadosRepository {
  _Pares(this._d);

  final DuplicadosEnMemoria _d;

  @override
  Future<Either<Failure, Map<String, ParDecidido>>> decididos() async => Right(_d.decididos);

  @override
  Stream<Map<String, ParDecidido>> observarDecididos() => _d._decididos();

  @override
  Future<Either<Failure, Unit>> decidir(
    ParDuplicado par,
    DecisionParDuplicado decision, {
    required DateTime ahora,
  }) async {
    final falla = _d.falloAlDecidir;
    if (falla != null) return Left(falla);
    _d.decisiones.add((clave: par.clave, decision: decision));
    _d.decididos = {..._d.decididos, par.clave: ParDecidido(decision: decision, decididoEn: ahora)};
    _d._cambios.add(null);
    return const Right(unit);
  }
}

/// Overrides para probar «Posibles duplicados» sin plugins ni base de datos: los repositorios en
/// memoria de [datos], el reloj de [datos] y un plazo de «Deshacer» de [plazo].
///
/// Con [conMapa] se suman los del mapa falso (la hoja de comparar dibuja un mapa chico) y los de la
/// edición («Editar uno»); sin él, solo lo que necesitan las pruebas sin widgets.
List<Override> overridesDuplicados(
  DuplicadosEnMemoria datos, {
  Duration plazo = const Duration(seconds: 8),
  bool conMapa = false,
  FabricaMapaFalsa? mapa,
  SituacionMapa? situacion,
}) => [
  if (conMapa)
    // `overridesAlta` ya sobrescribe el repositorio y el reloj: un provider no se puede sobrescribir
    // dos veces en el mismo contenedor.
    ...overridesAlta(
      repo: datos.ubicacionesRepo,
      ahora: datos.ahora,
      mapa: mapa,
      situacion: situacion,
    )
  else ...[
    ubicacionRepositoryProvider.overrideWithValue(datos.ubicacionesRepo),
    relojAltaUbicacionProvider.overrideWithValue(() => datos.ahora),
  ],
  paresDuplicadosRepositoryProvider.overrideWithValue(datos.paresRepo),
  plazoDeshacerUnionProvider.overrideWithValue(plazo),
  // Sin base abierta el provider devuelve una lista vacía; con los repositorios en memoria hay que
  // pasar por el caso de uso de todos modos.
  paresParaRevisarProvider.overrideWith(
    (ref, colportorId) => ref.watch(observarParesDuplicadosUseCaseProvider)(colportorId),
  ),
];
