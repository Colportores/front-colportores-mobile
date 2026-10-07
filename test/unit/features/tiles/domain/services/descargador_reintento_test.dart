// Una descarga que se corta con el Wi-Fi arriba reintenta sola, con espera creciente (HU-SYNC-010,
// #189, decisión «reintento»): 30 s, 1 min, 2 min, 5 min y de ahí cada 5 min, sin tope de intentos
// con la app abierta. Un cambio de conectividad permitido reintenta ya y vuelve a los 30 s; pausar,
// eliminar, cerrar o perder la conexión permitida cancelan la espera. El estado sigue siendo
// `DescargaPausada(sinConexion)`.
//
// El tiempo es el de `fakeAsync`: nada espera de verdad. Los fakes y el descargador se arman ADENTRO
// del `fakeAsync` para que los eventos y los temporizadores corran en esa misma zona.
import 'dart:async';

import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/descargador_paquetes_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

/// Todo lo que arma un test, dentro de un `fakeAsync`.
final class Entorno {
  Entorno(this.reloj)
    : conectividad = ConectividadFalsa(),
      servidor = ServidorFalso()..cancelaEnLaZonaActual = true,
      espacio = EspacioFalso(),
      archivos = ArchivosEnMemoria(),
      repositorio = RepositorioTilesEnMemoria(),
      bytes = bytesDePrueba(5500) {
    paquete = paqueteDe(bytes);
    servidor.archivos[paquete.origen] = bytes;
    descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: espacio,
      cliente: servidor,
      archivos: archivos,
      checksum: ChecksumFalso(archivos),
      repository: repositorio,
    );
    descargador.cambios.listen(estados.add);
  }

  final FakeAsync reloj;
  final ConectividadFalsa conectividad;
  final ServidorFalso servidor;
  final EspacioFalso espacio;
  final ArchivosEnMemoria archivos;
  final RepositorioTilesEnMemoria repositorio;
  final List<int> bytes;
  final estados = <EstadoDescarga>[];
  late final PaqueteTiles paquete;
  late final DescargadorPaquetesTiles descargador;

  EstadoDescarga? get estado => descargador.estadoDe(paquete.id);

  /// La pausa por corte: sigue sola, con [recibidos] bytes en el `.part`.
  EstadoDescarga pausadaPorCorte(int recibidos) => DescargaPausada(
    paquete.id,
    motivo: MotivoPausa.sinConexion,
    recibidos: recibidos,
    total: 5500,
  );

  void dejarCorrer() => reloj.flushMicrotasks();

  /// Pasa [tiempo] de reloj: dispara los temporizadores que vencen, con sus intentos.
  void pasar(Duration tiempo) {
    reloj.elapse(tiempo);
    reloj.flushMicrotasks();
  }

  void descargar({bool esperarConexion = false}) {
    unawaited(descargador.descargar(paquete, esperarConexion: esperarConexion));
    dejarCorrer();
  }

  /// Cuántos pedidos al servidor hubo.
  int get pedidos => servidor.pedidos.length;
}

/// Un test con su entorno, adentro de un `fakeAsync`; al final cierra el descargador.
void probar(String nombre, void Function(Entorno e) cuerpo) {
  test(nombre, () {
    fakeAsync((reloj) {
      final entorno = Entorno(reloj);
      cuerpo(entorno);
      unawaited(entorno.descargador.cerrar());
      reloj.flushMicrotasks();
    });
  });
}

