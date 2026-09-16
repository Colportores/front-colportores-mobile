// Test de dominio: Dart puro.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/iniciar_sesion_con_google_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late IniciarSesionConGoogleUseCase useCase;

  final sesion = Sesion(
    usuarioId: '01920000-0000-7000-8000-000000000001',
    email: 'ana@gmail.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2026, 9, 1, 13),
  );

  setUp(() {
    repository = _MockAuthRepository();
    useCase = IniciarSesionConGoogleUseCase(repository);
  });

  group('IniciarSesionConGoogleUseCase', () {
    test('cuando el repositorio entra, devuelve la Sesion', () async {
      when(() => repository.iniciarSesionConGoogle()).thenAnswer((_) async => Right(sesion));

      final resultado = await useCase(const NoParams());

      expect(resultado, Right<Failure, Sesion>(sesion));
      verify(() => repository.iniciarSesionConGoogle()).called(1);
    });

    test('cuando el repositorio falla, propaga el Failure sin transformarlo', () async {
      when(
        () => repository.iniciarSesionConGoogle(),
      ).thenAnswer((_) async => const Left(FailureSinConexion()));

      final resultado = await useCase(const NoParams());

      expect(resultado, const Left<Failure, Sesion>(FailureSinConexion()));
    });
  });
}
