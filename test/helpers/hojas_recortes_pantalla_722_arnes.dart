// Arnés de #722 (recortes de pantalla): monta una hoja inferior con la pantalla recortada (isla o
// notch arriba, barra de gestos o de 3 botones abajo, cámara perforada) y mide qué controles quedan
// fuera del área segura.
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Un teléfono con recorte: tamaño en dp, barra de [arriba] (isla o barra de estado), barra de [abajo]
/// (gestos del iPhone, 34 dp, o 3 botones de Android 15, ~48 dp) y [escala] del texto.
final class Recorte {
  const Recorte(
    this.nombre,
    this.tamano, {
    required this.arriba,
    required this.abajo,
    required this.escala,
  });

  final String nombre;
  final Size tamano;
  final double arriba;
  final double abajo;
  final double escala;
}

/// Una hoja inferior y cómo se abre: [abrir] llama a su función pública con datos de prueba y
/// [overrides] son los providers que la hoja lee. Una hoja que se abre sola (la sugerencia de mapa, que
/// la abre un widget cuando el provider trae algo) no tiene [abrir] y pone ese widget en [cuerpo].
final class HojaAbrible {
  const HojaAbrible(this.nombre, this.abrir, {this.overrides = const [], this.cuerpo});

  final String nombre;
  final Future<Object?> Function(BuildContext context)? abrir;
  final List<Override> overrides;
  final Widget? cuerpo;
}

/// Pone la pantalla de [recorte] (tamaño, barras, cámara perforada) para los arneses que ya montan
/// su propia app: se llama antes de montar y no toca nada más.
void ponerRecorte(WidgetTester tester, Recorte recorte) {
  const dpr = 1.0;
  tester.view.physicalSize = recorte.tamano * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = FakeViewPadding(top: recorte.arriba * dpr, bottom: recorte.abajo * dpr);
  tester.view.viewPadding = tester.view.padding;
  // La cámara perforada, centrada arriba.
  tester.view.displayFeatures = [
    ui.DisplayFeature(
      bounds: Rect.fromCenter(center: Offset(recorte.tamano.width / 2, 16), width: 80, height: 32),
      type: ui.DisplayFeatureType.cutout,
      state: ui.DisplayFeatureState.unknown,
    ),
  ];
  addTearDown(tester.view.reset);
}

/// Monta [hoja] en la pantalla de [recorte] y la deja abierta.
Future<void> montarHojaRecortada(WidgetTester tester, Recorte recorte, HojaAbrible hoja) async {
  ponerRecorte(tester, recorte);
  await tester.pumpWidget(
    ProviderScope(
      overrides: hoja.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(recorte.escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                ?hoja.cuerpo,
                Center(
                  child: TextButton(
                    onPressed: () => hoja.abrir?.call(context),
                    child: const Text('abrir hoja'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir hoja'));
  // Los providers contestan en el turno siguiente y la hoja se anima al abrir; sin `pumpAndSettle`
  // porque algunas tienen indicadores que giran para siempre.
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Los controles de la hoja abierta que quedan fuera del área segura de [recorte] (vacía si están
/// todos dentro): los botones y las zonas tocables enteros, y el centro de cada campo, entre la barra de
/// arriba y la de abajo. Si la hoja se desplaza (texto grande en una pantalla chica), cada control se
/// lleva a la vista antes de medirlo: lo que importa es que, con la hoja en el último renglón, nada
/// quede bajo la barra. Falla si la hoja no tiene ningún control: sin eso el test no mide nada.
Future<List<String>> controlesFueraDelAreaSegura(WidgetTester tester, Recorte recorte) async {
  final hoja = find.byType(BottomSheet);
  expect(hoja, findsOneWidget, reason: 'la hoja no se abrió');
  final limiteAbajo = recorte.tamano.height - recorte.abajo;
  final fuera = <String>[];
  var vistos = 0;

  Future<void> medir(Finder buscados, {required bool entero, bool traer = true}) async {
    final todos = find.descendant(of: hoja, matching: buscados);
    final cantidad = todos.evaluate().length;
    for (var i = 0; i < cantidad; i++) {
      final uno = todos.at(i);
      if (traer) {
        await tester.ensureVisible(uno);
        await tester.pump();
      }
      vistos++;
      final rect = tester.getRect(uno);
      final abajo = entero ? rect.bottom : rect.center.dy;
      final arriba = entero ? rect.top : rect.center.dy;
      if (abajo > limiteAbajo + 0.5 || arriba < recorte.arriba - 0.5) {
        fuera.add(
          '${tester.widget(uno).runtimeType} $rect (límite ${recorte.arriba}–$limiteAbajo)',
        );
      }
    }
  }

  await medir(find.bySubtype<ButtonStyleButton>(), entero: true);
  await medir(find.byType(TextField), entero: false);
  await medir(find.byType(InkWell), entero: true);
  await medir(find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null), entero: true);
  // Una lista que se desplaza termina arriba de la barra: el último renglón no queda debajo.
  await medir(find.byType(Scrollable), entero: true, traer: false);
  expect(vistos, greaterThan(0), reason: 'no hay ningún control para medir');
  return fuera;
}
