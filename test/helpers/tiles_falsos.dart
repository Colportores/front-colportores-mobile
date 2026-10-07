// Fakes de los puertos de la descarga de tiles (HU-SYNC-010): sin red, disco ni HTTP reales.
import 'dart:async';
import 'dart:math';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/repositories/paquetes_tiles_repository.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:crypto/crypto.dart' as crypto;
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

  /// Qué informan las lecturas después de la primera (el disco se llenó mientras bajaba); `null`
  /// sigue informando [libres].
  int? libresDespuesDeLaPrimera;

  /// Las lecturas después de la primera lanzan (la plataforma no contesta).
  bool lanzaDespuesDeLaPrimera = false;

  int _lecturas = 0;

  @override
  Future<int> bytesLibres() async {
    if (_lecturas++ == 0) return libres;
    if (lanzaDespuesDeLaPrimera) throw StateError('la plataforma no contesta');
    return libresDespuesDeLaPrimera ?? libres;
  }
}

/// Archivos en memoria: los bytes de cada ruta. Escribe al momento, sin buffer.
///
/// - [modificados]: cuándo se tocó cada archivo (`listar`); lo que no figura es de [ahora].
/// - [discoLlenoDespuesDe]: cuántos bytes en total aceptan las escrituras antes de lanzar
///   [ErrorEspacioTiles] (un disco que se llena a mitad de la descarga).
/// - [fallaAlBorrar]: `borrar` lanza (un disco de solo lectura).
/// - [compuerta]: si no es null, cada `agregar` espera a que se complete (un disco lento, para
///   probar que la descarga no pide más bytes mientras el pedazo anterior no salió).
final class ArchivosEnMemoria implements ArchivosTiles {
  final contenido = <String, List<int>>{};
  final modificados = <String, DateTime>{};
  final borrados = <String>[];
  DateTime ahora = DateTime(2026, 10, 7, 12);
  int? discoLlenoDespuesDe;
  Future<void>? compuerta;

  /// Un disco de solo lectura: `borrar` lanza.
  bool fallaAlBorrar = false;

  /// Cuántos pedazos llegaron a `agregar`, de todos los archivos.
  int pedazosEscritos = 0;

  int get _total => contenido.values.fold(0, (suma, bytes) => suma + bytes.length);

  @override
  String rutaParcial(String clave) => '/tiles/$clave.pmtiles.part';

  @override
  String rutaFinal(String clave) => '/tiles/$clave.pmtiles';

  @override
  Future<int> tamano(String ruta) async => contenido[ruta]?.length ?? 0;

  @override
  Future<bool> existe(String ruta) async => contenido.containsKey(ruta);

  @override
  Future<EscrituraArchivo> abrir(String ruta, {required bool anexar}) async {
    final bytes = [if (anexar) ...?contenido[ruta]];
    contenido[ruta] = bytes;
    modificados[ruta] = ahora;
    return _EscrituraEnMemoria(this, bytes);
  }

  @override
  Future<void> renombrar(String desde, String hasta) async {
    contenido[hasta] = contenido.remove(desde) ?? (throw StateError('no existe $desde'));
    modificados[hasta] = modificados.remove(desde) ?? ahora;
  }

  @override
  Future<void> borrar(String ruta) async {
    if (fallaAlBorrar) throw StateError('solo lectura');
    if (contenido.remove(ruta) != null) borrados.add(ruta);
    modificados.remove(ruta);
  }

  @override
  Future<List<ArchivoTiles>> listar() async {
    return [
      for (final MapEntry(key: ruta, value: bytes) in contenido.entries)
        if (ruta.endsWith(ArchivoTiles.extensionFinal) ||
            ruta.endsWith(ArchivoTiles.extensionParcial))
          ArchivoTiles(
            nombre: ruta.split('/').last,
            ruta: ruta,
            bytes: bytes.length,
            modificado: modificados[ruta] ?? ahora,
          ),
    ];
  }
}

final class _EscrituraEnMemoria implements EscrituraArchivo {
  _EscrituraEnMemoria(this._archivos, this._bytes);

  final ArchivosEnMemoria _archivos;
  final List<int> _bytes;

  @override
  Future<void> agregar(List<int> bytes) async {
    _archivos.pedazosEscritos++;
    final espera = _archivos.compuerta;
    if (espera != null) await espera;
    final tope = _archivos.discoLlenoDespuesDe;
    if (tope != null && _archivos._total + bytes.length > tope) throw const ErrorEspacioTiles();
    _bytes.addAll(bytes);
  }

  @override
  Future<void> cerrar() async {}
}

