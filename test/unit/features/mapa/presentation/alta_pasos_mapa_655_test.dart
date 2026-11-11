// #655 (vista 41, 41A y 41B): los pasos del alta sobre el mapa principal — N·01 → N·02 → «Elegí la
// ciudad», el aviso de duplicado y «Crear igual» — y el atrás de a un paso, sin widgets ni plugins.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';

/// Unos 40 m al este de Av. Italia: el mapa dice otra calle.
const _mataojo = Coordenadas(lat: -34.88761, lon: -56.12980);

Future<void> _esperar() => Future<void>.delayed(const Duration(milliseconds: 90));

final class _Banco {
  _Banco({GpsFalso? gps, RepoAltaFalso? repo, GeocodificadorFalso? geocodificador, this.punto})
    : gps = gps ?? GpsFalso(),
      repo = repo ?? RepoAltaFalso(),
      geocodificador =
          geocodificador ??
          GeocodificadorFalso(
            (p) => p == _mataojo
                ? const DireccionDelPunto(calle: 'Mataojo', numero: '2047')
                : const DireccionDelPunto(calle: 'Grecia', numero: '3307'),
          ) {
    contenedor = ProviderContainer(
      overrides: overridesAlta(gps: this.gps, repo: this.repo, geocodificador: this.geocodificador),
    );
    proveedor = altaUbicacionProvider(ParametrosAlta(colportorId: 'col-1', puntoInicial: punto));
    contenedor.listen(proveedor, (_, _) {});
  }

  final GpsFalso gps;
  final RepoAltaFalso repo;
  final GeocodificadorFalso geocodificador;
  final Coordenadas? punto;
  late final ProviderContainer contenedor;
  late final NotifierProvider<AltaUbicacionNotifier, AltaUbicacionState> proveedor;

  AltaUbicacionState get estado => contenedor.read(proveedor);
  AltaUbicacionNotifier get alta => contenedor.read(proveedor.notifier);
}

Future<_Banco> _listo({
  GpsFalso? gps,
  RepoAltaFalso? repo,
  GeocodificadorFalso? geocodificador,
  Coordenadas? punto,
}) async {
  final b = _Banco(gps: gps, repo: repo, geocodificador: geocodificador, punto: punto);
  addTearDown(b.contenedor.dispose);
  await _esperar();
  return b;
}

RepoAltaFalso _conDuplicados(List<CandidataDuplicado> candidatas) =>
    RepoAltaFalso()..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: candidatas));

