// Test de la capa data: Dart puro, con el data source en memoria.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/jornada_repository_impl.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/iniciar_jornada_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Almacenamiento roto a propósito: toda operación lanza una excepción no tipada.
final class _DataSourceRoto implements JornadaLocalDataSource {
  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async => throw Exception('disco');

  @override
  Future<void> insertar(JornadaModel jornada) async => throw Exception('disco');

  @override
  Future<void> finalizar(JornadaModel jornada) async => throw Exception('disco');
}

void main() {
  final t0 = DateTime.utc(2026, 9, 22, 12);

  Jornada jornada({
    String id = 'jor-1',
    String colportorId = 'u-1',
    DateTime? fin,
    DateTime? deletedAt,
  }) => Jornada(
    id: id,
    colportorId: colportorId,
    inicio: t0,
    fin: fin,
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: colportorId,
      deletedAt: deletedAt,
    ),
  );

  late JornadaLocalDataSourceEnMemoria local;
  late JornadaRepositoryImpl repositorio;

  setUp(() {
    local = JornadaLocalDataSourceEnMemoria();
    repositorio = JornadaRepositoryImpl(local, logger: loggerMudo());
  });

  group('JornadaRepositoryImpl.crear', () {
    test('dado que no hay jornada activa, cuando se crea, queda guardada y vuelve la entidad de '
        'dominio', () async {
      final resultado = await repositorio.crear(jornada());

      final guardada = resultado.getOrElse(() => fail('se esperaba Right'));
      expect(guardada, jornada());
      expect(guardada.runtimeType, Jornada);
      expect(local.jornadas.map((j) => j.toEntity()), [jornada()]);
    });

    test('dado que el colportor ya tiene una jornada abierta, cuando se crea otra, devuelve '
        'FailureJornadaActiva y no la guarda', () async {
      await repositorio.crear(jornada());

      final resultado = await repositorio.crear(jornada(id: 'jor-2'));

      expect(resultado, const Left<Failure, Jornada>(FailureJornadaActiva()));
      expect(local.jornadas.map((j) => j.id), ['jor-1']);
    });

    test('dado que la jornada anterior está cerrada o borrada, cuando se crea otra, se '
        'guarda', () async {
      local = JornadaLocalDataSourceEnMemoria(
        iniciales: [
          JornadaModel.fromEntity(jornada(id: 'cerrada', fin: t0.add(const Duration(hours: 8)))),
          JornadaModel.fromEntity(jornada(id: 'borrada', deletedAt: t0)),
        ],
      );
      repositorio = JornadaRepositoryImpl(local, logger: loggerMudo());

      final resultado = await repositorio.crear(jornada(id: 'nueva'));

      expect(resultado.isRight(), isTrue);
      expect(local.jornadas.map((j) => j.id), ['cerrada', 'borrada', 'nueva']);
    });

    test(
      'dado que otro colportor tiene una jornada abierta, cuando se crea una, se guarda',
      () async {
        await repositorio.crear(jornada(id: 'de-otro', colportorId: 'u-2'));

        final resultado = await repositorio.crear(jornada(id: 'mia'));

        expect(resultado.isRight(), isTrue);
      },
    );

    test('dado que el almacenamiento falla, cuando se crea, devuelve FailureInesperado', () async {
      final roto = JornadaRepositoryImpl(_DataSourceRoto(), logger: loggerMudo());

      final resultado = await roto.crear(jornada());

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
    });

    test('dado un id repetido, cuando se crea, devuelve FailureInesperado y no pisa la '
        'existente', () async {
      await repositorio.crear(jornada(fin: t0.add(const Duration(hours: 1))));

      final resultado = await repositorio.crear(jornada());

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(local.jornadas.single.fin, isNotNull);
    });
  });

  group('JornadaRepositoryImpl.obtenerActiva', () {
    test('dado que no hay jornadas, cuando se consulta, devuelve null', () async {
      expect(await repositorio.obtenerActiva('u-1'), const Right<Failure, Jornada?>(null));
    });

    test('dado una jornada abierta, cuando se consulta, la devuelve como entidad de '
        'dominio', () async {
      await repositorio.crear(jornada());

      final activa = (await repositorio.obtenerActiva('u-1')).getOrElse(() => fail('Left'));

      expect(activa, jornada());
      expect(activa.runtimeType, Jornada);
    });

    test('dado solo jornadas cerradas, borradas o de otro colportor, cuando se consulta, '
        'devuelve null', () async {
      local = JornadaLocalDataSourceEnMemoria(
        iniciales: [
          JornadaModel.fromEntity(jornada(id: 'cerrada', fin: t0.add(const Duration(hours: 8)))),
          JornadaModel.fromEntity(jornada(id: 'borrada', deletedAt: t0)),
          JornadaModel.fromEntity(jornada(id: 'de-otro', colportorId: 'u-2')),
        ],
      );
      repositorio = JornadaRepositoryImpl(local, logger: loggerMudo());

      expect(await repositorio.obtenerActiva('u-1'), const Right<Failure, Jornada?>(null));
    });

    test('dado que el almacenamiento falla, cuando se consulta, devuelve '
        'FailureInesperado', () async {
      final roto = JornadaRepositoryImpl(_DataSourceRoto(), logger: loggerMudo());

      final resultado = await roto.obtenerActiva('u-1');

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
    });
  });

  group('JornadaRepositoryImpl.finalizar', () {
    final fin = t0.add(const Duration(hours: 8));
    final cierre = fin.add(const Duration(minutes: 5));

    test('dado una jornada abierta, cuando se finaliza, guarda fin y updated_at y devuelve la '
        'entidad cerrada', () async {
      await local.insertar(JornadaModel.fromEntity(jornada()));

      final resultado = await repositorio.finalizar(
        jornada().finalizada(fin: fin, actualizadaEn: cierre),
      );

      final cerrada = resultado.getOrElse(() => throw StateError('esperaba Right'));
      expect(cerrada.runtimeType, Jornada);
      expect(cerrada.fin, fin);
      expect(cerrada.duracion, const Duration(hours: 8));
      final guardada = local.jornadas.single;
      expect(guardada.fin, fin);
      expect(guardada.auditoria.updatedAt, cierre);
      expect(guardada.auditoria.createdAt, t0);
      expect(await repositorio.obtenerActiva('u-1'), const Right<Failure, Jornada?>(null));
    });

    test('dado que la jornada ya estaba cerrada, cuando se finaliza otra vez, devuelve '
        'FailureSinJornadaActiva y no pisa el fin guardado', () async {
      await local.insertar(JornadaModel.fromEntity(jornada(fin: fin)));

      final resultado = await repositorio.finalizar(
        jornada().finalizada(fin: fin.add(const Duration(minutes: 10)), actualizadaEn: cierre),
      );

      expect(resultado, const Left<Failure, Jornada>(FailureSinJornadaActiva()));
      expect(local.jornadas.single.fin, fin);
    });

    test('dado una jornada borrada o de otro colportor, cuando se finaliza, devuelve '
        'FailureSinJornadaActiva', () async {
      await local.insertar(JornadaModel.fromEntity(jornada(deletedAt: t0)));
      await local.insertar(JornadaModel.fromEntity(jornada(id: 'ajena', colportorId: 'u-2')));

      final borrada = await repositorio.finalizar(
        jornada().finalizada(fin: fin, actualizadaEn: cierre),
      );
      final ajena = await repositorio.finalizar(
        jornada(id: 'ajena').finalizada(fin: fin, actualizadaEn: cierre),
      );

      expect(borrada, const Left<Failure, Jornada>(FailureSinJornadaActiva()));
      expect(ajena, const Left<Failure, Jornada>(FailureSinJornadaActiva()));
    });

    test(
      'dado que el almacenamiento falla, cuando se finaliza, devuelve FailureInesperado',
      () async {
        final roto = JornadaRepositoryImpl(_DataSourceRoto(), logger: loggerMudo());

        final resultado = await roto.finalizar(
          jornada().finalizada(fin: fin, actualizadaEn: cierre),
        );

        expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
      },
    );
  });

  group('IniciarJornadaUseCase + JornadaRepositoryImpl', () {
    test('dado dos inicios casi simultáneos, cuando los dos pasan la comprobación, solo uno crea '
        'la jornada y el otro recibe FailureJornadaActiva', () async {
      var n = 0;
      final iniciar = IniciarJornadaUseCase(
        repositorio,
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
      expect(local.jornadas.where((j) => j.estaAbierta), hasLength(1));
    });
  });
}
