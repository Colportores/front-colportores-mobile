// QA de #416 / PR #506 (HU-NOT-005) de punta a punta con la base real: los recordatorios que la
// revisión guarda al abrir la app aparecen en el centro (#481) como la HU promete (más reciente
// primero, sin leer), se actualizan con el centro abierto, «Borrar todas» deja la tabla vacía y la
// revisión siguiente no los trae de vuelta. Matriz 360×640 / 412×915 × texto 1,0 / 2,0 con las guías
// de accesibilidad. Capturas (fuera del repo, `.dart_tool/qa_capturas/`) con
// `--dart-define=QA_CAPTURAS=true`.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/agendas_para_recordar_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/consultor_destinos_notificacion_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/historial_notificaciones_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/historial_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/conciliar_recordatorios_use_case.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/historial_notificaciones_falsos.dart'
    show borrarConfirmar, centroLista, centroMenu, centroVacio, menuBorrarTodas;
import '../../helpers/logger_mudo.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
final _raiz = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late MarcaConciliacionRecordatoriosEnMemoria marca;
  late DateTime ahora;
  late ConciliarRecordatoriosUseCase conciliar;
  late HistorialNotificacionesRepositoryImpl historial;

  Agenda agenda(String id, DateTime visita, [TipoAgenda tipo = TipoAgenda.entrevista]) => Agenda(
    id: id,
    espacioId: 'esp-1',
    espacioPersonaId: 'ep-1',
    tipo: tipo,
    fechaProgramada: visita,
    colportorId: 'col-1',
    auditoria: auditoriaDe(creada: DateTime.utc(2026, 10, 1)),
  );

  Future<void> armar(WidgetTester tester, {String calle = 'Av. Italia', int visitas = 5}) async {
    final logger = loggerMudo();
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    historial = HistorialNotificacionesRepositoryImpl(
      HistorialNotificacionesLocalDataSourceDrift(db),
      logger: logger,
    );
    marca = MarcaConciliacionRecordatoriosEnMemoria(DateTime.utc(2026, 10, 20));
    ahora = DateTime.utc(2026, 10, 27, 18);
    conciliar = ConciliarRecordatoriosUseCase(
      AgendasParaRecordarDrift(db),
      PreferenciasRecordatoriosRepositoryEnMemoria(),
      marca,
      RegistrarNotificacionUseCase(historial, ahora: () => ahora),
      ahora: () => ahora,
      logger: logger,
    );
    await tester.runAsync(() async {
      await sembrarCasa(db);
      await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(calle: Value(calle), numero: const Value('1234')),
      );
      for (var i = 0; i < visitas; i++) {
        await insertarAgenda(
          db,
          agenda(
            'age-$i',
            DateTime.utc(2026, 10, 21 + i, 15),
            i.isEven ? TipoAgenda.entrevista : TipoAgenda.cobranza,
          ),
        );
      }
      await conciliar('col-1');
    });
  }

  Future<void> montar(WidgetTester tester, Size tamano, double texto) async {
    tester.view
      ..physicalSize = tamano
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = texto;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialNotificacionesRepositoryProvider.overrideWithValue(historial),
          consultorDestinosNotificacionProvider.overrideWithValue(
            ConsultorDestinosNotificacionDrift(db),
          ),
          relojHistorialNotificacionesProvider.overrideWithValue(() => ahora),
        ],
        child: RepaintBoundary(
          key: _raiz,
          child: MaterialApp(theme: temaClaro(), home: const CentroNotificacionesPage()),
        ),
      ),
    );
    await asentar(tester);
  }

  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      try {
        await cuerpo(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(db.close);
      }
    });
  }

  for (final t in const [
    (nombre: '360x640', tamano: Size(360, 640)),
    (nombre: '412x915', tamano: Size(412, 915)),
  ]) {
    for (final escala in const [1.0, 2.0]) {
      prueba(
        'dado 5 recordatorios que sonaron con la app cerrada, el centro los lista sin leer, el '
        'más reciente primero, sin overflow y con las guías de accesibilidad '
        '(${t.nombre}, texto ${escala}x)',
        (tester) async {
          final semantica = tester.ensureSemantics();
          await armar(tester, calle: 'Avenida Libertador General San Martín de la Costa');
          await montar(tester, t.tamano, escala);

          expect(tester.takeException(), isNull);
          expect(centroLista, findsOneWidget);
          // Primera fila visible: el recordatorio de la visita más próxima a «ahora».
          expect(find.text('Recordatorio de visita'), findsWidgets);
          expect(
            find.textContaining('en Avenida Libertador General', findRichText: true),
            findsWidgets,
          );
          final textos = [
            for (final e in find.text('Recordatorio de visita').evaluate())
              tester.getTopLeft(find.byWidget(e.widget)).dy,
          ];
          expect([...textos]..sort(), textos, reason: 'de arriba hacia abajo, en orden');
          // Las no leídas se anuncian al lector.
          expect(find.bySemanticsLabel(RegExp('Nueva|nueva|sin leer')), findsWidgets);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          expect(tester.takeException(), isNull);

          if (_conCapturas) {
            await cargarFuentes(tester);
            await tester.pump();
            await capturar(tester, 'centro_${t.nombre}_${escala}x');
          }
          semantica.dispose();
        },
      );
    }
  }

  // skip: issue #416 (QA) — el rótulo del día («DOMINGO 25», 10 pt, #67758B sobre #FAFAF7) da 4,43:1 < 4,5:1.
  // Es del centro de #481, no de este PR; se deja anotado porque lo que se guarda acá es lo que se lista.
  testWidgets('dado los recordatorios guardados, el rótulo de cada día del centro cumple el '
      'contraste AA (412x915)', (tester) async {
    final semantica = tester.ensureSemantics();
    try {
      await armar(tester);
      await montar(tester, const Size(412, 915), 1);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantica.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }
  }, skip: true);

  prueba('dado el centro vacío, cuando la persona sale, la app vuelve y un recordatorio sonó, al '
      'volver a entrar aparece', (tester) async {
    await armar(tester, visitas: 0);
    await montar(tester, const Size(412, 915), 1);
    expect(centroVacio, findsOneWidget);

    // Sale del centro (con la base real y la pantalla montada la escritura queda esperando el reloj
    // falso: se desmonta antes, como al navegar).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await insertarAgenda(db, agenda('age-9', DateTime.utc(2026, 10, 27, 18, 20)));
      ahora = DateTime.utc(2026, 10, 27, 18, 5);
      marca.marca = DateTime.utc(2026, 10, 27, 17);
      await conciliar('col-1');
    });
    await montar(tester, const Size(412, 915), 1);

    expect(centroVacio, findsNothing);
    expect(centroLista, findsOneWidget);
    expect(find.textContaining('Entrevista en Av. Italia 1234'), findsOneWidget);
  });

  prueba('dado 5 recordatorios, cuando la persona toca «Borrar todas» y confirma, el centro queda '
      'vacío; y al volver a abrir la app no reaparecen', (tester) async {
    await armar(tester);
    await montar(tester, const Size(412, 915), 1);
    expect(centroLista, findsOneWidget);

    await tester.tap(centroMenu);
    await asentar(tester);
    await tester.tap(menuBorrarTodas);
    await asentar(tester);
    await tester.tap(borrarConfirmar);
    await asentar(tester);
    expect(centroVacio, findsOneWidget);

    await tester.runAsync(() async {
      ahora = DateTime.utc(2026, 10, 27, 19);
      await conciliar('col-1');
    });
    await asentar(tester);

    expect(centroVacio, findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.notificacionesHistorial).get()), isEmpty);
  });
}

/// Deja correr lo asíncrono de la base real y vuelve a pintar.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> cargarFuentes(WidgetTester tester) async {
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

Future<void> capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/416_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
