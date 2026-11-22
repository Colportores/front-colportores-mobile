// HU-UBI-003 · vista 06 (#199, hallazgo B1 del #294): de qué ciudad es el mapa. Con el
// `situacionMapaProvider` REAL (la conexión, lo descargado y el catálogo del arnés del aviso) y un
// puerto `CiudadesParaAlta` falso: la ciudad sale del mismo puerto que el alta, se pide con el último
// GPS si ya hay y una sola vez más con la primera lectura. Sin respaldo por posición, bbox ni
// ubicaciones, y sin aviso nuevo cuando no hay ciudad (decisión del 07/10 en el #294). El adaptador
// real llega con #274: hasta entonces la app es siempre el caso «el puerto falla».
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart'
    show FuenteTiles;
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import '../../helpers/tiles_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

/// Montevideo tal como la conoce el catálogo de paquetes de prueba (`c-1`).
const _montevideoDelCatalogo = CiudadCatalogo(id: 'c-1', nombre: 'Montevideo');

/// Una ciudad que el catálogo de paquetes no cubre.
const _otraCiudad = CiudadCatalogo(id: 'c-9', nombre: 'Otra');

PropuestaCiudad _montevideo(Coordenadas? punto) => CiudadPropuesta(
  _montevideoDelCatalogo,
  punto == null ? OrigenPropuesta.deZona : OrigenPropuesta.detectada,
);

Finder get _descargar => find.widgetWithText(FilledButton, 'Descargar mapa');
Finder get _activarDatos => find.widgetWithText(OutlinedButton, 'Activar datos');
Finder get _descargarConPeso =>
    find.ancestor(of: find.textContaining('Descargar mapa ·'), matching: find.byType(FilledButton));

Future<MontajeMapaUbicaciones> _montar(
  WidgetTester tester, {
  required CiudadesFalsas ciudades,
  ArnesMapa? arnes,
  GpsFalso? gps,
}) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso(canvas()),
  arnes: arnes ?? ArnesMapa(catalogo: [paqueteMontevideo]),
  ciudades: ciudades,
  gps: gps,
);

void _sinAviso() {
  expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing);
  expect(find.byKey(ClavesAvisoMapa.pildora), findsNothing);
  expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsNothing);
  expect(find.byKey(ClavesAvisoMapa.noCarga), findsNothing);
  expect(_descargar, findsNothing);
}

