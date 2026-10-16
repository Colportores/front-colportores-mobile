// `MapaBase` (HU-UBI-003, #286): el mapa común de las vistas 03, 04, 06, 07 y 10. La vista nativa de
// MapLibre no se dibuja en `flutter test`: es la falsa de `mapa_base_falso.dart`, que se comporta
// como ella en lo que `MapaBase` espera (gestos, `moverCamara`, toques).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mapa_base_falso.dart';

const _italia = Coordenadas(lat: -34.88761, lon: -56.13024);
const _inicial = CamaraMapa(centro: _italia, zoom: 16);
const _otro = Coordenadas(lat: -34.9, lon: -56.2);

/// Lo que `MapaBase` le avisó a quien lo usa.
class _Avisos {
  ControladorMapaBase? controlador;
  var creado = 0;
  final movidas = <CamaraMapa>[];
  final quietas = <(CamaraMapa, AreaMapa)>[];
  final toques = <Coordenadas>[];
  final toquesLargos = <Coordenadas>[];
  final toquesPunto = <String>[];
}

/// Un `MapaBase` de 300 × 400 con la vista falsa.
Widget _app(
  FabricaMapaFalsa fabrica,
  _Avisos avisos, {
  FuenteMapa fuente = const FuenteMapa.sinTiles(),
  CamaraMapa? camaraInicial = _inicial,
  AjusteMapa? ajuste,
  InteraccionMapa interaccion = const InteraccionMapa(),
  bool zoomSobreCentro = false,
  List<PuntoMapa> puntos = const [],
  bool agrupar = false,
  CirculoPrecision? precision,
  CirculoCercania? cercania,
  double reservaInferior = 0,
  double? reservaDerecha,
  bool conToquePunto = false,
  bool conToqueLargo = false,
  double ancho = 300,
  double alto = 400,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [fabrica.override],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: ancho,
            height: alto,
            child: MapaBase(
              fuente: fuente,
              camaraInicial: camaraInicial,
              ajuste: ajuste,
              interaccion: interaccion,
              zoomSobreCentro: zoomSobreCentro,
              puntos: puntos,
              agruparPuntos: agrupar,
              precision: precision,
              cercania: cercania,
              reservaInferior: reservaInferior,
              reservaDerecha: reservaDerecha ?? 80,
              alCrearse: (c) {
                avisos.controlador = c;
                avisos.creado++;
              },
              alMoverCamara: avisos.movidas.add,
              alQuedarQuieto: (c, a) => avisos.quietas.add((c, a)),
              alTocar: avisos.toques.add,
              alTocarLargo: conToqueLargo ? avisos.toquesLargos.add : null,
              alTocarPunto: conToquePunto ? avisos.toquesPunto.add : null,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pellizcar(
  WidgetTester tester, {
  required double izquierda,
  required double derecha,
}) async {
  final centro = tester.getCenter(find.byType(MapaBase));
  final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
  final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
  for (var i = 0; i < 6; i++) {
    await a.moveBy(Offset(-izquierda, 0));
    await b.moveBy(Offset(derecha, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await _asentar(tester);
}

/// Dos toques seguidos en [donde]: un doble toque. Entre uno y otro pasa un rato corto: el
/// reconocedor de Flutter descarta un segundo toque que llega antes de `kDoubleTapMinTime` (40 ms).
Future<void> _dobleToque(WidgetTester tester, Offset donde) async {
  await tester.tapAt(donde);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(donde);
}

void main() {
  late FabricaMapaFalsa fabrica;
  late _Avisos avisos;

  setUp(() {
    fabrica = FabricaMapaFalsa();
    avisos = _Avisos();
  });

  group('arranque', () {
    testWidgets('la vista arranca en la cámara inicial y se avisa una vez que el mapa existe', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      expect(avisos.creado, 1);
      expect(avisos.controlador!.camara, _inicial);
      expect(fabrica.config!.camaraInicial, _inicial);
      expect(fabrica.camara, _inicial);
    });

    testWidgets('al estar lista avisa que quedó quieta, con el área que se ve', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      final (camara, area) = avisos.quietas.single;
      expect(camara, _inicial);
      expect(area.esValida, isTrue);
      expect(area.contiene(_italia), isTrue);
      // Es el área de la vista de 300 × 400 a ese zoom.
      expect(area, ProyeccionMercator.areaVisible(_inicial, ancho: 300, alto: 400));
      expect(avisos.movidas, isEmpty, reason: 'nadie tocó el mapa');
    });

    testWidgets('con un ajuste arranca en la cámara que deja a todos los puntos a la vista', (
      tester,
    ) async {
      const puntos = [_italia, _otro];
      await tester.pumpWidget(
        _app(
          fabrica,
          avisos,
          camaraInicial: null,
          ajuste: const AjusteMapa(puntos: puntos, margen: 40),
          alto: 150,
        ),
      );
      await _asentar(tester);

      final esperada = ProyeccionMercator.camaraQueAjusta(
        puntos,
        ancho: 300,
        alto: 150,
        margen: 40,
      );
      expect(fabrica.config!.camaraInicial, esperada);
      expect(avisos.controlador!.camara, esperada);
    });

    testWidgets('cambiar el ajuste mueve la cámara, sin contarlo como un gesto', (tester) async {
      Widget montar(List<Coordenadas> puntos) => _app(
        fabrica,
        avisos,
        camaraInicial: null,
        ajuste: AjusteMapa(puntos: puntos, margen: 40),
        alto: 150,
      );
      await tester.pumpWidget(montar(const [_italia, _otro]));
      await _asentar(tester);

      await tester.pumpWidget(montar(const [_italia, Coordenadas(lat: -34.8877, lon: -56.1303)]));
      await _asentar(tester);

      final esperada = ProyeccionMercator.camaraQueAjusta(
        const [_italia, Coordenadas(lat: -34.8877, lon: -56.1303)],
        ancho: 300,
        alto: 150,
        margen: 40,
      );
      expect(fabrica.movimientos.single, esperada);
      expect(fabrica.camara, esperada);
      expect(avisos.movidas, isEmpty);
    });

    testWidgets('el mismo ajuste en otro objeto no mueve nada', (tester) async {
      Widget montar() => _app(
        fabrica,
        avisos,
        camaraInicial: null,
        ajuste: const AjusteMapa(puntos: [_italia, _otro], margen: 40),
        alto: 150,
      );
      await tester.pumpWidget(montar());
      await _asentar(tester);
      await tester.pumpWidget(montar());
      await _asentar(tester);

      expect(fabrica.movimientos, isEmpty);
    });

    testWidgets('sin tamaño todavía, el ajuste no revienta', (tester) async {
      await tester.pumpWidget(
        _app(
          fabrica,
          avisos,
          camaraInicial: null,
          ajuste: const AjusteMapa(puntos: [_italia]),
          ancho: 0,
          alto: 0,
        ),
      );
      await _asentar(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('controlador', () {
    testWidgets('moverCamara mueve la vista y no cuenta como un gesto del colportor', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);
      const destino = CamaraMapa(centro: _otro, zoom: 17.5);

      await avisos.controlador!.moverCamara(destino);
      await _asentar(tester);

      expect(fabrica.movimientos, [destino]);
      expect(avisos.controlador!.camara, destino);
      expect(avisos.movidas, isEmpty, reason: 'el eco del pedido no es un gesto');
      expect(avisos.quietas.last.$1, destino);
    });

    testWidgets('un moverCamara pedido antes de que la vista esté lista se aplica al estarlo', (
      tester,
    ) async {
      const destino = CamaraMapa(centro: _otro, zoom: 17);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [fabrica.override],
          child: MaterialApp(
            home: SizedBox(
              width: 300,
              height: 400,
              child: MapaBase(
                fuente: const FuenteMapa.sinTiles(),
                camaraInicial: _inicial,
                alCrearse: (c) => unawaited(c.moverCamara(destino)),
                alQuedarQuieto: (c, a) => avisos.quietas.add((c, a)),
              ),
            ),
          ),
        ),
      );
      await _asentar(tester);

      expect(fabrica.movimientos, [destino]);
      expect(avisos.quietas.last.$1, destino);
    });

    testWidgets('si la vista no puede mover la cámara no se rompe nada', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);
      fabrica.fallaAlMover = StateError('la vista nativa se cayó');

      await avisos.controlador!.moverCamara(const CamaraMapa(centro: _otro, zoom: 17));
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(MapaBase), findsOneWidget);
    });
  });

  group('gestos del colportor', () {
    testWidgets('arrastrar avisa cada cámara nueva', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      await tester.drag(find.byType(MapaBase), const Offset(-80, 0));
      await _asentar(tester);

      expect(avisos.movidas, isNotEmpty);
      // Arrastrar el mapa hacia la izquierda mueve el centro al este.
      expect(avisos.movidas.last.centro.lon, greaterThan(_italia.lon));
      expect(avisos.movidas.last.zoom, 16);
      expect(avisos.quietas.last.$1, avisos.movidas.last);
    });

    testWidgets('un movimiento del colportor lejos de lo que pidió el código sí es un gesto', (
      tester,
    ) async {
      fabrica.ecoDeMoverCamara = false;
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);
      await avisos.controlador!.moverCamara(const CamaraMapa(centro: _otro, zoom: 17));

      // El eco todavía no llegó y el colportor mueve el mapa a otro lado.
      fabrica.moverPorGesto(const CamaraMapa(centro: _italia, zoom: 17));
      expect(avisos.movidas.single.centro, _italia);
    });

    testWidgets('lo que llega al mismo centro que pidió el código es su eco, no un gesto', (
      tester,
    ) async {
      fabrica.ecoDeMoverCamara = false;
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);
      await avisos.controlador!.moverCamara(const CamaraMapa(centro: _otro, zoom: 17));

      fabrica.moverPorGesto(
        const CamaraMapa(centro: Coordenadas(lat: -34.9, lon: -56.2000004), zoom: 17),
      );

      expect(avisos.movidas, isEmpty);
    });

    testWidgets('sin interacción el mapa es una imagen: no atrapa los toques ni se mueve', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, interaccion: InteraccionMapa.ninguna));
      await _asentar(tester);

      final ignora = find.descendant(
        of: find.byType(MapaBase),
        matching: find.byType(IgnorePointer),
      );
      expect(ignora, findsOneWidget);
      expect(tester.widget<IgnorePointer>(ignora).ignoring, isTrue);
      await tester.drag(find.byType(MapaBase), const Offset(-80, 0), warnIfMissed: false);
      await _asentar(tester);
      expect(avisos.movidas, isEmpty);
      expect(avisos.toques, isEmpty);
    });

    testWidgets('con interacción no hay nada que ignore los toques', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      expect(
        find.descendant(of: find.byType(MapaBase), matching: find.byType(IgnorePointer)),
        findsNothing,
      );
    });

    testWidgets('solo desplazar: el pellizco no cambia el zoom', (tester) async {
      await tester.pumpWidget(
        _app(fabrica, avisos, interaccion: const InteraccionMapa(zoom: false)),
      );
      await _asentar(tester);

      await _pellizcar(tester, izquierda: 6, derecha: 14);

      expect(fabrica.camara!.zoom, _inicial.zoom);
      expect(fabrica.config!.dobleToqueZoom, isFalse);
    });

    testWidgets('un toque avisa dónde, y un punto, cuál', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, conToquePunto: true));
      await _asentar(tester);

      fabrica.tocar(_otro);
      fabrica.tocarPunto('m7');

      expect(avisos.toques, [_otro]);
      expect(avisos.toquesPunto, ['m7']);
      expect(fabrica.config!.puntosTocables, isTrue);
    });

    testWidgets('quien no pide el toque de un punto no lo recibe y la vista lo sabe', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      fabrica.tocarPunto('m7');

      expect(avisos.toquesPunto, isEmpty);
      expect(fabrica.config!.puntosTocables, isFalse);
    });
  });

  group('zoom sobre el centro (el pin fijo de la vista 03)', () {
    testWidgets('el pellizco no se avisa como gesto y al soltar el mapa vuelve al centro', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      // Los dedos no están centrados: MapLibre acercaría sobre el punto entre ellos.
      final centro = tester.getCenter(find.byType(MapaBase));
      final a = await tester.startGesture(centro + const Offset(20, 30), pointer: 1);
      final b = await tester.startGesture(centro + const Offset(100, 30), pointer: 2);
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-6, 0));
        await b.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(avisos.movidas, isEmpty, reason: 'durante el pellizco no se avisa');
      expect(
        ProyeccionMercator.distanciaPixeles(fabrica.camara!.centro, _italia, fabrica.camara!.zoom),
        greaterThan(1),
        reason: 'la vista corrió el centro, como la nativa',
      );
      await a.up();
      await b.up();
      await _asentar(tester);

      final camara = fabrica.camara!;
      expect(camara.zoom, greaterThan(_inicial.zoom));
      expect(camara.centro.lat, closeTo(_italia.lat, 1e-6));
      expect(camara.centro.lon, closeTo(_italia.lon, 1e-6));
      expect(avisos.movidas, isEmpty, reason: 'el regreso al centro tampoco es un gesto');
      expect(avisos.quietas.last.$1, camara);
      expect(fabrica.movimientos.last.centro, _italia);
    });

    testWidgets(
      'el doble toque sigue prendido: acerca sobre el punto tocado y al terminar vuelve al centro',
      (tester) async {
        await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
        await _asentar(tester);
        expect(fabrica.config!.dobleToqueZoom, isTrue);
        expect(fabrica.config!.interaccion.zoom, isTrue);

        await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)) + const Offset(80, 100));
        await tester.pump(const Duration(milliseconds: 160));

        expect(avisos.movidas, isEmpty, reason: 'durante el zoom no se avisa');
        expect(
          ProyeccionMercator.distanciaPixeles(
            fabrica.camara!.centro,
            _italia,
            fabrica.camara!.zoom,
          ),
          greaterThan(1),
          reason: 'la vista corrió el centro: acerca sobre el punto tocado, como la nativa',
        );
        await _asentar(tester, 20);

        final camara = fabrica.camara!;
        expect(camara.zoom, closeTo(_inicial.zoom + 1, 1e-9));
        expect(camara.centro.lat, closeTo(_italia.lat, 1e-6));
        expect(camara.centro.lon, closeTo(_italia.lon, 1e-6));
        expect(avisos.movidas, isEmpty, reason: 'el regreso al centro tampoco es un gesto');
        expect(avisos.toques, isEmpty, reason: 'un doble toque no es un toque al mapa');
        expect(avisos.quietas.last.$1, camara);
        expect(fabrica.movimientos.last.centro, _italia);
      },
    );

    testWidgets('sin zoomSobreCentro el doble toque acerca y se avisa, sin restaurar nada', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)) + const Offset(80, 100));
      await _asentar(tester, 20);

      expect(fabrica.camara!.zoom, closeTo(_inicial.zoom + 1, 1e-9));
      expect(avisos.movidas, isNotEmpty);
      expect(fabrica.movimientos, isEmpty);
      expect(
        ProyeccionMercator.distanciaPixeles(fabrica.camara!.centro, _italia, fabrica.camara!.zoom),
        greaterThan(1),
      );
    });

    testWidgets('tocar dos veces y arrastrar (el zoom de un dedo) tampoco mueve el centro', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final donde = tester.getCenter(find.byType(MapaBase)) + const Offset(40, 40);

      await tester.tapAt(donde);
      final segundo = await tester.startGesture(donde);
      for (var i = 0; i < 6; i++) {
        await segundo.moveBy(const Offset(0, 14));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        ProyeccionMercator.distanciaPixeles(fabrica.camara!.centro, _italia, fabrica.camara!.zoom),
        greaterThan(10),
        reason: 'la vista sí movió el mapa',
      );
      expect(avisos.movidas, isEmpty, reason: 'durante el gesto no se avisa');
      await segundo.up();
      await _asentar(tester, 20);

      expect(fabrica.camara!.centro.lat, closeTo(_italia.lat, 1e-6));
      expect(fabrica.camara!.centro.lon, closeTo(_italia.lon, 1e-6));
      expect(avisos.movidas, isEmpty);
      expect(fabrica.movimientos.last.centro, _italia);
    });

    testWidgets('un toque solo se avisa como toque y no restaura nada', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      await tester.tapAt(tester.getCenter(find.byType(MapaBase)) + const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 400));
      await _asentar(tester, 20);

      expect(avisos.toques, hasLength(1));
      expect(fabrica.movimientos, isEmpty);
      expect(fabrica.camara!.zoom, _inicial.zoom);
    });

    testWidgets('dos toques lejos uno del otro son dos toques, no un doble toque', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final arriba = tester.getTopLeft(find.byType(MapaBase)) + const Offset(20, 20);

      await tester.tapAt(arriba);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(arriba + const Offset(250, 350));
      await tester.pump(const Duration(milliseconds: 400));
      await _asentar(tester, 20);

      // (El `GestureDetector` de la vista falsa descarta uno de los dos cuando caen tan pegados;
      // la vista nativa avisa los dos. Lo que importa acá es que no se armó ningún zoom.)
      expect(avisos.toques, isNotEmpty);
      expect(fabrica.movimientos, isEmpty, reason: 'no armó ningún zoom');
      expect(fabrica.camara!.zoom, _inicial.zoom);
    });

    testWidgets('dos toques con más de 300 ms de por medio son dos toques', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final donde = tester.getCenter(find.byType(MapaBase));

      await tester.tapAt(donde);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(donde);
      await tester.pump(const Duration(milliseconds: 400));
      await _asentar(tester, 20);

      expect(avisos.toques, hasLength(2));
      expect(fabrica.movimientos, isEmpty, reason: 'no armó ningún zoom');
      expect(fabrica.camara!.zoom, _inicial.zoom);
    });

    testWidgets('un «quieta» de antes de que arranque la animación no restaura el centro', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)) + const Offset(80, 100));
      fabrica.avisarQuieta();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fabrica.movimientos, isEmpty, reason: 'la animación todavía no terminó');
      await _asentar(tester, 20);

      expect(fabrica.camara!.zoom, closeTo(_inicial.zoom + 1, 1e-9));
      expect(fabrica.camara!.centro.lat, closeTo(_italia.lat, 1e-6));
      expect(fabrica.camara!.centro.lon, closeTo(_italia.lon, 1e-6));
      expect(avisos.movidas, isEmpty);
    });

    testWidgets(
      'si el doble toque no llega a mover la cámara no queda nada trabado: el próximo arrastre se avisa',
      (tester) async {
        fabrica.dobleToqueAnima = false;
        await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
        await _asentar(tester);

        await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)) + const Offset(80, 100));
        await tester.pump(const Duration(milliseconds: 500));
        expect(fabrica.movimientos, isEmpty, reason: 'todavía espera a la vista');
        await tester.pump(const Duration(milliseconds: 600));
        expect(fabrica.movimientos.last.centro, _italia, reason: 'pasado el plazo, se destraba');

        await tester.drag(find.byType(MapaBase), const Offset(0, 80));
        await _asentar(tester);

        expect(avisos.movidas, isNotEmpty);
      },
    );

    testWidgets('dos dobles toques seguidos: cada uno vuelve a su centro', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final donde = tester.getCenter(find.byType(MapaBase)) + const Offset(60, 60);

      await _dobleToque(tester, donde);
      await _asentar(tester, 20);
      await _dobleToque(tester, donde);
      await _asentar(tester, 20);

      expect(fabrica.camara!.zoom, closeTo(_inicial.zoom + 2, 1e-9));
      expect(fabrica.camara!.centro.lat, closeTo(_italia.lat, 1e-6));
      expect(fabrica.camara!.centro.lon, closeTo(_italia.lon, 1e-6));
      expect(avisos.movidas, isEmpty);
    });

    // El alta centra el mapa donde se toca (`moverCamara`). Si eso pasa con un zoom sobre el centro
    // en curso, ese centro es al que hay que volver al terminar; no el de antes del zoom.
    testWidgets(
      'un moverCamara del código durante el doble toque es el centro al que se vuelve al terminar',
      (tester) async {
        // La vista no acerca (por ejemplo, con el zoom ya en el máximo): el zoom queda pendiente
        // hasta que vence la espera.
        fabrica.dobleToqueAnima = false;
        await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
        await _asentar(tester);

        await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)) + const Offset(80, 100));
        await tester.pump(const Duration(milliseconds: 160));
        await avisos.controlador!.moverCamara(const CamaraMapa(centro: _otro, zoom: 16));
        await _asentar(tester, 30);

        expect(fabrica.camara!.centro.lat, closeTo(_otro.lat, 1e-6));
        expect(fabrica.camara!.centro.lon, closeTo(_otro.lon, 1e-6));
        expect(fabrica.movimientos.last.centro, _otro, reason: 'no se deshizo el pedido');
        expect(avisos.movidas, isEmpty);
      },
    );

    testWidgets(
      'un moverCamara del código durante el pellizco es el centro al que se vuelve al soltar',
      (tester) async {
        await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
        await _asentar(tester);
        final centro = tester.getCenter(find.byType(MapaBase));
        final a = await tester.startGesture(centro + const Offset(20, 30), pointer: 1);
        final b = await tester.startGesture(centro + const Offset(100, 30), pointer: 2);
        for (var i = 0; i < 4; i++) {
          await a.moveBy(const Offset(-6, 0));
          await b.moveBy(const Offset(14, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }

        await avisos.controlador!.moverCamara(const CamaraMapa(centro: _otro, zoom: 17));
        await tester.pump(const Duration(milliseconds: 16));
        await a.up();
        await b.up();
        await _asentar(tester, 20);

        expect(fabrica.camara!.centro.lat, closeTo(_otro.lat, 1e-6));
        expect(fabrica.camara!.centro.lon, closeTo(_otro.lon, 1e-6));
        expect(avisos.movidas, isEmpty);
      },
    );

    testWidgets('solo desplazar: el doble toque no hace nada ni arma nada', (tester) async {
      await tester.pumpWidget(
        _app(
          fabrica,
          avisos,
          zoomSobreCentro: true,
          interaccion: const InteraccionMapa(zoom: false),
        ),
      );
      await _asentar(tester);

      await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)));
      await _asentar(tester, 20);

      expect(fabrica.config!.dobleToqueZoom, isFalse);
      expect(fabrica.camara!.zoom, _inicial.zoom);
      expect(fabrica.movimientos, isEmpty);
    });

    testWidgets('con un solo dedo el mapa se arrastra y se avisa, sin volver atrás', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      await tester.drag(find.byType(MapaBase), const Offset(0, 80));
      await _asentar(tester);

      expect(avisos.movidas, isNotEmpty);
      expect(fabrica.movimientos, isEmpty, reason: 'nada que restaurar');
      expect(fabrica.camara!.centro.lat, greaterThan(_italia.lat));
    });

    testWidgets('un arrastre después del pellizco se avisa como siempre', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      await _pellizcar(tester, izquierda: 6, derecha: 14);

      await tester.drag(find.byType(MapaBase), const Offset(0, 80));
      await _asentar(tester);

      expect(avisos.movidas, isNotEmpty);
    });

    testWidgets('dos pellizcos seguidos: cada uno vuelve a su centro', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      await _pellizcar(tester, izquierda: 6, derecha: 14);
      final zoomPrimero = fabrica.camara!.zoom;
      await _pellizcar(tester, izquierda: 6, derecha: 14);

      expect(fabrica.camara!.zoom, greaterThan(zoomPrimero));
      expect(fabrica.camara!.centro.lat, closeTo(_italia.lat, 1e-6));
      expect(fabrica.camara!.centro.lon, closeTo(_italia.lon, 1e-6));
      expect(avisos.movidas, isEmpty);
    });

    testWidgets('sin zoomSobreCentro el pellizco se avisa y no restaura nada', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      await _pellizcar(tester, izquierda: 6, derecha: 14);

      expect(avisos.movidas, isNotEmpty);
      expect(fabrica.movimientos, isEmpty);
      expect(fabrica.config!.dobleToqueZoom, isTrue);
    });

    testWidgets('salir de la pantalla en pleno pellizco no deja un temporizador colgado', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final centro = tester.getCenter(find.byType(MapaBase));
      final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await a.up();
      await b.up();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
    });

    testWidgets('pellizco y un dedo que sigue arrastrando: el arrastre se avisa y no se descarta', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final centro = tester.getCenter(find.byType(MapaBase));
      final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-6, 0));
        await b.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      expect(avisos.movidas, isEmpty, reason: 'recién se soltó un dedo: sigue siendo el zoom');

      for (var i = 0; i < 8; i++) {
        await b.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(avisos.movidas, isNotEmpty, reason: 'el dedo que queda arrastra el mapa');
      await b.up();
      await _asentar(tester);

      expect(fabrica.movimientos, isEmpty, reason: 'no se vuelve atrás: el ajuste se conserva');
      expect(fabrica.camara!.centro.lat, greaterThan(_italia.lat));
      expect(avisos.movidas.last.centro, fabrica.camara!.centro);
    });

    testWidgets('pellizco y un dedo que queda apoyado sin moverse: al soltar vuelve al centro', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final centro = tester.getCenter(find.byType(MapaBase));
      final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-6, 0));
        await b.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.moveBy(const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 200));
      await b.up();
      await _asentar(tester);

      expect(avisos.movidas, isEmpty);
      expect(fabrica.camara!.centro.lat, closeTo(_italia.lat, 1e-6));
      expect(fabrica.camara!.centro.lon, closeTo(_italia.lon, 1e-6));
      expect(fabrica.camara!.zoom, greaterThan(_inicial.zoom));
    });

    testWidgets('salir de la pantalla en pleno doble toque no deja un temporizador colgado', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      await _dobleToque(tester, tester.getCenter(find.byType(MapaBase)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });

    testWidgets('salir de la pantalla justo después de un toque no deja un temporizador colgado', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      await tester.tapAt(tester.getCenter(find.byType(MapaBase)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });
  });

  group('toque largo y doble toque (N2 del #288)', () {
    testWidgets('mantener el dedo apoyado avisa un toque largo, y no un toque', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, conToqueLargo: true));
      await _asentar(tester);

      final dedo = await tester.startGesture(tester.getCenter(find.byType(MapaBase)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await dedo.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(avisos.toquesLargos, hasLength(1));
      expect(avisos.toques, isEmpty);
    });

    testWidgets('quien no pide el toque largo no lo recibe, y no pasa nada', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      fabrica.tocarLargo(_otro);

      expect(avisos.toquesLargos, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el toque largo de la vista llega con las coordenadas que la vista dio', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, conToqueLargo: true));
      await _asentar(tester);

      fabrica.tocarLargo(_otro);

      expect(avisos.toquesLargos, [_otro]);
    });

    testWidgets('con una pulsación larga como primer toque, el siguiente no es un doble toque', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final donde = tester.getCenter(find.byType(MapaBase));

      final primero = await tester.startGesture(donde);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await primero.up();
      final segundo = await tester.startGesture(donde);
      // Si hubiera armado un doble toque, este movimiento se descartaría como parte del zoom.
      fabrica.moverSinTerminar(const CamaraMapa(centro: _otro, zoom: 17));
      await segundo.up();
      await _asentar(tester, 20);

      expect(avisos.movidas, hasLength(1), reason: 'es un gesto del colportor, no un doble toque');
    });

    testWidgets('con un primer toque corto, el siguiente sí es un doble toque (control)', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);
      final donde = tester.getCenter(find.byType(MapaBase));

      final primero = await tester.startGesture(donde);
      await tester.pump(kLongPressTimeout - const Duration(milliseconds: 100));
      await primero.up();
      final segundo = await tester.startGesture(donde);
      fabrica.moverSinTerminar(const CamaraMapa(centro: _otro, zoom: 17));
      await segundo.up();

      expect(avisos.movidas, isEmpty, reason: 'el zoom del doble toque no es un gesto');
      await _asentar(tester, 20);
    });

    testWidgets('dos pulsaciones largas seguidas: cada una arma su propio plazo', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true, conToqueLargo: true));
      await _asentar(tester);
      final donde = tester.getCenter(find.byType(MapaBase));

      for (var i = 0; i < 2; i++) {
        final dedo = await tester.startGesture(donde);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await dedo.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      final tercero = await tester.startGesture(donde);
      fabrica.moverSinTerminar(const CamaraMapa(centro: _otro, zoom: 17));
      await tercero.up();
      await _asentar(tester, 20);

      expect(avisos.toquesLargos, hasLength(2));
      expect(avisos.movidas, hasLength(1));
    });

    testWidgets('salir de la pantalla en plena pulsación no deja un temporizador colgado', (
      tester,
    ) async {
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true));
      await _asentar(tester);

      final dedo = await tester.startGesture(tester.getCenter(find.byType(MapaBase)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await dedo.up();

      expect(tester.takeException(), isNull);
    });
  });

  group('«Tu ubicación»: el punto azul para el lector de pantalla', () {
    const gps = PuntoMapa(id: 'gps', coordenadas: _italia, estilo: EstiloPunto.gps);

    Finder nodo() => find.bySemanticsLabel(MapaBase.textoTuUbicacion);

    /// Un punto a [dx], [dy] píxeles del centro de la cámara inicial (zoom 16).
    PuntoMapa gpsA(double dx, double dy) {
      final c = ProyeccionMercator.aPixeles(_italia, _inicial.zoom);
      return PuntoMapa(
        id: 'gps',
        coordenadas: ProyeccionMercator.aCoordenadas(c.x + dx, c.y + dy, _inicial.zoom),
        estilo: EstiloPunto.gps,
      );
    }

    testWidgets('es una imagen sin acciones, con la etiqueta del canvas y sin la precisión', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, puntos: const [gps]));
      await _asentar(tester);

      expect(MapaBase.textoTuUbicacion, 'Tu ubicación');
      expect(nodo(), findsOneWidget);
      expect(tester.getSemantics(nodo()), matchesSemantics(label: 'Tu ubicación', isImage: true));
      handle.dispose();
    });

    testWidgets('queda sobre el punto, donde lo dibuja la vista', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, puntos: [gpsA(50, -30)]));
      await _asentar(tester);

      final centro = tester.getCenter(find.byType(MapaBase));
      expect(tester.getCenter(nodo()).dx, closeTo(centro.dx + 50, 0.5));
      expect(tester.getCenter(nodo()).dy, closeTo(centro.dy - 30, 0.5));
      expect(tester.getSize(nodo()), const Size(24, 24));
      handle.dispose();
    });

    testWidgets('se reubica cuando el mapa queda quieto, no mientras se mueve', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, puntos: [gpsA(50, -30)]));
      await _asentar(tester);
      final antes = tester.getCenter(nodo());
      final c = ProyeccionMercator.aPixeles(_italia, _inicial.zoom);
      final corrida = CamaraMapa(
        centro: ProyeccionMercator.aCoordenadas(c.x + 100, c.y - 60, _inicial.zoom),
        zoom: _inicial.zoom,
      );

      fabrica.moverSinTerminar(corrida);
      await tester.pump();
      expect(tester.getCenter(nodo()), antes, reason: 'el mapa sigue moviéndose');

      fabrica.avisarQuieta();
      await tester.pump();
      final centro = tester.getCenter(find.byType(MapaBase));
      expect(tester.getCenter(nodo()).dx, closeTo(centro.dx - 50, 0.5));
      expect(tester.getCenter(nodo()).dy, closeTo(centro.dy + 30, 0.5));
      handle.dispose();
    });

    testWidgets('si el punto cambia de lugar, el nodo lo sigue', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, puntos: [gpsA(50, -30)]));
      await _asentar(tester);

      await tester.pumpWidget(_app(fabrica, avisos, puntos: [gpsA(-70, 20)]));
      await _asentar(tester);

      final centro = tester.getCenter(find.byType(MapaBase));
      expect(tester.getCenter(nodo()).dx, closeTo(centro.dx - 70, 0.5));
      expect(tester.getCenter(nodo()).dy, closeTo(centro.dy + 20, 0.5));
      handle.dispose();
    });

    testWidgets('si el punto queda fuera de la pantalla no hay nodo', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, puntos: [gpsA(50, -30)]));
      await _asentar(tester);
      expect(nodo(), findsOneWidget);

      fabrica.moverPorGesto(
        CamaraMapa(
          centro: ProyeccionMercator.aCoordenadas(
            ProyeccionMercator.aPixeles(_italia, _inicial.zoom).x + 600,
            ProyeccionMercator.aPixeles(_italia, _inicial.zoom).y,
            _inicial.zoom,
          ),
          zoom: _inicial.zoom,
        ),
      );
      await tester.pump();

      expect(nodo(), findsNothing);
      handle.dispose();
    });

    testWidgets('sin punto del GPS no hay nodo, aunque haya otros puntos', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          fabrica,
          avisos,
          puntos: [
            const PuntoMapa(id: 'a', coordenadas: _italia),
            const PuntoMapa(id: 'n', coordenadas: _italia, estilo: EstiloPunto.nuevo),
            const PuntoMapa(id: 'c', coordenadas: _italia, estilo: EstiloPunto.candidata),
          ],
        ),
      );
      await _asentar(tester);

      expect(nodo(), findsNothing);
      handle.dispose();
    });

    testWidgets('no atrapa toques: un toque justo encima llega al mapa', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, puntos: [gpsA(50, -30)]));
      await _asentar(tester);

      await tester.tapAt(tester.getCenter(nodo()));
      await tester.pump(const Duration(milliseconds: 400));

      expect(avisos.toques, hasLength(1));
      handle.dispose();
    });

    testWidgets('después de un zoom sobre el centro sigue donde está el punto', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(fabrica, avisos, zoomSobreCentro: true, puntos: const [gps]));
      await _asentar(tester);

      await _pellizcar(tester, izquierda: 6, derecha: 14);

      final centro = tester.getCenter(find.byType(MapaBase));
      expect(tester.getCenter(nodo()).dx, closeTo(centro.dx, 0.5));
      expect(tester.getCenter(nodo()).dy, closeTo(centro.dy, 0.5));
      handle.dispose();
    });
  });

  group('lo que se dibuja', () {
    testWidgets('los puntos, los grupos y el radio de precisión viajan a la vista', (tester) async {
      const puntos = [
        PuntoMapa(id: 'a', coordenadas: _italia),
        PuntoMapa(id: 'gps', coordenadas: _italia, estilo: EstiloPunto.gps),
      ];
      const precision = CirculoPrecision(centro: _italia, radioMetros: 12);
      await tester.pumpWidget(
        _app(fabrica, avisos, puntos: puntos, agrupar: true, precision: precision),
      );
      await _asentar(tester);

      expect(fabrica.config!.puntos, puntos);
      expect(fabrica.config!.agruparPuntos, isTrue);
      expect(fabrica.config!.precision, precision);
    });

    testWidgets('el área de «cerca tuyo» viaja a la vista', (tester) async {
      const area = CirculoCercania(centro: _italia, radioMetros: 60);
      await tester.pumpWidget(_app(fabrica, avisos, cercania: area));
      await _asentar(tester);

      expect(fabrica.config!.cercania, area);

      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      expect(fabrica.config!.cercania, isNull);
    });

    testWidgets('si cambian los puntos, la vista recibe los nuevos', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      await tester.pumpWidget(
        _app(
          fabrica,
          avisos,
          puntos: const [PuntoMapa(id: 'b', coordenadas: _otro)],
        ),
      );
      await _asentar(tester);

      expect(fabrica.config!.puntos.single.id, 'b');
    });

    testWidgets('el punto nuevo toma el color primario del tema', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      final tema = Theme.of(tester.element(find.byType(MapaBase)));
      expect(fabrica.config!.colorNuevo, tema.colorScheme.primary);
    });

    testWidgets('los límites de zoom y el fondo pasan tal cual', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      expect(fabrica.config!.zoomMinimo, 3);
      expect(fabrica.config!.zoomMaximo, 19);
      expect(fabrica.config!.fondo, ColoresMapa.fondo);
    });
  });

  group('atribución «© OpenStreetMap»', () {
    testWidgets('con tiles se ve, porque la licencia de los datos la pide', (tester) async {
      await tester.pumpWidget(
        _app(fabrica, avisos, fuente: const FuenteMapa.offline('/data/uy.pmtiles')),
      );
      await _asentar(tester);

      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });

    testWidgets('también con los tiles del servidor', (tester) async {
      await tester.pumpWidget(
        _app(fabrica, avisos, fuente: const FuenteMapa.online('https://s/uy.pmtiles')),
      );
      await _asentar(tester);

      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });

    testWidgets('sin tiles no hay datos de OpenStreetMap que atribuir', (tester) async {
      await tester.pumpWidget(_app(fabrica, avisos));
      await _asentar(tester);

      expect(find.text('© OpenStreetMap'), findsNothing);
    });

    testWidgets('crece con el texto del sistema (AA): la licencia se tiene que poder leer', (
      tester,
    ) async {
      const fuente = FuenteMapa.offline('/data/uy.pmtiles');
      await tester.pumpWidget(_app(fabrica, avisos, fuente: fuente, ancho: 600));
      await _asentar(tester);
      final normal = tester.getSize(find.text('© OpenStreetMap'));

      await tester.pumpWidget(_app(fabrica, avisos, fuente: fuente, ancho: 600, textScale: 2));
      await _asentar(tester);

      expect(tester.getSize(find.text('© OpenStreetMap')).height, closeTo(normal.height * 2, 0.5));
      expect(tester.widget<Text>(find.text('© OpenStreetMap')).textScaler, isNull);
    });

    testWidgets('el lector de pantalla la lee', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(fabrica, avisos, fuente: const FuenteMapa.offline('/data/uy.pmtiles')),
      );
      await _asentar(tester);

      expect(find.bySemanticsLabel('© OpenStreetMap'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('no atrapa toques: uno justo encima llega al mapa', (tester) async {
      await tester.pumpWidget(
        _app(fabrica, avisos, fuente: const FuenteMapa.offline('/data/uy.pmtiles'), textScale: 2),
      );
      await _asentar(tester);

      final atribucion = tester.getRect(find.text('© OpenStreetMap'));
      await tester.tapAt(atribucion.center);
      // Con el doble toque prendido, la vista confirma el toque pasado el plazo del segundo.
      await tester.pump(const Duration(milliseconds: 400));

      expect(avisos.toques, hasLength(1));
    });

    testWidgets('sube lo que tapa la hoja de abajo, para quedar a la vista', (tester) async {
      const fuente = FuenteMapa.offline('/data/uy.pmtiles');
      await tester.pumpWidget(_app(fabrica, avisos, fuente: fuente));
      await _asentar(tester);
      final mapa = tester.getRect(find.byType(MapaBase));
      final sinReserva = tester.getRect(find.text('© OpenStreetMap'));

      await tester.pumpWidget(_app(fabrica, avisos, fuente: fuente, reservaInferior: 120));
      await _asentar(tester);

      final conReserva = tester.getRect(find.text('© OpenStreetMap'));
      expect(conReserva.bottom, closeTo(sinReserva.bottom - 120, 0.5));
      expect(conReserva.bottom, lessThanOrEqualTo(mapa.bottom - 120 - 4));
    });

    testWidgets('el ancho que deja libre a la derecha se elige', (tester) async {
      const fuente = FuenteMapa.offline('/data/uy.pmtiles');
      Positioned posicion() => tester.widget<Positioned>(
        find.ancestor(of: find.text('© OpenStreetMap'), matching: find.byType(Positioned)).first,
      );
      await tester.pumpWidget(_app(fabrica, avisos, fuente: fuente));
      await _asentar(tester);
      expect(posicion().right, 80, reason: 'por defecto, un botón de 52 dp');

      await tester.pumpWidget(_app(fabrica, avisos, fuente: fuente, reservaDerecha: 20));
      await _asentar(tester);
      expect(posicion().right, 20);
    });

    testWidgets('si no entra en una línea baja a dos renglones, sin elipsis, y deja libre el botón', (
      tester,
    ) async {
      // Con la fuente de pruebas (cada letra, un cuadrado del tamaño del texto) a 2x no entra en 360.
      await tester.pumpWidget(
        _app(
          fabrica,
          avisos,
          fuente: const FuenteMapa.offline('/data/uy.pmtiles'),
          ancho: 360,
          textScale: 2,
        ),
      );
      await _asentar(tester);

      final texto = find.text('© OpenStreetMap');
      final mapa = tester.getRect(find.byType(MapaBase));
      final atribucion = tester.getRect(texto);
      expect(atribucion.height, closeTo(2 * 24, 0.5), reason: 'dos renglones: $atribucion');
      expect(tester.renderObject<RenderParagraph>(texto).didExceedMaxLines, isFalse);
      expect(tester.widget<Text>(texto).overflow, isNull, reason: 'sin elipsis ni recorte');
      expect(tester.widget<Text>(texto).maxLines, isNull);
      expect(atribucion.left, greaterThanOrEqualTo(mapa.left));
      expect(atribucion.right, lessThanOrEqualTo(mapa.right - 80), reason: 'el botón flotante');
      expect(atribucion.bottom, lessThanOrEqualTo(mapa.bottom - 4));
    });
  });
}
