// QA de la ficha de una persona (vista 32B, HU-UBI-009, #141, PR #563) de punta a punta con la base real:
// la pantalla (real), el repositorio y la fuente de Drift en memoria (con la tabla de auditoría local).
// Los tests del PR prueban la pantalla con un repositorio falso y Drift sin pantalla; estos prueban que
// lo que una persona ve sale de las tablas, se mantiene al día y que «Llamar» no deja el número en la
// auditoría. También mide el criterio «los datos cargan en < 500 ms desde la DB local».
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ficha_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ficha_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_ficha_persona_563_arnes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  Future<void> sembrarPersona({String id = 'per-1', String telefono = '099123456'}) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: 'María',
          apellido: const Value('Pérez'),
          telefono: Value(telefono),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> sembrarVenta(String id, {DateTime? fecha}) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: 'ep-1',
          numeroTalonario: '0042',
          montoTotal: 120000,
          fecha: fecha ?? DateTime.utc(2026, 10, 12, 14),
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> armar(WidgetTester tester, {void Function()? antes}) async {
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      await sembrarCasa(db);
      await sembrarPersona();
    });
  }

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  testWidgets('3 visitas y 1 venta salen de las tablas, con el teléfono enmascarado', (
    tester,
  ) async {
    await armar(tester);
    await tester.runAsync(() async {
      for (var i = 1; i <= 3; i++) {
        await insertarVisita(db, visitaDe('vis-$i', creada: DateTime.utc(2026, 10, i, 14)));
      }
      await sembrarVenta('ven-1');
    });
    final mundo = MundoFicha();
    await montarFichaConRepo563(
      tester,
      mundo,
      FichaPersonaRepositoryImpl(FichaPersonaLocalDataSourceDrift(db)),
    );
    await esperar(tester);

    expect(find.text('María Pérez'), findsOneWidget);
    expect(find.text('+598 99 *** 456'), findsOneWidget);
    expect(find.byKey(ClavesFicha.fila('ven-1')), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      expect(find.byKey(ClavesFicha.fila('vis-$i')), findsOneWidget);
    }
    await cerrar(tester);
  });

  testWidgets('una visita nueva en la base aparece sin reabrir la ficha', (tester) async {
    await armar(tester);
    final mundo = MundoFicha();
    await montarFichaConRepo563(
      tester,
      mundo,
      FichaPersonaRepositoryImpl(FichaPersonaLocalDataSourceDrift(db)),
    );
    await esperar(tester);
    expect(find.byKey(ClavesFicha.hero), findsOneWidget);

    await tester.runAsync(() => insertarVisita(db, visitaDe('vis-nueva')));
    await esperar(tester);

    expect(find.byKey(ClavesFicha.fila('vis-nueva')), findsOneWidget);
    expect(find.byKey(ClavesFicha.hero), findsNothing);
    await cerrar(tester);
  });

  testWidgets(
    '«Llamar» deja `click_to_call` con el id de la persona y sin el número en ninguna columna',
    (tester) async {
      await armar(tester);
      await tester.runAsync(() => insertarVisita(db, visitaDe('vis-1')));
      final mundo = MundoFicha();
      await montarFichaConRepo563(
        tester,
        mundo,
        FichaPersonaRepositoryImpl(FichaPersonaLocalDataSourceDrift(db)),
      );
      await esperar(tester);

      await tester.tap(find.byKey(ClavesFicha.botonLlamar));
      await esperar(tester);

      final filas = (await tester.runAsync(() => db.select(db.auditLogLocal).get()))!;
      expect(filas, hasLength(1));
      expect(filas.single.evento, 'click_to_call');
      expect(filas.single.uuid, 'per-1');
      expect(filas.single.toString(), isNot(contains('123456')));
      expect(filas.single.toString(), isNot(contains('099')));
      expect(mundo.marcador.numeros, ['099123456']);
      await cerrar(tester);
    },
  );

  test(
    'criterio «los datos cargan en < 500 ms»: 3 visitas y 1 venta, y también 2.000 movimientos',
    () async {
      final base = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      db = base;
      await sembrarCasa(db);
      await sembrarPersona();
      for (var i = 1; i <= 3; i++) {
        await insertarVisita(db, visitaDe('vis-$i', creada: DateTime.utc(2026, 10, i, 14)));
      }
      await sembrarVenta('ven-1');
      final fuente = FichaPersonaLocalDataSourceDrift(db);

      final reloj = Stopwatch()..start();
      final lectura = (await fuente.observar('per-1').first)!;
      reloj.stop();
      expect(lectura.historial, hasLength(4));
      expect(reloj.elapsedMilliseconds, lessThan(500));

      await db.batch((b) {
        b.insertAll(db.visitas, [
          for (var i = 0; i < 2000; i++)
            VisitasCompanion.insert(
              id: 'masiva-$i',
              espacioId: 'esp-1',
              espacioPersonaId: const Value('ep-1'),
              fecha: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
              tipoResultado: TipoResultadoVisita.entrevista.codigo,
              colportorId: 'col-1',
              createdAt: t0,
              updatedAt: t0,
            ),
        ]);
      });
      final reloj2 = Stopwatch()..start();
      final grande = (await fuente.observar('per-1').first)!;
      reloj2.stop();
      expect(grande.historial, hasLength(2004));
      expect(reloj2.elapsedMilliseconds, lessThan(500));
      await db.close();
    },
  );
}