void main() {
  group('N·01 → N·02 (41A·01 a 41A·04)', () {
    test('arranca en N·01 con el pin del GPS, la dirección y la ciudad del mapa', () async {
      final b = await _listo();

      expect(b.estado.paso, PasoAlta.posicion);
      expect(b.estado.punto, puntoItalia);
      expect(b.estado.calle.texto, 'Grecia');
      expect(b.estado.numero.texto, '3307');
      expect(b.estado.ciudad, montevideo);
    });

    test('«Confirmar posición» pasa a N·02; sin punto no hace nada', () async {
      final sinGps = await _listo(
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );
      expect(sinGps.estado.punto, isNull);
      expect(sinGps.alta.confirmarPosicion(), isFalse);
      expect(sinGps.estado.paso, PasoAlta.posicion);

      final b = await _listo();
      expect(b.alta.confirmarPosicion(), isTrue);
      expect(b.estado.paso, PasoAlta.queHayAca);
      // Dos toques seguidos: el segundo ya no está en N·01.
      expect(b.alta.confirmarPosicion(), isFalse);
      expect(b.estado.paso, PasoAlta.queHayAca);
    });

    test('sin GPS, tocar el mapa deja el pin y se puede confirmar (41A·02)', () async {
      final b = await _listo(
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );

      b.alta.marcarPunto(_mataojo);
      await _esperar();

      expect(b.estado.punto, _mataojo);
      expect(b.estado.calle.texto, 'Mataojo');
      expect(b.alta.confirmarPosicion(), isTrue);
    });

    test(
      'GPS ±85 m: no confirma hasta decidir; «Continuar» sigue con ese punto (41A·03)',
      () async {
        final b = await _listo(gps: GpsFalso(Right(lecturaGps(85))));

        expect(b.estado.necesitaDecisionPrecision, isTrue);
        expect(b.alta.confirmarPosicion(), isFalse);
        expect(b.alta.continuarConBajaPrecision(), isTrue);
        expect(b.estado.paso, PasoAlta.queHayAca);
        expect(b.estado.punto, puntoItalia);
        expect(b.estado.precisionDecidida, isTrue);
      },
    );

    test(
      'GPS ±85 m: «Ajustar manualmente» queda en N·01 y mover el pin lo vuelve manual',
      () async {
        final b = await _listo(gps: GpsFalso(Right(lecturaGps(85))));

        b.alta.decidirPrecision();
        b.alta.moverPunto(_mataojo);
        await _esperar();

        expect(b.estado.paso, PasoAlta.posicion);
        expect(b.estado.necesitaDecisionPrecision, isFalse);
        expect(b.alta.confirmarPosicion(), isTrue);
      },
    );

    test('fuera de N·01 el pin no se mueve (ni arrastrando ni tocando el mapa)', () async {
      final b = await _listo();
      b.alta.confirmarPosicion();

      b.alta.moverPunto(_mataojo);
      b.alta.marcarPunto(_mataojo);
      await _esperar();

      expect(b.estado.punto, puntoItalia);
    });

    test('mover el pin con la calle del mapa la actualiza y avisa «Calle actualizada»; '
        'lo escrito no se toca (41A·05)', () async {
      final b = await _listo();
      b.alta.editarNumero('3307 B');

      b.alta.moverPunto(_mataojo);
      await _esperar();

      expect(b.estado.calle.texto, 'Mataojo');
      expect(b.estado.calleActualizada, isTrue);
      expect(b.estado.numero.texto, '3307 B');
      expect(b.estado.numero.fuente, FuenteCampo.editado);
      expect(b.estado.propuesta?.numero, '2047');

      b.alta.editarCalle('Mataojo bis');
      expect(b.estado.calleActualizada, isFalse);
    });

    test('si el mapa no puede leer la dirección, el alta sigue sin ella', () async {
      final geo = GeocodificadorFalso((_) => throw StateError('sin red'));
      final b = await _listo(geocodificador: geo);

      expect(b.estado.punto, puntoItalia);
      expect(b.estado.calle.fuente, FuenteCampo.vacio);
      expect(b.alta.confirmarPosicion(), isTrue);
    });
  });

  group('«Elegí la ciudad» (41A·04B)', () {
    test('se abre solo desde N·02; elegir vuelve a N·02 con la ciudad «Editado»', () async {
      final b = await _listo();
      b.alta.abrirCiudades();
      expect(b.estado.paso, PasoAlta.posicion, reason: 'en N·01 no se abre');

      b.alta
        ..confirmarPosicion()
        ..abrirCiudades();
      expect(b.estado.paso, PasoAlta.ciudad);

      b.alta.elegirCiudad(canelones);
      expect(b.estado.paso, PasoAlta.queHayAca);
      expect(b.estado.ciudad, canelones);
      expect(b.estado.origenCiudad, OrigenCiudad.elegida);
      expect(b.estado.punto, puntoItalia, reason: 'elegir la ciudad no mueve el pin');
    });

    test('«Volver» deja la ciudad como estaba', () async {
      final b = await _listo();
      b.alta
        ..confirmarPosicion()
        ..abrirCiudades();

      expect(b.alta.atras(), isTrue);
      expect(b.estado.paso, PasoAlta.queHayAca);
      expect(b.estado.ciudad, montevideo);
      expect(b.estado.origenCiudad, OrigenCiudad.detectada);
    });
  });

  group('atrás de a un paso', () {
    test('N·02 → N·01 con el pin y lo escrito; en N·01 devuelve false (cierra)', () async {
      final b = await _listo();
      b.alta
        ..confirmarPosicion()
        ..editarNumero('3307 B');

      expect(b.alta.atras(), isTrue);
      expect(b.estado.paso, PasoAlta.posicion);
      expect(b.estado.punto, puntoItalia);
      expect(b.estado.numero.texto, '3307 B');
      expect(b.alta.atras(), isFalse);
    });

    test('mientras guarda no hace nada', () async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final b = await _listo(repo: repo);
      b.alta.confirmarPosicion();

      final registro = b.alta.registrar();
      expect(b.estado.guardando, isTrue);
      expect(b.alta.atras(), isTrue);
      expect(b.estado.paso, PasoAlta.queHayAca);

      repo.bloqueo!.complete();
      expect(await registro, isA<AltaCreada>());
    });
  });

  group('el aviso de duplicado (41B)', () {
    test('«Registrar» con candidatas pasa al aviso, de la más cercana a la más lejana', () async {
      final b = await _listo(
        repo: _conDuplicados([
          candidata('a', metros: 12, motivo: MotivoDuplicado.cercania),
          candidata('b', metros: 4, motivo: MotivoDuplicado.cercania),
        ]),
      );
      b.alta.confirmarPosicion();

      final r = await b.alta.registrar();

      expect(r, isA<AltaConCandidatas>());
      expect(b.estado.paso, PasoAlta.duplicado);
      expect([for (final c in b.estado.candidatas) c.ubicacion.id], ['b', 'a']);
      expect(b.estado.admiteCrearIgual, isTrue);
      expect(b.estado.guardando, isFalse);
    });

    test('«Cancelar» vuelve a N·01 con el pin donde estaba y sin candidatas (41B·01)', () async {
      final b = await _listo(repo: _conDuplicados([candidata('a')]));
      b.alta.confirmarPosicion();
      await b.alta.registrar();

      expect(b.alta.atras(), isTrue);
      expect(b.estado.paso, PasoAlta.posicion);
      expect(b.estado.candidatas, isEmpty);
      expect(b.estado.punto, puntoItalia);
    });

    test('tocar una fila la resalta; un id que no es candidata no cambia nada (41B·02)', () async {
      final b = await _listo(repo: _conDuplicados([candidata('a'), candidata('b', metros: 4)]));
      b.alta.confirmarPosicion();
      await b.alta.registrar();

      b.alta.resaltar('a');
      expect(b.estado.resaltada, 'a');
      b.alta.resaltar('zzz');
      expect(b.estado.resaltada, 'a');
      b.alta.resaltar('b');
      expect(b.estado.resaltada, 'b');
    });

    test('«Crear igual» pide la justificación; «Volver» vuelve al aviso (41B·03)', () async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async => ++intento == 1
            ? Right(AltaConDuplicados(candidatas: [candidata('a')]))
            : Right(AltaRegistrada(ubicacion: u));
      final b = await _listo(repo: repo);
      b.alta.confirmarPosicion();
      await b.alta.registrar();

      b.alta.irACrearIgual();
      expect(b.estado.paso, PasoAlta.crearIgual);
      expect(b.alta.atras(), isTrue);
      expect(b.estado.paso, PasoAlta.duplicado);

      b.alta.irACrearIgual();
      final r = await b.alta.registrar(justificacion: 'Es el fondo, otra entrada');
      expect(r, isA<AltaCreada>());
      expect(repo.llamadas.last.justificacion, 'Es el fondo, otra entrada');
      expect(repo.llamadas.last.ubicacion.id, repo.llamadas.first.ubicacion.id);
    });

    test('la misma dirección a menos de 100 m no admite «Crear igual» (41B·04, D1)', () async {
      final b = await _listo(
        repo: _conDuplicados([
          candidata('a', metros: 26, admiteConservarAmbos: false),
          candidata('b', metros: 40, motivo: MotivoDuplicado.cercania),
        ]),
      );
      b.alta.confirmarPosicion();
      await b.alta.registrar();

      expect(b.estado.admiteCrearIgual, isFalse);
      b.alta.irACrearIgual();
      expect(b.estado.paso, PasoAlta.duplicado);
    });

    test('con baja precisión sin decidir, «Registrar» vuelve a N·01 con el aviso', () async {
      final repo = RepoAltaFalso()
        ..comportamiento = (_) async => const Right(AltaConBajaPrecision(precisionMetros: 85));
      final b = await _listo(repo: repo);
      b.alta.confirmarPosicion();

      final r = await b.alta.registrar();

      expect(r, isA<AltaIgnorada>());
      expect(b.estado.paso, PasoAlta.posicion);
      expect(b.estado.guardando, isFalse);
    });

    test(
      'en la vista 03 (sin pasos) el duplicado no cambia de paso ni guarda candidatas',
      () async {
        final b = await _listo(repo: _conDuplicados([candidata('a')]));

        final r = await b.alta.registrar();

        expect(r, isA<AltaConCandidatas>());
        expect(b.estado.paso, PasoAlta.posicion);
        expect(b.estado.candidatas, isEmpty);
      },
    );
  });
}
