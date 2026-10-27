// Arnés de los tests de QA de las notas del lugar en la hoja de la casa arriba (vista 39, C·05, #447,
// PR #493): lleva la hoja real, con el enganche de `main.dart`, a cada estado que una persona puede ver
// de la pestaña «Notas» y de lo que se abre desde ella, y saca capturas.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/447_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/notas_lugar_arnes.dart';
import '../widget/mapa/personas_arnes.dart' show contextoActivo;
import 'hoja_casa_falsos.dart';
import 'lista_ubicaciones_falsos.dart' show ahoraLista;
import 'nota_ubicacion_falsos.dart';
import 'persona_falsos.dart';
import 'qa_vista39_445_arnes.dart' show contextoC02;

export '../widget/mapa/notas_lugar_arnes.dart'
    show asentarLugar, escribirYGuardarLugar, borrarPorMenuLugar, abrirOpcionesLugar;
export 'qa_baja_205_arnes.dart' show cargarFuentes205;
export 'qa_vista39_445_arnes.dart' show t360x640, t412x915, t320x568;

const conCapturas447 = bool.fromEnvironment('QA_CAPTURAS');

final raizCaptura447 = GlobalKey();

/// Los textos del canvas C·05.
const textoCanvas1 = 'Perro suelto: tocar timbre y esperar.';
const textoCanvas2 = 'Mejor después de las 18.';

/// Las dos notas del canvas C·05 (05/10 y 03/10), del lugar `u-1` de la hoja.
List<NotaUbicacion> notasC05() => [
  notaDeLugar('c1', textoCanvas1, ubicacionId: 'u-1', creada: DateTime(2026, 10, 5, 9)),
  notaDeLugar('c2', textoCanvas2, ubicacionId: 'u-1', creada: DateTime(2026, 10, 3, 18)),
];

/// Lo que un test necesita después de montar la hoja.
final class Montaje447 {
  Montaje447(this.repo);

  final NotaUbicacionRepositorioFalso repo;
}

Future<Montaje447> montarHoja447(
  WidgetTester tester, {
  NotaUbicacionRepositorioFalso? repo,
  List<NotaUbicacion>? notas,
  String? colportorId = 'col-1',
  bool esBaja = false,
  double escala = 1,
  Size tamano = const Size(412, 915),
  bool irANotas = true,
}) async {
  final r = repo ?? NotaUbicacionRepositorioFalso(notas: [...(notas ?? const [])]);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(lectura: (_) => Stream.value(contextoC02)),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contextoActivo()),
        ),
        fichaDePersonaDesdeLaCasaProvider.overrideWithValue(null),
        pestanaHistorialDeLaCasaProvider.overrideWithValue(null),
        pestanaNotasDeLaCasaProvider.overrideWithValue(
          (context, contexto) => PestanaNotasDeLaCasa(
            ubicacionId: contexto.ubicacionId,
            colportorId: contexto.colportorId,
            soloLectura: contexto.esBaja,
          ),
        ),
        ...overridesLugar(r),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: raizCaptura447, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: esBaja ? itemDeLaHoja(baja: DateTime(2026, 10, 1)) : itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: colportorId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await asentarLugar(tester);
  if (irANotas) {
    await tester.ensureVisible(find.byKey(ClavesHojaCasa.pestana('notas')));
    await tester.pump();
    await tester.tap(find.byKey(ClavesHojaCasa.pestana('notas')));
    await asentarLugar(tester);
  }
  return Montaje447(r);
}

