// «Mapa caído» (#299, seguimiento de #190): con conexión y el mapa de la ciudad sin descargar, al
// abrir el mapa se le pide 1 byte al `.pmtiles`; si no contesta sale «No pudimos cargar el mapa de
// esta ciudad» con «Reintentar», que vuelve a probar. Es el aviso que ya existía (el texto, la
// tarjeta y el botón son los de #190): acá se prueba cuándo sale y cómo se comporta «Reintentar».
//
// Con el descargador REAL sobre puertos falsos (`mapa_descargas_arnes.dart`) y la sonda falsa: ni el
// bucket `mapas` ni la red son reales. Medidas con las fuentes reales del proyecto.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart'
    show FuenteTiles;
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_base_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_descargas_arnes.dart';
import '../../helpers/tiles_falsos.dart';

Finder get _tarjetaNoCarga => find.byKey(ClavesAvisoMapa.noCarga);
Finder get _tarjetaDatos => find.byKey(ClavesAvisoMapa.datosMoviles);
Finder get _tarjetaSinConexion => find.byKey(ClavesAvisoMapa.sinConexion);
Finder get _reintentar => find.widgetWithText(FilledButton, 'Reintentar');
Finder get _revisando => find.widgetWithText(FilledButton, 'Revisando el mapa…');
Finder get _circulo => find.descendant(
  of: find.byKey(ClavesAvisoMapa.revisando),
  matching: find.byType(CircularProgressIndicator),
);
Finder get _titulo => find.text('No pudimos cargar el mapa de esta ciudad');
Finder get _cuerpo =>
    find.text('Tus ubicaciones se siguen viendo. Para ver las calles, probá de nuevo.');

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la >= lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Cada palabra de [texto] queda entera en un renglón (ninguna se parte en dos) y dentro del ancho
/// de pantalla. Devuelve cuántos renglones ocupa.
int _palabrasEnteras(WidgetTester tester, Finder texto, {required double anchoPantalla}) {
  final parrafo = tester.renderObject<RenderParagraph>(texto);
  final plano = parrafo.text.toPlainText();
  final renglones = <double>{};
  for (final palabra in RegExp(r'\S+').allMatches(plano)) {
    final cajas = parrafo.getBoxesForSelection(
      TextSelection(baseOffset: palabra.start, extentOffset: palabra.end),
    );
    expect(cajas, isNotEmpty, reason: palabra.group(0));
    final tope = cajas.first.top;
    for (final caja in cajas) {
      expect(
        (caja.top - tope).abs(),
        lessThan(1),
        reason: '«${palabra.group(0)}» se parte en dos renglones',
      );
    }
    renglones.add(tope.roundToDouble());
    final derecha = parrafo.localToGlobal(Offset(cajas.map((c) => c.right).reduce(_mayor), 0)).dx;
    expect(derecha, lessThanOrEqualTo(anchoPantalla), reason: '«${palabra.group(0)}» se sale');
  }
  return renglones.length;
}

double _mayor(double a, double b) => a > b ? a : b;

FuenteTiles _fuente(WidgetTester tester, [AmbitoTrabajo ambito = ambitoMontevideo]) {
  final contenedor = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  return contenedor.read(fuenteMapaProvider(ambito)).tipo;
}

/// El mapa abierto con conexión, el mapa de Montevideo sin descargar y el archivo caído.
ArnesMapa _conElArchivoCaido({TipoConexion conexion = TipoConexion.wifi}) {
  final arnes = ArnesMapa(conexion: conexion, catalogo: [paqueteMontevideo]);
  arnes.sonda.caidos.add(paqueteMontevideo.origen);
  return arnes;
}

void _ningunAviso() {
  expect(_tarjetaNoCarga, findsNothing);
  expect(_tarjetaDatos, findsNothing);
  expect(_tarjetaSinConexion, findsNothing);
  expect(find.textContaining('Sin conexión'), findsNothing);
}

