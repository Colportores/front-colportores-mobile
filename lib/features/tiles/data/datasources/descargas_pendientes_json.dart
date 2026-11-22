import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/descarga_pendiente.dart';
import '../models/descarga_pendiente_model.dart';
import 'paquetes_tiles_data_sources.dart';

/// [DescargasPendientesLocalDataSource] con un manifiesto JSON (`descargas_pendientes.json`) junto
/// a `registro.json`, en [_directorio] (decisión de Cristian, 07/10, «Tras cierre»): no es un dato
/// sensible, no necesita la DB cifrada y no obliga a migrar Drift.
///
/// Igual que el registro de los descargados, la escritura es atómica (`.tmp` y `rename`: un corte
/// nunca lo deja a medias) y las operaciones corren de a una. Un manifiesto que no se puede leer
/// cuenta como vacío (y queda en el log): las descargas que nombraba se olvidan y el colportor las
/// pide de nuevo; el `.part` que quedó se limpia a los 7 días. Una entrada ilegible se descarta
/// sola, sin perder las demás.
final class DescargasPendientesJson implements DescargasPendientesLocalDataSource {
  DescargasPendientesJson(this._directorio, {AppLogger? logger})
    : _logger = logger ?? AppLogger.instance;

  final Directory _directorio;
  final AppLogger _logger;

  static const nombreArchivo = 'descargas_pendientes.json';
  static const _version = 1;

  var _turno = Future<void>.value();

  File get _archivo => File(p.join(_directorio.path, nombreArchivo));

  @override
  Future<List<DescargaPendiente>> leer() => _enTurno(_leerLista);

  @override
  Future<void> guardar(DescargaPendiente pendiente) {
    return _enTurno(() async {
      final lista = await _leerLista();
      final i = lista.indexWhere((d) => d.id == pendiente.id);
      if (i < 0) {
        lista.add(pendiente);
      } else {
        lista[i] = pendiente;
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

  Future<List<DescargaPendiente>> _leerLista() async {
    final archivo = _archivo;
    if (!await archivo.exists()) return [];
    final List<dynamic> entradas;
    try {
      final raiz = jsonDecode(await archivo.readAsString());
      if (raiz is! Map<String, dynamic> || raiz['descargas'] is! List<dynamic>) {
        throw const FormatException('manifiesto sin descargas');
      }
      entradas = raiz['descargas'] as List<dynamic>;
    } on FormatException catch (e) {
      _logger.warn(LogModulo.map, 'pendientes', 'manifiesto ilegible', {'motivo': e.message});
      return [];
    }
    final lista = <DescargaPendiente>[];
    for (final entrada in entradas) {
      try {
        lista.add(DescargaPendienteModel.desdeJson(entrada));
      } on FormatException catch (e) {
        _logger.warn(LogModulo.map, 'pendientes', 'entrada ilegible', {'motivo': e.message});
      }
    }
    return lista;
  }

  Future<void> _escribir(List<DescargaPendiente> lista) async {
    await _directorio.create(recursive: true);
    final texto = jsonEncode({
      'version': _version,
      'descargas': [for (final d in lista) DescargaPendienteModel.aJson(d)],
    });
    final temporal = File('${_archivo.path}.tmp');
    await temporal.writeAsString(texto, flush: true);
    await temporal.rename(_archivo.path);
  }
}
