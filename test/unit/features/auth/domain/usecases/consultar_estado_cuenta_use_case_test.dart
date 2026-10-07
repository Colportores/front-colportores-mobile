// HU-AUTH-008 — estado de la cuenta: siempre del backend. Dart puro.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/cuenta_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/consultar_estado_cuenta_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _CuentaFalsa implements CuentaRepository {
  Either<Failure, EstadoCuenta> respuesta = const Right(EstadoCuenta.activa);
  EstadoCuenta? ultimo;

  /// Si está, [consultar] espera a que el test la complete (un backend que no contesta).
  Completer<void>? demora;
  int consultas = 0;

  @override
  Future<Either<Failure, EstadoCuenta>> consultar(String usuarioId) async {
    consultas++;
    await demora?.future;
    return respuesta;
  }

  @override
  Future<EstadoCuenta?> ultimoConocido(String usuarioId) async => ultimo;

  @override
  DateTime? ultimaConsultaExitosa(String usuarioId) => null;
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

  group('tope al entrar (#278)', () {
    const tope = Duration(milliseconds: 40);
    late Completer<void> sinRespuesta;

    setUp(() {
      sinRespuesta = Completer<void>();
      cuenta.demora = sinRespuesta;
      consultar = ConsultarEstadoCuentaUseCase(cuenta, limiteAlEntrar: tope);
    });

    tearDown(() {
      if (!sinRespuesta.isCompleted) sinRespuesta.complete();
    });

    test('el tope es de 15 s, el mismo del GPS', () {
      expect(ConsultarEstadoCuentaUseCase.limiteConsultaAlEntrar, const Duration(seconds: 15));
      expect(ConsultarEstadoCuentaUseCase(cuenta).limiteAlEntrar, const Duration(seconds: 15));
    });

    test('al entrar con un backend que no contesta y sin estado conocido, devuelve sin conexión '
        'al vencer el tope', () async {
      final resultado = await consultar(params(admite: true));

      expect(resultado, const Left<Failure, EstadoCuenta>(FailureSinConexion()));
    });

    test('al entrar con un backend que no contesta, rige el último estado conocido', () async {
      cuenta.ultimo = EstadoCuenta.pendienteAsignacion;

      final resultado = await consultar(params(admite: true));

      expect(resultado, const Right<Failure, EstadoCuenta>(EstadoCuenta.pendienteAsignacion));
    });

    test(
      'la respuesta que llega después del tope no cambia lo ya devuelto ni rompe nada',
      () async {
        final resultado = await consultar(params(admite: true));
        cuenta.respuesta = const Right(EstadoCuenta.activa);

        sinRespuesta.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(resultado, const Left<Failure, EstadoCuenta>(FailureSinConexion()));
        expect(cuenta.consultas, 1);
      },
    );

    test('la respuesta buena que llega después del tope se le pasa a quien la espera', () async {
      final tarde = <EstadoCuenta>[];
      final resultado = await consultar(
        ConsultarEstadoCuentaParams(
          usuarioId: 'u',
          admiteUltimoConocido: true,
          alLlegarTarde: tarde.add,
        ),
      );
      expect(resultado, const Left<Failure, EstadoCuenta>(FailureSinConexion()));
      expect(tarde, isEmpty);
      cuenta.respuesta = const Right(EstadoCuenta.pendienteAsignacion);

      sinRespuesta.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tarde, [EstadoCuenta.pendienteAsignacion]);
      expect(cuenta.consultas, 1);
    });

    test('la falla que llega después del tope no se le pasa a nadie', () async {
      final tarde = <EstadoCuenta>[];
      await consultar(
        ConsultarEstadoCuentaParams(
          usuarioId: 'u',
          admiteUltimoConocido: true,
          alLlegarTarde: tarde.add,
        ),
      );
      cuenta.respuesta = const Left(FailureSinConexion());

      sinRespuesta.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tarde, isEmpty);
    });

    test('una respuesta dentro del tope no pasa por quien espera la tardía', () async {
      final tarde = <EstadoCuenta>[];
      cuenta.respuesta = const Right(EstadoCuenta.suspendida);
      final pendiente = consultar(
        ConsultarEstadoCuentaParams(
          usuarioId: 'u',
          admiteUltimoConocido: true,
          alLlegarTarde: tarde.add,
        ),
      );
      sinRespuesta.complete();

      expect(await pendiente, const Right<Failure, EstadoCuenta>(EstadoCuenta.suspendida));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tarde, isEmpty);
    });

    test('refrescar a mano no tiene respuesta tardía: no llama a quien la espera', () async {
      final tarde = <EstadoCuenta>[];
      cuenta.respuesta = const Right(EstadoCuenta.activa);
      final pendiente = consultar(
        ConsultarEstadoCuentaParams(
          usuarioId: 'u',
          admiteUltimoConocido: false,
          alLlegarTarde: tarde.add,
        ),
      );
      await Future<void>.delayed(tope * 3);
      sinRespuesta.complete();

      expect(await pendiente, const Right<Failure, EstadoCuenta>(EstadoCuenta.activa));
      expect(tarde, isEmpty);
    });

    test('una respuesta dentro del tope se devuelve tal cual', () async {
      cuenta.respuesta = const Right(EstadoCuenta.suspendida);
      final pendiente = consultar(params(admite: true));
      sinRespuesta.complete();

      expect(await pendiente, const Right<Failure, EstadoCuenta>(EstadoCuenta.suspendida));
    });

    test('refrescar a mano no tiene tope: espera la respuesta aunque tarde más', () async {
      cuenta.respuesta = const Right(EstadoCuenta.activa);
      final pendiente = consultar(params(admite: false));
      await Future<void>.delayed(tope * 3);
      sinRespuesta.complete();

      expect(await pendiente, const Right<Failure, EstadoCuenta>(EstadoCuenta.activa));
    });
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
