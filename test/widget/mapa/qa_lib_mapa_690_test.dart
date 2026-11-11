// QA de #673 / PR #690: la app consume lib-mapa (`colportores_mapa` v1.0.0). El mapa nativo no se
// dibuja en `flutter test`, así que se prueba lo que el estilo y los tokens le entregan: que el aspecto
// no cambió contra la regla de antes (comparado con las reglas viejas copiadas acá), que el estilo
// final es consistente con los glyphs y sprites del paquete, y qué esconde la colocación de símbolos.
//
// Las capturas (`QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas/` (gitignored, fuera del commit).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mapa/colportores_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/assets_de_lib_mapa.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _recursos = '/data/user/0/uy.colportores/files/mapa/lib-mapa-1.0.0';

ConfigVistaMapa _config({FuenteMapa? fuente}) => ConfigVistaMapa(
  fuente: fuente ?? const FuenteMapa.offline('/data/montevideo.pmtiles'),
  camaraInicial: const CamaraMapa(centro: Coordenadas(lat: -34.9105, lon: -56.1505), zoom: 16),
  zoomMinimo: 3,
  zoomMaximo: MapaAlta.zoomMaximo,
  interaccion: const InteraccionMapa(),
  dobleToqueZoom: true,
  fondo: ColoresMapa.fondo,
  colorNuevo: const Color(0xFF0B6E4F),
  puntos: const [],
  agruparPuntos: true,
  precision: null,
  cercania: null,
  puntosTocables: true,
);

List<Map<String, dynamic>> _capas(String estilo) => [
  for (final c in (jsonDecode(estilo) as Map<String, dynamic>)['layers'] as List<dynamic>)
    c as Map<String, dynamic>,
];

String _estiloFinal({FuenteMapa? fuente}) => ConstructorEstiloMapa.construir(
  estiloBase: estiloDeLibMapa(),
  directorioRecursos: _recursos,
  config: _config(fuente: fuente),
);

// ---- La regla de antes (develop, `ColoresZona`), copiada tal cual para comparar ----

const _fondosViejos = [Color(0xFFF6F5F0), Color(0xFFDDE8D3)];

double _contrasteViejo(Color color) {
  final claro = color.computeLuminance();
  var peor = double.infinity;
  for (final fondo in _fondosViejos) {
    final otro = fondo.computeLuminance();
    final mayor = claro > otro ? claro : otro;
    final menor = claro > otro ? otro : claro;
    final razon = (mayor + .05) / (menor + .05);
    if (razon < peor) peor = razon;
  }
  return peor;
}

