// HU-UBI-001 / vista 03: las reglas del alta (GPS, punto, tipo, ciudad, dirección «Del mapa» y
// «Editado», registro) sin widgets ni plugins.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';

const _otroPunto = Coordenadas(lat: -34.8900, lon: -56.1300);

/// Deja correr la espera del punto (20 ms en los tests) y lo que dispara.
Future<void> _esperar() => Future<void>.delayed(const Duration(milliseconds: 90));

final class _Banco {
  _Banco({
    GpsFalso? gps,
    GeocodificadorFalso? geocodificador,
    CiudadesFalsas? ciudades,
    RepoAltaFalso? repo,
    ParametrosAlta parametros = parametrosAlta,
    List<Override> extra = const [],
  }) : gps = gps ?? GpsFalso(),
       geocodificador =
           geocodificador ??
           GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234')),
       ciudades = ciudades ?? CiudadesFalsas(),
       repo = repo ?? RepoAltaFalso() {
    contenedor = ProviderContainer(
      overrides: [
        ...overridesAlta(
          gps: this.gps,
          geocodificador: this.geocodificador,
          ciudades: this.ciudades,
          repo: this.repo,
        ),
        ...extra,
      ],
    );
    proveedor = altaUbicacionProvider(parametros);
    contenedor.listen(proveedor, (_, _) {});
  }

  final GpsFalso gps;
  final GeocodificadorFalso geocodificador;
  final CiudadesFalsas ciudades;
  final RepoAltaFalso repo;
  late final ProviderContainer contenedor;
  late final NotifierProvider<AltaUbicacionNotifier, AltaUbicacionState> proveedor;

  AltaUbicacionState get estado => contenedor.read(proveedor);
  AltaUbicacionNotifier get notificador => contenedor.read(proveedor.notifier);

  void cerrar() => contenedor.dispose();
}

_Banco _banco({
  GpsFalso? gps,
  GeocodificadorFalso? geocodificador,
  CiudadesFalsas? ciudades,
  RepoAltaFalso? repo,
  ParametrosAlta parametros = parametrosAlta,
  List<Override> extra = const [],
}) {
  final b = _Banco(
    gps: gps,
    geocodificador: geocodificador,
    ciudades: ciudades,
    repo: repo,
    parametros: parametros,
    extra: extra,
  );
  addTearDown(b.cerrar);
  return b;
}

