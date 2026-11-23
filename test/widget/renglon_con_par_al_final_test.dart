// #737: el renglón «título a la izquierda, par a la derecha» de la hora de los avisos. Si el par entra
// al lado del título van juntos; si no, el par baja entero, a la derecha y sin recorte.
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/renglon_con_par_al_final.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _titulo = Key('titulo');
const _par = Key('par');

Widget _renglon({
  required double ancho,
  double tituloAncho = 100,
  double parAncho = 60,
  double anchoMaximoDelTitulo = double.infinity,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: ancho,
      child: RenglonConParAlFinal(
        anchoMaximoDelTitulo: anchoMaximoDelTitulo,
        titulo: SizedBox(key: _titulo, width: tituloAncho, height: 40),
        par: SizedBox(key: _par, width: parAncho, height: 20),
      ),
    ),
  ),
);

void main() {
  testWidgets('si entran juntos: mismo renglón, centrados en vertical, el par a la derecha', (
    tester,
  ) async {
    await tester.pumpWidget(_renglon(ancho: 300));

    expect(tester.getTopLeft(find.byKey(_titulo)).dx, 0);
    expect(tester.getTopRight(find.byKey(_par)).dx, 300);
    // El par (20 de alto) queda centrado frente al título (40 de alto).
    expect(tester.getTopLeft(find.byKey(_par)).dy, 10);
    expect(tester.getSize(find.byType(RenglonConParAlFinal)).height, 40);
  });

  testWidgets('si no entran juntos: el par baja entero, a la derecha, sin recorte', (tester) async {
    await tester.pumpWidget(_renglon(ancho: 150));

    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.byKey(_titulo)), Offset.zero);
    expect(tester.getTopRight(find.byKey(_par)).dx, 150);
    expect(tester.getTopLeft(find.byKey(_par)).dy, 44, reason: 'debajo del título + 4 de aire');
    expect(tester.getSize(find.byKey(_par)).width, 60, reason: 'no se achicó ni se cortó');
    expect(tester.getSize(find.byType(RenglonConParAlFinal)).height, 64);
  });

  testWidgets('el límite justo: título + 12 + par igual al ancho entra en un renglón', (
    tester,
  ) async {
    await tester.pumpWidget(_renglon(ancho: 172));
    expect(tester.getTopLeft(find.byKey(_par)).dy, 10);

    await tester.pumpWidget(_renglon(ancho: 171));
    expect(tester.getTopLeft(find.byKey(_par)).dy, 44);
  });

  testWidgets('el título no pasa de su ancho máximo (el resto es del par)', (tester) async {
    await tester.pumpWidget(_renglon(ancho: 400, tituloAncho: 350, anchoMaximoDelTitulo: 240));

    expect(tester.getSize(find.byKey(_titulo)).width, 240);
    expect(tester.getTopRight(find.byKey(_par)).dx, 400);
  });

  testWidgets('sin ancho acotado se arma con lo que miden los dos y no falla', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RenglonConParAlFinal(
              titulo: const SizedBox(width: 100, height: 40),
              par: const SizedBox(width: 60, height: 20),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(RenglonConParAlFinal)), const Size(172, 40));
  });

  testWidgets('el toque llega al par aunque haya bajado', (tester) async {
    var toques = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 150,
            child: RenglonConParAlFinal(
              titulo: const SizedBox(width: 100, height: 40),
              par: GestureDetector(
                key: _par,
                behavior: HitTestBehavior.opaque,
                onTap: () => toques++,
                child: const SizedBox(width: 60, height: 20),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(_par));

    expect(toques, 1);
  });
}
