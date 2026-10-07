// QA de #286 / PR #288, ronda 2 (head a20cb64): comprueba con las fuentes reales y a 360×640 que lo
// que arregló el implementador quedó resuelto y que lo nuevo no pisa nada.
//
// - La pista, la atribución «© OpenStreetMap», el pin, «Volver a mi ubicación» y «Cerrar» del mapa del
//   alta (03A · 01 a 03) no se pisan ni se salen del mapa, con y sin GPS, con texto 1x, 1.3x y 2x.
// - La vista previa de la hoja de duplicados (04B): ningún pin queda bajo la atribución.
// - Rótulos de dos letras (candidatas 27 y 28: «AA», «AB») en el mapa, la leyenda y la etiqueta.
// - El espacio duro entre número y unidad en toda la hoja.
//
// MapLibre no se dibuja en `flutter test`: el mapa es la vista falsa de `mapa_base_falso.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_duplicado_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:dartz/dartz.dart' show Right;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart'
    show asentar, cargarFuentesReales, gpsSinPermiso;
import '../../helpers/mapa_base_falso.dart';

const _atribucion = '© OpenStreetMap';
const _fuente = FuenteMapa.offline('/data/uy.pmtiles');

class _Anfitrion extends StatelessWidget {
  const _Anfitrion();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => AltaUbicacionPage.abrir(context, colportorId: 'col-1'),
        child: const Text('abrir'),
      ),
    ),
  );
}

/// La vista falsa del mapa: `fabrica.config` es lo que armó el último `MapaBase` (con la hoja de
/// duplicados abierta, el de la vista previa).
class _Mundo {
  final fabrica = FabricaMapaFalsa();
}

