// HU-UBI-003 / issue #651 — un solo GPS del colportor: lo pide el mapa y todas las demás vistas
// (Lista, alta, Modificar, Precios) leen su estado, sin volver a pedir el permiso.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart'
    show LecturaGps;
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';
import '../../../../helpers/lista_ubicaciones_falsos.dart';
import '../../../../helpers/zonas_falsas.dart';

Left<Failure, T> _sinPermiso<T>() =>
    Left(const FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado));

Future<void> _esperar() => pumpEventQueue();

/// Un contenedor con la Lista, el Mapa y el alta (el alta con su propio banco de fakes) y el GPS.
final class _Banco {
  _Banco({GpsFalso? gps}) : gps = gps ?? GpsFalso() {
    contenedor = ProviderContainer(
      overrides: [
        ...overridesLista(repo: RepoListaFalso(), gps: this.gps),
        // Lo que además necesita el alta (el repo y el GPS son los de la lista).
        geocodificadorInversoProvider.overrideWithValue(GeocodificadorFalso()),
        ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
        esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
        generadorIdUbicacionProvider.overrideWithValue(() => 'id-1'),
      ],
    );
    addTearDown(contenedor.dispose);
    for (final p in [listaUbicacionesProvider('col-1'), mapaUbicacionesProvider('col-1')]) {
      contenedor.listen(p, (_, _) {});
    }
    contenedor.listen(altaUbicacionProvider(parametrosAlta), (_, _) {});
  }

  final GpsFalso gps;
  late final ProviderContainer contenedor;

  UbicacionColportorNotifier get ubicacion => contenedor.read(ubicacionColportorProvider.notifier);
  UbicacionColportorState get estado => contenedor.read(ubicacionColportorProvider);
  AltaUbicacionState get alta => contenedor.read(altaUbicacionProvider(parametrosAlta));
  ListaUbicacionesState get lista => contenedor.read(listaUbicacionesProvider('col-1'));
  MapaUbicacionesState get mapa => contenedor.read(mapaUbicacionesProvider('col-1'));
}

