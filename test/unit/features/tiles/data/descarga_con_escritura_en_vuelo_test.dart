// Pausar, eliminar, cerrar o perder la conexión MIENTRAS se escribe un pedazo (HU-SYNC-010, #189).
//
// Con los archivos del disco de verdad (`ArchivosTilesIo`): ahí el pedazo en vuelo es un `flush` real
// pendiente, y cerrar el archivo en ese momento lanzaba «Bad state: StreamSink is bound to a
// stream». Con los archivos en memoria (que escriben al momento) el problema no se ve. Lo único
// falso es el servidor, la conexión, el espacio y el repositorio.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/archivos_tiles_io.dart';
import 'package:colportores_mobile/features/tiles/data/services/calculador_checksum_sha256.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/descargador_paquetes_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../../helpers/tiles_falsos.dart';

/// Los archivos reales, avisando cuando el primer pedazo ya salió hacia el disco (sin esperar a que
/// termine de escribirse): ese es el momento en que el test pausa, elimina o corta la conexión.
final class _ArchivosQueAvisan implements ArchivosTiles {
  _ArchivosQueAvisan(this._real);

  final ArchivosTilesIo _real;

  /// Se completa cuando el primer pedazo está en vuelo.
  final primerPedazoEnVuelo = Completer<void>();

  @override
  String rutaParcial(String clave) => _real.rutaParcial(clave);

  @override
  String rutaFinal(String clave) => _real.rutaFinal(clave);

  @override
  Future<int> tamano(String ruta) => _real.tamano(ruta);

  @override
  Future<bool> existe(String ruta) => _real.existe(ruta);

  @override
  Future<EscrituraArchivo> abrir(String ruta, {required bool anexar}) async {
    return _EscrituraQueAvisa(await _real.abrir(ruta, anexar: anexar), this);
  }

  @override
  Future<void> renombrar(String desde, String hasta) => _real.renombrar(desde, hasta);

  @override
  Future<void> borrar(String ruta) => _real.borrar(ruta);

  @override
  Future<List<ArchivoTiles>> listar() => _real.listar();
}

final class _EscrituraQueAvisa implements EscrituraArchivo {
  _EscrituraQueAvisa(this._real, this._avisador);

  final EscrituraArchivo _real;
  final _ArchivosQueAvisan _avisador;

  @override
  Future<void> agregar(List<int> bytes) {
    final escritura = _real.agregar(bytes);
    if (!_avisador.primerPedazoEnVuelo.isCompleted) _avisador.primerPedazoEnVuelo.complete();
    return escritura;
  }

  @override
  Future<void> cerrar() => _real.cerrar();
}

