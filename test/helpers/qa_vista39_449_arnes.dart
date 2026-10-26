// Arnés de los tests de QA del paso «¿Con quién?» de la vista 39 (R·04 y C·07, #449, PR #463): monta la
// hoja en los ocho estados que se pueden alcanzar, en la matriz de tamaños y escalas de texto, con
// fuentes reales y capturas PNG.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/449_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/persona_falsos.dart';
import '../widget/mapa/hoja_con_quien_arnes.dart';
import '../widget/mapa/personas_arnes.dart';

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`.
const conCapturas449 = bool.fromEnvironment('QA_CAPTURAS');

/// La raíz de la captura: la app entera (la hoja vive dentro).
final raiz449 = GlobalKey();

const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);
const t320x568 = Size(320, 568);

/// Los estados de la hoja que una persona puede ver.
enum Estado449 {
  r04,
  r04ErrorNombre,
  r04Guardando,
  r04Falla,
  c07,
  c07Muchas,
  cargando,
  errorDeLectura,
}

/// Repositorio cuya lectura tarda [demora] (para el hueco entre el toque y la hoja).
final class PersonaRepositorioLento extends PersonaRepositorioFalso {
  PersonaRepositorioLento(this.demora);

  final Duration demora;

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) async* {
    await Future<void>.delayed(demora);
    yield* super.observarDelEspacio(espacioId);
  }
}

/// Monta el arnés de la PR (con su `ProviderScope`) dentro de una raíz capturable, con el alto del
/// teclado en [teclado] (dp lógicos, la pantalla va a 1 px = 1 dp).
Future<ResultadoConQuien> montar449(
  WidgetTester tester, {
  PersonaRepository? repo,
  SaldosDePersonas? saldos,
  Size tamano = t412x915,
  double escala = 1,
  double teclado = 0,
  bool abrir = true,
}) async {
  final resultado = ResultadoConQuien();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  if (teclado > 0) tester.view.viewInsets = FakeViewPadding(bottom: teclado);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: raiz449,
      child: ProviderScope(
        overrides: [
          personaRepositoryProvider.overrideWithValue(repo ?? PersonaRepositorioFalso()),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(contextoActivo()),
          ),
          saldosDePersonasProvider.overrideWithValue(saldos ?? SaldosFalsos(const {})),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          navigatorObservers: [resultado.rutas],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final e = await mostrarHojaConQuien(
                      context,
                      espacioId: 'esp-1',
                      colportorId: 'col-1',
                    );
                    resultado
                      ..elegida = e
                      ..cierres += 1;
                  },
                  child: const Text('abrir paso'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirPaso(tester);
  return resultado;
}

Finder get campoNombre449 => find.byType(TextField).at(0);
Finder get campoApellido449 => find.byType(TextField).at(1);
Finder get botonEmpezar449 => find.widgetWithText(FilledButton, 'Empezar entrevista');
Finder get botonVolver449 => find.widgetWithText(OutlinedButton, 'Volver');

/// Lleva la hoja al [estado]. El guardado «en curso» de `r04Guardando` se libera solo al terminar.
Future<ResultadoConQuien> llegarA449(
  WidgetTester tester,
  Estado449 estado, {
  Size tamano = t412x915,
  double escala = 1,
}) async {
  switch (estado) {
    case Estado449.r04:
      return montar449(tester, tamano: tamano, escala: escala);
    case Estado449.r04ErrorNombre:
      final r = await montar449(tester, tamano: tamano, escala: escala);
      await tester.ensureVisible(botonEmpezar449);
      await tester.pump();
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      return r;
    case Estado449.r04Guardando:
      final compuerta = Completer<void>();
      addTearDown(() {
        if (!compuerta.isCompleted) compuerta.complete();
      });
      final r = await montar449(
        tester,
        repo: PersonaRepositorioFalso(compuerta: compuerta),
        tamano: tamano,
        escala: escala,
      );
      await tester.enterText(campoNombre449, 'Pedro');
      await tester.enterText(campoApellido449, 'Gómez');
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.pump();
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      return r;
    case Estado449.r04Falla:
      final r = await montar449(
        tester,
        repo: PersonaRepositorioFalso(resultados: [fallaDeGuardado]),
        tamano: tamano,
        escala: escala,
      );
      await tester.enterText(campoNombre449, 'Pedro');
      await tester.enterText(campoApellido449, 'Gómez');
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.pump();
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      return r;
    case Estado449.c07:
      return montar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
        saldos: SaldosFalsos({'p0': 120000}),
        tamano: tamano,
        escala: escala,
      );
    case Estado449.c07Muchas:
      return montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            for (var i = 0; i < 30; i++)
              clienteDePersonas(
                'm$i',
                'María de los Ángeles ${'Nombre' * 3}$i',
                apellido: 'Fernández de la Peña y Gómez-Ibáñez',
                minutos: i,
              ),
          ]),
        saldos: SaldosFalsos({'m0': 120000, 'm1': 5}),
        tamano: tamano,
        escala: escala,
      );
    case Estado449.cargando:
      return montar449(tester, repo: PersonaRepositorioTardio(), tamano: tamano, escala: escala);
    case Estado449.errorDeLectura:
      return montar449(
        tester,
        repo: PersonaRepositorioQueFallaN(99),
        tamano: tamano,
        escala: escala,
      );
  }
}

/// Una captura PNG de la raíz en `.dart_tool/qa_capturas/449_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar449(WidgetTester tester, String nombre) async {
  if (!conCapturas449) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz449));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/449_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// «360x640_x2.0».
String sufijo449(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';
