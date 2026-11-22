// HU-UBI-003 · vista 41, grupo 41E (41E·03, 03B y 03C, #692): los tres modos del botón de ubicación
// según el canvas. ◎ blanco para «Mapa libre», ◉ lleno para «Seguir mi ubicación» y ▲ lleno para
// «Seguir y girar con el teléfono»; el nombre del modo se ve 2 s al cambiar y es el nombre accesible
// del botón («Ubicación: …»); con el mapa girado aparece la brújula arriba, que vuelve al norte, y
// en «Seguir y girar» el cono azul sale del punto del GPS hacia arriba.
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/zonas_falsas.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;

const _adelante = Coordenadas(lat: -34.88700, lon: -56.13024);
const _masAdelante = Coordenadas(lat: -34.88650, lon: -56.13000);

LecturaGps _lectura(Coordenadas punto, {double? rumbo}) =>
    LecturaGps(coordenadas: punto, precisionMetros: 5, rumboGrados: rumbo);

ModoSeguimiento _modo(WidgetTester tester) =>
    contenedorDeLaPestana(tester).read(ubicacionColportorProvider).modo;

final _rotulo = find.byKey(ClavesMapaUbicaciones.rotuloModo);
final _brujula = find.byKey(ClavesMapaUbicaciones.brujula);
final _cono = find.byKey(ClavesMapaUbicaciones.cono);

Finder _simbolo(ModoSeguimiento modo) => find.descendant(
  of: botonMiUbicacion,
  matching: find.byWidgetPredicate((w) => w is SimboloModoSeguimiento && w.modo == modo),
);

/// El texto que muestra el rótulo del modo, o `null` si no está a la vista.
String? _textoDelRotulo(WidgetTester tester) {
  if (_rotulo.evaluate().isEmpty) return null;
  return tester.widget<Text>(find.descendant(of: _rotulo, matching: find.byType(Text))).data;
}

/// El fondo del botón de ubicación.
Color _fondoDelBoton(WidgetTester tester) => tester
    .widget<Material>(find.descendant(of: botonMiUbicacion, matching: find.byType(Material)).first)
    .color!;

Future<void> _tocarBoton(WidgetTester tester) async {
  await tester.tap(botonMiUbicacion);
  await asentarLista(tester);
}

Future<void> _moverse(WidgetTester tester, GpsFalso gps, LecturaGps lectura) async {
  gps.moverse(lectura);
  await asentarLista(tester);
}

/// Deja pasar el tiempo del rótulo (2 s) y un poco más.
Future<void> _pasarDosSegundos(WidgetTester tester) async {
  await tester.pump(MedidasBotonUbicacion.duracionRotulo);
  await tester.pump(const Duration(milliseconds: 100));
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + .05) / (oscuro + .05);
}