void main() {
  group('antes de entrar al mapa', () {
    test(
      'ninguna vista pide el GPS ni el permiso: todas quedan «sin GPS» con lo que tienen',
      () async {
        final b = _Banco();
        await _esperar();

        expect(b.gps.lecturas, 0);
        expect(b.gps.activaciones, isEmpty);
        expect(b.estado.gps, EstadoGpsLista.sinPedir);
        expect(b.lista.gps, EstadoGpsLista.sinPedir);
        expect(b.mapa.gps, EstadoGpsLista.sinPedir);
        expect(b.alta.gps, EstadoGps.sinGps, reason: 'el alta ofrece «Activar GPS», sin diálogo');
      },
    );
  });

  group('al entrar a la pestaña Mapa', () {
    test('lee una sola vez y las demás vistas reciben la misma lectura', () async {
      final b = _Banco();
      await _esperar();

      await b.ubicacion.alAbrirPestana();
      await _esperar();

      expect(b.gps.lecturas, 1);
      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.lista.lectura, b.estado.lectura);
      expect(b.mapa.lectura, b.estado.lectura);
      expect(b.alta.gps, EstadoGps.conLectura);
      expect(b.alta.lectura, b.estado.lectura);
      expect(b.alta.punto, b.estado.posicion, reason: 'el pin parte de la lectura recordada');
    });

    test('abrir el alta o la lista después no relee el GPS', () async {
      final b = _Banco();
      await b.ubicacion.alAbrirPestana();
      await _esperar();

      // Armar un alta nueva es lo que pasa cada vez que se abre.
      const otraApertura = ParametrosAlta(colportorId: 'col-1', apertura: 2);
      b.contenedor.listen(altaUbicacionProvider(otraApertura), (_, _) {});
      await _esperar();

      expect(b.contenedor.read(altaUbicacionProvider(otraApertura)).gps, EstadoGps.conLectura);
      expect(b.gps.lecturas, 1);
      expect(b.gps.activaciones, isEmpty);
    });

    test('permiso denegado: un solo intento, todas las vistas «sin GPS» y ninguna lo vuelve a '
        'pedir al abrirse', () async {
      final b = _Banco(gps: GpsFalso(_sinPermiso()));
      await b.ubicacion.alAbrirPestana();
      await _esperar();

      expect(b.estado.gps, EstadoGpsLista.sinGps);
      expect(b.estado.motivoSinGps, MotivoSinGps.permisoDenegado);
      expect(b.lista.gps, EstadoGpsLista.sinGps);
      expect(b.alta.gps, EstadoGps.sinGps);
      expect(b.alta.motivoSinGps, MotivoSinGps.permisoDenegado);

      await b.ubicacion.alAbrirPestana();
      await b.ubicacion.alAbrirPestana();

      expect(b.gps.lecturas, 1, reason: 'cada apertura mostraría el diálogo del sistema');
    });

    test('«Activar GPS» desde cualquier vista abre el permiso y todas se enteran', () async {
      final gps = GpsFalso(_sinPermiso());
      gps.alActivar = () => gps.respuesta = Right<Failure, LecturaGps>(lecturaGps(6));
      final b = _Banco(gps: gps);
      await b.ubicacion.alAbrirPestana();
      await _esperar();

      // El alta ofrece «Activar GPS» (y se lo pide al GPS único).
      await b.contenedor.read(altaUbicacionProvider(parametrosAlta).notifier).activarGps();
      await _esperar();

      expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.lista.gps, EstadoGpsLista.conLectura);
      expect(b.mapa.gps, EstadoGpsLista.conLectura);
      expect(b.alta.gps, EstadoGps.conLectura);
    });

    test('al volver de los ajustes con el permiso otorgado se reintenta, una sola vez', () async {
      final gps = GpsFalso(_sinPermiso());
      final b = _Banco(gps: gps);
      await b.ubicacion.alAbrirPestana();
      await _esperar();
      await b.ubicacion.reintentarGpsSiHaceFalta();
      expect(gps.lecturas, 1, reason: 'volver de otra app no pide nada');

      await b.ubicacion.activarGps();
      expect(gps.lecturas, 2);
      gps.respuesta = Right(lecturaGps(6));
      await b.ubicacion.reintentarGpsSiHaceFalta();
      await b.ubicacion.reintentarGpsSiHaceFalta();

      expect(gps.lecturas, 3);
      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.alta.gps, EstadoGps.conLectura);
    });

    test('«Activar GPS» tocado dos veces seguidas abre un solo diálogo', () async {
      final gps = GpsFalso(_sinPermiso());
      final b = _Banco(gps: gps);
      await b.ubicacion.alAbrirPestana();
      await _esperar();

      await Future.wait([b.ubicacion.activarGps(), b.ubicacion.activarGps()]);

      expect(gps.activaciones, hasLength(1));
    });

    test('una falla a mitad de «Activar GPS» no deja nada trabado', () async {
      final gps = GpsFalso(_sinPermiso())..alActivar = () => throw StateError('sin ajustes');
      final b = _Banco(gps: gps);
      await b.ubicacion.alAbrirPestana();
      await _esperar();

      await b.ubicacion.activarGps();
      await b.ubicacion.activarGps();

      expect(gps.activaciones, hasLength(2), reason: 'el botón vuelve a estar disponible');
      expect(b.estado.gps, EstadoGpsLista.sinGps);
    });

    test('dos lecturas seguidas: gana la última aunque la anterior llegue después', () async {
      final gps = GpsFalso();
      final vieja = Completer<Either<Failure, LecturaGps>>();
      final nueva = Completer<Either<Failure, LecturaGps>>();
      gps.porLectura = (n) => n == 1 ? vieja.future : nueva.future;
      final b = _Banco(gps: gps);

      final a = b.ubicacion.refrescar();
      final c = b.ubicacion.refrescar();
      nueva.complete(Right(lecturaGps(5)));
      await c;
      vieja.complete(Right(lecturaGps(9)));
      await a;

      expect(b.estado.lectura!.precisionMetros, 5);
      expect(b.alta.lectura!.precisionMetros, 5);
    });
  });

  group('última posición recordada', () {
    test('al volver a armar el mapa o la lista, la posición ya está (sin leer de nuevo)', () async {
      final b = _Banco();
      await b.ubicacion.alAbrirPestana();
      await _esperar();
      b.contenedor.invalidate(mapaUbicacionesProvider('col-1'));
      b.contenedor.invalidate(listaUbicacionesProvider('col-1'));

      expect(b.mapa.lectura, b.estado.lectura, reason: 'el centro inicial del mapa');
      expect(b.lista.posicion, b.estado.posicion);
      expect(b.gps.lecturas, 1);
    });

    test('una lectura que falla después no tira la última buena', () async {
      final b = _Banco();
      await b.ubicacion.alAbrirPestana();
      await _esperar();
      final antes = b.estado.lectura;

      b.gps.respuesta = _sinPermiso();
      final resultado = await b.ubicacion.refrescar();

      expect(resultado.isLeft(), isTrue);
      expect(b.estado.lectura, antes);
      expect(b.estado.gps, EstadoGpsLista.conLectura);
    });
  });
}
