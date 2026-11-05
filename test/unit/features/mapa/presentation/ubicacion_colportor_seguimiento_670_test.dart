// HU-UBI-003 / issue #670 — seguimiento de la ubicación tipo Maps (decisión de Cristian del 05/11,
// «GPS viejo»): mientras el mapa sigue a la colportora, el GPS único mantiene la posición viva con un
// stream en vez de una lectura suelta; el stream se apaga fuera de la pestaña Mapa y con la app en
// segundo plano; el alta usa esa posición y no una lectura vieja.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart'
    show EstadoGpsLista;
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';
import '../../../../helpers/lista_ubicaciones_falsos.dart';
import '../../../../helpers/zonas_falsas.dart';

const _otraEsquina = Coordenadas(lat: -34.8900, lon: -56.1320);

LecturaGps _lectura(Coordenadas punto, {double precision = 6, double? rumbo}) =>
    LecturaGps(coordenadas: punto, precisionMetros: precision, rumboGrados: rumbo);

/// Un contenedor con el GPS único y, si se pide, el alta.
final class _Banco {
  _Banco({GpsFalso? gps}) : gps = gps ?? GpsFalso() {
    contenedor = ProviderContainer(
      overrides: [
        ...overridesLista(repo: RepoListaFalso(), gps: this.gps),
        geocodificadorInversoProvider.overrideWithValue(GeocodificadorFalso()),
        ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
        esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
        generadorIdUbicacionProvider.overrideWithValue(() => 'id-1'),
      ],
    );
    addTearDown(contenedor.dispose);
    contenedor.listen(ubicacionColportorProvider, (_, _) {});
  }

  final GpsFalso gps;
  late final ProviderContainer contenedor;

  UbicacionColportorNotifier get ubicacion => contenedor.read(ubicacionColportorProvider.notifier);
  UbicacionColportorState get estado => contenedor.read(ubicacionColportorProvider);

  /// El mapa se abrió: leyó el GPS una vez (como `alAbrirPestana`) y está a la vista.
  Future<void> abrirElMapa() async {
    await ubicacion.alAbrirPestana();
    ubicacion.mapaALaVista(true);
    await pumpEventQueue();
  }

  Future<void> moverse(LecturaGps lectura) async {
    gps.moverse(lectura);
    await pumpEventQueue();
  }

  AltaUbicacionState get alta => contenedor.read(altaUbicacionProvider(parametrosAlta));

  void abrirAlta() => contenedor.listen(altaUbicacionProvider(parametrosAlta), (_, _) {});
}

