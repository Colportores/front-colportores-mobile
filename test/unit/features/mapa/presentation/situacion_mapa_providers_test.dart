// La situación del mapa y el pedido de «Descargar mapa» (#190), sin pantalla: la conexión, lo
// descargado y el catálogo entran por los puertos falsos; un fallo de cualquiera se vuelve un valor
// (Riverpod 3 reintenta solo las excepciones) y mientras algo no se sabe no se afirma nada.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_base_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/situacion_mapa_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/repositories/paquetes_tiles_repository.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/tiles_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/mapa_descargas_arnes.dart';
import '../../../../helpers/tiles_falsos.dart';

/// Un repositorio cuyo catálogo revienta (lanza en vez de devolver una falla).
final class _RepositorioQueLanza implements PaquetesTilesRepository {
  @override
  Future<Either<Failure, List<PaqueteTiles>>> catalogo() async => throw StateError('catálogo roto');

  @override
  Future<Either<Failure, List<PaqueteDescargado>>> descargados() async => const Right([]);

  @override
  Stream<List<PaqueteDescargado>> observarDescargados() => Stream.value(const []);

  @override
  Future<Either<Failure, Unit>> registrar(PaqueteDescargado descargado) async => const Right(unit);

  @override
  Future<Either<Failure, Unit>> quitar(String paqueteId) async => const Right(unit);