void main() {
  const pedazo = 1 << 20;

  late Directory temporal;
  late Directory directorio;
  late _ArchivosQueAvisan archivos;
  late ServidorFalso servidor;
  late ConectividadFalsa conectividad;
  late RepositorioTilesEnMemoria repositorio;
  late DescargadorPaquetesTiles descargador;
  late List<int> bytes;
  late PaqueteTiles paquete;
  late List<EstadoDescarga> estados;

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('descarga_en_vuelo_');
    directorio = Directory(p.join(temporal.path, 'tiles'));
    archivos = _ArchivosQueAvisan(ArchivosTilesIo(directorio));
    bytes = bytesDePrueba(3 * pedazo);
    paquete = paqueteDe(bytes, id: 'ciudad-montevideo', nivel: NivelCobertura.ciudad);
    servidor = ServidorFalso()
      ..tamanoPedazo = pedazo
      ..archivos[paquete.partes.first.origen] = bytes;
    conectividad = ConectividadFalsa();
    repositorio = RepositorioTilesEnMemoria();
    descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: EspacioFalso(),
      cliente: servidor,
      archivos: archivos,
      checksum: const CalculadorChecksumSha256(),
      repository: repositorio,
    );
    estados = [];
    descargador.cambios.listen(estados.add);
  });

  tearDown(() async {
    await descargador.cerrar();
    await temporal.delete(recursive: true);
  });

  /// Arranca la descarga y deja pasar hasta que el primer pedazo esté en vuelo hacia el disco.
  Future<void> bajarHastaEscribirElPrimerPedazo() async {
    final resultado = await descargador.descargar(paquete);
    expect(resultado.isRight(), isTrue, reason: '$resultado');
    await archivos.primerPedazoEnVuelo.future;
  }

  /// Espera a que el intento en curso termine de verdad: ahí la pausa ya está emitida. Una pérdida de
  /// conexión corta la bajada, pero la pausa se emite recién cuando el `.part` termina de cerrarse,
  /// y eso es I/O real: lo que tarda depende del disco, así que no se espera por un número fijo de
  /// vueltas del bucle de eventos (con un disco lento el estado seguía en curso: intermitente en CI).
  Future<void> enPausa() async {
    await descargador.esperar(paquete.id);
    // Los eventos de `cambios` ya salieron: la lista `estados` los recibe en la vuelta siguiente.
    await pumpEventQueue();
  }

  void sinFallas() {
    expect(estados.whereType<DescargaFallida>(), isEmpty, reason: '$estados');
  }

  test('pausar con un pedazo en escritura deja la pausa del colportor, sin falla', () async {
    await bajarHastaEscribirElPrimerPedazo();

    await descargador.pausar(paquete.id);
    await pumpEventQueue();

    final estado = descargador.estadoDe(paquete.id);
    expect(estado, isA<DescargaPausada>());
    expect((estado! as DescargaPausada).motivo, MotivoPausa.usuario);
    sinFallas();
  });

  test(
    'pausada así, al reanudar sigue con Range desde lo que quedó en el disco y termina',
    () async {
      await bajarHastaEscribirElPrimerPedazo();
      await descargador.pausar(paquete.id);
      final enDisco = await archivos.tamano(archivos.rutaParcial(paquete.claveDeParte(0)));
      expect(enDisco, greaterThan(0));

      final resultado = await descargador.descargar(paquete);
      await descargador.esperar(paquete.id);

      expect(resultado.isRight(), isTrue, reason: '$resultado');
      expect(servidor.pedidos, [0, enDisco]);
      final estado = descargador.estadoDe(paquete.id);
      expect(estado, isA<DescargaCompletada>());
      final rutas = (estado! as DescargaCompletada).descargado.rutas;
      expect(await File(rutas.single).readAsBytes(), bytes);
      sinFallas();
    },
  );

  test(
    'perder el Wi-Fi con un pedazo en escritura la deja en cola, y vuelve sola al volver',
    () async {
      await bajarHastaEscribirElPrimerPedazo();

      conectividad.cambiarA(TipoConexion.sinConexion);
      await enPausa();

      final estado = descargador.estadoDe(paquete.id);
      expect(estado, isA<DescargaPausada>());
      expect((estado! as DescargaPausada).sigueSola, isTrue);
      sinFallas();

      conectividad.cambiarA(TipoConexion.wifi);
      await descargador.esperar(paquete.id);

      final fin = descargador.estadoDe(paquete.id);
      expect(fin, isA<DescargaCompletada>());
      expect(await File((fin! as DescargaCompletada).descargado.rutas.single).readAsBytes(), bytes);
      sinFallas();
    },
  );

  test('pasar a datos móviles sin permiso con un pedazo en escritura la pausa sin falla', () async {
    await bajarHastaEscribirElPrimerPedazo();

    conectividad.cambiarA(TipoConexion.datosMoviles);
    await enPausa();

    final estado = descargador.estadoDe(paquete.id);
    expect(estado, isA<DescargaPausada>());
    expect((estado! as DescargaPausada).motivo, MotivoPausa.sinWifi);
    sinFallas();
  });

  test('eliminar con un pedazo en escritura no emite falla y borra todo', () async {
    await bajarHastaEscribirElPrimerPedazo();

    final resultado = await descargador.eliminar(paquete.id);
    await pumpEventQueue();

    expect(resultado.isRight(), isTrue, reason: '$resultado');
    sinFallas();
    expect(estados.last, isA<DescargaEliminada>());
    expect(directorio.listSync().where((e) => e.path.contains('.pmtiles')), isEmpty);
  });

  test('cerrar el descargador con un pedazo en escritura no emite falla', () async {
    await bajarHastaEscribirElPrimerPedazo();

    await descargador.cerrar();
    await pumpEventQueue();

    sinFallas();
    final estado = descargador.estadoDe(paquete.id);
    expect(estado, isA<DescargaPausada>());
  });
}