/// El SHA-256 real de [bytes] en hex minúscula: lo mismo que publica el catálogo.
String checksumDe(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Calcula el SHA-256 real de lo que hay en [ArchivosEnMemoria].
final class ChecksumFalso implements CalculadorChecksum {
  ChecksumFalso(this._archivos);

  final ArchivosEnMemoria _archivos;

  @override
  Future<String> calcular(String ruta) async => checksumDe(_archivos.contenido[ruta] ?? const []);
}

/// Servidor de paquetes: responde 206 desde el byte pedido, o 200 con todo si ![soportaRange].
///
/// - [cortarDespuesDe]: el próximo cuerpo manda esos bytes y se corta con [ErrorRedTiles].
/// - [retenerDespuesDe]: el próximo cuerpo manda esos bytes y queda abierto (una descarga
///   colgada, para pausarla); el test lo maneja con [abierto].
/// - [rechazarRango]: responde 416 a todo pedido desde un byte mayor que 0.
/// - [corrimiento]: el 206 dice empezar en `desde + corrimiento` (otro rango que el pedido).
/// - [soloEnOrigen]: [cortarDespuesDe] y [retenerDespuesDe] valen solo para ese archivo (la
///   segunda parte de un paquete); los pedidos de otro no los consumen.
/// - [cancelaEnLaZonaActual]: para los tests bajo `fakeAsync`; ver [_CuerpoQueCancelaEnLaZona].
final class ServidorFalso implements ClienteDescargaRango {
  final archivos = <Uri, List<int>>{};

  /// Desde qué byte se pidió, en orden.
  final pedidos = <int>[];

  /// Qué archivo se pidió, en orden.
  final origenes = <Uri>[];
  bool soportaRange = true;
  bool sinRed = false;
  bool rechazarRango = false;
  int? statusError;
  int? cortarDespuesDe;
  int? retenerDespuesDe;
  int corrimiento = 0;
  int tamanoPedazo = 1000;
  Uri? soloEnOrigen;

  /// Si no es null, `pedir` espera a que se complete antes de contestar: el servidor que tarda en
  /// mandar los encabezados (la descarga ya aceptada pero todavía sin ningún byte).
  Completer<void>? esperaAntesDeContestar;

  /// Bajo `fakeAsync` (o `testWidgets`), `await suscripcion.cancel()` de un `StreamController` no
  /// vuelve nunca: devuelve un `Future` de la zona raíz y su continuación queda en el reloj real.
  /// Con esto el cuerpo avisa el cancelado con un `Future` de la zona del que cancela.
  bool cancelaEnLaZonaActual = false;

  /// Cuerpos cuya suscripción se canceló (el test que lo mira no deja llegar ninguno al final).
  int cancelados = 0;

  /// Bytes de más que agrega al final del cuerpo (un servidor que manda otra cosa).
  int sobrante = 0;
  StreamController<List<int>>? abierto;

  @override
  Future<RespuestaDescarga> pedir(Uri origen, {required int desde}) async {
    pedidos.add(desde);
    origenes.add(origen);
    await esperaAntesDeContestar?.future;
    if (sinRed) throw const ErrorRedTiles();
    if (statusError case final status?) throw ErrorServidorTiles(status);
    if (rechazarRango && desde > 0) throw const ErrorServidorTiles(416);
    final archivo = archivos[origen];
    if (archivo == null) throw const ErrorServidorTiles(404);
    final inicio = soportaRange ? desde : 0;
    final resto = [...archivo.sublist(inicio), ...List.filled(sobrante, 7)];
    final dice = soportaRange ? desde + corrimiento : 0;
    return RespuestaDescarga(desde: dice, bytes: _cuerpo(resto, origen));
  }

  Stream<List<int>> _cuerpo(List<int> resto, Uri origen) {
    final cuerpo = StreamController<List<int>>(
      onCancel: () {
        cancelados++;
      },
    );
    final aplica = soloEnOrigen == null || soloEnOrigen == origen;
    final corte = aplica ? cortarDespuesDe : null;
    final retener = aplica ? retenerDespuesDe : null;
    if (aplica) {
      cortarDespuesDe = null;
      retenerDespuesDe = null;
    }
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
    return cancelaEnLaZonaActual ? _CuerpoQueCancelaEnLaZona(cuerpo.stream) : cuerpo.stream;
  }
}

/// Un cuerpo cuya suscripción se cancela con un `Future` de la zona actual (ver
/// [ServidorFalso.cancelaEnLaZonaActual]); ignora lo que tarde el cancelado del cuerpo de origen.
final class _CuerpoQueCancelaEnLaZona extends Stream<List<int>> {
  _CuerpoQueCancelaEnLaZona(this._origen);

  final Stream<List<int>> _origen;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final real = _origen.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _SuscripcionQueCancelaEnLaZona(real);
  }
}

final class _SuscripcionQueCancelaEnLaZona implements StreamSubscription<List<int>> {
  _SuscripcionQueCancelaEnLaZona(this._real);

  final StreamSubscription<List<int>> _real;

  @override
  Future<void> cancel() {
    unawaited(_real.cancel());
    return Future<void>.value();
  }

