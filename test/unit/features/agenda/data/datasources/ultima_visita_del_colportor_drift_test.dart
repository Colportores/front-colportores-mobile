// La hora de la visita anterior de una colportora (vista 39, R·07; #450), contra la tabla real
// `visita` en memoria.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/ultima_visita_del_colportor_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late UltimaVisitaDelColportorDrift ultima;

  Visita visita(
    String id, {
    required DateTime fecha,
    String colportorId = 'col-1',
    DateTime? borrada,
  }) => Visita(
    id: id,
    espacioPersonaId: 'ep-1',
    fecha: fecha,
    tipoResultado: TipoResultadoVisita.noContesto,
    colportorId: colportorId,
    auditoria: auditoriaDe(creada: fecha, borrada: borrada),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    ultima = UltimaVisitaDelColportorDrift(db);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  test('sin ninguna visita, no hay hora: nunca se inventa', () async {
    expect(await ultima.fechaAntesDe('col-1', DateTime.utc(2026, 10, 23, 15)), isNull);
  });

  test('devuelve la fecha de la última visita anterior al instante pedido', () async {
    await insertarVisita(db, visita('v1', fecha: DateTime.utc(2026, 10, 23, 13, 5)));
    await insertarVisita(db, visita('v2', fecha: DateTime.utc(2026, 10, 23, 14, 10)));
    await insertarVisita(db, visita('v3', fecha: DateTime.utc(2026, 10, 23, 14, 30)));

    expect(
      await ultima.fechaAntesDe('col-1', DateTime.utc(2026, 10, 23, 14, 20)),
      DateTime.utc(2026, 10, 23, 14, 10),
    );
  });

  test('una visita en el mismo instante no cuenta: es la de ahora, no la anterior', () async {
    await insertarVisita(db, visita('v1', fecha: DateTime.utc(2026, 10, 23, 14, 10)));

    expect(await ultima.fechaAntesDe('col-1', DateTime.utc(2026, 10, 23, 14, 10)), isNull);
  });

  test('no mira las visitas de otra colportora ni las dadas de baja', () async {
    await insertarVisita(
      db,
      visita('v1', fecha: DateTime.utc(2026, 10, 23, 14, 10), colportorId: 'col-2'),
    );
    await insertarVisita(
      db,
      visita(
        'v2',
        fecha: DateTime.utc(2026, 10, 23, 14, 5),
        borrada: DateTime.utc(2026, 10, 23, 14, 6),
      ),
    );
    await insertarVisita(db, visita('v3', fecha: DateTime.utc(2026, 10, 23, 13, 40)));

    expect(
      await ultima.fechaAntesDe('col-1', DateTime.utc(2026, 10, 23, 15)),
      DateTime.utc(2026, 10, 23, 13, 40),
    );
  });

  test('entiende un instante en hora local igual que en UTC', () async {
    await insertarVisita(db, visita('v1', fecha: DateTime.utc(2026, 10, 23, 14, 10)));

    final local = DateTime.utc(2026, 10, 23, 15).toLocal();
    expect(await ultima.fechaAntesDe('col-1', local), DateTime.utc(2026, 10, 23, 14, 10));
  });
}
