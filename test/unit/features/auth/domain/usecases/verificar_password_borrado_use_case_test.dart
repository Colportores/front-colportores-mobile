// HU-AUTH-010, vista 19: la contraseña de la confirmación final se valida en el teléfono, con 5
// intentos y una espera de 5 minutos que sobrevive al cierre de la app.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_intentos_borrado.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/intentos_borrado_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/verificar_password_borrado_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

final class _IntentosEnMemoria implements IntentosBorradoRepository {
  EstadoIntentosBorrado estado = EstadoIntentosBorrado.limpio;
  int limpiezas = 0;

  @override
  Future<EstadoIntentosBorrado> leer() async => estado;

  @override
  Future<void> guardar(EstadoIntentosBorrado nuevo) async => estado = nuevo;

  @override
  Future<void> limpiar() async {
    limpiezas++;
    estado = EstadoIntentosBorrado.limpio;
  }
}

void main() {
  late DbLocalRepositoryEnMemoria db;
  late _IntentosEnMemoria intentos;
  late DateTime ahora;
  late VerificarPasswordBorradoUseCase useCase;

  Future<Either<Failure, Unit>> probar(String password) =>
      useCase(VerificarPasswordBorradoParams(password: password));

  setUp(() {
    db = dbLocalYaPreparada();
    intentos = _IntentosEnMemoria();
    ahora = DateTime.utc(2026, 9, 30, 12);
    useCase = VerificarPasswordBorradoUseCase(db, intentos, () => ahora);
  });

  test('contraseña correcta: Right, destruye la DEK y limpia los intentos', () async {
    intentos.estado = EstadoIntentosBorrado(fallidos: 3);

    final r = await probar('Secreto123');

    expect(r, const Right<Failure, Unit>(unit));
    expect(db.entregadas, hasLength(1));
    expect(db.entregadas.single.destruida, isTrue, reason: 'la DEK no queda viva en memoria');
    expect(intentos.estado, EstadoIntentosBorrado.limpio);
  });

  test('contraseña incorrecta: cuenta un intento y dice cuántos quedan', () async {
    final r = await probar('otra');

    expect(r, const Left<Failure, Unit>(FailurePasswordBorradoIncorrecta(intentosRestantes: 4)));
    expect(intentos.estado.fallidos, 1);
    final r2 = await probar('otra');
    expect(r2, const Left<Failure, Unit>(FailurePasswordBorradoIncorrecta(intentosRestantes: 3)));
  });

  test('el quinto intento fallido bloquea 5 minutos y lo guarda', () async {
    for (var i = 0; i < 4; i++) {
      await probar('otra');
    }

    final r = await probar('otra');

    final fin = ahora.add(const Duration(minutes: 5));
    expect(r, Left<Failure, Unit>(FailureBorradoBloqueado(hasta: fin)));
    expect(intentos.estado.bloqueadoHasta, fin, reason: 'el fin de la espera se persiste');
    expect(intentos.estado.fallidos, 0);
  });

  test('en espera no prueba la contraseña, ni siquiera la correcta', () async {
    final fin = ahora.add(const Duration(minutes: 3));
    intentos.estado = EstadoIntentosBorrado(bloqueadoHasta: fin);

    final r = await probar('Secreto123');

    expect(r, Left<Failure, Unit>(FailureBorradoBloqueado(hasta: fin)));
    expect(db.llamadas, isNot(contains('desenvolver')));
  });

  test('pasada la espera, se empieza de nuevo con los 5 intentos', () async {
    intentos.estado = EstadoIntentosBorrado(bloqueadoHasta: ahora.add(const Duration(minutes: 5)));
    ahora = ahora.add(const Duration(minutes: 5));

    final r = await probar('otra');

    expect(r, const Left<Failure, Unit>(FailurePasswordBorradoIncorrecta(intentosRestantes: 4)));
  });

  test('contraseña vacía: validación, sin gastar un intento', () async {
    final r = await probar('');

    expect(r.isLeft(), isTrue);
    expect(intentos.estado.fallidos, 0);
    expect(db.llamadas, isNot(contains('desenvolver')));
  });

  test('una falla del almacén no cuenta como intento', () async {
    db.fallas['desenvolver'] = const FailureAlmacenSeguroSinRecuperacion();

    final r = await probar('Secreto123');

    expect(r, const Left<Failure, Unit>(FailureAlmacenSeguroSinRecuperacion()));
    expect(intentos.estado.fallidos, 0);
  });

  group('requisitos', () {
    test('con envoltorio pide contraseña', () async {
      final r = await useCase.requisitos();

      expect(r.getOrElse(() => throw StateError('')).pidePassword, isTrue);
    });

    test('sin envoltorio (Google sin backup) pide solo la frase', () async {
      db.envoltorio = null;

      final r = await useCase.requisitos();

      expect(r.getOrElse(() => throw StateError('')).pidePassword, isFalse);
    });

    test('trae la espera en curso, y una vencida se da de baja', () async {
      intentos.estado = EstadoIntentosBorrado(
        bloqueadoHasta: ahora.add(const Duration(minutes: 2)),
      );
      var r = await useCase.requisitos();
      expect(
        r.getOrElse(() => throw StateError('')).estadoIntentos.bloqueadoHasta,
        ahora.add(const Duration(minutes: 2)),
      );

      ahora = ahora.add(const Duration(minutes: 3));
      r = await useCase.requisitos();
      expect(r.getOrElse(() => throw StateError('')).estadoIntentos.bloqueadoHasta, isNull);
      expect(intentos.limpiezas, 1);
    });

    test('si el almacén no se puede leer, falla (sin saberlo no se confirma nada)', () async {
      db.fallas['estado'] = const FailureAlmacenSeguro();

      final r = await useCase.requisitos();

      expect(r.isLeft(), isTrue);
    });
  });
}