  @override
  void onData(void Function(List<int> data)? handleData) => _real.onData(handleData);

  @override
  void onError(Function? handleError) => _real.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _real.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _real.pause(resumeSignal);

  @override
  void resume() => _real.resume();

  @override
  bool get isPaused => _real.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _real.asFuture(futureValue);
}

/// Repositorio en memoria para los tests de dominio.
final class RepositorioTilesEnMemoria implements PaquetesTilesRepository {
  List<PaqueteTiles> paquetesCatalogo = [];
  Failure? falloCatalogo;
  Failure? falloDescargados;
  Failure? falloRegistrar;
  Failure? falloQuitar;
  int reconciliaciones = 0;
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

  /// Con `StreamController` y no `async*`: cancelar un `async*` parado en un `await for` sin
  /// eventos espera al próximo `yield`, que nunca llega, y el test se cuelga.
  @override
  Stream<List<PaqueteDescargado>> observarDescargados() {
    final salida = StreamController<List<PaqueteDescargado>>();
    StreamSubscription<void>? avisos;
    salida
      ..onListen = () {
        salida.add(registrados);
        avisos = _avisos.stream.listen((_) => salida.add(registrados));
      }
      ..onCancel = () => avisos?.cancel();
    return salida.stream;
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
    final fallo = falloQuitar;
    if (fallo != null) return Left(fallo);
    _descargados.remove(paqueteId);
    _avisos.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> reconciliar() async {
    reconciliaciones++;
    return const Right(unit);
  }
}

/// Bytes de prueba de [largo] (no todos iguales, para que un corrimiento cambie el checksum).
/// Con [semilla] distinta salen otros: sirve para las partes de un mismo paquete.
List<int> bytesDePrueba(int largo, {int semilla = 5}) => [
  for (var i = 0; i < largo; i++) (i * 13 + semilla) % 251,
];

/// Un paquete de una sola parte con esos [bytes]: tamaño y SHA-256 salen de ellos (salvo que se
/// pase [sha256]). Se baja de `https://tiles.test/<id>.pmtiles`.
PaqueteTiles paqueteDe(
  List<int> bytes, {
  String id = 'zona-centro',
  NivelCobertura nivel = NivelCobertura.zona,
  String? ambitoId = 'z-1',
  String? sha256,
  String? version,
}) {
  return paqueteEnPartes(
    [bytes],
    id: id,
    nivel: nivel,
    ambitoId: ambitoId,
    sha256: sha256,
    version: version,
  );
}

/// Un paquete con una parte por cada lista de [partes] (una ciudad grande, en dos archivos). Se
/// baja de `https://tiles.test/<id>-p<n>.pmtiles`, o de `<id>.pmtiles` si es una sola. [sha256]
/// reemplaza el SHA-256 de la primera parte y [shaDeLaParte] el de las partes que nombra.
PaqueteTiles paqueteEnPartes(
  List<List<int>> partes, {
  String id = 'ciudad-montevideo',
  NivelCobertura nivel = NivelCobertura.ciudad,
  String? ambitoId = 'c-1',
  String? sha256,
  Map<int, String> shaDeLaParte = const {},
  String? version,
}) {
  final hashes = [for (final bytes in partes) checksumDe(bytes)];
  if (sha256 != null) hashes[0] = sha256;
  shaDeLaParte.forEach((parte, sha) => hashes[parte] = sha);
  return PaqueteTiles(
    id: id,
    nivel: nivel,
    ambitoId: ambitoId,
    nombre: 'Centro',
    version:
        version ?? (hashes.length == 1 ? hashes.first : checksumDe(hashes.join('\n').codeUnits)),
    partes: [
      for (var i = 0; i < partes.length; i++)
        ParteTiles(
          origen: Uri.parse(
            partes.length == 1
                ? 'https://tiles.test/$id.pmtiles'
                : 'https://tiles.test/$id-p${i + 1}.pmtiles',
          ),
          tamanoBytes: partes[i].length,
          sha256: hashes[i],
        ),
    ],
  );
}

/// El paquete tal como lo deja la descarga: una ruta final por parte.
PaqueteDescargado descargadoDe(PaqueteTiles paquete) {
  return PaqueteDescargado(
    paquete: paquete,
    rutas: [for (var i = 0; i < paquete.partes.length; i++) rutaFinalDe(paquete, i)],
  );
}

String rutaFinalDe(PaqueteTiles paquete, int parte) =>
    '/tiles/${paquete.claveDeParte(parte)}.pmtiles';

String rutaParcialDe(PaqueteTiles paquete, int parte) =>
    '/tiles/${paquete.claveDeParte(parte)}.pmtiles.part';

/// Lo que se baja de la primera parte (los paquetes de una sola parte).
extension PaqueteDePrueba on PaqueteTiles {
  Uri get origen => partes.first.origen;
}