/// Una captura PNG de lo que se ve en `.dart_tool/qa_capturas/447_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar447(WidgetTester tester, String nombre) async {
  if (!conCapturas447) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/447_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String sufijo447(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

/// Los estados de la pestaña «Notas» (y de lo que se abre desde ella) que una persona puede alcanzar.
enum Estado447 {
  c05Canvas,
  vacio,
  cargando,
  errorAlLeer,
  sesentaNotas,
  nota5000,
  palabraLarga,
  conBorradas,
  dadaDeBaja,
  sinSesion,
  avisoBorrada,
  avisoFallaAlBorrar,
  avisoGuardada,
  opcionesDeLaNota,
  formularioNuevo,
  formularioConFalla,
  formularioNotaLarga,
  borradasDelLugar,
  borradasSoloLectura,
}

Future<Montaje447> llegarA447(
  WidgetTester tester,
  Estado447 estado, {
  Size tamano = const Size(412, 915),
  double escala = 1,
}) async {
  Future<Montaje447> m({
    NotaUbicacionRepositorioFalso? repo,
    List<NotaUbicacion>? notas,
    String? colportorId = 'col-1',
    bool esBaja = false,
  }) => montarHoja447(
    tester,
    repo: repo,
    notas: notas,
    colportorId: colportorId,
    esBaja: esBaja,
    tamano: tamano,
    escala: escala,
  );

  switch (estado) {
    case Estado447.c05Canvas:
      return m(notas: notasC05());
    case Estado447.vacio:
      return m();
    case Estado447.cargando:
      return m(repo: NotaUbicacionRepositorioCargando());
    case Estado447.errorAlLeer:
      return m(repo: NotaUbicacionRepositorioQueFallaUnaVez(notas: notasC05()));
    case Estado447.sesentaNotas:
      return m(
        notas: [
          for (var i = 0; i < 60; i++)
            notaDeLugar(
              'n$i',
              'Nota número ${i + 1} del lugar.',
              ubicacionId: 'u-1',
              creada: DateTime(2026, 9, 1).add(Duration(hours: i)),
            ),
        ],
      );
    case Estado447.nota5000:
      return m(
        notas: [
          notaDeLugar('l', '${'Portón verde, timbre roto. ' * 190}FIN', ubicacionId: 'u-1'),
          ...notasC05(),
        ],
      );
    case Estado447.palabraLarga:
      return m(
        notas: [
          notaDeLugar(
            'p',
            'Clave: ${'A1B2C3D4' * 40} 😀👍🏽 ${'ñandú' * 30}',
            ubicacionId: 'u-1',
            creada: DateTime(2026, 10, 22, 14, 20),
          ),
          ...notasC05(),
        ],
      );
    case Estado447.conBorradas:
      return m(
        notas: [
          ...notasC05(),
          notaDeLugar(
            'b1',
            'Una que borré',
            ubicacionId: 'u-1',
            creada: DateTime(2026, 9, 30, 10),
            borrada: DateTime(2026, 10, 1),
          ),
          notaDeLugar(
            'b2',
            'Otra que borré',
            ubicacionId: 'u-1',
            creada: DateTime(2026, 9, 29, 10),
            borrada: DateTime(2026, 10, 1),
          ),
        ],
      );
    case Estado447.dadaDeBaja:
      return m(notas: notasC05(), esBaja: true);
    case Estado447.sinSesion:
      return m(notas: notasC05(), colportorId: null);
    case Estado447.avisoBorrada:
      final r = await m(notas: notasC05());
      await borrarPorMenuLugar(tester, 'c1');
      return r;
    case Estado447.avisoFallaAlBorrar:
      final repo = NotaUbicacionRepositorioFalso(notas: notasC05())
        ..resultados['borrar'] = [const FailureInesperado(causa: 'x')];
      final r = await m(repo: repo);
      await borrarPorMenuLugar(tester, 'c1');
      return r;
    case Estado447.avisoGuardada:
      final r = await m(notas: notasC05());
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      await escribirYGuardarLugar(tester, 'Casa de esquina, portón azul.');
      return r;
    case Estado447.opcionesDeLaNota:
      final r = await m(notas: notasC05());
      await abrirOpcionesLugar(tester, 'c1');
      return r;
    case Estado447.formularioNuevo:
      final r = await m(notas: notasC05());
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      return r;
    case Estado447.formularioConFalla:
      final repo = NotaUbicacionRepositorioFalso(notas: notasC05())
        ..resultados['agregar'] = [const FailureInesperado(causa: 'x')];
      final r = await m(repo: repo);
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      await escribirYGuardarLugar(tester, 'Esta no se guardó 😀');
      return r;
    case Estado447.formularioNotaLarga:
      final r = await m(notas: notasC05());
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      await tester.enterText(find.byKey(ClavesNotas.campo), 'x' * 6000);
      await asentarLugar(tester);
      return r;
    case Estado447.borradasDelLugar:
    case Estado447.borradasSoloLectura:
      final r = await m(
        notas: [
          ...notasC05(),
          notaDeLugar(
            'b1',
            'Una que borré',
            ubicacionId: 'u-1',
            creada: DateTime(2026, 9, 30, 10),
            borrada: DateTime(2026, 10, 1),
          ),
          notaDeLugar(
            'b2',
            'Otra que borré',
            ubicacionId: 'u-1',
            creada: DateTime(2026, 9, 29, 10),
            borrada: DateTime(2026, 10, 1),
          ),
        ],
        esBaja: estado == Estado447.borradasSoloLectura,
      );
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.verBorradas));
      await tester.tap(find.byKey(ClavesNotasDelLugar.verBorradas));
      await asentarLugar(tester);
      return r;
  }
}
