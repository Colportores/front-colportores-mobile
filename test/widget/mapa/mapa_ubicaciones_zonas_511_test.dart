// HU-UBI-003 (#511, #654): las zonas del colportor sobre el mapa de ubicaciones, con el estilo de
// zona del panel (vista 24) y el retoque del teléfono. Desde el #654 (decisión de Cristian, 04/11) el
// mapa dibuja y nombra solo las zonas propias: las de otros colportores de la misma campaña y
// ciudad llegan a la réplica (el cálculo de la zona de cada punto las necesita) pero no al dibujo.
// No hay canvas del teléfono (decisión de Cristian, 27/10, «Zonas mapa»): los casos son los del
// issue y los límites de cada flujo. La vista nativa es la falsa del arnés: se mira lo que el mapa
// le pide dibujar (`config.zonas`) y lo que oye el lector de pantalla.
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/zonas_del_mapa_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

const _mapa = 'Mapa de ubicaciones';

/// Dos casas en el mismo punto, a 80 m del GPS: el mapa las junta en un grupo.
List<UbicacionConResumen> _casasAgrupadas() => [
  filaLista('par-1', numero: '1', metrosAlNorte: 80),
  filaLista('par-2', numero: '2', metrosAlNorte: 80),
];

List<ZonaMapa> _dibujadas(FabricaMapaFalsa mapa) => mapa.config!.zonas;

Map<String, bool> _propias(FabricaMapaFalsa mapa) => {
  for (final z in _dibujadas(mapa)) z.id: z.propia,
};

Future<MontajeMapaUbicaciones> _montar(
  WidgetTester tester,
  ZonasDelMapaFalsas zonas, {
  List<UbicacionConResumen> casas = const [],
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool activa = true,
}) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso(casas),
  otrosOverrides: [zonas.sobrescribe],
  escala: escala,
  tamano: tamano,
  activa: activa,
);

