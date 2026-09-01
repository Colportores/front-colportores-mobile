// Test de dominio: Dart puro.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/obtener_sesion_actual_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  final ahora = DateTime.utc(2026, 9, 1, 12);

  Sesion sesionQueExpira(DateTime cuando) => Sesion(
    usuarioId: '01920000-0000-7000-8000-000000000001',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: cuando,
  );

  setUp(() => repository = _MockAuthRepository());

  group('ObtenerSesionActualUseCase', () {
    group('dado que hay una sesión guardada', () {
      test('cuando sigue vigente, la devuelve', () async {
        final sesion = sesionQueExpira(ahora.add(const Duration(hours: 1)));
        when(() => repository.sesionActual()).thenAnswer((_) async => Right(sesion));

        final resultado = await ObtenerSesionActualUseCase(repository, ahora: () => ahora)(
          const NoParams(),
        );

        expect(resultado, Right<Failure, Sesion?>(sesion));
      });

      test('cuando ya venció, la trata como ausente (null)', () async {
        final vencida = sesionQueExpira(ahora.subtract(const Duration(minutes: 1)));
        when(() => repository.sesionActual()).thenAnswer((_) async => Right(vencida));

        final resultado = await ObtenerSesionActualUseCase(repository, ahora: () => ahora)(
          const NoParams(),
        );

        expect(resultado, const Right<Failure, Sesion?>(null));
      });
    });

    group('dado que no hay sesión', () {
      test('cuando consulta, devuelve null', () async {
        when(() => repository.sesionActual()).thenAnswer((_) async => const Right(null));

        final resultado = await ObtenerSesionActualUseCase(repository)(const NoParams());

        expect(resultado, const Right<Failure, Sesion?>(null));
      });
    });

    group('dado que el repositorio falla', () {
      test('cuando consulta, propaga el Failure', () async {
        when(
          () => repository.sesionActual(),
        ).thenAnswer((_) async => const Left(FailureInesperado()));

        final resultado = await ObtenerSesionActualUseCase(repository)(const NoParams());

        expect(resultado, const Left<Failure, Sesion?>(FailureInesperado()));
      });
    });
  });
}
