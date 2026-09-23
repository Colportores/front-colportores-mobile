// Recuperación guiada de ADR-006 (HU-AUTH-009): el almacén seguro falló con la DB en disco y hay
// DEK envuelta con la contraseña. Repositorio y sesión en memoria.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/empezar_de_nuevo_db_local_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/recuperar_db_local_con_password_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

void main() {
  late DbLocalRepositoryEnMemoria repo;
  late VigenciaEnMemoria vigencia;
  late RecuperarDbLocalConPasswordUseCase recuperar;
  final dek = Uint8List.fromList(List<int>.filled(32, 42));

  setUp(() {
    repo = DbLocalRepositoryEnMemoria()
      ..marca = MarcaDbLocal.ilegible
      ..archivo = true
      ..envoltorio = (dek: dek, password: 'secreto123');
    vigencia = VigenciaEnMemoria();
    recuperar = RecuperarDbLocalConPasswordUseCase(repo, vigencia);
  });

  Future<Either<Failure, Unit>> conPassword(String password) =>
      recuperar(RecuperarDbLocalParams(password: password));

  group('RecuperarDbLocalConPasswordUseCase', () {
    test('dada la contraseña correcta, desenvuelve la DEK, recién ahí reconstruye el almacén y '
        'abre la DB: no se pierde nada', () async {
      final r = await conPassword('secreto123');

      expect(r, const Right<Failure, Unit>(unit));
      expect(repo.llamadas, ['desenvolver', 'reconstruir', 'abrir']);
      expect(repo.dekEnAlmacen, dek, reason: 'el almacén queda con la DEK recuperada');
      expect(repo.marca, MarcaDbLocal.puesta);
      expect(repo.abiertaCon!.bytes, dek);
      expect(repo.archivo, isTrue);
    });

    test(
      'dada otra contraseña, dice que no abre y no toca el almacén: se puede reintentar',
      () async {
        final r = await conPassword('otra-cosa');

        expect(r, const Left<Failure, Unit>(FailurePasswordNoAbreDatos()));
        expect(
          const FailurePasswordNoAbreDatos().mensaje,
          'Esa contraseña no abre tus datos guardados en este teléfono. Si la cambiaste hace poco, '
          'probá con la anterior.',
        );
        expect(repo.llamadas, ['desenvolver']);
        expect(repo.marca, MarcaDbLocal.ilegible);
      },
    );

    test('dado que no hay envoltorio, no hay recuperación por contraseña', () async {
      repo.envoltorio = null;

      expect(
        await conPassword('secreto123'),
        const Left<Failure, Unit>(FailureAlmacenSeguroSinRecuperacion()),
      );
    });

    test('dado que el almacén sigue sin poder escribirse, devuelve la falla, destruye la DEK y no '
        'abre', () async {
      repo.fallas['reconstruir'] = const FailureAlmacenSeguro();

      final r = await conPassword('secreto123');

      expect(r, const Left<Failure, Unit>(FailureAlmacenSeguro()));
      expect(repo.llamadas, isNot(contains('abrir')));
      expect(repo.entregadas.single.destruida, isTrue);
      expect(repo.envoltorio, isNotNull, reason: 'el envoltorio queda para reintentar');
    });

    test('dado un logout mientras corre Argon2id, no abre y destruye la DEK', () async {
      repo.argon2idPendiente = Completer<void>();

      final enCurso = conPassword('secreto123');
      await repo.pidioArgon2id.future;
      vigencia.cerrarSesion();
      repo.argon2idPendiente!.complete();
      final r = await enCurso;

      expect(r, const Left<Failure, Unit>(FailureSesionCerrada()));
      expect(repo.llamadas, isNot(contains('abrir')));
      expect(repo.entregadas.single.destruida, isTrue);
    });

    test('dado que no hay sesión, no hace nada', () async {
      vigencia.haySesion = false;

      expect(await conPassword('secreto123'), const Left<Failure, Unit>(FailureSesionCerrada()));
      expect(repo.llamadas, isEmpty);
    });

    test('dada una contraseña vacía, devuelve FailureValidacion sin tocar nada', () async {
      final r = await conPassword('');

      expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
      expect(repo.llamadas, isEmpty);
    });

    test('los params no imprimen la contraseña', () {
      final previo = EquatableConfig.stringify;
      addTearDown(() => EquatableConfig.stringify = previo);
      EquatableConfig.stringify = true;

      expect('${const RecuperarDbLocalParams(password: 'secreto123')}', isNot(contains('secreto')));
    });
  });

  group('EmpezarDeNuevoDbLocalUseCase', () {
    test('con el sí del usuario, deja el dispositivo sin DB, sin DEK y sin envoltorio', () async {
      repo.dekEnAlmacen = dek;

      final r = await EmpezarDeNuevoDbLocalUseCase(repo)(const NoParams());

      expect(r, const Right<Failure, Unit>(unit));
      expect(repo.llamadas, ['descartar']);
      expect(repo.archivo, isFalse);
      expect(repo.dekEnAlmacen, isNull);
      expect(repo.envoltorio, isNull);
    });

    test('si el borrado falla, devuelve la falla', () async {
      repo.fallas['descartar'] = const FailureAlmacenSeguro();

      expect(
        await EmpezarDeNuevoDbLocalUseCase(repo)(const NoParams()),
        const Left<Failure, Unit>(FailureAlmacenSeguro()),
      );
    });
  });
}
