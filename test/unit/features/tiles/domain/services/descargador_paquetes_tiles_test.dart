// Test de dominio: Dart puro, con los puertos falsos de test/helpers/tiles_falsos.dart.
import 'dart:async';

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
  final parcial = rutaParcialDe(paquete, 0);
  final destino = rutaFinalDe(paquete, 0);

  // Una ciudad en dos archivos, de 3 000 y 2 500 bytes.
  final primera = bytesDePrueba(3000);
  final segunda = bytesDePrueba(2500, semilla: 9);
  final ciudad = paqueteEnPartes([primera, segunda]);

  setUp(() {
    conectividad = ConectividadFalsa();
    espacio = EspacioFalso();
    servidor = ServidorFalso()
      ..archivos[paquete.origen] = bytes
      ..archivos[ciudad.partes[0].origen] = primera
      ..archivos[ciudad.partes[1].origen] = segunda;
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
  Future<Either<Failure, Unit>> descargar({
    PaqueteTiles? cual,
    bool datosMoviles = false,
    bool esperarConexion = false,
  }) async {
    final elegido = cual ?? paquete;
    final resultado = await descargador.descargar(
      elegido,
      permitirDatosMoviles: datosMoviles,
      esperarConexion: esperarConexion,
    );
    await descargador.esperar(elegido.id);
    await dejarCorrer();
    return resultado;
  }

  Future<void> esperarReanudacion([PaqueteTiles? cual]) async {
    await dejarCorrer();
    await descargador.esperar((cual ?? paquete).id);
    await dejarCorrer();
  }

  void expectCompleta() {
    expect(descargador.estadoDe(paquete.id), isA<DescargaCompletada>());
    expect(archivos.contenido[destino], bytes);
    expect(archivos.contenido.containsKey(parcial), isFalse);
    expect(repositorio.registrados, [descargadoDe(paquete)]);
  }

  void expectCiudadCompleta() {
    expect(descargador.estadoDe(ciudad.id), isA<DescargaCompletada>());
    expect(archivos.contenido[rutaFinalDe(ciudad, 0)], primera);
    expect(archivos.contenido[rutaFinalDe(ciudad, 1)], segunda);
    expect(archivos.contenido.keys.where((r) => r.endsWith('.part')), isEmpty);
    expect(repositorio.registrados, [descargadoDe(ciudad)]);
  }

  /// El paquete con otro tamaño declarado (para los chequeos de espacio).
  PaqueteTiles conTamano(PaqueteTiles original, int tamano) {
    final parte = original.partes.first;
    return PaqueteTiles(
      // `original.id` y no el `id` suelto: ese es la función identidad de dartz.
      id: original.id,
      nivel: original.nivel,
      ambitoId: original.ambitoId,
      nombre: original.nombre,
      version: original.version,
      partes: [ParteTiles(origen: parte.origen, tamanoBytes: tamano, sha256: parte.sha256)],
    );
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
      final grande = conTamano(paquete, 87 * 1000 * 1000 + 1);
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
      final grande = conTamano(paquete, 3 * 1000 * 1000);
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
      expect(descargador.estadoDe(paquete.id), isNull);
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
      final alterado = paqueteDe(bytes, sha256: '0' * 64);

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

    test(
      'dado que falló a mitad, el botón vuelve a habilitarse: descargar de nuevo completa',
      () async {
        servidor.statusError = 500;
        await descargar();
        servidor.statusError = null;

        expect(await descargar(), const Right<Failure, Unit>(unit));

        expectCompleta();
      },
    );

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

    test('dado un SHA-256 del catálogo en mayúsculas, lo compara normalizado', () async {
      final mayusculas = paqueteDe(bytes, sha256: checksumDe(bytes).toUpperCase());

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

    test('dado dos toques seguidos antes de que arranque la primera, baja una sola vez', () async {
      final primero = descargador.descargar(paquete);
      final segundo = descargador.descargar(paquete);

      expect(await primero, const Right<Failure, Unit>(unit));
      expect(await segundo, const Right<Failure, Unit>(unit));
      await esperarReanudacion();

      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado un paquete ya descargado, cuando lo descargo de nuevo (otra versión), lo baja otra '
        'vez y lo deja registrado', () async {
      await descargar();

      await descargar();

      expect(servidor.pedidos, [0, 0]);
      expectCompleta();
    });

    test('dado que el disco se llena a mitad, falla con «Espacio insuficiente», deja el .part y '
        'al liberar lugar sigue desde ahí', () async {
      archivos.discoLlenoDespuesDe = 2500;

      await descargar();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailureEspacioInsuficiente(megabytesRequeridos: 1)),
      );
      expect(archivos.contenido[parcial], bytes.sublist(0, 2000));
      archivos.discoLlenoDespuesDe = null;

      expect(await descargar(), const Right<Failure, Unit>(unit));

      expect(servidor.pedidos, [0, 2000]);
      expectCompleta();
    });

    test(
      'dado un disco lento, no pide más bytes hasta que el pedazo anterior salió al disco',
      () async {
        final gate = Completer<void>();
        archivos.compuerta = gate.future;
        await descargador.descargar(paquete);

        for (var i = 0; i < 5; i++) {
          await dejarCorrer();
        }

        expect(archivos.pedazosEscritos, 1);
        expect(archivos.contenido[parcial], isEmpty);
        gate.complete();
        await esperarReanudacion();
        expect(archivos.pedazosEscritos, 6);
        expectCompleta();
      },
    );
  });

  group('paquete en partes (una ciudad en dos archivos)', () {
    test('dado una ciudad en dos partes, las baja de a una en orden, valida cada una y recién al '
        'final las renombra y las registra juntas', () async {
      await descargar(cual: ciudad);

      expectCiudadCompleta();
      expect(servidor.origenes, [ciudad.partes[0].origen, ciudad.partes[1].origen]);
      expect(servidor.pedidos, [0, 0]);
      final progreso = estados.whereType<DescargaEnCurso>().map((e) => e.recibidos).toList();
      expect(progreso, [0, 1000, 2000, 3000, 3000, 4000, 5000, 5500]);
      expect(estados.whereType<DescargaEnCurso>().every((e) => e.total == 5500), isTrue);
      expect(estados.whereType<DescargaVerificando>(), hasLength(1));
    });

    test('dado que se corta la red en la segunda parte, queda en pausa con las dos partes '
        'guardadas y sigue solo con la segunda al volver', () async {
      servidor
        ..soloEnOrigen = ciudad.partes[1].origen
        ..cortarDespuesDe = 1000;

      await descargar(cual: ciudad);

      expect(
        descargador.estadoDe(ciudad.id),
        DescargaPausada(ciudad.id, motivo: MotivoPausa.sinConexion, recibidos: 4000, total: 5500),
      );
      expect(archivos.contenido[rutaParcialDe(ciudad, 0)], primera);
      expect(archivos.contenido[rutaParcialDe(ciudad, 1)], segunda.sublist(0, 1000));
      expect(repositorio.registrados, isEmpty);

      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion(ciudad);

      expect(servidor.pedidos, [0, 0, 1000]);
      expect(servidor.origenes.last, ciudad.partes[1].origen);
      expectCiudadCompleta();
    });

    test('dado que la segunda parte llega corrupta, falla con el aviso de paquete dañado, borra '
        'esa parte, no registra nada y no deja ninguna parte a medio renombrar', () async {
      final danada = paqueteEnPartes([primera, segunda], shaDeLaParte: {1: '1' * 64});
      servidor
        ..archivos[danada.partes[0].origen] = primera
        ..archivos[danada.partes[1].origen] = segunda;

      await descargador.descargar(danada);
      await descargador.esperar(danada.id);

      expect(
        descargador.estadoDe(danada.id),
        DescargaFallida(danada.id, const FailurePaqueteTilesCorrupto()),
      );
      expect(archivos.contenido.keys, [rutaParcialDe(danada, 0)]);
      expect(repositorio.registrados, isEmpty);
    });

    test('dado que la primera parte llega corrupta, no baja la segunda', () async {
      final danada = paqueteEnPartes([primera, segunda], sha256: '1' * 64);
      servidor
        ..archivos[danada.partes[0].origen] = primera
        ..archivos[danada.partes[1].origen] = segunda;

      await descargador.descargar(danada);
      await descargador.esperar(danada.id);

      expect(servidor.origenes, [danada.partes[0].origen]);
      expect(descargador.estadoDe(danada.id), isA<DescargaFallida>());
    });

    test(
      'dado que el espacio no alcanza para todas las partes, bloquea antes de bajar nada',
      () async {
        espacio.libres = 5000;

        final resultado = await descargador.descargar(ciudad);

        expect(
          resultado,
          const Left<Failure, Unit>(FailureEspacioInsuficiente(megabytesRequeridos: 1)),
        );
        expect(servidor.pedidos, isEmpty);
      },
    );

    test('dado que la primera parte ya está en disco, el espacio que se pide es solo el de lo que '
        'falta', () async {
      archivos.contenido[rutaParcialDe(ciudad, 0)] = [...primera];
      espacio.libres = 2500;

      expect(await descargar(cual: ciudad), const Right<Failure, Unit>(unit));

      expect(servidor.origenes, [ciudad.partes[1].origen]);
      expectCiudadCompleta();
    });
  });

  group('en cola: «Descargar mapa» y lo que baja la app sola', () {
    Iterable<DescargaPausada> pausas() => estados.whereType<DescargaPausada>();

    test('dado que no hay conexión, cuando toco «Descargar mapa», queda en cola sin error y, con '
        'la primera conexión que vuelve —aunque sean datos móviles—, descarga sola', () async {
      conectividad.tipo = TipoConexion.sinConexion;

      final resultado = await descargar(datosMoviles: true, esperarConexion: true);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.sinConexion, recibidos: 0, total: 5500),
      );
      expect(servidor.pedidos, isEmpty);

      conectividad.cambiarA(TipoConexion.datosMoviles);
      await esperarReanudacion();

      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado lo que baja la app sola (sin permiso de datos móviles), con datos móviles queda en '
        'cola esperando el Wi-Fi y no arranca hasta que lo hay', () async {
      conectividad.tipo = TipoConexion.datosMoviles;

      final resultado = await descargar(esperarConexion: true);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.sinWifi, recibidos: 0, total: 5500),
      );

      conectividad.cambiarA(TipoConexion.sinConexion);
      await esperarReanudacion();
      conectividad.cambiarA(TipoConexion.datosMoviles);
      await esperarReanudacion();
      expect(servidor.pedidos, isEmpty);

      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado que está en cola por la app, cuando el colportor toca «Descargar mapa» con datos '
        'móviles, arranca en el acto con el permiso', () async {
      conectividad.tipo = TipoConexion.datosMoviles;
      await descargar(esperarConexion: true);

      final resultado = await descargar(datosMoviles: true, esperarConexion: true);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado que ya está en cola, cuando toco «Descargar mapa» otra vez, no se encola otra: ni '
        'un estado nuevo ni un segundo pedido', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      await descargar(datosMoviles: true, esperarConexion: true);
      final antes = pausas().length;

      final otra = await descargar(datosMoviles: true, esperarConexion: true);
      final otraMas = await descargar(datosMoviles: true, esperarConexion: true);

      expect(otra, const Right<Failure, Unit>(unit));
      expect(otraMas, const Right<Failure, Unit>(unit));
      expect(pausas(), hasLength(antes));
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();
      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado que el colportor ya pidió «Descargar mapa», cuando la app vuelve a ofrecerlo sin '
        'permiso, no le quita el permiso de datos móviles', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      await descargar(datosMoviles: true, esperarConexion: true);
      await descargar(esperarConexion: true);

      conectividad.cambiarA(TipoConexion.datosMoviles);
      await esperarReanudacion();

      expect(servidor.pedidos, [0]);
      expectCompleta();
    });

    test('dado que la app dejó la descarga en cola esperando Wi-Fi, cuando el colportor la pausa, '
        'ya no sigue sola', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      await descargar(esperarConexion: true);

      await descargador.pausar(paquete.id);
      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      expect(servidor.pedidos, isEmpty);
      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.usuario, recibidos: 0, total: 5500),
      );
    });

    test('dado que en cola vuelve la conexión pero ya no hay espacio, falla con ese aviso y el '
        'colportor puede reintentar', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      await descargar(datosMoviles: true, esperarConexion: true);
      espacio.libres = 0;

      conectividad.cambiarA(TipoConexion.wifi);
      await esperarReanudacion();

      expect(
        descargador.estadoDe(paquete.id),
        DescargaFallida(paquete.id, const FailureEspacioInsuficiente(megabytesRequeridos: 1)),
      );
      espacio.libres = 1 << 40;
      expect(
        await descargar(datosMoviles: true, esperarConexion: true),
        isA<Right<Failure, Unit>>(),
      );
      expectCompleta();
    });

    test(
      'dado que la conexión vuelve y se va en seguida, sigue en cola esperando la próxima',
      () async {
        conectividad.tipo = TipoConexion.sinConexion;
        await descargar(esperarConexion: true);

        conectividad.cambiarA(TipoConexion.wifi);
        conectividad.tipo = TipoConexion.sinConexion;
        await esperarReanudacion();

        expect(servidor.pedidos, isEmpty);
        expect(descargador.estadoDe(paquete.id), isA<DescargaPausada>());
        conectividad.cambiarA(TipoConexion.wifi);
        await esperarReanudacion();
        expectCompleta();
      },
    );
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

    test(
      'dado que descargo con datos móviles autorizados y el Wi-Fi se va, sigue bajando',
      () async {
        servidor.retenerDespuesDe = 2000;
        await descargador.descargar(paquete, permitirDatosMoviles: true);
        await dejarCorrer();

        conectividad.cambiarA(TipoConexion.datosMoviles);
        await dejarCorrer();

        expect(descargador.estadoDe(paquete.id), isA<DescargaEnCurso>());
        await descargador.pausar(paquete.id);
      },
    );

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

    test('dado que toco «Descargar» y en seguida «Pausar», queda pausada sin bajar nada y se puede '
        'reanudar', () async {
      final arranque = descargador.descargar(paquete);
      final pausa = descargador.pausar(paquete.id);

      await arranque;
      await pausa;

      expect(
        descargador.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.usuario, recibidos: 0, total: 5500),
      );
      expect(servidor.pedidos, isEmpty);
      expect(await descargar(), const Right<Failure, Unit>(unit));
      expectCompleta();
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

    test(
      'dado que cierro el descargador con una descarga en curso, queda el .part y en pausa',
      () async {
        await arrancarColgada();

        await descargador.cerrar();

        expect(archivos.contenido[parcial], bytes.sublist(0, 2000));
        expect(
          descargador.estadoDe(paquete.id),
          DescargaPausada(paquete.id, motivo: MotivoPausa.usuario, recibidos: 2000, total: 5500),
        );
      },
    );
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

    test('dado un paquete en partes, borra las partes de todas las versiones y no toca los de '
        'otros paquetes con un id parecido', () async {
      await descargar(cual: ciudad);
      final vieja = '/tiles/${ciudad.id}-p1-0123456789ab.pmtiles';
      final viejaParcial = '/tiles/${ciudad.id}-p2-0123456789ab.pmtiles.part';
      final deOtro = '/tiles/${ciudad.id}-norte-p1-0123456789ab.pmtiles';
      final deOtraCiudad = '/tiles/${ciudad.id}2-p1-0123456789ab.pmtiles';
      archivos.contenido
        ..[vieja] = [1]
        ..[viejaParcial] = [1]
        ..[deOtro] = [1]
        ..[deOtraCiudad] = [1];

      final resultado = await descargador.eliminar(ciudad.id);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(archivos.contenido.keys, [deOtro, deOtraCiudad]);
      expect(repositorio.registrados, isEmpty);
    });

    test('dado que no se puede sacar del repositorio, no borra ningún archivo', () async {
      await descargar();
      repositorio.falloQuitar = const FailureInesperado(causa: 'registro');

      final resultado = await descargador.eliminar(paquete.id);

      expect(resultado, const Left<Failure, Unit>(FailureInesperado(causa: 'registro')));
      expect(archivos.contenido.containsKey(destino), isTrue);
    });
  });

  test('ErrorRedTiles, ErrorServidorTiles y ErrorEspacioTiles se describen en toString', () {
    expect(const ErrorRedTiles('x').toString(), 'ErrorRedTiles(x)');
    expect(const ErrorServidorTiles(416).toString(), 'ErrorServidorTiles(416)');
    expect(const ErrorEspacioTiles('lleno').toString(), 'ErrorEspacioTiles(lleno)');
  });

  test('ArchivoTiles distingue un .part de un .pmtiles', () {
    ArchivoTiles archivo(String nombre) {
      return ArchivoTiles(nombre: nombre, ruta: '/t/$nombre', bytes: 1, modificado: DateTime(2026));
    }

    expect(archivo('a-p1-abc.pmtiles').esFinal, isTrue);
    expect(archivo('a-p1-abc.pmtiles').esParcial, isFalse);
    expect(archivo('a-p1-abc.pmtiles.part').esParcial, isTrue);
    expect(archivo('a-p1-abc.pmtiles.part').esFinal, isFalse);
  });
}
