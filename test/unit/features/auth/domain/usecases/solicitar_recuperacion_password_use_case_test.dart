// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/solicitar_recuperacion_password_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late SolicitarRecuperacionPasswordUseCase useCase;

  setUp(() {
    repository = _MockAuthRepository();
    useCase = SolicitarRecuperacionPasswordUseCase(repository);
  });

  group('SolicitarRecuperacionPasswordUseCase', () {
    group('dado que el email es válido', () {
      test('cuando solicita, delega en el repositorio con el email normalizado', () async {
        when(
          () => repository.solicitarRecuperacionPassword(email: any(named: 'email')),
        ).thenAnswer((_) async => const Right(unit));

        final resultado = await useCase(
          const SolicitarRecuperacionPasswordParams(email: '  Ana@Example.COM '),
        );

        expect(resultado, const Right<Failure, Unit>(unit));
        verify(() => repository.solicitarRecuperacionPassword(email: 'ana@example.com')).called(1);
      });

      test('cuando el repositorio falla (p. ej. sin conexión), propaga el Failure sin '
          'transformarlo', () async {
        when(
          () => repository.solicitarRecuperacionPassword(email: any(named: 'email')),
        ).thenAnswer((_) async => const Left(FailureSinConexion()));

        final resultado = await useCase(
          const SolicitarRecuperacionPasswordParams(email: 'ana@example.com'),
        );

        expect(resultado, const Left<Failure, Unit>(FailureSinConexion()));
      });
    });

    group('dado que el email es inválido', () {
      test('cuando está vacío, retorna FailureValidacion sin tocar el repositorio', () async {
        final resultado = await useCase(const SolicitarRecuperacionPasswordParams(email: '   '));

        expect(
          resultado,
          const Left<Failure, Unit>(FailureValidacion(campos: {'email': 'Ingresá tu email'})),
        );
        verifyNever(() => repository.solicitarRecuperacionPassword(email: any(named: 'email')));
      });

      test('cuando no tiene formato válido, marca el campo email', () async {
        final resultado = await useCase(
          const SolicitarRecuperacionPasswordParams(email: 'no-es-un-email'),
        );

        expect(
          resultado,
          const Left<Failure, Unit>(FailureValidacion(campos: {'email': 'El email no es válido'})),
        );
        verifyNever(() => repository.solicitarRecuperacionPassword(email: any(named: 'email')));
      });
    });
  });
}
