// Test de la capa data contra la tabla real: AppDatabase en memoria (sin cifrado — el cifrado se
// prueba en database_helper_test.dart), mismo esquema y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source_drift.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/jornada_repository_impl.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/iniciar_jornada_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 22, 12);

  JornadaModel jornada({
    String id = 'jor-1',
    String colportorId = 'u-1',
    DateTime? inicio,
    DateTime? fin,
    DateTime? deletedAt,
  }) => JornadaModel(
    id: id,
    colportorId: colportorId,
    inicio: inicio ?? t0,
    fin: fin,
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: colportorId,
      deletedAt: deletedAt,
    ),
  );

  late AppDatabase db;
  late JornadaLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = JornadaLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  Future<int> filas() async => (await db.select(db.jornadas).get()).length;

  group('JornadaLocalDataSourceDrift — tabla jornada', () {
    test('dado la tabla local, cuando se listan sus columnas, son exactamente las claves de '
        'JornadaModel.toJson (el payload de sync)', () {
      expect(db.jornadas.$columns.map((c) => c.name), unorderedEquals(jornada().toJson().keys));
      expect(db.jornadas.actualTableName, 'jornada');
    });

    test('dado una jornada con todos sus campos, cuando se guarda y se lee la activa, vuelve '
        'igual', () async {
      final completa = JornadaModel(
        id: 'jor-1',
        colportorId: 'u-1',
        inicio: t0,
        acompananteId: 'u-2',
        tipoAcompanamiento: 'PAREJA',
        totalVisitas: 3,
        totalVentas: 1,
        auditoria: Auditoria(
          createdAt: t0,
          updatedAt: t0.add(const Duration(minutes: 5)),
          createdBy: 'u-1',
          syncVersion: 7,
        ),
      );
      await local.insertar(completa);

      expect(await local.obtenerActiva('u-1'), completa);
    });

    test('dado una fecha con microsegundos, cuando se guarda, queda como epoch ms y vuelve en UTC '
        'truncada al milisegundo', () async {
      await local.insertar(jornada(inicio: DateTime.utc(2026, 9, 22, 12, 0, 0, 123, 456)));

      final crudo = await db.customSelect('SELECT inicio FROM jornada').getSingle();
      final activa = await local.obtenerActiva('u-1');

      expect(
        crudo.read<int>('inicio'),
        DateTime.utc(2026, 9, 22, 12, 0, 0, 123).millisecondsSinceEpoch,
      );
      expect(activa!.inicio, DateTime.utc(2026, 9, 22, 12, 0, 0, 123));
      expect(activa.inicio.isUtc, isTrue);
    });

    test(
      'dado una jornada cerrada y borrada, cuando se guarda, fin y deleted_at vuelven en UTC',
      () async {
        final fin = t0.add(const Duration(hours: 8));
        final borrado = t0.add(const Duration(hours: 9));
        await local.insertar(jornada(fin: fin.toLocal(), deletedAt: borrado.toLocal()));

        final fila = await db.select(db.jornadas).getSingle();

        expect(fila.fin, fin);
        expect(fila.fin!.isUtc, isTrue);
        expect(fila.deletedAt, borrado);
        expect(fila.deletedAt!.isUtc, isTrue);
      },
    );

    test('dado un fin anterior al inicio o un total negativo, cuando se guarda, la DB lo rechaza '
        'como el cloud', () async {
      await expectLater(
        local.insertar(jornada(fin: t0.subtract(const Duration(minutes: 1)))),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        local.insertar(
          JornadaModel(
            id: 'jor-2',
            colportorId: 'u-1',
            inicio: t0,
            totalVisitas: -1,
            auditoria: Auditoria(createdAt: t0, updatedAt: t0),
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(await filas(), 0);
    });
  });

  group('JornadaLocalDataSourceDrift.obtenerActiva', () {
    test('dado que no hay jornadas, cuando se pide la activa, devuelve null', () async {
      expect(await local.obtenerActiva('u-1'), isNull);
    });

    test('dado jornadas cerradas, borradas o de otro colportor, cuando se pide la activa, devuelve '
        'null', () async {
      await local.insertar(jornada(id: 'cerrada', fin: t0.add(const Duration(hours: 1))));
      await local.insertar(jornada(id: 'borrada', deletedAt: t0));
      await local.insertar(jornada(id: 'ajena', colportorId: 'u-2'));

      expect(await local.obtenerActiva('u-1'), isNull);
      expect((await local.obtenerActiva('u-2'))?.id, 'ajena');
    });
  });

  group('JornadaLocalDataSourceDrift.finalizar', () {
    final fin = t0.add(const Duration(hours: 8));
    final cierre = fin.add(const Duration(minutes: 5));

    JornadaModel cerrada({String id = 'jor-1', String colportorId = 'u-1'}) =>
        JornadaModel.fromEntity(
          jornada(id: id, colportorId: colportorId).finalizada(fin: fin, actualizadaEn: cierre),
        );

    test('dado una jornada abierta, cuando se finaliza, guarda solo fin y updated_at', () async {
      await local.insertar(jornada());

      await local.finalizar(cerrada());

      final fila = await db.select(db.jornadas).getSingle();
      expect(fila.fin, fin);
      expect(fila.updatedAt, cierre);
      expect(fila.inicio, t0);
      expect(fila.createdAt, t0);
      expect(await local.obtenerActiva('u-1'), isNull);
    });

    test('dado una jornada ya cerrada, borrada, de otro colportor o inexistente, cuando se '
        'finaliza, lanza JornadaNoAbiertaException y no toca la fila', () async {
      final finPrevio = t0.add(const Duration(hours: 2));
      await local.insertar(jornada(fin: finPrevio));
      await local.insertar(jornada(id: 'borrada', deletedAt: t0));
      await local.insertar(jornada(id: 'ajena', colportorId: 'u-2'));

      for (final intento in [
        cerrada(),
        cerrada(id: 'borrada'),
        cerrada(id: 'ajena'),
        cerrada(id: 'no-existe'),
      ]) {
        await expectLater(local.finalizar(intento), throwsA(isA<JornadaNoAbiertaException>()));
      }
      final filas = await db.select(db.jornadas).get();
      expect(filas.firstWhere((f) => f.id == 'jor-1').fin, finPrevio);
      expect(filas.firstWhere((f) => f.id == 'ajena').fin, isNull);
    });

    test('dado dos cierres simultáneos de la misma jornada, cuando corren a la vez, solo uno se '
        'guarda y el otro lanza JornadaNoAbiertaException', () async {
      await local.insertar(jornada());
      final otro = JornadaModel.fromEntity(
        jornada().finalizada(fin: fin.add(const Duration(minutes: 1)), actualizadaEn: cierre),
      );

      final resultados = await Future.wait([
        local.finalizar(cerrada()).then((_) => true, onError: (Object _) => false),
        local.finalizar(otro).then((_) => true, onError: (Object _) => false),
      ]);

      expect(resultados.where((ok) => ok), hasLength(1));
      final ganador = resultados.first ? fin : fin.add(const Duration(minutes: 1));
      expect((await db.select(db.jornadas).getSingle()).fin, ganador);
    });
  });

  group('JornadaLocalDataSourceDrift.insertar', () {
    test('dado una jornada activa, cuando se inserta otra del mismo colportor, lanza '
        'JornadaActivaExistenteException y no guarda nada', () async {
      await local.insertar(jornada());

      await expectLater(
        local.insertar(jornada(id: 'jor-2')),
        throwsA(isA<JornadaActivaExistenteException>()),
      );
      expect(await filas(), 1);
    });

    test(
      'dado que la jornada anterior está cerrada, cuando se inserta una nueva, se guarda',
      () async {
        await local.insertar(jornada(fin: t0.add(const Duration(hours: 8))));

        await local.insertar(jornada(id: 'jor-2', inicio: t0.add(const Duration(days: 1))));

        expect((await local.obtenerActiva('u-1'))?.id, 'jor-2');
      },
    );

    test('dado dos inserciones simultáneas del mismo colportor, cuando corren a la vez, solo una '
        'se guarda', () async {
      final resultados = await Future.wait([
        for (final id in ['jor-1', 'jor-2'])
          local.insertar(jornada(id: id)).then((_) => true, onError: (Object _) => false),
      ]);

      expect(resultados.where((guardada) => guardada), hasLength(1));
      expect(await filas(), 1);
    });

    test('dado dos inicios casi simultáneos por el caso de uso, cuando los dos pasan la '
        'comprobación, solo uno crea la jornada y el otro recibe FailureJornadaActiva', () async {
      var n = 0;
      final iniciar = IniciarJornadaUseCase(
        JornadaRepositoryImpl(local, logger: loggerMudo()),
        generarId: () => 'jor-${++n}',
        ahora: () => t0,
      );

      final resultados = await Future.wait([
        iniciar(const IniciarJornadaParams(colportorId: 'u-1')),
        iniciar(const IniciarJornadaParams(colportorId: 'u-1')),
      ]);

      expect(resultados.where((r) => r.isRight()), hasLength(1));
      expect(
        resultados.where((r) => r == const Left<Failure, Jornada>(FailureJornadaActiva())),
        hasLength(1),
      );
      expect(await filas(), 1);
    });
  });

  group('IniciarJornadaUseCase + JornadaRepositoryImpl sobre Drift — precisión de fechas', () {
    test(
      'dado un reloj con microsegundos, cuando se inicia la jornada, la que devuelve crear es '
      'igual a la que se relee de la DB y el payload de sync lleva los mismos milisegundos',
      () async {
        final repositorio = JornadaRepositoryImpl(local, logger: loggerMudo());
        final iniciar = IniciarJornadaUseCase(
          repositorio,
          generarId: () => 'jor-1',
          ahora: () => DateTime.utc(2026, 9, 22, 12, 0, 0, 123, 999),
        );

        final creada = (await iniciar(
          const IniciarJornadaParams(colportorId: 'u-1'),
        )).getOrElse(() => fail('se esperaba Right'));
        final releida = (await repositorio.obtenerActiva(
          'u-1',
        )).getOrElse(() => fail('se esperaba Right'));

        expect(releida, creada);
        final payload = JornadaModel.fromEntity(creada).toJson();
        expect(payload['inicio'], '2026-09-22T12:00:00.123Z');
        expect(payload['created_at'], '2026-09-22T12:00:00.123Z');
        expect(payload['updated_at'], '2026-09-22T12:00:00.123Z');
      },
    );
  });
}