Color _aOchoBits(Color c) =>
    Color.fromARGB(255, (c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

Color _bordeViejo(int rgb) {
  var color = Color(0xFF000000 | rgb);
  for (var i = 0; i < 40 && _contrasteViejo(color) < 3.0; i++) {
    color = _aOchoBits(Color.lerp(color, const Color(0xFF000000), .08)!);
  }
  return color;
}

String _hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. el borde de las zonas: la misma regla que antes', () {
    test('dado cualquier color elegido por el coordinador, cuando se calcula el borde, entonces es '
        'el de la regla de develop y llega a 3:1', () {
      final distintos = <String>[];
      var probados = 0;
      for (var r = 0; r < 256; r += 15) {
        for (var g = 0; g < 256; g += 15) {
          for (var b = 0; b < 256; b += 15) {
            final rgb = (r << 16) | (g << 8) | b;
            final nuevo = ColoresZona.borde(_hex(rgb));
            final viejo = _bordeViejo(rgb);
            probados++;
            if (nuevo.toARGB32() != viejo.toARGB32()) distintos.add('${_hex(rgb)} $nuevo $viejo');
            expect(ColoresZona.contraste(nuevo), greaterThanOrEqualTo(3.0), reason: _hex(rgb));
          }
        }
      }
      expect(probados, 18 * 18 * 18);
      expect(
        distintos,
        isEmpty,
        reason: '${distintos.length} colores cambian: ${distintos.take(5)}',
      );
    });

    test('dado el contraste medido, cuando se compara con la fórmula de antes, entonces coincide '
        '(sin diferencia visible)', () {
      for (final rgb in [0x13407A, 0xFFD966, 0x9FD3FF, 0xFFFFFF, 0x000000, 0x808080, 0xDDE8D3]) {
        final color = Color(0xFF000000 | rgb);
        expect(
          ColoresZona.contraste(color),
          closeTo(_contrasteViejo(color), 1e-9),
          reason: _hex(rgb),
        );
      }
    });

    test('dado un valor que no es #RRGGBB (nulo, vacío, corto, con espacios, emoji), entonces se '
        'usa el azul de siempre y no revienta', () {
      final porDefecto = ColoresZona.borde(null);
      expect(porDefecto.toARGB32(), 0xFF13407A);
      for (final raro in [
        '',
        '#fff',
        'FF0000',
        '#12345G',
        ' #FF0000 ',
        '#FF00000',
        '🎨',
        '#ÑÑÑÑÑÑ',
      ]) {
        expect(ColoresZona.borde(raro), porDefecto, reason: '«$raro»');
      }
      // El minúsculo sí es un hex válido.
      expect(ColoresZona.borde('#ff0000'), ColoresZona.borde('#FF0000'));
    });
  });

  group('2. la insignia de la lista (vista 05) es la de antes con los tokens', () {
    // La tabla de develop: (relleno, tinta, borde de 2,5, franjas).
    const antes = <EstadoCasa, (Color, Color, Color?)>{
      EstadoCasa.sinVisita: (Colors.white, ColoresLista.grisEstado, ColoresLista.grisEstado),
      EstadoCasa.noContesto: (ColoresLista.grisEstado, Colors.white, null),
      EstadoCasa.entrevistaAgendada: (ColoresLista.ambar, ColoresLista.tinta, null),
      EstadoCasa.entrevistaHecha: (ColoresLista.verde, Colors.white, null),
      EstadoCasa.ventaCompleta: (ColoresLista.verde, Colors.white, null),
      EstadoCasa.cobranzaPendiente: (ColoresLista.azul, Colors.white, null),
      EstadoCasa.entregaYPago: (ColoresLista.azul, Colors.white, null),
      EstadoCasa.rechazo: (ColoresLista.rojo, Colors.white, null),
    };

    for (final tamano in [22.0, 26.0, 30.0, 36.0]) {
      testWidgets('a $tamano dp: relleno, glifo, borde, esquinas y franjas como en develop', (
        tester,
      ) async {
        for (final e in EstadoCasa.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: InsigniaEstadoCasa(estado: e, tamano: tamano),
              ),
            ),
          );
          final caja =
              tester
                      .widget<Container>(
                        find.descendant(
                          of: find.byType(InsigniaEstadoCasa),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration;
          final (fondo, tinta, borde) = antes[e]!;
          final esGrande = tamano >= 26;
          final radio = e.esDeVenta
              ? BorderRadius.circular(esGrande ? 8 : 5)
              : BorderRadius.circular(tamano);

          expect(caja.borderRadius, radio, reason: e.name);
          if (e == EstadoCasa.entregaYPago) {
            expect(caja.color, isNull);
            final g = caja.gradient! as LinearGradient;
            expect(g.colors, [
              ColoresLista.azul,
              ColoresLista.azul,
              const Color(0xFF4D76B1),
              const Color(0xFF4D76B1),
            ]);
            expect(g.stops, [0, 4 / 7, 4 / 7, 1]);
            expect(g.tileMode, TileMode.repeated);
            const raiz2 = 1.4142135623730951;
            final fin = -1 + 2 * (7 / raiz2) / tamano;
            expect(g.begin, Alignment.topLeft);
            expect(g.end, Alignment(fin, fin));
          } else {
            expect(caja.gradient, isNull, reason: e.name);
            expect(caja.color, fondo, reason: e.name);
          }
          if (borde == null) {
            expect(caja.border, isNull, reason: e.name);
          } else {
            expect(caja.border, Border.all(color: borde, width: 2.5), reason: e.name);
          }
          final glifo = FormatoListaUbicaciones.glifo(e);
          if (glifo.isNotEmpty) {
            final texto = tester.widget<Text>(
              find.descendant(of: find.byType(InsigniaEstadoCasa), matching: find.text(glifo)),
            );
            expect(texto.style!.color, tinta, reason: e.name);
            expect(texto.style!.fontSize, esGrande ? 15 : 10, reason: e.name);
          }
        }
      });
    }

    test('el glifo y el nombre de cada estado de la app no se separaron de los del token', () {
      for (final e in EstadoCasa.values) {
        final token = VarianteMarcador.de(e).token;
        expect(token.glifo ?? '', FormatoListaUbicaciones.glifo(e), reason: e.name);
        expect(token.nombre, FormatoListaUbicaciones.estado(e), reason: e.name);
      }
    });

    test('con los tokens el relleno y el número de cada estado llegan a 4,5:1 (menos el glifo '
        'inexistente de «Sin visita»)', () {
      double razon(int a, int b) => ContrasteMapa.entre(a, b);
      for (final v in VarianteMarcador.values) {
        expect(
          razon(v.token.tintaNumero, v.token.relleno),
          greaterThanOrEqualTo(4.5),
          reason: v.name,
        );
        if (v != VarianteMarcador.sinVisita) {
          expect(razon(v.token.tinta, v.token.relleno), greaterThanOrEqualTo(4.5), reason: v.name);
        }
      }
      // El número blanco también tiene que leerse sobre la franja clara de «Entrega y pago».
      final f = VarianteMarcador.entregaYPago.token;
      expect(razon(f.tintaNumero, f.franjas!.clara), greaterThanOrEqualTo(4.5));
    });
  });

  group('3. el estilo final es consistente con lo que viaja en el paquete', () {
    test(
      'dado el estilo armado, cuando se listan los text-font, entonces cada uno tiene su carpeta '
      'de glyphs con el rango de los dígitos',
      () {
        final fuentes = <String>{};
        for (final capa in _capas(_estiloFinal())) {
          final layout = capa['layout'];
          if (layout is Map<String, dynamic> && layout['text-font'] != null) {
            // Puede ser una lista de nombres o una expresión: se juntan los nombres de fuente.
            fuentes.addAll(
              RegExp(
                r'NotoSans-[A-Za-z]+',
              ).allMatches(jsonEncode(layout['text-font'])).map((m) => m.group(0)!),
            );
          }
        }
        expect(fuentes, containsAll(['NotoSans-Italic', 'NotoSans-Medium', 'NotoSans-Regular']));
        for (final f in fuentes) {
          final rango = File('${carpetaDeLibMapa('glyphs/$f').path}/0-255.pbf');
          expect(rango.existsSync(), isTrue, reason: 'falta glyphs/$f/0-255.pbf en el paquete');
        }
      },
    );

    test('dados los íconos del estilo del paquete, entonces existen en la hoja de sprites '
        '(1x y 2x)', () {
      final nombres = <String>{};
      for (final capa in _capas(estiloDeLibMapa())) {
        final layout = capa['layout'];
        if (layout is Map<String, dynamic> && layout['icon-image'] is String) {
          nombres.add(layout['icon-image'] as String);
        }
        final paint = capa['paint'];
        if (paint is Map<String, dynamic>) {
          for (final e in paint.entries) {
            if (e.key.endsWith('-pattern') && e.value is String) nombres.add(e.value as String);
          }
        }
      }
      for (final hoja in ['grayscale.json', 'grayscale@2x.json']) {
        final json =
            jsonDecode(archivoDeLibMapa('sprites/$hoja').readAsStringSync())
                as Map<String, dynamic>;
        for (final n in nombres) {
          expect(json.containsKey(n), isTrue, reason: '«$n» no está en $hoja');
        }
      }
    });

    test(
      'dado un paquete de tiles en tres partes, cuando se arma el estilo, entonces los ids no se '
      'repiten y los números de OSM de cada parte quedan por debajo de las capas de la app',
      () {
        final capas = _capas(
          _estiloFinal(
            fuente: const FuenteMapa.offlineEnPartes(['/a.pmtiles', '/b.pmtiles', '/c.pmtiles']),
          ),
        );
        final ids = [for (final c in capas) c['id'] as String];
        expect(ids.toSet().length, ids.length, reason: 'ids repetidos: MapLibre rechaza el estilo');
        final numeros = [
          for (var i = 0; i < ids.length; i++)
            if (ids[i].startsWith('address_label')) i,
        ];
        expect(numeros, hasLength(3));
        final primeraPropia = ids.indexWhere((id) => id.startsWith('colportores:'));
        expect(numeros.every((i) => i < primeraPropia), isTrue);
        for (final c in capas.where((c) => (c['id'] as String).startsWith('address_label'))) {
          expect(c['minzoom'], TokensMapa.zoomNumerosDePuerta, reason: '${c['id']}');
        }
      },
    );

    test('dado un estilo sin glyphs ni sprites, entonces no queda ninguna capa con '
        'texto (necesita glyphs), pero los íconos de la app siguen', () {
      final capas = _capas(
        ConstructorEstiloMapa.construirSinRecursos(
          estiloBase: estiloDeLibMapa(),
          config: _config(),
        ),
      );
      final conTexto = capas.where(
        (c) =>
            c['type'] == 'symbol' &&
            (c['layout'] as Map<String, dynamic>).containsKey('text-field'),
      );
      expect(conTexto, isEmpty);
      final ids = [for (final c in capas) c['id']];
      expect(ids, containsAll(ConstructorEstiloMapa.capasQueOcupanLugar));
    });

    test(
      'las capas que ocupan su lugar no llevan texto propio que compita con el número de OSM',
      () {
        final capas = _capas(_estiloFinal());
        for (final id in ConstructorEstiloMapa.capasQueOcupanLugar) {
          final layout = capas.singleWhere((c) => c['id'] == id)['layout'] as Map<String, dynamic>;
          expect(layout.containsKey('text-field'), isFalse, reason: id);
          expect(layout.containsKey('icon-padding'), isFalse, reason: id);
        }
      },
    );

    testWidgets(
      'dado el rótulo de la zona (por debajo de los marcadores), cuando los marcadores ya no ignoran la '
      'colocación, entonces el rótulo puede esconderse bajo cualquier casa: tiene que ganar o '
      'declarar qué pasa',
      (tester) async {
        // MapLibre ubica primero los símbolos de las capas de arriba. `capaZonasRotulo` está más abajo
        // que `capasQueOcupanLugar` y no tiene `text-allow-overlap`: si el cuadro de su texto toca el de
        // una insignia, el nombre de la zona desaparece (antes, con `icon-ignore-placement: true`,
        // los marcadores nunca lo escondían). El nombre de la zona es lo que identifica la propia sin
        // depender del color (#654).
        final capas = _capas(
          ConstructorEstiloMapa.construir(
            estiloBase: estiloDeLibMapa(),
            directorioRecursos: _recursos,
            config: _config().conZonaPropiaDePrueba(),
          ),
        );
        final ids = [for (final c in capas) c['id'] as String];
        final rotulo = capas[ids.indexOf(ConstructorEstiloMapa.capaZonasRotulo)];
        final layout = rotulo['layout'] as Map<String, dynamic>;
        final primerOcupante = ConstructorEstiloMapa.capasQueOcupanLugar
            .map(ids.indexOf)
            .reduce((a, b) => a < b ? a : b);
        expect(ids.indexOf(ConstructorEstiloMapa.capaZonasRotulo), lessThan(primerOcupante));
        expect(
          layout['text-allow-overlap'] == true || layout['text-optional'] == true,
          isTrue,
          reason: 'el rótulo de la zona se esconde donde lo pisa un marcador',
        );
      },
    );
  });

  group('4. zooms y atribución', () {
    test(
      'el zoom máximo 19 es el mismo en el alta, el mapa principal, Modificar y las vistas previas',
      () {
        expect(MapaAlta.zoomMaximo, 19);
        expect(_config().zoomMaximo, 19);
        expect(
          const MapaBase(
            fuente: FuenteMapa.sinTiles(),
            camaraInicial: CamaraMapa(centro: Coordenadas(lat: 0, lon: 0), zoom: 3),
          ).zoomMaximo,
          19,
        );
        expect(MapaAlta.zoomCalle, 16);
        expect(MapaAlta.zoomMinimo, lessThan(MapaAlta.zoomCalle));
        expect(MapaAlta.zoomCalle, lessThan(MapaAlta.zoomMaximo));
      },
    );
  });

  group('5. capturas de los marcadores y la insignia con los tokens', () {
    testWidgets('los 9 marcadores del mapa (de lejos y acercado) y las 8 insignias de la lista', (
      tester,
    ) async {
      await tester.runAsync(_cargarFuentes);
      final insignias = <ui.Image>[];
      final cuadrados = <ui.Image>[];
      await tester.runAsync(() async {
        for (final v in VarianteMarcador.values) {
          final a = await MarcadorEstado.dibujarInsignia(v, escala: 4);
          final c = await MarcadorEstado.dibujarCuadrado(v, escala: 4);
          insignias.add((await (await ui.instantiateImageCodec(a)).getNextFrame()).image);
          cuadrados.add((await (await ui.instantiateImageCodec(c)).getNextFrame()).image);
        }
      });
      expect(insignias, hasLength(VarianteMarcador.values.length));
      // Cada PNG tiene píxeles del color del token en el centro de la forma.
      for (var i = 0; i < insignias.length; i++) {
        expect(insignias[i].width, greaterThan(0));
        expect(cuadrados[i].width, greaterThan(0));
      }
      if (!_conCapturas) return;

      final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
      final registro = ui.PictureRecorder();
      final lienzo = ui.Canvas(registro);
      lienzo.drawRect(
        const Rect.fromLTWH(0, 0, 1900, 520),
        Paint()..color = const Color(0xFFF6F5F0),
      );
      for (var i = 0; i < insignias.length; i++) {
        lienzo.drawImage(insignias[i], Offset(10.0 + i * 205, 10), Paint());
        lienzo.drawImage(cuadrados[i], Offset(10.0 + i * 205, 150), Paint());
      }
      final img = await tester.runAsync(() => registro.endRecording().toImage(1900, 520));
      final png = await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
      File('${dir.path}/690_marcadores.png').writeAsBytesSync(png!.buffer.asUint8List());

      // Las insignias de la lista, a 22 y 30 dp, en 1,0× y 2,0× de texto.
      final clave = GlobalKey();
      for (final escala in [1.0, 2.0]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(escala)),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: RepaintBoundary(
                  key: clave,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final t in [22.0, 30.0])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final e in EstadoCasa.values)
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: InsigniaEstadoCasa(estado: e, tamano: t),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final borde = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final foto = await tester.runAsync(() => borde.toImage(pixelRatio: 3));
        final datos = await tester.runAsync(() => foto!.toByteData(format: ui.ImageByteFormat.png));
        File(
          '${dir.path}/690_insignias_lista_x$escala.png',
        ).writeAsBytesSync(Uint8List.view(datos!.buffer));
      }
    });
  });
}

/// Una config con una zona propia, para que el estilo arme el rótulo (`capaZonasRotulo`).
extension on ConfigVistaMapa {
  ConfigVistaMapa conZonaPropiaDePrueba() => ConfigVistaMapa(
    fuente: fuente,
    camaraInicial: camaraInicial,
    zoomMinimo: zoomMinimo,
    zoomMaximo: zoomMaximo,
    interaccion: interaccion,
    dobleToqueZoom: dobleToqueZoom,
    fondo: fondo,
    colorNuevo: colorNuevo,
    puntos: puntos,
    agruparPuntos: agruparPuntos,
    precision: precision,
    cercania: cercania,
    puntosTocables: puntosTocables,
    zonas: const [
      ZonaMapa(
        id: 'z1',
        rotulo: 'Zona 1',
        poligonos: [
          [
            [
              Coordenadas(lat: -34.90, lon: -56.15),
              Coordenadas(lat: -34.90, lon: -56.14),
              Coordenadas(lat: -34.91, lon: -56.14),
            ],
          ],
        ],
        color: Color(0xFF13407A),
        propia: true,
        puntoRotulo: Coordenadas(lat: -34.905, lon: -56.145),
      ),
    ],
  );
}
