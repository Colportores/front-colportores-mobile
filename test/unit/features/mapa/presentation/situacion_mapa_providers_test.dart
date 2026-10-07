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
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
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

    test(
      'con el paquete ya descargado, la consulta dice «ya descargado» y no «no disponible»',
      () async {
        arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
        await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
        contenedor = armar(arnes);
        final consulta = paqueteDelAmbitoProvider(ambitoMontevideo);
        observar(contenedor, consulta);
        observar(contenedor, situacionMapaProvider(ambitoMontevideo));
        await _dejarCorrer();

        expect(contenedor.read(consulta).value, const PaqueteYaDescargado());
        final situacion = contenedor.read(situacionMapaProvider(ambitoMontevideo));
        expect(situacion.fuente.tipo, FuenteTiles.pmtilesOffline);
        expect(situacion.aviso, isNull);
      },
    );

    test('un catálogo que no cubre la ciudad sigue siendo «no disponible» aunque haya otro mapa '
        'descargado', () async {
      // El mapa descargado es de otra ciudad: no cubre este ámbito.
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteCanelones]);
      await arnes.repositorio.registrar(descargadoDe(paqueteCanelones));
      contenedor = armar(arnes);
      observar(contenedor, situacionMapaProvider(ambitoMontevideo));
      await _dejarCorrer();

      expect(
        contenedor.read(paqueteDelAmbitoProvider(ambitoMontevideo)).value,
        const PaqueteNoDisponible(),
      );
      expect(
        contenedor.read(situacionMapaProvider(ambitoMontevideo)).aviso,
        const AvisoMapaNoCarga(),
      );
    });

    test('si se borra el mapa descargado con la conexión igual, vuelve a preguntar y ofrece el del '
        'catálogo, sin «No pudimos cargar el mapa»', () async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
      contenedor = armar(arnes);
      final provider = situacionMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      expect(contenedor.read(provider).fuente.tipo, FuenteTiles.pmtilesOffline);
      expect(contenedor.read(provider).aviso, isNull);

      await arnes.repositorio.quitar(paqueteMontevideo.id);
      await _dejarCorrer();

      final situacion = contenedor.read(provider);
      expect(situacion.aviso, AvisoDatosMoviles(paqueteMontevideo));
      expect(situacion.fuente.tipo, FuenteTiles.servidorOnline);
    });

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

  // Lo que el aviso le dice al colportor entre tocar «Descargar mapa» y tener el mapa (decisión del
  // 06/10, P1): «Se descarga sola cuando vuelva la señal.» (esperaSenal), «Descargando el mapa…»
  // (bajando), y el botón deshabilitado mientras cualquiera de las dos dure (enMarcha).
  group('solicitudMapaProvider: en qué está el pedido', () {
    test('enMarcha cubre ocupada, en espera, en cola y bajando; esperaSenal, solo las dos que '
        'esperan la señal', () {
      const casos = <(String, EstadoSolicitudMapa, bool, bool)>[
        ('en reposo', EstadoSolicitudMapa(), false, false),
        ('ocupada', EstadoSolicitudMapa(ocupada: true), true, false),
        ('en espera del catálogo', EstadoSolicitudMapa(enEspera: true), true, true),
        ('en cola', EstadoSolicitudMapa(enCola: true), true, true),
        ('bajando', EstadoSolicitudMapa(bajando: true), true, false),
        ('solo una falla', EstadoSolicitudMapa(falla: FailureServidor()), false, false),
      ];
      for (final (nombre, estado, enMarcha, esperaSenal) in casos) {
        expect(estado.enMarcha, enMarcha, reason: nombre);
        expect(estado.esperaSenal, esperaSenal, reason: nombre);
      }
    });

    /// Con el catálogo leído (había conexión) y el teléfono ya sin señal: el pedido va a la cola.
    Future<Completer<void>> montarSinSenal() async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
      observar(contenedor, solicitudMapaProvider(ambitoMontevideo));
      await _dejarCorrer();
      arnes.conectividad.cambiarA(TipoConexion.sinConexion);
      await _dejarCorrer();
      // Un disco que no escribe hasta que el test lo deja: la descarga queda «bajando».
      final compuerta = Completer<void>();
      arnes.archivos.compuerta = compuerta.future;
      return compuerta;
    }

    test(
      'sin señal queda en cola, sin falla ni «ocupada», y pedir de nuevo no encola otra',
      () async {
        final compuerta = await montarSinSenal();
        final provider = solicitudMapaProvider(ambitoMontevideo);

        await contenedor.read(provider.notifier).pedir();

        var estado = contenedor.read(provider);
        expect(estado.enCola, isTrue);
        expect(estado.esperaSenal, isTrue);
        expect(estado.enMarcha, isTrue);
        expect(estado.ocupada, isFalse);
        expect(estado.bajando, isFalse);
        expect(estado.falla, isNull);
        expect(arnes.servidor.pedidos, isEmpty);

        final lecturas = arnes.conectividad.lecturas;
        await contenedor.read(provider.notifier).pedir();
        await contenedor.read(provider.notifier).pedir();
        await _dejarCorrer();

        estado = contenedor.read(provider);
        expect(estado.enCola, isTrue);
        expect(arnes.conectividad.lecturas, lecturas, reason: 'no se encoló otra descarga');
        compuerta.complete();
      },
    );

    test('al volver la señal pasa de «en cola» a «bajando» y, al terminar, a nada', () async {
      final compuerta = await montarSinSenal();
      final provider = solicitudMapaProvider(ambitoMontevideo);
      final vistos = <EstadoSolicitudMapa>[];
      final suscripcion = contenedor.listen(provider, (_, nuevo) => vistos.add(nuevo));
      addTearDown(suscripcion.close);
      await contenedor.read(provider.notifier).pedir();

      arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
      await _dejarCorrer();

      var estado = contenedor.read(provider);
      expect(estado.bajando, isTrue);
      expect(estado.enCola, isFalse);
      expect(estado.esperaSenal, isFalse);
      expect(estado.enMarcha, isTrue);

      compuerta.complete();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();

      estado = contenedor.read(provider);
      expect(estado, const EstadoSolicitudMapa());
      expect(arnes.montevideoDescargado, isTrue);
      // Nunca quedó el botón libre en el medio: de «en cola» a «bajando» sin pasar por «reposo».
      final alMedio = vistos.skipWhile((e) => !e.enCola).takeWhile((e) => e.enMarcha);
      expect(alMedio.any((e) => e.bajando), isTrue);
    });

    test(
      'al volver la señal con el pedido en cola, pasa a «bajando» sin esperar al servidor',
      () async {
        final compuerta = await montarSinSenal();
        final provider = solicitudMapaProvider(ambitoMontevideo);
        await contenedor.read(provider.notifier).pedir();
        expect(contenedor.read(provider).enCola, isTrue);
        // El servidor tarda en mandar los encabezados: hasta el primer pedazo el descargador no dice más.
        final espera = Completer<void>();
        arnes.servidor.esperaAntesDeContestar = espera;
        addTearDown(() {
          if (!espera.isCompleted) espera.complete();
        });

        arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await _dejarCorrer();

        expect(arnes.servidor.pedidos, hasLength(1), reason: 'pidió y no le contestaron todavía');
        final estado = contenedor.read(provider);
        expect(estado.bajando, isTrue);
        expect(estado.enCola, isFalse);
        expect(estado.esperaSenal, isFalse);
        expect(estado.enMarcha, isTrue);
        expect(estado.falla, isNull);

        espera.complete();
        compuerta.complete();
        await arnes.descargador.esperar('ciudad-montevideo');
        await _dejarCorrer();
        expect(contenedor.read(provider), const EstadoSolicitudMapa());
        expect(arnes.montevideoDescargado, isTrue);
      },
    );

    test('un pedido más mientras baja no hace otra descarga ni cambia el estado', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
      final provider = solicitudMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      final compuerta = Completer<void>();
      arnes.archivos.compuerta = compuerta.future;

      await contenedor.read(provider.notifier).pedir();
      await _dejarCorrer();
      expect(contenedor.read(provider).bajando, isTrue);
      final lecturas = arnes.conectividad.lecturas;

      await contenedor.read(provider.notifier).pedir();

      expect(contenedor.read(provider).bajando, isTrue);
      expect(arnes.conectividad.lecturas, lecturas);
      expect(arnes.servidor.pedidos, hasLength(1));
      compuerta.complete();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();
      expect(contenedor.read(provider), const EstadoSolicitudMapa());
    });

    test('si se cae la señal a mitad de la descarga vuelve a «en cola» y retoma sola', () async {
      arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
      final provider = solicitudMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      final compuerta = Completer<void>();
      arnes.archivos.compuerta = compuerta.future;
      await contenedor.read(provider.notifier).pedir();
      await _dejarCorrer();
      expect(contenedor.read(provider).bajando, isTrue);

      arnes.conectividad.cambiarA(TipoConexion.sinConexion);
      await _dejarCorrer();

      var estado = contenedor.read(provider);
      expect(estado.enCola, isTrue);
      expect(estado.bajando, isFalse);
      expect(estado.falla, isNull);

      compuerta.complete();
      await _dejarCorrer();
      arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
      await _dejarCorrer();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();

      estado = contenedor.read(provider);
      expect(estado, const EstadoSolicitudMapa());
      expect(arnes.montevideoDescargado, isTrue);
    });

    test('una falla a mitad de la descarga deja la falla y nada «en marcha»', () async {
      arnes = ArnesMapa(conexion: TipoConexion.wifi, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
      final provider = solicitudMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();
      // El disco se llena en el segundo pedazo de 1000 bytes.
      arnes.archivos.discoLlenoDespuesDe = 1200;

      await contenedor.read(provider.notifier).pedir();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();

      final estado = contenedor.read(provider);
      expect(estado.falla, isA<FailureEspacioInsuficiente>());
      expect(estado.enMarcha, isFalse);
      expect(estado.esperaSenal, isFalse);

      // Con lugar otra vez, el siguiente pedido arranca y borra la falla.
      arnes.archivos.discoLlenoDespuesDe = null;
      await contenedor.read(provider.notifier).pedir();
      await arnes.descargador.esperar('ciudad-montevideo');
      await _dejarCorrer();
      expect(contenedor.read(provider), const EstadoSolicitudMapa());
      expect(arnes.montevideoDescargado, isTrue);
    });

    // Entre el pedido y el primer `DescargaEnCurso` el descargador todavía no dice nada (espera los
    // encabezados del servidor, hasta 30 s): el pedido ya está en marcha y el botón no se libera.
    group('con el servidor tardando en contestar', () {
      late Completer<void> espera;

      Future<void> montarConServidorLento() async {
        arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
        contenedor = armar(arnes);
        observar(contenedor, paqueteDelAmbitoProvider(ambitoMontevideo));
        observar(contenedor, solicitudMapaProvider(ambitoMontevideo));
        await _dejarCorrer();
        espera = Completer<void>();
        arnes.servidor.esperaAntesDeContestar = espera;
        addTearDown(() {
          if (!espera.isCompleted) espera.complete();
        });
      }

      test(
        'queda «bajando» desde el pedido, sin ocupada ni falla, y al terminar vuelve a nada',
        () async {
          await montarConServidorLento();
          final provider = solicitudMapaProvider(ambitoMontevideo);

          await contenedor.read(provider.notifier).pedir();
          await _dejarCorrer();

          expect(arnes.servidor.pedidos, hasLength(1));
          expect(arnes.descargador.estadoDe('ciudad-montevideo'), isNull);
          var estado = contenedor.read(provider);
          expect(estado.bajando, isTrue);
          expect(estado.enMarcha, isTrue);
          expect(estado.ocupada, isFalse);
          expect(estado.esperaSenal, isFalse);
          expect(estado.falla, isNull);

          // Otro pedido mientras tanto no hace nada.
          await contenedor.read(provider.notifier).pedir();
          expect(arnes.servidor.pedidos, hasLength(1));

          espera.complete();
          await arnes.descargador.esperar('ciudad-montevideo');
          await _dejarCorrer();

          estado = contenedor.read(provider);
          expect(estado, const EstadoSolicitudMapa());
          expect(arnes.montevideoDescargado, isTrue);
        },
      );

      test('si el servidor responde con error, llega la falla y nada queda «en marcha»', () async {
        await montarConServidorLento();
        arnes.servidor.statusError = 500;
        final provider = solicitudMapaProvider(ambitoMontevideo);

        await contenedor.read(provider.notifier).pedir();
        await _dejarCorrer();
        expect(contenedor.read(provider).bajando, isTrue);

        espera.complete();
        await arnes.descargador.esperar('ciudad-montevideo');
        await _dejarCorrer();

        final estado = contenedor.read(provider);
        expect(estado.falla, const FailureServidor(status: 500));
        expect(estado.enMarcha, isFalse);
      });

      test(
        'con una falla anterior en el descargador, el pedido nuevo también queda «bajando»',
        () async {
          await montarConServidorLento();
          final provider = solicitudMapaProvider(ambitoMontevideo);
          arnes.servidor
            ..esperaAntesDeContestar = null
            ..statusError = 500;
          await contenedor.read(provider.notifier).pedir();
          await arnes.descargador.esperar('ciudad-montevideo');
          await _dejarCorrer();
          expect(arnes.descargador.estadoDe('ciudad-montevideo'), isA<DescargaFallida>());
          expect(contenedor.read(provider).falla, isNotNull);

          // El estado que queda en el descargador es el de la falla vieja; el pedido nuevo es otro.
          arnes.servidor
            ..statusError = null
            ..esperaAntesDeContestar = espera;
          await contenedor.read(provider.notifier).pedir();
          await _dejarCorrer();

          expect(arnes.descargador.estadoDe('ciudad-montevideo'), isA<DescargaFallida>());
          final estado = contenedor.read(provider);
          expect(estado.bajando, isTrue);
          expect(estado.enMarcha, isTrue);
          expect(estado.falla, isNull);
        },
      );
    });

    test('el pedido en espera del catálogo cuenta como «esperando la señal»', () async {
      arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
      contenedor = armar(arnes);
      final provider = solicitudMapaProvider(ambitoMontevideo);
      observar(contenedor, provider);
      await _dejarCorrer();

      await contenedor.read(provider.notifier).pedir();
      await contenedor.read(provider.notifier).pedir();

      final estado = contenedor.read(provider);
      expect(estado.enEspera, isTrue);
      expect(estado.esperaSenal, isTrue);
      expect(estado.enMarcha, isTrue);
      expect(arnes.servidor.pedidos, isEmpty);
    });
  });
}
