// Arnés de los tests de QA de la hoja de la casa arriba (vista 39, C·02, #445, PR #476): lleva la hoja a
// cada estado que una persona puede ver, en la matriz de tamaños y escalas de texto, y saca capturas.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/445_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/personas_arnes.dart' show asentar, contextoActivo;
import 'hoja_casa_falsos.dart';
import 'lista_ubicaciones_falsos.dart' show ahoraLista;
import 'persona_falsos.dart';

export 'qa_baja_205_arnes.dart' show cargarFuentes205;

const conCapturas445 = bool.fromEnvironment('QA_CAPTURAS');

const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);
const t320x568 = Size(320, 568);

final raizCaptura445 = GlobalKey();

final ana445 = clienteDePersonas('p-ana', 'Ana', apellido: 'Gómez');

/// El contexto del canvas C·02: Pedro debe $ 1.200 y Ana dio una entrevista el 05/10.
final contextoC02 = ContextoDeLaCasa(
  espacioId: 'esp-1',
  personas: [pedroGomez, ana445],
  saldosCentavos: const {'p-pedro': 120000},
  ultimaEntrevistaDe: {'p-ana': DateTime(2026, 10, 5, 12)},
  nota: notaDelCanvas,
);

ContextoDeLaCasa contextoCon(List<PersonaDelEspacio> filas, {bool nota = true}) =>
    ContextoDeLaCasa(espacioId: 'esp-1', personas: filas, nota: nota ? notaDelCanvas : null);

/// Lo que un test necesita después de montar la hoja.
final class Montaje445 {
  final cierres = <int>[];
  final visitas = <ContextoDeVisita>[];
  final cobros = <ContextoDeCobro>[];
  final fichas = <ContextoDeFicha>[];
  final repo = PersonaRepositorioFalso();
}

Future<Montaje445> montarHoja445(
  WidgetTester tester, {
  ContextoDeLaCasa? contexto,
  Stream<ContextoDeLaCasa>? lectura,
  Stream<ContextoDeLaCasa> Function()? lecturaFn,
  ItemListaUbicacion? item,
  bool arriba = true,
  String? colportorId = 'col-1',
  bool conFicha = true,
  FutureOr<void> Function(ContextoDeFicha)? ficha,
  bool conHistorial = false,
  bool conNotas = false,
  double escala = 1,
  Size tamano = t412x915,
  Montaje445? montaje,
  List<Override> otros = const [],
}) async {
  final m = montaje ?? Montaje445();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final casa = item ?? itemDeLaHoja();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(
          lectura: (_) =>
              lecturaFn != null ? lecturaFn() : (lectura ?? Stream.value(contexto ?? contextoC02)),
          registrarVisita: (c) => m.visitas.add(c),
          cobrar: (c) async => m.cobros.add(c),
        ),
        personaRepositoryProvider.overrideWithValue(m.repo),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contextoActivo()),
        ),
        fichaDePersonaDesdeLaCasaProvider.overrideWithValue(
          conFicha
              ? (c) async {
                  m.fichas.add(c);
                  if (ficha != null) await ficha(c);
                  return null;
                }
              : null,
        ),
        pestanaHistorialDeLaCasaProvider.overrideWithValue(
          conHistorial ? (context, datos) => const Text('Historial (de #446)') : null,
        ),
        pestanaNotasDeLaCasaProvider.overrideWithValue(
          conNotas ? (context, datos) => const Text('Notas (de #447)') : null,
        ),
        ...otros,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: raizCaptura445, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: casa,
              ahora: ahoraLista,
              alCerrar: () => m.cierres.add(m.cierres.length),
              arriba: arriba,
              colportorId: colportorId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return m;
}

/// Una captura PNG de lo que se ve en `.dart_tool/qa_capturas/445_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar445(WidgetTester tester, String nombre) async {
  if (!conCapturas445) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/445_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String sufijo445(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

Future<void> asentar445(WidgetTester tester) => asentar(tester);

/// Los estados de la hoja arriba que una persona puede alcanzar.
enum Estado445 {
  c02Produccion,
  c02Pestanas,
  sinPersonas,
  sesentaPersonas,
  nombresLargos,
  cargando,
  errorAlLeer,
  dadaDeBaja,
  lejos,
  fallaAlAbrirFicha,
}

PersonaDelEspacio _larga() => clienteDePersonas(
  'p-larga',
  'Maximiliano Alejandro Bartolomé',
  apellido: 'Rodríguez de la Santísima Trinidad y Tobago',
);

Future<Montaje445> llegarA445(
  WidgetTester tester,
  Estado445 estado, {
  Size tamano = t412x915,
  double escala = 1,
}) async {
  switch (estado) {
    case Estado445.c02Produccion:
      return montarHoja445(tester, tamano: tamano, escala: escala);
    case Estado445.c02Pestanas:
      return montarHoja445(
        tester,
        conHistorial: true,
        conNotas: true,
        tamano: tamano,
        escala: escala,
      );
    case Estado445.sinPersonas:
      return montarHoja445(tester, contexto: contextoCon(const []), tamano: tamano, escala: escala);
    case Estado445.sesentaPersonas:
      return montarHoja445(
        tester,
        contexto: contextoCon([
          for (var i = 0; i < 60; i++)
            clienteDePersonas('p$i', 'Persona', apellido: 'Número ${i + 1}', minutos: i),
        ]),
        tamano: tamano,
        escala: escala,
      );
    case Estado445.nombresLargos:
      return montarHoja445(
        tester,
        contexto: ContextoDeLaCasa(
          espacioId: 'esp-1',
          personas: [_larga(), ana445],
          saldosCentavos: const {'p-larga': 123456700},
        ),
        tamano: tamano,
        escala: escala,
      );
    case Estado445.cargando:
      return montarHoja445(
        tester,
        lectura: StreamController<ContextoDeLaCasa>().stream,
        tamano: tamano,
        escala: escala,
      );
    case Estado445.errorAlLeer:
      return montarHoja445(
        tester,
        lectura: Stream<ContextoDeLaCasa>.error(StateError('no se pudo leer')),
        tamano: tamano,
        escala: escala,
      );
    case Estado445.dadaDeBaja:
      return montarHoja445(
        tester,
        item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 18, 12), estado: null),
        tamano: tamano,
        escala: escala,
      );
    case Estado445.lejos:
      return montarHoja445(tester, item: itemDeLaHoja(metros: 650), tamano: tamano, escala: escala);
    case Estado445.fallaAlAbrirFicha:
      final m = await montarHoja445(
        tester,
        ficha: (_) => throw StateError('no abre'),
        tamano: tamano,
        escala: escala,
      );
      await tester.tap(find.byKey(ClavesHojaCasa.abrirPersona).last);
      await tester.pump();
      await tester.pump();
      return m;
  }
}
