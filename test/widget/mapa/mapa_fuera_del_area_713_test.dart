// Las casas «fuera del área» en el mapa (#713; HU-SYNC-011, R-UB12): el motor las marca y nunca las
// borra. El mapa las distingue con un aro ámbar (y la etiqueta «FUERA DE TU ÁREA» en «Cercanía» y en
// su hoja); en «Referencias» el colportor elige verlas u ocultarlas. Ocultas no se dibujan ni están en
// «Cercanía» —la elegida sí— y el mapa dice cuántas hay, con «Ver». Solo visual: nada se borra.
// Ningún artboard lo dibuja (criterio del 10/11): los casos son los del issue y los límites de cada
// flujo. La vista nativa es la falsa del arnés: se mira lo que el mapa le pide dibujar.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/fuera_del_area_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_fuera_del_area.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_hojas_teclado_324_arnes.dart' show escucharAnuncios;
import 'mapa_ubicaciones_arnes.dart';

/// Lo que el motor marcó fuera del área, como lo da `DriftLocalStore.observarFueraDelArea`: emite lo
/// que hay al suscribirse y cada cambio (un pull).
final class _FueraDelAreaFalsas {
  _FueraDelAreaFalsas([this._actual = const {}]);

  Set<String> _actual;
  final _cambios = StreamController<Set<String>>.broadcast();

  /// Si no es `null`, la lectura falla con esto.
  Object? falla;

  void emitir(Set<String> ids) {
    _actual = ids;
    _cambios.add(ids);
  }

  Stream<Set<String>> _leer() async* {
    final error = falla;
    if (error != null) throw error;
    yield _actual;
    yield* _cambios.stream;
  }

  Override get sobrescribe => idsFueraDelAreaProvider.overrideWith((ref) => _leer());
}

/// u1 y u3 fuera del área; u2 y u4, en el área. Lejos del GPS (ninguna «cerca tuyo»).
List<UbicacionConResumen> _casas() => [
  filaLista('u1', numero: '101', metrosAlNorte: 300),
  filaLista('u2', numero: '102', metrosAlNorte: 320),
  filaLista('u3', numero: '103', metrosAlNorte: 340),
  filaLista('u4', numero: '104', metrosAlNorte: 360),
];

