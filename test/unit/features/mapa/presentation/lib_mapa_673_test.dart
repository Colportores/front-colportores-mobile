// #673: la app consume lib-mapa (`colportores_mapa`, tag v1.0.0) en vez de la copia a mano del
// estilo. El estilo, los glyphs y los sprites salen del paquete; los colores y formas de los estados de
// casa, las zonas, los zooms y la atribución, de sus tokens. El aspecto no cambia.
import 'dart:convert';

import 'package:colportores_mapa/colportores_mapa.dart';
import 'package:colportores_mobile/features/mapa/data/services/preparador_recursos_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/marcador_estado.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/recursos_mapa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/assets_de_lib_mapa.dart';

const _montevideo = Coordenadas(lat: -34.9105, lon: -56.1505);
const _recursos = '/data/user/0/uy.colportores/files/mapa/lib-mapa-1.0.0';

ConfigVistaMapa _config({List<PuntoMapa> puntos = const []}) => ConfigVistaMapa(
  fuente: const FuenteMapa.offline('/data/montevideo.pmtiles'),
  camaraInicial: const CamaraMapa(centro: _montevideo, zoom: 16),
  zoomMinimo: 3,
  zoomMaximo: MapaAlta.zoomMaximo,
  interaccion: const InteraccionMapa(),
  dobleToqueZoom: true,
  fondo: ColoresMapa.fondo,
  colorNuevo: const Color(0xFF0B6E4F),
  puntos: puntos,
  agruparPuntos: true,
  precision: null,
  cercania: null,
  puntosTocables: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String estiloBase;

  setUpAll(() => estiloBase = estiloDeLibMapa());

  List<Map<String, dynamic>> capas(String estilo) => [
    for (final c in (jsonDecode(estilo) as Map<String, dynamic>)['layers'] as List<dynamic>)
      c as Map<String, dynamic>,
  ];

  group('el estilo, los glyphs y los sprites vienen del paquete', () {
    test('dado el bundle de la app, cuando se lee el estilo, entonces es el de lib-mapa', () async {
      expect(rutaEstiloBaseMapa, 'packages/colportores_mapa/assets/mapa/estilo/colportores.json');
      expect(await rootBundle.loadString(rutaEstiloBaseMapa), estiloBase);
      final metadatos =
          (jsonDecode(estiloBase) as Map<String, dynamic>)['metadata'] as Map<String, dynamic>;
      expect(metadatos['colportores:estilo'], '1.0.0');
    });

    test('dado el bundle de la app, cuando se listan los assets, entonces ya no queda la copia a '
        'mano de assets/mapa/ y los glyphs y sprites están en el paquete', () async {
      final assets = (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets();

      expect(assets.where((a) => a.startsWith('assets/mapa/')), isEmpty);
      const raiz = PreparadorRecursosMapa.raizAssets;
      for (final fuente in ['NotoSans-Regular', 'NotoSans-Medium', 'NotoSans-Italic']) {
        for (final rango in ['0-255', '256-511', '8192-8447']) {
          expect(assets, contains('${raiz}glyphs/$fuente/$rango.pbf'));
        }
      }
      expect(
        assets,
        containsAll([
          '${raiz}sprites/grayscale.json',
          '${raiz}sprites/grayscale.png',
          '${raiz}sprites/grayscale@2x.json',
          '${raiz}sprites/grayscale@2x.png',
        ]),
      );
    });

    test('la versión de la copia al almacenamiento interno cambia con el paquete: cada teléfono '
        'vuelve a copiar los glyphs y sprites de lib-mapa', () {
      expect(PreparadorRecursosMapa.versionRecursosMapa, 'lib-mapa-1.0.0');
      expect(PreparadorRecursosMapa.raizAssets, 'packages/colportores_mapa/assets/mapa/');
    });
  });

  group('los números de puerta de OSM (decisión P4, opción A)', () {
    test('el estilo del paquete los dibuja desde el zoom de calle del móvil', () {
      final numeros = capas(estiloBase).singleWhere((c) => c['id'] == 'address_label');
      expect(numeros['minzoom'], TokensMapa.zoomNumerosDePuerta);
      expect(TokensMapa.zoomNumerosDePuerta, MapaAlta.zoomCalle);
      expect(MapaAlta.zoomCalle, 16);
      expect((numeros['layout'] as Map<String, dynamic>)['text-field'], [
        'get',
        'addr_housenumber',
      ]);
    });

    test('dado el mapa principal o el alta, cuando se arma el estilo, entonces los números siguen '
        'y quedan por debajo de todas las capas de la app', () {
      final todas = capas(
        ConstructorEstiloMapa.construir(
          estiloBase: estiloBase,
          directorioRecursos: _recursos,
          config: _config(),
        ),
      );
      final ids = [for (final c in todas) c['id'] as String];
      final numeros = ids.indexOf('address_label');
      final primeraPropia = ids.indexWhere((id) => id.startsWith('colportores:'));

      expect(numeros, isNonNegative);
      expect(primeraPropia, greaterThan(numeros));
      expect(todas[numeros]['source'], ConstructorEstiloMapa.fuenteTiles);
    });

    test('dados los marcadores de la app, cuando pisan un número de OSM, entonces se ven igual y '
        'el número se esconde: ocupan su lugar', () {
      final todas = capas(
        ConstructorEstiloMapa.construir(
          estiloBase: estiloBase,
          directorioRecursos: _recursos,
          config: _config(),
        ),
      );

      expect(ConstructorEstiloMapa.capasQueOcupanLugar, [
        ConstructorEstiloMapa.capaEstado,
        ConstructorEstiloMapa.capaCercano,
        ConstructorEstiloMapa.capaCuadradoAro,
        ConstructorEstiloMapa.capaCuadrado,
      ]);
      for (final id in ConstructorEstiloMapa.capasQueOcupanLugar) {
        final layout = todas.singleWhere((c) => c['id'] == id)['layout'] as Map<String, dynamic>;
        expect(layout['icon-allow-overlap'], isTrue, reason: '$id siempre se dibuja');
        expect(layout['icon-ignore-placement'], isFalse, reason: '$id esconde lo que pisa');
      }
      // Los demás íconos propios siguen sin esconder a nadie.
      for (final c in todas) {
        final id = c['id'] as String;
        if (!id.startsWith('colportores:') || c['type'] != 'symbol') continue;
        if (ConstructorEstiloMapa.capasQueOcupanLugar.contains(id)) continue;
        final layout = c['layout'] as Map<String, dynamic>;
        if (layout.containsKey('icon-image')) {
          expect(layout['icon-ignore-placement'], isTrue, reason: id);
        }
      }
    });

    test(
      'dado el nombre de la zona propia debajo de los marcadores que ocupan su lugar, cuando una '
      'insignia lo pisa, entonces el nombre se sigue viendo (no queda solo el color, WCAG 1.4.1)',
      () {
        final todas = capas(
          ConstructorEstiloMapa.construir(
            estiloBase: estiloBase,
            directorioRecursos: _recursos,
            config: _config(),
          ),
        );
        final ids = [for (final c in todas) c['id'] as String];
        final rotulo = ids.indexOf(ConstructorEstiloMapa.capaZonasRotulo);
        expect(rotulo, isNonNegative);
        for (final id in ConstructorEstiloMapa.capasQueOcupanLugar) {
          expect(ids.indexOf(id), greaterThan(rotulo), reason: id);
        }
        final layout = todas[rotulo]['layout'] as Map<String, dynamic>;
        expect(layout['text-allow-overlap'], isTrue);
        expect(layout['text-ignore-placement'], isTrue);
      },
    );

    test('sin glyphs (no se pudieron copiar) no hay números de OSM: son texto', () {
      final ids = [
        for (final c in capas(
          ConstructorEstiloMapa.construirSinRecursos(estiloBase: estiloBase, config: _config()),
        ))
          c['id'],
      ];
      expect(ids, isNot(contains('address_label')));
    });
  });

  group('los colores y formas de los estados de casa salen de los tokens', () {
    test('cada variante del mapa es un estado de lib-mapa, con el mismo nombre', () {
      for (final v in VarianteMarcador.values) {
        expect(v.token.id, v.name);
      }
      expect({
        for (final e in EstadosDeCasa.todos) e.id,
      }, {for (final v in VarianteMarcador.values) v.name}..remove('edificio'));
      expect(VarianteMarcador.edificio.token, TokensMapa.edificioSinEstado);
    });

    test('el relleno, la tinta, el número, el borde y la forma son los del token', () {
      for (final v in VarianteMarcador.values) {
        expect(v.fondo, Color(v.token.relleno), reason: v.name);
        expect(v.tinta, Color(v.token.tinta), reason: v.name);
        expect(v.tintaNumero, Color(v.token.tintaNumero), reason: v.name);
        expect(v.borde, Color(v.token.borde ?? v.token.relleno), reason: v.name);
        expect(v.esCuadrada, v.token.forma == FormaDeMarcador.cuadrado, reason: v.name);
      }
    });

    test('el aspecto no cambia: los colores de siempre (vista 39 y vista 05)', () {
      const antes = {
        VarianteMarcador.sinVisita: (0xFFFFFFFF, 0xFF6B7688, 0xFF2A3A52, 0xFF6B7688, false),
        VarianteMarcador.noContesto: (0xFF6B7688, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF6B7688, false),
        VarianteMarcador.entrevistaAgendada: (
          0xFFE0B43C,
          0xFF0E1A2B,
          0xFF0E1A2B,
          0xFFE0B43C,
          false,
        ),
        VarianteMarcador.entrevistaHecha: (0xFF1F6E3A, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F6E3A, false),
        VarianteMarcador.ventaCompleta: (0xFF1F6E3A, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F6E3A, true),
        VarianteMarcador.cobranzaPendiente: (0xFF13407A, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF13407A, true),
        VarianteMarcador.entregaYPago: (0xFF13407A, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF13407A, true),
        VarianteMarcador.rechazo: (0xFFA8312A, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFA8312A, false),
        VarianteMarcador.edificio: (0xFFFFFFFF, 0xFF2A3A52, 0xFF2A3A52, 0xFF2A3A52, true),
      };
      for (final MapEntry(key: v, value: (fondo, tinta, numero, borde, cuadrada))
          in antes.entries) {
        expect(v.fondo.toARGB32(), fondo, reason: v.name);
        expect(v.tinta.toARGB32(), tinta, reason: v.name);
        expect(v.tintaNumero.toARGB32(), numero, reason: v.name);
        expect(v.borde.toARGB32(), borde, reason: v.name);
        expect(v.esCuadrada, cuadrada, reason: v.name);
      }
      // La forma del token coincide con la regla de siempre (cuadrado = estado de la venta).
      for (final e in EstadoCasa.values) {
        expect(VarianteMarcador.de(e).esCuadrada, e.esDeVenta, reason: e.name);
      }
    });

    test(
      'las franjas de «Entrega y pago» son las del token: 4 + 3 dp a 135° y la clara #4D76B1',
      () {
        final franjas = VarianteMarcador.entregaYPago.token.franjas!;
        expect(franjas.angulo, 135);
        expect(franjas.anchoOscura, 4);
        expect(franjas.anchoClara, 3);
        expect(franjas.clara, 0xFF4D76B1);
        for (final v in VarianteMarcador.values) {
          if (v == VarianteMarcador.entregaYPago) continue;
          expect(v.token.franjas, isNull, reason: v.name);
        }
      },
    );
  });

  group('las zonas usan la regla de contraste de la librería', () {
    test('la zona sin color es el valor del móvil del token (el azul de siempre)', () {
      expect(ColoresZona.porDefecto, Color(TokensMapa.zonaSinColor.movil));
      expect(ColoresZona.porDefecto.toARGB32(), 0xFF13407A);
      expect(ColoresZona.borde(null), ColoresZona.porDefecto);
    });

    test(
      'el borde de cualquier color es el de ContrasteMapa.bordeDeZona, con 3:1 sobre el mapa',
      () {
        expect(ColoresZona.contrasteMinimo, TokensMapa.contrasteBordes);
        expect(ColoresZona.fondoLiso, ColoresMapa.fondo);
        for (final hex in ['#FFD966', '#9FD3FF', '#FFFFFF', '#13407A', '#A98330', '#000000']) {
          final argb = 0xFF000000 | int.parse(hex.substring(1), radix: 16);
          final borde = ColoresZona.borde(hex);
          expect(borde.toARGB32(), ContrasteMapa.bordeDeZona(argb), reason: hex);
          expect(
            ColoresZona.contraste(borde),
            greaterThanOrEqualTo(TokensMapa.contrasteBordes),
            reason: hex,
          );
        }
        for (final color in TokensMapa.paletaZonas) {
          final hex = '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
          expect(ColoresZona.borde(hex).toARGB32(), ContrasteMapa.bordeDeZona(color), reason: hex);
        }
      },
    );
  });

  group('zooms y atribución desde los tokens', () {
    test('el zoom máximo es el 19 del token en el alta, el mapa principal y Modificar', () {
      expect(MapaAlta.zoomMaximo, TokensMapa.zoomMaximo);
      expect(MapaAlta.zoomMaximo, 19);
      expect(
        const MapaBase(
          fuente: FuenteMapa.sinTiles(),
          camaraInicial: CamaraMapa(centro: _montevideo, zoom: 16),
        ).zoomMaximo,
        TokensMapa.zoomMaximo,
      );
    });

    test('la atribución es la corta del token', () {
      expect(TokensMapa.atribucionCorto, '© OpenStreetMap');
    });
  });
}
