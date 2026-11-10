// Arnés de los tests de QA de «Entrevista dada» y «Vender» de «¿Qué pasó?» (vista 39, R·04 → R·08 y C·06 /
// C·07; #648, PR #657): lleva la vista a cada estado que una persona puede ver, en la matriz de tamaños y
// escalas de texto. Reusa el arnés del implementador (`Arnes648`).
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/648_*.png`
// (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrevista_dada_648_arnes.dart';
import 'persona_falsos.dart';
import 'qa_agenda_148_arnes.dart' show cargarFuentes;

export 'qa_agenda_148_arnes.dart' show usarFuentesReales;

const conCapturas648 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos648 = bool.fromEnvironment('QA_HALLAZGOS');

const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);

final ayer648 = DateTime.utc(2026, 10, 22, 15);

enum Estado648 {
  /// C·06 con «Vender» (la casa ya tuvo una entrevista dada).
  quePasoConVender,

  /// C·06 con el aviso rojo «Ya tenés una entrevista en curso en …».
  quePasoOtraEnCurso,

  /// R·04: la casa sin personas, nombre y apellido.
  r04Nombre,

  /// C·07: la casa con dos personas.
  c07Lista,

  /// R·05.
  r05,

  /// R·05 cerrada: el aviso fijo del mapa.
  avisoFijo,

  /// R·06.
  r06,

  /// R·06 con «No pudimos guardar».
  r06NoSeGuardo,

  /// R·07.
  r07,

  /// «La venta no se guardó. Podés volver a tocar «Vender».» (se salió de la venta de «Vender»).
  ventaDeLaCasaNoGuardada,

  /// «La venta no se guardó. La entrevista … sigue en curso.» (se salió de la venta de R·06).
  ventaDeLaEntrevistaNoGuardada,
}

String sufijo648(Size t, double escala) => '${t.width.toInt()}x${t.height.toInt()}_x$escala';

/// Lleva la vista a [estado].
Future<Arnes648> llegarA648(
  WidgetTester tester,
  Estado648 estado, {
  Size tamano = t360x640,
  double escala = 1,
}) async {
  await cargarFuentes(tester);
  final a = Arnes648();
  final dosPersonas = [
    clienteDePersonas('1', 'Pedro', apellido: 'Gómez'),
    clienteDePersonas('2', 'Ana', apellido: 'Gómez'),
  ];
  switch (estado) {
    case Estado648.quePasoConVender:
      a.lector.porVinculo['ep-1'] = ayer648;
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
    case Estado648.quePasoOtraEnCurso:
      await a.montar(tester, tamano: tamano, escala: escala);
      await a
          .contenedor(tester)
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-9', espacioPersonaId: 'ep-9');
      await a.asentar(tester);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
    case Estado648.r04Nombre:
      await a.montar(tester, personas: [], tamano: tamano, escala: escala);
      await a.hastaLaEntrevista(tester);
    case Estado648.c07Lista:
      await a.montar(tester, personas: dosPersonas, tamano: tamano, escala: escala);
      await a.hastaLaEntrevista(tester);
    case Estado648.r05:
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.hastaLaEntrevista(tester);
    case Estado648.avisoFijo:
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.hastaLaEntrevista(tester);
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
    case Estado648.r06:
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.hastaLaHoraDeSalida(tester);
    case Estado648.r06NoSeGuardo:
      await a.montar(tester, tamano: tamano, escala: escala);
      a.montaje.agenda.falla = const FailureInesperado();
      await a.hastaLaHoraDeSalida(tester);
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);
    case Estado648.r07:
      a.montaje.rota.fallaAlGuardar = true;
      a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 13, 30);
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.hastaLaEntrevista(tester);
    case Estado648.ventaDeLaCasaNoGuardada:
      a.lector.porVinculo['ep-1'] = ayer648;
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.tocarKey(tester, const Key('venta_atras'));
    case Estado648.ventaDeLaEntrevistaNoGuardada:
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.hastaLaHoraDeSalida(tester);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await a.tocarKey(tester, const Key('venta_atras'));
  }
  return a;
}

/// Una captura PNG de lo que se ve (hojas modales y avisos incluidos) en
/// `.dart_tool/qa_capturas/648_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar648(WidgetTester tester, String nombre) async {
  if (!conCapturas648) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/648_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
