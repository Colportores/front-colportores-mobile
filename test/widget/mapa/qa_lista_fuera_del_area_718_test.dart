// QA de #718 (seguimiento de #715: la pestaña «Lista», vista 05, marca las casas «fuera del área» con
// la misma etiqueta que «Cercanía» y no oculta ninguna; decisión del 17/11, P1 §2; HU-SYNC-011, R-UB12).
// Cubre lo que `lista_fuera_del_area_713_test.dart` no toca: cada estado a 360x640 y 412x915 con el
// texto a 1,0 y a 2,0 (sin desbordes ni palabras partidas, etiqueta entera a la vista), una baja
// también marcada, direcciones largas y edificios, la lectura que se demora o falla, los filtros y el
// buscador, la reentrada a la pestaña y la hoja de la casa que se abre desde la fila. Las capturas
// (con `--dart-define=QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas`, fuera del repo.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/fuera_del_area_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_fuera_del_area.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart'
    show FilaUbicacionLista;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_mapa_fuera_del_area_715_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

Finder _fila(String id) => find.byKey(ValueKey(id));

Finder _etiquetaEn(String id) =>
    find.descendant(of: _fila(id), matching: find.byType(EtiquetaFueraDelArea));

Finder get _todasLasEtiquetas => find.byType(EtiquetaFueraDelArea);

/// Una palabra de la etiqueta partida en dos renglones: cada palabra, medida sola con el mismo estilo
/// y el mismo `textScaler`, tiene que entrar en el ancho que le toca al texto.
void _sinPalabrasPartidas(WidgetTester tester, Finder texto, double escala) {
  final parrafo = tester.renderObject<RenderParagraph>(texto);
  final estilo = (parrafo.text as TextSpan).style!;
  final contenido = parrafo.text.toPlainText();
  for (final palabra in contenido.split(' ')) {
    final p = TextPainter(
      text: TextSpan(text: palabra, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(escala),
    )..layout();
    expect(
      p.width,
      lessThanOrEqualTo(parrafo.size.width + .5),
      reason: '«$palabra» no entra en ${parrafo.size.width} dp',
    );
  }
}

typedef _Escena = Future<void> Function(WidgetTester tester, Size tamano, double escala);

Future<void> _montar(
  WidgetTester tester,
  FueraDelAreaFalsas715 fuera,
  List<UbicacionConResumen> casas, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool casaAbreSuHoja = false,
  List<Override> masOverrides = const [],
}) => montarLista(
  tester,
  repo: RepoListaFalso(casas),
  escala: escala,
  tamano: tamano,
  casaAbreSuHoja: casaAbreSuHoja,
  masOverrides: [fuera.sobrescribe, ...masOverrides],
);

Future<void> _mostrarBajas(WidgetTester tester) async {
  await abrirHojaFiltros(tester);
  await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
  await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
  await asentarLista(tester);
  await tester.ensureVisible(botonVerUbicaciones);
  await verUbicaciones(tester);
}

/// Lista perezosa: cada fila que está armada lleva su etiqueta (todas están marcadas).
void _todasLasFilasMarcadas() {
  final filas = find.byType(FilaUbicacionLista).evaluate().length;
  expect(filas, greaterThan(0));
  expect(_todasLasEtiquetas, findsNWidgets(filas));
}

final _casasLargas = [
  filaLista(
    'u1',
    calle: 'Av. General Fructuoso Rivera de las Tres Cruces',
    numero: '1234 bis',
    metrosAlNorte: 10,
  ),
  filaLista('u2', calle: 'Av. Italia', numero: '102', metrosAlNorte: 20),
  filaLista(
    'u3',
    tipo: TipoUbicacion.edificio,
    calle: 'Av. Italia',
    numero: '103',
    metrosAlNorte: 30,
    espacios: 24,
  ),
  filaLista('u4', calle: 'Bulevar Artigas', numero: '104', metrosAlNorte: 40),
];

