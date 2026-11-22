// La limpieza de las notas borradas hace más de 90 días (HU-UBI-012): qué reloj usa y qué hace si falla.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/limpieza_notas_borradas_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/limpiar_notas_borradas_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _Repo implements LimpiezaNotasBorradasRepository {
  final recibidos = <DateTime>[];
  Either<Failure, int> resultado = const Right(0);

  @override
  Future<Either<Failure, int>> purgarVencidas({required DateTime ahora}) async {
    recibidos.add(ahora);
    return resultado;
  }
}

void main() {
  const params = NoParams();
  // La hora del servidor en estos tests, salvo que el test diga otra: la misma que el reloj.
  final servidorAlDia = DateTime.utc(2027, 1, 25, 9);

  LimpiarNotasBorradasUseCase caso(
    _Repo repo, {
    required Future<DateTime> Function() ahora,
    Future<DateTime?> Function()? servidor,
  }) => LimpiarNotasBorradasUseCase(
    repo,
    ahora: ahora,
    horaDelServidor: servidor ?? () async => servidorAlDia,
  );

  test('dado el reloj, cuando se limpia, le pasa al repositorio lo que dice el reloj', () async {
    final repo = _Repo()..resultado = const Right(3);
    final ahora = DateTime.utc(2027, 1, 25, 9);

    final r = await caso(repo, ahora: () async => ahora)(params);

    expect(r, const Right<Failure, int>(3));
    expect(repo.recibidos, [ahora]);
  });

  test('dado que el teléfono retrocede la hora, la limpieza usa la más alta que ya vio', () async {
    final repo = _Repo();
    var sistema = DateTime.utc(2027, 2, 1, 10);
    final reloj = RelojSesionEnMemoria(sistema: () => sistema);
    final c = caso(repo, ahora: reloj.ahora, servidor: () async => DateTime.utc(2027, 3, 1));

    await c(params);
    sistema = DateTime.utc(2026, 10, 1); // la colportora atrasa el reloj del teléfono
    await c(params);

    expect(repo.recibidos, [DateTime.utc(2027, 2, 1, 10), DateTime.utc(2027, 2, 1, 10)]);
  });

  test(
    'dado que el teléfono adelanta la hora, la limpieza usa la última que dijo el servidor (#509 P3)',
    () async {
      final repo = _Repo();

      await caso(
        repo,
        ahora: () async => DateTime.utc(2028, 6, 1), // la fecha adelantada del teléfono
        servidor: () async => DateTime.utc(2027, 1, 25, 9),
      )(params);

      expect(repo.recibidos, [DateTime.utc(2027, 1, 25, 9)]);
    },
  );

  test(
    'dado un teléfono que nunca habló con el servidor, no borra nada y no es una falla',
    () async {
      final repo = _Repo();

      final r = await caso(repo, ahora: () async => DateTime.utc(2028), servidor: () async => null)(
        params,
      );

      expect(r, const Right<Failure, int>(0));
      expect(repo.recibidos, isEmpty);
    },
  );

  test('dado que leer la hora del servidor falla, no limpia nada y no filtra el texto', () async {
    final repo = _Repo();

    final r = await caso(
      repo,
      ahora: () async => DateTime.utc(2027),
      servidor: () async => throw StateError('base rota con texto de una nota'),
    )(params);

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureInesperado>());
    expect('${falla!.props}', isNot(contains('texto de una nota')));
    expect(repo.recibidos, isEmpty);
  });

  test('dado que el reloj falla, no limpia nada: ante la duda la nota se conserva', () async {
    final repo = _Repo();

    final r = await caso(
      repo,
      ahora: () async => throw StateError('almacén roto con texto de una nota'),
    )(params);

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureInesperado>());
    expect('${falla!.props}', isNot(contains('texto de una nota')));
    expect(repo.recibidos, isEmpty);
  });

  test('dado que el repositorio falla, devuelve esa falla', () async {
    final repo = _Repo()..resultado = const Left(FailureInesperado(causa: 'X'));

    final r = await caso(repo, ahora: () async => DateTime.utc(2027))(params);

    expect(r.isLeft(), isTrue);
  });
}
