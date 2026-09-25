// HU-AUTH-008 — estado de la cuenta: siempre del backend. Dart puro.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/cuenta_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/consultar_estado_cuenta_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _CuentaFalsa implements CuentaRepository {
  Either<Failure, EstadoCuenta> respuesta = const Right(EstadoCuenta.activa);
  EstadoCuenta? ultimo;

  @override
  Future<Either<Failure, EstadoCuenta>> consultar(String usuarioId) async => respuesta;

  @override
  Future<EstadoCuenta?> ultimoConocido(String usuarioId) async => ultimo;
}

void main() {
  late _CuentaFalsa cuenta;
  late ConsultarEstadoCuentaUseCase consultar;

  setUp(() {
    cuenta = _CuentaFalsa();
    consultar = ConsultarEstadoCuentaUseCase(cuenta);
  });

  ConsultarEstadoCuentaParams params({required bool admite}) =>
      ConsultarEstadoCuentaParams(usuarioId: 'u', admiteUltimoConocido: admite);

  test('con respuesta del backend, devuelve ese estado aunque haya uno recordado', () async {
    cuenta
      ..respuesta = const Right(EstadoCuenta.pendienteAsignacion)
      ..ultimo = EstadoCuenta.activa;

    expect(
      await consultar(params(admite: true)),
      const Right<Failure, EstadoCuenta>(EstadoCuenta.pendienteAsignacion),
    );
  });

  test('al entrar sin red, rige el último estado que informó el backend', () async {
    cuenta
      ..respuesta = const Left(FailureSinConexion())
      ..ultimo = EstadoCuenta.suspendida;

    expect(
      await consultar(params(admite: true)),
      const Right<Failure, EstadoCuenta>(EstadoCuenta.suspendida),
    );
  });

  test('al entrar sin red y sin estado conocido, no inventa uno: devuelve la falla', () async {
    cuenta.respuesta = const Left(FailureSinConexion());

    expect(
      await consultar(params(admite: true)),
      const Left<Failure, EstadoCuenta>(FailureSinConexion()),
    );
  });

  test('al refrescar a mano sin red, devuelve la falla aunque haya uno recordado', () async {
    cuenta
      ..respuesta = const Left(FailureSinConexion())
      ..ultimo = EstadoCuenta.pendienteAsignacion;

    expect(
      await consultar(params(admite: false)),
      const Left<Failure, EstadoCuenta>(FailureSinConexion()),
    );
  });

  test('solo la cuenta activa accede a los módulos de campo', () {
    expect(EstadoCuenta.activa.accedeAModulosDeCampo, isTrue);
    expect(EstadoCuenta.pendienteAsignacion.accedeAModulosDeCampo, isFalse);
    expect(EstadoCuenta.suspendida.accedeAModulosDeCampo, isFalse);
  });

  test('los params se comparan por valor', () {
    expect(params(admite: true), params(admite: true));
    expect(params(admite: true), isNot(params(admite: false)));
  });
}
