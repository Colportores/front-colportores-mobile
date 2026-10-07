import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../models/paquete_descargado_model.dart';
import 'paquetes_tiles_data_sources.dart';

/// [RegistroPaquetesDescargadosLocalDataSource] con un manifiesto JSON (`registro.json`) junto a
/// los `.pmtiles`, en [_directorio] (decisión d7 de #189): no es un dato sensible, no necesita la DB
/// cifrada y no obliga a migrar Drift.
///
/// La escritura es atómica: el manifiesto nuevo se escribe en `registro.json.tmp` y recién
/// entonces reemplaza al anterior con un `rename`, así un corte nunca lo deja a medias. Las
/// operaciones corren de a una (leer, cambiar y escribir no se pisan). Un manifiesto que no se puede
/// leer cuenta como vacío (y queda en el log): los paquetes que nombraba se tratan como no
/// descargados y `PaquetesTilesRepository.reconciliar` borra sus archivos.
final class RegistroPaquetesDescargadosJson implements RegistroPaquetesDescargadosLocalDataSource {
  RegistroPaquetesDescargadosJson(this._directorio, {AppLogger? logger})
    : _logger = logger ?? AppLogger.instance;

  final Directory _directorio;
  final AppLogger _logger;

  static const nombreArchivo = 'registro.json';
  static const _version = 1;

  var _turno = Future<void>.value();

  File get _archivo => File(p.join(_directorio.path, nombreArchivo));

  @override
  Future<List<PaqueteDescargado>> leer() => _enTurno(_leerLista);

  @override
  Future<void> guardar(PaqueteDescargado descargado) {
    return _enTurno(() async {
      final lista = await _leerLista();
      final i = lista.indexWhere((d) => d.id == descargado.id);
      if (i < 0) {
        lista.add(descargado);
      } else {
        lista[i] = descargado;
      }
      await _escribir(lista);
    });
  }

  @override
  Future<void> quitar(String paqueteId) {
    return _enTurno(() async {
      final lista = await _leerLista();
      final antes = lista.length;
      lista.removeWhere((d) => d.id == paqueteId);
      if (lista.length != antes) await _escribir(lista);
    });
  }

  Future<T> _enTurno<T>(Future<T> Function() tarea) {
    final resultado = _turno.then((_) => tarea());
    _turno = resultado.then((_) {}, onError: (Object _) {});
    return resultado;
  }

  Future<List<PaqueteDescargado>> _leerLista() async {
    final archivo = _archivo;
    if (!await archivo.exists()) return [];
    final List<dynamic> entradas;
    try {
      final raiz = jsonDecode(await archivo.readAsString());
      if (raiz is! Map<String, dynamic> || raiz['paquetes'] is! List<dynamic>) {
        throw const FormatException('manifiesto sin paquetes');
      }
      entradas = raiz['paquetes'] as List<dynamic>;
    } on FormatException catch (e) {
      _logger.warn(LogModulo.map, 'registro', 'manifiesto ilegible', {'motivo': e.message});
      return [];
    }
    final lista = <PaqueteDescargado>[];
    for (final entrada in entradas) {
      try {
        lista.add(PaqueteDescargadoModel.desdeJson(entrada, _directorio.path));
      } on FormatException catch (e) {
        _logger.warn(LogModulo.map, 'registro', 'entrada ilegible', {'motivo': e.message});
      }
    }
    return lista;
  }

  Future<void> _escribir(List<PaqueteDescargado> lista) async {
    await _directorio.create(recursive: true);
    final texto = jsonEncode({
      'version': _version,
      'paquetes': [for (final d in lista) PaqueteDescargadoModel.aJson(d)],
    });
    final temporal = File('${_archivo.path}.tmp');
    await temporal.writeAsString(texto, flush: true);
    await temporal.rename(_archivo.path);
  }
}
