// HU-AUTH-008 — repositorio del estado de cuenta, con el remoto y el almacén en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/secure_storage/generacion_datos_locales.dart';
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

/// Un backend que contesta cuando el test lo decide, pedido por pedido.
final class _RemotoManual implements EstadoCuentaRemoteDataSource {
  final pedidos = <Completer<EstadoCuenta>>[];

  @override
  Future<EstadoCuenta> consultar() {
    final pedido = Completer<EstadoCuenta>();
    pedidos.add(pedido);
    return pedido.future;
  }
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

  test(
    'recuerda cuándo consultó con éxito por última vez, por cuenta, y no con una falla',
    () async {
      var reloj = DateTime(2026, 9, 30, 14, 30);
      repo = CuentaRepositoryImpl(
        remoto,
        EstadoCuentaEnAlmacen(almacen),
        logger: loggerMudo(),
        ahora: () => reloj,
      );
      expect(repo.ultimaConsultaExitosa('ana'), isNull);

      await repo.consultar('ana');
      reloj = DateTime(2026, 9, 30, 14, 36);
      remoto.simularSinConexion = true;
      await repo.consultar('ana');

      expect(repo.ultimaConsultaExitosa('ana'), DateTime(2026, 9, 30, 14, 30));
      expect(repo.ultimaConsultaExitosa('beto'), isNull);
    },
  );

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

