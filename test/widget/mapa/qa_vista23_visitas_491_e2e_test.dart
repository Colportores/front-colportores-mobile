// QA de #491, de punta a punta: la hoja de la casa con la lista «Visitas agendadas» leída de la base
// real (Drift en memoria, `ConsultaAgendaRepositoryDrift.observarDeLaCasa`). El implementador probó la
// hoja con un lector falso; acá se prueba la consulta de verdad: solo las programadas de esta casa y de
// este colportor, de la más temprana a la más tardía, sin las de un depto o una casa de baja, con la
// persona de baja «sin nombre», y viva (agendar, cancelar, dar de baja y reactivar la actualizan).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/consulta_agenda_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart'
    show abrirDetalleDeAgendaProvider;
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/visitas_agendadas_de_la_casa.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/logger_mudo.dart';

Future<void> _esperarBase(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  final jueves = DateTime(2026, 10, 8, 14, 30);
  final sabado = DateTime(2026, 10, 10, 12, 30);

  Agenda agenda(
    String id,
    DateTime cuando, {
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    DateTime? borrada,
  }) => Agenda(
    id: id,
    espacioId: espacio,
    espacioPersonaId: vinculo,
    tipo: tipo,
    fechaProgramada: cuando.toUtc(),
    estado: estado,
    colportorId: colportor,
    auditoria: auditoriaDe(borrada: borrada),
  );

  Future<void> persona(String id, String nombre, {String apellido = '', DateTime? baja}) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: nombre,
          apellido: Value(apellido),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(baja),
        ),
      );

  Future<void> armar(WidgetTester tester) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await tester.runAsync(() async {
      await sembrarCasa(db);
      await persona('per-1', 'María', apellido: 'Fernández');
    });
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesHojaCasa(agendas: ConsultaAgendaRepositoryDrift(db)),
          abrirDetalleDeAgendaProvider.overrideWithValue((_) async => null),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(
            body: HojaCasa(
              item: itemDeLaHoja(id: 'ub-1'),
              ahora: ahoraLista,
              alCerrar: () {},
              colportorId: 'col-1',
            ),
          ),
        ),
      ),
    );
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

  Finder filas() => find.byType(FilaVisitaAgendada);

  prueba('la base real: solo las programadas de la casa y del colportor, en orden', (tester) async {
    await armar(tester);
    await tester.runAsync(() async {
      await sembrarUbicacion(db, id: 'ub-2');
      await sembrarEspacio(db, id: 'esp-otra', ubicacionId: 'ub-2');
      await insertarAgenda(db, agenda('cob', sabado, tipo: TipoAgenda.cobranza));
      await insertarAgenda(db, agenda('ent', jueves));
      await insertarAgenda(db, agenda('cumplida', jueves, estado: EstadoAgenda.cumplida));
      await insertarAgenda(db, agenda('cancelada', jueves, estado: EstadoAgenda.cancelada));
      await insertarAgenda(db, agenda('borrada', jueves, borrada: DateTime.utc(2026, 10, 2)));
      await insertarAgenda(db, agenda('ajena', jueves, colportor: 'col-2'));
      await insertarAgenda(db, agenda('otra-casa', jueves, espacio: 'esp-otra', vinculo: null));
    });
    await montar(tester);

    expect(filas(), findsNWidgets(2));
    final ent = tester.getTopLeft(find.byKey(ClavesVisitasAgendadas.fila('ent'))).dy;
    final cob = tester.getTopLeft(find.byKey(ClavesVisitasAgendadas.fila('cob'))).dy;
    expect(ent, lessThan(cob), reason: 'la entrevista del jueves va antes que la cobranza');
    expect(find.text('María Fernández'), findsNWidgets(2));
    expect(find.text('JUE 08/10 · 14:30'), findsOneWidget);
    expect(find.text('SÁB 10/10 · 12:30'), findsOneWidget);
  });

  prueba('cancelar o cumplir una visita la saca; agendar otra la suma, sin reabrir la hoja', (
    tester,
  ) async {
    await armar(tester);
    await tester.runAsync(() => insertarAgenda(db, agenda('ent', jueves)));
    await montar(tester);
    expect(filas(), findsOneWidget);

    await tester.runAsync(
      () => insertarAgenda(db, agenda('cob', sabado, tipo: TipoAgenda.cobranza)),
    );
    await _esperarBase(tester);
    expect(filas(), findsNWidgets(2));

    await tester.runAsync(
      () => (db.update(db.agendas)..where((a) => a.id.equals('ent'))).write(
        AgendasCompanion(estado: Value(EstadoAgenda.cancelada.codigo)),
      ),
    );
    await _esperarBase(tester);
    expect(filas(), findsOneWidget);
    expect(find.text('Cobranza'), findsOneWidget);

    await tester.runAsync(
      () => (db.update(db.agendas)..where((a) => a.id.equals('cob'))).write(
        AgendasCompanion(estado: Value(EstadoAgenda.cumplida.codigo)),
      ),
    );
    await _esperarBase(tester);
    expect(find.byKey(ClavesVisitasAgendadas.seccion), findsNothing);
  });

  prueba('la casa de baja en la base oculta la lista y al reactivarla vuelve (agenda intacta)', (
    tester,
  ) async {
    await armar(tester);
    await tester.runAsync(() => insertarAgenda(db, agenda('ent', jueves)));
    await montar(tester);
    expect(filas(), findsOneWidget);

    await tester.runAsync(
      () => (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(deletedAt: Value(DateTime.utc(2026, 10, 5))),
      ),
    );
    await _esperarBase(tester);
    expect(filas(), findsNothing);

    await tester.runAsync(
      () => (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        const UbicacionesCompanion(deletedAt: Value(null)),
      ),
    );
    await _esperarBase(tester);
    expect(filas(), findsOneWidget);
    final guardada = await tester.runAsync(() => db.select(db.agendas).get());
    expect(guardada, hasLength(1));
    expect(guardada!.single.deletedAt, isNull);
  });

  prueba('un depto de baja se lleva solo su visita; el otro depto del edificio se queda', (
    tester,
  ) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await tester.runAsync(() async {
      await sembrarEdificio(db);
      await persona('per-1', 'María', apellido: 'Fernández');
      await persona('per-2', 'Luis', apellido: 'Pérez');
      await insertarAgenda(db, agenda('d1', jueves));
      await insertarAgenda(db, agenda('d2', sabado, espacio: 'esp-2', vinculo: 'ep-2'));
    });
    await montar(tester);
    expect(filas(), findsNWidgets(2));
    expect(find.text('María Fernández · Depto 1A'), findsOneWidget);

    await tester.runAsync(
      () => (db.update(db.espacios)..where((e) => e.id.equals('esp-1'))).write(
        EspaciosCompanion(deletedAt: Value(DateTime.utc(2026, 10, 5))),
      ),
    );
    await _esperarBase(tester);
    expect(filas(), findsOneWidget);
    expect(find.byKey(ClavesVisitasAgendadas.fila('d2')), findsOneWidget);
  });

  prueba('la persona de baja sale sin nombre y la persona sin apellido no deja un espacio', (
    tester,
  ) async {
    await armar(tester);
    await tester.runAsync(() async {
      await persona('per-ana', 'Ana');
      await sembrarVinculo(db, id: 'ep-ana', personaId: 'per-ana');
      await insertarAgenda(db, agenda('ent', jueves));
      await insertarAgenda(db, agenda('ana', sabado, vinculo: 'ep-ana', tipo: TipoAgenda.cobranza));
    });
    await montar(tester);
    expect(find.text('Ana'), findsOneWidget, reason: 'sin apellido no queda «Ana » con espacio');

    await tester.runAsync(
      () => (db.update(db.personas)..where((p) => p.id.equals('per-1'))).write(
        PersonasCompanion(deletedAt: Value(DateTime.utc(2026, 10, 5))),
      ),
    );
    await _esperarBase(tester);
    expect(filas(), findsNWidgets(2), reason: 'la cita sigue, sin persona');
    expect(find.text('María Fernández'), findsNothing);
  });
}
