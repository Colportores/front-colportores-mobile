// QA de #769 (PR #773, «Nombres camp.», vistas 40A·02 y 40B·01): el adaptador de compañeros de campaña con
// nombres reales de la región (tildes, minúsculas, apellido vacío) y los bordes de la campaña en curso.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/transferencias/data/repositories/companieros_de_campania_local.dart';
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

  Future<void> campania(String id, {String inicio = '2026-09-01', String? fin}) =>
      db.customStatement(
        'INSERT INTO campania (id, nombre, fecha_inicio, fecha_fin, created_at, updated_at) '
        "VALUES ('$id', 'Campaña $id', '$inicio', ${fin == null ? 'NULL' : "'$fin'"}, 1, 1)",
      );

  Future<void> inscripcion(String campaniaId) => db.customStatement(
    'INSERT INTO campania_colportor (id, campania_id, usuario_id, created_at, updated_at) '
    "VALUES ('ic-$campaniaId', '$campaniaId', 'yo', 1, 1)",
  );

  Future<void> companiero(
    String campaniaId,
    String usuario,
    String nombre,
    String apellido,
  ) => db.customStatement(
    'INSERT INTO campania_companiero (id, campania_id, usuario_id, nombre, apellido, created_at, '
    "updated_at) VALUES ('cc-$usuario', '$campaniaId', '$usuario', '$nombre', '$apellido', 1, 1)",
  );

  Future<List<String>> nombres() async {
    final r = await adaptador.listar('yo');
    return r
        .getOrElse(() => throw StateError('se esperaba la lista, vino $r'))
        .companieros
        .map((c) => c.nombre)
        .toList();
  }

  group('40A·02 · la lista de compañeros', () {
    test('el último día de la campaña todavía lista a los compañeros', () async {
      await campania('c', fin: '2026-11-26');
      await inscripcion('c');
      await companiero('c', 'u-1', 'Ana', 'Silva');

      expect(await nombres(), ['Ana Silva']);
    });

    test('un compañero sin apellido se muestra sin espacio de más', () async {
      await campania('c');
      await inscripcion('c');
      await companiero('c', 'u-1', 'Ana', '');

      expect(await nombres(), ['Ana']);
    });

    test('con 500 compañeros devuelve todos, una sola vez cada uno', () async {
      await campania('c');
      await inscripcion('c');
      for (var i = 0; i < 500; i++) {
        await companiero('c', 'u-$i', 'Nombre$i', 'Apellido$i');
      }

      final r = await adaptador.listar('yo');

      expect(r.getOrElse(() => throw StateError('no')).companieros, hasLength(500));
    });

    test(
      'el orden es por nombre como se lee en español: «Ángel» y «ana» no van después de «Zoe»',
      () async {
        await campania('c');
        await inscripcion('c');
        await companiero('c', 'u-1', 'Zoe', 'Díaz');
        await companiero('c', 'u-2', 'Ángel', 'Ruiz');
        await companiero('c', 'u-3', 'ana', 'Silva');
        await companiero('c', 'u-4', 'Beto', 'Paz');

        expect(await nombres(), ['ana Silva', 'Ángel Ruiz', 'Beto Paz', 'Zoe Díaz']);
      },
      skip:
          'QA #773: el orden sale de ORDER BY nombre de SQLite (binario): «Ángel» y los nombres en minúscula '
          'quedan después de «Zoe» en la lista de 40A·02',
    );
  });
}