  @override
  Future<Either<Failure, Unit>> reconciliar() async => const Right(unit);
}

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

  group('situacionMapaProvider', () {
    test(
      'mientras no se sabe la conexión: el color liso y ningún aviso (nunca «Sin conexión»)',
      () {
        arnes = ArnesMapa(conexion: TipoConexion.sinConexion);
        contenedor = armar(arnes);

        final situacion = observar(contenedor, situacionMapaProvider(ambitoMontevideo));

        expect(situacion, const SituacionMapa.sinDatos());
      },
    );

    test('sin conexión y sin descargar: el aviso de sin conexión y sin tiles', () async {
      arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      final provider = situacionMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);

      await _dejarCorrer();

      final situacion = contenedor.read(provider);
      expect(situacion.aviso, const AvisoSinConexion());
      expect(situacion.fuente.tipo, FuenteTiles.sinTiles);
    });

    test('con datos móviles: mapa en línea, aviso con el peso, y con Wi-Fi no hay aviso', () async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      final provider = situacionMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();

      expect(contenedor.read(provider).aviso, AvisoDatosMoviles(paqueteMontevideo));
      expect(contenedor.read(provider).fuente.tipo, FuenteTiles.servidorOnline);

      arnes.conectividad.cambiarA(TipoConexion.wifi);
      await _dejarCorrer();

      expect(contenedor.read(provider).aviso, isNull);
      expect(contenedor.read(provider).fuente.tipo, FuenteTiles.servidorOnline);
    });

    test('al volver la conexión se vuelve a preguntar el catálogo', () async {
      arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      final provider = paqueteDelAmbitoProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      expect(contenedor.read(provider).value, const PaqueteSinRed());

      arnes.conectividad.cambiarA(TipoConexion.wifi);
      await _dejarCorrer();

      expect(contenedor.read(provider).value, PaqueteHallado(paqueteMontevideo));
    });

    test(
      'el catálogo que lanza o devuelve una falla es «no disponible», no una excepción',
      () async {
        for (final lanza in [true, false]) {
          arnes = ArnesMapa(conexion: TipoConexion.wifi);
          if (!lanza) arnes.repositorio.falloCatalogo = const FailureSinConexion();
          contenedor = ProviderContainer(
            overrides: [
              monitorConectividadProvider.overrideWithValue(arnes.conectividad),
              paquetesTilesRepositoryProvider.overrideWithValue(
                lanza ? _RepositorioQueLanza() : arnes.repositorio,
              ),
              descargadorPaquetesTilesProvider.overrideWithValue(arnes.descargador),
            ],
          );
          addTearDown(contenedor.dispose);
          final provider = paqueteDelAmbitoProvider(ambitoMontevideo);
          observar(contenedor, provider);
          observar(contenedor, situacionMapaProvider(ambitoMontevideo));
          await _dejarCorrer();

          expect(
            contenedor.read(provider).value,
            const PaqueteNoDisponible(),
            reason: 'lanza=$lanza',
          );
          expect(
            contenedor.read(situacionMapaProvider(ambitoMontevideo)).aviso,
            const AvisoMapaNoCarga(),
            reason: 'lanza=$lanza',
          );
        }
      },
    );

    test('un ámbito desconocido no consulta el catálogo ni afirma nada con conexión', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      const ambito = AmbitoTrabajo();
      final provider = situacionMapaProvider(ambito);
      observar(contenedor, provider);
      await _dejarCorrer();

      expect(contenedor.read(paqueteDelAmbitoProvider(ambito)).value, const PaqueteSinAmbito());
      expect(contenedor.read(provider), const SituacionMapa.sinDatos());
    });

    test(
      'con el paquete descargado, el mapa sale del teléfono y fuenteMapaProvider lo repite',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
        contenedor = armar(arnes);
        observar(contenedor, situacionMapaProvider(ambitoMontevideo));
        await _dejarCorrer();

        final fuente = contenedor.read(fuenteMapaProvider(ambitoMontevideo));

        expect(fuente.tipo, FuenteTiles.pmtilesOffline);
        expect(fuente.origenes, [rutaFinalDe(paqueteMontevideo, 0)]);
        expect(contenedor.read(situacionMapaProvider(ambitoMontevideo)).aviso, isNull);
      },
    );
  });

  group('descartes del aviso en la sesión', () {
    test('minimizar el aviso rojo y ocultar el de datos móviles son independientes', () {
      arnes = ArnesMapa();
      contenedor = armar(arnes);
      final notificador = contenedor.read(descartesAvisoMapaProvider.notifier);
      expect(contenedor.read(descartesAvisoMapaProvider), const DescartesAvisoMapa());

      notificador.minimizarSinConexion();
      expect(
        contenedor.read(descartesAvisoMapaProvider),
        const DescartesAvisoMapa(sinConexionMinimizado: true),
      );

      notificador.ocultarDatosMoviles();
      expect(
        contenedor.read(descartesAvisoMapaProvider),
        const DescartesAvisoMapa(sinConexionMinimizado: true, datosMovilesOculto: true),
      );
    });
  });

  group('solicitudMapaProvider («Descargar mapa»)', () {
    test('sin ámbito conocido dice qué falta y no queda ocupada', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      const ambito = AmbitoTrabajo();
      final provider = solicitudMapaProvider(ambito);
      observar(contenedor, provider);

      await contenedor.read(provider.notifier).pedir();

      final estado = contenedor.read(provider);
      expect(estado.falla, const FailureCiudadRequerida());
      expect(estado.ocupada, isFalse);
      expect(estado.enEspera, isFalse);
    });

    test(
      'sin saber todavía el paquete queda en espera y arranca cuando el catálogo responde',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        contenedor = armar(arnes);
        final provider = solicitudMapaProvider(ambitoMontevideo);
        observar(contenedor, provider);
        await _dejarCorrer();

        await contenedor.read(provider.notifier).pedir();
        expect(contenedor.read(provider).enEspera, isTrue);
        expect(arnes.servidor.pedidos, isEmpty);

        arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await _dejarCorrer();
        await arnes.descargador.esperar('ciudad-montevideo');
        await _dejarCorrer();

        expect(arnes.montevideoDescargado, isTrue);
        final estado = contenedor.read(provider);
        expect(estado.enEspera, isFalse);
        expect(estado.ocupada, isFalse);
        expect(estado.falla, isNull);
      },
    );

    test('con el paquete conocido, dos pedidos juntos son una sola descarga', () async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
      final provider = solicitudMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      final antes = arnes.conectividad.lecturas;

      final primero = contenedor.read(provider.notifier).pedir();
      final segundo = contenedor.read(provider.notifier).pedir();
      await Future.wait([primero, segundo]);
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();

      expect(arnes.conectividad.lecturas - antes, 1);
      expect(arnes.servidor.pedidos, hasLength(1));
      expect(arnes.montevideoDescargado, isTrue);
    });

    test('una descarga que falla deja la falla; la siguiente que arranca la borra', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
      final provider = solicitudMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      arnes.servidor.statusError = 503;

      await contenedor.read(provider.notifier).pedir();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();

      expect(contenedor.read(provider).falla, isA<FailureServidor>());
      expect(contenedor.read(provider).ocupada, isFalse);

      arnes.servidor.statusError = null;
      await contenedor.read(provider.notifier).pedir();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();

      expect(contenedor.read(provider).falla, isNull);
      expect(arnes.montevideoDescargado, isTrue);
    });

    test(
      'si el descargador no está cableado, el pedido falla con un valor y no deja nada trabado',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        // Sin el override del descargador: leerlo lanza `UnimplementedError`.
        contenedor = ProviderContainer(
          overrides: [
            monitorConectividadProvider.overrideWithValue(arnes.conectividad),
            paquetesTilesRepositoryProvider.overrideWithValue(arnes.repositorio),
          ],
        );
        addTearDown(contenedor.dispose);
        observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
        final provider = solicitudMapaProvider(ambitoMontevideo);
        observar(contenedor, provider);
        await _dejarCorrer();

        await contenedor.read(provider.notifier).pedir();

        final estado = contenedor.read(provider);
        expect(estado.falla, isA<FailureInesperado>());
        expect(estado.ocupada, isFalse);
      },
    );

    test('el estado se compara por valor y `copiar` cambia solo lo que se pide', () {
      const base = EstadoSolicitudMapa(enEspera: true, falla: FailureCiudadRequerida());

      expect(base.copiar(), base);
      expect(base.copiar(ocupada: true).ocupada, isTrue);
      expect(base.copiar(sinFalla: true).falla, isNull);
      expect(base.copiar(sinFalla: true).enEspera, isTrue);
      expect(const EstadoSolicitudMapa(), const EstadoSolicitudMapa());
    });
  });
}
