// Arnés de los tests de QA de «Registrar visita: ¿qué pasó?» y del aviso «Guardado» (vista 39, C·06 y
// R·01, #411, PR #474): lleva la vista a cada estado que una persona puede ver, en la matriz de
// tamaños y escalas de texto.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/411_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/personas_arnes.dart';
import '../widget/mapa/registrar_visita_arnes.dart';
import 'agenda_repositorio_falso.dart';
import 'persona_falsos.dart';

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`.
const conCapturas411 = bool.fromEnvironment('QA_CAPTURAS');

const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);
const t320x568 = Size(320, 568);

/// Los estados de la vista que una persona puede alcanzar.
enum Estado411 {
  /// C·06 como se ve hoy en producción: solo las dos opciones de un toque (las otras no tienen destino).
  c06Dos,

  /// C·06 con las cinco opciones (con «Cobranza»).
  c06Cinco,

  /// C·06 con las cinco y un nombre larguísimo en «Cobranza».
  c06CincoLargo,

  /// C·06 mientras guarda («Guardando…»).
  c06Guardando,

  /// C·06 con el aviso rojo «No pudimos guardar la visita».
  c06Falla,

  /// C·06 con el aviso «Esta casa ya no está en tu teléfono».
  c06CasaNoEsta,

  /// R·01 «Guardado… No contestó» con «Deshacer».
  r01NoContesto,

  /// R·01 con «Rechazo».
  r01Rechazo,

  /// R·01 con lector de pantalla (el aviso no se cierra solo).
  r01Lector,

  /// «Se deshizo. Grecia 3307 vuelve a como estaba.»
  seDeshizo,

  /// «No pudimos deshacer. La visita quedó guardada.»
  noPudimosDeshacer,

  /// «¿Con quién es la entrevista?» al programar, con varias personas.
  conQuienProgramar,

  /// «+ Alguien nuevo» desde «¿Con quién es la entrevista?» al programar: el formulario corto.
  conQuienProgramarAlta,
}

final _pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');
final _ana = clienteDePersonas('ana', 'Ana', apellido: 'Gómez', minutos: 1);
final _larga = clienteDePersonas(
  'larga',
  'Maximiliano Alejandro Bartolomé',
  apellido: 'Rodríguez de la Santísima Trinidad y Tobago',
);

/// Lleva la vista a [estado]. Lo que queda colgado de una compuerta se libera solo al terminar.
Future<ArnesQuePaso> llegarA411(
  WidgetTester tester,
  Estado411 estado, {
  Size tamano = t412x915,
  double escala = 1,
}) async {
  switch (estado) {
    case Estado411.c06Dos:
      return montarQuePaso(tester, tamano: tamano, escala: escala);
    case Estado411.c06Cinco:
      return montarQuePaso(
        tester,
        personas: [_pedro],
        saldos: {'pedro': 120000},
        programar: true,
        entrevistaDada: true,
        cobrar: true,
        tamano: tamano,
        escala: escala,
      );
    case Estado411.c06CincoLargo:
      return montarQuePaso(
        tester,
        personas: [_larga],
        saldos: {'larga': 123456700},
        programar: true,
        entrevistaDada: true,
        cobrar: true,
        tamano: tamano,
        escala: escala,
      );
    case Estado411.c06Guardando:
      final compuerta = Completer<void>();
      addTearDown(() {
        if (!compuerta.isCompleted) compuerta.complete();
      });
      final repo = AgendaRepositorioFalso()..compuerta = compuerta;
      final a = await montarQuePaso(tester, repo: repo, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.noContesto);
      return a;
    case Estado411.c06Falla:
      final repo = AgendaRepositorioFalso()
        ..resultados.add(const FailureInesperado(causa: 'StateError'));
      final a = await montarQuePaso(tester, repo: repo, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.noContesto);
      return a;
    case Estado411.c06CasaNoEsta:
      final repo = AgendaRepositorioFalso()
        ..resultados.add(const FailureValidacion(campos: {'espacio': 'no está'}));
      final a = await montarQuePaso(tester, repo: repo, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.noContesto);
      return a;
    case Estado411.r01NoContesto:
      final a = await montarQuePaso(tester, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.noContesto);
      return a;
    case Estado411.r01Rechazo:
      final a = await montarQuePaso(tester, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.rechazo);
      return a;
    case Estado411.r01Lector:
      final a = await montarQuePaso(tester, tamano: tamano, escala: escala, lector: true);
      await elegir(tester, OpcionQuePaso.noContesto);
      return a;
    case Estado411.seDeshizo:
      final a = await montarQuePaso(tester, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.noContesto);
      await tester.tap(find.text('Deshacer'));
      await asentar(tester);
      return a;
    case Estado411.noPudimosDeshacer:
      final repo = AgendaRepositorioFalso()
        ..resultadosDeshacer.add(const FailureInesperado(causa: 'StateError'));
      final a = await montarQuePaso(tester, repo: repo, tamano: tamano, escala: escala);
      await elegir(tester, OpcionQuePaso.noContesto);
      await tester.tap(find.text('Deshacer'));
      await asentar(tester);
      return a;
    case Estado411.conQuienProgramar:
      final a = await montarQuePaso(
        tester,
        personas: [_pedro, _ana],
        programar: true,
        tamano: tamano,
        escala: escala,
      );
      await elegir(tester, OpcionQuePaso.programarEntrevista);
      return a;
    case Estado411.conQuienProgramarAlta:
      final a = await montarQuePaso(
        tester,
        personas: [_pedro, _ana],
        programar: true,
        tamano: tamano,
        escala: escala,
      );
      await elegir(tester, OpcionQuePaso.programarEntrevista);
      // La lista es perezosa: a texto grande «+ Alguien nuevo» todavía no se construyó.
      await tester.scrollUntilVisible(
        find.text('+ Alguien nuevo'),
        120,
        scrollable: find
            .descendant(of: find.byType(HojaConQuien), matching: find.byType(Scrollable))
            .first,
      );
      await tester.pump();
      await tester.tap(find.text('+ Alguien nuevo'));
      await asentar(tester);
      return a;
  }
}

/// Una captura PNG de lo que se ve (hojas modales y avisos incluidos) en
/// `.dart_tool/qa_capturas/411_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar411(WidgetTester tester, String nombre) async {
  if (!conCapturas411) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/411_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// «360x640_x2.0».
String sufijo411(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';
