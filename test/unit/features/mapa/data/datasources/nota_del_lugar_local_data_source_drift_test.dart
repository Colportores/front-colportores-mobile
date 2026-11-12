// La nota más reciente del lugar (vista 39, C·01) contra la tabla real `nota`: AppDatabase en memoria.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_del_lugar_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 24, 12);

  late AppDatabase db;
  late NotaDelLugarLocalDataSourceDrift local;

  Future<void> insertar(
    String id, {
    String tipo = TipoObjetivoNota.ubicacion,
    String objetivo = 'ub-1',
    String texto = 'Perro suelto: tocar timbre y esperar.',
    int minutos = 0,
    DateTime? borrada,
  }) => db
      .into(db.notas)
      .insert(
        NotasCompanion.insert(
          id: id,
          targetType: tipo,
          targetId: objetivo,
          texto: texto,
          createdAt: t0.add(Duration(minutes: minutos)),
          updatedAt: t0.add(Duration(minutes: minutos)),
          deletedAt: Value(borrada),
        ),
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = NotaDelLugarLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  test('sin ninguna nota, emite null', () async {
    expect(await local.observarMasReciente('ub-1').first, isNull);
  });

  test('con varias notas del lugar, emite la más reciente', () async {
    await insertar('n-1', texto: 'Vieja', minutos: 1);
    await insertar('n-2', texto: 'Nueva', minutos: 5);
    await insertar('n-3', texto: 'Media', minutos: 3);

    final nota = await local.observarMasReciente('ub-1').first;

    expect(nota, isNotNull);
    expect(nota!.id, 'n-2');
    expect(nota.texto, 'Nueva');
    expect(nota.creadaEl, t0.add(const Duration(minutes: 5)));
  });

  test('a igual instante gana el id mayor (UUID v7: el más nuevo)', () async {
    await insertar('n-a', texto: 'Primera');
    await insertar('n-b', texto: 'Segunda');

    expect((await local.observarMasReciente('ub-1').first)!.id, 'n-b');
  });

  test('no mezcla las notas de una persona, de otra ubicación ni las dadas de baja', () async {
    await insertar('n-persona', tipo: TipoObjetivoNota.persona, texto: 'De una persona');
    await insertar('n-otra', objetivo: 'ub-2', texto: 'De otra casa');
    await insertar('n-baja', texto: 'Borrada', minutos: 9, borrada: t0);
    await insertar('n-ok', texto: 'La buena', minutos: 1);

    expect((await local.observarMasReciente('ub-1').first)!.id, 'n-ok');
  });

  test('si todas las notas del lugar están dadas de baja, emite null', () async {
    await insertar('n-baja', borrada: t0);

    expect(await local.observarMasReciente('ub-1').first, isNull);
  });

  test('al agregar una nota nueva, vuelve a emitir con ella', () async {
    await insertar('n-1', texto: 'Primera', minutos: 1);
    final emitidas = <NotaDelLugar?>[];
    final suscripcion = local.observarMasReciente('ub-1').listen(emitidas.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();

    await insertar('n-2', texto: 'Segunda', minutos: 2);
    await pumpEventQueue();

    expect(emitidas.map((n) => n?.texto), ['Primera', 'Segunda']);
  });
}
