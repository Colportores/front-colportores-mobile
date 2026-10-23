// R·05 · «Entrevista en curso» (vista 39, HU-VIS-005, #450): los textos del canvas, el tiempo que
// corre, la nota, el doble toque en «Finalizar entrevista» y los casos límite de letra grande y
// textos largos.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _inicio = DateTime(2026, 10, 23, 14, 23);

void main() {
  var ahora = DateTime(2026, 10, 23, 14, 41);
  var finalizadas = 0;
  final notas = <String>[];

  setUp(() {
    ahora = DateTime(2026, 10, 23, 14, 41);
    finalizadas = 0;
    notas.clear();
  });

  Future<void> montar(
    WidgetTester tester, {
    String direccion = 'Grecia 3307',
    String persona = 'Pedro Gómez',
    String notaInicial = '',
    double escala = 1,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: HojaEntrevistaEnCurso(
            direccion: direccion,
            persona: persona,
            inicio: _inicio,
            notaInicial: notaInicial,
            alEscribirNota: notas.add,
            alFinalizar: () => finalizadas++,
            reloj: () => ahora,
          ),
        ),
      ),
    );
  }

  testWidgets('R·05 muestra el lugar, la persona, «EN CURSO», cuánto va y desde cuándo', (
    tester,
  ) async {
    await montar(tester);

    expect(find.text('Entrevista en curso'), findsOneWidget);
    expect(find.text('Grecia 3307 · Pedro Gómez'), findsOneWidget);
    expect(find.text('EN CURSO'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('Desde las 14:23'), findsOneWidget);
    expect(find.text('✎  Nota de la visita'), findsOneWidget);
    expect(find.text('Finalizar entrevista'), findsOneWidget);
  });

  testWidgets('el tiempo se actualiza solo cada medio minuto', (tester) async {
    await montar(tester);
    expect(find.text('18 min'), findsOneWidget);

    ahora = DateTime(2026, 10, 23, 14, 42);
    await tester.pump(const Duration(seconds: 30));

    expect(find.text('19 min'), findsOneWidget);
    expect(find.text('18 min'), findsNothing);
  });

  testWidgets('una hora y pico se lee «1 h 20 min»; recién empezada, «menos de 1 min»', (
    tester,
  ) async {
    ahora = DateTime(2026, 10, 23, 15, 43);
    await montar(tester);
    expect(find.text('1 h 20 min'), findsOneWidget);

    ahora = _inicio.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('menos de 1 min'), findsOneWidget);
  });

  testWidgets('el lector de pantalla dice el tiempo como una sola frase', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(tester);

    expect(find.bySemanticsLabel('en curso, 18 min, desde las 14:23'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('«Finalizar entrevista» responde a un solo toque aunque lleguen dos seguidos', (
    tester,
  ) async {
    await montar(tester);

    await tester.tap(find.byKey(ClavesEntrevista.finalizar));
    await tester.tap(find.byKey(ClavesEntrevista.finalizar));
    await tester.pump();

    expect(finalizadas, 1);
  });

  testWidgets('la nota se escribe en la misma hoja y cada cambio llega a quien la guarda', (
    tester,
  ) async {
    await montar(tester);
    expect(find.byKey(ClavesEntrevista.campoNota), findsNothing);

    await tester.tap(find.byKey(ClavesEntrevista.botonNota));
    await tester.pump();
    await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'volver con la esposa');

    expect(notas.last, 'volver con la esposa');
  });

  testWidgets('una nota que ya estaba escrita se ve abierta al volver a la hoja', (tester) async {
    await montar(tester, notaInicial: 'perro suelto');

    expect(find.byKey(ClavesEntrevista.campoNota), findsOneWidget);
    expect(find.text('perro suelto'), findsOneWidget);
  });

  testWidgets('sin lugar ni persona no deja un renglón vacío', (tester) async {
    await montar(tester, direccion: '', persona: '');

    expect(find.text('Entrevista en curso'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('con la persona o el lugar muy largos no desborda', (tester) async {
    await montar(
      tester,
      direccion: 'Avenida General José Gervasio Artigas esquina Bulevar España 1234',
      persona: 'María de los Ángeles Fernández de la Rosa Gómez',
      tamano: const Size(320, 568),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a 200 % de letra en 320×568 todo se alcanza desplazando y nada desborda', (
    tester,
  ) async {
    await montar(tester, escala: 2, tamano: const Size(320, 568));
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(ClavesEntrevista.finalizar),
      80,
      scrollable: find.descendant(
        of: find.byKey(ClavesEntrevista.hojaEnCurso),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(ClavesEntrevista.finalizar));

    expect(finalizadas, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('los botones miden al menos 48 dp de alto', (tester) async {
    await montar(tester);

    expect(tester.getSize(find.byKey(ClavesEntrevista.finalizar)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(ClavesEntrevista.botonNota)).height, greaterThanOrEqualTo(48));
  });
}