void main() {
  group('sin zonas: no se dibuja nada ni aparece un aviso vacío', () {
    testWidgets('dado un teléfono sin zonas, cuando se abre el mapa, entonces el mapa no recibe '
        'ninguna y el lector oye solo «Mapa de ubicaciones»', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas();
      final m = await _montar(tester, zonas, casas: _casasAgrupadas());

      expect(_dibujadas(m.mapa), isEmpty);
      expect(find.bySemanticsLabel(_mapa), findsOneWidget);
      expect(find.textContaining('zona', findRichText: true), findsNothing);
      expect(find.textContaining('Zona', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    testWidgets('dada una campaña que todavía no bajó zonas, cuando el pull las trae, entonces '
        'aparecen sin tocar nada', (tester) async {
      final zonas = ZonasDelMapaFalsas();
      final m = await _montar(tester, zonas);
      expect(_dibujadas(m.mapa), isEmpty);

      zonas.emitir([zonaCuadrada('a', propia: true)]);
      await asentarLista(tester);

      expect(_propias(m.mapa), {'a': true});
    });
  });

  group('una zona', () {
    testWidgets('dada solo la zona propia, entonces se dibuja resaltada, con su nombre, y el '
        'lector oye cuál es', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', nombre: 'Cerro Norte', propia: true, color: '#A8312A'),
      ]);
      final m = await _montar(tester, zonas);

      final zona = _dibujadas(m.mapa).single;
      expect(zona.propia, isTrue);
      expect(zona.rotulo, 'Tu zona · Cerro Norte');
      expect(zona.puntoRotulo, isNotNull);
      expect(zona.color, const Color(0xFFA8312A));
      expect(find.bySemanticsLabel('$_mapa. Tu zona: Cerro Norte.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dado un colportor sin zona asignada (la ciudad tiene zonas de otros), entonces no '
        'se dibuja ninguna y el lector oye solo «Mapa de ubicaciones»', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', nombre: 'La Teja'),
        zonaCuadrada('b', nombre: 'Belvedere', lon: -56.1),
      ]);
      final m = await _montar(tester, zonas, casas: _casasAgrupadas());

      expect(_dibujadas(m.mapa), isEmpty);
      expect(find.bySemanticsLabel(_mapa), findsOneWidget);
      expect(find.textContaining('zona', findRichText: true), findsNothing);
      expect(find.byType(MapaBase), findsOneWidget);
      expect(botonNueva, findsOneWidget);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    testWidgets('dada una zona sin color o con uno claro, entonces el borde sale con contraste de '
        'al menos 3:1', (tester) async {
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('sin', propia: true, color: null),
        zonaCuadrada('amarillo', propia: true, color: '#FFFF00', lon: -56.10),
      ]);
      final m = await _montar(tester, zonas);

      for (final z in _dibujadas(m.mapa)) {
        expect(ColoresZona.contraste(z.color), greaterThanOrEqualTo(3), reason: z.id);
      }
      // #695: la que el backend guardó sin color sale gris (el token de lib-mapa), no azul.
      final sin = _dibujadas(m.mapa).singleWhere((z) => z.id == 'sin');
      expect(sin.color, ColoresZona.borde(null));
      expect(sin.color.toARGB32(), isNot(0xFF13407A));
    });
  });

  group('varias zonas, superpuestas y anidadas', () {
    testWidgets('dadas tres zonas que se pisan, entonces al mapa llega solo la propia y el lector '
        'no menciona las otras', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', nombre: 'Centro', lado: .06),
        zonaCuadrada('b', nombre: 'Cordón', propia: true, lat: -34.87, lon: -56.17, lado: .06),
        zonaCuadrada('c', nombre: 'Pocitos', lat: -34.88, lon: -56.15, lado: .06),
      ]);
      final m = await _montar(tester, zonas);

      expect(_propias(m.mapa), {'b': true});
      expect(find.bySemanticsLabel('$_mapa. Tu zona: Cordón.'), findsOneWidget);
      expect(find.textContaining('Centro', findRichText: true), findsNothing);
      semantica.dispose();
    });

    testWidgets('dada la zona propia adentro de otra, entonces llega solo la propia con su nombre '
        'y su lugar', (tester) async {
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('grande', nombre: 'Ciudad vieja', lado: .1),
        zonaCuadrada('chica', nombre: 'Plaza', propia: true, lat: -34.87, lon: -56.17, lado: .01),
      ]);
      final m = await _montar(tester, zonas);

      final zona = _dibujadas(m.mapa).single;
      expect(zona.id, 'chica');
      expect(zona.rotulo, 'Tu zona · Plaza');
      expect(zona.puntoRotulo, isNotNull);
    });

    testWidgets('dados dos colportores en la misma campaña y ciudad, cada uno dibuja solo la '
        'suya', (tester) async {
      // La réplica es la misma para los dos: trae las zonas de la ciudad. `propia` depende de la
      // inscripción de cada uno (el repositorio la calcula; acá lo hace el falso).
      final ana = ZonasDelMapaFalsas([
        zonaCuadrada('zona-ana', nombre: 'Cerro Norte', propia: true),
        zonaCuadrada('zona-beto', nombre: 'La Teja', lon: -56.1),
      ]);
      final beto = ZonasDelMapaFalsas([
        zonaCuadrada('zona-ana', nombre: 'Cerro Norte'),
        zonaCuadrada('zona-beto', nombre: 'La Teja', propia: true, lon: -56.1),
      ]);

      final deAna = await _montar(tester, ana);
      expect(_dibujadas(deAna.mapa).map((z) => z.id), ['zona-ana']);
      expect(_dibujadas(deAna.mapa).single.rotulo, 'Tu zona · Cerro Norte');

      final deBeto = await _montar(tester, beto);
      expect(_dibujadas(deBeto.mapa).map((z) => z.id), ['zona-beto']);
      expect(_dibujadas(deBeto.mapa).single.rotulo, 'Tu zona · La Teja');
    });

    testWidgets('dadas dos zonas propias (el colportor está en dos campañas), entonces las dos se '
        'resaltan y el lector las nombra a las dos', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', nombre: 'Centro', propia: true),
        zonaCuadrada('b', nombre: 'Cordón', propia: true, lon: -56.1),
      ]);
      final m = await _montar(tester, zonas);

      expect(_propias(m.mapa), {'a': true, 'b': true});
      expect(find.bySemanticsLabel('$_mapa. Tu zona: Centro y Cordón.'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('junto con las casas agrupadas', () {
    testWidgets('dadas casas que se agrupan, cuando hay zonas, entonces las casas llegan al mapa '
        'igual que sin zonas y se siguen agrupando', (tester) async {
      final sin = await _montar(tester, ZonasDelMapaFalsas(), casas: _casasAgrupadas());
      final puntosSinZonas = sin.mapa.config!.puntos;
      expect(sin.mapa.config!.agruparPuntos, isTrue);

      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true, lat: -34.9, lon: -56.2)]);
      final con = await _montar(tester, zonas, casas: _casasAgrupadas());

      expect(con.mapa.config!.puntos, puntosSinZonas);
      expect(con.mapa.config!.agruparPuntos, isTrue);
      expect(_dibujadas(con.mapa), hasLength(1));
    });

    testWidgets('dado un toque en una casa que está dentro de una zona, entonces abre su vista '
        'previa: la zona no se queda con el toque', (tester) async {
      // La zona rodea a las casas (a ~80 m del GPS).
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', propia: true, lat: -34.90, lon: -56.15, lado: .05),
      ]);
      final m = await _montar(tester, zonas, casas: [filaLista('casa', metrosAlNorte: 80)]);
      expect(vistaPrevia, findsNothing);

      m.mapa.tocarPunto('casa');
      await asentarLista(tester, 6);

      expect(vistaPrevia, findsOneWidget);
    });

    testWidgets('dado un toque en el mapa sobre una zona sin casa, entonces es un toque al mapa '
        'vacío: no abre nada ni cambia la selección', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true)]);
      final m = await _montar(tester, zonas, casas: [filaLista('casa', metrosAlNorte: 80)]);

      m.mapa.tocar(const Coordenadas(lat: -34.88, lon: -56.18));
      await asentarLista(tester, 6);

      expect(vistaPrevia, findsNothing);
      expect(m.altas, isEmpty);
      expect(_dibujadas(m.mapa), hasLength(1));
    });

    testWidgets('dado el dedo mantenido sobre una zona, entonces abre el alta con ese punto como '
        'siempre', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true)]);
      final m = await _montar(tester, zonas);
      const punto = Coordenadas(lat: -34.88, lon: -56.18);

      m.mapa.tocarLargo(punto);
      await asentarLista(tester, 6);

      expect(m.altas, [punto]);
    });
  });

  group('al día con el pull', () {
    testWidgets('dado un pull que cambia la zona propia, entonces el mapa dibuja la nueva y el '
        'lector lo dice', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', nombre: 'Centro', propia: true),
        zonaCuadrada('b', nombre: 'Cordón', lon: -56.1),
      ]);
      final m = await _montar(tester, zonas);
      expect(_propias(m.mapa), {'a': true});

      zonas.emitir([
        zonaCuadrada('a', nombre: 'Centro'),
        zonaCuadrada('b', nombre: 'Cordón', propia: true, lon: -56.1),
      ]);
      await asentarLista(tester);

      expect(_propias(m.mapa), {'b': true});
      expect(find.bySemanticsLabel('$_mapa. Tu zona: Cordón.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dado un pull que le quita la zona asignada (las ajenas siguen en la réplica), '
        'entonces el mapa queda sin zonas y sin texto de más', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', propia: true),
        zonaCuadrada('b', lon: -56.1),
      ]);
      final m = await _montar(tester, zonas);
      expect(_dibujadas(m.mapa), hasLength(1));

      zonas.emitir([zonaCuadrada('a'), zonaCuadrada('b', lon: -56.1)]);
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), isEmpty);
      expect(find.bySemanticsLabel(_mapa), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dado un pull que le saca todas las zonas (lo sacaron de la campaña), entonces '
        'el mapa queda sin zonas y sin texto de más', (tester) async {
      final semantica = tester.ensureSemantics();
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true)]);
      final m = await _montar(tester, zonas);
      expect(_dibujadas(m.mapa), hasLength(1));

      zonas.emitir(const []);
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), isEmpty);
      expect(find.bySemanticsLabel(_mapa), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dados dos pulls seguidos antes de que el mapa se redibuje, entonces queda el '
        'último, sin pisarse ni perder ninguno', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a')]);
      final m = await _montar(tester, zonas);
      expect(_dibujadas(m.mapa), isEmpty);

      zonas
        ..emitir([zonaCuadrada('a'), zonaCuadrada('b', propia: true)])
        ..emitir([zonaCuadrada('b', propia: true), zonaCuadrada('c', lon: -56.1)]);
      await asentarLista(tester);

      expect(_propias(m.mapa), {'b': true});
    });
  });

  group('falla a mitad de la acción', () {
    testWidgets('dada una lectura de zonas que falla al abrir, entonces el mapa anda igual, sin '
        'zonas y sin error a la vista', (tester) async {
      final zonas = ZonasDelMapaFalsas()..fallaAlSuscribir = 'sin base';
      final m = await _montar(tester, zonas, casas: [filaLista('casa', metrosAlNorte: 80)]);

      expect(_dibujadas(m.mapa), isEmpty);
      expect(hayPunto(m.mapa, 'casa'), isTrue);
      expect(find.textContaining('No pudimos'), findsNothing);
      expect(tester.takeException(), isNull);

      m.mapa.tocarPunto('casa');
      await asentarLista(tester, 6);
      expect(vistaPrevia, findsOneWidget);
    });

    testWidgets('dada una falla después de haber leído zonas, entonces siguen las que ya había y '
        'cuando vuelve a leer se actualizan', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true)]);
      final m = await _montar(tester, zonas);

      zonas.fallar();
      await asentarLista(tester);
      expect(_propias(m.mapa), {'a': true});
      expect(tester.takeException(), isNull);

      zonas.emitir([zonaCuadrada('b', propia: true), zonaCuadrada('c', lon: -56.1)]);
      await asentarLista(tester);
      expect(_propias(m.mapa), {'b': true});
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('dado cambiar de pestaña y volver, entonces las zonas siguen y no se vuelven a '
        'leer', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true)]);
      final m = await _montar(tester, zonas);
      expect(zonas.suscripciones, 1);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);

      expect(_propias(m.mapa), {'a': true});
      expect(zonas.suscripciones, 1);
    });

    testWidgets('dada la pestaña que todavía no se abrió, entonces no lee zonas hasta que se '
        'abre', (tester) async {
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', propia: true)]);
      final m = await _montar(tester, zonas, activa: false);
      expect(zonas.suscripciones, 0);

      m.activa.value = true;
      await asentarLista(tester);

      expect(zonas.pedidos, ['col-1']);
      expect(_propias(m.mapa), {'a': true});
    });
  });

  group('datos límite', () {
    testWidgets('dadas 300 zonas de la ciudad, entonces al mapa llega solo la propia, sin '
        'error', (tester) async {
      final zonas = ZonasDelMapaFalsas([
        for (var i = 0; i < 300; i++)
          zonaCuadrada('z-$i', propia: i == 7, lon: -56.5 + i * .002, lado: .01),
      ]);
      final m = await _montar(tester, zonas, casas: _casasAgrupadas());

      expect(_dibujadas(m.mapa).map((z) => z.id), ['z-7']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado un nombre larguísimo, entonces el nombre viaja entero al mapa y al lector '
        'sin desbordar nada', (tester) async {
      final semantica = tester.ensureSemantics();
      final nombre = 'Barrio ${'muy ' * 40}largo';
      final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', nombre: nombre, propia: true)]);
      final m = await _montar(tester, zonas);

      expect(_dibujadas(m.mapa).single.rotulo, 'Tu zona · $nombre');
      expect(find.bySemanticsLabel('$_mapa. Tu zona: $nombre.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    testWidgets('dada una zona sin forma (sin área), entonces se dibuja sin nombre y el mapa no '
        'se cae', (tester) async {
      final plana = zonaCuadrada('plana', propia: true, lado: 0);
      final zonas = ZonasDelMapaFalsas([plana, zonaCuadrada('b', lon: -56.1)]);
      final m = await _montar(tester, zonas);

      expect(_dibujadas(m.mapa), hasLength(1));
      expect(_dibujadas(m.mapa).single.puntoRotulo, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado el texto del sistema al 200 % en un teléfono chico (320×568), entonces el '
        'mapa con zonas se arma sin desbordar y conserva sus botones', (tester) async {
      final zonas = ZonasDelMapaFalsas([
        zonaCuadrada('a', nombre: 'Cerro Norte', propia: true),
        zonaCuadrada('b', nombre: 'La Teja', lon: -56.1),
      ]);
      final m = await _montar(
        tester,
        zonas,
        casas: _casasAgrupadas(),
        escala: 2,
        tamano: const Size(320, 568),
      );

      expect(_dibujadas(m.mapa).map((z) => z.id), ['a']);
      expect(find.byType(MapaBase), findsOneWidget);
      expect(botonNueva, findsOneWidget);
      expect(botonMiUbicacion, findsOneWidget);
      expect(chipReferencias, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
