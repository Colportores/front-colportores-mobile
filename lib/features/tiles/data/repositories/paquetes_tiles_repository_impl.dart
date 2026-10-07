import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../../domain/repositories/paquetes_tiles_repository.dart';
import '../../domain/services/puertos_descarga.dart';
import '../datasources/paquetes_tiles_data_sources.dart';

/// [PaquetesTilesRepository] sobre el catálogo remoto y el registro local de descargados.
///
/// Un paquete registrado al que le falta un archivo (lo borró el sistema, por ejemplo) no se
/// informa: el mapa no lo podría abrir. Los logs `[MAP]` llevan solo ids de paquete.
final class PaquetesTilesRepositoryImpl implements PaquetesTilesRepository {
  PaquetesTilesRepositoryImpl({
    required this._catalogo,
    required this._registro,
    required this._archivos,
    required this._checksum,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _logger = logger ?? AppLogger.instance;

  /// Un `.pmtiles` sin registrar más nuevo que esto no se borra: puede ser uno que una descarga
  /// acaba de renombrar y todavía está por registrar.
  static const gracia = Duration(minutes: 10);

  /// Un `.part` más viejo que esto no se va a reanudar: el catálogo ya no nombra ese archivo (el
  /// bucket guarda los retirados 7 días).
  static const vigenciaParcial = Duration(days: 7);

  final CatalogoPaquetesTilesRemoteDataSource _catalogo;
  final RegistroPaquetesDescargadosLocalDataSource _registro;
  final ArchivosTiles _archivos;
  final CalculadorChecksum _checksum;
  final DateTime Function() _ahora;
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
    } on FormatException catch (e) {
      // El servidor contestó algo que no es un catálogo de esta versión del formato.
      _logger.warn(LogModulo.map, 'catalogo', 'catálogo ilegible', {'motivo': e.message});
      return const Left(FailureServidor());
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

  /// Anota el paquete y, ya anotado, borra los archivos de la versión anterior del mismo paquete
  /// (otro `sha12` en el nombre): ya nada los usa. Si el borrado falla, el paquete queda anotado
  /// igual y `reconciliar` limpia esos archivos la próxima vez.
  @override
  Future<Either<Failure, Unit>> registrar(PaqueteDescargado descargado) async {
    final previo = await _previo(descargado.id);
    final resultado = await _escribir(
      'registrar',
      descargado.id,
      () => _registro.guardar(descargado),
    );
    if (resultado.isLeft() || previo == null) return resultado;
    final nuevas = descargado.rutas.toSet();
    for (final ruta in previo.rutas.where((ruta) => !nuevas.contains(ruta))) {
      try {
        await _archivos.borrar(ruta);
      } on Object catch (e) {
        _logger.warn(LogModulo.map, 'registrar', 'no se pudo borrar la versión anterior', {
          'paquete': descargado.id,
          'error': e.runtimeType.toString(),
        });
      }
    }
    return resultado;
  }

  /// Lo que estaba anotado de [paqueteId] antes de registrar el nuevo; `null` si nada o si no se
  /// pudo leer (la escritura que sigue deja su propio log).
  Future<PaqueteDescargado?> _previo(String paqueteId) async {
    try {
      return (await _registro.leer()).where((d) => d.id == paqueteId).firstOrNull;
    } on Object {
      return null;
    }
  }

  @override
  Future<Either<Failure, Unit>> quitar(String paqueteId) {
    return _escribir('quitar', paqueteId, () => _registro.quitar(paqueteId));
  }

  @override
  Future<Either<Failure, Unit>> reconciliar() async {
    try {
      final registrados = await _registro.leer();
      final enUso = <String>{};
      var cambio = false;
      for (final registrado in registrados) {
        if (await _intacto(registrado)) {
          enUso.addAll(registrado.rutas.map(p.basename));
        } else {
          _logger.warn(LogModulo.map, 'reconciliar', 'paquete no válido: se trata como no bajado', {
            'paquete': registrado.id,
          });
          await _registro.quitar(registrado.id);
          cambio = true;
        }
      }
      final ahora = _ahora();
      for (final archivo in await _archivos.listar()) {
        if (enUso.contains(archivo.nombre)) continue;
        final edad = ahora.difference(archivo.modificado);
        final sobra = archivo.esParcial ? edad >= vigenciaParcial : edad >= gracia;
        if (sobra) await _archivos.borrar(archivo.ruta);
      }
      if (cambio) _avisos.add(null);
      return const Right(unit);
    } on Object catch (e, st) {
      _logger.error(LogModulo.map, 'reconciliar', 'no se pudo reconciliar', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
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

  /// Los registrados cuyos `.pmtiles` siguen todos en el teléfono.
  Future<List<PaqueteDescargado>> _vigentes() async {
    final vigentes = <PaqueteDescargado>[];
    for (final descargado in await _registro.leer()) {
      if (await _estanTodos(descargado)) {
        vigentes.add(descargado);
      } else {
        _logger.warn(LogModulo.map, 'descargados', 'falta el archivo', {'paquete': descargado.id});
      }
    }
    return vigentes;
  }

  Future<bool> _estanTodos(PaqueteDescargado descargado) async {
    if (descargado.rutas.length != descargado.paquete.partes.length) return false;
    for (final ruta in descargado.rutas) {
      if (!await _archivos.existe(ruta)) return false;
    }
    return true;
  }

  /// Cada archivo está, pesa lo que dice el catálogo con el que se bajó y tiene su checksum.
  Future<bool> _intacto(PaqueteDescargado descargado) async {
    if (!await _estanTodos(descargado)) return false;
    final partes = descargado.paquete.partes;
    for (var i = 0; i < partes.length; i++) {
      final ruta = descargado.rutas[i];
      if (await _archivos.tamano(ruta) != partes[i].tamanoBytes) return false;
      final calculado = await _checksum.calcular(ruta);
      if (calculado.toLowerCase() != partes[i].sha256.toLowerCase()) return false;
    }
    return true;
  }
}
