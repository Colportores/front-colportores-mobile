// Test de dominio: la descarga que sigue después de cerrar la app (HU-SYNC-010, #300). Un
// «reinicio» es un descargador nuevo sobre los mismos archivos y el mismo repositorio: lo que no
// sobrevive es lo que el descargador guarda en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/descarga_pendiente.dart';
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
  late DateTime ahora;
  late List<DescargadorPaquetesTiles> abiertos;
  late List<EstadoDescarga> estados;
  final bytes = bytesDePrueba(5500);
  final paquete = paqueteDe(bytes);
  final parcial = rutaParcialDe(paquete, 0);
  final desde = DateTime(2026, 10, 7, 12);

  /// Un descargador nuevo sobre lo que dejó el anterior: la app recién abierta.
  DescargadorPaquetesTiles abrirApp() {
    final descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: espacio,
      cliente: servidor,
      archivos: archivos,
      checksum: ChecksumFalso(archivos),
      repository: repositorio,
      ahora: () => ahora,
    );
    abiertos.add(descargador);
    estados = [];
    descargador.cambios.listen(estados.add);
    return descargador;
  }

  setUp(() {
    ahora = desde;
    conectividad = ConectividadFalsa();
    espacio = EspacioFalso();
    servidor = ServidorFalso()..archivos[paquete.origen] = bytes;
    archivos = ArchivosEnMemoria()..ahora = ahora;
    repositorio = RepositorioTilesEnMemoria();
    abiertos = [];
  });

  tearDown(() async {
    for (final descargador in abiertos) {
      await descargador.cerrar();
    }
  });

  /// Deja pasar los eventos de `cambios`, las escrituras de lo anotado y los intentos que
  /// arrancan solos.
  Future<void> dejarCorrer() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// La app se cierra: se corta lo que estaba bajando y el descargador se pierde.
  Future<void> cerrarApp(DescargadorPaquetesTiles descargador) async {
    await dejarCorrer();
    await descargador.cerrar();
  }

  Future<void> terminar(DescargadorPaquetesTiles descargador, PaqueteTiles cual) async {
    await dejarCorrer();
    await descargador.esperar(cual.id);
    await dejarCorrer();
  }

  /// Dos versiones del mismo paquete que se bajan de archivos distintos: la del catálogo de ayer y
  /// la de hoy.
  PaqueteTiles conOrigen(PaqueteTiles original, String url) {
    final parte = original.partes.first;
    return PaqueteTiles(
      id: original.id,
      nivel: original.nivel,
      ambitoId: original.ambitoId,
      nombre: original.nombre,
      version: original.version,
      partes: [
        ParteTiles(origen: Uri.parse(url), tamanoBytes: parte.tamanoBytes, sha256: parte.sha256),
      ],
    );
  }

  DescargaPendiente anotada(
    PaqueteTiles cual, {
    bool datosMoviles = false,
    bool pausada = false,
    DateTime? cuando,
  }) => DescargaPendiente(
    paquete: cual,
    anotadaEn: cuando ?? desde,
    permitirDatosMoviles: datosMoviles,
    pausadaPorElColportor: pausada,
  );

  group('lo que se anota', () {
    test('dado que toco «Descargar mapa» con señal, anota el paquete con que empezó, el permiso de '
        'datos móviles y cuándo lo pedí', () async {
      final app = abrirApp();
      servidor.retenerDespuesDe = 1000;

      await app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await dejarCorrer();

      expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true)]);
      await app.pausar(paquete.id);
    });

    test('dado que toco «Descargar mapa» sin señal, anota el pedido en cola aunque nunca haya '
        'arrancado', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final app = abrirApp();

      final resultado = await app.descargar(
        paquete,
        permitirDatosMoviles: true,
        esperarConexion: true,
      );
      await dejarCorrer();

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(servidor.pedidos, isEmpty);
      expect(app.estadoDe(paquete.id), isA<DescargaPausada>());
      expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true)]);
    });

    test('dado que no se pudo arrancar y no pidió esperar, no anota nada', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final app = abrirApp();

      final resultado = await app.descargar(paquete);
      await dejarCorrer();

      expect(resultado.isLeft(), isTrue);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que no hay lugar para bajarlo, no anota nada', () async {
      espacio.libres = 100;
      final app = abrirApp();

      final resultado = await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      expect(resultado.isLeft(), isTrue);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado dos toques seguidos, anota una sola vez la descarga', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final app = abrirApp();

      final primero = app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      final segundo = app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await Future.wait([primero, segundo]);
      await dejarCorrer();

      expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true)]);
    });

    test('dado que la anotación sigue escribiéndose cuando se cierra la app, cerrar espera a que '
        'termine de escribirse', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final app = abrirApp();
      final retenida = repositorio.retenerAnotaciones = Completer<void>();

      await app.descargar(paquete, esperarConexion: true);
      var cerrado = false;
      final cierre = app.cerrar().then((_) => cerrado = true);
      await dejarCorrer();

      expect(cerrado, isFalse);
      expect(repositorio.pendientes, isEmpty);

      retenida.complete();
      await cierre;

      expect(cerrado, isTrue);
      expect(repositorio.pendientes, [anotada(paquete)]);
    });

    test('dado que termina de bajar, la olvida', () async {
      final app = abrirApp();

      await app.descargar(paquete, esperarConexion: true);
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaCompletada>());
      expect(repositorio.registrados, [descargadoDe(paquete)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que falla (el servidor responde con error), la olvida: se le dice al colportor y '
        'no se reintenta sola en cada arranque', () async {
      servidor.statusError = 500;
      final app = abrirApp();

      await app.descargar(paquete, esperarConexion: true);
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que el archivo baja corrupto, la olvida', () async {
      final corrupto = paqueteDe(bytes, sha256: 'f' * 64);
      final app = abrirApp();

      await app.descargar(corrupto, esperarConexion: true);
      await terminar(app, corrupto);

      expect(app.estadoDe(corrupto.id), isA<DescargaFallida>());
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que se corta la red a mitad, sigue anotada: queda para retomarla', () async {
      servidor.cortarDespuesDe = 2000;
      final app = abrirApp();

      await app.descargar(paquete, esperarConexion: true);
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaPausada>());
      expect(repositorio.pendientes, [anotada(paquete)]);
    });

    test('dado que la elimino, la olvida y borra lo que había bajado', () async {
      servidor.retenerDespuesDe = 2000;
      final app = abrirApp();
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      final resultado = await app.eliminar(paquete.id);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(repositorio.pendientes, isEmpty);
      expect(archivos.contenido.containsKey(parcial), isFalse);
    });

    test('dado que la elimino mientras todavía se prepara, no queda anotada después', () async {
      final app = abrirApp();

      final pedida = app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      final eliminada = app.eliminar(paquete.id);
      await Future.wait([pedida, eliminada]);
      await dejarCorrer();

      expect(repositorio.pendientes, isEmpty);
      expect(archivos.contenido, isEmpty);
    });

    test(
      'dado que la elimino pero no se puede olvidar, devuelve la falla para que se repita',
      () async {
        final app = abrirApp();
        await app.descargar(paquete, esperarConexion: true);
        await terminar(app, paquete);
        repositorio.falloPendientes = const FailureInesperado();

        final resultado = await app.eliminar(paquete.id);

        expect(resultado.isLeft(), isTrue);
      },
    );

    test('dado que la pauso yo, la anota como pausada por mí', () async {
      servidor.retenerDespuesDe = 2000;
      final app = abrirApp();
      await app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await dejarCorrer();

      await app.pausar(paquete.id);
      await dejarCorrer();

      expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true, pausada: true)]);
    });

    test('dado que la pauso estando en cola, la anota como pausada por mí', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final app = abrirApp();
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      await app.pausar(paquete.id);
      await dejarCorrer();

      expect(repositorio.pendientes, [anotada(paquete, pausada: true)]);
    });

    test('dado que la pausé y la pido de nuevo, deja de estar pausada y cuenta 7 días desde el '
        'pedido nuevo', () async {
      servidor.retenerDespuesDe = 2000;
      final app = abrirApp();
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();
      await app.pausar(paquete.id);
      await dejarCorrer();
      ahora = desde.add(const Duration(days: 3));
      servidor.retenerDespuesDe = 2000;

      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      expect(repositorio.pendientes, [anotada(paquete, cuando: ahora)]);
      await app.pausar(paquete.id);
    });

    test(
      'dado que se cierra la app mientras baja, no la olvida ni la marca pausada por mí',
      () async {
        servidor.retenerDespuesDe = 2000;
        final app = abrirApp();
        await app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
        await dejarCorrer();

        await cerrarApp(app);

        expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true)]);
        expect(archivos.contenido[parcial], bytes.sublist(0, 2000));
      },
    );

    test(
      'dado que le doy el permiso de datos móviles a una descarga en curso, queda anotado',
      () async {
        servidor.retenerDespuesDe = 2000;
        final app = abrirApp();
        await app.descargar(paquete, esperarConexion: true);
        await dejarCorrer();
        expect(repositorio.pendientes.single.permitirDatosMoviles, isFalse);

        await app.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
        await dejarCorrer();

        expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true)]);
        await app.pausar(paquete.id);
      },
    );

    test('dado que no se puede escribir lo anotado, la descarga igual baja entera', () async {
      repositorio.falloPendientes = const FailureInesperado();
      final app = abrirApp();

      final resultado = await app.descargar(paquete, esperarConexion: true);
      await terminar(app, paquete);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(app.estadoDe(paquete.id), isA<DescargaCompletada>());
      expect(repositorio.registrados, [descargadoDe(paquete)]);
    });
  });

  group('Escenario: La descarga sigue después de cerrar la app', () {
    test('dado que se cerró la app con la descarga a medias, al abrirla sigue desde lo que ya '
        'bajó, sobre el mismo archivo, y la deja disponible', () async {
      servidor.retenerDespuesDe = 2000;
      final antes = abrirApp();
      await antes.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await dejarCorrer();
      await cerrarApp(antes);
      expect(archivos.contenido[parcial], bytes.sublist(0, 2000));

      final despues = abrirApp();
      await despues.retomarPendientes();
      await terminar(despues, paquete);

      expect(servidor.pedidos, [0, 2000]);
      expect(servidor.origenes.toSet(), {paquete.origen});
      expect(despues.estadoDe(paquete.id), isA<DescargaCompletada>());
      expect(archivos.contenido[rutaFinalDe(paquete, 0)], bytes);
      expect(archivos.contenido.containsKey(parcial), isFalse);
      expect(repositorio.registrados, [descargadoDe(paquete)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que el pedido quedó en cola sin haber arrancado nunca, al abrir la app con señal '
        'arranca solo', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final antes = abrirApp();
      await antes.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await cerrarApp(antes);
      expect(servidor.pedidos, isEmpty);
      conectividad.tipo = TipoConexion.wifi;

      final despues = abrirApp();
      await despues.retomarPendientes();
      await terminar(despues, paquete);

      expect(servidor.pedidos, [0]);
      expect(despues.estadoDe(paquete.id), isA<DescargaCompletada>());
      expect(repositorio.registrados, [descargadoDe(paquete)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que el pedido en cola se abre otra vez sin señal, sigue en cola y arranca con la '
        'primera conexión que vuelva', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final antes = abrirApp();
      await antes.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await cerrarApp(antes);

      final despues = abrirApp();
      await despues.retomarPendientes();
      await dejarCorrer();

      expect(
        despues.estadoDe(paquete.id),
        DescargaPausada(paquete.id, motivo: MotivoPausa.sinConexion, recibidos: 0, total: 5500),
      );
      expect(servidor.pedidos, isEmpty);
      expect(repositorio.pendientes, [anotada(paquete, datosMoviles: true)]);

      conectividad.cambiarA(TipoConexion.datosMoviles);
      await terminar(despues, paquete);

      expect(despues.estadoDe(paquete.id), isA<DescargaCompletada>());
      expect(repositorio.registrados, [descargadoDe(paquete)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que el catálogo ya trae otra versión, termina el archivo que empezó y no toca el '
        'nuevo; la versión nueva se baja después como cualquier otra', () async {
      final viejo = conOrigen(paqueteDe(bytes), 'https://tiles.test/zona-centro-v1.pmtiles');
      final bytesNuevos = bytesDePrueba(6000, semilla: 9);
      final nuevo = conOrigen(paqueteDe(bytesNuevos), 'https://tiles.test/zona-centro-v2.pmtiles');
      servidor
        ..archivos[viejo.origen] = bytes
        ..archivos[nuevo.origen] = bytesNuevos
        ..retenerDespuesDe = 2000;
      final antes = abrirApp();
      await antes.descargar(viejo, esperarConexion: true);
      await dejarCorrer();
      await cerrarApp(antes);
      repositorio.paquetesCatalogo = [nuevo];

      final despues = abrirApp();
      await despues.retomarPendientes();
      await terminar(despues, viejo);

      expect(servidor.origenes.toSet(), {viejo.origen});
      expect(servidor.pedidos, [0, 2000]);
      expect(repositorio.registrados, [descargadoDe(viejo)]);
      expect(archivos.contenido[rutaFinalDe(viejo, 0)], bytes);
      expect(
        archivos.contenido.keys.where((ruta) => ruta.contains(nuevo.claveDeParte(0))),
        isEmpty,
      );
      expect(repositorio.pendientes, isEmpty);

      await despues.descargar(nuevo);
      await terminar(despues, nuevo);

      expect(repositorio.registrados, [descargadoDe(nuevo)]);
    });

    test('dado un paquete en dos archivos que se cerró bajando el segundo, retoma el segundo desde '
        'donde quedó y no vuelve a pedir el primero', () async {
      final primera = bytesDePrueba(3000);
      final segunda = bytesDePrueba(2500, semilla: 9);
      final ciudad = paqueteEnPartes([primera, segunda]);
      servidor
        ..archivos[ciudad.partes[0].origen] = primera
        ..archivos[ciudad.partes[1].origen] = segunda
        ..soloEnOrigen = ciudad.partes[1].origen
        ..retenerDespuesDe = 1000;
      final antes = abrirApp();
      await antes.descargar(ciudad, esperarConexion: true);
      await dejarCorrer();
      await cerrarApp(antes);
      expect(archivos.contenido[rutaParcialDe(ciudad, 0)], primera);
      expect(archivos.contenido[rutaParcialDe(ciudad, 1)], segunda.sublist(0, 1000));
      servidor.pedidos.clear();
      servidor.origenes.clear();

      final despues = abrirApp();
      await despues.retomarPendientes();
      await terminar(despues, ciudad);

      expect(servidor.origenes, [ciudad.partes[1].origen]);
      expect(servidor.pedidos, [1000]);
      expect(repositorio.registrados, [descargadoDe(ciudad)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que se cortó la red a mitad y se cerró la app, al abrirla retoma desde el byte que '
        'quedó', () async {
      servidor.cortarDespuesDe = 2000;
      final antes = abrirApp();
      await antes.descargar(paquete, esperarConexion: true);
      await terminar(antes, paquete);
      await cerrarApp(antes);

      final despues = abrirApp();
      await despues.retomarPendientes();
      await terminar(despues, paquete);

      expect(servidor.pedidos, [0, 2000]);
      expect(repositorio.registrados, [descargadoDe(paquete)]);
    });

    test('dado que la descarga tenía permiso de datos móviles, al abrir la app con datos móviles '
        'sigue sin esperar el Wi-Fi', () async {
      servidor.retenerDespuesDe = 2000;
      final antes = abrirApp();
      await antes.descargar(paquete, permitirDatosMoviles: true, esperarConexion: true);
      await dejarCorrer();
      await cerrarApp(antes);
      conectividad.tipo = TipoConexion.datosMoviles;

      final despues = abrirApp();
      await despues.retomarPendientes();
      await terminar(despues, paquete);

      expect(despues.estadoDe(paquete.id), isA<DescargaCompletada>());
    });

    test(
      'dado que la descarga no tenía permiso de datos móviles, al abrir la app con datos móviles '
      'espera el Wi-Fi',
      () async {
        servidor.retenerDespuesDe = 2000;
        final antes = abrirApp();
        await antes.descargar(paquete, esperarConexion: true);
        await dejarCorrer();
        await cerrarApp(antes);
        conectividad.tipo = TipoConexion.datosMoviles;

        final despues = abrirApp();
        await despues.retomarPendientes();
        await dejarCorrer();

        expect(
          despues.estadoDe(paquete.id),
          DescargaPausada(paquete.id, motivo: MotivoPausa.sinWifi, recibidos: 2000, total: 5500),
        );
        expect(servidor.pedidos, [0]);

        conectividad.cambiarA(TipoConexion.wifi);
        await terminar(despues, paquete);

        expect(despues.estadoDe(paquete.id), isA<DescargaCompletada>());
        expect(servidor.pedidos, [0, 2000]);
      },
    );

    test('dado que se retoma tres días después y la red se corta, los 7 días siguen contando desde '
        'el pedido: ni retomar ni un reintento los renuevan', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final antes = abrirApp();
      await antes.descargar(paquete, esperarConexion: true);
      await cerrarApp(antes);
      ahora = desde.add(const Duration(days: 3));
      servidor.cortarDespuesDe = 2000;

      final despues = abrirApp();
      await despues.retomarPendientes();
      conectividad.cambiarA(TipoConexion.wifi);
      await terminar(despues, paquete);

      expect(despues.estadoDe(paquete.id), isA<DescargaPausada>());
      expect(repositorio.pendientes, [anotada(paquete)]);
      expect(repositorio.pendientes.single.anotadaEn, desde);
    });

    test('dado que el colportor la había pausado, al abrir la app no la retoma sola', () async {
      servidor.retenerDespuesDe = 2000;
      final antes = abrirApp();
      await antes.descargar(paquete, esperarConexion: true);
      await dejarCorrer();
      await antes.pausar(paquete.id);
      await cerrarApp(antes);
      servidor.pedidos.clear();

      final despues = abrirApp();
      await despues.retomarPendientes();
      conectividad.cambiarA(TipoConexion.wifi);
      await dejarCorrer();

      expect(despues.estadoDe(paquete.id), isNull);
      expect(servidor.pedidos, isEmpty);
      expect(repositorio.pendientes, [anotada(paquete, pausada: true)]);

      // Cuando él quiere, la pide y sigue desde lo que ya había.
      await despues.descargar(paquete, esperarConexion: true);
      await terminar(despues, paquete);

      expect(servidor.pedidos, [2000]);
      expect(repositorio.registrados, [descargadoDe(paquete)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test('dado que pasaron los 7 días, no la retoma', () async {
      await repositorio.anotarDescargaPendiente(
        anotada(paquete, cuando: desde.subtract(DescargaPendiente.vigencia)),
      );

      final app = abrirApp();
      await app.retomarPendientes();
      await dejarCorrer();

      expect(app.estadoDe(paquete.id), isNull);
      expect(servidor.pedidos, isEmpty);
    });

    test('dado que faltan unos minutos para los 7 días, todavía la retoma', () async {
      await repositorio.anotarDescargaPendiente(
        anotada(
          paquete,
          cuando: desde.subtract(DescargaPendiente.vigencia - const Duration(minutes: 5)),
        ),
      );

      final app = abrirApp();
      await app.retomarPendientes();
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaCompletada>());
    });

    test('dado que el colportor ya la pidió de nuevo antes de que termine de retomar, no baja dos '
        'veces', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      final app = abrirApp();

      final retomada = app.retomarPendientes();
      final pedida = app.descargar(paquete, esperarConexion: true);
      await Future.wait([retomada, pedida]);
      await terminar(app, paquete);

      expect(servidor.pedidos, [0]);
      expect(repositorio.registrados, [descargadoDe(paquete)]);
    });

    test('dado que ya la pidió en esta sesión, retomar no la pide otra vez', () async {
      servidor.retenerDespuesDe = 2000;
      final app = abrirApp();
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      await app.retomarPendientes();
      await dejarCorrer();

      expect(servidor.pedidos, [0]);
      await app.pausar(paquete.id);
    });

    test('dado que se llama dos veces a retomar, la descarga arranca una sola vez', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      final app = abrirApp();

      await Future.wait([app.retomarPendientes(), app.retomarPendientes()]);
      await terminar(app, paquete);

      expect(servidor.pedidos, [0]);
      expect(repositorio.registrados, [descargadoDe(paquete)]);
    });

    test('dado que ya no hay lugar en el teléfono, la descarga falla con el aviso de siempre y no '
        'se reintenta en cada arranque', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      espacio.libres = 100;

      final app = abrirApp();
      await app.retomarPendientes();
      await dejarCorrer();

      expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
      expect(estados.last, isA<DescargaFallida>());
      expect(repositorio.pendientes, isEmpty);
      expect(servidor.pedidos, isEmpty);
    });

    test('dado que el servidor ya no tiene el archivo, la descarga falla y se olvida: el colportor '
        'la pide de nuevo', () async {
      servidor.archivos.remove(paquete.origen);
      await repositorio.anotarDescargaPendiente(anotada(paquete));

      final app = abrirApp();
      await app.retomarPendientes();
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
      expect(repositorio.pendientes, isEmpty);

      servidor.archivos[paquete.origen] = bytes;
      await app.descargar(paquete, esperarConexion: true);
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaCompletada>());
    });

    test('dado que no se puede leer lo anotado, no retoma nada y no lanza', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      repositorio.falloPendientes = const FailureInesperado();

      final app = abrirApp();
      await app.retomarPendientes();
      await dejarCorrer();

      expect(app.estadoDe(paquete.id), isNull);
      expect(servidor.pedidos, isEmpty);
    });

    test('dado varias descargas pendientes, retoma todas', () async {
      final otro = paqueteDe(bytesDePrueba(3000, semilla: 9), id: 'ciudad-mvd');
      servidor.archivos[otro.origen] = bytesDePrueba(3000, semilla: 9);
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      await repositorio.anotarDescargaPendiente(anotada(otro, datosMoviles: true));

      final app = abrirApp();
      await app.retomarPendientes();
      await terminar(app, paquete);
      await terminar(app, otro);

      expect(app.estadoDe(paquete.id), isA<DescargaCompletada>());
      expect(app.estadoDe(otro.id), isA<DescargaCompletada>());
      expect(repositorio.pendientes, isEmpty);
    });

    test(
      'dado un error del servidor (503) al abrir la app con la descarga a medias y que se cierra '
      'otra vez, al abrirla con el servidor andando sigue desde el mismo byte y la deja '
      'disponible',
      () async {
        servidor.retenerDespuesDe = 2000;
        final antes = abrirApp();
        await antes.descargar(paquete, esperarConexion: true);
        await dejarCorrer();
        await cerrarApp(antes);
        servidor.statusError = 503;
        final primera = abrirApp();

        await primera.retomarPendientes();
        await dejarCorrer();

        expect(
          primera.estadoDe(paquete.id),
          DescargaPausada(
            paquete.id,
            motivo: MotivoPausa.sinConexion,
            recibidos: 2000,
            total: 5500,
          ),
        );
        expect(repositorio.pendientes, [anotada(paquete)]);
        expect(archivos.contenido[parcial], bytes.sublist(0, 2000));
        await cerrarApp(primera);
        servidor.statusError = null;

        final segunda = abrirApp();
        await segunda.retomarPendientes();
        await terminar(segunda, paquete);

        expect(servidor.pedidos, [0, 2000, 2000]);
        expect(segunda.estadoDe(paquete.id), isA<DescargaCompletada>());
        expect(archivos.contenido[rutaFinalDe(paquete, 0)], bytes);
        expect(repositorio.registrados, [descargadoDe(paquete)]);
        expect(repositorio.pendientes, isEmpty);
      },
    );

    test('dado que elimino un paquete mientras la retoma todavía no llegó a él, no lo baja ni lo '
        'vuelve a anotar', () async {
      final bytesOtro = bytesDePrueba(3000, semilla: 9);
      final otro = paqueteDe(
        bytesOtro,
        id: 'ciudad-mvd',
        nivel: NivelCobertura.ciudad,
        ambitoId: 'c-1',
      );
      servidor.archivos[otro.origen] = bytesOtro;
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      await repositorio.anotarDescargaPendiente(anotada(otro));
      final app = abrirApp();
      final retenida = espacio.retener = Completer<void>();

      final retoma = app.retomarPendientes();
      await dejarCorrer();
      final eliminado = await app.eliminar(otro.id);
      retenida.complete();
      await retoma;
      await terminar(app, paquete);

      expect(eliminado.isRight(), isTrue);
      expect(app.estadoDe(otro.id), isNull);
      expect(servidor.origenes, [paquete.origen]);
      expect(repositorio.registrados, [descargadoDe(paquete)]);
      expect(repositorio.pendientes, isEmpty);
    });

    test(
      'dado que la anotación tiene fecha futura (el reloj del teléfono estaba adelantado), se '
      'retoma y se vuelve a anotar con la fecha de hoy: los 7 días cuentan desde ahora',
      () async {
        final futura = desde.add(const Duration(days: 30));
        await repositorio.anotarDescargaPendiente(anotada(paquete, cuando: futura));
        servidor.retenerDespuesDe = 2000;
        final app = abrirApp();

        await app.retomarPendientes();
        await dejarCorrer();

        expect(servidor.pedidos, [0]);
        final corregida = repositorio.pendientes.single;
        expect(corregida, anotada(paquete, cuando: desde));
        expect(corregida.vencida(desde.add(const Duration(days: 7))), isTrue);
        expect(corregida.vencida(desde.add(const Duration(days: 7, seconds: -1))), isFalse);
        await app.pausar(paquete.id);
      },
    );

    // El reloj adelantado que se corrigió casi nunca es un mes: una hora de más o un segundo. Todo
    // adelanto se lleva a hoy, no solo el de más de un día.
    for (final adelanto in const [
      Duration(seconds: 1),
      Duration(hours: 3),
      Duration(hours: 23, minutes: 59, seconds: 59),
    ]) {
      test('dado que la anotación está adelantada $adelanto, se retoma y se vuelve a anotar con la '
          'fecha de hoy', () async {
        await repositorio.anotarDescargaPendiente(anotada(paquete, cuando: desde.add(adelanto)));
        servidor.retenerDespuesDe = 2000;
        final app = abrirApp();

        await app.retomarPendientes();
        await dejarCorrer();

        expect(servidor.pedidos, [0]);
        final corregida = repositorio.pendientes.single;
        expect(corregida, anotada(paquete, cuando: desde));
        expect(corregida.vencida(desde.add(DescargaPendiente.vigencia)), isTrue);
        expect(
          corregida.vencida(desde.add(DescargaPendiente.vigencia - const Duration(seconds: 1))),
          isFalse,
        );
        await app.pausar(paquete.id);
      });
    }

    test('dado que la que pausó el colportor tiene fecha futura, tampoco se retoma pero se '
        'corrige la fecha', () async {
      final futura = desde.add(const Duration(days: 30));
      await repositorio.anotarDescargaPendiente(anotada(paquete, pausada: true, cuando: futura));
      final app = abrirApp();

      await app.retomarPendientes();
      await dejarCorrer();

      expect(servidor.pedidos, isEmpty);
      expect(app.estadoDe(paquete.id), isNull);
      expect(repositorio.pendientes, [anotada(paquete, pausada: true, cuando: desde)]);
    });

    test('dado que la anotación es de hoy, la retoma no la reescribe sin necesidad', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete, pausada: true));
      final app = abrirApp();
      final antes = repositorio.anotaciones;

      await app.retomarPendientes();
      await dejarCorrer();

      expect(repositorio.anotaciones, antes);
    });

    test(
      'dado que se retoma, avisa que está bajando sin esperar los encabezados del servidor',
      () async {
        await repositorio.anotarDescargaPendiente(anotada(paquete));
        servidor.esperaAntesDeContestar = Completer<void>();

        final app = abrirApp();
        await app.retomarPendientes();
        await dejarCorrer();

        expect(app.estaDescargando(paquete.id), isTrue);
        expect(estados.first, isA<DescargaEnCurso>());
        servidor.esperaAntesDeContestar!.complete();
        await terminar(app, paquete);
      },
    );
  });

  group('en qué está el mapa de un lugar', () {
    const ambito = AmbitoTrabajo(zonaId: 'z-1');
    const otroAmbito = AmbitoTrabajo(zonaId: 'z-9');

    test(
      'dado que la descarga retomada quedó en cola sin señal, la reconoce por el lugar sin pedir '
      'el catálogo',
      () async {
        conectividad.tipo = TipoConexion.sinConexion;
        await repositorio.anotarDescargaPendiente(anotada(paquete));

        final app = abrirApp();
        await app.retomarPendientes();
        await dejarCorrer();

        expect(app.paqueteEnMarchaQueCubre(ambito), paquete);
        expect(app.paqueteEnMarchaQueCubre(otroAmbito), isNull);
        expect(app.paqueteDe(paquete.id), paquete);
      },
    );

    test('dado que la retoma falló de forma terminal (el servidor ya no tiene el archivo), sigue '
        'contando para la tarjeta hasta que el colportor la pide de nuevo', () async {
      servidor.archivos.remove(paquete.origen);
      await repositorio.anotarDescargaPendiente(anotada(paquete));

      final app = abrirApp();
      await app.retomarPendientes();
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
      expect(repositorio.pendientes, isEmpty);
      expect(app.paqueteEnMarchaQueCubre(ambito), paquete);
      expect(app.paqueteEnMarchaQueCubre(otroAmbito), isNull);

      servidor.archivos[paquete.origen] = bytes;
      servidor.retenerDespuesDe = 2000;
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      expect(app.paqueteEnMarchaQueCubre(ambito), paquete, reason: 'ahora está bajando');
      await app.pausar(paquete.id);
      expect(app.paqueteEnMarchaQueCubre(ambito), isNull);
    });

    test('dado que la retoma falló por falta de lugar, sigue contando para la tarjeta', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete));
      espacio.libres = 100;

      final app = abrirApp();
      await app.retomarPendientes();
      await dejarCorrer();

      expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
      expect(app.paqueteEnMarchaQueCubre(ambito), paquete);
    });

    test('dado que la falla fue tras el toque del colportor, no cuenta: esa la ve la tarjeta en '
        'el momento', () async {
      servidor.archivos.remove(paquete.origen);
      final app = abrirApp();

      await app.descargar(paquete, esperarConexion: true);
      await terminar(app, paquete);

      expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
      expect(app.paqueteEnMarchaQueCubre(ambito), isNull);
    });

    test('dado que terminó de bajar, ya no está en marcha', () async {
      await repositorio.anotarDescargaPendiente(anotada(paquete));

      final app = abrirApp();
      await app.retomarPendientes();
      await terminar(app, paquete);

      expect(app.paqueteEnMarchaQueCubre(ambito), isNull);
    });

    test('dado que la pausó el colportor, no está en marcha', () async {
      servidor.retenerDespuesDe = 2000;
      final app = abrirApp();
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();
      expect(app.paqueteEnMarchaQueCubre(ambito), paquete);

      await app.pausar(paquete.id);

      expect(app.paqueteEnMarchaQueCubre(ambito), isNull);
    });

    test('dado varias en marcha que cubren el lugar, elige la de nivel más chico', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final ciudad = paqueteDe(
        bytesDePrueba(3000, semilla: 9),
        id: 'ciudad-mvd',
        nivel: NivelCobertura.ciudad,
        ambitoId: 'c-1',
      );
      final app = abrirApp();
      await app.descargar(ciudad, esperarConexion: true);
      await app.descargar(paquete, esperarConexion: true);
      await dejarCorrer();

      expect(
        app.paqueteEnMarchaQueCubre(const AmbitoTrabajo(zonaId: 'z-1', ciudadId: 'c-1')),
        paquete,
      );
      expect(app.paqueteEnMarchaQueCubre(const AmbitoTrabajo(ciudadId: 'c-1')), ciudad);
    });

    // Dos descargas anotadas del mismo lugar: la zona (la de nivel más chico) y la ciudad. Lo que
    // baja manda sobre lo que falló al retomar: una falla de una no puede tapar a la otra, que
    // sigue bajando, ni habilitar «Descargar mapa» mientras el mapa se descarga.
    group('dos pendientes del mismo lugar', () {
      const lugar = AmbitoTrabajo(zonaId: 'z-1', ciudadId: 'c-1');
      final bytesCiudad = bytesDePrueba(3000, semilla: 9);
      final paqueteCiudad = paqueteDe(
        bytesCiudad,
        id: 'ciudad-mvd',
        nivel: NivelCobertura.ciudad,
        ambitoId: 'c-1',
      );

      setUp(() => servidor.archivos[paqueteCiudad.origen] = bytesCiudad);

      /// Anota las dos en el orden pedido y abre la app: con la señal bien, cada una arranca.
      Future<DescargadorPaquetesTiles> abrirConLasDos({required bool ciudadPrimero}) async {
        final dos = [paquete, paqueteCiudad];
        for (final cual in ciudadPrimero ? dos.reversed : dos) {
          await repositorio.anotarDescargaPendiente(anotada(cual));
        }
        final app = abrirApp();
        await app.retomarPendientes();
        await dejarCorrer();
        return app;
      }

      for (final ciudadPrimero in [false, true]) {
        final orden = ciudadPrimero ? 'ciudad y zona' : 'zona y ciudad';

        test('dado que la de zona falló al retomar y la de ciudad sigue bajando ($orden), elige '
            'la que baja', () async {
          servidor.archivos.remove(paquete.origen);
          servidor.soloEnOrigen = paqueteCiudad.origen;
          servidor.retenerDespuesDe = 1000;

          final app = await abrirConLasDos(ciudadPrimero: ciudadPrimero);

          expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
          expect(app.estaDescargando(paqueteCiudad.id), isTrue);
          expect(app.paqueteEnMarchaQueCubre(lugar), paqueteCiudad);
          await app.pausar(paqueteCiudad.id);
        });

        test('dado que la de ciudad falló al retomar y la de zona sigue bajando ($orden), elige '
            'la que baja', () async {
          servidor.archivos.remove(paqueteCiudad.origen);
          servidor.soloEnOrigen = paquete.origen;
          servidor.retenerDespuesDe = 1000;

          final app = await abrirConLasDos(ciudadPrimero: ciudadPrimero);

          expect(app.estadoDe(paqueteCiudad.id), isA<DescargaFallida>());
          expect(app.estaDescargando(paquete.id), isTrue);
          expect(app.paqueteEnMarchaQueCubre(lugar), paquete);
          await app.pausar(paquete.id);
        });

        test('dado que las dos quedaron en cola sin señal ($orden), elige la de nivel más chico, '
            'sea cual sea el orden en que se retomaron', () async {
          conectividad.tipo = TipoConexion.sinConexion;

          final app = await abrirConLasDos(ciudadPrimero: ciudadPrimero);

          expect(app.estadoDe(paquete.id), isA<DescargaPausada>());
          expect(app.estadoDe(paqueteCiudad.id), isA<DescargaPausada>());
          expect(app.paqueteEnMarchaQueCubre(lugar), paquete);
        });

        test('dado que las dos fallaron al retomar ($orden), elige la de nivel más chico: la '
            'tarjeta muestra una sola falla', () async {
          servidor.archivos.remove(paquete.origen);
          servidor.archivos.remove(paqueteCiudad.origen);

          final app = await abrirConLasDos(ciudadPrimero: ciudadPrimero);

          expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
          expect(app.estadoDe(paqueteCiudad.id), isA<DescargaFallida>());
          expect(app.paqueteEnMarchaQueCubre(lugar), paquete);
        });
      }

      test('dado que la de zona falló al retomar y la de ciudad quedó en cola sin señal, elige '
          'la que está en cola: se descarga sola', () async {
        servidor.archivos.remove(paquete.origen);
        await repositorio.anotarDescargaPendiente(anotada(paquete));
        final app = abrirApp();
        await app.retomarPendientes();
        await terminar(app, paquete);
        conectividad.tipo = TipoConexion.sinConexion;

        await app.descargar(paqueteCiudad, esperarConexion: true);
        await dejarCorrer();

        expect(app.estadoDe(paquete.id), isA<DescargaFallida>());
        expect(app.estadoDe(paqueteCiudad.id), isA<DescargaPausada>());
        expect(app.paqueteEnMarchaQueCubre(lugar), paqueteCiudad);
      });
    });
  });
}
