// Test de dominio: Dart puro, con los puertos falsos de test/helpers/tiles_falsos.dart.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/descargador_paquetes_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  late ConectividadFalsa conectividad;
  late EspacioFalso espacio;
  late ServidorFalso servidor;
  late ArchivosEnMemoria archivos;
  late RepositorioTilesEnMemoria repositorio;
  late DescargadorPaquetesTiles descargador;
  late List<EstadoDescarga> estados;
  final bytes = bytesDePrueba(5500);
  final paquete = paqueteDe(bytes);
  final parcial = '/tiles/${paquete.id}.pmtiles.part';
  final destino = '/tiles/${paquete.id}.pmtiles';

  setUp(() {
    conectividad = ConectividadFalsa();
    espacio = EspacioFalso();
    servidor = ServidorFalso()..archivos[paquete.origen] = bytes;
    archivos = ArchivosEnMemoria();
    repositorio = RepositorioTilesEnMemoria();
    descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: espacio,
      cliente: servidor,
      archivos: archivos,
      checksum: ChecksumFalso(archivos),
      repository: repositorio,
    );
    estados = [];
    descargador.cambios.listen(estados.add);
  });

  tearDown(() => descargador.cerrar());

  /// Deja pasar los eventos de `cambios` y los intentos que arrancan solos (al volver la conexión).
  Future<void> dejarCorrer() => Future<void>.delayed(Duration.zero);

  /// Descarga y espera a que termine el intento.
  Future<Either<Failure, Unit>> descargar({bool datosMoviles = false}) async {
    final resultado = await descargador.descargar(paquete, permitirDatosMoviles: datosMoviles);
    await descargador.esperar(paquete.id);
    await dejarCorrer();
    return resultado;
  }

  Future<void> esperarReanudacion() async {
    await dejarCorrer();
    await descargador.esperar(paquete.id);
    await dejarCorrer();
  }

  void expectCompleta() {
    expect(descargador.estadoDe(paquete.id), isA<DescargaCompletada>());
    expect(archivos.contenido[destino], bytes);
    expect(archivos.contenido.containsKey(parcial), isFalse);
    expect(repositorio.registrados, [PaqueteDescargado(paquete: paquete, ruta: destino)]);
  }

  group('DescargadorPaquetesTiles — HU-SYNC-010', () {
    test('Escenario: Descarga exitosa — dado que estoy en Wi-Fi, cuando descargo, se descarga con '
        'progress, valida el checksum y queda disponible para el mapa', () async {
      final resultado = await descargar();

      expect(resultado, const Right<Failure, Unit>(unit));
      expectCompleta();
      expect(servidor.pedidos, [0]);
      final progreso = estados.whereType<DescargaEnCurso>().map((e) => e.recibidos).toList();
      expect(progreso, [0, 1000, 2000, 3000, 4000, 5000, 5500]);
      expect(estados.whereType<DescargaEnCurso>().last.progreso, 1);
      expect(estados[estados.length - 2], DescargaVerificando(paquete.id));
    });

    test('Escenario: Sin espacio — dado que el teléfono no tiene espacio, cuando intento '
        'descargar, bloquea con "Espacio insuficiente - se requieren X MB"', () async {
      final grande = paqueteDe(bytes).copiaConTamano(87 * 1000 * 1000 + 1);
      espacio.libres = 50 * 1000 * 1000;

      final resultado = await descargador.descargar(grande);

      final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(failure, const FailureEspacioInsuficiente(megabytesRequeridos: 88));
      expect(failure.mensaje, startsWith('Espacio insuficiente - se requieren 88 MB'));
      expect(servidor.pedidos, isEmpty);
      expect(descargador.estadoDe(paquete.id), isNull);
    });

    test('dado que hay un .part, cuando falta espacio, pide solo lo que falta bajar', () async {
      archivos.contenido[parcial] = bytes.sublist(0, 2000);
      final grande = paqueteDe(bytes).copiaConTamano(3 * 1000 * 1000);
      espacio.libres = 1000;

      final resultado = await descargador.descargar(grande);

      final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(failure, const FailureEspacioInsuficiente(megabytesRequeridos: 3));
      espacio.libres = 3500;
      expect(await descargar(), const Right<Failure, Unit>(unit));
      expect(servidor.pedidos, [2000]);
      expectCompleta();
    });

    test('dado que otra descarga está en curso, cuando chequea el espacio, descuenta lo que a esa '
        'le falta', () async {
      final otro = paqueteDe(bytesDePrueba(4000), id: 'ciudad-mvd');
      servidor
        ..archivos[otro.origen] = bytesDePrueba(4000)
        ..retenerDespuesDe = 1000;
      await descargador.descargar(otro);
      espacio.libres = 6000;

      final resultado = await descargador.descargar(paquete);

      expect(resultado.isLeft(), isTrue);
      await descargador.pausar(otro.id);
    });

    test('dado que estoy con datos móviles sin autorizarlos, cuando descargo, pide Wi-Fi y no baja '
        'nada', () async {
      conectividad.tipo = TipoConexion.datosMoviles;

      final resultado = await descargar();

      expect(resultado, const Left<Failure, Unit>(FailureDescargaRequiereWifi()));
      expect(servidor.pedidos, isEmpty);
    });

    test('dado que estoy con datos móviles, cuando los autorizo (override), descarga', () async {
      conectividad.tipo = TipoConexion.datosMoviles;

      expect(await descargar(datosMoviles: true), const Right<Failure, Unit>(unit));
      expectCompleta();
    });

    test('dado que no hay conexión, cuando descargo, devuelve FailureSinConexion', () async {
      conectividad.tipo = TipoConexion.sinConexion;

      expect(await descargar(), const Left<Failure, Unit>(FailureSinConexion()));
    });

    test('Escenario: Pausa y resume — dado que estoy descargando y pierdo Wi-Fi, cuando la '
        'conexión se restablece, la descarga retoma desde donde quedó (HTTP Range)', () async {
      servidor.cortarDespuesDe = 3000;

      await descargar();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.sinConexion, recibidos: 3000, total: 5500),
      );
      expect(archivos.contenido[parcial], bytes.sublist(0, 3000));
      expect(archivos.contenido.containsKey(destino), isFalse);
      expect(repositorio.registrados, isEmpty);

      conectividad.cambiarA(TipoConexion.sinConexion);
      await esperarReanudacion();
      expect(servidor.pedidos, [0]);
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      expect(servidor.pedidos, [0, 3000]);
      expectCompleta();
    });

    test('dado que el servidor no soporta Range (200 en vez de 206), cuando reanuda, reescribe el '
        '.part desde cero y el archivo queda entero', () async {
      servidor.cortarDespuesDe = 3000;
      await descargar();
      servidor.soportaRange = false;

      await descargar();

      expect(servidor.pedidos, [0, 3000]);
      expectCompleta();
    });

    test('dado que el checksum no coincide, cuando termina de bajar, '
        'borra el archivo y falla', () async {
      final alterado = paqueteDe(bytes, checksum: 'otro');

      await descargador.descargar(alterado);
      await descargador.esperar(alterado.id);

      expect(
        descargador.estadoDe(alterado.id),
        DescargaFallida(alterado.id, const FailurePaqueteTilesCorrupto()),
      );
      expect(archivos.contenido, isEmpty);
      expect(repositorio.registrados, isEmpty);
    });

    test('dado que el servidor manda de más, corta, borra el .part y falla', () async {
      servidor.sobrante = 10;

      await descargar();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailurePaqueteTilesCorrupto()),
      );
      expect(archivos.contenido, isEmpty);
    });

    test('dado un .part más grande que el paquete, lo descarta y baja desde cero', () async {
      archivos.contenido[parcial] = List.filled(6000, 1);

      await descargar();

      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado que el .part ya está entero, valida sin pedir nada al servidor', () async {
      archivos.contenido[parcial] = [...bytes];

      await descargar();

      expect(servidor.pedidos, isEmpty);
      expectCompleta();
    });

    test('dado que el servidor responde con error, falla con FailureServidor', () async {
      servidor.statusError = 500;

      await descargar();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailureServidor(status: 500)),
      );
    });

    test('dado un 206 con otro rango que el pedido, descarta el cuerpo y falla con '
        'FailureServidor', () async {
      servidor.corrimiento = 100;

      await descargar();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailureServidor(status: 206)),
      );
      expect(servidor.cancelados, 1);
      expect(archivos.contenido, isEmpty);
    });

    test('dado un 416 al reanudar, borra el .part y baja una vez más desde cero', () async {
      archivos.contenido[parcial] = List.filled(2000, 9);
      servidor.rechazarRango = true;

      await descargar();

      expect(servidor.pedidos, [2000, 0]);
      expectCompleta();
    });

    test('dado un checksum del catálogo en mayúsculas, lo compara normalizado', () async {
      final mayusculas = paqueteDe(bytes, checksum: checksumDe(bytes).toUpperCase());

      await descargador.descargar(mayusculas);
      await descargador.esperar(mayusculas.id);

      expect(descargador.estadoDe(mayusculas.id), isA<DescargaCompletada>());
    });

    test('dado que no se puede registrar, falla con ese Failure', () async {
      repositorio.falloRegistrar = const FailureInesperado(causa: 'disco');

      await descargar();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailureInesperado(causa: 'disco')),
      );
    });

    test('dado que la red no responde al pedir, queda en pausa esperando la conexión', () async {
      servidor.sinRed = true;

      await descargar();

      final estado = descargador.estadoDe(paquete.id);
      expect(estado, isA<DescargaPausada>().having((e) => e.sigueSola, 'sigueSola', isTrue));
    });

    test('dado que la descarga está en curso, cuando la pido otra vez, '
        'no hace otro pedido', () async {
      servidor.retenerDespuesDe = 1000;
      await descargador.descargar(paquete);

      expect(await descargador.descargar(paquete), const Right<Failure, Unit>(unit));
      expect(servidor.pedidos, [0]);
      await descargador.pausar(paquete.id);
    });
  });

  group('pausa', () {
    Future<void> arrancarColgada() async {
      servidor.retenerDespuesDe = 2000;
      await descargador.descargar(paquete);
      await dejarCorrer();
    }

    test('dado que pauso, deja el .part y no sigue sola al volver la conexión; sigue con '
        'descargar desde donde quedó', () async {
      await arrancarColgada();

      await descargador.pausar(paquete.id);

      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.usuario, recibidos: 2000, total: 5500),
      );
      expect(archivos.contenido[parcial], bytes.sublist(0, 2000));
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();
      expect(servidor.pedidos, [0]);

      await descargar();
      expect(servidor.pedidos, [0, 2000]);
      expectCompleta();
    });

    test('dado que se va el Wi-Fi sin datos móviles autorizados, '
        'pausa y sigue sola al volver', () async {
      await arrancarColgada();

      conectividad.cambiarA(TipoConexion.datosMoviles);
      await descargador.esperar(paquete.id);

      final estado = descargador.estadoDe(paquete.id);
      expect(estado, isA<DescargaPausada>().having((e) => e.motivo, 'motivo', MotivoPausa.sinWifi));
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();
      expect(servidor.pedidos, [0, 2000]);
      expectCompleta();
    });

    test('dado que pauso y en el mismo momento se va la red, la pausa sigue siendo mía y no se '
        'retoma sola al volver el Wi-Fi', () async {
      await arrancarColgada();

      final pausa = descargador.pausar(paquete.id);
      conectividad.cambiarA(TipoConexion.sinConexion);
      await pausa;
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.usuario, recibidos: 2000, total: 5500),
      );
      expect(servidor.pedidos, [0]);
    });

    test('dado que pausé una descarga que esperaba la conexión, ya no sigue sola', () async {
      servidor.cortarDespuesDe = 1000;
      await descargar();

      await descargador.pausar(paquete.id);
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      final estado = descargador.estadoDe(paquete.id);
      expect(estado, isA<DescargaPausada>().having((e) => e.sigueSola, 'sigueSola', isFalse));
      expect(servidor.pedidos, [0]);
    });

    test('dado que al volver la conexión ya no hay espacio, '
        'la descarga falla con ese aviso', () async {
      servidor.cortarDespuesDe = 1000;
      await descargar();
      espacio.libres = 0;

      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailureEspacioInsuficiente(megabytesRequeridos: 1)),
      );
    });

    test('dado que pido pausar un paquete que no se está descargando, no pasa nada', () async {
      await descargador.pausar('otro');

      expect(descargador.estadoDe('otro'), isNull);
    });
  });

  group('eliminar', () {
    test('dado un paquete descargado, lo saca del repositorio y borra el archivo', () async {
      await descargar();

      final resultado = await descargador.eliminar(paquete.id);
      await dejarCorrer();

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(archivos.contenido, isEmpty);
      expect(repositorio.registrados, isEmpty);
      expect(descargador.estadoDe(paquete.id), isNull);
      expect(estados.last, DescargaEliminada(paquete.id));
    });

    test('dado una descarga en curso, la corta y borra el .part', () async {
      servidor.retenerDespuesDe = 1000;
      await descargador.descargar(paquete);
      await dejarCorrer();

      await descargador.eliminar(paquete.id);

      expect(archivos.contenido, isEmpty);
      expect(descargador.estadoDe(paquete.id), isNull);
    });
  });

  test('ErrorRedTiles y ErrorServidorTiles se describen en toString', () {
    expect(const ErrorRedTiles('x').toString(), 'ErrorRedTiles(x)');
    expect(const ErrorServidorTiles(416).toString(), 'ErrorServidorTiles(416)');
  });
}

extension on PaqueteTiles {
  /// El mismo paquete con otro tamaño declarado (para los chequeos de espacio).
  PaqueteTiles copiaConTamano(int tamano) => PaqueteTiles(
    // `this.` porque el `id` suelto es la función identidad de dartz.
    id: this.id,
    nivel: nivel,
    ambitoId: ambitoId,
    nombre: nombre,
    tamanoBytes: tamano,
    checksum: checksum,
    origen: origen,
  );
}
