// Arnés de los tests de QA de la entrevista sin persona y de «Vender» con su visita (vista 39, R·04 → R·08 y
// C·06 / C·07 + alta corta 32 A; #669, PR #672): lleva la vista a cada estado nuevo en la matriz de tamaños
// y escalas de texto. Reusa el arnés del implementador (`Arnes648`) y el de QA de #648.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/669_*.png`
// (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrevista_dada_648_arnes.dart';
import 'persona_falsos.dart';
import 'qa_agenda_148_arnes.dart' show cargarFuentes;
import 'qa_vista39_648_arnes.dart' show t360x640, t412x915;

export 'qa_agenda_148_arnes.dart' show usarFuentesReales;
export 'qa_vista39_648_arnes.dart' show t360x640, t412x915;

const conCapturas669 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos669 = bool.fromEnvironment('QA_HALLAZGOS');

final ayer669 = DateTime.utc(2026, 10, 22, 15);

enum Estado669 {
  /// R·05 de una entrevista que empezó sin nombre.
  r05SinPersona,

  /// R·05 cerrada: el aviso fijo del mapa, sin persona.
  avisoFijoSinPersona,

  /// R·06 sin persona.
  r06SinPersona,

  /// R·06 sin persona con «No pudimos guardar».
  r06SinPersonaNoSeGuardo,

  /// R·07 sin persona (no se registró el inicio).
  r07SinPersona,

  /// 32 A pedida por «Sí, registrar la venta» desde R·06.
  altaDesdeR06,

  /// 32 A pedida desde R·07.
  altaDesdeR07,

  /// 32 A con el nombre escrito y «No pudimos guardar».
  altaConFalla,

  /// 32 A con el error de «nombre vacío» a la vista.
  altaConErrorDeNombre,

  /// La venta (27) de la persona recién anotada.
  ventaTrasElAlta,

  /// Se salió de la venta tras el alta: «La venta no se guardó. La entrevista … sigue en curso.»
  ventaTrasElAltaNoGuardada,

  /// C·06 con el aviso «Esa persona ya no está en tu teléfono…» de «Vender».
  venderPersonaDeBaja,

  /// C·06 con el aviso «La casa ya no está en tu teléfono…» de «Vender».
  venderCasaDeBaja,

  /// C·06 con «Ya no queda ninguna persona entrevistada…» (C·07 en modo «Vender» sin nadie).
  venderSinNadie,

  /// La venta de «Vender» (27) ya abierta.
  venderLaVenta,
}

String sufijo669(Size t, double escala) => '${t.width.toInt()}x${t.height.toInt()}_x$escala';

Finder get altaPagina669 => find.byType(AltaPersonaPage);
Finder get botonGuardarPersona669 => find.widgetWithText(FilledButton, TextosPersonas.guardar);
Finder get campoNombre669 => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == TextosPersonas.sugerenciaNombre,
);
Finder get ventaPagina669 => find.byKey(const Key('nueva_venta_pagina'));

PersonaRepositorioFalso personas669(Arnes648 a, WidgetTester tester) =>
    a.contenedor(tester).read(personaRepositoryProvider) as PersonaRepositorioFalso;

Future<void> escribirNombre669(WidgetTester tester, String nombre) async {
  await tester.enterText(campoNombre669, nombre);
  await tester.pump();
}

Future<void> guardarPersona669(WidgetTester tester, Arnes648 a) async {
  await tester.ensureVisible(botonGuardarPersona669);
  await tester.pump();
  await tester.tap(botonGuardarPersona669);
  await a.asentar(tester);
}

/// Una casa sin personas, «Entrevista dada» → «Todavía no sé con quién» → R·05.
Future<void> hastaR05SinPersona(
  WidgetTester tester,
  Arnes648 a, {
  Size tamano = t360x640,
  double escala = 1,
  bool inicioPerdido = false,
}) async {
  if (inicioPerdido) {
    a.montaje.rota.fallaAlGuardar = true;
    a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 5);
  }
  await a.montar(tester, personas: [], tamano: tamano, escala: escala);
  a.montaje.rotulo = (direccion: 'Grecia 3307', persona: '');
  await a.abrirQuePaso(tester);
  await a.elegir(tester, OpcionQuePaso.entrevistaDada);
  await a.tocarKey(tester, ClavesConQuien.todaviaNoSe);
}

/// Lleva la vista a [estado].
Future<Arnes648> llegarA669(
  WidgetTester tester,
  Estado669 estado, {
  Size tamano = t360x640,
  double escala = 1,
}) async {
  await cargarFuentes(tester);
  final a = Arnes648();
  switch (estado) {
    case Estado669.r05SinPersona:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
    case Estado669.avisoFijoSinPersona:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
    case Estado669.r06SinPersona:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
    case Estado669.r06SinPersonaNoSeGuardo:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      a.montaje.agenda.falla = const FailureInesperado();
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);
    case Estado669.r07SinPersona:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala, inicioPerdido: true);
    case Estado669.altaDesdeR06:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
    case Estado669.altaDesdeR07:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala, inicioPerdido: true);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
    case Estado669.altaConFalla:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      personas669(a, tester).resultados.add(const FailureInesperado());
      await escribirNombre669(tester, 'Lucía');
      await guardarPersona669(tester, a);
    case Estado669.altaConErrorDeNombre:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await guardarPersona669(tester, a);
    case Estado669.ventaTrasElAlta:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await escribirNombre669(tester, 'Lucía');
      await guardarPersona669(tester, a);
    case Estado669.ventaTrasElAltaNoGuardada:
      await hastaR05SinPersona(tester, a, tamano: tamano, escala: escala);
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await escribirNombre669(tester, 'Lucía');
      await guardarPersona669(tester, a);
      await a.tocarKey(tester, const Key('venta_atras'));
    case Estado669.venderPersonaDeBaja:
      a.lector.porVinculo['ep-1'] = ayer669;
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
      a.montaje.destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');
      await a.elegir(tester, OpcionQuePaso.vender);
    case Estado669.venderCasaDeBaja:
      a.lector.porVinculo['ep-1'] = ayer669;
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
      a.montaje.destino.sinDestino = true;
      await a.elegir(tester, OpcionQuePaso.vender);
    case Estado669.venderSinNadie:
      a.lector.porVinculo['ep-1'] = ayer669;
      a.lector.porVinculo['ep-2'] = ayer669;
      await a.montar(
        tester,
        personas: [
          clienteDePersonas('1', 'Pedro', apellido: 'Gómez'),
          clienteDePersonas('2', 'Ana', apellido: 'Gómez'),
        ],
        tamano: tamano,
        escala: escala,
      );
      await a.abrirQuePaso(tester);
      final repo = personas669(a, tester);
      final todas = await repo.observarDelEspacio('esp-1').first;
      for (final p in todas) {
        await repo.darDeBaja(personaId: p.persona.id, ahora: ayer669);
      }
      await a.asentar(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
    case Estado669.venderLaVenta:
      a.lector.porVinculo['ep-1'] = ayer669;
      await a.montar(tester, tamano: tamano, escala: escala);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
  }
  return a;
}

/// Una captura PNG de lo que se ve (hojas modales y avisos incluidos) en
/// `.dart_tool/qa_capturas/669_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar669(WidgetTester tester, String nombre) async {
  if (!conCapturas669) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/669_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
