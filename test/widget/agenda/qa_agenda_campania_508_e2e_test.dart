// QA de #508, de punta a punta: la pestaña «Agenda» real sobre la base real (Drift en memoria) con
// la campaña bajada por el pull. «Cumplidas» mira la campaña (no las de antes de que empiece), «Ver
// más» suma la segunda página, y la casa dada de baja se lleva su agenda de la lista y la devuelve al
// reactivarse, sin tocar la agenda guardada.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/consulta_agenda_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/replica_de_campanias.dart';

Future<void> _esperarBase(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  Agenda agenda(String id, DateTime cuando, {EstadoAgenda estado = EstadoAgenda.cumplida}) =>
      Agenda(
        id: id,
        espacioId: 'esp-1',
        espacioPersonaId: 'ep-1',
        tipo: TipoAgenda.entrevista,
        fechaProgramada: cuando.toUtc(),
        estado: estado,
        colportorId: 'col-1',
        auditoria: auditoriaDe(),
      );

  Future<void> armar(WidgetTester tester, int cuantas) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await tester.runAsync(() async {
      await sembrarCasa(db);
      await ReplicaDeCampanias(db).bajar({
        'campania': [filaCampania('cam-1', 'Verano', inicio: '2026-10-01', fin: '2027-02-28')],
        'campania_colportor': [filaInscripcion('ins-1', campania: 'cam-1')],
      });
      // `cuantas` cumplidas dentro de la campaña (una por hora, hacia atrás desde ayer) y una de
      // antes de que empiece.
      for (var i = 0; i < cuantas; i++) {
        await insertarAgenda(
          db,
          agenda(
            'k${i.toString().padLeft(3, '0')}',
            DateTime(2026, 10, 27, 20).subtract(Duration(hours: i * 9)),
          ),
        );
      }
      await insertarAgenda(db, agenda('antes', DateTime(2026, 9, 20, 12)));
    });
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 30000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaRepositoryDrift(db)),
          relojAgendaProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
        ),
      ),
    );
    await _esperarBase(tester);
    await tester.tap(find.text('Pendientes ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agenda_estado_cumplidas')));
    await tester.tap(find.byKey(const Key('agenda_aplicar_estado')));
    await tester.pumpAndSettle();
    await _esperarBase(tester);
  }

  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    });
  }

  int filas(WidgetTester tester) => tester.widgetList(find.byType(FilaAgenda)).length;

  Future<void> casa({required bool deBaja}) =>
      (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(deletedAt: Value(deBaja ? DateTime.utc(2026, 10, 28, 9) : null)),
      );

  prueba(
    '«Cumplidas» trae la campaña (no la de antes de empezar) y «Ver más» suma la segunda página',
    (tester) async {
      await armar(tester, 55);
      await montar(tester);

      expect(find.text('En esta campaña'), findsOneWidget);
      expect(filas(tester), 50);
      expect(find.byKey(const Key('agenda_ver_mas')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda_ver_mas')));
      await _esperarBase(tester);
      // 55 de la campaña: la de septiembre (antes del 1/10) no entra.
      expect(filas(tester), 55);
      expect(find.byKey(const Key('agenda_ver_mas')), findsNothing);
    },
  );

  prueba('la casa de baja se lleva su agenda de la lista y la devuelve al reactivarse', (
    tester,
  ) async {
    await armar(tester, 5);
    await montar(tester);
    expect(filas(tester), 5);

    await tester.runAsync(() => casa(deBaja: true));
    await _esperarBase(tester);
    expect(filas(tester), 0);
    expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);

    await tester.runAsync(() => casa(deBaja: false));
    await _esperarBase(tester);
    expect(filas(tester), 5);

    // La agenda nunca se tocó: sigue guardada y cumplida.
    final guardada = await tester.runAsync(() => db.select(db.agendas).get());
    expect(guardada, hasLength(6));
    expect(guardada!.every((a) => a.deletedAt == null), isTrue);
  });
}
