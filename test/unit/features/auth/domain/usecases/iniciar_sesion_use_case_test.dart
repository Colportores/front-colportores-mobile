// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/iniciar_sesion_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late IniciarSesionUseCase useCase;

  final sesion = Sesion(
    usuarioId: '01920000-0000-7000-8000-000000000001',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );

  setUp(() {
    repository = _MockAuthRepository();
    useCase = IniciarSesionUseCase(repository);
  });

  group('IniciarSesionUseCase', () {
    group('dado que los datos son válidos', () {
      test('cuando inicia sesión, delega en el repositorio con el email normalizado', () async {
        when(
          () => repository.iniciarSesion(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => Right(sesion));

        final resultado = await useCase(
          const IniciarSesionParams(email: '  Ana@Example.COM ', password: 'secreto123'),
        );

        expect(resultado, Right<Failure, Sesion>(sesion));
        verify(
          () => repository.iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        ).called(1);
      });

      test('cuando el repositorio falla, propaga el Failure sin transformarlo', () async {
        when(
          () => repository.iniciarSesion(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => const Left(FailureCredencialesInvalidas()));

        final resultado = await useCase(
          const IniciarSesionParams(email: 'ana@example.com', password: 'secreto123'),
        );

        expect(resultado, const Left<Failure, Sesion>(FailureCredencialesInvalidas()));
      });
    });

    group('dado que los datos son inválidos', () {
      test(
        'cuando el email está vacío, retorna FailureValidacion sin tocar el repositorio',
        () async {
          final resultado = await useCase(
            const IniciarSesionParams(email: '   ', password: 'secreto123'),
          );

          expect(resultado.isLeft(), isTrue);
          final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
          expect(failure, isA<FailureValidacion>());
          expect((failure as FailureValidacion).campos, {'email': 'Ingresá tu email'});
          verifyNever(
            () => repository.iniciarSesion(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          );
        },
      );

      test('cuando el email no tiene formato válido, marca el campo email', () async {
        final resultado = await useCase(
          const IniciarSesionParams(email: 'no-es-un-email', password: 'secreto123'),
        );

        final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
        expect((failure as FailureValidacion).campos.keys, ['email']);
      });

      test('cuando la contraseña es corta, marca el campo password', () async {
        final resultado = await useCase(
          const IniciarSesionParams(email: 'ana@example.com', password: '123'),
        );

        final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
        expect((failure as FailureValidacion).campos.keys, ['password']);
      });

      test('cuando ambos son inválidos, reporta los dos campos a la vez', () async {
        final resultado = await useCase(const IniciarSesionParams(email: '', password: ''));

        final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
        expect((failure as FailureValidacion).campos.keys, containsAll(['email', 'password']));
      });
    });
  });
}
