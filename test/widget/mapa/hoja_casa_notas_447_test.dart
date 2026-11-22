// La pestaña Notas dentro de la hoja arriba de la casa (vista 39, C·05, #447): con el enganche real de
// `main.dart` (`pestanaNotasDeLaCasaProvider`) la hoja ofrece «Notas», la pestaña usa el lugar, el
// colportor y el estado de baja de la casa, y las notas se escriben y se leen en el teléfono.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/nota_ubicacion_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart';
import 'notas_lugar_arnes.dart';
import 'personas_arnes.dart' show contextoActivo;

void main() {
  final enganche = pestanaNotasDeLaCasaProvider.overrideWithValue(
    (context, contexto) => PestanaNotasDeLaCasa(
      ubicacionId: contexto.ubicacionId,
      colportorId: contexto.colportorId,
      soloLectura: contexto.esBaja,
    ),
  );

  Future<NotaUbicacionRepositorioFalso> montar(
    WidgetTester tester, {
    List<NotaUbicacion> notas = const [],
    String? colportorId = 'col-1',
    bool esBaja = false,
    double escala = 1,
    Size tamano = t412x915,
  }) async {
    final repo = NotaUbicacionRepositorioFalso(notas: [...notas]);
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...overridesHojaCasa(lectura: (_) => Stream.value(contextoC02)),
          personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(contextoActivo()),
          ),
          fichaDePersonaDesdeLaCasaProvider.overrideWithValue(null),
          pestanaHistorialDeLaCasaProvider.overrideWithValue(null),
          enganche,
          ...overridesLugar(repo),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: HojaCasa(
                item: esBaja ? itemDeLaHoja(baja: DateTime(2026, 10, 1)) : itemDeLaHoja(),
                ahora: ahoraLista,
                alCerrar: () {},
                arriba: true,
                colportorId: colportorId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await asentarLugar(tester);
    return repo;
  }

  Future<void> irANotas(WidgetTester tester) async {
    await tester.tap(find.byKey(ClavesHojaCasa.pestana('notas')));
    await asentarLugar(tester);
  }

  testWidgets(
    'dado la hoja arriba con el enganche de las notas, la pestaña «Notas» se ofrece y abre las notas de ESTE lugar',
    (tester) async {
      final repo = await montar(
        tester,
        notas: [
          notaDeLugar('a', 'Del lugar de la hoja', ubicacionId: 'u-1'),
          notaDeLugar('b', 'De otro lugar', ubicacionId: 'otro'),
        ],
      );
      expect(find.text('Notas'), findsOneWidget);
      expect(repo.notas, hasLength(2));

      await irANotas(tester);

      expect(find.byKey(ClavesNotasDelLugar.pestana), findsOneWidget);
      expect(find.text('+ Nota del lugar'), findsOneWidget);
      expect(find.text('Del lugar de la hoja'), findsOneWidget);
      expect(find.text('De otro lugar'), findsNothing);
    },
  );

  testWidgets(
    'dado que escribo una nota desde la hoja, queda en la pestaña y la hoja sigue abierta',
    (tester) async {
      final repo = await montar(tester);
      await irANotas(tester);

      await tester.tap(find.text('+ Nota del lugar'));
      await asentarLugar(tester);
      await escribirYGuardarLugar(tester, 'Casa de esquina, portón azul.');

      expect(find.text('Casa de esquina, portón azul.'), findsOneWidget);
      expect(find.byKey(ClavesNotasDelLugar.pestana), findsOneWidget);
      expect(repo.notas, hasLength(1));
      expect(repo.notas.single.auditoria.createdBy, 'col-1');
    },
  );

  testWidgets('dado que cambio de pestaña y vuelvo a Notas, las notas siguen', (tester) async {
    await montar(tester, notas: [notaDeLugar('a', 'Persiste', ubicacionId: 'u-1')]);
    await irANotas(tester);
    expect(find.text('Persiste'), findsOneWidget);

    await tester.tap(find.byKey(ClavesHojaCasa.pestana('personas')));
    await asentarLugar(tester);
    expect(find.text('Persiste'), findsNothing);
    await irANotas(tester);

    expect(find.text('Persiste'), findsOneWidget);
  });

  testWidgets('dado una casa dada de baja, la pestaña Notas se ve en solo lectura', (tester) async {
    await montar(tester, esBaja: true, notas: [notaDeLugar('a', 'Se lee', ubicacionId: 'u-1')]);
    await irANotas(tester);

    expect(find.text('Se lee'), findsOneWidget);
    expect(find.byKey(ClavesNotasDelLugar.soloLectura), findsOneWidget);
    expect(find.text('+ Nota del lugar'), findsNothing);
  });

  testWidgets(
    'dado que no hay un colportor con sesión, la pestaña muestra las notas sin escribir',
    (tester) async {
      await montar(
        tester,
        colportorId: null,
        notas: [notaDeLugar('a', 'Se lee', ubicacionId: 'u-1')],
      );
      await irANotas(tester);

      expect(find.text('Se lee'), findsOneWidget);
      expect(find.text('+ Nota del lugar'), findsNothing);
    },
  );

  testWidgets(
    'dado el texto al 200 % en un teléfono chico, la pestaña Notas no se desborda dentro de la hoja',
    (tester) async {
      await montar(
        tester,
        escala: 2,
        tamano: t320x568,
        notas: [
          for (var i = 0; i < 6; i++)
            notaDeLugar('n$i', 'Nota $i ${'larga ' * 30}', ubicacionId: 'u-1'),
        ],
      );
      await irANotas(tester);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dado un borrado desde la hoja, «Deshacer» devuelve la nota a la pestaña', (
    tester,
  ) async {
    await montar(tester, notas: [notaDeLugar('a', 'Para borrar', ubicacionId: 'u-1')]);
    await irANotas(tester);

    await borrarPorMenuLugar(tester, 'a');
    expect(find.text('Para borrar'), findsNothing);
    await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
    await asentarLugar(tester);

    expect(find.text('Para borrar'), findsOneWidget);
    expect(find.byKey(ClavesNotas.hojaOpciones), findsNothing);
  });
}
