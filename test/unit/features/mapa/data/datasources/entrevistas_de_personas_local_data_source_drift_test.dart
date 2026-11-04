// La última entrevista dada a cada persona (vista 39, C·02 «Entrevista dada el 05/10») contra la tabla
// real `visita`: AppDatabase en memoria.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/entrevistas_de_personas_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 5, 12);

  late AppDatabase db;
  late EntrevistasDePersonasLocalDataSourceDrift local;

  Future<void> insertar(
    String id, {
    String? vinculo = 'ep-1',
    String tipo = 'ENTREVISTA',
    int dias = 0,
    DateTime? borrada,
  }) => db
      .into(db.visitas)
      .insert(
        VisitasCompanion.insert(
          id: id,
          espacioId: 'esp-1',
          espacioPersonaId: Value(vinculo),
          fecha: t0.add(Duration(days: dias)),
          tipoResultado: tipo,
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = EntrevistasDePersonasLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  test('sin ninguna visita no hay fechas', () async {
    expect(await local.ultimaEntrevistaDe(['ep-1']), isEmpty);
  });

  test('sin vínculos no consulta nada y no devuelve nada', () async {
    expect(await local.ultimaEntrevistaDe(const []), isEmpty);
  });

  test('con varias entrevistas de una persona, devuelve la más reciente', () async {
    await insertar('v-1', dias: 1);
    await insertar('v-2', dias: 9);
    await insertar('v-3', dias: 4);

    final fechas = await local.ultimaEntrevistaDe(['ep-1']);

    expect(fechas, {'ep-1': t0.add(const Duration(days: 9))});
  });

  test(
    'solo cuenta las entrevistas: una venta, un cobro o un «No contestó» no son una entrevista',
    () async {
      await insertar('v-venta', tipo: 'VENTA', dias: 3);
      await insertar('v-cobro', tipo: 'COBRANZA', dias: 4);
      await insertar('v-no', tipo: 'NO_CONTESTO', dias: 5);
      await insertar('v-rechazo', tipo: 'RECHAZO', dias: 6);

      expect(await local.ultimaEntrevistaDe(['ep-1']), isEmpty);
    },
  );

  test('ignora las entrevistas dadas de baja y las que no tienen persona', () async {
    await insertar('v-baja', dias: 7, borrada: t0);
    await insertar('v-sin-persona', vinculo: null, dias: 8);
    await insertar('v-ok', dias: 2);

    expect(await local.ultimaEntrevistaDe(['ep-1']), {'ep-1': t0.add(const Duration(days: 2))});
  });

  test('devuelve una fecha por persona y deja afuera a quien no tuvo entrevista ni a los vínculos '
      'que no se pidieron', () async {
    await insertar('v-1', vinculo: 'ep-1', dias: 1);
    await insertar('v-2', vinculo: 'ep-2', dias: 2);
    await insertar('v-3', vinculo: 'ep-3', dias: 3);

    final fechas = await local.ultimaEntrevistaDe(['ep-1', 'ep-2', 'ep-4']);

    expect(fechas, {
      'ep-1': t0.add(const Duration(days: 1)),
      'ep-2': t0.add(const Duration(days: 2)),
    });
  });

  test('una lista larga de personas se consulta en lotes y no pierde a ninguna', () async {
    final ids = [for (var i = 0; i < 1100; i++) 'ep-$i'];
    await insertar('v-primero', vinculo: ids.first, dias: 1);
    await insertar('v-ultimo', vinculo: ids.last, dias: 2);

    final fechas = await local.ultimaEntrevistaDe(ids);

    expect(fechas.keys, unorderedEquals([ids.first, ids.last]));
  });
}
