// La limpieza de las notas de persona borradas hace más de 90 días (HU-UBI-012) contra la tabla `nota`
// real: AppDatabase en memoria, mismo esquema y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_borradas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/limpieza_notas_borradas_repository_impl.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  // El «ahora» de la limpieza: el 24/01/2027 a las 14:20 UTC.
  final ahora = DateTime.utc(2027, 1, 24, 14, 20);
  final hace89 = ahora.subtract(const Duration(days: 89));
  final hace90 = ahora.subtract(const Duration(days: 90));
  final hace91 = ahora.subtract(const Duration(days: 91));

  late AppDatabase db;
  late NotasBorradasLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = NotasBorradasLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  Future<void> sembrar(
    String id, {
    String tipo = TipoObjetivoNota.persona,
    DateTime? borrada,
    String texto = 'Prefiere de tarde',
  }) => db
      .into(db.notas)
      .insert(
        NotasCompanion.insert(
          id: id,
          targetType: tipo,
          targetId: 'objetivo-1',
          texto: texto,
          createdAt: DateTime.utc(2026, 6, 1),
          updatedAt: borrada ?? DateTime.utc(2026, 6, 1),
          deletedAt: Value(borrada),
        ),
      );

  Future<void> marcarBorrada(String id, DateTime? cuando) => (db.update(
    db.notas,
  )..where((n) => n.id.equals(id))).write(NotasCompanion(deletedAt: Value(cuando)));

  Future<List<String>> ids() async => [
    for (final f in await (db.select(db.notas)..orderBy([(n) => OrderingTerm.asc(n.id)])).get())
      f.id,
  ];

  group('purgarVencidas', () {
    test('dada una nota borrada hace 91 días, cuando se limpia, se borra para siempre', () async {
      await sembrar('vieja', borrada: hace91);

      final borradas = await local.purgarVencidas(ahora: ahora);

      expect(borradas, 1);
      expect(await ids(), isEmpty);
    });

    test('dada una nota borrada hace 89 días, cuando se limpia, sigue en «Ver borradas»', () async {
      await sembrar('reciente', borrada: hace89);

      final borradas = await local.purgarVencidas(ahora: ahora);

      expect(borradas, 0);
      expect(await ids(), ['reciente']);
    });

    test('dada una nota borrada hace justo 90 días, todavía no se borra', () async {
      await sembrar('justo', borrada: hace90);

      expect(await local.purgarVencidas(ahora: ahora), 0);
      expect(await ids(), ['justo']);
    });

    test('dada una nota activa muy vieja, cuando se limpia, no se toca', () async {
      await sembrar('activa');

      expect(await local.purgarVencidas(ahora: ahora), 0);
      expect(await ids(), ['activa']);
    });

    test(
      'dadas notas de una visita o una agenda borradas hace más de 90 días, no se tocan',
      () async {
        await sembrar('visita', tipo: TipoObjetivoNota.visita, borrada: hace91);
        await sembrar('agenda', tipo: TipoObjetivoNota.agenda, borrada: hace91);
        await sembrar('persona', borrada: hace91);

        final borradas = await local.purgarVencidas(ahora: ahora);

        expect(borradas, 1);
        expect(await ids(), ['agenda', 'visita']);
      },
    );

    test('dada una nota de un lugar borrada hace 91 días, cuando se limpia, se borra', () async {
      await sembrar('lugar', tipo: TipoObjetivoNota.ubicacion, borrada: hace91);

      expect(await local.purgarVencidas(ahora: ahora), 1);
      expect(await ids(), isEmpty);
    });

    test(
      'dada una nota de un lugar borrada hace 89 o justo 90 días, todavía no se borra',
      () async {
        await sembrar('lugar89', tipo: TipoObjetivoNota.ubicacion, borrada: hace89);
        await sembrar('lugar90', tipo: TipoObjetivoNota.ubicacion, borrada: hace90);

        expect(await local.purgarVencidas(ahora: ahora), 0);
        expect(await ids(), ['lugar89', 'lugar90']);
      },
    );

    test('dada una nota de un lugar activa muy vieja, o restaurada, no se toca', () async {
      await sembrar('activa', tipo: TipoObjetivoNota.ubicacion);
      await sembrar('restaurada', tipo: TipoObjetivoNota.ubicacion, borrada: hace91);
      await marcarBorrada('restaurada', null);

      expect(await local.purgarVencidas(ahora: ahora), 0);
      expect(await ids(), ['activa', 'restaurada']);
    });

    test('dadas notas de persona y de lugar vencidas, una sola limpieza borra las dos', () async {
      await sembrar('persona', borrada: hace91);
      await sembrar('lugar', tipo: TipoObjetivoNota.ubicacion, borrada: hace91);
      await sembrar('lugar-nueva', tipo: TipoObjetivoNota.ubicacion, borrada: hace89);

      expect(await local.purgarVencidas(ahora: ahora), 2);
      expect(await ids(), ['lugar-nueva']);
    });

    test('dadas varias notas, borra solo las vencidas y es idempotente', () async {
      await sembrar('a', borrada: hace91);
      await sembrar('b', borrada: hace89);
      await sembrar('c');
      await sembrar('d', borrada: DateTime.utc(2025, 1, 1));

      expect(await local.purgarVencidas(ahora: ahora), 2);
      expect(await local.purgarVencidas(ahora: ahora), 0);
      expect(await ids(), ['b', 'c']);
    });

    test('dada una hora con otro offset, el corte es el mismo instante', () async {
      await sembrar('justo', borrada: hace90);
      await sembrar('pasada', borrada: hace90.subtract(const Duration(milliseconds: 1)));

      final enMontevideo = ahora.toLocal();
      expect(await local.purgarVencidas(ahora: enMontevideo), 1);
      expect(await ids(), ['justo']);
    });

    test(
      'dada una nota restaurada dentro de los 90 días, cuando se limpia, no se pierde',
      () async {
        await sembrar('n1', borrada: hace89);
        await marcarBorrada('n1', null);

        expect(await local.purgarVencidas(ahora: ahora.add(const Duration(days: 30))), 0);
        expect(await ids(), ['n1']);
      },
    );

    test('dada una nota borrada de nuevo, el plazo cuenta desde el último borrado', () async {
      await sembrar('n1', borrada: hace91);
      // Se restauró y se volvió a borrar hace 10 días.
      await marcarBorrada('n1', ahora.subtract(const Duration(days: 10)));

      expect(await local.purgarVencidas(ahora: ahora), 0);
      expect(await ids(), ['n1']);
    });

    test('dados dos pedidos casi a la vez, los dos terminan y no hay error', () async {
      await sembrar('a', borrada: hace91);
      await sembrar('b', borrada: hace91);

      final r = await Future.wait([
        local.purgarVencidas(ahora: ahora),
        local.purgarVencidas(ahora: ahora),
      ]);

      expect(r.reduce((a, b) => a + b), 2);
      expect(await ids(), isEmpty);
    });
  });

  group('LimpiezaNotasBorradasRepositoryImpl', () {
    test('dada una nota vencida, devuelve cuántas borró', () async {
      await sembrar('vieja', borrada: hace91);

      final r = await LimpiezaNotasBorradasRepositoryImpl(
        local,
        logger: loggerMudo(),
      ).purgarVencidas(ahora: ahora);

      expect(r.getOrElse(() => -1), 1);
    });

    test('dada una base que falla, devuelve la falla con el tipo y sin el texto', () async {
      await sembrar('vieja', borrada: hace91, texto: 'Debe plata a Ana Martínez 099 123 456');
      await db.close();

      final r = await LimpiezaNotasBorradasRepositoryImpl(
        local,
        logger: loggerMudo(),
      ).purgarVencidas(ahora: ahora);

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isNotNull);
      expect('${falla!.props}', isNot(contains('Martínez')));
      expect('${falla.props}', isNot(contains('DELETE')));
    });
  });
}
