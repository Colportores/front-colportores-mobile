// La copia local del nombre (#243) contra la tabla real: AppDatabase en memoria.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/auth/data/datasources/sesion_usuario_local_data_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  late AppDatabase db;
  late SesionUsuarioLocalDataSource local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = SesionUsuarioLocalDataSource(db);
  });

  tearDown(() => db.close());

  test('la tabla local se llama sesion_usuario y no tiene más columnas que usuario y nombre', () {
    expect(db.sesionUsuarios.actualTableName, 'sesion_usuario');
    expect(db.sesionUsuarios.$columns.map((c) => c.name), ['usuario_id', 'nombre']);
  });

  test('sin nada guardado, leer devuelve null', () async {
    expect(await local.leer('u-1'), isNull);
  });

  test('guardar y leer: vuelve el mismo nombre, con acentos y todo', () async {
    await local.guardar('u-1', 'María Ángeles');

    expect(await local.leer('u-1'), 'María Ángeles');
  });

  test('guardar dos veces para el mismo usuario reemplaza: queda una sola fila', () async {
    await local.guardar('u-1', 'Lucía');
    await local.guardar('u-1', 'Lucía Beatriz');

    expect(await local.leer('u-1'), 'Lucía Beatriz');
    expect(await db.select(db.sesionUsuarios).get(), hasLength(1));
  });

  test('el nombre de otro usuario nunca se devuelve', () async {
    await local.guardar('u-1', 'Lucía');

    expect(await local.leer('u-2'), isNull);
  });

  test('borrar deja la tabla vacía; borrar sin nada guardado no falla', () async {
    await local.guardar('u-1', 'Lucía');
    await local.guardar('u-2', 'Ana');

    await local.borrar();
    await local.borrar();

    expect(await db.select(db.sesionUsuarios).get(), isEmpty);
  });
}