void main() {
  setUpAll(cargarFuentesReales);

  group('al abrir el mapa con conexión', () {
    testWidgets('el archivo borrado del servidor (404): el aviso de siempre, con su texto y '
        '«Reintentar», sobre el fondo liso', (tester) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes);

      expect(arnes.sonda.pruebas, [paqueteMontevideo.origen]);
      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_titulo, findsOneWidget);
      expect(_cuerpo, findsOneWidget);
      expect(_reintentar, findsOneWidget);
      expect(_habilitado(tester, _reintentar), isTrue);
      // No es un problema de conexión y no se dice que lo sea; el mapa es el color liso del diseño.
      expect(find.textContaining('Sin conexión'), findsNothing);
      expect(find.textContaining('grises'), findsNothing);
      expect(_fuente(tester), FuenteTiles.sinTiles);
    });

    for (final conexion in [TipoConexion.wifi, TipoConexion.datosMoviles]) {
      testWidgets('el servidor caído con ${conexion.name}: el mismo aviso, sin el de descargar', (
        tester,
      ) async {
        final arnes = ArnesMapa(conexion: conexion, catalogo: [paqueteMontevideo]);
        arnes.sonda.servidorCaido = true;
        await montarAviso(tester, arnes: arnes);

        expect(_tarjetaNoCarga, findsOneWidget);
        expect(_tarjetaDatos, findsNothing);
        expect(find.textContaining('Sin conexión'), findsNothing);
      });
    }

    testWidgets('el archivo contesta: el mapa en línea y ningún aviso', (tester) async {
      final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
      await montarAviso(tester, arnes: arnes);

      expect(arnes.sonda.pruebas, [paqueteMontevideo.origen]);
      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.servidorOnline);
    });

    testWidgets('con datos móviles y el archivo bien: la tarjeta de descargar, como antes', (
      tester,
    ) async {
      final arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      await montarAviso(tester, arnes: arnes);

      expect(_tarjetaDatos, findsOneWidget);
      expect(_tarjetaNoCarga, findsNothing);
      expect(_fuente(tester), FuenteTiles.servidorOnline);
    });

    testWidgets('mientras la prueba no contesta no hay aviso de falla; cuando dice que no, sale', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
      final espera = arnes.sonda.espera = Completer<void>();
      arnes.sonda.caidos.add(paqueteMontevideo.origen);
      await montarAviso(tester, arnes: arnes);

      expect(arnes.sonda.enCurso, 1);
      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.servidorOnline);

      espera.complete();
      await asentarAviso(tester);

      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_fuente(tester), FuenteTiles.sinTiles);
    });

    testWidgets('un error inesperado al probar no inventa un aviso', (tester) async {
      final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
      arnes.sonda.lanza = true;
      await montarAviso(tester, arnes: arnes);

      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.servidorOnline);
    });

    testWidgets('sin conexión no se prueba nada: el aviso es el de sin conexión', (tester) async {
      final arnes = _conElArchivoCaido(conexion: TipoConexion.sinConexion);
      await montarAviso(tester, arnes: arnes);

      expect(arnes.sonda.pruebas, isEmpty);
      expect(_tarjetaSinConexion, findsOneWidget);
      expect(_tarjetaNoCarga, findsNothing);
    });

    testWidgets('con el mapa en el teléfono no se prueba nada ni sale aviso', (tester) async {
      final arnes = _conElArchivoCaido();
      await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
      await montarAviso(tester, arnes: arnes);

      expect(arnes.sonda.pruebas, isEmpty);
      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.pmtilesOffline);
    });

    testWidgets('dentro de la hoja del alta (vista 03) sale el mismo aviso', (tester) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes, modo: AvisoMapaModo.enHoja);

      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_reintentar, findsOneWidget);
    });
  });

  group('«Reintentar» vuelve a probar el archivo', () {
    testWidgets('si el archivo volvió, el aviso se va y se ve el mapa en línea', (tester) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes);
      expect(_tarjetaNoCarga, findsOneWidget);

      arnes.sonda.caidos.clear();
      await tocarAviso(tester, _reintentar);

      expect(arnes.sonda.pruebas, hasLength(2));
      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.servidorOnline);
    });

    testWidgets('si sigue caído, el aviso sigue y el botón vuelve a habilitarse', (tester) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes);

      await tocarAviso(tester, _reintentar);

      expect(arnes.sonda.pruebas, hasLength(2));
      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_habilitado(tester, _reintentar), isTrue);
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('mientras prueba, el botón espera; y si la prueba falla, no queda trabado', (
      tester,
    ) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes);
      final espera = arnes.sonda.espera = Completer<void>();

      await tester.ensureVisible(_reintentar);
      await tester.tap(_reintentar);
      await asentarAviso(tester);

      // En el medio el aviso sigue (no parpadea al fondo liso → mapa en línea) y no se puede pedir
      // otra prueba.
      expect(arnes.sonda.enCurso, 1);
      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_habilitado(tester, _revisando), isFalse);

      espera.complete();
      await asentarAviso(tester);

      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_habilitado(tester, _reintentar), isTrue);
    });

    testWidgets('dos toques mientras prueba son una sola prueba', (tester) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes);
      arnes.sonda.caidos.clear();
      final espera = arnes.sonda.espera = Completer<void>();

      await tester.ensureVisible(_reintentar);
      await tester.tap(_reintentar);
      await tester.tap(_reintentar, warnIfMissed: false);
      await asentarAviso(tester);

      expect(arnes.sonda.pruebas, hasLength(2));
      expect(arnes.sonda.enCurso, 1);

      espera.complete();
      await asentarAviso(tester);

      expect(arnes.sonda.pruebas, hasLength(2));
      _ningunAviso();
    });

    testWidgets('dos fallas seguidas: cada «Reintentar» prueba una vez y ninguna se pierde', (
      tester,
    ) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes);

      await tocarAviso(tester, _reintentar);
      await tocarAviso(tester, _reintentar);
      arnes.sonda.caidos.clear();
      await tocarAviso(tester, _reintentar);

      expect(arnes.sonda.pruebas, hasLength(4));
      _ningunAviso();
    });
  });

  group('mientras «Reintentar» revisa, el botón dice qué pasa', () {
    /// Toca «Reintentar» con una prueba que tarda: el botón queda en «Revisando el mapa…».
    Future<({ArnesMapa arnes, Completer<void> espera})> revisando(
      WidgetTester tester, {
      Size tamano = const Size(390, 844),
      double escala = 1,
    }) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes, tamano: tamano, escala: escala);
      final espera = arnes.sonda.espera = Completer<void>();
      await tester.ensureVisible(_reintentar);
      await tester.pump();
      await tester.tap(_reintentar);
      await asentarAviso(tester);
      return (arnes: arnes, espera: espera);
    }

    testWidgets('«Revisando el mapa…» con un círculo, apagado, y el aviso no cambia', (
      tester,
    ) async {
      await revisando(tester);

      expect(_revisando, findsOneWidget);
      expect(_habilitado(tester, _revisando), isFalse);
      expect(_circulo, findsOneWidget);
      expect(tester.getSize(_circulo), const Size(18, 18));
      expect(_reintentar, findsNothing);
      // El título y el cuerpo siguen siendo los de siempre.
      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_titulo, findsOneWidget);
      expect(_cuerpo, findsOneWidget);
    });

    testWidgets('el texto se va cuando termina: vuelve el aviso con «Reintentar» habilitado', (
      tester,
    ) async {
      final r = await revisando(tester);

      r.espera.complete();
      await asentarAviso(tester);

      expect(_revisando, findsNothing);
      expect(_circulo, findsNothing);
      expect(find.text('Revisando el mapa…'), findsNothing);
      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_habilitado(tester, _reintentar), isTrue);
    });

    testWidgets('el texto se va cuando termina y el archivo volvió: ni aviso ni texto, el mapa en '
        'línea', (tester) async {
      final r = await revisando(tester);

      r.arnes.sonda.caidos.clear();
      r.espera.complete();
      await asentarAviso(tester);

      expect(find.text('Revisando el mapa…'), findsNothing);
      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.servidorOnline);
    });

    testWidgets('si la prueba revienta a mitad, no queda trabado en «Revisando el mapa…»', (
      tester,
    ) async {
      final r = await revisando(tester);

      r.arnes.sonda.lanza = true;
      r.espera.complete();
      await asentarAviso(tester);

      expect(find.text('Revisando el mapa…'), findsNothing);
      expect(tester.takeException(), isNull);
      // Un error que no es de red no afirma nada: el aviso se va y el mapa se pide en línea.
      _ningunAviso();
    });

    testWidgets('dos toques seguidos son una sola prueba y el segundo no encola otra', (
      tester,
    ) async {
      final r = await revisando(tester);

      await tester.tap(_revisando, warnIfMissed: false);
      await asentarAviso(tester);

      expect(r.arnes.sonda.pruebas, hasLength(2));
      expect(r.arnes.sonda.enCurso, 1);
      r.espera.complete();
      await asentarAviso(tester);
      expect(r.arnes.sonda.pruebas, hasLength(2));
    });

    testWidgets('el lector de pantalla lo anuncia: región viva, botón apagado con ese nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await revisando(tester);

      final nodo = tester.getSemantics(find.text('Revisando el mapa…'));

      expect(
        nodo,
        isSemantics(
          label: 'Revisando el mapa…',
          isButton: true,
          isLiveRegion: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      semantica.dispose();
    });

    testWidgets('se lee: texto blanco pleno sobre el azul del botón (WCAG 1.4.3)', (tester) async {
      await revisando(tester);

      final fondo = tester
          .widget<Material>(find.descendant(of: _revisando, matching: find.byType(Material)).first)
          .color!;
      final texto = tester
          .renderObject<RenderParagraph>(find.text('Revisando el mapa…'))
          .text
          .style!
          .color!;

      expect(texto.a, 1);
      expect(_contraste(texto, Color.alphaBlend(fondo, Colors.white)), greaterThanOrEqualTo(4.5));
    });

    testWidgets('a 320×568 con el texto al 200 % ninguna palabra se corta ni se sale de la '
        'pantalla', (tester) async {
      await revisando(tester, tamano: const Size(320, 568), escala: 2);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_revisando);
      await tester.pump();
      final boton = tester.getRect(_revisando);
      expect(boton.left, greaterThanOrEqualTo(0));
      expect(boton.right, lessThanOrEqualTo(320));
      expect(boton.bottom, lessThanOrEqualTo(568));
      expect(boton.height, greaterThanOrEqualTo(48));

      final renglones = _palabrasEnteras(
        tester,
        find.text('Revisando el mapa…'),
        anchoPantalla: 320,
      );
      expect(renglones, greaterThan(1), reason: 'al 200 % baja de renglón: es el caso que se mide');
      _palabrasEnteras(tester, _titulo, anchoPantalla: 320);
      _palabrasEnteras(tester, _cuerpo, anchoPantalla: 320);
      // El texto va dentro del botón: el círculo y el texto caben a lo ancho del botón.
      final texto = tester.getRect(find.text('Revisando el mapa…'));
      expect(texto.left, greaterThanOrEqualTo(boton.left));
      expect(texto.right, lessThanOrEqualTo(boton.right));
      expect(texto.bottom, lessThanOrEqualTo(boton.bottom));
    });

    testWidgets('a 360×640 con el texto al 200 % en la hoja del alta tampoco se corta', (
      tester,
    ) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(
        tester,
        arnes: arnes,
        modo: AvisoMapaModo.enHoja,
        tamano: const Size(360, 640),
        escala: 2,
      );
      arnes.sonda.espera = Completer<void>();
      await tester.ensureVisible(_reintentar);
      await tester.pump();
      await tester.tap(_reintentar);
      await asentarAviso(tester);

      expect(tester.takeException(), isNull);
      expect(_revisando, findsOneWidget);
      _palabrasEnteras(tester, find.text('Revisando el mapa…'), anchoPantalla: 360);
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('con el archivo todavía caído, prueba de nuevo y el aviso sigue', (tester) async {
      final arnes = _conElArchivoCaido();
      final montaje = await montarAviso(tester, arnes: arnes);

      await salirYReentrarAviso(tester, montaje);

      expect(arnes.sonda.pruebas, hasLength(2));
      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_habilitado(tester, _reintentar), isTrue);
    });

    testWidgets('con el archivo de vuelta, ya no hay aviso', (tester) async {
      final arnes = _conElArchivoCaido();
      final montaje = await montarAviso(tester, arnes: arnes);
      expect(_tarjetaNoCarga, findsOneWidget);

      arnes.sonda.caidos.clear();
      await salirYReentrarAviso(tester, montaje);

      _ningunAviso();
    });
  });

  group('datos límite', () {
    testWidgets('a 360×640 y texto al 2x el aviso no desborda y «Reintentar» se alcanza', (
      tester,
    ) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(tester, arnes: arnes, tamano: const Size(360, 640), escala: 2);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_reintentar);
      await tester.pump();
      expect(tester.getRect(_reintentar).bottom, lessThanOrEqualTo(640));
      expect(tester.getSize(_reintentar).height, greaterThanOrEqualTo(48));
    });

    testWidgets('con texto al 2x en la hoja del alta tampoco desborda', (tester) async {
      final arnes = _conElArchivoCaido();
      await montarAviso(
        tester,
        arnes: arnes,
        modo: AvisoMapaModo.enHoja,
        tamano: const Size(360, 640),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      expect(_titulo, findsOneWidget);
      expect(_cuerpo, findsOneWidget);
    });
  });
}
