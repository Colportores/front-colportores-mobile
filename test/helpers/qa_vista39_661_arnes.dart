// Arnés de los tests de QA de «Vender» con varias personas entrevistadas y de «Ir a la entrevista» (vista 39,
// C·06 / C·07 / R·05; #661, PR #668): lleva la vista a cada estado que una persona puede ver, en la matriz
// de tamaños y escalas de texto. Reusa el arnés del implementador (`Arnes648`) y el de QA de #648.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/661_*.png`
// (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrevista_dada_648_arnes.dart';
import 'persona_falsos.dart';
import 'qa_agenda_148_arnes.dart' show cargarFuentes;
import 'qa_vista39_648_arnes.dart' show t360x640, t412x915;

export 'qa_agenda_148_arnes.dart' show usarFuentesReales;
export 'qa_vista39_648_arnes.dart' show t360x640, t412x915, verHallazgos648;

const conCapturas661 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos661 = bool.fromEnvironment('QA_HALLAZGOS');

final ayer661 = DateTime.utc(2026, 10, 22, 15);
final hoy661 = DateTime.utc(2026, 10, 23, 12);

enum Estado661 {
  /// C·06 con «Vender» y su ayuda «Elegís a quién le vendés» (dos personas entrevistadas).
  quePasoVarias,

  /// C·07 en modo «Vender»: solo las entrevistadas, botón «Vender».
  conQuienVende,

  /// C·07 en modo «Vender» con tres personas en la casa, una sin entrevista.
  conQuienVendeTres,

  /// C·06 con el aviso rojo «Ya tenés una entrevista en curso en …» y su botón «Ir a la entrevista».
  quePasoOtraEnCurso,

  /// R·05 abierta desde «Ir a la entrevista».
  r05DesdeElAviso,

  /// De vuelta de R·05 con atrás: «¿Qué pasó?» con el aviso y su botón otra vez.
  quePasoOtraVolvio,
}

String sufijo661(Size t, double escala) => '${t.width.toInt()}x${t.height.toInt()}_x$escala';

/// Lleva la vista a [estado].
Future<Arnes648> llegarA661(
  WidgetTester tester,
  Estado661 estado, {
  Size tamano = t360x640,
  double escala = 1,
}) async {
  await cargarFuentes(tester);
  final a = Arnes648();
  final dos = [
    clienteDePersonas('1', 'Pedro', apellido: 'Gómez'),
    clienteDePersonas('2', 'Ana', apellido: 'Gómez', minutos: 5),
  ];
  final tres = [...dos, clienteDePersonas('3', 'Luis', apellido: 'Díaz', minutos: 9)];
  a.lector.porVinculo['ep-1'] = ayer661;
  a.lector.porVinculo['ep-2'] = hoy661;
  switch (estado) {
    case Estado661.quePasoVarias:
      await a.montar(tester, personas: dos, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
    case Estado661.conQuienVende:
      await a.montar(tester, personas: dos, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
    case Estado661.conQuienVendeTres:
      await a.montar(tester, personas: tres, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
    case Estado661.quePasoOtraEnCurso:
      await a.montar(tester, personas: dos, tamano: tamano, escala: escala);
      await otraEnCurso661(tester, a);
    case Estado661.r05DesdeElAviso:
      await a.montar(tester, personas: dos, tamano: tamano, escala: escala);
      await otraEnCurso661(tester, a);
      await tocarIrALaEntrevista661(tester, a);
    case Estado661.quePasoOtraVolvio:
      await a.montar(tester, personas: dos, tamano: tamano, escala: escala);
      await otraEnCurso661(tester, a);
      await tocarIrALaEntrevista661(tester, a);
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
  }
  return a;
}

/// Hay una entrevista en curso en otra casa y se toca «Entrevista dada» en esta: sale el aviso.
Future<void> otraEnCurso661(WidgetTester tester, Arnes648 a) async {
  await a
      .contenedor(tester)
      .read(entrevistaEnCursoProvider('col-1').notifier)
      .empezar(espacioId: 'esp-9', espacioPersonaId: 'ep-9');
  await a.asentar(tester);
  await a.abrirQuePaso(tester);
  await a.elegir(tester, OpcionQuePaso.entrevistaDada);
}

Finder get irALaEntrevista661 => find.byKey(ClavesQuePaso.accionDeLaFalla);

Future<void> tocarIrALaEntrevista661(WidgetTester tester, Arnes648 a) async {
  await tester.ensureVisible(irALaEntrevista661);
  await tester.tap(irALaEntrevista661);
  await a.asentar(tester);
}

/// Una captura PNG de lo que se ve (hojas modales y avisos incluidos) en
/// `.dart_tool/qa_capturas/661_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar661(WidgetTester tester, String nombre) async {
  if (!conCapturas661) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/661_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
