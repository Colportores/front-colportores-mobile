// «Mapa caído» (#299, seguimiento de #190): al abrir el mapa con conexión, si el mapa de la ciudad
// no está en el teléfono, se le pide 1 byte al `.pmtiles` del catálogo. Si no contesta, sale el
// aviso «No pudimos cargar el mapa de esta ciudad». Sin pantalla: la conexión, el catálogo y la
// sonda entran por los puertos falsos (`ArnesMapa`, `SondaFalsa`).
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/situacion_mapa_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/tiles_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/mapa_descargas_arnes.dart';
import '../../../../helpers/tiles_falsos.dart';

const _ambitoCanelones = AmbitoTrabajo(ciudadId: 'c-2');

/// Montevideo en dos archivos (una ciudad grande no entra en uno solo).
final _montevideoEnPartes = paqueteEnPartes([bytesDePrueba(3000), bytesDePrueba(3000, semilla: 5)]);

Future<void> _dejarCorrer() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ArnesMapa arnes;
  late ProviderContainer contenedor;

  ProviderContainer armar(ArnesMapa a) {
    final c = ProviderContainer(overrides: a.overrides);
    addTearDown(c.dispose);
    addTearDown(() => unawaited(a.cerrar()));
    return c;
  }

  /// Escucha el provider para que no se descarte entre una lectura y otra.
  T observar<T>(ProviderContainer c, ProviderListenable<T> provider) {
    final suscripcion = c.listen(provider, (_, _) {});
    addTearDown(suscripcion.close);
    return suscripcion.read();
  }

  /// Abre el mapa: escucha la situación y deja correr la conexión, el catálogo y la prueba.
  Future<void> abrirMapa([AmbitoTrabajo ambito = ambitoMontevideo]) async {
    observar(contenedor, situacionMapaProvider(ambito));
    await _dejarCorrer();
  }

  SituacionMapa situacion([AmbitoTrabajo ambito = ambitoMontevideo]) =>
      contenedor.read(situacionMapaProvider(ambito));

  PruebaDelMapa? prueba([AmbitoTrabajo ambito = ambitoMontevideo]) =>
      contenedor.read(pruebaDelMapaProvider(ambito)).value;

  group('con conexión y el mapa sin descargar', () {
    test(
      'le pide 1 byte al archivo de la ciudad; si contesta, el mapa en línea y ningún aviso',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        contenedor = armar(arnes);

        await abrirMapa();

        expect(arnes.sonda.pruebas, [paqueteMontevideo.origen]);
        expect(prueba(), PruebaDelMapa.respondio);
        expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
        expect(situacion().aviso, isNull);
      },
    );

    test('con datos móviles también, y el aviso de descargar sigue siendo el de siempre', () async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);

      await abrirMapa();

      expect(arnes.sonda.pruebas, [paqueteMontevideo.origen]);
      expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
      expect(situacion().aviso, AvisoDatosMoviles(paqueteMontevideo));
    });

    test(
      'el archivo borrado del servidor (404): fondo liso y «No pudimos cargar el mapa»',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        contenedor = armar(arnes);

        await abrirMapa();

        expect(prueba(), PruebaDelMapa.fallo);
        expect(situacion().fuente.tipo, FuenteTiles.sinTiles);
        expect(situacion().aviso, const AvisoMapaNoCarga());
      },
    );

    test('cualquier error del servidor (403, 416, 500, 503) es lo mismo que un 404', () async {
      for (final status in [403, 416, 500, 503]) {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda
          ..caidos.add(paqueteMontevideo.origen)
          ..statusError = status;
        contenedor = armar(arnes);

        await abrirMapa();

        expect(situacion().aviso, const AvisoMapaNoCarga(), reason: '$status');
      }
    });

    test('el servidor caído o que no responde a tiempo: «No pudimos cargar el mapa», no «Sin '
        'conexión»', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      arnes.sonda.servidorCaido = true;
      contenedor = armar(arnes);

      await abrirMapa();

      expect(prueba(), PruebaDelMapa.fallo);
      expect(situacion().aviso, const AvisoMapaNoCarga());
      expect(situacion().aviso, isNot(const AvisoSinConexion()));
    });

    test(
      'con datos móviles y el archivo caído, el aviso de descargar da lugar al de la falla',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        contenedor = armar(arnes);

        await abrirMapa();

        expect(situacion().aviso, const AvisoMapaNoCarga());
      },
    );

    test(
      'mientras la prueba no contesta no se afirma nada: el mapa en línea, sin aviso de falla',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.espera = Completer<void>();
        contenedor = armar(arnes);

        await abrirMapa();

        expect(arnes.sonda.enCurso, 1);
        expect(prueba(), isNull);
        expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
        expect(situacion().aviso, isNull);

        // El servidor por fin dice que no: recién ahí sale el aviso.
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        arnes.sonda.espera!.complete();
        await _dejarCorrer();

        expect(situacion().aviso, const AvisoMapaNoCarga());
      },
    );

    test('la prueba lenta no demora el catálogo: «Descargar mapa» y el peso salen igual', () async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      arnes.sonda.espera = Completer<void>();
      contenedor = armar(arnes);

      await abrirMapa();

      expect(
        contenedor.read(paqueteDelAmbitoProvider(ambitoMontevideo)).value,
        PaqueteHallado(paqueteMontevideo),
      );
      expect(situacion().aviso, AvisoDatosMoviles(paqueteMontevideo));
    });

    test('un error de programación en la prueba no afirma nada: ni falla ni aviso', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      arnes.sonda.lanza = true;
      contenedor = armar(arnes);

      await abrirMapa();

      expect(prueba(), isNull);
      expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
      expect(situacion().aviso, isNull);
    });

    test(
      'con la sonda sin cablear (main.dart no preparó los mapas) la prueba no afirma nada',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        contenedor = ProviderContainer(
          overrides: [
            monitorConectividadProvider.overrideWithValue(arnes.conectividad),
            paquetesTilesRepositoryProvider.overrideWithValue(arnes.repositorio),
            descargadorPaquetesTilesProvider.overrideWithValue(arnes.descargador),
          ],
        );
        addTearDown(contenedor.dispose);
        addTearDown(() => unawaited(arnes.cerrar()));

        await abrirMapa();

        expect(prueba(), isNull);
        expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
        expect(situacion().aviso, isNull);
      },
    );
  });

  group('un paquete en varios archivos', () {
    test('se prueban todos a la vez y, si todos contestan, el mapa en línea', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [_montevideoEnPartes]);
      contenedor = armar(arnes);

      await abrirMapa();

      expect(arnes.sonda.pruebas, [for (final parte in _montevideoEnPartes.partes) parte.origen]);
      expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
      expect(situacion().aviso, isNull);
    });

    test('alcanza con que falte uno para que las calles no se vean completas', () async {
      for (final indice in [0, 1]) {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [_montevideoEnPartes]);
        arnes.sonda.caidos.add(_montevideoEnPartes.partes[indice].origen);
        contenedor = armar(arnes);

        await abrirMapa();

        expect(arnes.sonda.pruebas, hasLength(2), reason: 'parte $indice');
        expect(situacion().aviso, const AvisoMapaNoCarga(), reason: 'parte $indice');
      }
    });
  });

  group('cuándo no se prueba', () {
    test(
      'sin conexión: no se pide nada, vale el aviso de sin conexión; al volver, se prueba',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        contenedor = armar(arnes);

        await abrirMapa();

        expect(arnes.sonda.pruebas, isEmpty);
        expect(prueba(), isNull);
        expect(situacion().aviso, const AvisoSinConexion());

        arnes.conectividad.cambiarA(TipoConexion.wifi);
        await _dejarCorrer();

        expect(arnes.sonda.pruebas, [paqueteMontevideo.origen]);
        expect(situacion().aviso, const AvisoMapaNoCarga());

        // Y cuando el archivo vuelve, el aviso se va solo al recuperar la señal.
        arnes.sonda.caidos.clear();
        arnes.conectividad.cambiarA(TipoConexion.sinConexion);
        await _dejarCorrer();
        expect(situacion().aviso, const AvisoSinConexion());
        arnes.conectividad.cambiarA(TipoConexion.wifi);
        await _dejarCorrer();

        expect(situacion().aviso, isNull);
        expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
      },
    );

    test(
      'con el mapa de la ciudad en el teléfono: se dibuja lo descargado y no se pide nada',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
        contenedor = armar(arnes);

        await abrirMapa();

        expect(arnes.sonda.pruebas, isEmpty);
        expect(situacion().fuente.tipo, FuenteTiles.pmtilesOffline);
        expect(situacion().aviso, isNull);
      },
    );

    test(
      'si se borra el mapa descargado con el archivo caído, ahí sí se prueba y sale el aviso',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
        contenedor = armar(arnes);
        await abrirMapa();
        expect(arnes.sonda.pruebas, isEmpty);

        await arnes.repositorio.quitar(paqueteMontevideo.id);
        await _dejarCorrer();

        expect(arnes.sonda.pruebas, [paqueteMontevideo.origen]);
        expect(situacion().aviso, const AvisoMapaNoCarga());
      },
    );

    test('sin saber en qué ciudad trabaja: no hay archivo que probar', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      const ambito = AmbitoTrabajo();

      await abrirMapa(ambito);

      expect(arnes.sonda.pruebas, isEmpty);
      expect(situacion(ambito), const SituacionMapa.sinDatos());
    });

    test(
      'si el catálogo no trae la ciudad: el aviso es el del catálogo y no se pide nada',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteCanelones]);
        contenedor = armar(arnes);

        await abrirMapa();

        expect(arnes.sonda.pruebas, isEmpty);
        expect(prueba(), isNull);
        expect(situacion().aviso, const AvisoMapaNoCarga());
      },
    );

    test('pasar de Wi-Fi a datos móviles con el mapa abierto no vuelve a probar: es una prueba '
        'por apertura', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      await abrirMapa();

      arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
      await _dejarCorrer();
      arnes.conectividad.cambiarA(TipoConexion.wifi);
      await _dejarCorrer();

      expect(arnes.sonda.pruebas, hasLength(1));
      expect(situacion().aviso, isNull);
    });
  });

  group('cada ciudad con su archivo', () {
    test('el archivo caído de una ciudad no marca a la otra', () async {
      arnes = ArnesMapa(
        conexion: TipoConexion.wifi,
        catalogo: [paqueteMontevideo, paqueteCanelones],
      );
      arnes.sonda.caidos.add(paqueteMontevideo.origen);
      contenedor = armar(arnes);

      await abrirMapa();
      await abrirMapa(_ambitoCanelones);

      expect(situacion().aviso, const AvisoMapaNoCarga());
      expect(situacion(_ambitoCanelones).aviso, isNull);
      expect(situacion(_ambitoCanelones).fuente.origenes, [paqueteCanelones.origen.toString()]);
      expect(arnes.sonda.pruebas, containsAll([paqueteMontevideo.origen, paqueteCanelones.origen]));
    });

    test(
      'la respuesta que llega tarde, cuando ya se perdió la señal, no queda pegada al volver',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.espera = Completer<void>();
        contenedor = armar(arnes);
        await abrirMapa();
        expect(arnes.sonda.enCurso, 1);

        arnes.conectividad.cambiarA(TipoConexion.sinConexion);
        await _dejarCorrer();
        expect(situacion().aviso, const AvisoSinConexion());

        // El servidor contesta que no, pero ya no importa: el pedido era de antes de perder la señal.
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        arnes.sonda.espera!.complete();
        arnes.sonda.espera = null;
        await _dejarCorrer();
        expect(situacion().aviso, const AvisoSinConexion());

        arnes.sonda.caidos.clear();
        arnes.conectividad.cambiarA(TipoConexion.wifi);
        await _dejarCorrer();

        expect(arnes.sonda.pruebas, hasLength(2));
        expect(situacion().aviso, isNull);
        expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
      },
    );
  });

  group('una prueba por apertura y «Reintentar»', () {
    test('volver atrás y reentrar vuelve a probar', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      arnes.sonda.caidos.add(paqueteMontevideo.origen);
      contenedor = armar(arnes);
      final abierta = contenedor.listen(situacionMapaProvider(ambitoMontevideo), (_, _) {});
      await _dejarCorrer();
      expect(situacion().aviso, const AvisoMapaNoCarga());

      // Sale del mapa, el archivo vuelve al servidor, y reentra.
      abierta.close();
      await _dejarCorrer();
      arnes.sonda.caidos.clear();
      await abrirMapa();

      expect(arnes.sonda.pruebas, hasLength(2));
      expect(situacion().aviso, isNull);
    });

    test(
      'invalidar la prueba («Reintentar») la repite; si el archivo volvió, el aviso se va',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        contenedor = armar(arnes);
        await abrirMapa();
        expect(situacion().aviso, const AvisoMapaNoCarga());

        arnes.sonda.caidos.clear();
        contenedor.invalidate(pruebaDelMapaProvider(ambitoMontevideo));
        await _dejarCorrer();

        expect(arnes.sonda.pruebas, hasLength(2));
        expect(situacion().aviso, isNull);
        expect(situacion().fuente.tipo, FuenteTiles.servidorOnline);
      },
    );

    test(
      'si sigue caído, el aviso no parpadea mientras se vuelve a probar y sigue después',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        arnes.sonda.caidos.add(paqueteMontevideo.origen);
        contenedor = armar(arnes);
        await abrirMapa();

        arnes.sonda.espera = Completer<void>();
        contenedor.invalidate(pruebaDelMapaProvider(ambitoMontevideo));
        await _dejarCorrer();

        expect(arnes.sonda.enCurso, 1);
        expect(situacion().aviso, const AvisoMapaNoCarga());
        expect(situacion().fuente.tipo, FuenteTiles.sinTiles);

        arnes.sonda.espera!.complete();
        await _dejarCorrer();

        expect(situacion().aviso, const AvisoMapaNoCarga());
        expect(arnes.sonda.enCurso, 0);
      },
    );
  });

  group('los pedidos en vuelo se cancelan cuando nadie espera la respuesta', () {
    test('cada prueba sale con su cancelación y, si todo contesta, no se cancela nada', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [_montevideoEnPartes]);
      contenedor = armar(arnes);

      await abrirMapa();
      expect(prueba(), PruebaDelMapa.respondio);

      expect(arnes.sonda.pruebas, hasLength(2));
      expect(arnes.sonda.conCancelacion, 2);
      expect(arnes.sonda.canceladas, 0);
    });

    test('salir del mapa con la prueba en vuelo la cancela (todas las partes)', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [_montevideoEnPartes]);
      arnes.sonda.espera = Completer<void>();
      contenedor = armar(arnes);
      final abierta = contenedor.listen(situacionMapaProvider(ambitoMontevideo), (_, _) {});
      await _dejarCorrer();
      expect(arnes.sonda.enCurso, 2);
      expect(arnes.sonda.canceladas, 0, reason: 'el mapa sigue abierto: nadie cancela');

      abierta.close();
      await _dejarCorrer();

      expect(arnes.sonda.canceladas, 2);
      expect(arnes.sonda.enCurso, 0);
    });

    test('invalidar la prueba («Reintentar») cancela la vieja y la nueva manda', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      arnes.sonda.espera = Completer<void>();
      contenedor = armar(arnes);
      await abrirMapa();
      expect(arnes.sonda.enCurso, 1);

      contenedor.invalidate(pruebaDelMapaProvider(ambitoMontevideo));
      await _dejarCorrer();

      expect(arnes.sonda.pruebas, hasLength(2));
      expect(arnes.sonda.canceladas, 1, reason: 'la vieja se aborta; no queda su conexión abierta');
      expect(arnes.sonda.enCurso, 1, reason: 'solo sigue en vuelo la nueva');

      arnes.sonda.espera!.complete();
      await _dejarCorrer();

      expect(prueba(), PruebaDelMapa.respondio);
      expect(situacion().aviso, isNull);
    });

    test('si una parte falla, las demás no se siguen esperando: se cancelan', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [_montevideoEnPartes]);
      arnes.sonda.caidos.add(_montevideoEnPartes.partes[0].origen);
      arnes.sonda.esperas[_montevideoEnPartes.partes[1].origen] = Completer<void>();
      contenedor = armar(arnes);

      await abrirMapa();

      expect(situacion().aviso, const AvisoMapaNoCarga());
      expect(arnes.sonda.canceladas, 1);
      expect(arnes.sonda.enCurso, 0);
    });
  });
}