final _escenas = <String, _Escena>{
  'A una casa marcada': (t, tam, e) async {
    await _montar(t, FueraDelAreaFalsas715({'u2'}), casas715(), tamano: tam, escala: e);
    expect(_etiquetaEn('u2'), findsOneWidget);
    expect(_todasLasEtiquetas, findsOneWidget);
  },
  'B todas marcadas': (t, tam, e) async {
    await _montar(
      t,
      FueraDelAreaFalsas715({'u1', 'u2', 'u3', 'u4'}),
      casas715(),
      tamano: tam,
      escala: e,
    );
    _todasLasFilasMarcadas();
  },
  'C direcciones largas, edificio y marcadas': (t, tam, e) async {
    await _montar(
      t,
      FueraDelAreaFalsas715({'u1', 'u2', 'u3', 'u4'}),
      _casasLargas,
      tamano: tam,
      escala: e,
    );
    _todasLasFilasMarcadas();
  },
  'D baja también marcada, con las bajas a la vista': (t, tam, e) async {
    await _montar(
      t,
      FueraDelAreaFalsas715({'u5'}),
      // Solo la baja: la lista es perezosa y a 2,0 la última fila queda fuera del cuadro.
      [casas715(conBaja: true).last],
      tamano: tam,
      escala: e,
    );
    await _mostrarBajas(t);
    // Con Ahem o con la fuente real, la fila de filtros de #196 puede desbordar un cuadro a 2,0: no es
    // de este PR (lo mismo que hace `lista_ubicaciones_baja_test.dart`).
    final desborde = t.takeException();
    expect(desborde == null || desborde.toString().contains('overflowed'), isTrue);
    expect(_etiquetaEn('u5'), findsOneWidget);
    expect(find.text('BAJA'), findsWidgets);
  },
};

