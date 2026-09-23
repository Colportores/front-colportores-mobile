// Cierre de sesión: además de invalidar la sesión, cierra la DB local y destruye la clave
// (HU-AUTH-006, ADR-003). Con SQLCipher real en un directorio temporal.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Almacén local que empieza sano y se rompe cuando se le pide: para cerrar sesión primero hay que
/// haberla iniciado. `AuthRepositoryImpl.cerrarSesion` lee la sesión fuera de su `try`, así que la
/// falla escapa del use case tal cual, que es el caso que importa acá.
final class _LocalQueFalla implements AuthLocalDataSource {
  final AuthLocalDataSourceEnMemoria _real = AuthLocalDataSourceEnMemoria();

  bool explotar = false;

  @override
  Future<SesionModel?> leerSesion() async {
    if (explotar) throw const _FallaDeAlmacen();
    return _real.leerSesion();
  }

  @override
  Future<void> guardarSesion(SesionModel sesion) => _real.guardarSesion(sesion);

  @override
  Future<void> borrarSesion() => _real.borrarSesion();
}

final class _FallaDeAlmacen implements Exception {
  const _FallaDeAlmacen();
}

/// Cierra de verdad (la clave se destruye, como hace `DatabaseHelper.cerrar` aunque falle) y
/// después lanza: es un cierre de la DB que falla.
class _DbLocalQueFallaAlCerrar extends DbLocalNotifier {
  @override
  Future<void> cerrar() async {
    await super.cerrar();
    throw const DbLocalException(operacion: 'cerrar');
  }
}

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  group('SesionNotifier.cerrarSesion', () {
    late Directory directorio;
    late DatabaseHelper helper;
    late AuthRemoteDataSourceEnMemoria remote;
    late _LocalQueFalla local;
    late ProviderContainer container;

    setUp(() async {
      directorio = await Directory.systemTemp.createTemp('colportores_sesion_test');
      helper = DatabaseHelper(
        directorio: () async => directorio,
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      remote = AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});
      local = _LocalQueFalla();
      container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(local),
          databaseHelperProvider.overrideWithValue(helper),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await helper.cerrar();
      await directorio.delete(recursive: true);
    });

    Future<void> iniciarSesion() async {
      await container.read(sesionProvider.future);
      final falla = await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
      expect(falla, isNull);
    }

    test(
      'dado sesión y DB abierta, cuando cierra sesión, cierra la DB y destruye la clave',
      () async {
        await iniciarSesion();
        final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
        await container.read(dbLocalProvider.notifier).abrir(clave);

        await container.read(sesionProvider.notifier).cerrarSesion();

        expect(container.read(sesionProvider).value, isNull);
        expect(container.read(dbLocalProvider), isNull);
        expect(helper.abierta, isFalse);
        expect(clave.destruida, isTrue);
        expect(remote.llamadasCerrarSesion, 1);
      },
    );

    test('dado sesión sin DB abierta, cuando cierra sesión, no falla ni toca el helper', () async {
      await iniciarSesion();

      await expectLater(container.read(sesionProvider.notifier).cerrarSesion(), completes);

      expect(container.read(sesionProvider).value, isNull);
      expect(container.read(dbLocalProvider), isNull);
      expect(helper.abierta, isFalse);
    });

    test('cuando el use case lanza, igual cierra la DB y deja la sesión cerrada', () async {
      await iniciarSesion();
      final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
      await container.read(dbLocalProvider.notifier).abrir(clave);
      local.explotar = true;

      await expectLater(
        container.read(sesionProvider.notifier).cerrarSesion(),
        throwsA(isA<Exception>()),
      );

      expect(
        container.read(sesionProvider).value,
        isNull,
        reason: 'la sesión ya se dio por cerrada: la app no puede seguir mostrando al usuario',
      );
      expect(container.read(dbLocalProvider), isNull);
      expect(helper.abierta, isFalse, reason: 'deslogueado con la DB abierta es peor que el error');
      expect(clave.destruida, isTrue);
    });

    test(
      'cuando fallan el use case y el cierre de la DB, propaga y loguea la del use case',
      () async {
        final salida = _SalidaEnMemoria();
        final conFallas = ProviderContainer(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(remote),
            authLocalDataSourceProvider.overrideWithValue(local),
            databaseHelperProvider.overrideWithValue(helper),
            dbLocalProvider.overrideWith(_DbLocalQueFallaAlCerrar.new),
            sesionProvider.overrideWith(() => SesionNotifier(logger: AppLogger(output: salida))),
          ],
        );
        addTearDown(conFallas.dispose);
        await conFallas.read(sesionProvider.future);
        final falla = await conFallas
            .read(sesionProvider.notifier)
            .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
        expect(falla, isNull);
        final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
        await conFallas.read(dbLocalProvider.notifier).abrir(clave);
        local.explotar = true;

        await expectLater(
          conFallas.read(sesionProvider.notifier).cerrarSesion(),
          throwsA(isA<_FallaDeAlmacen>()),
          reason: 'la del cierre de la DB ya la loguea el helper; la que se perdía era esta',
        );

        expect(
          salida.lineas,
          anyElement(startsWith('[ERROR][AUTH][LOGOUT_FAIL]')),
          reason: 'un logout que no se completó no puede quedar sin rastro',
        );
        expect(conFallas.read(sesionProvider).value, isNull);
        expect(helper.abierta, isFalse);
        expect(clave.destruida, isTrue);
      },
    );

    test('dado una apertura de la DB en vuelo, cuando cierra sesión, no la deja abierta', () async {
      await iniciarSesion();
      final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));

      final apertura = container.read(dbLocalProvider.notifier).abrir(clave);
      await container.read(sesionProvider.notifier).cerrarSesion();
      await apertura;

      expect(container.read(sesionProvider).value, isNull);
      expect(container.read(dbLocalProvider), isNull);
      expect(helper.abierta, isFalse);
      expect(clave.destruida, isTrue);
    });
  });

  group('SesionNotifier.iniciarSesionConGoogle', () {
    test('cuando el proveedor entra, deja la sesión iniciada', () async {
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(
            AuthRemoteDataSourceEnMemoria(credenciales: const {}),
          ),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);

      final falla = await container.read(sesionProvider.notifier).iniciarSesionConGoogle();

      expect(falla, isNull);
      expect(
        container.read(sesionProvider).value?.email,
        AuthRemoteDataSourceEnMemoria.emailGoogle,
      );
    });

    test('cuando falla (sin red), deja el Failure y sigue deslogueado', () async {
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(
            AuthRemoteDataSourceEnMemoria(credenciales: const {}, simularSinConexion: true),
          ),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);

      final falla = await container.read(sesionProvider.notifier).iniciarSesionConGoogle();

      expect(falla, isA<FailureSinConexion>());
      expect(container.read(sesionProvider).value, isNull);
    });
  });

  group('SesionNotifier.registrar', () {
    ProviderContainer construirContainer(AuthRemoteDataSourceEnMemoria remote) => ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
    );

    test('dado un email nuevo, cuando registra, deja la sesión iniciada', () async {
      final container = construirContainer(AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);

      final resultado = await container
          .read(sesionProvider.notifier)
          .registrar(
            nombre: 'Ana',
            apellido: 'Pérez',
            cedula: '12345678',
            email: 'ana@example.com',
            password: 'Secreto123',
            aceptaTerminos: true,
          );

      expect(resultado.isRight(), isTrue);
      expect(
        resultado.getOrElse(() => throw StateError('esperaba Right')).requiereVerificacion,
        isFalse,
      );
      expect(container.read(sesionProvider).value?.email, 'ana@example.com');
    });

    test(
      'dado un email ya registrado, cuando registra, deja el Failure y no inicia sesión',
      () async {
        final container = construirContainer(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'Secreto123'}),
        );
        addTearDown(container.dispose);
        await container.read(sesionProvider.future);

        final resultado = await container
            .read(sesionProvider.notifier)
            .registrar(
              nombre: 'Ana',
              apellido: 'Pérez',
              cedula: '12345678',
              email: 'ana@example.com',
              password: 'OtraSecreta1',
              aceptaTerminos: true,
            );

        expect(resultado.fold((f) => f, (_) => null), isA<FailureEmailYaRegistrado>());
        expect(container.read(sesionProvider).value, isNull);
      },
    );

    test('dado que falta verificar el email, cuando registra, no deja sesión iniciada', () async {
      final container = construirContainer(
        AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        ),
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);

      final resultado = await container
          .read(sesionProvider.notifier)
          .registrar(
            nombre: 'Ana',
            apellido: 'Pérez',
            cedula: '12345678',
            email: 'ana@example.com',
            password: 'Secreto123',
            aceptaTerminos: true,
          );

      expect(resultado.isRight(), isTrue);
      final r = resultado.getOrElse(() => throw StateError('esperaba Right'));
      expect(r.requiereVerificacion, isTrue);
      expect(container.read(sesionProvider).value, isNull);
    });
  });

  group('SesionNotifier.reenviarVerificacion', () {
    test('cuando reenvía, no toca el estado de sesión', () async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);

      final falla = await container
          .read(sesionProvider.notifier)
          .reenviarVerificacion('ana@example.com');

      expect(falla, isNull);
      expect(remote.reenviosPorEmail['ana@example.com'], 1);
      expect(container.read(sesionProvider).value, isNull);
    });
  });
}
