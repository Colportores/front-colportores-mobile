// El aviso fijo de la entrevista en curso sobre el mapa (vista 39, R·05; decisión de Cristian,
// 23/10, #450): no tapa «Referencias» ni los avisos del mapa, y lleva de vuelta a la entrevista.
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart' show Size, SingleChildScrollView;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

void main() {
  late MontajeEntrevista entrevista;

  setUp(() => entrevista = MontajeEntrevista());

  testWidgets('sin entrevista en curso el mapa se ve como siempre', (tester) async {
    await montarMapaUbicaciones(tester, overridesExtra: entrevista.overrides);

    expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
    expect(chipReferencias, findsOneWidget);
  });

  testWidgets('con una entrevista en curso, el aviso va arriba y «Referencias» queda debajo', (
    tester,
  ) async {
    await entrevista.almacen.guardar(entrevistaDePrueba());
    await montarMapaUbicaciones(tester, overridesExtra: entrevista.overrides);
    await asentarLista(tester);

    final aviso = tester.getRect(find.byKey(ClavesEntrevista.avisoFijo));
    final chip = tester.getRect(chipReferencias);
    expect(find.text('Entrevista en curso · Grecia 3307 · 18 min'), findsOneWidget);
    expect(aviso.top, lessThan(chip.top));
    expect(aviso.bottom, lessThanOrEqualTo(chip.top));
    expect(aviso.overlaps(chip), isFalse);
  });

  testWidgets('«Referencias» sigue respondiendo con el aviso a la vista', (tester) async {
    await entrevista.almacen.guardar(entrevistaDePrueba());
    await montarMapaUbicaciones(tester, overridesExtra: entrevista.overrides);
    await asentarLista(tester);

    await tester.tap(chipReferencias);
    await asentarLista(tester);

    expect(hojaReferencias, findsOneWidget);
  });

  testWidgets('el aviso lleva de vuelta a la hoja de la entrevista', (tester) async {
    await entrevista.almacen.guardar(entrevistaDePrueba());
    await montarMapaUbicaciones(tester, overridesExtra: entrevista.overrides);
    await asentarLista(tester);

    await tester.tap(find.byKey(ClavesEntrevista.avisoFijo));
    await asentarLista(tester);

    expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
  });

  testWidgets('a 200 % de letra en 320×568 el aviso no desborda ni empuja la hoja', (tester) async {
    await entrevista.almacen.guardar(entrevistaDePrueba());
    await montarMapaUbicaciones(
      tester,
      overridesExtra: entrevista.overrides,
      escala: 2,
      tamano: const Size(320, 568),
    );
    await asentarLista(tester);

    expect(tester.takeException(), isNull);
    // El aviso se desplaza dentro de lo que queda libre arriba: lo que se ve no pasa de la hoja.
    final visible = tester.getRect(
      find
          .ancestor(
            of: find.byKey(ClavesEntrevista.avisoFijo),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(visible.bottom, lessThanOrEqualTo(tester.getRect(hoja).top + 0.5));
  });
}
