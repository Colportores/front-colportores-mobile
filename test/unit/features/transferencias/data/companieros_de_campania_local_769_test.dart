// Los compañeros de campaña que el teléfono ya bajó (#769, «Nombres camp.»; vistas 40A·02 y 40B·01 de
// #512): el adaptador lee `campania_companiero` con la campaña en curso del colportor, contra el esquema real.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/transferencias/data/repositories/companieros_de_campania_local.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/companiero_de_campania.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  var hoy = DateTime(2026, 11, 26);
  late CompanierosDeCampaniaLocal adaptador;

  setUp(() {
    hoy = DateTime(2026, 11, 26);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    adaptador = CompanierosDeCampaniaLocal(db, () => hoy);
  });
  tearDown(() => db.close());

  Future<void> campania(
    String id, {
    String inicio = '2026-09-01',
    String? fin,
    String? nombre,
  }) => db.customStatement(
    'INSERT INTO campania (id, nombre, fecha_inicio, fecha_fin, created_at, updated_at) '
    "VALUES ('$id', '${nombre ?? 'Campaña $id'}', '$inicio', ${fin == null ? 'NULL' : "'$fin'"}, 1, 1)",
  );

  Future<void> inscripcion(String campaniaId, {String usuario = 'yo'}) => db.customStatement(
    'INSERT INTO campania_colportor (id, campania_id, usuario_id, created_at, updated_at) '
    "VALUES ('ic-$campaniaId-$usuario', '$campaniaId', '$usuario', 1, 1)",
  );

  Future<void> ciudad(String id, String nombre) => db.customStatement(
    'INSERT INTO ciudad (id, nombre, lat_centro, lon_centro, created_at, updated_at) '
    "VALUES ('$id', '$nombre', -34.9, -56.1, 1, 1)",
  );

  Future<void> companiero(
    String campaniaId,
    String usuario,
    String nombre,
    String apellido, {
    String? ciudadId,
    bool baja = false,
    String? id,
  }) => db.customStatement(
    'INSERT INTO campania_companiero (id, campania_id, usuario_id, nombre, apellido, ciudad_id, '
    'created_at, updated_at, deleted_at) '
    "VALUES ('${id ?? 'cc-$campaniaId-$usuario'}', '$campaniaId', '$usuario', '$nombre', '$apellido', "
    "${ciudadId == null ? 'NULL' : "'$ciudadId'"}, 1, 1, ${baja ? '2' : 'NULL'})",
  );

  CompanierosDeCampania lista(Either<Failure, CompanierosDeCampania> r) =>
      r.getOrElse(() => throw StateError('se esperaba la lista, vino $r'));

  test(
    'con la campaña en curso, lista a los compañeros por nombre, sin quien pregunta ni los dados de baja, '
    'con su ciudad',
    () async {
      await campania('camp-1', nombre: 'Primavera 2026');
      await inscripcion('camp-1');
      await ciudad('riv', 'Rivera');
      await companiero('camp-1', 'yo', 'Lucía', 'Gómez');
      await companiero('camp-1', 'u-2', 'Juan', 'Pérez', ciudadId: 'riv');
      await companiero('camp-1', 'u-3', 'Ana', 'Silva');
      await companiero('camp-1', 'u-4', 'Baja', 'De la campaña', baja: true);

      final r = lista(await adaptador.listar('yo'));

      expect(r.campania, 'Primavera 2026');
      expect(r.companieros, const [
        CompanieroDeCampania(id: 'u-3', nombre: 'Ana Silva'),
        CompanieroDeCampania(id: 'u-2', nombre: 'Juan Pérez', lugar: 'Rivera'),
      ]);
    },
  );

  test(
    'una persona con dos filas se muestra una sola vez y los de otra campaña no aparecen',
    () async {
      await campania('camp-1');
      await campania('camp-0', inicio: '2025-01-01', fin: '2025-12-31');
      await inscripcion('camp-1');
      await companiero('camp-1', 'u-2', 'Juan', 'Pérez');
      await companiero('camp-1', 'u-2', 'Juan', 'Pérez', id: 'cc-repetida');
      await companiero('camp-0', 'u-9', 'Vieja', 'Campaña');

      final r = lista(await adaptador.listar('yo'));

      expect(r.companieros.map((c) => c.id), ['u-2']);
    },
  );

  test('con más de una campaña en curso toma la que empezó última', () async {
    await campania('camp-a', inicio: '2026-03-01');
    await campania('camp-b', inicio: '2026-10-01', nombre: 'Primavera');
    await inscripcion('camp-a');
    await inscripcion('camp-b');
    await companiero('camp-a', 'u-2', 'Vieja', 'Campaña');
    await companiero('camp-b', 'u-3', 'Nueva', 'Campaña');

    final r = lista(await adaptador.listar('yo'));

    expect(r.campania, 'Primavera');
    expect(r.companieros.map((c) => c.id).toList(), ['u-3']);
  });

  test('campaña en curso pero sin compañeros: la lista vacía (40A·09), no un error', () async {
    await campania('camp-1');
    await inscripcion('camp-1');

    final r = lista(await adaptador.listar('yo'));

    expect(r.companieros, isEmpty);
  });

  test(
    'sin campaña en curso (o terminada) no hay de dónde sacar la lista: no disponibles',
    () async {
      expect(
        await adaptador.listar('yo'),
        const Left<Failure, CompanierosDeCampania>(FailureCompanierosNoDisponibles()),
      );

      await campania('camp-1', inicio: '2026-01-01', fin: '2026-06-30');
      await inscripcion('camp-1');
      await companiero('camp-1', 'u-2', 'Juan', 'Pérez');

      expect((await adaptador.listar('yo')).isLeft(), isTrue);
    },
  );

  test(
    'el día de Montevideo manda: el último día de la campaña todavía cuenta, el siguiente no',
    () async {
      await campania('camp-1', fin: '2026-11-26');
      await inscripcion('camp-1');
      await companiero('camp-1', 'u-2', 'Juan', 'Pérez');

      expect((await adaptador.listar('yo')).isRight(), isTrue);

      hoy = DateTime(2026, 11, 27);
      expect((await adaptador.listar('yo')).isLeft(), isTrue);
    },
  );

  test('si la base falla devuelve «no disponibles» en vez de tirar', () async {
    await db.close();

    expect((await adaptador.listar('yo')).isLeft(), isTrue);
    // El tearDown vuelve a cerrar: cerrar dos veces es inocuo en drift.
  });
}
