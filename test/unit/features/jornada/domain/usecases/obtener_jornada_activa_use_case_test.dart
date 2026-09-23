// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/obtener_jornada_activa_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _RepositorioFalso implements JornadaRepository {
  Either<Failure, Jornada?> respuestaActiva = const Right(null);
  final List<String> consultas = [];

  @override
  Future<Either<Failure, Jornada?>> obtenerActiva(String colportorId) async {
    consultas.add(colportorId);
    return respuestaActiva;
  }

  @override
  Future<Either<Failure, Jornada>> crear(Jornada jornada) =>
      throw UnimplementedError('no se usa en este caso de uso');

  @override
  Future<Either<Failure, Jornada>> finalizar(Jornada jornada) =>
      throw UnimplementedError('no se usa en este caso de uso');
}

void main() {
  late _RepositorioFalso repositorio;
  late ObtenerJornadaActivaUseCase obtenerActiva;

  setUp(() {
    repositorio = _RepositorioFalso();
    obtenerActiva = ObtenerJornadaActivaUseCase(repositorio);
  });

  final abierta = Jornada(
    id: 'jor-1',
    colportorId: 'u-1',
    inicio: DateTime.utc(2026, 9, 23, 12),
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 9, 23, 12),
      updatedAt: DateTime.utc(2026, 9, 23, 12),
      createdBy: 'u-1',
    ),
  );

  group('ObtenerJornadaActivaUseCase', () {
    test('dado que no tengo jornada activa, devuelve null', () async {
      final resultado = await obtenerActiva(const ObtenerJornadaActivaParams(colportorId: 'u-1'));

      expect(resultado, const Right<Failure, Jornada?>(null));
      expect(repositorio.consultas, ['u-1']);
    });

    test('dado que tengo jornada activa, la devuelve', () async {
      repositorio.respuestaActiva = Right(abierta);

      final resultado = await obtenerActiva(const ObtenerJornadaActivaParams(colportorId: ' u-1 '));

      expect(resultado, Right<Failure, Jornada?>(abierta));
      expect(repositorio.consultas, ['u-1']);
    });

    test('dado que el repositorio falla, devuelve el Failure', () async {
      repositorio.respuestaActiva = const Left(FailureInesperado());

      final resultado = await obtenerActiva(const ObtenerJornadaActivaParams(colportorId: 'u-1'));

      expect(resultado, const Left<Failure, Jornada?>(FailureInesperado()));
    });

    test('dado un colportor vacío, devuelve FailureValidacion sin consultar', () async {
      final resultado = await obtenerActiva(const ObtenerJornadaActivaParams(colportorId: '  '));

      expect(resultado.fold((f) => f, (_) => null), isA<FailureValidacion>());
      expect(repositorio.consultas, isEmpty);
    });

    test('dado dos params con el mismo colportor, son iguales', () {
      expect(
        const ObtenerJornadaActivaParams(colportorId: 'u-1'),
        const ObtenerJornadaActivaParams(colportorId: 'u-1'),
      );
    });
  });
}
