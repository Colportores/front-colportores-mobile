// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_registro.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/registrar_usuario_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late RegistrarUsuarioUseCase useCase;

  final sesion = Sesion(
    usuarioId: '01920000-0000-7000-8000-000000000001',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );

  const RegistrarUsuarioParams datosValidos = RegistrarUsuarioParams(
    nombre: 'Ana',
    apellido: 'Pérez',
    cedula: '1.234.567-8',
    email: 'ana@example.com',
    password: 'Secreto123',
    aceptaTerminos: true,
  );

  setUp(() {
    repository = _MockAuthRepository();
    useCase = RegistrarUsuarioUseCase(repository);
  });

  void stubRepositorio(Either<Failure, ResultadoRegistro> resultado) {
    when(
      () => repository.registrar(
        nombre: any(named: 'nombre'),
        apellido: any(named: 'apellido'),
        cedula: any(named: 'cedula'),
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => resultado);
  }

  group('RegistrarUsuarioUseCase', () {
    group('dado que los datos son válidos', () {
      test('cuando registra, delega en el repositorio con email y cédula normalizados', () async {
        final resultadoRegistro = ResultadoRegistro(sesion: sesion, email: sesion.email);
        stubRepositorio(Right(resultadoRegistro));

        final resultado = await useCase(
          const RegistrarUsuarioParams(
            nombre: '  Ana ',
            apellido: ' Pérez ',
            cedula: '1.234.567-8',
            email: '  Ana@Example.COM ',
            password: 'Secreto123',
            aceptaTerminos: true,
          ),
        );

        expect(resultado, Right<Failure, ResultadoRegistro>(resultadoRegistro));
        verify(
          () => repository.registrar(
            nombre: 'Ana',
            apellido: 'Pérez',
            cedula: '12345678',
            email: 'ana@example.com',
            password: 'Secreto123',
          ),
        ).called(1);
      });

      // Caso borde de la HU (§Casos borde identificados): "Email con caracteres Unicode válidos
      // (ej: tildes en el local-part RFC 6531)". El regex de email (`[^\s@]+@[^\s@]+\.[^\s@]{2,}`)
      // no restringe a ASCII: si alguien lo "endurece" a `[a-zA-Z0-9.]` para "ser más estricto",
      // este test lo agarra.
      test(
        'cuando el email tiene tildes en el local-part, lo acepta y lo normaliza en minúsculas',
        () async {
          final resultadoRegistro = ResultadoRegistro(sesion: sesion, email: sesion.email);
          stubRepositorio(Right(resultadoRegistro));

          final resultado = await useCase(
            const RegistrarUsuarioParams(
              nombre: 'José',
              apellido: 'Pérez',
              cedula: '1.234.567-8',
              email: 'José.Pérez@example.com',
              password: 'Secreto123',
              aceptaTerminos: true,
            ),
          );

          expect(resultado.isRight(), isTrue);
          verify(
            () => repository.registrar(
              nombre: 'José',
              apellido: 'Pérez',
              cedula: '12345678',
              email: 'josé.pérez@example.com',
              password: 'Secreto123',
            ),
          ).called(1);
        },
      );

      test('cuando el repositorio falla, propaga el Failure sin transformarlo', () async {
        stubRepositorio(const Left(FailureEmailYaRegistrado()));

        final resultado = await useCase(datosValidos);

        expect(resultado, const Left<Failure, ResultadoRegistro>(FailureEmailYaRegistrado()));
      });
    });

    group('dado que los datos son inválidos', () {
      Future<Map<String, String>> camposInvalidos(RegistrarUsuarioParams params) async {
        final resultado = await useCase(params);
        expect(resultado.isLeft(), isTrue);
        final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
        expect(failure, isA<FailureValidacion>());
        verifyNever(
          () => repository.registrar(
            nombre: any(named: 'nombre'),
            apellido: any(named: 'apellido'),
            cedula: any(named: 'cedula'),
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        );
        return (failure as FailureValidacion).campos;
      }

      test('cuando el nombre está vacío, marca el campo nombre', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: '   ',
            apellido: datosValidos.apellido,
            cedula: datosValidos.cedula,
            email: datosValidos.email,
            password: datosValidos.password,
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'nombre': 'Ingresá tu nombre'});
      });

      test('cuando el apellido está vacío, marca el campo apellido', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: '',
            cedula: datosValidos.cedula,
            email: datosValidos.email,
            password: datosValidos.password,
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'apellido': 'Ingresá tu apellido'});
      });

      test('cuando la cédula está vacía, marca el campo cedula', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: '   ',
            email: datosValidos.email,
            password: datosValidos.password,
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'cedula': 'Ingresá tu cédula'});
      });

      test('cuando la cédula tiene letras, marca el campo cedula como inválido', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: '1234abc8',
            email: datosValidos.email,
            password: datosValidos.password,
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'cedula': 'La cédula no es válida'});
      });

      test('cuando la cédula tiene menos de 7 dígitos, marca el campo cedula', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: '12.345',
            email: datosValidos.email,
            password: datosValidos.password,
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'cedula': 'La cédula no es válida'});
      });

      test('cuando el email no tiene formato válido, marca el campo email', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: datosValidos.cedula,
            email: 'no-es-un-email',
            password: datosValidos.password,
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'email': 'El email no es válido'});
      });

      test('cuando la contraseña no tiene mayúscula ni número, marca el campo password', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: datosValidos.cedula,
            email: datosValidos.email,
            password: 'secretito',
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'password': 'Usá al menos 8 caracteres, una mayúscula y un número.'});
      });

      // Refuerzo: la política es "≥ 8 y mayúscula y dígito" combinados (Supuesto S1 de la HU),
      // no solo "algo de cada uno". Con mayúscula y dígito pero 7 caracteres tiene que rechazarla
      // igual que si le faltara la mayúscula o el dígito.
      test('cuando la contraseña tiene mayúscula y dígito pero menos de 8 caracteres, marca el '
          'campo password', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: datosValidos.cedula,
            email: datosValidos.email,
            password: 'Ab1defg',
            aceptaTerminos: true,
          ),
        );

        expect(campos, {'password': 'Usá al menos 8 caracteres, una mayúscula y un número.'});
      });

      test('cuando no acepta los términos, marca el campo aceptaTerminos', () async {
        final campos = await camposInvalidos(
          RegistrarUsuarioParams(
            nombre: datosValidos.nombre,
            apellido: datosValidos.apellido,
            cedula: datosValidos.cedula,
            email: datosValidos.email,
            password: datosValidos.password,
            aceptaTerminos: false,
          ),
        );

        expect(campos, {'aceptaTerminos': 'Tenés que aceptar los términos.'});
      });

      test('cuando todos los datos son inválidos, reporta todos los campos a la vez', () async {
        final campos = await camposInvalidos(
          const RegistrarUsuarioParams(
            nombre: '',
            apellido: '',
            cedula: '',
            email: '',
            password: '',
            aceptaTerminos: false,
          ),
        );

        expect(
          campos.keys,
          containsAll(['nombre', 'apellido', 'cedula', 'email', 'password', 'aceptaTerminos']),
        );
      });
    });
  });
}