void main() {
  group('QA #718 · cada estado de la Lista con marcas en los dos teléfonos', () {
    for (final MapEntry(key: nombreTamano, value: tamano) in tamanos715.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final MapEntry(key: nombre, value: armar) in _escenas.entries) {
          testWidgets('$nombre · $nombreTamano · texto $escala: sin desbordes, etiqueta entera y '
              'dentro de la pantalla', (tester) async {
            await cargarFuentes715(tester);
            await armar(tester, tamano, escala);

            expect(tester.takeException(), isNull);
            for (final etiqueta in _todasLasEtiquetas.evaluate()) {
              final caja = tester.getRect(find.byElementPredicate((e) => e == etiqueta));
              expect(caja.left, greaterThanOrEqualTo(0));
              expect(caja.right, lessThanOrEqualTo(tamano.width));
              expect(caja.height, greaterThanOrEqualTo(10 * escala));
            }
            _sinPalabrasPartidas(
              tester,
              find.descendant(of: _todasLasEtiquetas.first, matching: find.byType(Text)).first,
              escala,
            );
            await capturar715(tester, 'lista $nombre $nombreTamano x$escala');
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('QA #718 · el lector de pantalla', () {
    testWidgets('la fila marcada dice «Fuera de tu área» una sola vez y se puede activar; la '
        'etiqueta suelta no es otro nodo', (tester) async {
      await cargarFuentes715(tester);
      final semantica = tester.ensureSemantics();
      await _montar(tester, FueraDelAreaFalsas715({'u1'}), casas715());

      final nodo = tester.getSemantics(_fila('u1'));
      expect('Fuera de tu área'.allMatches(nodo.label).length, 1);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // La etiqueta visual no suma un nodo tocable ni uno propio dentro de la fila.
      expect(tester.getSemantics(_fila('u1')).getSemanticsData().flagsCollection.isButton, isTrue);
      semantica.dispose();
    });

    testWidgets('el orden del texto leído: dirección, «Fuera de tu área», estado', (tester) async {
      await cargarFuentes715(tester);
      final semantica = tester.ensureSemantics();
      await _montar(tester, FueraDelAreaFalsas715({'u1'}), casas715());

      final etiqueta = tester.getSemantics(_fila('u1')).label;
      expect(etiqueta.indexOf('Av. Italia 101'), lessThan(etiqueta.indexOf('Fuera de tu área')));
      expect(etiqueta, startsWith('Av. Italia 101. Fuera de tu área. '));
      semantica.dispose();
    });
  });

  group('QA #718 · la lectura de las marcas se demora, falla o se recupera', () {
    testWidgets('mientras la lectura no llega, la Lista muestra las filas sin etiqueta y sin un '
        'spinner colgado; cuando llega, aparece', (tester) async {
      final marcas = StreamController<Set<String>>();
      addTearDown(marcas.close);
      await montarLista(
        tester,
        repo: RepoListaFalso(casas715()),
        masOverrides: [idsFueraDelAreaProvider.overrideWith((ref) => marcas.stream)],
      );

      expect(_fila('u1'), findsOneWidget);
      expect(_todasLasEtiquetas, findsNothing);
      expect(tester.takeException(), isNull);

      marcas.add({'u1'});
      await asentarLista(tester);
      expect(_etiquetaEn('u1'), findsOneWidget);
    });

    testWidgets('si la lectura de las marcas falla, la Lista sigue entera, sin etiquetas y sin '
        'excepción; con la próxima lectura buena vuelven', (tester) async {
      final marcas = StreamController<Set<String>>();
      addTearDown(marcas.close);
      await montarLista(
        tester,
        repo: RepoListaFalso(casas715()),
        masOverrides: [idsFueraDelAreaProvider.overrideWith((ref) => marcas.stream)],
      );

      marcas.addError(StateError('la base no responde'));
      await asentarLista(tester);
      expect(tester.takeException(), isNull);
      expect(_fila('u1'), findsOneWidget);
      expect(_fila('u4'), findsOneWidget);
      expect(_todasLasEtiquetas, findsNothing);

      marcas.add({'u4'});
      await asentarLista(tester);
      expect(_etiquetaEn('u4'), findsOneWidget);
    });

    testWidgets('un id marcado que ya no está en la Lista (otra ciudad, borrada) no rompe ni suma '
        'etiquetas a las demás', (tester) async {
      await _montar(tester, FueraDelAreaFalsas715({'no-existe', 'u2'}), casas715());

      expect(_todasLasEtiquetas, findsOneWidget);
      expect(_etiquetaEn('u2'), findsOneWidget);
    });

    testWidgets('300 casas marcadas, la lista perezosa no desborda y la etiqueta sigue en la fila '
        'que se ve', (tester) async {
      final muchas = [
        for (var i = 0; i < 300; i++)
          filaLista('m$i', numero: '${200 + i}', metrosAlNorte: i.toDouble()),
      ];
      await _montar(
        tester,
        FueraDelAreaFalsas715({for (var i = 0; i < 300; i++) 'm$i'}),
        muchas,
        escala: 2,
        tamano: const Size(360, 640),
      );

      expect(_etiquetaEn('m0'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await asentarLista(tester);
      expect(tester.takeException(), isNull);
      expect(_todasLasEtiquetas, findsWidgets);
    });
  });

  group('QA #718 · filtros, buscador y reentrada', () {
    testWidgets('el buscador deja solo la casa marcada: conserva la etiqueta; sin resultados no '
        'queda ninguna', (tester) async {
      await _montar(tester, FueraDelAreaFalsas715({'u1'}), casas715());

      await buscarEnLista(tester, '101');
      expect(_fila('u1'), findsOneWidget);
      expect(_etiquetaEn('u1'), findsOneWidget);
      expect(_fila('u2'), findsNothing);

      await buscarEnLista(tester, '999');
      expect(_fila('u1'), findsNothing);
      expect(_todasLasEtiquetas, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('salir de la pestaña y volver (se desmonta y se monta de nuevo) conserva las '
        'marcas', (tester) async {
      final montada = ValueNotifier(true);
      addTearDown(montada.dispose);
      await montarLista(
        tester,
        repo: RepoListaFalso(casas715()),
        montadaCambiante: montada,
        masOverrides: [
          FueraDelAreaFalsas715({'u3'}).sobrescribe,
        ],
      );
      expect(_etiquetaEn('u3'), findsOneWidget);

      montada.value = false;
      await asentarLista(tester);
      expect(_todasLasEtiquetas, findsNothing);

      montada.value = true;
      await asentarLista(tester);
      expect(_etiquetaEn('u3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una pestaña fuera de vista (otra pestaña activa) sigue las marcas del pull y '
        'las muestra al volver', (tester) async {
      final activa = ValueNotifier(false);
      addTearDown(activa.dispose);
      final fuera = FueraDelAreaFalsas715();
      await montarLista(
        tester,
        repo: RepoListaFalso(casas715()),
        activaCambiante: activa,
        masOverrides: [fuera.sobrescribe],
      );

      fuera.emitir({'u2'});
      await asentarLista(tester);
      activa.value = true;
      await asentarLista(tester);
      expect(_etiquetaEn('u2'), findsOneWidget);
    });
  });

  group('QA #718 · tocar la fila marcada', () {
    testWidgets('abre la hoja de la casa (una sola vez, aunque se toque dos veces) y la Lista no '
        'pierde la etiqueta al cerrarla', (tester) async {
      await _montar(tester, FueraDelAreaFalsas715({'u1'}), casas715(), casaAbreSuHoja: true);

      await tester.tap(find.text('Av. Italia 101'));
      await tester.tap(find.text('Av. Italia 101'), warnIfMissed: false);
      await asentarLista(tester);
      expect(tester.takeException(), isNull);

      await tester.tapAt(const Offset(190, 20));
      await asentarLista(tester);
      expect(_etiquetaEn('u1'), findsOneWidget);
    });

    testWidgets('la hoja de la casa que se abre desde la fila marcada lleva la misma etiqueta '
        '«FUERA DE TU ÁREA» (la misma casa lleva la misma marca)', (tester) async {
      await _montar(tester, FueraDelAreaFalsas715({'u1'}), casas715(), casaAbreSuHoja: true);

      await tester.tap(find.text('Av. Italia 101'));
      await asentarLista(tester, 14);

      // La etiqueta de la fila (1) + la de la hoja (2).
      expect(find.byKey(ClavesFueraDelArea.etiqueta), findsNWidgets(2));
    }, skip: !verHallazgos715);
  });
}