void main() {
  group('con la ciudad del puerto el mapa trae las calles', () {
    testWidgets('con Wi-Fi: el mapa en línea de la ciudad, sin ningún aviso', (tester) async {
      final m = await _montar(tester, ciudades: CiudadesFalsas(propone: _montevideo));

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);
      _sinAviso();
    });

    testWidgets('06C·05 · sin conexión: la tarjeta ofrece «Descargar mapa» y «Activar datos»', (
      tester,
    ) async {
      final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
      final m = await _montar(
        tester,
        ciudades: CiudadesFalsas(propone: _montevideo),
        arnes: arnes,
      );

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
      expect(find.text('Sin conexión a internet'), findsOneWidget);
      expect(_descargar, findsOneWidget);
      expect(_activarDatos, findsOneWidget);
    });

    testWidgets('06C·06 · el aviso minimizado es la píldora «Sin conexión · Descargar mapa»', (
      tester,
    ) async {
      final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
      await _montar(
        tester,
        ciudades: CiudadesFalsas(propone: _montevideo),
        arnes: arnes,
      );

      await tester.tap(find.byTooltip('Minimizar aviso'));
      await asentarLista(tester);

      expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
      expect(find.text('Sin conexión · Descargar mapa'), findsOneWidget);
    });

    testWidgets('06C·07 · con datos móviles el aviso dice cuánto pesa «Descargar mapa» y se ven '
        'las calles en línea', (tester) async {
      final arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      final m = await _montar(
        tester,
        ciudades: CiudadesFalsas(propone: _montevideo),
        arnes: arnes,
      );

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);
      expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsOneWidget);
      expect(find.text('Estás viendo el mapa con datos móviles'), findsOneWidget);
      expect(_descargarConPeso, findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Ahora no'), findsOneWidget);
    });

    testWidgets('con el paquete de la ciudad ya descargado el mapa sale del teléfono, sin conexión '
        'y sin aviso', (tester) async {
      final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
      await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));

      final m = await _montar(
        tester,
        ciudades: CiudadesFalsas(propone: _montevideo),
        arnes: arnes,
      );

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.pmtilesOffline);
      expect(m.mapa.config!.fuente.origenes, [rutaFinalDe(paqueteMontevideo, 0)]);
      _sinAviso();
    });

    testWidgets('una ciudad que el catálogo no cubre dice «No pudimos cargar el mapa»', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas(
        propone: (_) => const CiudadPropuesta(_otraCiudad, OrigenPropuesta.deZona),
      );
      final m = await _montar(tester, ciudades: ciudades);

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
      expect(find.byKey(ClavesAvisoMapa.noCarga), findsOneWidget);
    });
  });

  group('se le pregunta al puerto con el GPS, y una sola vez más', () {
    testWidgets('sin punto al abrir y con la primera lectura del GPS; las lecturas que siguen no '
        'vuelven a preguntar', (tester) async {
      final ciudades = CiudadesFalsas(propone: _montevideo);
      final m = await _montar(tester, ciudades: ciudades);

      expect(ciudades.propuestas, [null, puntoItalia]);

      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);
      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(m.gps.lecturas, greaterThan(1));
      expect(ciudades.propuestas, [null, puntoItalia]);
    });

    testWidgets('si sin punto el puerto no sabe («falta el punto»), con el del GPS sí: las calles '
        'aparecen cuando llega la lectura', (tester) async {
      final ciudades = CiudadesFalsas(
        propone: (punto) => punto == null ? const FaltaElPunto() : _montevideo(punto),
      );
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final m = await _montar(tester, ciudades: ciudades, gps: gps);

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
      _sinAviso();

      gps.bloqueo!.complete();
      await asentarLista(tester);

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);
      expect(ciudades.propuestas, [null, puntoItalia]);
    });

    testWidgets('sin GPS (permiso denegado) se pregunta una sola vez, y si hace falta el punto el '
        'mapa sigue sin calles ni aviso nuevo', (tester) async {
      final ciudades = CiudadesFalsas(
        propone: (punto) => punto == null ? const FaltaElPunto() : _montevideo(punto),
      );
      final m = await _montar(tester, ciudades: ciudades, gps: gpsSinPermiso());

      expect(ciudades.propuestas, [null]);
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
      _sinAviso();
    });

    testWidgets('la ciudad que ya se sabía no se pierde si la segunda pregunta falla', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas(propone: _montevideo);
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final m = await _montar(tester, ciudades: ciudades, gps: gps);
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);

      ciudades.fallaPropuesta = const FailureInesperado();
      gps.bloqueo!.complete();
      await asentarLista(tester);

      expect(ciudades.propuestas, [null, puntoItalia]);
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);
      _sinAviso();
    });

    testWidgets('la respuesta de una pregunta vieja no pisa a la nueva (gana la última)', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas(
        propone: (punto) => punto == null
            ? _montevideo(punto)
            : const CiudadPropuesta(_otraCiudad, OrigenPropuesta.detectada),
      );
      final lenta = Completer<void>();
      ciudades.bloqueoPropuesta = lenta;
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final m = await _montar(tester, ciudades: ciudades, gps: gps);

      // La primera pregunta (sin punto) sigue esperando; la segunda ya no espera.
      ciudades.bloqueoPropuesta = null;
      gps.bloqueo!.complete();
      await asentarLista(tester);
      expect(find.byKey(ClavesAvisoMapa.noCarga), findsOneWidget);

      lenta.complete();
      await asentarLista(tester);

      expect(find.byKey(ClavesAvisoMapa.noCarga), findsOneWidget);
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
    });

    testWidgets('la ciudad llega después de abrir: el mapa se ve primero sin calles y las trae '
        'cuando el puerto contesta', (tester) async {
      final ciudades = CiudadesFalsas(propone: _montevideo);
      final espera = Completer<void>();
      ciudades.bloqueoPropuesta = espera;
      final m = await _montar(tester, ciudades: ciudades);
      expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
      _sinAviso();

      espera.complete();
      await asentarLista(tester);

      expect(m.mapa.config!.fuente.tipo, FuenteTiles.servidorOnline);
    });
  });

  group('sin ciudad (el puerto falla, como la app hasta #274): sin calles y sin aviso nuevo', () {
    final sinCiudad = <String, CiudadesFalsas Function()>{
      'el puerto devuelve una falla': () =>
          CiudadesFalsas()..fallaPropuesta = const FailureInesperado(),
      'el puerto lanza': () => CiudadesFalsas()..lanzaAlProponer = StateError('sin fuente'),
      'la campaña no tiene ciudades': () =>
          CiudadesFalsas(propone: (_) => const CampaniaSinCiudades()),
    };

    for (final MapEntry(key: caso, value: crear) in sinCiudad.entries) {
      testWidgets('con Wi-Fi, $caso: el mapa se ve sin calles y no avisa nada', (tester) async {
        final m = await _montar(tester, ciudades: crear());

        expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
        expect(tester.takeException(), isNull);
        _sinAviso();
      });

      testWidgets('sin conexión, $caso: la tarjeta ofrece «Activar datos» pero no «Descargar mapa» '
          '(no hay a qué ciudad pedirlo)', (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        final m = await _montar(tester, ciudades: crear(), arnes: arnes);

        expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
        expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
        expect(_activarDatos, findsOneWidget);
        expect(find.textContaining('Descargar mapa'), findsNothing);
      });

      testWidgets(
        'con datos móviles, $caso: ninguna tarjeta (sin paquete no hay peso que mostrar)',
        (tester) async {
          final arnes = ArnesMapa(
            conexion: TipoConexion.datosMoviles,
            catalogo: [paqueteMontevideo],
          );
          final m = await _montar(tester, ciudades: crear(), arnes: arnes);

          expect(m.mapa.config!.fuente.tipo, FuenteTiles.sinTiles);
          _sinAviso();
        },
      );
    }

    testWidgets('las ubicaciones del colportor se siguen viendo sobre el color liso', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        ciudades: CiudadesFalsas()..fallaPropuesta = const FailureInesperado(),
      );

      expect(hayPunto(m.mapa, 'a'), isTrue);
      expect(hayPunto(m.mapa, 'gps'), isTrue);
    });
  });
}
