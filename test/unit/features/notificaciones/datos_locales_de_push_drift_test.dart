// HU-NOT-003 (#187) — lo que la base local aporta al texto de una push, contra la tabla real.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/datos_locales_de_push_repository_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../helpers/logger_mudo.dart';

final _t = DateTime.utc(2026, 11, 1, 12);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DatosLocalesDePushRepositoryDrift repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = DatosLocalesDePushRepositoryDrift(db);
  });
  tearDown(() => db.close());

  Future<void> campania(String id, String nombre) => db
      .into(db.campanias)
      .insert(
        CampaniasCompanion.insert(
          id: id,
          nombre: nombre,
          fechaInicio: '2026-11-01',
          createdAt: _t,
          updatedAt: _t,
        ),
      );

  Future<void> zona(String id, String nombre) => db
      .into(db.zonas)
      .insert(
        ZonasCompanion.insert(
          id: id,
          nombre: nombre,
          campaniaCiudadId: 'cc-1',
          tipoForma: 'ESQUINAS',
          poligonoGeojson: const {'type': 'Polygon'},
          createdAt: _t,
          updatedAt: _t,
        ),
      );

  Future<void> agenda(String id, DateTime cuando, {String estado = 'PROGRAMADA', DateTime? baja}) =>
      db
          .into(db.agendas)
          .insert(
            AgendasCompanion.insert(
              id: id,
              espacioId: 'esp-1',
              tipo: 'ENTREVISTA',
              fechaProgramada: cuando,
              colportorId: 'col-1',
              estado: Value(estado),
              deletedAt: Value(baja),
              createdAt: _t,
              updatedAt: _t,
            ),
          );

  test('el nombre de una campaña y de una zona que están en el teléfono; null si no', () async {
    await campania('camp-1', '  Verano 2027 ');
    await zona('z-1', 'Cerro Norte');

    expect(await repo.nombreDeCampania('camp-1'), 'Verano 2027');
    expect(await repo.nombreDeZona('z-1'), 'Cerro Norte');
    expect(await repo.nombreDeCampania('otra'), isNull);
    expect(await repo.nombreDeZona('otra'), isNull);
  });

  test('un nombre en blanco cuenta como sin nombre', () async {
    await campania('camp-1', '   ');

    expect(await repo.nombreDeCampania('camp-1'), isNull);
  });

  test('las visitas de mañana: solo programadas, vivas y del día local siguiente', () async {
    final ahora = DateTime(2026, 11, 9, 21, 30);
    await agenda('hoy', DateTime(2026, 11, 9, 23, 59).toUtc());
    await agenda('m1', DateTime(2026, 11, 10, 0, 0).toUtc());
    await agenda('m2', DateTime(2026, 11, 10, 23, 59).toUtc());
    await agenda('m-cancelada', DateTime(2026, 11, 10, 10).toUtc(), estado: 'CANCELADA');
    await agenda('m-cumplida', DateTime(2026, 11, 10, 11).toUtc(), estado: 'CUMPLIDA');
    await agenda('m-baja', DateTime(2026, 11, 10, 12).toUtc(), baja: _t);
    await agenda('pasado', DateTime(2026, 11, 11, 0, 0).toUtc());

    expect(await repo.visitasProgramadasParaManana(ahora), 2);
  });

  test('sin visitas mañana, 0', () async {
    expect(await repo.visitasProgramadasParaManana(DateTime(2026, 11, 9)), 0);
  });
}