void main() {
  const treintaSegundos = Duration(seconds: 30);
  const unSegundo = Duration(seconds: 1);
  const diezMinutos = Duration(minutes: 10);

  group('reintento de una descarga cortada con el Wi-Fi arriba', () {
    probar('dado que el servidor corta la conexión, queda en la pausa «sin conexión» y a los '
        '30 s vuelve a pedir desde donde quedó', (e) {
      e.servidor.cortarDespuesDe = 3000;

      e.descargar();

      expect(e.estado, e.pausadaPorCorte(3000));
      expect(e.pedidos, 1);
      e.pasar(treintaSegundos - unSegundo);
      expect(e.pedidos, 1, reason: 'a los 29 s todavía no reintenta');
      e.pasar(unSegundo);
      expect(e.servidor.pedidos, [0, 3000]);
      expect(e.estado, isA<DescargaCompletada>());
      expect(e.archivos.contenido[rutaFinalDe(e.paquete, 0)], e.bytes);
      expect(e.repositorio.registrados, [descargadoDe(e.paquete)]);
    });

    probar('dado que el pedido no llega al servidor, la espera crece: 30 s, 1 min, 2 min, 5 min '
        'y de ahí cada 5 min', (e) {
      e.servidor.sinRed = true;
      e.descargar();
      expect(e.pedidos, 1);

      var esperado = 1;
      for (final espera in const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 5),
        Duration(minutes: 5),
        Duration(minutes: 5),
      ]) {
        e.pasar(espera - unSegundo);
        expect(e.pedidos, esperado, reason: 'un segundo antes de los $espera');
        e.pasar(unSegundo);
        esperado++;
        expect(e.pedidos, esperado, reason: 'a los $espera');
        expect(e.estado, e.pausadaPorCorte(0));
      }
    });

    probar('dado que sigue sin llegar, no hay tope de intentos: sigue pidiendo cada 5 min', (e) {
      e.servidor.sinRed = true;
      e.descargar();

      e.pasar(const Duration(minutes: 8, seconds: 30));
      expect(e.pedidos, 5, reason: 'el inicial y los de 30 s, 1 min, 2 min y 5 min');

      for (var i = 1; i <= 100; i++) {
        e.pasar(const Duration(minutes: 5));
        expect(e.pedidos, 5 + i);
      }
      expect(e.estado, e.pausadaPorCorte(0));
    });

    probar('dado que la espera sigue, cuando cambia la conectividad a una permitida, reintenta ya '
        'y la espera vuelve a ser de 30 s', (e) {
      e.servidor.sinRed = true;
      e.descargar();
      e.pasar(const Duration(seconds: 30));
      e.pasar(const Duration(minutes: 1));
      expect(e.pedidos, 3);
      e.pasar(const Duration(minutes: 1));
      expect(e.pedidos, 3, reason: 'ahora espera 2 min');

      e.conectividad.cambiarA(TipoConexion.wifi);
      e.dejarCorrer();

      expect(e.pedidos, 4, reason: 'reintenta ya, sin esperar los 2 min');
      e.pasar(treintaSegundos - unSegundo);
      expect(e.pedidos, 4);
      e.pasar(unSegundo);
      expect(e.pedidos, 5, reason: 'la espera volvió a 30 s');
    });

    probar('dado que pierdo el Wi-Fi mientras espera, cancela la espera y retoma ya cuando '
        'vuelve', (e) {
      e.servidor.cortarDespuesDe = 3000;
      e.descargar();

      e.conectividad.cambiarA(TipoConexion.sinConexion);
      e.pasar(diezMinutos);

      expect(e.servidor.pedidos, [0], reason: 'sin conexión no pide nada');
      expect(e.estado, e.pausadaPorCorte(3000));

      e.conectividad.cambiarA(TipoConexion.wifi);
      e.dejarCorrer();

      expect(e.servidor.pedidos, [0, 3000]);
    });

    probar('dado que paso a datos móviles sin permiso mientras espera, no reintenta por esa '
        'conexión', (e) {
      e.servidor.cortarDespuesDe = 3000;
      e.descargar();

      e.conectividad.cambiarA(TipoConexion.datosMoviles);
      e.pasar(diezMinutos);

      expect(e.servidor.pedidos, [0]);

      e.conectividad.cambiarA(TipoConexion.wifi);
      e.dejarCorrer();

      expect(e.servidor.pedidos, [0, 3000]);
    });

    probar('dado que el colportor pausa mientras espera, no reintenta', (e) {
      e.servidor.cortarDespuesDe = 3000;
      e.descargar();

      unawaited(e.descargador.pausar(e.paquete.id));
      e.dejarCorrer();
      e.pasar(diezMinutos);

      expect(e.servidor.pedidos, [0]);
      expect(
        e.estado,
        DescargaPausada(e.paquete.id, motivo: MotivoPausa.usuario, recibidos: 3000, total: 5500),
      );
    });

    probar('dado que elimino el paquete mientras espera, no reintenta y no queda nada', (e) {
      e.servidor.cortarDespuesDe = 3000;
      e.descargar();

      unawaited(e.descargador.eliminar(e.paquete.id));
      e.dejarCorrer();
      e.pasar(diezMinutos);

      expect(e.servidor.pedidos, [0]);
      expect(e.estados.last, isA<DescargaEliminada>());
      expect(e.archivos.contenido.keys.where((ruta) => ruta.contains('.pmtiles')), isEmpty);
    });

    probar('dado que cierro el descargador mientras espera, no reintenta', (e) {
      e.servidor.cortarDespuesDe = 3000;
      e.descargar();

      unawaited(e.descargador.cerrar());
      e.dejarCorrer();
      e.pasar(diezMinutos);

      expect(e.servidor.pedidos, [0]);
    });

    probar('dado que la descarga se retoma a mano en medio de la espera, pide ya y la espera '
        'vuelve a ser de 30 s', (e) {
      e.servidor.sinRed = true;
      e.descargar();
      e.pasar(const Duration(seconds: 30));
      expect(e.pedidos, 2, reason: 'el primer reintento; ahora espera 1 min');
      e.pasar(const Duration(seconds: 10));

      e.descargar();

      expect(e.pedidos, 3, reason: 'el toque pide ya');
      e.pasar(const Duration(seconds: 29));
      expect(e.pedidos, 3, reason: 'el reintento de la espera anterior se canceló');
      e.pasar(const Duration(seconds: 1));
      expect(e.pedidos, 4, reason: 'a los 30 s del toque');
    });

    probar('dado que la descarga espera la conexión (en cola, sin red), no reintenta por tiempo '
        'y arranca con la primera conexión permitida', (e) {
      e.conectividad.tipo = TipoConexion.sinConexion;
      e.descargar(esperarConexion: true);

      e.pasar(diezMinutos);
      expect(e.pedidos, 0);

      e.conectividad.cambiarA(TipoConexion.wifi);
      e.dejarCorrer();
      expect(e.pedidos, 1);
    });

    probar('dado que el reintento falla porque ya no hay espacio, la descarga falla con ese aviso '
        'y no sigue reintentando', (e) {
      e.servidor.cortarDespuesDe = 3000;
      e.descargar();
      e.espacio.libres = 0;

      e.pasar(treintaSegundos);

      expect(e.estado, isA<DescargaFallida>());
      e.pasar(diezMinutos);
      expect(e.servidor.pedidos, [0]);
    });
  });

  test('con esperas cortas de verdad el reintento termina de bajar el archivo', () async {
    final conectividad = ConectividadFalsa();
    final archivos = ArchivosEnMemoria();
    final repositorio = RepositorioTilesEnMemoria();
    final bytes = bytesDePrueba(5500);
    final paquete = paqueteDe(bytes);
    final servidor = ServidorFalso()
      ..archivos[paquete.origen] = bytes
      ..cortarDespuesDe = 3000;
    final descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: EspacioFalso(),
      cliente: servidor,
      archivos: archivos,
      checksum: ChecksumFalso(archivos),
      repository: repositorio,
      esperasDeReintento: const [Duration(milliseconds: 20)],
    );
    addTearDown(descargador.cerrar);
    final completada = descargador.cambios
        .firstWhere((estado) => estado is DescargaCompletada)
        .timeout(const Duration(seconds: 10));

    await descargador.descargar(paquete);
    await completada;

    expect(servidor.pedidos, [0, 3000]);
    expect(archivos.contenido[rutaFinalDe(paquete, 0)], bytes);
    expect(archivos.contenido.containsKey(rutaParcialDe(paquete, 0)), isFalse);
    expect(repositorio.registrados, [descargadoDe(paquete)]);
  });
}