void main() {
  group('41E·03, 03B y 03C: el símbolo, el fondo y el nombre de cada modo', () {
    testWidgets('◎ blanco en «Mapa libre», ◉ lleno al seguir y ▲ lleno al seguir y girar, con el '
        'nombre «Ubicación: <modo>»', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      final esperados = [
        (ModoSeguimiento.libre, Colors.white, 'Ubicación: Mapa libre'),
        (ModoSeguimiento.seguir, ColoresMapa.aroSeleccion, 'Ubicación: Seguir mi ubicación'),
        (
          ModoSeguimiento.seguirYGirar,
          ColoresMapa.aroSeleccion,
          'Ubicación: Seguir y girar con el teléfono',
        ),
      ];
      for (final (modo, fondo, nombre) in esperados) {
        expect(_modo(tester), modo);
        expect(_simbolo(modo), findsOneWidget, reason: '$modo');
        expect(_fondoDelBoton(tester), fondo, reason: '$modo');
        expect(
          tester.getSemantics(botonMiUbicacion),
          isSemantics(label: nombre, isButton: true, isEnabled: true, hasTapAction: true),
        );
        expect(tester.getSize(botonMiUbicacion), const Size(48, 48));
        await _tocarBoton(tester);
      }
      expect(_modo(tester), ModoSeguimiento.libre, reason: 'después del último vuelve al primero');
      semantica.dispose();
    });

    test('el símbolo se distingue del fondo con contraste AA en los tres modos', () {
      for (final modo in ModoSeguimiento.values) {
        expect(
          _contraste(modo.tintaDelBoton, modo.fondoDelBoton),
          greaterThanOrEqualTo(4.5),
          reason: '$modo',
        );
      }
      // El botón lleno se distingue del blanco del libre, no solo por el símbolo.
      expect(ModoSeguimiento.seguir.fondoDelBoton, isNot(ModoSeguimiento.libre.fondoDelBoton));
    });

    testWidgets('los tres símbolos se pintan distinto (no es solo el color)', (tester) async {
      Future<List<int>> pintar(ModoSeguimiento modo) async {
        final clave = GlobalKey();
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: clave,
              child: SimboloModoSeguimiento(modo: modo, color: const Color(0xFF000000)),
            ),
          ),
        );
        final limite = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final imagen = await tester.runAsync(() async {
          final img = await limite.toImage();
          final datos = await img.toByteData();
          img.dispose();
          return datos!.buffer.asUint8List().toList();
        });
        return imagen!;
      }

      final libre = await pintar(ModoSeguimiento.libre);
      final seguir = await pintar(ModoSeguimiento.seguir);
      final girar = await pintar(ModoSeguimiento.seguirYGirar);
      expect(libre, isNot(seguir));
      expect(seguir, isNot(girar));
      expect(libre, isNot(girar));
    });
  });

  group('41E·03: el nombre del modo aparece 2 s al cambiar', () {
    testWidgets('al abrir el mapa no hay rótulo: solo aparece con un cambio', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      expect(_rotulo, findsNothing);
    });

    testWidgets('cada toque muestra el nombre del modo nuevo a la izquierda del botón y se va a '
        'los 2 s', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await _tocarBoton(tester);
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoSeguir);
      final rotulo = tester.getRect(_rotulo);
      final boton = tester.getRect(botonMiUbicacion);
      expect(rotulo.right, lessThanOrEqualTo(boton.left), reason: 'a la izquierda del botón');
      expect(rotulo.center.dy, closeTo(boton.center.dy, 1), reason: 'a la altura del botón');

      await _pasarDosSegundos(tester);
      expect(_rotulo, findsNothing);

      await _tocarBoton(tester);
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoSeguirYGirar);
      await _pasarDosSegundos(tester);
      await _tocarBoton(tester);
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoLibre);
    });

    testWidgets('dos toques seguidos: queda el último modo y sus 2 s cuentan desde el último '
        'toque', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await _tocarBoton(tester);
      await tester.pump(const Duration(milliseconds: 1500));
      await _tocarBoton(tester);
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoSeguirYGirar);

      // 1,5 s después del primer toque + lo que pasó: el reloj del primero ya habría vencido.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoSeguirYGirar);

      await _pasarDosSegundos(tester);
      expect(_rotulo, findsNothing);
    });

    testWidgets('arrastrar el mapa mientras la sigue muestra «Mapa libre»', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _pasarDosSegundos(tester);

      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoLibre);
    });

    testWidgets('el rótulo no toma toques ni se lee dos veces: el lector ya oye el anuncio y el '
        'nombre del botón', (tester) async {
      final semantica = tester.ensureSemantics();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      expect(_rotulo, findsOneWidget);

      // Un toque sobre el rótulo cae en el mapa, no en el rótulo.
      final resultado = tester.hitTestOnBinding(tester.getCenter(_rotulo));
      final tocados = resultado.path.map((e) => e.target).whereType<RenderObject>().toSet();
      final delRotulo = tester.renderObjectList(
        find.descendant(of: _rotulo, matching: find.byType(Text)),
      );
      expect(delRotulo.any(tocados.contains), isFalse);
      expect(m.altas, isEmpty);

      expect(find.bySemanticsLabel(TextosMapaUbicaciones.seguimientoSeguir), findsNothing);
      semantica.dispose();
    });

    for (final tamano in const [Size(320, 568), Size(390, 844)]) {
      testWidgets('con el texto a 2.0 en ${tamano.width.toInt()} dp el rótulo más largo entra en '
          'la pantalla sin desbordar', (tester) async {
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          tamano: tamano,
          escala: 2,
        );
        await _tocarBoton(tester);
        await _tocarBoton(tester);

        expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoSeguirYGirar);
        expect(tester.takeException(), isNull);
        final rotulo = tester.getRect(_rotulo);
        expect(rotulo.left, greaterThanOrEqualTo(0));
        expect(rotulo.right, lessThanOrEqualTo(tester.getRect(botonMiUbicacion).left));
        expect(tester.getSize(botonMiUbicacion), const Size(48, 48));
      });
    }

    testWidgets('irse de la pestaña y volver no lo vuelve a mostrar: el modo no cambió', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _pasarDosSegundos(tester);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.seguir);
      expect(_rotulo, findsNothing);
    });

    testWidgets('cerrar la pantalla con el rótulo a la vista no deja el reloj colgado', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      expect(_rotulo, findsOneWidget);

      m.montada.value = false;
      await asentarLista(tester);
      await _pasarDosSegundos(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('41E·03C: la brújula', () {
    testWidgets('no está en «Mapa libre» ni en «Seguir»; aparece en «Seguir y girar» como botón '
        '«Brújula: volver al norte» de 48 dp', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      expect(_brujula, findsNothing);
      await _tocarBoton(tester);
      expect(_brujula, findsNothing);
      await _tocarBoton(tester);

      expect(_brujula, findsOneWidget);
      expect(tester.getSize(_brujula), const Size(48, 48));
      expect(
        tester.getSemantics(_brujula),
        isSemantics(label: TextosMapaUbicaciones.brujula, isButton: true, hasTapAction: true),
      );
      // Arriba a la derecha, debajo de «Referencias».
      final referencias = tester.getRect(chipReferencias);
      final brujula = tester.getRect(_brujula);
      expect(brujula.top, greaterThanOrEqualTo(referencias.bottom));
      expect(brujula.right, closeTo(referencias.right, 0.01));
      expect(brujula.bottom, lessThan(tester.getRect(botonMiUbicacion).top));
      semantica.dispose();
    });

    testWidgets('tocarla en «Seguir y girar» pone el norte arriba y la sigue en «Seguir mi '
        'ubicación»', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 120));
      expect(m.mapa.camara!.rumbo, 120);
      await _pasarDosSegundos(tester);

      await tester.tap(_brujula);
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.seguir);
      expect(m.mapa.camara!.rumbo, 0);
      expect(m.gps.siguiendo, isTrue, reason: 'sigue a la colportora');
      expect(_textoDelRotulo(tester), TextosMapaUbicaciones.seguimientoSeguir);
      expect(_brujula, findsNothing, reason: 'con el norte arriba no hace falta');

      // Una lectura con rumbo no lo vuelve a girar.
      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 45));
      expect(m.mapa.camara!.rumbo, 0);
    });

    testWidgets('dos toques seguidos a la brújula la dejan en «Seguir», sin pasar a otro modo', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 120));

      await tester.tap(_brujula);
      await tester.tap(_brujula, warnIfMissed: false);
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.seguir);
      expect(m.mapa.camara!.rumbo, 0);
      expect(m.gps.seguimientosAbiertos - m.gps.seguimientosCerrados, 1);
    });

    testWidgets('con el mapa libre que quedó girado (lo movió con el dedo) se ve la brújula y la '
        'endereza sin volver a seguirla', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 135));
      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.mapa.camara!.rumbo, 135);
      expect(_brujula, findsOneWidget, reason: 'el norte no está arriba: se dice');

      await tester.tap(_brujula);
      await asentarLista(tester);

      expect(m.mapa.camara!.rumbo, 0);
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.gps.siguiendo, isFalse);
      expect(_brujula, findsNothing);
    });

    testWidgets('al salir de «Seguir y girar» con el botón la brújula se va', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 60));
      expect(_brujula, findsOneWidget);

      await _tocarBoton(tester);
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(_brujula, findsNothing);
    });

    testWidgets('con el texto a 2.0 la brújula sigue de 48 dp y no desborda', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        tamano: const Size(320, 568),
        escala: 2,
      );
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_brujula), const Size(48, 48));
    });
  });

  group('41E·03C: el cono de orientación', () {
    testWidgets(
      'en «Seguir y girar» con rumbo sale del punto del GPS hacia arriba, con su nombre',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
        await _tocarBoton(tester);
        await _tocarBoton(tester);
        await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));

        expect(_cono, findsOneWidget);
        final mapa = tester.getRect(find.byType(MapaBase));
        final (:x, :y) = ProyeccionMercator.aPantalla(
          _adelante,
          m.mapa.camara!,
          ancho: mapa.width,
          alto: mapa.height,
        );
        final centro = tester.getCenter(_cono);
        expect(centro.dx, closeTo(mapa.left + x, 0.5));
        expect(centro.dy, closeTo(mapa.top + y, 0.5));
        expect(tester.getSize(_cono), const Size.square(ConoOrientacion.diametro));
        expect(find.bySemanticsLabel(TextosMapaUbicaciones.conoOrientacion), findsOneWidget);

        // La lectura siguiente lo lleva con el punto.
        await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 100));
        final (x: x2, y: y2) = ProyeccionMercator.aPantalla(
          _masAdelante,
          m.mapa.camara!,
          ancho: mapa.width,
          alto: mapa.height,
        );
        expect(tester.getCenter(_cono).dx, closeTo(mapa.left + x2, 0.5));
        expect(tester.getCenter(_cono).dy, closeTo(mapa.top + y2, 0.5));
        semantica.dispose();
      },
    );

    testWidgets('quieta desde que entró al modo no hay rumbo ni giro: el cono no se dibuja', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      expect(_cono, findsNothing);

      await _moverse(tester, m.gps, _lectura(_adelante));
      expect(_cono, findsNothing);

      // Empieza a caminar: el mapa gira y el cono aparece; al pararse queda con el último rumbo.
      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 30));
      expect(_cono, findsOneWidget);
      await _moverse(tester, m.gps, _lectura(_adelante));
      expect(m.mapa.camara!.rumbo, 30);
      expect(_cono, findsOneWidget);
    });

    testWidgets('no hay cono en «Mapa libre» ni en «Seguir», y se va al salir de «Seguir y '
        'girar»', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      expect(_cono, findsNothing);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));
      expect(_cono, findsNothing, reason: 'en «Seguir» el norte va arriba: no se dice el rumbo');

      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 90));
      expect(_cono, findsOneWidget);

      await _tocarBoton(tester);
      expect(_cono, findsNothing);

      // Al volver a «Seguir y girar» se espera otra vez un rumbo.
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      expect(_cono, findsNothing);
    });

    testWidgets('soltarla con el dedo o con la brújula saca el cono', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));
      expect(_cono, findsOneWidget);

      await tester.tap(_brujula);
      await asentarLista(tester);
      expect(_cono, findsNothing);

      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 90));
      expect(_cono, findsOneWidget);
      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);
      expect(_cono, findsNothing);
    });

    testWidgets('el cono no toma toques: tocar una casa debajo sigue andando', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));

      final resultado = tester.hitTestOnBinding(tester.getCenter(_cono) - const Offset(0, 40));
      final tocados = resultado.path.map((e) => e.target).whereType<RenderObject>().toSet();
      final delCono = tester.renderObjectList(
        find.descendant(of: _cono, matching: find.byType(CustomPaint)),
      );
      expect(delCono.any(tocados.contains), isFalse);
    });
    testWidgets(
      'con la hoja del alta abierta el seguimiento se pausa: la cámara no se mueve sola y '
      'el cono no se dibuja',
      (tester) async {
        final m = await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          altaReal: true,
          otrosOverrides: [
            geocodificadorInversoProvider.overrideWithValue(GeocodificadorFalso()),
            ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
            esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
          ],
        );
        await _tocarBoton(tester);
        await _tocarBoton(tester);
        await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));
        expect(_cono, findsOneWidget);

        await tester.tap(botonNueva);
        await asentarLista(tester, 12);
        final movimientos = m.mapa.movimientos.length;
        expect(_cono, findsNothing);

        await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 200));
        expect(m.mapa.movimientos.length, movimientos, reason: 'la cámara no se mueve sola');
        expect(m.mapa.camara!.rumbo, 90);
        expect(_cono, findsNothing);
        expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      },
    );
  });
}
