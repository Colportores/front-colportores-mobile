import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../../domain/repositories/paquetes_tiles_repository.dart';
import '../../domain/services/puertos_descarga.dart';
import '../datasources/paquetes_tiles_data_sources.dart';

/// [PaquetesTilesRepository] sobre el catálogo remoto y el registro local de descargados.
///
/// Un paquete registrado cuyo `.pmtiles` ya no está (lo borró el sistema, por ejemplo) no se
/// informa: el mapa no lo podría abrir. Los logs `[MAP]` llevan solo ids de paquete.
final class PaquetesTilesRepositoryImpl implements PaquetesTilesRepository {
  PaquetesTilesRepositoryImpl({
    required this._catalogo,
    required this._registro,
    required this._archivos,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger.instance;

  final CatalogoPaquetesTilesRemoteDataSource _catalogo;
  final RegistroPaquetesDescargadosLocalDataSource _registro;
  final ArchivosTiles _archivos;
  final AppLogger _logger;

  /// Avisa a los que observan que el registro cambió.
  final _avisos = StreamController<void>.broadcast();

  @override
  Future<Either<Failure, List<PaqueteTiles>>> catalogo() async {
    try {
      return Right(await _catalogo.listar());
    } on ErrorRedTiles {
      return const Left(FailureSinConexion());
    } on ErrorServidorTiles catch (e) {
      _logger.warn(LogModulo.map, 'catalogo', 'catálogo rechazado', {'status': e.status});
      return Left(FailureServidor(status: e.status));
    } on Object catch (e, st) {
      _logger.error(LogModulo.map, 'catalogo', 'no se pudo leer el catálogo', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, List<PaqueteDescargado>>> descargados() async {
    try {
      return Right(await _vigentes());
    } on Object catch (e, st) {
      _logger.error(LogModulo.map, 'descargados', 'no se pudo leer el registro', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  /// Emite la lista al suscribirse y la relee con cada cambio del registro, en orden. Si no se
  /// puede leer emite una lista vacía (ya quedó el log): el mapa cae al online.
  @override
  Stream<List<PaqueteDescargado>> observarDescargados() {
    final salida = StreamController<List<PaqueteDescargado>>();
    StreamSubscription<void>? avisos;
    var cola = Future<void>.value();
    void releer() {
      cola = cola.then((_) async {
        final lista = (await descargados()).getOrElse(() => const []);
        if (!salida.isClosed) salida.add(lista);
      });
    }

    salida
      ..onListen = () {
        avisos = _avisos.stream.listen((_) => releer());
        releer();
      }
      ..onCancel = () async {
        await avisos?.cancel();
        await cola;
      };
    return salida.stream;
  }

  @override
  Future<Either<Failure, Unit>> registrar(PaqueteDescargado descargado) {
    return _escribir('registrar', descargado.id, () => _registro.guardar(descargado));
  }

  @override
  Future<Either<Failure, Unit>> quitar(String paqueteId) {
    return _escribir('quitar', paqueteId, () => _registro.quitar(paqueteId));
  }

  Future<Either<Failure, Unit>> _escribir(
    String op,
    String paqueteId,
    Future<void> Function() escritura,
  ) async {
    final contexto = {'paquete': paqueteId};
    try {
      await escritura();
    } on Object catch (e, st) {
      _logger.error(LogModulo.map, op, 'no se pudo escribir el registro', contexto, e, st);
      return Left(FailureInesperado(causa: e));
    }
    _logger.info(LogModulo.map, op, 'registro de paquetes actualizado', contexto);
    _avisos.add(null);
    return const Right(unit);
  }

  /// Los registrados cuyo `.pmtiles` sigue en el teléfono.
  Future<List<PaqueteDescargado>> _vigentes() async {
    final vigentes = <PaqueteDescargado>[];
    for (final descargado in await _registro.leer()) {
      if (await _archivos.existe(descargado.ruta)) {
        vigentes.add(descargado);
      } else {
        _logger.warn(LogModulo.map, 'descargados', 'falta el archivo', {'paquete': descargado.id});
      }
    }
    return vigentes;
  }
}