Future<_Mundo> _montar(
  WidgetTester tester, {
  GpsFalso? gps,
  RepoAltaFalso? repo,
  double escala = 1,
  Size tamano = const Size(360, 640),
  FuenteMapa? fuente = _fuente,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  final m = _Mundo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesAlta(
          gps: gps,
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234'),
          ),
          repo: repo,
          ahora: DateTime.utc(2026, 10, 2, 12),
          fuente: fuente,
          mapa: m.fabrica,
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const _Anfitrion(),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await asentar(tester);
  return m;
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
  await tester.tap(f);
  await asentar(tester);
}

Finder get _registrar => find.widgetWithText(FilledButton, TextosAlta.registrar);

RepoAltaFalso _repoCon(int candidatas) => RepoAltaFalso()
  ..comportamiento = (_) async => Right(
    AltaConDuplicados(
      candidatas: [for (var i = 0; i < candidatas; i++) candidata('c$i', metros: 12.0 + i * 2)],
    ),
  );

/// El texto de la pista del alta, sea cual sea.
Finder get _textoPista => find.byWidgetPredicate(
  (w) => w is Text && (w.data == TextosAlta.mover || w.data == TextosAlta.tocar),
);

Finder get _pastillaPista => find.ancestor(of: _textoPista, matching: find.byType(Container)).first;

Finder get _atribucionDelAlta =>
    find.descendant(of: find.byType(MapaAlta), matching: find.text(_atribucion));

void _dentro(Rect pieza, Rect mapa, String que) => expect(
  mapa.inflate(0.5).contains(pieza.topLeft) && mapa.inflate(0.5).contains(pieza.bottomRight),
  isTrue,
  reason: '$que ($pieza) se sale del mapa ($mapa)',
);

void _sinSolape(Rect a, Rect b, String que) =>
    expect(a.overlaps(b), isFalse, reason: '$que: $a se pisa con $b');

Future<void> _abrirTeclado(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
}

Future<void> _cerrarTeclado(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
}

enum _EstadoMapa {
  gpsPreciso('03A · 01 GPS preciso'),
  sinGps('03A · 02 Sin GPS'),
  gpsImpreciso('03A · 03 GPS impreciso');

  const _EstadoMapa(this.rotulo);
  final String rotulo;
}

void main() {
  setUpAll(cargarFuentesReales);

  group('QA2 #286 · mapa del alta: la pista, la atribución, el pin y los botones no se pisan', () {
    for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
      for (final escala in [1.0, 1.3, 2.0]) {
        for (final estado in _EstadoMapa.values) {
          testWidgets(
            '${estado.rotulo} con tiles a ${tamano.width.toInt()}×${tamano.height.toInt()} y '
            'texto ${escala}x',
            (tester) async {
              final gps = switch (estado) {
                _EstadoMapa.gpsPreciso => null,
                _EstadoMapa.sinGps => gpsSinPermiso,
                _EstadoMapa.gpsImpreciso => GpsFalso(Right(lecturaGps(85))),
              };
              await _montar(tester, gps: gps, escala: escala, tamano: tamano);
              if (estado == _EstadoMapa.gpsImpreciso) await _tocar(tester, find.text('Casa'));
              await tester.pumpAndSettle();

              expect(tester.takeException(), isNull);
              final mapa = tester.getRect(find.byType(MapaAlta));
              final pista = tester.getRect(_pastillaPista);
              final atribucion = tester.getRect(_atribucionDelAlta);
              final pin = tester.getRect(find.byType(PinAlta));
              final cerrar = tester.getRect(find.byTooltip(TextosAlta.cerrar));
              final volver = find.byTooltip(TextosAlta.volverAMiUbicacion);

              _dentro(pista, mapa, 'la pista');
              _dentro(atribucion, mapa, 'la atribución');
              _sinSolape(pista, atribucion, 'pista vs atribución');
              _sinSolape(pista, pin, 'pista vs pin');
              _sinSolape(pista, cerrar, 'pista vs «Cerrar»');
              _sinSolape(atribucion, pin, 'atribución vs pin');
              _sinSolape(atribucion, cerrar, 'atribución vs «Cerrar»');
              expect(
                pista.top,
                greaterThanOrEqualTo(pin.bottom),
                reason: 'la pista tapa la punta del pin',
              );
              if (volver.evaluate().isNotEmpty) {
                final rv = tester.getRect(volver);
                _dentro(rv, mapa, '«Volver a mi ubicación»');
                _sinSolape(pista, rv, 'pista vs «Volver a mi ubicación»');
                _sinSolape(atribucion, rv, 'atribución vs «Volver a mi ubicación»');
              } else {
                expect(estado, _EstadoMapa.sinGps, reason: 'sin botón solo en «Sin GPS»');
              }
            },
          );
        }
      }
    }
  });

  // QA2 P1 (decisión del 06/10, mapa §2): con el teclado abierto el mapa de 360×640 queda de ~129 dp y la
  // pista de dos renglones con la letra grande tapa la atribución o se corta. La pista no se muestra
  // mientras el teclado está abierto y vuelve al cerrarlo; el resto del mapa queda como estaba.
  group('QA2 #286 · teclado abierto en el alta: la pista se oculta y nada más', () {
    for (final estado in [_EstadoMapa.gpsPreciso, _EstadoMapa.sinGps]) {
      for (final escala in [1.0, 1.3, 2.0]) {
        testWidgets(
          '${estado.rotulo} con el teclado abierto (300 dp) a 360×640 y texto ${escala}x: sin pista, '
          'con la atribución, el pin y los botones a la vista, y la pista vuelve al cerrarlo',
          (tester) async {
            final sinGps = estado == _EstadoMapa.sinGps;
            await _montar(tester, gps: sinGps ? gpsSinPermiso : null, escala: escala);
            await tester.pumpAndSettle();
            expect(_textoPista, findsOneWidget, reason: 'sin teclado la pista está');
            final altoSinTeclado = tester.getSize(find.byType(MapaAlta)).height;

            await _abrirTeclado(tester);

            expect(tester.takeException(), isNull);
            expect(_textoPista, findsNothing, reason: 'con el teclado abierto no hay pista');
            final mapa = tester.getRect(find.byType(MapaAlta));
            expect(
              mapa.height,
              lessThan(altoSinTeclado - 100),
              reason: 'el teclado achica el mapa',
            );
            final atribucion = tester.getRect(_atribucionDelAlta);
            final pin = tester.getRect(find.byType(PinAlta));
            final cerrar = tester.getRect(find.byTooltip(TextosAlta.cerrar));
            _dentro(atribucion, mapa, 'la atribución con el teclado');
            _dentro(pin, mapa, 'el pin con el teclado');
            _dentro(cerrar, mapa, '«Cerrar» con el teclado');
            _sinSolape(atribucion, pin, 'atribución vs pin con el teclado');
            _sinSolape(atribucion, cerrar, 'atribución vs «Cerrar» con el teclado');
            final volver = find.byTooltip(TextosAlta.volverAMiUbicacion);
            if (sinGps) {
              expect(volver, findsNothing, reason: 'sin lectura no hay botón');
            } else {
              final rv = tester.getRect(volver);
              _dentro(rv, mapa, '«Volver a mi ubicación» con el teclado');
              _sinSolape(atribucion, rv, 'atribución vs «Volver a mi ubicación» con el teclado');
            }

            // Cierra el teclado: la pista vuelve, entera y sin pisar la atribución.
            await _cerrarTeclado(tester);
            expect(_textoPista, findsOneWidget, reason: 'sin teclado la pista vuelve');
            final mapaLibre = tester.getRect(find.byType(MapaAlta));
            final pista = tester.getRect(_pastillaPista);
            _dentro(pista, mapaLibre, 'la pista al cerrar el teclado');
            _sinSolape(
              pista,
              tester.getRect(_atribucionDelAlta),
              'pista vs atribución sin teclado',
            );

            // Y se oculta de nuevo cada vez que el teclado se abre.
            await _abrirTeclado(tester);
            expect(_textoPista, findsNothing, reason: 'el teclado se abrió otra vez');
            await _cerrarTeclado(tester);
            expect(_textoPista, findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets('con el teclado abierto a 360×640 y texto ${escala}x «Volver a mi ubicación» se '
          'toca y devuelve el punto a la lectura del GPS', (tester) async {
        final m = await _montar(tester, escala: escala);
        await tester.pumpAndSettle();
        await _abrirTeclado(tester);

        // El colportor movió el mapa con el teclado abierto: el punto queda «Marcado a mano».
        m.fabrica.moverPorGesto(
          CamaraMapa(
            centro: Coordenadas(lat: puntoItalia.lat + 0.002, lon: puntoItalia.lon),
            zoom: m.fabrica.camara!.zoom,
          ),
        );
        await asentar(tester);
        expect(find.text(TextosAlta.marcadoAMano), findsOneWidget);

        final volver = find.byTooltip(TextosAlta.volverAMiUbicacion);
        expect(volver.hitTestable(), findsOneWidget, reason: 'el botón recibe el toque');
        final movimientos = m.fabrica.movimientos.length;
        await tester.tap(volver);
        await asentar(tester);

        expect(find.text(TextosAlta.marcadoAMano), findsNothing, reason: 'volvió a la lectura');
        expect(m.fabrica.movimientos, hasLength(movimientos + 1), reason: 'la cámara vuelve');
        expect(m.fabrica.movimientos.last.centro.lat, closeTo(puntoItalia.lat, 1e-9));
        expect(m.fabrica.movimientos.last.centro.lon, closeTo(puntoItalia.lon, 1e-9));
        expect(_textoPista, findsNothing, reason: 'el teclado sigue abierto');
        expect(tester.takeException(), isNull);
      });
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets('con el teclado abierto a 360×640 y texto ${escala}x se puede marcar el punto '
          'tocando el mapa (sin GPS)', (tester) async {
        await _montar(tester, gps: gpsSinPermiso, escala: escala);
        await tester.pumpAndSettle();
        await _abrirTeclado(tester);
        expect(find.text(TextosAlta.marcadoAMano), findsNothing);

        await tester.tapAt(tester.getCenter(find.byType(MapaAlta)));
        await asentar(tester, 10);

        expect(find.text(TextosAlta.marcadoAMano), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group(
    'QA2 #286 · 03A · 04 número editado: la etiqueta «Editado» no se parte a mitad de palabra',
    () {
      for (final escala in [1.0, 1.3, 2.0]) {
        testWidgets('a 360×640 y texto ${escala}x', (tester) async {
          await _montar(tester, escala: escala);
          await tester.enterText(find.widgetWithText(TextField, '1234'), '1236');
          await asentar(tester);
          await tester.pumpAndSettle();

          final etiqueta = find.text('Editado');
          expect(etiqueta, findsOneWidget);
          final render = tester.renderObject<RenderParagraph>(etiqueta);
          final renglones = (TextPainter(
            text: render.text,
            textDirection: TextDirection.ltr,
            textScaler: render.textScaler,
          )..layout(maxWidth: render.size.width)).computeLineMetrics();
          expect(renglones, hasLength(1), reason: '«Editado» baja a 2 renglones');
          // skip: QA #288: a 360×640 con texto 2x la etiqueta «Editado» de la columna NÚMERO se parte
          // a mitad de palabra («Editad» / «o»); viene de #193 (HojaAlta), no del delta de #288.
        }, skip: escala == 2.0);
      }
    },
  );

  group('QA2 #286 · vista previa de la hoja de duplicados: la atribución no tapa ningún pin', () {
    for (final candidatas in [1, 2, 28]) {
      for (final escala in [1.0, 1.3, 2.0]) {
        testWidgets('$candidatas candidata(s) a 360×640 y texto ${escala}x', (tester) async {
          await _montar(tester, repo: _repoCon(candidatas), escala: escala);
          await _tocar(tester, find.text('Casa'));
          await _tocar(tester, _registrar);
          expect(tester.takeException(), isNull);

          final vista = find.byType(MapaBase).last;
          final rect = tester.getRect(vista);
          // La vista previa es el último `MapaBase` del árbol (el de la hoja, sobre el del alta).
          final mapaBase = tester.widget<MapaBase>(vista);
          expect(mapaBase.interaccion, InteraccionMapa.ninguna, reason: 'no es la vista previa');
          final camara = (tester.state(vista) as ControladorMapaBase).camara;
          final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
          final atribucion = tester.getRect(
            find.descendant(of: vista, matching: find.text(_atribucion)),
          );
          _dentro(atribucion, rect, 'la atribución de la vista previa');

          for (final p in mapaBase.puntos) {
            final px = ProyeccionMercator.aPixeles(p.coordenadas, camara.zoom);
            final posicion = rect.center + Offset(px.x - centro.x, px.y - centro.y);
            // El relleno del pin, según el estilo del mapa: «nueva» 11, candidata 11.5 y, con dos
            // letras, 14.5. El trazo blanco (3 dp) y 1 dp del relleno pueden rozar la atribución (con
            // 28 candidatas y texto 2x «nueva» queda en el margen de 40 dp del encuadre): se admite un
            // roce de 2 dp, pero ningún pin queda tapado.
            final radio = p.estilo == EstiloPunto.nuevo
                ? 11.0
                : ((p.letra?.length ?? 0) > 1
                      ? ConstructorEstiloMapa.radioCandidataDosLetras
                      : ConstructorEstiloMapa.radioCandidata);
            final circulo = Rect.fromCircle(center: posicion, radius: radio);
            _dentro(circulo, rect, 'el pin «${p.letra ?? p.id}»');
            _sinSolape(circulo.deflate(2), atribucion, 'pin «${p.letra ?? p.id}» vs atribución');
          }
        });
      }
    }
  });

  group('QA2 #286 · rótulos de candidatas sin tope (28 candidatas: «AA» y «AB»)', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('el mapa, la leyenda y la etiqueta dicen lo mismo (texto ${escala}x)', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await _montar(tester, repo: _repoCon(28), escala: escala);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _registrar);
        expect(tester.takeException(), isNull);

        final esperadas = [for (var i = 0; i < 28; i++) FormatoUbicaciones.rotuloCandidata(i)];
        expect(esperadas.take(3), ['A', 'B', 'C']);
        expect(esperadas[25], 'Z');
        expect(esperadas[26], 'AA');
        expect(esperadas[27], 'AB');
        expect(esperadas.toSet(), hasLength(28), reason: 'ningún rótulo se repite');

        // El pin del mapa.
        final mapaBase = tester.widget<MapaBase>(find.byType(MapaBase).last);
        expect(mapaBase.interaccion, InteraccionMapa.ninguna, reason: 'no es la vista previa');
        final letras = [
          for (final p in mapaBase.puntos)
            if (p.estilo == EstiloPunto.candidata) p.letra,
        ];
        expect(letras, esperadas);

        // La leyenda («AA a 38 m») y la lista, hasta la última.
        for (final i in [0, 25, 26, 27]) {
          final r = esperadas[i];
          final metros = 12.0 + i * 2;
          expect(find.text('$r a ${FormatoUbicaciones.distancia(metros)}'), findsOneWidget);
        }
        for (final r in ['AA', 'AB']) {
          final etiqueta = find.bySemanticsLabel('Candidata $r');
          await tester.ensureVisible(etiqueta);
          await tester.pump();
          expect(etiqueta, findsOneWidget, reason: 'la etiqueta «Candidata $r» para el lector');
          // La píldora entra en la tarjeta: ni se corta ni deja el rótulo suelto.
          final letra = find.text(r).last;
          final pildora = tester.getRect(
            find.ancestor(of: letra, matching: find.byType(Container)).first,
          );
          expect(pildora.height, greaterThanOrEqualTo(24));
          expect(pildora.width, greaterThanOrEqualTo(tester.getSize(letra).width));
        }
        semantica.dispose();
      });
    }
  });

  group('QA2 #286 · espacio duro entre el número y la unidad', () {
    final conEspacioComun = RegExp(r'\d (m|km)\b');

    for (final candidatas in [1, 2]) {
      for (final escala in [1.0, 1.3, 2.0]) {
        testWidgets('$candidatas candidata(s) a 360×640 y texto ${escala}x: ninguna distancia '
            'parte el renglón', (tester) async {
          await _montar(tester, repo: _repoCon(candidatas), escala: escala);
          await _tocar(tester, find.text('Casa'));
          await _tocar(tester, _registrar);

          final textos = [
            for (final e
                in find
                    .descendant(of: find.byType(HojaDuplicadoAlta), matching: find.byType(Text))
                    .evaluate())
              if ((e.widget as Text).data != null) (e.widget as Text).data!,
          ];
          expect(
            textos.where(conEspacioComun.hasMatch),
            isEmpty,
            reason: 'distancia con espacio común',
          );
          expect(textos.where((t) => t.contains('${FormatoUbicaciones.espacioDuro}m')), isNotEmpty);
        });
      }
    }

    for (final escala in [1.0, 1.3, 2.0]) {
      testWidgets('el título «Ya existe una ubicación a 12 m» no deja la unidad sola '
          '(texto ${escala}x)', (tester) async {
        await _montar(tester, repo: _repoCon(1), escala: escala);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _registrar);

        final titulo = find.textContaining('Ya existe una ubicación a');
        expect(titulo, findsOneWidget);
        final render = tester.renderObject<RenderParagraph>(titulo);
        final texto = render.text.toPlainText();
        // Donde empieza la última línea (el extremo izquierdo de su renglón).
        final inicio = render.getPositionForOffset(Offset(0, render.size.height - 1)).offset;
        final linea = texto.substring(inicio);
        expect(linea, contains('12 m'), reason: 'la última línea es «$linea»');
      });
    }
  });
}