void main() {
  group('GPS', () {
    test(
      'con GPS preciso: el pin arranca en la lectura, con ciudad y dirección del mapa',
      () async {
        final b = _banco();
        expect(b.estado.gps, EstadoGps.buscando);

        await _esperar();

        expect(b.estado.gps, EstadoGps.conLectura);
        expect(b.estado.punto, puntoItalia);
        expect(b.estado.origen, OrigenCoordenadas.gps);
        expect(b.estado.precisionMetros, 6);
        expect(b.estado.esImpreciso, isFalse);
        expect(b.estado.movimientosCamara, 1);
        expect(b.estado.ciudad, montevideo);
        expect(b.estado.origenCiudad, OrigenCiudad.detectada);
        expect(b.estado.calle, const CampoDireccion('Av. Italia', FuenteCampo.delMapa));
        expect(b.estado.numero, const CampoDireccion('1234', FuenteCampo.delMapa));
      },
    );

    test('el tipo no viene elegido: sin tipo no se puede registrar; con el tipo, sí', () async {
      final b = _banco();
      await _esperar();
      expect(b.estado.tipo, isNull);
      expect(b.estado.puedeRegistrar, isFalse);

      b.notificador.elegirTipo(TipoUbicacion.casa);

      expect(b.estado.puedeRegistrar, isTrue);
    });

    test('GPS impreciso (más de 50 m): «Registrar» espera la decisión del colportor', () async {
      final b = _banco(gps: GpsFalso(Right(lecturaGps(85))));
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);

      expect(b.estado.esImpreciso, isTrue);
      expect(b.estado.necesitaDecisionPrecision, isTrue);
      expect(b.estado.puedeRegistrar, isFalse);
      expect(await b.notificador.registrar(), isA<AltaIgnorada>());
      expect(b.repo.llamadas, isEmpty);

      b.notificador.decidirPrecision();

      expect(b.estado.necesitaDecisionPrecision, isFalse);
      expect(b.estado.puedeRegistrar, isTrue);
      expect(await b.notificador.registrar(), isA<AltaCreada>());
      expect(b.repo.llamadas, hasLength(1));
    });

    test('exactamente 50 m no es impreciso', () async {
      final b = _banco(gps: GpsFalso(Right(lecturaGps(50))));
      await _esperar();
      expect(b.estado.esImpreciso, isFalse);
    });

    test(
      'permiso denegado: sin punto, la ciudad es la de la zona y no se puede registrar',
      () async {
        final b = _banco(
          gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
        );
        await _esperar();

        expect(b.estado.gps, EstadoGps.sinGps);
        expect(b.estado.motivoSinGps, MotivoSinGps.permisoDenegado);
        expect(b.estado.punto, isNull);
        expect(b.estado.ciudad, montevideo);
        expect(b.estado.origenCiudad, OrigenCiudad.deZona);

        b.notificador.elegirTipo(TipoUbicacion.casa);
        expect(b.estado.puedeRegistrar, isFalse);
        expect(await b.notificador.registrar(), isA<AltaIgnorada>());
      },
    );

    test('sin GPS se marca el punto a mano y el alta sale con origen manual', () async {
      final b = _banco(
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado))),
      );
      await _esperar();

      b.notificador.marcarPunto(_otroPunto);
      b.notificador.elegirTipo(TipoUbicacion.negocio);

      expect(b.estado.punto, _otroPunto);
      expect(b.estado.origen, OrigenCoordenadas.manual);
      expect(b.estado.precisionMetros, isNull);
      expect(b.estado.movimientosCamara, 1);
      expect(b.estado.puedeRegistrar, isTrue);

      final r = await b.notificador.registrar();

      expect(r, isA<AltaCreada>());
      expect(b.repo.llamadas.single.origen, OrigenCoordenadas.manual);
      expect(b.repo.llamadas.single.ubicacion.lat, _otroPunto.lat);
    });

    test('«Activar GPS» pide lo que corresponde y vuelve a leer', () async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
      );
      gps.alActivar = () => gps.respuesta = Right(lecturaGps(7));
      final b = _banco(gps: gps);
      await _esperar();
      expect(b.estado.gps, EstadoGps.sinGps);

      await b.notificador.activarGps();

      expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
      expect(b.estado.gps, EstadoGps.conLectura);
      expect(b.estado.punto, puntoItalia);
    });

    test('al volver de los ajustes, si seguía sin GPS se reintenta; si ya hay, no', () async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado)),
      );
      final b = _banco(gps: gps);
      await _esperar();
      expect(gps.lecturas, 1);

      gps.respuesta = Right(lecturaGps(9));
      await b.notificador.reintentarGpsSiHaceFalta();
      expect(b.estado.gps, EstadoGps.conLectura);
      expect(gps.lecturas, 2);

      await b.notificador.reintentarGpsSiHaceFalta();
      expect(gps.lecturas, 2);
    });

    test(
      'mientras espera el GPS se puede marcar el punto a mano y la lectura no lo mueve',
      () async {
        final gps = GpsFalso()..bloqueo = Completer<void>();
        final b = _banco(gps: gps);
        await _esperar();
        expect(b.estado.gps, EstadoGps.buscando);

        b.notificador.marcarPunto(_otroPunto);
        gps.bloqueo!.complete();
        await _esperar();

        expect(b.estado.gps, EstadoGps.conLectura);
        expect(b.estado.punto, _otroPunto);
        expect(b.estado.origen, OrigenCoordenadas.manual);
        expect(b.estado.lectura?.coordenadas, puntoItalia);
      },
    );

    test(
      'un alta por tap largo arranca en ese punto, «Marcado a mano», y el GPS no lo mueve',
      () async {
        final b = _banco(
          parametros: const ParametrosAlta(colportorId: 'col-1', puntoInicial: _otroPunto),
        );
        expect(b.estado.punto, _otroPunto);
        expect(b.estado.origen, OrigenCoordenadas.manual);

        await _esperar();

        expect(b.estado.punto, _otroPunto);
        expect(b.estado.precisionMetros, isNull);
        expect(b.estado.gps, EstadoGps.conLectura);
        expect(b.estado.calle.texto, 'Av. Italia');
      },
    );
  });

  group('mover el punto', () {
    test('mover el mapa deja el punto a mano, sin precisión, y no hace falta decidir', () async {
      final b = _banco(gps: GpsFalso(Right(lecturaGps(85))));
      await _esperar();
      expect(b.estado.necesitaDecisionPrecision, isTrue);

      b.notificador.moverPunto(_otroPunto);

      expect(b.estado.punto, _otroPunto);
      expect(b.estado.origen, OrigenCoordenadas.manual);
      expect(b.estado.precisionMetros, isNull);
      expect(b.estado.necesitaDecisionPrecision, isFalse);
    });

    test(
      '«Volver a mi ubicación» vuelve a la lectura y vuelve a pedir decidir si era imprecisa',
      () async {
        final b = _banco(gps: GpsFalso(Right(lecturaGps(85))));
        await _esperar();
        b.notificador.decidirPrecision();
        b.notificador.moverPunto(_otroPunto);
        final camara = b.estado.movimientosCamara;

        b.notificador.volverAMiUbicacion();

        expect(b.estado.punto, puntoItalia);
        expect(b.estado.origen, OrigenCoordenadas.gps);
        expect(b.estado.necesitaDecisionPrecision, isTrue);
        expect(b.estado.movimientosCamara, camara + 1);
      },
    );

    test(
      'mover varias veces seguidas pregunta una sola vez, por el punto en el que se detuvo',
      () async {
        final b = _banco();
        await _esperar();
        final antes = b.geocodificador.pedidos.length;

        b.notificador.moverPunto(const Coordenadas(lat: -34.8801, lon: -56.1301));
        b.notificador.moverPunto(const Coordenadas(lat: -34.8802, lon: -56.1302));
        b.notificador.moverPunto(_otroPunto);
        await _esperar();

        expect(b.geocodificador.pedidos.length, antes + 1);
        expect(b.geocodificador.pedidos.last, _otroPunto);
      },
    );

    test('una respuesta vieja (de un punto que ya se dejó) se descarta', () async {
      final b = _banco();
      await _esperar();
      b.geocodificador.respuesta = (p) => p == _otroPunto
          ? const DireccionDelPunto(calle: 'Rivera', numero: '10')
          : const DireccionDelPunto(calle: 'Vieja', numero: '1');
      final lenta = Completer<void>();
      b.geocodificador.bloqueo = lenta;

      b.notificador.moverPunto(const Coordenadas(lat: -34.88, lon: -56.13));
      await _esperar();
      b.geocodificador.bloqueo = null;
      b.notificador.moverPunto(_otroPunto);
      await _esperar();
      expect(b.estado.calle.texto, 'Rivera');

      lenta.complete();
      await _esperar();

      expect(b.estado.calle.texto, 'Rivera');
      expect(b.estado.numero.texto, '10');
    });

    test('con el alta guardándose, el punto no se mueve', () async {
      final b = _banco(repo: RepoAltaFalso()..bloqueo = Completer<void>());
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);
      unawaited(b.notificador.registrar());
      await _esperar();
      expect(b.estado.guardando, isTrue);

      b.notificador.moverPunto(_otroPunto);
      b.notificador.marcarPunto(_otroPunto);

      expect(b.estado.punto, puntoItalia);
    });
  });

  group('calle y número: «Del mapa» y «Editado»', () {
    test('lo que el colportor escribió queda «Editado» y no se pisa al mover el mapa', () async {
      final b = _banco();
      await _esperar();

      b.notificador.editarNumero('1236');
      b.geocodificador.respuesta = (_) => const DireccionDelPunto(calle: 'Rivera', numero: '1250');
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.numero, const CampoDireccion('1236', FuenteCampo.editado));
      expect(b.estado.calle, const CampoDireccion('Rivera', FuenteCampo.delMapa));
      expect(b.estado.propuesta, const DireccionDelPunto(calle: 'Rivera', numero: '1250'));
    });

    test('«Usar 1250» toma el valor del mapa y lo deja «Del mapa»', () async {
      final b = _banco();
      await _esperar();
      b.notificador.editarNumero('1236');
      b.geocodificador.respuesta = (_) =>
          const DireccionDelPunto(calle: 'Av. Italia', numero: '1250');
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      b.notificador.usarNumeroDelMapa();

      expect(b.estado.numero, const CampoDireccion('1250', FuenteCampo.delMapa));
    });

    test('«Usar» la calle del mapa', () async {
      final b = _banco();
      await _esperar();
      b.notificador.editarCalle('Italia');
      b.geocodificador.respuesta = (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1');
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      b.notificador.usarCalleDelMapa();

      expect(b.estado.calle, const CampoDireccion('Av. Italia', FuenteCampo.delMapa));
    });

    test('«Usar» sin valor del mapa no hace nada', () async {
      final b = _banco(geocodificador: GeocodificadorFalso());
      await _esperar();
      b.notificador.editarCalle('Italia');

      b.notificador.usarCalleDelMapa();
      b.notificador.usarNumeroDelMapa();

      expect(b.estado.calle, const CampoDireccion('Italia', FuenteCampo.editado));
      expect(b.estado.numero.texto, '');
    });

    test('«Calle actualizada»: cuenta cuando la calle del mapa cambia al mover el punto', () async {
      final b = _banco();
      await _esperar();
      expect(b.estado.avisosCalle, 0);

      b.geocodificador.respuesta = (_) => const DireccionDelPunto(calle: 'Rivera', numero: '5');
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.calle.texto, 'Rivera');
      expect(b.estado.avisosCalle, 1);
    });

    test('la misma calle al mover no genera aviso', () async {
      final b = _banco();
      await _esperar();

      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.avisosCalle, 0);
    });

    test('sin dirección del mapa (sin red, o sin calle) los campos «Del mapa» se vacían', () async {
      final b = _banco();
      await _esperar();
      expect(b.estado.calle.fuente, FuenteCampo.delMapa);

      b.geocodificador.respuesta = (_) => null;
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.calle, const CampoDireccion());
      expect(b.estado.numero, const CampoDireccion());
      expect(b.estado.propuesta, isNull);
      expect(b.estado.puedeRegistrar, isFalse, reason: 'falta el tipo, no la dirección');
    });

    test('con el geocodificador sin respuesta se registra igual con las coordenadas', () async {
      final b = _banco(geocodificador: GeocodificadorFalso());
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.edificio);

      final r = await b.notificador.registrar();

      expect(r, isA<AltaCreada>());
      expect(b.repo.llamadas.single.ubicacion.calle, isNull);
      expect(b.repo.llamadas.single.ubicacion.numero, isNull);
    });

    test('borrar lo escrito deja el campo libre para que el mapa lo vuelva a completar', () async {
      final b = _banco();
      await _esperar();
      b.notificador.editarCalle('Otra');
      expect(b.estado.calle.fuente, FuenteCampo.editado);

      b.notificador.editarCalle('  ');
      expect(b.estado.calle.fuente, FuenteCampo.vacio);
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.calle, const CampoDireccion('Av. Italia', FuenteCampo.delMapa));
    });

    test('lo escrito va a la ubicación (recortado) y lo vacío cuenta como no cargado', () async {
      final b = _banco(geocodificador: GeocodificadorFalso());
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);
      b.notificador.editarCalle('  Av. Italia ');
      b.notificador.editarNumero('   ');

      await b.notificador.registrar();

      expect(b.repo.llamadas.single.ubicacion.calle, 'Av. Italia');
      expect(b.repo.llamadas.single.ubicacion.numero, isNull);
    });
  });

  group('ciudad', () {
    const deCampania = CiudadPropuesta(canelones, OrigenPropuesta.deCampania);
    Future<_Banco> sinGps({CiudadesFalsas? ciudades}) async {
      final b = _banco(
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal))),
        ciudades: ciudades,
      );
      await _esperar();
      return b;
    }

    test('siempre se propone una ciudad de la campaña: con GPS, la del punto', () async {
      final b = _banco();
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);

      expect(b.ciudades.propuestas, [puntoItalia]);
      expect(b.estado.ciudad, montevideo);
      expect(b.estado.origenCiudad, OrigenCiudad.detectada);
      expect(b.estado.puedeRegistrar, isTrue);
    });

    test('sin zona del punto ni asignada: la de la campaña, sin preguntar', () async {
      final b = _banco(ciudades: CiudadesFalsas(propone: (_) => deCampania));
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);

      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.deCampania);
      expect(b.estado.puedeRegistrar, isTrue);
      await b.notificador.registrar();
      expect(b.repo.llamadas.single.ubicacion.ciudadId, canelones.id);
    });

    test('sin GPS ni punto la propuesta sale sin punto (zona asignada o única ciudad)', () async {
      final b = await sinGps();

      expect(b.ciudades.propuestas, [null]);
      expect(b.estado.ciudad, montevideo);
      expect(b.estado.origenCiudad, OrigenCiudad.deZona);
    });

    test('con varias ciudades y sin zona asignada ni punto: queda por elegir; al marcar el '
        'punto, se propone', () async {
      final b = await sinGps(
        ciudades: CiudadesFalsas(
          propone: (punto) => punto == null ? const FaltaElPunto() : deCampania,
        ),
      );

      expect(b.estado.ciudad, isNull);
      expect(b.estado.origenCiudad, OrigenCiudad.porElegir);

      b.notificador.marcarPunto(_otroPunto);
      await _esperar();

      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.deCampania);
    });

    test('la propuesta sin punto que llega tarde no pisa la del punto marcado', () async {
      final ciudades = CiudadesFalsas(
        propone: (punto) =>
            punto == null ? const CiudadPropuesta(montevideo, OrigenPropuesta.deZona) : deCampania,
      )..bloqueoPropuesta = Completer<void>();
      final b = await sinGps(ciudades: ciudades);
      b.notificador.marcarPunto(_otroPunto);
      await _esperar();

      ciudades.bloqueoPropuesta!.complete();
      await _esperar();

      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.deCampania);
    });

    test('«Cambiar» deja registrar con otra ciudad, y mover el punto no la pisa', () async {
      final b = _banco();
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);

      b.notificador.elegirCiudad(canelones);
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.elegida);
      expect(b.estado.puedeRegistrar, isTrue);
      expect(b.ciudades.propuestas, [puntoItalia], reason: 'elegida: no se vuelve a proponer');
      await b.notificador.registrar();
      expect(b.repo.llamadas.single.ubicacion.ciudadId, canelones.id);
    });

    test('si elige la ciudad mientras la propuesta viene en camino, la propuesta no la pisa y '
        'la dirección del punto igual se aplica', () async {
      final ciudades = CiudadesFalsas()..bloqueoPropuesta = Completer<void>();
      final b = _banco(ciudades: ciudades);
      await _esperar();
      expect(b.estado.origenCiudad, OrigenCiudad.buscando);

      b.notificador.elegirCiudad(canelones);
      ciudades.bloqueoPropuesta!.complete();
      await _esperar();

      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.elegida);
      expect(b.estado.calle, const CampoDireccion('Av. Italia', FuenteCampo.delMapa));
    });

    test('al mover el punto a otra ciudad de la campaña, la propuesta cambia', () async {
      final b = _banco();
      await _esperar();
      expect(b.estado.ciudad, montevideo);

      b.ciudades.propone = (_) => deCampania;
      b.notificador.moverPunto(_otroPunto);
      await _esperar();

      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.deCampania);
    });

    test('si al mover el punto no se puede leer la ciudad, se conserva la que ya tenía', () async {
      final b = _banco();
      await _esperar();

      b.ciudades.fallaPropuesta = const FailureInesperado();
      b.notificador.moverPunto(_otroPunto);
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);

      expect(b.estado.ciudad, montevideo);
      expect(b.estado.origenCiudad, OrigenCiudad.detectada);
      expect(b.estado.puedeRegistrar, isTrue);
    });

    group('la campaña no tiene ciudades', () {
      Future<_Banco> sinCiudades() async {
        final b = _banco(ciudades: CiudadesFalsas(propone: (_) => const CampaniaSinCiudades()));
        await _esperar();
        b.notificador.elegirTipo(TipoUbicacion.casa);
        return b;
      }

      test('es el único caso sin ciudad: aviso, y no se registra ni se crea nada', () async {
        final b = await sinCiudades();

        expect(b.estado.ciudad, isNull);
        expect(b.estado.origenCiudad, OrigenCiudad.sinCiudades);
        expect(b.estado.puedeRegistrar, isFalse);
        expect(await b.notificador.registrar(), isA<AltaIgnorada>());
        expect(b.repo.llamadas, isEmpty);
      });

      test('«Reintentar»: con la campaña ya con ciudades, se propone y deja registrar', () async {
        final b = await sinCiudades();

        b.ciudades.propone = (_) => const CiudadPropuesta(montevideo, OrigenPropuesta.detectada);
        await b.notificador.reintentarCiudad();

        expect(b.estado.ciudad, montevideo);
        expect(b.estado.origenCiudad, OrigenCiudad.detectada);
        expect(b.estado.puedeRegistrar, isTrue);
      });

      test('dos «Reintentar» seguidos mandan un solo pedido; con ciudad ya no preguntan', () async {
        final b = await sinCiudades();
        b.ciudades.bloqueoPropuesta = Completer<void>();

        final primero = b.notificador.reintentarCiudad();
        final segundo = b.notificador.reintentarCiudad();
        b.ciudades.bloqueoPropuesta!.complete();
        await Future.wait([primero, segundo]);
        expect(b.ciudades.propuestas, hasLength(2), reason: 'la del arranque y un solo reintento');

        b.ciudades
          ..bloqueoPropuesta = null
          ..propone = (_) => const CiudadPropuesta(montevideo, OrigenPropuesta.detectada);
        await b.notificador.reintentarCiudad();
        await b.notificador.reintentarCiudad();
        expect(b.ciudades.propuestas, hasLength(3));
      });

      test('si sigue sin ciudades, el aviso queda y se puede reintentar de nuevo', () async {
        final b = await sinCiudades();

        await b.notificador.reintentarCiudad();

        expect(b.estado.origenCiudad, OrigenCiudad.sinCiudades);
        expect(b.estado.ciudad, isNull);
      });
    });

    group('no se pueden leer las ciudades', () {
      test('queda el aviso con «Reintentar», sin dejar trabado «Buscando la ciudad…»', () async {
        final b = _banco(ciudades: CiudadesFalsas()..fallaPropuesta = const FailureInesperado());
        await _esperar();
        b.notificador.elegirTipo(TipoUbicacion.casa);

        expect(b.estado.ciudad, isNull);
        expect(b.estado.origenCiudad, OrigenCiudad.noSePudoLeer);
        expect(b.estado.puedeRegistrar, isFalse);

        b.ciudades.fallaPropuesta = null;
        await b.notificador.reintentarCiudad();

        expect(b.estado.ciudad, montevideo);
        expect(b.estado.puedeRegistrar, isTrue);
      });

      test('si el puerto lanza en vez de devolver una falla, pasa lo mismo', () async {
        final b = _banco(ciudades: CiudadesFalsas()..lanzaAlProponer = StateError('sin base'));
        await _esperar();

        expect(b.estado.origenCiudad, OrigenCiudad.noSePudoLeer);
        expect(b.estado.ciudad, isNull);

        b.ciudades.lanzaAlProponer = null;
        await b.notificador.reintentarCiudad();

        expect(b.estado.ciudad, montevideo);
      });

      test('«Reintentar» y mover el punto a la vez: queda la propuesta del punto nuevo', () async {
        final b = _banco(ciudades: CiudadesFalsas()..fallaPropuesta = const FailureInesperado());
        await _esperar();
        b.ciudades.fallaPropuesta = null;
        b.ciudades.propone = (punto) => punto == _otroPunto
            ? deCampania
            : const CiudadPropuesta(montevideo, OrigenPropuesta.detectada);
        b.ciudades.bloqueoPropuesta = Completer<void>();

        final reintento = b.notificador.reintentarCiudad();
        b.notificador.moverPunto(_otroPunto);
        await _esperar();
        b.ciudades.bloqueoPropuesta!.complete();
        await reintento;
        await _esperar();

        expect(b.estado.ciudad, canelones);
      });
    });
  });

  group('registrar', () {
    Future<_Banco> listo({RepoAltaFalso? repo, GpsFalso? gps}) async {
      final b = _banco(repo: repo, gps: gps);
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);
      return b;
    }

    test(
      'crea la ubicación con los datos del formulario y su espacio default si es una casa',
      () async {
        final b = await listo();

        final r = await b.notificador.registrar();

        expect(r, isA<AltaCreada>());
        final u = b.repo.llamadas.single.ubicacion;
        expect(u.tipo, TipoUbicacion.casa);
        expect(u.calle, 'Av. Italia');
        expect(u.numero, '1234');
        expect(u.ciudadId, montevideo.id);
        expect(u.auditoria.createdBy, 'col-1');
        expect(b.repo.llamadas.single.espacio, isNotNull);
        expect(b.repo.llamadas.single.origen, OrigenCoordenadas.gps);
      },
    );

    test('un negocio no lleva espacio default', () async {
      final b = await listo();
      b.notificador.elegirTipo(TipoUbicacion.negocio);

      await b.notificador.registrar();

      expect(b.repo.llamadas.single.espacio, isNull);
    });

    test('doble toque: un solo registro', () async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final b = await listo(repo: repo);

      final primero = b.notificador.registrar();
      final segundo = b.notificador.registrar();
      expect(b.estado.guardando, isTrue);
      repo.bloqueo!.complete();
      final resultados = await Future.wait([primero, segundo]);

      expect(repo.llamadas, hasLength(1));
      expect(resultados.whereType<AltaCreada>(), hasLength(1));
      expect(resultados.whereType<AltaIgnorada>(), hasLength(1));
    });

    test(
      'mientras guarda, «guardando» está en alto; si falla, el botón vuelve a habilitarse',
      () async {
        final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureInesperado());
        final b = await listo(repo: repo);

        final r = await b.notificador.registrar();

        expect(r, isA<AltaFallida>());
        expect(b.estado.guardando, isFalse);
        expect(b.estado.falla, isA<FailureInesperado>());
        expect(b.estado.puedeRegistrar, isTrue);
      },
    );

    test('tras una falla, se puede reintentar y sale, con el mismo id', () async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async =>
            ++intento == 1 ? const Left(FailureInesperado()) : Right(AltaRegistrada(ubicacion: u));
      final b = await listo(repo: repo);

      await b.notificador.registrar();
      final r = await b.notificador.registrar();

      expect(r, isA<AltaCreada>());
      expect(b.estado.falla, isNull);
      expect(repo.llamadas.map((l) => l.ubicacion.id).toSet(), hasLength(1));
    });

    test('tocar el formulario después de una falla saca el aviso', () async {
      final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureInesperado());
      final b = await listo(repo: repo);
      await b.notificador.registrar();
      expect(b.estado.falla, isNotNull);

      b.notificador.editarCalle('Otra');

      expect(b.estado.falla, isNull);
    });

    test('una excepción del caso de uso es una falla, no un error sin atrapar', () async {
      final b = _banco(
        extra: [
          registrarUbicacionUseCaseProvider.overrideWith((ref) => throw StateError('sin DB')),
        ],
      );
      await _esperar();
      b.notificador.elegirTipo(TipoUbicacion.casa);

      final r = await b.notificador.registrar();

      expect(r, isA<AltaFallida>());
      expect(b.estado.guardando, isFalse);
      expect(b.estado.puedeRegistrar, isTrue);
    });

    test(
      'un duplicado no crea nada: devuelve las candidatas y el formulario queda como estaba',
      () async {
        final repo = RepoAltaFalso()
          ..comportamiento = (_) async =>
              Right(AltaConDuplicados(candidatas: [candidata('otra', metros: 12)]));
        final b = await listo(repo: repo);
        b.notificador.editarNumero('1236');

        final r = await b.notificador.registrar();

        expect(r, isA<AltaConCandidatas>());
        expect((r as AltaConCandidatas).candidatas.single.ubicacion.id, 'otra');
        expect(b.estado.guardando, isFalse);
        expect(b.estado.numero.texto, '1236');
        expect(b.estado.tipo, TipoUbicacion.casa);
        expect(b.estado.punto, puntoItalia);
      },
    );

    test('«Crear igual»: reintenta con la justificación y el mismo id', () async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async => ++intento == 1
            ? Right(AltaConDuplicados(candidatas: [candidata('otra')]))
            : Right(AltaRegistrada(ubicacion: u));
      final b = await listo(repo: repo);

      await b.notificador.registrar();
      final r = await b.notificador.registrar(justificacion: 'Otra puerta en el mismo número');

      expect(r, isA<AltaCreada>());
      expect(repo.llamadas, hasLength(2));
      expect(repo.llamadas[1].ubicacion.id, repo.llamadas[0].ubicacion.id);
    });

    test(
      '«Crear igual» con la justificación en blanco falla con el motivo y no crea nada',
      () async {
        final b = await listo();

        final r = await b.notificador.registrar(justificacion: '   ');

        expect(r, isA<AltaFallida>());
        expect((r as AltaFallida).falla, isA<FailureValidacion>());
        expect(b.repo.llamadas, isEmpty);
        expect(b.estado.guardando, isFalse);
      },
    );

    test('un alta con GPS impreciso y decidido sale con la confirmación', () async {
      final b = await listo(gps: GpsFalso(Right(lecturaGps(85))));
      b.notificador.decidirPrecision();

      final r = await b.notificador.registrar();

      expect(r, isA<AltaCreada>());
      expect(b.repo.llamadas.single.origen, OrigenCoordenadas.gps);
    });
  });
}
