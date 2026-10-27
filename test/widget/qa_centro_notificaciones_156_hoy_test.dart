// QA de la campana en el encabezado de Hoy y del recorrido completo (#156, PR #481): Hoy → campana →
// centro → atrás, con la pantalla real (`InicioPage`) a 360x640 y 412x915, texto 1.0 y 2.0; y el
// mismo recorrido sobre la tabla real (Drift en memoria) para que lo leído y lo borrado se vea en
// la campana. Capturas con `--dart-define=QA_CAPTURAS=true`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/consultor_destinos_notificacion_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/historial_notificaciones_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/historial_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';
import '../helpers/logger_mudo.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/qa_centro_notificaciones_156_arnes.dart';
import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

final _campana = find.byKey(const Key('inicio_notificaciones'));
final _numero = find.byKey(const Key('inicio_notificaciones_numero'));

Future<void> _montar(
  WidgetTester tester,
  List<Override> overridesCentro, {
  required Tamano tam,
  double escala = 1,
}) async {
  tester.view
    ..physicalSize = Size(tam.ancho, tam.alto)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => ahoraDelCentro),
        ...overridesPestanaMapa(),
        ...overridesCentro,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa156_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('la campana en el encabezado de Hoy', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        for (final sinLeer in [0, 7, 120]) {
          testWidgets(
            'con $sinLeer sin leer · ${tam.nombre} · texto ${escala}x: la campana y el engranaje '
            'caben, se tocan y no desbordan',
            (tester) async {
              final avisos = [
                for (var i = 0; i < sinLeer; i++) aviso('n-$i', hace: Duration(minutes: i + 1)),
              ];
              await _montar(
                tester,
                CentroArnes(avisos: avisos).overrides,
                tam: tam,
                escala: escala,
              );
              expect(tester.takeException(), isNull);
              expect(_campana, findsOneWidget);
              final c = tester.getRect(_campana);
              final g = tester.getRect(find.byKey(const Key('inicio_configuracion')));
              expect(c.width, greaterThanOrEqualTo(48));
              expect(c.height, greaterThanOrEqualTo(48));
              expect(c.overlaps(g), isFalse, reason: 'la campana no pisa al engranaje');
              expect(c.left, greaterThanOrEqualTo(0));
              expect(g.right, lessThanOrEqualTo(tam.ancho));
              if (sinLeer == 0) {
                expect(_numero, findsNothing);
              } else {
                expect(tester.widget<Text>(_numero).data, sinLeer > 99 ? '99+' : '$sinLeer');
              }
            },
          );
        }
      }
    }
  });

  group('hallazgos', () {
    for (final sinLeer in [120]) {
      testWidgets(
        'con $sinLeer sin leer a 360x640 y texto 2.0x el globo de la campana no tapa el engranaje',
        (tester) async {
          final avisos = [
            for (var i = 0; i < sinLeer; i++) aviso('n-$i', hace: Duration(minutes: i + 1)),
          ];
          await _montar(
            tester,
            CentroArnes(avisos: avisos).overrides,
            tam: tamanos.first,
            escala: 2,
          );
          final globo = tester.getRect(_numero);
          final engranaje = tester.getRect(
            find.descendant(
              of: find.byKey(const Key('inicio_configuracion')),
              matching: find.byType(Icon),
            ),
          );
          expect(
            globo.inflate(4).overlaps(engranaje),
            isFalse,
            reason: 'el globo $globo pisa el engranaje $engranaje',
          );
        },
        // skip: QA #156: a 360x640 y texto 2.0x el globo «99+» de la campana tapa el engranaje.
        skip: !_hallazgos,
      );
    }
  });

  testWidgets(
    'recorrido: Hoy → campana → leer un aviso → marcar todas → atrás: el número baja y la campana '
    'queda sola; al reentrar lo leído sigue leído',
    (tester) async {
      final arnes = CentroArnes(avisos: cincoDelCanvas());
      await _montar(tester, arnes.overrides, tam: tamanos.first);
      expect(tester.widget<Text>(_numero).data, '3');

      await tester.tap(_campana);
      await tester.pumpAndSettle();
      expect(centroPagina, findsOneWidget);
      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
      expect(arnes.abridor.abiertos, hasLength(1));

      await tester.tap(find.byKey(const Key('centro_atras')));
      await tester.pumpAndSettle();
      expect(centroPagina, findsNothing);
      expect(tester.widget<Text>(_numero).data, '2');

      await tester.tap(_campana);
      await tester.pumpAndSettle();
      expect(find.text('Nueva'), findsNWidgets(2), reason: 'lo leído sigue leído');
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('centro_atras')));
      await tester.pumpAndSettle();
      expect(_numero, findsNothing);
    },
  );

  group('sobre la tabla real (Drift en memoria)', () {
    Future<(AppDatabase, HistorialNotificacionesRepositoryImpl, List<Override>)> abrir() async {
      final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      final repo = HistorialNotificacionesRepositoryImpl(
        HistorialNotificacionesLocalDataSourceDrift(db),
        logger: loggerMudo(),
      );
      for (final n in cincoDelCanvas()) {
        await repo.registrar(n, ahora: ahoraDelCentro);
      }
      return (
        db,
        repo,
        <Override>[
          historialNotificacionesRepositoryProvider.overrideWithValue(repo),
          consultorDestinosNotificacionProvider.overrideWithValue(
            ConsultorDestinosNotificacionDrift(db),
          ),
          relojHistorialNotificacionesProvider.overrideWithValue(() => ahoraDelCentro),
        ],
      );
    }

    Future<void> cerrar(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }

    testWidgets('marcar todas y borrar todas dejan la tabla y la campana de acuerdo', (
      tester,
    ) async {
      final (db, _, overrides) = await abrir();
      await _montar(tester, overrides, tam: tamanos.first);
      expect(tester.widget<Text>(_numero).data, '3');

      await tester.tap(_campana);
      await tester.pumpAndSettle();
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();
      expect(find.text('Nueva'), findsNothing);
      final sinLeer = await tester.runAsync(
        () => (db.select(db.notificacionesHistorial)..where((t) => t.leidaEn.isNull())).get(),
      );
      expect(sinLeer, isEmpty);

      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuBorrarTodas);
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar las 5 notificaciones?'), findsOneWidget);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();
      expect(centroVacio, findsOneWidget);
      final filas = await tester.runAsync(() => db.select(db.notificacionesHistorial).get());
      expect(filas, isEmpty, reason: 'la tabla local queda vacía');

      await tester.tap(find.byKey(const Key('centro_atras')));
      await tester.pumpAndSettle();
      expect(_numero, findsNothing);
      await cerrar(tester, db);
    });

    testWidgets('lo que pasó de los 90 días no se ve, y abrir el centro lo purga de la tabla', (
      tester,
    ) async {
      final (db, repo, overrides) = await abrir();
      // Uno de hace 89 días entra; uno de hace 91 no. `registrar` purga, así que el viejo se mete
      // directo en la tabla.
      await repo.registrar(aviso('dia89', hace: const Duration(days: 89)), ahora: ahoraDelCentro);
      await db
          .into(db.notificacionesHistorial)
          .insert(
            NotificacionesHistorialCompanion.insert(
              id: 'dia91',
              tipo: TipoNotificacion.recordatorioVisita.codigo,
              titulo: 'Muy viejo',
              recibidaEn: ahoraDelCentro.subtract(const Duration(days: 91)),
            ),
          );
      await _montar(tester, overrides, tam: (nombre: 'alto', ancho: 390, alto: 3000));
      await tester.tap(_campana);
      await tester.pumpAndSettle();

      expect(filaDe('dia89'), findsOneWidget);
      expect(filaDe('dia91'), findsNothing);
      expect(find.text('Muy viejo'), findsNothing);
      final filas = await tester.runAsync(() => db.select(db.notificacionesHistorial).get());
      expect(filas!.map((f) => f.id), isNot(contains('dia91')), reason: 'se purgó al abrir');
      await cerrar(tester, db);
    });
  });

  group('capturas de Hoy con la campana', () {
    setUpAll(cargarTipografias);
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets('captura hoy ${tam.nombre} t${escala.toInt()}', (tester) async {
          final avisos = [
            for (var i = 0; i < 120; i++) aviso('n-$i', hace: Duration(minutes: i + 1)),
          ];
          await _montar(
            tester,
            CentroArnes(avisos: avisos).overrides,
            tam: tam,
            escala: escala,
          );
          await _foto(tester, 'hoy_${tam.nombre}_t${escala.toInt()}');
        }, skip: !conCapturas);
      }
    }
  });
}
