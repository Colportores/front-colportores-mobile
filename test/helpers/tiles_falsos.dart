// Fakes de los puertos de la descarga de tiles (HU-SYNC-010): sin red, disco ni HTTP reales.
import 'dart:async';
import 'dart:math';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/repositories/paquetes_tiles_repository.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart';

/// Conectividad que el test cambia con [cambiarA].
final class ConectividadFalsa implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;
  final _cambios = StreamController<TipoConexion>.broadcast(sync: true);

  void cambiarA(TipoConexion nueva) {
    tipo = nueva;
    _cambios.add(nueva);
  }

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => _cambios.stream;
}

final class EspacioFalso implements MedidorEspacioDisco {
  int libres = 1 << 40;

  @override
  Future<int> bytesLibres() async => libres;
}

/// Archivos en memoria: los bytes de cada ruta. Escribe al momento, sin buffer.
final class ArchivosEnMemoria implements ArchivosTiles {
  final contenido = <String, List<int>>{};

  @override
  String rutaParcial(String paqueteId) => '/tiles/$paqueteId.pmtiles.part';

  @override
  String rutaFinal(String paqueteId) => '/tiles/$paqueteId.pmtiles';

  @override
  Future<int> tamano(String ruta) async => contenido[ruta]?.length ?? 0;

  @override
  Future<bool> existe(String ruta) async => contenido.containsKey(ruta);

  @override
  Future<EscrituraArchivo> abrir(String ruta, {required bool anexar}) async {
    final bytes = [if (anexar) ...?contenido[ruta]];
    contenido[ruta] = bytes;
    return _EscrituraEnMemoria(bytes);
  }

  @override
  Future<void> renombrar(String desde, String hasta) async {
    contenido[hasta] = contenido.remove(desde) ?? (throw StateError('no existe $desde'));
  }

  @override
  Future<void> borrar(String ruta) async {
    contenido.remove(ruta);
  }
}

final class _EscrituraEnMemoria implements EscrituraArchivo {
  _EscrituraEnMemoria(this._bytes);

  final List<int> _bytes;

  @override
  void agregar(List<int> bytes) => _bytes.addAll(bytes);

  @override
  Future<void> cerrar() async {}
}

/// Checksum de juguete sobre [ArchivosEnMemoria]: distingue un archivo entero de uno cortado o
/// alterado, que es lo que importa en los tests.
final class ChecksumFalso implements CalculadorChecksum {
  ChecksumFalso(this._archivos);

  final ArchivosEnMemoria _archivos;

  @override
  Future<String> calcular(String ruta) async => checksumDe(_archivos.contenido[ruta] ?? const []);
}

String checksumDe(List<int> bytes) {
  var hash = 17;
  for (final b in bytes) {
    hash = (hash * 31 + b) & 0x3fffffff;
  }
  return '${bytes.length}:$hash';
}

/// Servidor de paquetes: responde 206 desde el byte pedido, o 200 con todo si ![soportaRange].
///
/// - [cortarDespuesDe]: el próximo cuerpo manda esos bytes y se corta con [ErrorRedTiles].
/// - [retenerDespuesDe]: el próximo cuerpo manda esos bytes y queda abierto (una descarga
///   colgada, para pausarla); el test lo maneja con [abierto].
final class ServidorFalso implements ClienteDescargaRango {
  final archivos = <Uri, List<int>>{};
  final pedidos = <int>[];
  bool soportaRange = true;
  bool sinRed = false;
  int? statusError;
  int? cortarDespuesDe;
  int? retenerDespuesDe;
  int tamanoPedazo = 1000;

  /// Bytes de más que agrega al final del cuerpo (un servidor que manda otra cosa).
  int sobrante = 0;
  StreamController<List<int>>? abierto;

  @override
  Future<RespuestaDescarga> pedir(Uri origen, {required int desde}) async {
    pedidos.add(desde);
    if (sinRed) throw const ErrorRedTiles();
    if (statusError case final status?) throw ErrorServidorTiles(status);
    final archivo = archivos[origen];
    if (archivo == null) throw const ErrorServidorTiles(404);
    final inicio = soportaRange ? desde : 0;
    final resto = [...archivo.sublist(inicio), ...List.filled(sobrante, 7)];
    return RespuestaDescarga(desde: inicio, bytes: _cuerpo(resto));
  }

  Stream<List<int>> _cuerpo(List<int> resto) {
    final cuerpo = StreamController<List<int>>();
    final corte = cortarDespuesDe;
    final retener = retenerDespuesDe;
    cortarDespuesDe = null;
    retenerDespuesDe = null;
    final hasta = min(corte ?? retener ?? resto.length, resto.length);
    for (var i = 0; i < hasta; i += tamanoPedazo) {
      cuerpo.add(resto.sublist(i, min(i + tamanoPedazo, hasta)));
    }
    if (retener != null) {
      abierto = cuerpo;
    } else {
      if (corte != null) cuerpo.addError(const ErrorRedTiles());
      unawaited(cuerpo.close());
    }
    return cuerpo.stream;
  }
}

/// Repositorio en memoria para los tests de dominio.
final class RepositorioTilesEnMemoria implements PaquetesTilesRepository {
  List<PaqueteTiles> paquetesCatalogo = [];
  Failure? falloCatalogo;
  Failure? falloDescargados;
  Failure? falloRegistrar;
  final _descargados = <String, PaqueteDescargado>{};
  final _avisos = StreamController<void>.broadcast(sync: true);

  List<PaqueteDescargado> get registrados => _descargados.values.toList();

  @override
  Future<Either<Failure, List<PaqueteTiles>>> catalogo() async {
    final fallo = falloCatalogo;
    return fallo == null ? Right(paquetesCatalogo) : Left(fallo);
  }

  @override
  Future<Either<Failure, List<PaqueteDescargado>>> descargados() async {
    final fallo = falloDescargados;
    return fallo == null ? Right(registrados) : Left(fallo);
  }

  @override
  Stream<List<PaqueteDescargado>> observarDescargados() async* {
    yield registrados;
    await for (final _ in _avisos.stream) {
      yield registrados;
    }
  }

  @override
  Future<Either<Failure, Unit>> registrar(PaqueteDescargado descargado) async {
    final fallo = falloRegistrar;
    if (fallo != null) return Left(fallo);
    _descargados[descargado.id] = descargado;
    _avisos.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> quitar(String paqueteId) async {
    _descargados.remove(paqueteId);
    _avisos.add(null);
    return const Right(unit);
  }
}

/// Bytes de prueba de [largo] (no todos iguales, para que un corrimiento cambie el checksum).
List<int> bytesDePrueba(int largo) => [for (var i = 0; i < largo; i++) (i * 13 + 5) % 251];

/// Un paquete con esos [bytes]: tamaño y checksum salen de ellos (salvo que se pase [checksum]).
PaqueteTiles paqueteDe(
  List<int> bytes, {
  String id = 'zona-centro',
  NivelCobertura nivel = NivelCobertura.zona,
  String? ambitoId = 'z-1',
  String? checksum,
}) {
  return PaqueteTiles(
    id: id,
    nivel: nivel,
    ambitoId: ambitoId,
    nombre: 'Centro',
    tamanoBytes: bytes.length,
    checksum: checksum ?? checksumDe(bytes),
    origen: Uri.parse('https://tiles.test/$id.pmtiles'),
  );
}