Future<MontajeMapaUbicaciones> _montar(
  WidgetTester tester,
  _FueraDelAreaFalsas fuera, {
  List<UbicacionConResumen>? casas,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso(casas ?? _casas()),
  otrosOverrides: [fuera.sobrescribe],
  escala: escala,
  tamano: tamano,
);

final _avisoMapa = find.byKey(ClavesFueraDelArea.avisoMapa);
final _avisoHoja = find.byKey(ClavesFueraDelArea.avisoHoja);
final _interruptor = find.byKey(ClavesFueraDelArea.interruptor);

Set<String> _dibujadas(FabricaMapaFalsa mapa) => {
  for (final p in mapa.config!.puntos)
    if (p.id != 'gps') p.id,
};

Set<String> _conAro(FabricaMapaFalsa mapa) => {
  for (final p in mapa.config!.puntos)
    if (p.fueraDelArea) p.id,
};

Future<void> _abrirReferencias(WidgetTester tester) async {
  await tester.tap(chipReferencias);
  await asentarLista(tester, 12);
}

Future<void> _cerrarReferencias(WidgetTester tester) async {
  // Con la fila y el interruptor de más, «Cerrar» puede quedar debajo del borde: la leyenda se desliza.
  await tester.ensureVisible(find.byKey(ClavesMapaUbicaciones.cerrarReferencias));
  await asentarLista(tester, 4);
  await tester.tap(find.byKey(ClavesMapaUbicaciones.cerrarReferencias));
  await asentarLista(tester, 12);
}

/// Oculta las casas fuera del área desde «Referencias», como lo hace el colportor.
Future<void> _ocultarDesdeReferencias(WidgetTester tester) async {
  await _abrirReferencias(tester);
  await tester.ensureVisible(_interruptor);
  await tester.tap(_interruptor);
  await asentarLista(tester, 4);
  await _cerrarReferencias(tester);
}

void main() {
  group('la marca', () {
    testWidgets('dadas dos casas fuera del área, cuando se abre el mapa, entonces solo esas llevan '
        'el aro, se ven todas y el lector oye cuántas hay', (tester) async {
      final semantica = tester.ensureSemantics();
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1', 'u3'}));

      expect(_dibujadas(m.mapa), {'u1', 'u2', 'u3', 'u4'});
      expect(_conAro(m.mapa), {'u1', 'u3'});
      expect(
        find.bySemanticsLabel(RegExp('2 casas fuera de tu área, con un aro ámbar')),
        findsOneWidget,
      );
      expect(_avisoMapa, findsNothing, reason: 'nada está oculto');
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    testWidgets('en «Cercanía» la fila lleva «FUERA DE TU ÁREA» y el lector lo dice', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await tocarAsa(tester);

      expect(
        find.descendant(of: fila('u1'), matching: find.text('FUERA DE TU ÁREA')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fila('u2'), matching: find.text('FUERA DE TU ÁREA')),
        findsNothing,
      );
      final etiqueta = tester.getSemantics(fila('u1')).label;
      expect(etiqueta, contains('Fuera de tu área'));
      expect(tester.getSemantics(fila('u2')).label, isNot(contains('Fuera de tu área')));
      semantica.dispose();
    });

    testWidgets('la hoja de la casa fuera del área también lo dice', (tester) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));

      m.mapa.tocarPunto('u1');
      await asentarLista(tester);

      expect(vistaPrevia, findsOneWidget);
      expect(
        find.descendant(of: vistaPrevia, matching: find.byType(EtiquetaFueraDelArea)),
        findsOneWidget,
      );

      await tester.tap(cerrarVistaPrevia);
      await asentarLista(tester);
      m.mapa.tocarPunto('u2');
      await asentarLista(tester);
      expect(
        find.descendant(of: vistaPrevia, matching: find.byType(EtiquetaFueraDelArea)),
        findsNothing,
      );
    });

    testWidgets('una marcada que no es del mapa (de baja u otra) no cuenta ni se dibuja', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1', 'no-esta'}));

      expect(_conAro(m.mapa), {'u1'});
      expect(_dibujadas(m.mapa), isNot(contains('no-esta')));
      expect(find.bySemanticsLabel(RegExp('1 casa fuera de tu área, con un aro')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el pull saca una casa del área con el mapa abierto: aparece el aro; vuelve al '
        'área: el aro se va', (tester) async {
      final fuera = _FueraDelAreaFalsas();
      final m = await _montar(tester, fuera);
      expect(_conAro(m.mapa), isEmpty);

      fuera.emitir({'u2'});
      await asentarLista(tester);
      expect(_conAro(m.mapa), {'u2'});

      fuera.emitir(const {});
      await asentarLista(tester);
      expect(_conAro(m.mapa), isEmpty);
      expect(_dibujadas(m.mapa), {'u1', 'u2', 'u3', 'u4'});
    });

    testWidgets('si la marca no se puede leer, el mapa sigue igual, sin marcas ni avisos', (
      tester,
    ) async {
      final fuera = _FueraDelAreaFalsas()..falla = StateError('base cerrada');
      final m = await _montar(tester, fuera);

      expect(_dibujadas(m.mapa), {'u1', 'u2', 'u3', 'u4'});
      expect(_conAro(m.mapa), isEmpty);
      expect(_avisoMapa, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ver u ocultar desde «Referencias»', () {
    testWidgets('sin casas fuera del área la leyenda no habla del aro ni ofrece el interruptor '
        '(el mapa no lo dibuja)', (tester) async {
      await _montar(tester, _FueraDelAreaFalsas());
      await _abrirReferencias(tester);

      expect(hojaReferencias, findsOneWidget);
      expect(find.byKey(ClavesFueraDelArea.leyenda), findsNothing);
      expect(_interruptor, findsNothing);
    });

    testWidgets('con casas fuera del área el interruptor dice cuántas son y que no se borra nada; '
        'arranca prendido', (tester) async {
      await _montar(tester, _FueraDelAreaFalsas({'u1', 'u3'}));
      await _abrirReferencias(tester);

      expect(find.byKey(ClavesFueraDelArea.leyenda), findsOneWidget);
      expect(find.text('Fuera de tu área: ya no es de tu zona. No se borra.'), findsOneWidget);
      expect(_interruptor, findsOneWidget);
      expect(tester.widget<SwitchListTile>(_interruptor).value, isTrue);
      expect(find.text('Mostrar las casas fuera de tu área'), findsOneWidget);
      expect(
        find.text('2 casas. Ocultarlas solo cambia lo que ves en el mapa: no se borra nada.'),
        findsOneWidget,
      );
    });

    testWidgets('ocultarlas: no se dibujan, no están en «Cercanía», el mapa dice cuántas hay y '
        '«Ver» las trae de vuelta', (tester) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1', 'u3'}));

      await _ocultarDesdeReferencias(tester);

      expect(_dibujadas(m.mapa), {'u2', 'u4'});
      expect(_avisoMapa, findsOneWidget);
      expect(
        find.descendant(of: _avisoMapa, matching: find.text('2 casas fuera de tu área ocultas')),
        findsOneWidget,
      );

      await tocarAsa(tester);
      expect(fila('u1'), findsNothing);
      expect(fila('u3'), findsNothing);
      expect(fila('u2'), findsOneWidget);
      expect(_avisoHoja, findsOneWidget);

      await tester.tap(find.descendant(of: _avisoMapa, matching: find.text('Ver')));
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), {'u1', 'u2', 'u3', 'u4'});
      expect(_conAro(m.mapa), {'u1', 'u3'});
      expect(_avisoMapa, findsNothing);
      expect(_avisoHoja, findsNothing);
      expect(fila('u1'), findsOneWidget);
    });

    testWidgets('«Ver» del aviso de «Cercanía» también las trae de vuelta', (tester) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await _ocultarDesdeReferencias(tester);
      await tocarAsa(tester);

      await tester.tap(_avisoHoja);
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), contains('u1'));
      expect(_avisoHoja, findsNothing);
    });

    testWidgets('ocultar no da de baja ni cambia ninguna casa (solo visual)', (tester) async {
      final repo = RepoListaFalso(_casas());
      final m = await montarMapaUbicaciones(
        tester,
        repo: repo,
        otrosOverrides: [
          _FueraDelAreaFalsas({'u1', 'u3'}).sobrescribe,
        ],
      );

      await _ocultarDesdeReferencias(tester);
      await tester.tap(_avisoMapa);
      await asentarLista(tester);

      expect(repo.cambiosDeBaja, isEmpty);
      expect(m.altas, isEmpty);
      final estado = contenedorDeLaPestana(tester).read(fueraDelAreaEnElMapaProvider('col-1'));
      expect(estado.ids, {'u1', 'u3'}, reason: 'la marca sigue: solo cambió lo que se ve');
    });

    testWidgets('el aviso es un botón con su nombre entero y anuncia al volver a mostrarlas', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final anuncios = escucharAnuncios(tester);
      await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await _ocultarDesdeReferencias(tester);

      expect(anuncios, contains('Las casas fuera de tu área quedaron ocultas.'));
      final nodo = tester.getSemantics(_avisoMapa);
      expect(nodo.label, '1 casa fuera de tu área oculta. Ver');
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(_avisoMapa).height, greaterThanOrEqualTo(48));

      await tester.tap(_avisoMapa);
      await asentarLista(tester);
      expect(anuncios, contains('Las casas fuera de tu área se ven en el mapa.'));
      semantica.dispose();
    });
  });

  group('casos límite', () {
    testWidgets('la elegida no se oculta: sigue a la vista con su hoja y se va al cerrarla', (
      tester,
    ) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      m.mapa.tocarPunto('u1');
      await asentarLista(tester);

      contenedorDeLaPestana(tester).read(verFueraDelAreaProvider.notifier).ocultar();
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), contains('u1'));
      expect(vistaPrevia, findsOneWidget);

      await tester.tap(cerrarVistaPrevia);
      await asentarLista(tester);
      expect(_dibujadas(m.mapa), isNot(contains('u1')));
      expect(seleccionadaId(tester), isNull);
    });

    testWidgets('doble toque en «Ver»: una sola vez, sin errores', (tester) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await _ocultarDesdeReferencias(tester);

      await tester.tap(_avisoMapa);
      await tester.tap(_avisoMapa, warnIfMissed: false);
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), contains('u1'));
      expect(_avisoMapa, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dos cambios seguidos del interruptor (un cuadro entre ellos): queda el último', (
      tester,
    ) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await _abrirReferencias(tester);
      await tester.ensureVisible(_interruptor);
      await asentarLista(tester, 4);

      await tester.tap(_interruptor);
      await tester.pump();
      await tester.tap(_interruptor);
      await asentarLista(tester, 4);
      expect(tester.widget<SwitchListTile>(_interruptor).value, isTrue);
      await _cerrarReferencias(tester);

      expect(_dibujadas(m.mapa), contains('u1'));
      expect(_avisoMapa, findsNothing);
    });

    testWidgets('doble toque en el interruptor en el mismo cuadro: no alterna dos veces, quedan '
        'ocultas y sin errores', (tester) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await _abrirReferencias(tester);
      await tester.ensureVisible(_interruptor);
      await asentarLista(tester, 4);

      await tester.tap(_interruptor);
      await tester.tap(_interruptor);
      await asentarLista(tester, 4);
      expect(tester.widget<SwitchListTile>(_interruptor).value, isFalse);
      await _cerrarReferencias(tester);

      expect(_dibujadas(m.mapa), isNot(contains('u1')));
      expect(_avisoMapa, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cambiar de pestaña y volver, o desmontar el mapa y reabrirlo: la elección sigue', (
      tester,
    ) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1'}));
      await _ocultarDesdeReferencias(tester);

      m.activa.value = false;
      await asentarLista(tester);
      m.activa.value = true;
      await asentarLista(tester);
      expect(_dibujadas(m.mapa), isNot(contains('u1')));
      expect(_avisoMapa, findsOneWidget);

      m.montada.value = false;
      await asentarLista(tester);
      m.montada.value = true;
      await asentarLista(tester);
      expect(_dibujadas(m.mapa), isNot(contains('u1')));
      expect(_avisoMapa, findsOneWidget);
    });

    testWidgets('ocultas, el pull saca otra del área: la cuenta sube sin tocar nada', (
      tester,
    ) async {
      final fuera = _FueraDelAreaFalsas({'u1'});
      final m = await _montar(tester, fuera);
      await _ocultarDesdeReferencias(tester);

      fuera.emitir({'u1', 'u2'});
      await asentarLista(tester);

      expect(_dibujadas(m.mapa), {'u3', 'u4'});
      expect(find.text('2 casas fuera de tu área ocultas'), findsOneWidget);

      fuera.emitir(const {});
      await asentarLista(tester);
      expect(_avisoMapa, findsNothing, reason: 'sin casas fuera del área no hay nada oculto');
      expect(_dibujadas(m.mapa), {'u1', 'u2', 'u3', 'u4'});
    });

    testWidgets('todas fuera del área y ocultas: «Cercanía» queda con el aviso y «Ver»', (
      tester,
    ) async {
      final m = await _montar(tester, _FueraDelAreaFalsas({'u1', 'u2', 'u3', 'u4'}));
      await _ocultarDesdeReferencias(tester);
      await tocarAsa(tester);

      expect(_dibujadas(m.mapa), isEmpty);
      expect(_avisoHoja, findsOneWidget);
      expect(find.byKey(ClavesMapaUbicaciones.vacio), findsNothing, reason: 'no está vacío');
    });

    testWidgets('lista larga: 200 casas, 150 fuera del área', (tester) async {
      final casas = [
        for (var i = 0; i < 200; i++) filaLista('c$i', numero: '$i', metrosAlNorte: 300.0 + i),
      ];
      final m = await _montar(
        tester,
        _FueraDelAreaFalsas({for (var i = 0; i < 150; i++) 'c$i'}),
        casas: casas,
      );
      expect(_conAro(m.mapa), hasLength(150));

      await _ocultarDesdeReferencias(tester);

      expect(_dibujadas(m.mapa), hasLength(50));
      expect(find.text('150 casas fuera de tu área ocultas'), findsOneWidget);
    });

    for (final (ancho, alto) in [(320.0, 568.0), (390.0, 844.0)]) {
      testWidgets('texto al 200 % en $ancho×$alto: el aviso entra a lo ancho, se lee entero y se '
          'toca', (tester) async {
        final m = await _montar(
          tester,
          _FueraDelAreaFalsas({for (var i = 1; i <= 4; i++) 'u$i'}),
          escala: 2,
          tamano: Size(ancho, alto),
        );
        await _ocultarDesdeReferencias(tester);

        expect(tester.takeException(), isNull);
        final caja = tester.getRect(_avisoMapa);
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(ancho));
        expect(caja.bottom, lessThan(alto - AlturaHoja.altoMinimizada(const TextScaler.linear(2))));

        await tester.tap(_avisoMapa);
        await asentarLista(tester);
        expect(_dibujadas(m.mapa), hasLength(4));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('texto al 200 %: la fila con la etiqueta y «Referencias» con el interruptor no '
        'desbordan', (tester) async {
      await _montar(tester, _FueraDelAreaFalsas({'u1'}), escala: 2, tamano: const Size(320, 568));
      await tocarAsa(tester);
      expect(tester.takeException(), isNull);

      await _abrirReferencias(tester);
      await tester.ensureVisible(_interruptor);
      await asentarLista(tester, 4);
      expect(_interruptor, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
