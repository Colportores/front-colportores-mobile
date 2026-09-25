// HU-AUTH-008 — repositorio del estado de cuenta, con el remoto y el almacén en memoria.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cuenta_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _RemotoRoto implements EstadoCuentaRemoteDataSource {
  @override
  Future<EstadoCuenta> consultar() async => throw StateError('boom');
}

void main() {
  late EstadoCuentaEnMemoria remoto;
  late AlmacenSeguroEnMemoria almacen;
  late CuentaRepositoryImpl repo;

  setUp(() {
    remoto = EstadoCuentaEnMemoria(estado: EstadoCuenta.pendienteAsignacion);
    almacen = AlmacenSeguroEnMemoria();
    repo = CuentaRepositoryImpl(remoto, EstadoCuentaEnAlmacen(almacen), logger: loggerMudo());
  });

  test('consulta al backend y lo recuerda con el usuario', () async {
    expect(
      await repo.consultar('ana'),
      const Right<Failure, EstadoCuenta>(EstadoCuenta.pendienteAsignacion),
    );
    expect(almacen.contenido[ClaveSegura.estadoCuenta], 'ana:pendienteAsignacion');
    expect(await repo.ultimoConocido('ana'), EstadoCuenta.pendienteAsignacion);
  });

  test('otra cuenta en el mismo equipo no hereda el estado', () async {
    await repo.consultar('ana');

    expect(await repo.ultimoConocido('beto'), isNull);
  });

  test('sin red, FailureSinConexion y no toca lo recordado', () async {
    await repo.consultar('ana');
    remoto
      ..simularSinConexion = true
      ..estado = EstadoCuenta.activa;

    expect(await repo.consultar('ana'), const Left<Failure, EstadoCuenta>(FailureSinConexion()));
    expect(await repo.ultimoConocido('ana'), EstadoCuenta.pendienteAsignacion);
  });

  test('con el BFF en error, FailureServidor con su mensaje si lo trae', () async {
    remoto.falla = const ServidorException(status: 503);
    expect(
      await repo.consultar('ana'),
      const Left<Failure, EstadoCuenta>(FailureServidor(status: 503)),
    );

    remoto.falla = const ServidorException(status: 500, mensaje: 'x');
    expect(
      await repo.consultar('ana'),
      const Left<Failure, EstadoCuenta>(FailureServidor(status: 500, mensaje: 'x')),
    );
  });

  test('una excepción inesperada sale como FailureInesperado', () async {
    final roto = CuentaRepositoryImpl(
      _RemotoRoto(),
      EstadoCuentaLocalEnMemoria(),
      logger: loggerMudo(),
    );

    expect((await roto.consultar('ana')).fold((f) => f, (_) => null), isA<FailureInesperado>());
  });

  test('si el almacén falla, el estado consultado vale igual y el recordado es null', () async {
    almacen.simularFalla = true;

    expect(
      await repo.consultar('ana'),
      const Right<Failure, EstadoCuenta>(EstadoCuenta.pendienteAsignacion),
    );
    expect(await repo.ultimoConocido('ana'), isNull);
  });

  test('un valor guardado que no es un estado se ignora', () async {
    almacen = AlmacenSeguroEnMemoria({ClaveSegura.estadoCuenta: 'ana:otracosa'});
    repo = CuentaRepositoryImpl(remoto, EstadoCuentaEnAlmacen(almacen), logger: loggerMudo());

    expect(await repo.ultimoConocido('ana'), isNull);
  });

  test('sin fuente (Supabase sin el endpoint del BFF), sigue como hasta ahora: activa', () async {
    expect(await EstadoCuentaSinFuente(logger: loggerMudo()).consultar(), EstadoCuenta.activa);
  });
}