void main() {
  group('abrir y cerrar el stream', () {
    test('dado el mapa libre, cuando llegan lecturas, no hay ningún stream abierto', () async {
      final b = _Banco();
      await b.abrirElMapa();

      expect(b.estado.modo, ModoSeguimiento.libre);
      expect(b.estado.enVivo, isFalse);
      expect(b.gps.seguimientosAbiertos, 0);
    });

    test(
      'dado el mapa a la vista, cuando pasa a seguir, abre el stream y la posición es viva',
      () async {
        final b = _Banco();
        await b.abrirElMapa();

        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        await pumpEventQueue();
        expect(b.estado.modo, ModoSeguimiento.seguir);
        expect(b.estado.enVivo, isTrue);
        expect(b.gps.siguiendo, isTrue);
        expect(b.estado.lecturaViva, b.estado.lectura);

        await b.moverse(_lectura(_otraEsquina, rumbo: 90));
        expect(b.estado.lectura, _lectura(_otraEsquina, rumbo: 90));
        expect(b.estado.posicion, _otraEsquina);
        expect(b.estado.gps, EstadoGpsLista.conLectura);
      },
    );

    test(
      'seguir y girar mantiene el mismo stream: pasar de un modo que sigue a otro no lo reabre',
      () async {
        final b = _Banco();
        await b.abrirElMapa();

        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        b.ubicacion.cambiarModo(ModoSeguimiento.seguirYGirar);
        await pumpEventQueue();

        expect(b.gps.seguimientosAbiertos, 1);
        expect(b.gps.siguiendo, isTrue);
      },
    );

    test('cerrar el modo («libre») cierra el stream y la lectura deja de ser viva', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await b.moverse(_lectura(_otraEsquina));

      b.ubicacion.cambiarModo(ModoSeguimiento.libre);
      await pumpEventQueue();

      expect(b.gps.siguiendo, isFalse);
      expect(b.estado.enVivo, isFalse);
      expect(b.estado.lecturaViva, isNull, reason: 'sin stream la última lectura puede ser vieja');
      expect(b.estado.posicion, _otraEsquina, reason: 'pero la última posición se conserva');
    });

    test('con el mapa fuera de vista (otra pestaña, app en segundo plano) el stream se cierra y '
        'el modo se recuerda', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguirYGirar);
      await pumpEventQueue();
      expect(b.gps.siguiendo, isTrue);

      b.ubicacion.mapaALaVista(false);
      await pumpEventQueue();
      expect(b.gps.siguiendo, isFalse, reason: 'batería: sin pantalla no hay stream');
      expect(b.estado.modo, ModoSeguimiento.seguirYGirar, reason: 'el modo se recuerda');
      expect(b.estado.enVivo, isFalse);

      b.ubicacion.mapaALaVista(true);
      await pumpEventQueue();
      expect(b.gps.siguiendo, isTrue, reason: 'vuelve con el mapa');
      expect(b.gps.seguimientosAbiertos, 2);
      expect(b.estado.enVivo, isTrue);
    });

    test(
      'con el modo prendido pero el mapa sin abrir, el stream espera a que esté a la vista',
      () async {
        final b = _Banco();
        await b.ubicacion.alAbrirPestana();
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        await pumpEventQueue();
        expect(b.gps.seguimientosAbiertos, 0);

        b.ubicacion.mapaALaVista(true);
        await pumpEventQueue();
        expect(b.gps.siguiendo, isTrue);
      },
    );

    test('sin ninguna lectura no hay a quién seguir: el modo no cambia', () async {
      final b = _Banco(
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );
      await b.abrirElMapa();

      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await pumpEventQueue();

      expect(b.estado.modo, ModoSeguimiento.libre);
      expect(b.gps.seguimientosAbiertos, 0);
    });

    test(
      'tres toques seguidos al botón dan una vuelta entera sin dejar un stream colgado',
      () async {
        final b = _Banco();
        await b.abrirElMapa();

        b.ubicacion
          ..siguienteModo()
          ..siguienteModo()
          ..siguienteModo();
        await pumpEventQueue();

        expect(b.estado.modo, ModoSeguimiento.libre);
        expect(b.gps.siguiendo, isFalse);
        expect(b.gps.seguimientosAbiertos, 1);
        expect(b.gps.seguimientosCerrados, 1);
      },
    );

    test('al descartar el contenedor el stream se cierra', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await pumpEventQueue();
      expect(b.gps.siguiendo, isTrue);

      b.contenedor.dispose();
      await pumpEventQueue();

      expect(b.gps.siguiendo, isFalse);
    });

    test(
      'abrir la pestaña con el seguimiento en vivo no lee otra vez: la posición ya es de ahora',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        await pumpEventQueue();
        final lecturas = b.gps.lecturas;

        await b.ubicacion.alAbrirPestana();

        expect(b.gps.lecturas, lecturas);
      },
    );
  });

  group('lo que llega mientras tanto', () {
    test('una lectura suelta en vuelo no pisa a la del stream que llegó después', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await pumpEventQueue();

      // «Mi ubicación» pide una lectura nueva (queda en vuelo) y el stream trae una posición más nueva.
      b.gps.bloqueo = Completer<void>();
      b.gps.respuesta = Right(_lectura(const Coordenadas(lat: -34.5, lon: -56.0)));
      final suelta = b.ubicacion.refrescar();
      await pumpEventQueue();
      await b.moverse(_lectura(_otraEsquina));
      b.gps.bloqueo!.complete();
      await suelta;
      await pumpEventQueue();

      expect(b.estado.posicion, _otraEsquina, reason: 'la lectura del stream es la más nueva');
    });

    test('lecturas repetidas del mismo lugar no cambian el estado', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await b.moverse(_lectura(_otraEsquina));
      var avisos = 0;
      b.contenedor.listen(ubicacionColportorProvider, (_, _) => avisos++);

      await b.moverse(_lectura(_otraEsquina));
      await b.moverse(_lectura(_otraEsquina));

      expect(avisos, 0);
    });
  });

  group('cuando el seguimiento se corta solo', () {
    for (final motivo in [MotivoSinGps.permisoDenegado, MotivoSinGps.servicioApagado]) {
      test(
        '$motivo: vuelve a «libre», cierra el stream, deja «sin GPS» con «Activar GPS» y lo avisa una vez',
        () async {
          final b = _Banco();
          await b.abrirElMapa();
          b.ubicacion.cambiarModo(ModoSeguimiento.seguirYGirar);
          await b.moverse(_lectura(_otraEsquina));

          b.gps.fallarElSeguimiento(motivo);
          await pumpEventQueue();

          expect(b.estado.modo, ModoSeguimiento.libre);
          expect(b.estado.enVivo, isFalse);
          expect(b.gps.siguiendo, isFalse);
          expect(b.estado.cortes, 1);
          expect(b.estado.gps, EstadoGpsLista.sinGps);
          expect(b.estado.motivoSinGps, motivo);
          expect(b.estado.posicion, _otraEsquina, reason: 'la última posición buena se conserva');

          // «Activar GPS» sigue funcionando después del corte: el botón no queda trabado.
          await b.ubicacion.activarGps();
          expect(b.gps.activaciones, [motivo]);
        },
      );
    }

    test(
      'una falla sin motivo conocido corta el seguimiento pero deja la posición como estaba',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        await pumpEventQueue();

        b.gps.fallarElSeguimiento(MotivoSinGps.sinSenal);
        await pumpEventQueue();

        expect(b.estado.modo, ModoSeguimiento.libre);
        expect(b.estado.cortes, 1);
        expect(b.estado.gps, EstadoGpsLista.conLectura);
        expect(b.estado.lectura, isNotNull);
      },
    );

    test(
      'si el sistema cierra el stream sin avisar, también se corta (nadie sigue a nada)',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        await pumpEventQueue();

        await b.gps.cerrarElSeguimiento();
        await pumpEventQueue();

        expect(b.estado.modo, ModoSeguimiento.libre);
        expect(b.estado.cortes, 1);
        expect(b.estado.enVivo, isFalse);
      },
    );

    test('después de un corte se puede volver a seguir', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await pumpEventQueue();
      b.gps.fallarElSeguimiento(MotivoSinGps.sinSenal);
      await pumpEventQueue();

      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await pumpEventQueue();

      expect(b.estado.modo, ModoSeguimiento.seguir);
      expect(b.estado.enVivo, isTrue);
    });
  });

  group('el alta y Modificar usan la posición viva', () {
    test('con el seguimiento prendido, el pin del alta arranca en la posición de ahora', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await b.moverse(_lectura(_otraEsquina, precision: 4));

      b.abrirAlta();
      await pumpEventQueue();

      expect(b.alta.punto, _otraEsquina);
      expect(b.alta.lectura?.coordenadas, _otraEsquina);
    });

    test('con el alta abierta el pin sale de una lectura y se queda con ella aunque la colportora '
        'siga caminando: «Registrar» guarda lo que el pin muestra', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await b.moverse(_lectura(_otraEsquina, precision: 4));
      b.abrirAlta();
      await pumpEventQueue();

      await b.moverse(_lectura(const Coordenadas(lat: -34.9, lon: -56.14), precision: 30));

      expect(b.alta.punto, _otraEsquina);
      expect(b.alta.lectura?.coordenadas, _otraEsquina, reason: 'el pin y su lectura van juntos');
      expect(b.alta.lectura?.precisionMetros, 4);
      expect(b.alta.esImpreciso, isFalse, reason: 'la precisión es la del pin, no la de ahora');
    });

    test('«Volver a mi ubicación» del alta lleva el pin a la posición de ahora', () async {
      final b = _Banco();
      await b.abrirElMapa();
      b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
      await b.moverse(_lectura(_otraEsquina, precision: 4));
      b.abrirAlta();
      await pumpEventQueue();
      const adelante = Coordenadas(lat: -34.9, lon: -56.14);
      await b.moverse(_lectura(adelante, precision: 5));

      b.contenedor.read(altaUbicacionProvider(parametrosAlta).notifier).volverAMiUbicacion();

      expect(b.alta.punto, adelante);
      expect(b.alta.lectura?.coordenadas, adelante);
      expect(b.gps.lecturas, 1, reason: 'no hace falta otra lectura: la posición ya es viva');
    });

    test(
      'con el pin movido a mano, la lectura que llega sigue viva para «Volver a mi ubicación»',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        b.abrirAlta();
        await pumpEventQueue();
        const aMano = Coordenadas(lat: -34.7, lon: -56.0);
        b.contenedor.read(altaUbicacionProvider(parametrosAlta).notifier).marcarPunto(aMano);
        await pumpEventQueue();
        await b.moverse(_lectura(_otraEsquina));

        expect(b.alta.punto, aMano, reason: 'el pin puesto a mano no se mueve solo');
        expect(b.alta.lectura?.coordenadas, _otraEsquina);

        b.contenedor.read(altaUbicacionProvider(parametrosAlta).notifier).volverAMiUbicacion();
        expect(b.alta.punto, _otraEsquina);
      },
    );
  });
}