  group('dos consultas que se cruzan: gana la pedida más tarde (QA #278)', () {
    late _RemotoManual manual;

    setUp(() {
      manual = _RemotoManual();
      repo = CuentaRepositoryImpl(manual, EstadoCuentaEnAlmacen(almacen), logger: loggerMudo());
    });

    test('la respuesta vieja que llega después de la nueva no pisa lo recordado', () async {
      final vieja = repo.consultar('ana');
      final nueva = repo.consultar('ana');

      manual.pedidos[1].complete(EstadoCuenta.activa);
      await nueva;
      manual.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);

      // A quien la pidió le llega lo suyo; lo que se recuerda para el próximo arranque, no.
      expect(await vieja, const Right<Failure, EstadoCuenta>(EstadoCuenta.pendienteAsignacion));
      expect(await repo.ultimoConocido('ana'), EstadoCuenta.activa);
    });

    test('si la vieja contesta primero y la nueva después, queda recordada la nueva', () async {
      final vieja = repo.consultar('ana');
      final nueva = repo.consultar('ana');

      manual.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
      await vieja;
      expect(await repo.ultimoConocido('ana'), EstadoCuenta.pendienteAsignacion);
      manual.pedidos[1].complete(EstadoCuenta.suspendida);
      await nueva;

      expect(await repo.ultimoConocido('ana'), EstadoCuenta.suspendida);
    });

    test('una consulta nueva que falló no impide recordar la respuesta de la vieja', () async {
      final vieja = repo.consultar('ana');
      final nueva = repo.consultar('ana');

      manual.pedidos[1].completeError(const SinConexionException());
      expect(await nueva, const Left<Failure, EstadoCuenta>(FailureSinConexion()));
      manual.pedidos[0].complete(EstadoCuenta.suspendida);
      await vieja;

      expect(await repo.ultimoConocido('ana'), EstadoCuenta.suspendida);
    });

    test('lo que se pidió después para otra cuenta no cuenta', () async {
      final deAna = repo.consultar('ana');
      final deBeto = repo.consultar('beto');

      manual.pedidos[1].complete(EstadoCuenta.activa);
      await deBeto;
      manual.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
      await deAna;

      expect(await repo.ultimoConocido('ana'), EstadoCuenta.pendienteAsignacion);
    });

    test('la respuesta vieja tampoco cambia cuándo fue la última revisión', () async {
      var reloj = DateTime(2026, 10, 7, 14, 30);
      repo = CuentaRepositoryImpl(
        manual,
        EstadoCuentaEnAlmacen(almacen),
        logger: loggerMudo(),
        ahora: () => reloj,
      );
      final vieja = repo.consultar('ana');
      final nueva = repo.consultar('ana');
      manual.pedidos[1].complete(EstadoCuenta.activa);
      await nueva;

      reloj = DateTime(2026, 10, 7, 14, 45);
      manual.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
      await vieja;

      expect(repo.ultimaConsultaExitosa('ana'), DateTime(2026, 10, 7, 14, 30));
    });
  });

  group('una respuesta lenta que llega cuando la sesión o los datos ya cambiaron (#319)', () {
    late _RemotoManual manual;
    late GeneracionDatosLocales generacion;
    String? sesionDe;

    setUp(() {
      manual = _RemotoManual();
      generacion = GeneracionDatosLocales();
      sesionDe = 'ana';
      repo = CuentaRepositoryImpl(
        manual,
        EstadoCuentaEnAlmacen(almacen),
        usuarioEnSesion: () => sesionDe,
        generacion: generacion,
        logger: loggerMudo(),
      );
    });

    test(
      'dado el mismo usuario y los mismos datos, la respuesta se recuerda como siempre',
      () async {
        final consulta = repo.consultar('ana');

        manual.pedidos.single.complete(EstadoCuenta.activa);

        expect(await consulta, const Right<Failure, EstadoCuenta>(EstadoCuenta.activa));
        expect(almacen.contenido[ClaveSegura.estadoCuenta], 'ana:activa');
      },
    );

    test('dado que se borraron los datos locales mientras esperaba, la respuesta no reescribe '
        'lo borrado, pero se la devuelve a quien la pidió', () async {
      final consulta = repo.consultar('ana');
      await almacen.escribir(ClaveSegura.estadoCuenta, 'ana:pendienteAsignacion');
      await almacen.borrar(ClaveSegura.estadoCuenta);
      generacion
        ..avanzar()
        ..avanzar();

      manual.pedidos.single.complete(EstadoCuenta.activa);

      expect(await consulta, const Right<Failure, EstadoCuenta>(EstadoCuenta.activa));
      expect(almacen.contenido.containsKey(ClaveSegura.estadoCuenta), isFalse);
      expect(await repo.ultimoConocido('ana'), isNull);
    });

    test('dado que se borraron los datos locales mientras esperaba, la respuesta tampoco cuenta '
        'como una revisión exitosa', () async {
      final consulta = repo.consultar('ana');
      generacion.avanzar();

      manual.pedidos.single.complete(EstadoCuenta.activa);
      await consulta;

      expect(repo.ultimaConsultaExitosa('ana'), isNull);
    });

    test('dado que entró otra cuenta mientras esperaba, la respuesta de la anterior no pisa lo '
        'que recuerda la nueva', () async {
      final deAna = repo.consultar('ana');
      sesionDe = 'beto';
      final deBeto = repo.consultar('beto');

      manual.pedidos[1].complete(EstadoCuenta.activa);
      await deBeto;
      manual.pedidos[0].complete(EstadoCuenta.suspendida);
      await deAna;

      expect(almacen.contenido[ClaveSegura.estadoCuenta], 'beto:activa');
      expect(await repo.ultimoConocido('ana'), isNull);
      expect(await repo.ultimoConocido('beto'), EstadoCuenta.activa);
    });

    test('dado que la otra cuenta todavía no consultó, la respuesta de la anterior tampoco deja '
        'su estado en el único lugar donde se recuerda', () async {
      final deAna = repo.consultar('ana');
      sesionDe = 'beto';

      manual.pedidos.single.complete(EstadoCuenta.suspendida);
      await deAna;

      expect(almacen.contenido.containsKey(ClaveSegura.estadoCuenta), isFalse);
    });

    test('dado que se cerró la sesión mientras esperaba, la respuesta no se recuerda', () async {
      final consulta = repo.consultar('ana');
      sesionDe = null;

      manual.pedidos.single.complete(EstadoCuenta.activa);
      await consulta;

      expect(almacen.contenido.containsKey(ClaveSegura.estadoCuenta), isFalse);
    });

    test(
      'dado que la persona vuelve a entrar con la misma cuenta, la consulta de antes del borrado '
      'se descarta aunque el usuario coincida',
      () async {
        final deAntes = repo.consultar('ana');
        sesionDe = null;
        generacion.avanzar();
        sesionDe = 'ana';
        final deAhora = repo.consultar('ana');

        manual.pedidos[0].complete(EstadoCuenta.activa);
        await deAntes;
        expect(almacen.contenido.containsKey(ClaveSegura.estadoCuenta), isFalse);
        manual.pedidos[1].complete(EstadoCuenta.pendienteAsignacion);
        await deAhora;

        expect(almacen.contenido[ClaveSegura.estadoCuenta], 'ana:pendienteAsignacion');
      },
    );

    test(
      'dado un pedido hecho después del borrado, la respuesta se recuerda con normalidad',
      () async {
        generacion
          ..avanzar()
          ..avanzar();
        final consulta = repo.consultar('ana');

        manual.pedidos.single.complete(EstadoCuenta.activa);
        await consulta;

        expect(almacen.contenido[ClaveSegura.estadoCuenta], 'ana:activa');
        expect(repo.ultimaConsultaExitosa('ana'), isNotNull);
      },
    );

    test('dado que se borraron los datos y la consulta falla, la falla sale igual', () async {
      final consulta = repo.consultar('ana');
      generacion.avanzar();

      manual.pedidos.single.completeError(const SinConexionException());

      expect(await consulta, const Left<Failure, EstadoCuenta>(FailureSinConexion()));
      expect(almacen.contenido.containsKey(ClaveSegura.estadoCuenta), isFalse);
    });
  });

  test('sin fuente (Supabase sin el endpoint del BFF), sigue como hasta ahora: activa', () async {
    expect(await EstadoCuentaSinFuente(logger: loggerMudo()).consultar(), EstadoCuenta.activa);
  });
}
