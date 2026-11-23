// Arnés de los tests de QA de #386 (PR #758, «términos de uso» del registro): abridor y monitor de
// conectividad falsos, montaje del registro, fuentes reales y capturas PNG a `.dart_tool/qa_capturas/`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/services/abridor_de_pagina.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/abridor_de_pagina_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'db_local_repository_en_memoria.dart';

const conCapturas386 = bool.fromEnvironment('QA_CAPTURAS');

const avisoSinConexion386 = 'Necesitás conexión para leer los términos.';

/// Texto que fijó la «Decisión del agente de decisiones (23/11)» del issue #386 (P1 del archivo de
/// pendientes): pisa al texto propuesto por el implementador.
const avisoDecidido386 =
    'No pudimos abrir los términos. Podés leerlos en colportores.github.io/terminos/v1';

final raiz386 = GlobalKey();

final class AbridorFalso386 implements AbridorDePagina {
  final List<Uri> abiertas = [];
  bool resultado = true;
  Object? falla;
  Completer<void>? demora;

  @override
  Future<bool> abrir(Uri direccion) async {
    abiertas.add(direccion);
    await demora?.future;
    if (falla case final f?) throw f;
    return resultado;
  }
}

final class MonitorFalso386 implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => const Stream<TipoConexion>.empty();
}

Future<void> cargarFuentes386(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
}

Future<void> capturar386(WidgetTester tester, String nombre) async {
  if (!conCapturas386) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz386));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/386_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> montar386(
  WidgetTester tester, {
  required Size tamanio,
  required AbridorFalso386 abridor,
  required MonitorFalso386 monitor,
  double escala = 1,
  bool lectorDePantalla = false,
  AuthRemoteDataSourceEnMemoria? remote,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          remote ?? AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        abridorDePaginaProvider.overrideWithValue(abridor),
        monitorConectividadProvider.overrideWithValue(monitor),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raiz386,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(escala),
              accessibleNavigation: lectorDePantalla,
            ),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_registro'),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const RegistroPage())),
                child: const Text('pantalla anterior'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir_registro')));
  await tester.pumpAndSettle();
}

Future<void> tocarEnlace386(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('registro_terminos')));
  await tester.pump();
  await tester.tapOnText(find.textRange.ofSubstring('términos de uso'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String textoDe386(WidgetTester tester, String clave) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(Key(clave)), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Iterable<SemanticsNode> nodos386(SemanticsNode raiz) sync* {
  yield raiz;
  final hijos = <SemanticsNode>[];
  raiz.visitChildren((h) {
    hijos.add(h);
    return true;
  });
  for (final h in hijos) {
    yield* nodos386(h);
  }
}
