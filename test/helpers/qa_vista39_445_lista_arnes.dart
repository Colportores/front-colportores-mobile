// Arnés de QA (r2) de la hoja de la casa desde la Lista (vista 05, #445, PR #476): abre el modal con
// una casa y lo lleva al resumen (un tercio) o a la hoja arriba (la mitad).
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/lista_ubicaciones_arnes.dart';
import 'lista_ubicaciones_falsos.dart';

/// Abre «Av. Italia 1234» desde la Lista; con [arriba] sube la hoja tocando el asa.
Future<void> abrirHojaDeLaLista445(
  WidgetTester tester, {
  required bool arriba,
  Size tamano = const Size(412, 915),
  double escala = 1,
}) async {
  await montarLista(
    tester,
    repo: RepoListaFalso([filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40)]),
    escala: escala,
    tamano: tamano,
    registrarVisita: (c) {},
  );
  await tester.tap(find.text('Av. Italia 1234'));
  await asentarLista(tester);
  if (arriba) {
    await tester.tap(find.byKey(ClavesHojaCasa.asaDeLaLista));
    await asentarLista(tester);
  }
}
