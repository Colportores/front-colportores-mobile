// Arnés de los tests de QA de la vista 21 «Jornada sin cerrar» (A08, #250): monta
// `CorregirJornadaPage` empujada sobre otra ruta —igual que `JornadaPage._finalizar`— con el
// almacenamiento en memoria y el reloj en la mano del test, y deja la hoja de hora a un paso.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/corregir_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final sesionQa = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

/// Lunes 21/09/2026 18:00: la jornada que quedó abierta en casi todos los casos.
final inicioQa = DateTime(2026, 9, 21, 18);

/// Martes 22/09/2026 08:00: de las 18:01 a las 06:00 del martes (12 h después del inicio).
final ahoraQa = DateTime(2026, 9, 22, 8);

JornadaModel jornadaAbiertaQa([DateTime? inicio]) {
  final i = inicio ?? inicioQa;
  return JornadaModel.fromEntity(
    Jornada(
      id: 'jor-previa',
      colportorId: sesionQa.usuarioId,
      inicio: i,
      auditoria: Auditoria(createdAt: i, updatedAt: i, createdBy: sesionQa.usuarioId),
    ),
  );
}

/// El almacenamiento en memoria de la app con perillas para «guardando» y «falla».
final class DataSourceQa implements JornadaLocalDataSource {
  DataSourceQa({Iterable<JornadaModel>? iniciales})
    : _real = JornadaLocalDataSourceEnMemoria(iniciales: iniciales ?? [jornadaAbiertaQa()]);

  final JornadaLocalDataSourceEnMemoria _real;

  /// Si no es `null`, el cierre espera a que se complete (estado «cerrando»).
  Completer<void>? demoraFinalizar;
  Object? errorAlFinalizar;

  /// Cuántos cierres llegaron al almacenamiento (un doble toque no debe sumar dos).
  int escrituras = 0;

  List<JornadaModel> get jornadas => _real.jornadas;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) => _real.obtenerActiva(colportorId);

  @override
  Future<void> insertar(JornadaModel jornada) => _real.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) async {
    escrituras++;
    if (demoraFinalizar case final demora?) await demora.future;
    if (errorAlFinalizar case final error?) throw error;
    return _real.finalizar(jornada);
  }
}

final class BackupQa implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// Lo que devolvió `Navigator.pop` al salir de la pantalla.
final class ResultadoQa {
  Jornada? valor;
  bool recibido = false;
}

/// Escala de texto que el test puede subir a mitad de camino sin perder el estado armado.
final class EscalaQa {
  EscalaQa([this.valor = 1]);
  double valor;
}

final raizCapturaQa = GlobalKey();
final navegadorQa = GlobalKey<NavigatorState>();

/// Tamaños lógicos de la matriz de QA (360x640 el chico y 412x915 el grande).
const telefonoChicoQa = Size(360, 640);
const telefonoGrandeQa = Size(412, 915);

void fijarPantallaQa(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> montarQa(
  WidgetTester tester,
  DataSourceQa dataSource, {
  EscalaQa? escala,
  DateTime Function()? reloj,
}) {
  final e = escala ?? EscalaQa();
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(dataSource),
        disparadorBackupProvider.overrideWithValue(BackupQa()),
        relojJornadaProvider.overrideWithValue(reloj ?? () => ahoraQa),
      ],
      child: MaterialApp(
        navigatorKey: navegadorQa,
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizCapturaQa,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(e.valor)),
            child: child!,
          ),
        ),
        home: const Scaffold(),
      ),
    ),
  );
}

Future<ResultadoQa> abrirCorregirQa(WidgetTester tester, {DateTime? inicio}) async {
  final resultado = ResultadoQa();
  unawaited(
    navegadorQa.currentState!
        .push<Jornada>(
          MaterialPageRoute(
            builder: (_) => CorregirJornadaPage(sesion: sesionQa, inicio: inicio ?? inicioQa),
          ),
        )
        .then((valor) {
          resultado
            ..valor = valor
            ..recibido = true;
        }),
  );
  await tester.pumpAndSettle();
  return resultado;
}

/// Abre la hoja de hora de «Elegir la hora».
Future<void> abrirHojaQa(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('corregir_jornada_elegir_hora')));
  await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
  await tester.pumpAndSettle();
}

/// Con la hoja abierta, pasa a «Otra hora» y escribe [texto] tal cual (los formateadores del campo
/// actúan como con el teclado). Antes vacía el campo: con el campo ya lleno (5 caracteres, sin
/// selección) el formateador de largo ignora cualquier texto más largo, como un pegado en un campo
/// lleno.
Future<void> escribirEnHojaQa(WidgetTester tester, String texto) async {
  if (find.byKey(const Key('hoja_hora_campo')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('hoja_hora_valor')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '');
  await tester.enterText(find.byKey(const Key('hoja_hora_campo')), texto);
  await tester.pumpAndSettle();
}

/// Abre la hoja, escribe [texto] y, si [confirmar], pulsa «Usar esta hora».
Future<void> elegirHoraQa(WidgetTester tester, String texto, {bool confirmar = true}) async {
  await abrirHojaQa(tester);
  await escribirEnHojaQa(tester, texto);
  if (!confirmar) return;
  await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
  await tester.pumpAndSettle();
}

FilledButton botonCerrarQa(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('corregir_jornada_cerrar')));

FilledButton botonUsarEscritaQa(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('hoja_hora_usar_escrita')));

/// Carga las fuentes del proyecto y los íconos de Material (sin ellos `flutter_test` pinta cajas).
/// Solo para capturas y medidas de geometría: con el texto antialiasado `textContrastGuideline` da
/// falsos negativos.
Future<void> cargarFuentesQa(WidgetTester tester) async {
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

/// Una captura PNG en `.dart_tool/qa_capturas/` (gitignored): nunca se commitea.
Future<void> capturarQa(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCapturaQa));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/326_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
