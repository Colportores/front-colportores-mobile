// Cada verificación semanal del backup queda en el `audit_log` local (HU-SYNC-009), sin contenido.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/respaldo/data/datasources/auditoria_backup_local.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AuditoriaBackupLocal auditoria;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    auditoria = AuditoriaBackupLocal(db);
  });
  tearDown(() => db.close());

  test('sin verificaciones, no hay una última', () async {
    expect(await auditoria.ultimaVerificacion(), isNull);
  });

  test('una verificación sin problemas queda como «ok», sin motivo', () async {
    await auditoria.registrar(cuando: DateTime.utc(2026, 11, 2, 22), hayProblema: false);

    final fila = (await db.select(db.auditLogLocal).get()).single;
    expect(fila.evento, EventoAuditoriaLocal.backupIntegridadOk);
    expect(fila.uuid, EventoAuditoriaLocal.uuidBackup);
    expect(fila.motivo, isNull);
  });

  test('con problemas, deja sus nombres ordenados y nada más', () async {
    await auditoria.registrar(
      cuando: DateTime.utc(2026, 11, 2, 22),
      hayProblema: true,
      problemas: {'corrupt', 'brokenLink'},
    );

    final fila = (await db.select(db.auditLogLocal).get()).single;
    expect(fila.evento, EventoAuditoriaLocal.backupIntegridadProblema);
    expect(fila.motivo, 'brokenLink,corrupt');
  });

  test('la última es la más reciente, salga bien o mal, y no mira otros eventos', () async {
    await auditoria.registrar(cuando: DateTime.utc(2026, 10, 20), hayProblema: false);
    await auditoria.registrar(cuando: DateTime.utc(2026, 11, 2, 22), hayProblema: true);
    await auditoria.registrar(cuando: DateTime.utc(2026, 10, 27), hayProblema: false);
    await db
        .into(db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.clickToCall,
            uuid: 'per-1',
            creadoEn: DateTime.utc(2026, 12, 1),
          ),
        );

    expect(await auditoria.ultimaVerificacion(), DateTime.utc(2026, 11, 2, 22));
  });
}
