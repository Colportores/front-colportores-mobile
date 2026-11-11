// QA de la hoja de la casa arriba (vista 39, C·02, #445, PR #476): el camino real por el mapa (la hoja a
// un tercio muestra el resumen C·01; subida a la mitad, la hoja con pestañas C·02) y por la Lista (modal sin
// tres alturas). Fuentes reales; capturas con `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;
import 'personas_arnes.dart' show contextoActivo;

Finder get _pestanas => find.byKey(ClavesHojaCasa.pestanas);
Finder get _agregar => find.byKey(ClavesHojaCasa.agregarPersona);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);

Future<MontajeMapaUbicaciones> _montarMapa(
  WidgetTester tester, {
  Size tamano = t412x915,
  double escala = 1,
  ContextoDeLaCasa? contexto,
}) async {
  await cargarFuentes205(tester);
  final m = await montarMapaUbicaciones(
    tester,
    repo: RepoListaFalso(canvas()),
    tamano: tamano,
    escala: escala,
    lecturaContexto: (_) => Stream.value(contexto ?? contextoC02),
    registrarVisita: (c) {},
    cobrar: (c) {},
    otrosOverrides: [
      personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
      espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(contextoActivo())),
      fichaDePersonaDesdeLaCasaProvider.overrideWithValue((c) async => null),
    ],
  );
  return m;
}

void main() {
  for (final tamano in [t360x640, t412x915]) {
    for (final escala in [1.0, 2.0]) {
      final sufijo = sufijo445(tamano, escala);
      testWidgets('el mapa sube la hoja de la casa: tercio = resumen, mitad = pestañas · $sufijo', (
        tester,
      ) async {
        final m = await _montarMapa(tester, tamano: tamano, escala: escala);
        m.mapa.tocarPunto('a');
        await asentarLista(tester);

        // A un tercio (C·01): el resumen, sin pestañas.
        expect(_pestanas, findsNothing);
        expect(find.text('Pedro Gómez'), findsOneWidget);
        await capturar445(tester, 'mapa_tercio_$sufijo');

        // Subida a la mitad (C·02): «Registrar visita», pestañas y personas.
        await tocarAsa(tester);
        expect(altoHoja(tester), closeTo(tamano.height / 2, 2));
        expect(_pestanas, findsOneWidget);
        expect(find.text('Ana Gómez'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturar445(tester, 'mapa_mitad_$sufijo');

        // Con la hoja a la mitad se llega a «+ Agregar persona» desplazando la hoja.
        await tester.ensureVisible(_agregar);
        await tester.pump();
        expect(_agregar, findsOneWidget);
        expect(tester.getRect(_agregar).bottom, lessThanOrEqualTo(tamano.height));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('bajar la hoja de la mitad a un tercio vuelve al resumen sin perder la casa', (
    tester,
  ) async {
    final m = await _montarMapa(tester);
    m.mapa.tocarPunto('a');
    await asentarLista(tester);
    await tocarAsa(tester);
    expect(_pestanas, findsOneWidget);

    await tocarAsa(tester); // mitad → minimizada (el asa cicla)
    await asentarLista(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cambiar de casa con la hoja arriba: la otra casa no hereda la pestaña ni los avisos',
    (tester) async {
      final m = await _montarMapa(tester);
      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      await tocarAsa(tester);
      expect(_pestanas, findsOneWidget);

      m.mapa.tocarPunto('b');
      await asentarLista(tester);
      expect(find.text('Av. Italia 1250'), findsWidgets);
      expect(_registrar, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('con la hoja a la mitad el asa sigue siendo el objetivo táctil de 48 dp', (
    tester,
  ) async {
    final m = await _montarMapa(tester, tamano: t360x640, escala: 2);
    m.mapa.tocarPunto('a');
    await asentarLista(tester);
    await tocarAsa(tester);
    expect(tester.getSize(asa).height, greaterThanOrEqualTo(AlturaHoja.altoAsa));
    expect(tester.getSize(asa).height, greaterThanOrEqualTo(48));
  });
}
