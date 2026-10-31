// HU-SYNC-006 (#175) — Lo que el asistente ve en la base: si es un teléfono sin datos y cuánto trajo
// la recuperación.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/respaldo/data/datasources/lector_de_lo_recuperado_drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

Future<void> _sembrarJornada(AppDatabase db) {
  final t = DateTime.utc(2026, 10, 22, 12);
  return db
      .into(db.jornadas)
      .insert(
        JornadasCompanion.insert(
          id: 'j-1',
          colportorId: 'u-1',
          inicio: t,
          createdAt: t,
          updatedAt: t,
        ),
      );
}

void main() {
  late AppDatabase db;
  late LectorDeLoRecuperadoDrift lector;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    lector = LectorDeLoRecuperadoDrift(() => db);
  });

  tearDown(() => db.close());

  test('una base recién creada es un teléfono sin datos', () async {
    expect(await lector.baseSinDatos(), isTrue);
    final r = await lector.resumen();
    expect((r.ubicaciones, r.personas, r.ventas, r.cobros), (0, 0, 0, 0));
  });

  test('sin base abierta, lanza: nunca se afirma que no hay nada sin haber mirado', () async {
    final sinBase = LectorDeLoRecuperadoDrift(() => null);

    await expectLater(sinBase.baseSinDatos(), throwsStateError);
    await expectLater(sinBase.resumen(), throwsStateError);
  });

  test('una jornada guardada ya no es un teléfono sin datos', () async {
    await _sembrarJornada(db);

    expect(await lector.baseSinDatos(), isFalse);
  });

  test('el resumen cuenta lo que la persona reconoce: las dadas de baja no suman, pero la base '
      'con una baja ya no es un teléfono sin datos', () async {
    await sembrarUbicacion(db);
    await sembrarUbicacion(db, id: 'ub-2');
    await sembrarUbicacion(db, id: 'ub-3', borrada: DateTime.utc(2026, 10, 23));
    final t = DateTime.utc(2026, 10, 1);
    await db
        .into(db.personas)
        .insert(PersonasCompanion.insert(id: 'per-1', nombre: 'Ana', createdAt: t, updatedAt: t));

    final r = await lector.resumen();

    expect((r.ubicaciones, r.personas, r.ventas, r.cobros), (2, 1, 0, 0));
    expect(await lector.baseSinDatos(), isFalse);
  });

  test('lee la base de ahora: si la recuperación la reemplaza, ve la nueva', () async {
    var actual = db;
    final cambiante = LectorDeLoRecuperadoDrift(() => actual);
    expect(await cambiante.baseSinDatos(), isTrue);

    final otra = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    addTearDown(otra.close);
    await _sembrarJornada(otra);
    actual = otra;

    expect(await cambiante.baseSinDatos(), isFalse);
  });
}
