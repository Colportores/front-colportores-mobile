// La nota de la entrevista en curso, cifrada en la base local («Nota entrev.», 25/10; #450): queda
// como fila `nota` de la visita que se va a guardar, y la visita la reemplaza con el texto final.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/borrador_de_nota_de_entrevista_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late BorradorDeNotaDeEntrevistaDrift borrador;
  final ahora = DateTime.utc(2026, 10, 23, 14, 30);

  Future<void> guardar(String texto, {String notaId = 'not-1'}) => borrador.guardar(
    notaId: notaId,
    visitaId: 'vis-1',
    colportorId: 'col-1',
    texto: texto,
    ahora: ahora,
  );

  Future<List<NotaFila>> notas() => db.select(db.notas).get();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    borrador = BorradorDeNotaDeEntrevistaDrift(db);
  });
  tearDown(() => db.close());

  test('sin nada guardado, no hay texto', () async {
    expect(await borrador.leer('not-1'), '');
  });

  test('guarda la nota como la de la visita que se va a crear, local-only', () async {
    await guardar('perro suelto, tocar timbre');

    final fila = (await notas()).single;
    expect(fila.id, 'not-1');
    expect(fila.targetType, TipoObjetivoNota.visita);
    expect(fila.targetId, 'vis-1');
    expect(fila.createdBy, 'col-1');
    expect(await borrador.leer('not-1'), 'perro suelto, tocar timbre');
  });

  test('escribir de nuevo actualiza la misma fila, no suma otra', () async {
    await guardar('perro');
    await guardar('perro suelto');

    expect((await notas()).single.texto, 'perro suelto');
  });

  test('en blanco borra el borrador: no queda una nota vacía', () async {
    await guardar('perro');

    await guardar('   ');

    expect(await notas(), isEmpty);
    expect(await borrador.leer('not-1'), '');
  });

  test('borrar solo toca la nota de esa entrevista', () async {
    await guardar('perro', notaId: 'not-1');
    await guardar('gato', notaId: 'not-2');

    await borrador.borrar('not-1');

    expect(await borrador.leer('not-1'), '');
    expect(await borrador.leer('not-2'), 'gato');
  });

  test('la visita reemplaza al borrador con el texto final: una sola nota, la última', () async {
    await sembrarCasa(db);
    await guardar('borrador viejo');
    final encolador = EncoladorSyncEnMemoria();
    final datos = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );

    await datos.registrarVisita(visitaDe('vis-1'), nota: notaDe('not-1', texto: 'texto final'));

    final filas = await notas();
    expect(filas, hasLength(1));
    expect(filas.single.texto, 'texto final');
    expect(filas.single.targetId, 'vis-1');
  });
}
