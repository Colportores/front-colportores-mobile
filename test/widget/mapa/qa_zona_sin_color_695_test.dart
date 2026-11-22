// QA de #695 / PR #711: la zona sin color se ve gris, desde el token de lib-mapa v1.1.0 («Zona s/color»,
// decisión de Cristian del 11/11, lib-mapa#12). No hay artboard nuevo: se compara con las vistas
// vecinas del mapa (06 y 24). El mapa nativo no se dibuja en `flutter test`: se prueba lo que la app le
// entrega (el color de `ZonaMapa`, el GeoJSON y las capas del estilo) y los estados de la pestaña.
//
// Las capturas (`QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas/` (gitignored, fuera del commit).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:colportores_mapa/colportores_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/zona_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/assets_de_lib_mapa.dart';
import '../../helpers/zonas_del_mapa_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// El gris del token y el borde que sale de oscurecerlo hasta 3:1 (calculado a mano en la revisión
/// de QA: 2 pasos del 8 % hacia el negro).
const _grisDelToken = 0xFF8A94A6;
const _bordeGris = 0xFF757D8D;
const _azulDeAntes = 0xFF13407A;

// ---- WCAG 2 propio del test: no depende del código de la librería que se está comprobando.
double _lineal(int canal) {
  final s = canal / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luz(int c) =>
    0.2126 * _lineal((c >> 16) & 255) +
    0.7152 * _lineal((c >> 8) & 255) +
    0.0722 * _lineal(c & 255);

double _contraste(int a, int b) {
  final x = _luz(a);
  final y = _luz(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

const _tierra = 0xFFF6F5F0;
const _parque = 0xFFDDE8D3;
const _blanco = 0xFFFFFFFF;

/// Todo lo que el coordinador puede haber guardado (o el backend devolver) que no es un `#RRGGBB`.
final _sinColor = <String?>[
  null,
  '',
  ' ',
  '   ',
  '#',
  '#1',
  '#12345',
  '#1234567',
  '#GGGGGG',
  '#ÑÑÑÑÑÑ',
  'azul',
  'null',
  'rgb(138,148,166)',
  '8A94A6',
  ' #8A94A6',
  '#8A94A6 ',
  '#8A94A6\n',
  '#8A94A6FF',
  '#🙂🙂🙂',
  '🙂',
  '#${'A' * 5000}',
  'x' * 10000,
];

ConfigVistaMapa _config(List<ZonaMapa> zonas) => ConfigVistaMapa(
  fuente: const FuenteMapa.offline('/data/montevideo.pmtiles'),
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
  zonas: zonas,
);

Map<String, dynamic> _estilo(List<ZonaMapa> zonas) =>
    jsonDecode(
          ConstructorEstiloMapa.construir(
            estiloBase: estiloDeLibMapa(),
            directorioRecursos: '/data/user/0/uy.colportores/files/mapa/lib-mapa-1.0.0',
            config: _config(zonas),
          ),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _capa(Map<String, dynamic> estilo, String id) =>
    ((estilo['layers'] as List<dynamic>).cast<Map<String, dynamic>>()).singleWhere(
      (c) => c['id'] == id,
    );

ZonaMapa _zona(String? color, {String nombre = 'Cerro Norte'}) => ZonaMapa.desde(
  ZonaDelMapa(
    id: 'z-${color ?? 'sin'}',
    nombre: nombre,
    propia: true,
    color: color,
    geometria: zonaCuadrada('x', propia: true).geometria,
  ),
);

void main() {
  group('el color de la zona sin color: el gris del token', () {
    test('dado el token de lib-mapa v1.1.0, entonces es un solo valor, el gris #8A94A6 (no el azul '
        'del móvil de antes)', () {
      expect(TokensMapa.zonaSinColor, _grisDelToken);
      expect(ColoresZona.porDefecto.toARGB32(), _grisDelToken);
      expect(ColoresZona.porDefecto.toARGB32(), isNot(_azulDeAntes));
    });

    for (final valor in _sinColor) {
      final etiqueta = valor == null
          ? 'null'
          : '«${valor.length > 20 ? '${valor.substring(0, 20)}… (${valor.length} caracteres)' : valor}»';
      test('dado el color $etiqueta, cuando se dibuja la zona, entonces sale el mismo gris '
          'oscurecido y no revienta', () {
        expect(ColoresZona.borde(valor).toARGB32(), _bordeGris);
        expect(_zona(valor).color.toARGB32(), _bordeGris);
      });
    }

    test('dada una zona sin color, entonces el borde llega a 3:1 sobre la tierra y sobre el '
        'parque, y a más de 3:1 sobre el filete blanco (cuenta propia, no la de la librería)', () {
      final borde = ColoresZona.borde(null).toARGB32();
      expect(_contraste(borde, _tierra), greaterThanOrEqualTo(3));
      expect(_contraste(borde, _parque), greaterThanOrEqualTo(3));
      expect(_contraste(borde, _blanco), greaterThanOrEqualTo(3));
      // El gris del token a secas no llega: por eso lo oscurece `bordeDeZona`.
      expect(_contraste(_grisDelToken, _parque), lessThan(3));
    });

    test('dado el borde de la zona sin color, entonces se ve gris: poca saturación, el mismo tono '
        'azulado del token y nada que ver con el azul de antes', () {
      final borde = ColoresZona.borde(null);
      final hsl = HSLColor.fromColor(borde);
      expect(hsl.saturation, lessThan(0.2));
      final a = HSLColor.fromColor(const Color(_grisDelToken));
      expect((hsl.hue - a.hue).abs(), lessThan(10));
      final antes = HSLColor.fromColor(const Color(_azulDeAntes));
      expect(antes.saturation, greaterThan(0.6));
      expect(_contraste(borde.toARGB32(), _azulDeAntes), lessThan(2.5));
    });

    test('dado un color elegido (claro, oscuro, en minúsculas), entonces no cambia nada: el gris '
        'es solo para el que no eligió', () {
      expect(ColoresZona.borde('#1F6E3A'), const Color(0xFF1F6E3A));
      expect(ColoresZona.borde('#a8312a'), const Color(0xFFA8312A));
      final amarillo = ColoresZona.borde('#FFFF00');
      expect(amarillo.toARGB32(), isNot(_bordeGris));
      expect(HSLColor.fromColor(amarillo).saturation, greaterThan(0.8));
      expect(ColoresZona.contraste(amarillo), greaterThanOrEqualTo(3));
    });

    test('dado que el coordinador eligió justo #8A94A6, entonces se ve igual que la que no eligió '
        '(el gris es un color como cualquiera)', () {
      expect(ColoresZona.borde('#8A94A6'), ColoresZona.borde(null));
    });
  });

  group('lo que el mapa recibe: el GeoJSON y las capas del estilo', () {
    test('dada una zona sin color y una elegida, entonces cada Feature lleva su color y el gris no '
        'se pisa con el otro', () {
      final fc = ConstructorEstiloMapa.coleccionZonas([_zona(null), _zona('#1F6E3A')]);
      final colores = [
        for (final f in (fc['features'] as List<dynamic>).cast<Map<String, dynamic>>())
          (f['properties'] as Map<String, dynamic>)['color'],
      ];
      expect(colores, ['#757D8D', '#1F6E3A']);
    });

    test('dada una zona sin color, cuando se arma el estilo, entonces relleno y borde leen la '
        'misma propiedad `color`, así que el relleno también es gris (20 %)', () {
      final estilo = _estilo([_zona(null)]);
      final fuente =
          (estilo['sources'] as Map<String, dynamic>)[ConstructorEstiloMapa.fuenteZonas]
              as Map<String, dynamic>;
      final f =
          ((fuente['data'] as Map<String, dynamic>)['features'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect((f['properties'] as Map<String, dynamic>)['color'], '#757D8D');

      final relleno = _capa(estilo, ConstructorEstiloMapa.capaZonaPropiaRelleno);
      final borde = _capa(estilo, ConstructorEstiloMapa.capaZonaPropiaBorde);
      final halo = _capa(estilo, ConstructorEstiloMapa.capaZonaPropiaHalo);
      expect((relleno['paint'] as Map<String, dynamic>)['fill-color'], ['get', 'color']);
      expect((relleno['paint'] as Map<String, dynamic>)['fill-opacity'], .2);
      expect((borde['paint'] as Map<String, dynamic>)['line-color'], ['get', 'color']);
      expect((borde['paint'] as Map<String, dynamic>)['line-width'], 4);
      expect((halo['paint'] as Map<String, dynamic>)['line-color'], '#FFFFFF');
    });

    test(
      'dada una zona sin color, entonces su nombre sigue legible: tinta oscura con filete blanco '
      'sobre el relleno gris (no depende del color, WCAG 1.4.1)',
      () {
        final rotulo = _capa(_estilo([_zona(null)]), ConstructorEstiloMapa.capaZonasRotulo);
        final p = rotulo['paint'] as Map<String, dynamic>;
        expect(p['text-halo-color'], '#FFFFFF');
        expect(_contraste(ColoresMapa.tinta.toARGB32(), _blanco), greaterThanOrEqualTo(7));
        // El relleno al 20 % del borde gris sobre la tierra y sobre el parque.
        for (final fondo in [_tierra, _parque]) {
          final mezcla = _mezcla(_bordeGris, fondo, .2);
          expect(
            _contraste(ColoresMapa.tinta.toARGB32(), mezcla),
            greaterThanOrEqualTo(4.5),
            reason: '${mezcla.toRadixString(16)} sobre ${fondo.toRadixString(16)}',
          );
        }
      },
    );

    test(
      'dado el estilo de lib-mapa, entonces la zona gris no se confunde con una línea de calles: '
      'el borde (4 px + filete de 7) es más oscuro y grueso que los límites #8A93A0 de 0,4-0,7 px',
      () {
        final estilo = _estilo([_zona(null)]);
        final limites = ((estilo['layers'] as List<dynamic>).cast<Map<String, dynamic>>()).where(
          (c) => c['id'] == 'boundaries' || c['id'] == 'boundaries_country',
        );
        expect(limites, isNotEmpty);
        for (final c in limites) {
          final p = c['paint'] as Map<String, dynamic>;
          expect(p['line-color'], '#8A93A0');
          final ancho = p['line-width'];
          // Los anchos del estilo base pueden ser un número o una expresión por zoom.
          if (ancho is num) expect(ancho, lessThan(4));
        }
        expect(
          _contraste(_bordeGris, 0xFF8A93A0),
          lessThan(1.5),
        ); // casi el mismo gris: va por grosor
      },
    );
  });

  group('estados de la pestaña «Mapa» con una zona sin color', () {
    const tamanos = [Size(360, 640), Size(412, 915)];

    for (final tamano in tamanos) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('dada una zona sin color en ${tamano.width.toInt()}×${tamano.height.toInt()} '
            'con texto ×$escala, entonces llega gris al mapa, sin overflow y el lector no oye '
            'ningún color', (tester) async {
          final semantica = tester.ensureSemantics();
          final zonas = ZonasDelMapaFalsas([
            zonaCuadrada('a', nombre: 'Cerro Norte', propia: true, color: null),
          ]);
          final m = await montarMapaUbicaciones(
            tester,
            otrosOverrides: [zonas.sobrescribe],
            escala: escala,
            tamano: tamano,
          );

          final z = m.mapa.config!.zonas.single;
          expect(z.color.toARGB32(), _bordeGris);
          expect(z.rotulo, 'Tu zona · Cerro Norte');
          expect(
            find.bySemanticsLabel('Mapa de ubicaciones. Tu zona: Cerro Norte.'),
            findsOneWidget,
          );
          expect(find.textContaining('gris', findRichText: true), findsNothing);
          expect(find.textContaining('azul', findRichText: true), findsNothing);
          expect(tester.takeException(), isNull);
          semantica.dispose();
        });
      }
    }

    testWidgets('dado que las zonas todavía se leen (cargando), entonces el mapa se abre sin zonas '
        'ni spinner suelto, y al llegar la sin color aparece gris', (tester) async {
      final zonas = ZonasDelMapaFalsas()..fallaAlSuscribir = null;
      final m = await montarMapaUbicaciones(tester, otrosOverrides: [zonas.sobrescribe]);
      expect(m.mapa.config!.zonas, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(botonNueva, findsOneWidget);

      zonas.emitir([zonaCuadrada('a', propia: true, color: null)]);
      await asentarLista(tester);
      expect(m.mapa.config!.zonas.single.color.toARGB32(), _bordeGris);
    });

    testWidgets(
      'dado un teléfono sin zonas (vacío), entonces no se dibuja nada y no aparece ningún '
      'aviso de zona',
      (tester) async {
        final zonas = ZonasDelMapaFalsas();
        final m = await montarMapaUbicaciones(tester, otrosOverrides: [zonas.sobrescribe]);
        expect(m.mapa.config!.zonas, isEmpty);
        expect(find.textContaining('zona', findRichText: true), findsNothing);
        expect(find.textContaining('Zona', findRichText: true), findsNothing);
      },
    );

    testWidgets(
      'dado un error al leer las zonas (error), entonces el mapa sigue en pie sin zonas y, '
      'cuando la lectura se recupera, la sin color vuelve en gris',
      (tester) async {
        final zonas = ZonasDelMapaFalsas()..fallaAlSuscribir = 'sin base';
        final m = await montarMapaUbicaciones(tester, otrosOverrides: [zonas.sobrescribe]);
        expect(m.mapa.config!.zonas, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(botonNueva, findsOneWidget);
        expect(tester.takeException(), isNull);

        zonas.emitir([zonaCuadrada('a', propia: true, color: null)]);
        await asentarLista(tester);
        expect(m.mapa.config!.zonas.single.color.toARGB32(), _bordeGris);
      },
    );

    testWidgets(
      'dada una zona gris ya dibujada, cuando la lectura falla a mitad, entonces conserva '
      'el gris y no cambia al azul',
      (tester) async {
        final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true, color: null)]);
        final m = await montarMapaUbicaciones(tester, otrosOverrides: [zonas.sobrescribe]);
        expect(m.mapa.config!.zonas.single.color.toARGB32(), _bordeGris);

        zonas.fallar();
        await asentarLista(tester);
        final z = m.mapa.config!.zonas;
        // Lo último que se leyó se conserva (documentado en `zonasParaElMapaProvider`).
        expect(z.single.color.toARGB32(), _bordeGris);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dado un pull que le pone color a la zona y otro que se lo saca, entonces pasa de '
        'gris a su color y vuelve al gris', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true, color: null)]);
      final m = await montarMapaUbicaciones(tester, otrosOverrides: [zonas.sobrescribe]);
      expect(m.mapa.config!.zonas.single.color.toARGB32(), _bordeGris);

      zonas.emitir([zonaCuadrada('a', propia: true, color: '#1F6E3A')]);
      await asentarLista(tester);
      expect(m.mapa.config!.zonas.single.color, const Color(0xFF1F6E3A));

      zonas.emitir([zonaCuadrada('a', propia: true, color: null)]);
      await asentarLista(tester);
      expect(m.mapa.config!.zonas.single.color.toARGB32(), _bordeGris);
    });

    testWidgets('dadas dos zonas propias, una sin color y otra con color, entonces cada una '
        'conserva el suyo', (tester) async {
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('sin', propia: true, color: null),
        zonaCuadrada('con', propia: true, color: '#A8312A', lon: -56.1),
      ]);
      final m = await montarMapaUbicaciones(tester, otrosOverrides: [zonas.sobrescribe]);
      final porId = {for (final z in m.mapa.config!.zonas) z.id: z.color.toARGB32()};
      expect(porId, {'sin': _bordeGris, 'con': 0xFFA8312A});
    });
  });

  group('privacidad', () {
    test('dada una zona sin color, entonces ni toString ni los props de ZonaMapa muestran el '
        'nombre de la zona', () {
      final z = _zona(null, nombre: 'Cerro Norte');
      expect(z.toString(), isNot(contains('Cerro Norte')));
      expect(zonaCuadrada('a', nombre: 'Cerro Norte').toString(), isNot(contains('Cerro Norte')));
    });
  });

  group('captura de la zona gris sobre los fondos del mapa (simulada: el mapa nativo no se '
      'dibuja en test)', () {
    test('se genera la plancha antes/después en .dart_tool/qa_capturas', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final inter = await File('assets/fonts/Inter.ttf').readAsBytes();
      final cargador = FontLoader('Inter')..addFont(Future.value(ByteData.sublistView(inter)));
      await cargador.load();

      const ancho = 1200.0;
      const alto = 760.0;
      final registro = ui.PictureRecorder();
      final lienzo = Canvas(registro);
      final fondos = [
        ('tierra #F6F5F0', const Color(_tierra)),
        ('parque #DDE8D3', const Color(_parque)),
        ('agua #C9D6EA', const Color(0xFFC9D6EA)),
      ];
      final colores = [
        ('antes: azul #13407A', const Color(_azulDeAntes)),
        ('ahora: gris #8A94A6 → borde #757D8D', const Color(_bordeGris)),
        ('gris sin oscurecer #8A94A6 (no llega a 3:1)', const Color(_grisDelToken)),
      ];
      lienzo.drawRect(const Rect.fromLTWH(0, 0, ancho, alto), Paint()..color = Colors.white);
      for (var f = 0; f < fondos.length; f++) {
        for (var c = 0; c < colores.length; c++) {
          final x = 20.0 + c * 395;
          final y = 20.0 + f * 245;
          final r = Rect.fromLTWH(x, y, 375, 225);
          lienzo.drawRect(r, Paint()..color = fondos[f].$2);
          // Un límite administrativo del estilo base (#8A93A0, 0,7 px) para comparar.
          lienzo.drawLine(
            Offset(x, y + 20),
            Offset(x + 375, y + 20),
            Paint()
              ..color = const Color(0xFF8A93A0)
              ..strokeWidth = 1,
          );
          final zona = Path()
            ..moveTo(x + 50, y + 50)
            ..lineTo(x + 320, y + 65)
            ..lineTo(x + 300, y + 190)
            ..lineTo(x + 70, y + 175)
            ..close();
          final color = colores[c].$2;
          lienzo.drawPath(zona, Paint()..color = color.withValues(alpha: .2));
          lienzo.drawPath(
            zona,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = 7
              ..color = Colors.white.withValues(alpha: .9),
          );
          lienzo.drawPath(
            zona,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = 4
              ..color = color,
          );
          final texto = TextPainter(
            text: TextSpan(
              text: 'Tu zona · Cerro Norte',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ColoresMapa.tinta,
                shadows: [
                  for (final d in const [
                    Offset(1, 1),
                    Offset(-1, -1),
                    Offset(1, -1),
                    Offset(-1, 1),
                  ])
                    Shadow(color: Colors.white, offset: d),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          texto.paint(lienzo, Offset(x + 100, y + 110));
          final pie = TextPainter(
            text: TextSpan(
              text: '${colores[c].$1} · ${fondos[f].$1}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF0E1A2B)),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          pie.paint(lienzo, Offset(x + 8, y + 205));
        }
      }
      final img = await registro.endRecording().toImage(ancho.toInt(), alto.toInt());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      expect(png, isNotNull);
      if (!_conCapturas) return;
      final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
      File('${dir.path}/zona_sin_color_695.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}

/// El color de [primero] al [alfa] sobre [fondo] (ambos opacos), canal por canal.
int _mezcla(int primero, int fondo, double alfa) {
  int canal(int s) => (alfa * ((primero >> s) & 255) + (1 - alfa) * ((fondo >> s) & 255)).round();
  return 0xFF000000 | (canal(16) << 16) | (canal(8) << 8) | canal(0);
}
