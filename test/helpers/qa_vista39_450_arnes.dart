// Arnés de la QA de #450 (vista 39: R·05 «Entrevista en curso», R·06 «Terminó la entrevista» y R·07
// «Sin inicio registrado», más el aviso fijo sobre el mapa): monta el recorrido con las fuentes reales
// del proyecto, a cada tamaño y escala de letra, y lleva la pantalla hasta cada estado del canvas.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/aviso_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/flujo_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrevista_falsos.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los teléfonos de la matriz de la QA: el del diseño (360×640) y el grande (412×915).
const tamanos39 = [Size(360, 640), Size(412, 915)];
const escalas39 = [1.0, 2.0];

/// Cada artboard del canvas 39 que cubre #450 (R·05, R·06, R·07) y sus variantes de estado.
enum Estado39 {
  r05('R·05 entrevista en curso'),
  r05Nota('R·05 con la nota abierta y escrita'),
  r06('R·06 horas y ¿hubo venta? (salida de ahora)'),
  r06PideSalida('R·06 pide la salida (la app se cerró con la entrevista abierta)'),
  r07('R·07 sin inicio registrado (entrada de la visita anterior)'),
  r07SinVisita('R·07 sin inicio ni visita anterior (pide la entrada)'),
  r06Error('R·06 no se pudo guardar'),
  r06Guardando('R·06 guardando'),
  avisoFijo('aviso fijo arriba del mapa');

  const Estado39(this.rotulo);

  final String rotulo;

  String get id => name;
}

bool _fuentesCargadas = false;

/// `false` solo para la guía de contraste de Flutter: lee los colores de la captura y con las
/// fuentes reales da falsos negativos; con las cajas de Ahem lee el color de verdad.
bool usarFuentesReales = true;

/// Sin las fuentes del proyecto `flutter_test` pinta cajas (Ahem) y las medidas no son las reales.
Future<void> cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

final llave = GlobalKey();
final abrir = find.byKey(const Key('qa_abrir'));
final terminar = find.byKey(const Key('qa_terminar'));
final terminarPidiendo = find.byKey(const Key('qa_terminar_pidiendo'));
final sinInicio = find.byKey(const Key('qa_sin_inicio'));

/// Lo que dejó el recorrido: lo último que devolvió el flujo.
final class Recorrido {
  Recorrido(this.montaje);

  final MontajeEntrevista montaje;
  SalidaTerminoEntrevista? salida;
  var devolvio = false;
  late ProviderContainer contenedor;
}

/// Monta el recorrido (el aviso fijo y un botón por entrada al flujo) a [tamano] y [escala].
Future<Recorrido> montar(
  WidgetTester tester, {
  MontajeEntrevista? montaje,
  Size tamano = const Size(360, 640),
  double escala = 1,
  bool conAviso = true,
}) async {
  await cargarFuentes(tester);
  final r = Recorrido(montaje ?? MontajeEntrevista());
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Future<void> corre(Future<SalidaTerminoEntrevista?> Function() flujo) async {
    r.devolvio = false;
    r.salida = await flujo();
    r.devolvio = true;
  }

  await tester.pumpWidget(
    RepaintBoundary(
      key: llave,
      child: ProviderScope(
        overrides: r.montaje.overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                r.contenedor = ProviderScope.containerOf(context);
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      if (conAviso) const AvisoEntrevistaEnCurso(colportorId: 'col-1'),
                      ElevatedButton(
                        key: const Key('qa_abrir'),
                        onPressed: () =>
                            corre(() => FlujoEntrevista.abrir(context, ref, colportorId: 'col-1')),
                        child: const Text('abrir'),
                      ),
                      ElevatedButton(
                        key: const Key('qa_terminar'),
                        onPressed: () => corre(
                          () => FlujoEntrevista.terminar(context, ref, colportorId: 'col-1'),
                        ),
                        child: const Text('terminar'),
                      ),
                      ElevatedButton(
                        key: const Key('qa_terminar_pidiendo'),
                        onPressed: () => corre(
                          () => FlujoEntrevista.terminar(
                            context,
                            ref,
                            colportorId: 'col-1',
                            pedirSalida: true,
                          ),
                        ),
                        child: const Text('terminar pidiendo'),
                      ),
                      ElevatedButton(
                        key: const Key('qa_sin_inicio'),
                        onPressed: () => corre(
                          () => FlujoEntrevista.terminarSinInicio(
                            context,
                            ref,
                            colportorId: 'col-1',
                            espacioPersonaId: 'ep-1',
                            direccion: 'Grecia 3307',
                            persona: 'Pedro Gómez',
                          ),
                        ),
                        child: const Text('sin inicio'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return r;
}

Future<void> tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// La entrevista empezó a las 14:23 de esta sesión y ahora son las 14:41 (no se pide la salida).
Future<void> empezadaEnEstaSesion(WidgetTester tester, Recorrido r) async {
  r.montaje.reloj = () => inicioEntrevista;
  await r.contenedor
      .read(entrevistaEnCursoProvider('col-1').notifier)
      .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
  r.montaje.reloj = () => ahoraEntrevista;
  await tester.pumpAndSettle();
}

/// Lleva la pantalla hasta [estado] a [tamano] y [escala].
Future<Recorrido> llegar(
  WidgetTester tester,
  Estado39 estado, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  MontajeEntrevista? montaje,
}) async {
  final m = montaje ?? MontajeEntrevista();
  switch (estado) {
    case Estado39.r05 || Estado39.r05Nota || Estado39.r06PideSalida || Estado39.avisoFijo:
      await m.almacen.guardar(entrevistaDePrueba());
    case Estado39.r07:
      m.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
    case _:
  }
  final r = await montar(tester, montaje: m, tamano: tamano, escala: escala);
  switch (estado) {
    case Estado39.avisoFijo:
      break;
    case Estado39.r05:
      await tocar(tester, abrir);
    case Estado39.r05Nota:
      await tocar(tester, abrir);
      await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
      await tester.enterText(
        find.byKey(ClavesEntrevista.campoNota),
        'perro suelto, tocar timbre dos veces; volver con la esposa después de las seis',
      );
      await tester.pumpAndSettle();
    case Estado39.r06 || Estado39.r06Error || Estado39.r06Guardando:
      await empezadaEnEstaSesion(tester, r);
      await tocar(tester, abrir);
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      if (estado == Estado39.r06Error) {
        m.agenda.falla = const FailureInesperado();
        await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));
      } else if (estado == Estado39.r06Guardando) {
        m.agenda.compuerta = Completer<void>();
        await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
        await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
    case Estado39.r06PideSalida:
      await tocar(tester, terminarPidiendo);
    case Estado39.r07 || Estado39.r07SinVisita:
      await tocar(tester, sinInicio);
  }
  return r;
}

/// R·05 abierta de una entrevista empezada en esta sesión (a las 14:23; ahora son las 14:41).
Future<Recorrido> enCursoEnEstaSesion(
  WidgetTester tester, {
  Size tamano = const Size(360, 640),
  double escala = 1,
}) async {
  final r = await montar(tester, tamano: tamano, escala: escala);
  await empezadaEnEstaSesion(tester, r);
  await tocar(tester, abrir);
  return r;
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// La pantalla completa como PNG, solo con `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(llave));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa450_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String nombreDeCelda(Estado39 e, Size t, double escala) =>
    '${e.id}_${t.width.toInt()}x${t.height.toInt()}_x${escala.toStringAsFixed(0)}';
