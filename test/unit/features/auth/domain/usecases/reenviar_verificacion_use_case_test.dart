// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/reenviar_verificacion_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late ReenviarVerificacionUseCase useCase;

  setUp(() {
    repository = _MockAuthRepository();
    useCase = ReenviarVerificacionUseCase(repository);
  });

  group('ReenviarVerificacionUseCase', () {
    group('dado que el email es válido', () {
      test('cuando reenvía, delega en el repositorio con el email normalizado', () async {
        when(
          () => repository.reenviarVerificacion(email: any(named: 'email')),
        ).thenAnswer((_) async => const Right(unit));

        final resultado = await useCase(
          const ReenviarVerificacionParams(email: '  Ana@Example.COM '),
        );

        expect(resultado, const Right<Failure, Unit>(unit));
        verify(() => repository.reenviarVerificacion(email: 'ana@example.com')).called(1);
      });

      test('cuando el repositorio falla, propaga el Failure sin transformarlo', () async {
        when(() => repository.reenviarVerificacion(email: any(named: 'email'))).thenAnswer(
          (_) async => const Left(
            FailureServidor(mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.'),
          ),
        );

        final resultado = await useCase(const ReenviarVerificacionParams(email: 'ana@example.com'));

        expect(
          resultado,
          const Left<Failure, Unit>(
            FailureServidor(mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.'),
          ),
        );
      });
    });

    group('dado que el email es inválido', () {
      test('cuando está vacío, retorna FailureValidacion sin tocar el repositorio', () async {
        final resultado = await useCase(const ReenviarVerificacionParams(email: '   '));

        expect(
          resultado,
          const Left<Failure, Unit>(FailureValidacion(campos: {'email': 'Ingresá tu email'})),
        );
        verifyNever(() => repository.reenviarVerificacion(email: any(named: 'email')));
      });

      test('cuando no tiene formato válido, marca el campo email', () async {
        final resultado = await useCase(const ReenviarVerificacionParams(email: 'no-es-un-email'));

        expect(
          resultado,
          const Left<Failure, Unit>(FailureValidacion(campos: {'email': 'El email no es válido'})),
        );
        verifyNever(() => repository.reenviarVerificacion(email: any(named: 'email')));
      });
    });
  });
}
