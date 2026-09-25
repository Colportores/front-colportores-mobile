// Cierre de sesión: además de invalidar la sesión, cierra la DB local y destruye la clave
// (HU-AUTH-006, ADR-003). Con SQLCipher real en un directorio temporal.
import 'dart:async';
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
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_cierre_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Almacén local que empieza sano y se rompe cuando se le pide: para cerrar sesión primero hay que
/// haberla iniciado. `AuthRepositoryImpl.cerrarSesion` traduce la falla a un `Left`.
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

class _MockAuthRepository extends Mock implements AuthRepository {}

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

    test(
      'cuando la sesión guardada no se puede borrar, devuelve el Left y el usuario sigue adentro '
      'con la DB abierta (#54)',
      () async {
        await iniciarSesion();
        final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
        await container.read(dbLocalProvider.notifier).abrir(clave);
        local.explotar = true;

        final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

        expect(resultado.isLeft(), isTrue);
        expect(
          container.read(sesionProvider).value,
          isNotNull,
          reason: 'la sesión sigue guardada: mostrar el login sería mentirle al usuario',
        );
        expect(helper.abierta, isTrue);
        expect(clave.destruida, isFalse);
      },
    );

    test('cuando cerrar la DB falla, igual deja la sesión cerrada y no lo propaga', () async {
      final conFallas = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(local),
          databaseHelperProvider.overrideWithValue(helper),
          dbLocalProvider.overrideWith(_DbLocalQueFallaAlCerrar.new),
        ],
      );
      addTearDown(conFallas.dispose);
      await conFallas.read(sesionProvider.future);
      await conFallas
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
      final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
      await conFallas.read(dbLocalProvider.notifier).abrir(clave);

      final resultado = await conFallas.read(sesionProvider.notifier).cerrarSesion();

      expect(
        resultado,
        const Right<Failure, ResultadoCierreSesion>(ResultadoCierreSesion.completo),
      );
      expect(conFallas.read(sesionProvider).value, isNull);
      expect(helper.abierta, isFalse);
      expect(clave.destruida, isTrue);
    });

    test(
      'cuando el use case lanza, cierra la DB, deja la sesión cerrada, loguea y propaga',
      () async {
        final salida = _SalidaEnMemoria();
        final repo = _MockAuthRepository();
        when(repo.sesionActual).thenAnswer((_) async => const Right(null));
        when(repo.reintentarRevocacionPendiente).thenAnswer((_) async => const Right(unit));
        when(() => repo.expiraciones).thenAnswer((_) => const Stream.empty());
        when(repo.cerrarSesion).thenThrow(const _FallaDeAlmacen());
        final conFallas = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
            databaseHelperProvider.overrideWithValue(helper),
            sesionProvider.overrideWith(() => SesionNotifier(logger: AppLogger(output: salida))),
          ],
        );
        addTearDown(conFallas.dispose);
        await conFallas.read(sesionProvider.future);
        final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
        await conFallas.read(dbLocalProvider.notifier).abrir(clave);

        await expectLater(
          conFallas.read(sesionProvider.notifier).cerrarSesion(),
          throwsA(isA<_FallaDeAlmacen>()),
        );

        expect(salida.lineas, anyElement(startsWith('[ERROR][AUTH][LOGOUT_FAIL]')));
        expect(conFallas.read(sesionProvider).value, isNull);
        expect(
          helper.abierta,
          isFalse,
          reason: 'deslogueado con la DB abierta es peor que el error',
        );
        expect(clave.destruida, isTrue);
      },
    );

    test(
      'dado un logout sin red, cuando vuelve a iniciar sesión, reintenta la revocación pendiente',
      () async {
        await iniciarSesion();
        remote.simularSinConexion = true;

        final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

        expect(
          resultado,
          const Right<Failure, ResultadoCierreSesion>(ResultadoCierreSesion.revocacionPendiente),
        );
        expect(container.read(sesionProvider).value, isNull);

        remote.simularSinConexion = false;
        await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
        await pumpEventQueue();

        expect(remote.revocaciones, hasLength(1));
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
            aceptaTradeOffE2E: true,
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
              aceptaTradeOffE2E: true,
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
            aceptaTradeOffE2E: true,
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

  group('SesionNotifier — fin de sesión forzado (HU-AUTH-007)', () {
    late Directory directorio;
    late DatabaseHelper helper;
    late AuthRemoteDataSourceEnMemoria remote;
    late ProviderContainer container;

    setUp(() async {
      directorio = await Directory.systemTemp.createTemp('colportores_expiracion_test');
      helper = DatabaseHelper(
        directorio: () async => directorio,
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      remote = AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});
      container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          databaseHelperProvider.overrideWithValue(helper),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await helper.cerrar();
      await directorio.delete(recursive: true);
    });

    Future<ClaveDb> entrarConDbAbierta() async {
      await container.read(sesionProvider.future);
      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
      final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
      await container.read(dbLocalProvider.notifier).abrir(clave);
      return clave;
    }

    /// Espera a que el estado real quede sin sesión. El cierre de la DB pasa por el isolate de
    /// drift, y `pumpEventQueue` no espera mensajes entre isolates: en un runner lento el estado
    /// todavía tenía la sesión (falla intermitente en el CI del PR #130).
    Future<void> sesionCerrada() {
      final cerrada = Completer<void>();
      final escucha = container.listen(sesionProvider, (_, estado) {
        if (estado case AsyncData(value: null) when !cerrada.isCompleted) cerrada.complete();
      }, fireImmediately: true);
      return cerrada.future.whenComplete(escucha.close);
    }

    for (final (motivo, aviso) in const [
      (MotivoExpiracion.revocada, FailureSesionRevocada()),
      (MotivoExpiracion.inactividad, FailureSesionExpiradaPorInactividad()),
    ]) {
      test(
        'dado sesión y DB abierta, cuando la sesión termina por ${motivo.name}, vuelve al login '
        'con el aviso y cierra la DB sin borrar el archivo (lo que falta sincronizar sigue ahí)',
        () async {
          final clave = await entrarConDbAbierta();
          final archivo = await helper.archivo();
          expect(archivo.existsSync(), isTrue);

          remote.simularExpiracion(motivo);
          await sesionCerrada();

          expect(container.read(sesionProvider).value, isNull);
          expect(container.read(avisoSesionProvider), aviso);
          expect(helper.abierta, isFalse);
          expect(clave.destruida, isTrue);
          expect(archivo.existsSync(), isTrue, reason: 'es un cierre de sesión, no un borrado');
          expect(remote.llamadasCerrarSesion, 0, reason: 'no espera a la red');
        },
      );
    }

    test('dado un fin de sesión sin nadie adentro (el login ya está a la vista), solo deja el '
        'aviso', () async {
      await container.read(sesionProvider.future);

      remote.simularExpiracion(MotivoExpiracion.revocada);
      await pumpEventQueue();

      expect(container.read(sesionProvider).value, isNull);
      expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
    });

    test('Escenario: Expiración por inactividad — al arrancar con la sesión descartada por 30 días '
        'sin uso, queda en el login con el aviso de la HU', () async {
      remote.vencidaPorInactividadAlArrancar = true;

      expect(await container.read(sesionProvider.future), isNull);
      expect(
        container.read(avisoSesionProvider)?.mensaje,
        'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.',
      );
    });

    test('al volver a entrar, el aviso desaparece', () async {
      remote.vencidaPorInactividadAlArrancar = true;
      await container.read(sesionProvider.future);

      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');

      expect(container.read(avisoSesionProvider), isNull);
    });

    test('con Google o con un registro que deja sesión, el aviso también desaparece', () async {
      remote.vencidaPorInactividadAlArrancar = true;
      await container.read(sesionProvider.future);
      await container.read(sesionProvider.notifier).iniciarSesionConGoogle();
      expect(container.read(avisoSesionProvider), isNull);

      container.read(avisoSesionProvider.notifier).mostrar(const FailureSesionRevocada());
      await container
          .read(sesionProvider.notifier)
          .registrar(
            nombre: 'Ana',
            apellido: 'Pérez',
            cedula: '12345672',
            email: 'nueva@example.com',
            password: 'Secreto123',
            aceptaTerminos: true,
            aceptaTradeOffE2E: true,
          );
      expect(container.read(avisoSesionProvider), isNull);
    });
  });
}
