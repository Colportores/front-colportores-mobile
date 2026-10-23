// Dobles de la gestión de espacios (HU-UBI-007, vista 11): un repositorio en memoria con las mismas
// reglas que el real (ubicación activa y no casa, número sin repetir sin contar espacios ni
// mayúsculas, idempotencia del alta) y con las pausas y las fallas que piden los casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/contador_personas_espacio.dart';
import 'package:dartz/dartz.dart';

import 'modificar_ubicacion_falsos.dart';

/// El instante de «hoy» de los tests de la gestión de espacios.
final hoyEspacios = DateTime.utc(2026, 10, 23, 15);

/// Un edificio («Mataojo 2044», el del canvas de la vista 11).
Ubicacion edificioMataojo({String id = 'ubi-1', TipoUbicacion tipo = TipoUbicacion.edificio}) =>
    ubicacionGuardada(id: id, tipo: tipo, calle: 'Mataojo', numero: '2044');

/// Un espacio de [ubicacionId]. [orden] ordena las altas (minutos desde las 10:00).
Espacio espacioDe(
  String id,
  String? numero, {
  String? piso,
  String ubicacionId = 'ubi-1',
  int orden = 0,
  DateTime? baja,
}) => Espacio(
  id: id,
  ubicacionId: ubicacionId,
  numeroDepto: numero,
  piso: piso,
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 20, 10, orden),
    updatedAt: DateTime.utc(2026, 10, 20, 10, orden),
    createdBy: 'col-1',
    deletedAt: baja,
  ),
);

/// Las personas activas de cada espacio.
final class ContadorPersonasFalso implements ContadorPersonasEspacio {
  ContadorPersonasFalso([Map<String, int>? personas]) : personas = personas ?? {};

  final Map<String, int> personas;

  /// Si no es `null`, contar lanza esto.
  Object? lanza;

  @override
  Future<int> activasEn(String espacioId) async {
    final roto = lanza;
    if (roto != null) throw roto;
    return personas[espacioId] ?? 0;
  }
}

/// [EspacioRepository] en memoria.
///
/// - [espera]: si no es `null`, la próxima escritura (agregar, modificar o dar de baja) espera a que se
///   complete y recién ahí se aplica.
/// - [fallas]: las fallas de las próximas escrituras, de a una (una escritura que falla no cambia nada).
/// - [lanzas]: lo mismo, pero lanzando.
/// - [fallaAlListar]: mientras no sea `null`, `listar` devuelve esa falla.
final class EspacioRepoFalso implements EspacioRepository {
  EspacioRepoFalso(this.ubicacion, {List<Espacio> espacios = const []}) {
    this.espacios.addAll(espacios);
  }

  final Ubicacion ubicacion;

  /// Todo lo guardado, bajas incluidas.
  final espacios = <Espacio>[];

  Completer<void>? espera;
  final fallas = <Failure>[];
  final lanzas = <Object>[];
  Failure? fallaAlListar;

  /// Si no es `null`, la próxima lectura de la lista espera a que se complete.
  Completer<void>? esperaAlListar;

  /// Las escrituras que llegaron, en orden: `agregar:<id>`, `modificar:<id>`, `baja:<id>`.
  final llamadas = <String>[];

  /// Las lecturas de la lista.
  var listados = 0;

  List<Espacio> get activos => [
    for (final e in espacios)
      if (!e.estaBorrada && e.ubicacionId == ubicacion.id) e,
  ];

  Espacio? _por(String id) {
    for (final e in espacios) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<Either<Failure, Espacio>?> _antes() async {
    final pausa = espera;
    if (pausa != null) {
      espera = null;
      await pausa.future;
    }
    if (lanzas.isNotEmpty) throw lanzas.removeAt(0);
    if (fallas.isNotEmpty) return Left(fallas.removeAt(0));
    return null;
  }

  static Either<Failure, Espacio> _rechazo(MotivoRechazoEspacio motivo) =>
      Left(FailureValidacion(campos: {motivo.campo: motivo.mensaje}));

  @override
  Future<Either<Failure, Espacio>> agregar(Espacio espacio) async {
    llamadas.add('agregar:${espacio.id}');
    final previo = _por(espacio.id);
    if (previo != null) return Right(previo);
    final corte = await _antes();
    if (corte != null) return corte;
    if (ubicacion.estaBorrada) return _rechazo(MotivoRechazoEspacio.ubicacionDeBaja);
    if (ubicacion.tipo == TipoUbicacion.casa) return _rechazo(MotivoRechazoEspacio.ubicacionCasa);
    if (activos.any((e) => e.clave == espacio.clave)) {
      return _rechazo(MotivoRechazoEspacio.deptoDuplicado);
    }
    espacios.add(espacio);
    return Right(espacio);
  }

  @override
  Future<Either<Failure, Espacio>> modificar(
    String id, {
    required String numeroDepto,
    String? piso,
    required DateTime ahora,
  }) async {
    llamadas.add('modificar:$id');
    final corte = await _antes();
    if (corte != null) return corte;
    final actual = _por(id);
    if (actual == null) return _rechazo(MotivoRechazoEspacio.espacioInexistente);
    if (actual.estaBorrada) return _rechazo(MotivoRechazoEspacio.espacioDeBaja);
    final clave = Espacio.claveDeNumero(numeroDepto);
    if (clave != actual.clave && activos.any((e) => e.id != id && e.clave == clave)) {
      return _rechazo(MotivoRechazoEspacio.deptoDuplicado);
    }
    final nuevo = Espacio(
      id: actual.id,
      ubicacionId: actual.ubicacionId,
      numeroDepto: numeroDepto,
      piso: piso,
      auditoria: actual.auditoria.copyWith(updatedAt: ahora),
    );
    espacios[espacios.indexOf(actual)] = nuevo;
    return Right(nuevo);
  }

  @override
  Future<Either<Failure, Espacio>> darDeBaja(String id, {required DateTime ahora}) async {
    llamadas.add('baja:$id');
    final corte = await _antes();
    if (corte != null) return corte;
    final actual = _por(id);
    if (actual == null) return _rechazo(MotivoRechazoEspacio.espacioInexistente);
    final baja = Espacio(
      id: actual.id,
      ubicacionId: actual.ubicacionId,
      numeroDepto: actual.numeroDepto,
      piso: actual.piso,
      auditoria: actual.auditoria.copyWith(updatedAt: ahora, deletedAt: ahora),
    );
    espacios[espacios.indexOf(actual)] = baja;
    return Right(baja);
  }

  @override
  Future<Either<Failure, Espacio>> restaurar(String id, {required DateTime ahora}) async {
    final actual = _por(id);
    if (actual == null) return _rechazo(MotivoRechazoEspacio.espacioInexistente);
    return Right(actual);
  }

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async {
    final e = _por(id);
    return Right(e == null ? null : (espacio: e, ubicacion: ubicacion));
  }

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async {
    listados++;
    final pausa = esperaAlListar;
    if (pausa != null) {
      esperaAlListar = null;
      await pausa.future;
    }
    final falla = fallaAlListar;
    if (falla != null) return Left(falla);
    return Right([
      for (final e in espacios)
        if (e.ubicacionId == ubicacionId && (incluirBajas || !e.estaBorrada)) e,
    ]);
  }

  @override
  Future<Either<Failure, int>> contarActivos(String ubicacionId) async =>
      Right(activos.where((e) => e.ubicacionId == ubicacionId).length);
}
