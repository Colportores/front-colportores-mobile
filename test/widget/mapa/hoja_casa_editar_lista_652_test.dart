// «Editar casa» desde la hoja de la casa de la Lista (#652, decisión del 05/11 sobre «Abrir la
// existente»): la edición no se guarda, la hoja se cierra y la Lista abre la hoja de la otra casa,
// como «Abrir la existente» de la vista 10.
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

void main() {
  testWidgets(
    'dado «Abrir la existente» desde «Editar casa», la hoja de la casa se cierra y se abre '
    'la hoja de la otra casa',
    (tester) async {
      final aperturas = <String>[];
      await montarLista(
        tester,
        repo: RepoListaFalso([
          filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40),
          filaLista('b', calle: 'Rivera', numero: '50', metrosAlNorte: 400),
        ]),
        casaAbreSuHoja: true,
        masOverrides: [
          abridorEdicionUbicacionProvider.overrideWithValue((
            context, {
            required String colportorId,
            required String ubicacionId,
          }) async {
            aperturas.add(ubicacionId);
            return const UbicacionExistenteElegida('b');
          }),
        ],
      );
      await tester.tap(find.text('Av. Italia 1234'));
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.titulo), findsOneWidget);

      await tester.tap(find.byKey(ClavesHojaCasa.editar));
      await asentarLista(tester);
      await tester.pump(const Duration(seconds: 1));
      await asentarLista(tester);

      expect(aperturas, ['a']);
      expect(find.byType(HojaCasa), findsOneWidget, reason: 'una sola hoja: la de la otra casa');
      expect(
        tester.widget<Text>(find.byKey(ClavesHojaCasa.titulo)).data,
        'Rivera 50',
        reason: 'la hoja que quedó es la de la existente',
      );
    },
  );
}
