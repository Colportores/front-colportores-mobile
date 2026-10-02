// Cierre de sesión: además de invalidar la sesión, cierra la DB local y destruye la clave
// (HU-AUTH-006, ADR-003). Con SQLCipher real en un directorio temporal.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/sesion_usuario_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cambios_por_recuperacion_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_cierre_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/ultimo_correo_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
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

/// Borrado de datos que termina como se le diga: lo único que importa acá es qué hace la sesión.
final class _DatosQueBorran implements DatosLocalesRepository {
  Either<Failure, ResultadoBorradoDatosLocales> respuesta = const Right(
    ResultadoBorradoDatosLocales.completo,
  );

  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() => throw UnimplementedError();

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async => respuesta;
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

/// Almacén seguro donde escribir tarda: sirve para probar el orden de las operaciones.
final class _AlmacenLento implements AlmacenSeguro {
  String? contenido;
  final operaciones = <String>[];

  @override
  Future<String?> leer(ClaveSegura clave) async => contenido;

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    operaciones.add('escribir');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    contenido = valor;
  }

  @override
  Future<void> borrar(ClaveSegura clave) async {
    operaciones.add('borrar');
    contenido = null;
  }

  @override
  Future<void> borrarTodo() async => contenido = null;
}

/// Un correo que, contra su contrato, lanza al borrar: el cierre que ya está fallando no puede
/// perder el error original por eso.
final class _CorreoQueExplotaAlBorrar implements UltimoCorreoRepository {
  @override
  Future<String?> leer() async => 'ana@example.com';

  @override
  Future<void> guardar(String email) async {}

  @override
  Future<void> borrar() async => throw StateError('el almacén no responde');
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

    test('dado el nombre del usuario guardado en la DB, cuando cierra sesión, se borra con el '
        'resto (#243) y no queda en el teléfono', () async {
      await iniciarSesion();
      final bytes = List<int>.filled(32, 4);
      final db = await container
          .read(dbLocalProvider.notifier)
          .abrir(ClaveDb(Uint8List.fromList(bytes)));
      await SesionUsuarioLocalDataSource(db).guardar('u-1', 'Lucía');

      await container.read(sesionProvider.notifier).cerrarSesion();

      expect(container.read(sesionProvider).value, isNull);
      final reabierta = await helper.abrir(ClaveDb(Uint8List.fromList(bytes)));
      expect(await reabierta.select(reabierta.sesionUsuarios).get(), isEmpty);
    });

    test('dado que la sesión guardada no se puede borrar (el usuario sigue adentro), el nombre '
        'se conserva', () async {
      await iniciarSesion();
      final bytes = List<int>.filled(32, 4);
      final db = await container
          .read(dbLocalProvider.notifier)
          .abrir(ClaveDb(Uint8List.fromList(bytes)));
      await SesionUsuarioLocalDataSource(db).guardar('u-1', 'Lucía');
      local.explotar = true;

      final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

      expect(resultado.isLeft(), isTrue);
      expect(await SesionUsuarioLocalDataSource(db).leer('u-1'), 'Lucía');
    });

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

    test('el cierre sin red solo deja el aviso del login si quien cierra lo pide', () async {
      await iniciarSesion();
      remote.simularSinConexion = true;

      await container.read(sesionProvider.notifier).cerrarSesion();

      expect(container.read(sesionProvider).value, isNull);
      expect(
        container.read(avisoSesionProvider),
        isNull,
        reason: 'recuperación de contraseña y preparación de la DB cierran sin ese aviso',
      );
    });

    test('desde Configuración, el cierre sin red deja el aviso «Cerraste sesión…»', () async {
      await iniciarSesion();
      remote.simularSinConexion = true;

      await container.read(sesionProvider.notifier).cerrarSesion(avisarCierreSinConexion: true);

      expect(container.read(avisoSesionProvider), const FailureCierreSesionSinConexion());
    });

    test('con red, pedir el aviso no deja ninguno: el cierre fue completo', () async {
      await iniciarSesion();

      await container.read(sesionProvider.notifier).cerrarSesion(avisarCierreSinConexion: true);

      expect(container.read(avisoSesionProvider), isNull);
    });

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
  group('SesionNotifier — correo de la última cuenta (decisión de Cristian, 01/10)', () {
    late Directory directorio;
    late DatabaseHelper helper;
    late AuthRemoteDataSourceEnMemoria remote;
    late _LocalQueFalla local;
    late UltimoCorreoEnMemoria correo;
    late _DatosQueBorran datos;
    late CambiosPorRecuperacionEnMemoria cambios;
    late ProviderContainer container;

    ProviderContainer crear() => ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(local),
        databaseHelperProvider.overrideWithValue(helper),
        ultimoCorreoRepositoryProvider.overrideWithValue(correo),
        datosLocalesRepositoryProvider.overrideWithValue(datos),
        cambiosPorRecuperacionProvider.overrideWithValue(cambios),
      ],
    );

    setUp(() async {
      directorio = await Directory.systemTemp.createTemp('colportores_ultimo_correo_test');
      helper = DatabaseHelper(
        directorio: () async => directorio,
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      remote = AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});
      local = _LocalQueFalla();
      correo = UltimoCorreoEnMemoria();
      datos = _DatosQueBorran();
      cambios = CambiosPorRecuperacionEnMemoria();
      container = crear();
    });

    tearDown(() async {
      container.dispose();
      await helper.cerrar();
      await directorio.delete(recursive: true);
    });

    Future<void> entrar() async {
      await container.read(sesionProvider.future);
      final falla = await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
      expect(falla, isNull);
      await pumpEventQueue();
    }

    test('al entrar con correo y contraseña guarda solo el correo', () async {
      await entrar();

      expect(await correo.leer(), 'ana@example.com');
    });

    test('al entrar con Google guarda el correo de esa cuenta', () async {
      await container.read(sesionProvider.future);
      await container.read(sesionProvider.notifier).iniciarSesionConGoogle();
      await pumpEventQueue();

      expect(await correo.leer(), container.read(sesionProvider).value!.email);
    });

    test('al registrarse con una sesión que queda adentro guarda el correo', () async {
      await container.read(sesionProvider.future);
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
      await pumpEventQueue();

      expect(await correo.leer(), 'nueva@example.com');
    });

    test(
      'una sesión restaurada al arrancar también lo guarda (cuentas que entraron antes)',
      () async {
        await entrar();
        await correo.borrar();
        container.dispose();

        container = crear();
        await container.read(sesionProvider.future);
        await pumpEventQueue();

        expect(await correo.leer(), 'ana@example.com');
      },
    );

    test('si el que entra es otro, el correo guardado pasa a ser el suyo', () async {
      await correo.guardar('vieja@example.com');
      remote = AuthRemoteDataSourceEnMemoria(credenciales: const {'luis@example.com': 'otra12345'});
      container.dispose();
      container = crear();
      await container.read(sesionProvider.future);

      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'luis@example.com', password: 'otra12345');
      await pumpEventQueue();

      expect(await correo.leer(), 'luis@example.com');
    });

    test('arranque en frío con la sesión vencida por inactividad: «Sesión vencida» ya trae el '
        'correo guardado, sin sesión de dónde sacarlo', () async {
      await correo.guardar('ana@example.com');
      remote.vencidaPorInactividadAlArrancar = true;

      expect(await container.read(sesionProvider.future), isNull);

      final reingreso = container.read(reingresoSesionProvider)!;
      expect(reingreso.motivo, MotivoExpiracion.inactividad);
      expect(reingreso.email, 'ana@example.com');
    });

    test('arranque en frío vencido sin correo guardado: no inventa uno', () async {
      remote.vencidaPorInactividadAlArrancar = true;

      await container.read(sesionProvider.future);

      expect(container.read(reingresoSesionProvider)!.email, isNull);
      expect(container.read(avisoSesionProvider), isNotNull);
    });

    test('arranque en frío sin motivo de vencimiento (login común): no hay reingreso', () async {
      await correo.guardar('ana@example.com');

      await container.read(sesionProvider.future);

      expect(container.read(reingresoSesionProvider), isNull);
    });

    test('cuando la sesión termina con la app abierta, el correo guardado se conserva', () async {
      await entrar();

      remote.simularExpiracion(MotivoExpiracion.revocada);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(await correo.leer(), 'ana@example.com');
      expect(container.read(reingresoSesionProvider)?.email, 'ana@example.com');
    });

    test('cerrar sesión a propósito borra el correo', () async {
      await entrar();

      await container.read(sesionProvider.notifier).cerrarSesion();

      expect(await correo.leer(), isNull);
    });

    test('si cerrar sesión falla (el usuario sigue adentro) el correo se conserva', () async {
      await entrar();
      local.explotar = true;

      final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

      expect(resultado.isLeft(), isTrue);
      expect(await correo.leer(), 'ana@example.com');
    });

    test('entrar y cerrar sesión enseguida, sin esperar el guardado, termina sin correo', () async {
      // Con el almacén real el guardado puede tardar: el borrado pedido después tiene que ganar.
      final lento = _AlmacenLento();
      correo = UltimoCorreoEnMemoria();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(local),
          databaseHelperProvider.overrideWithValue(helper),
          ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(lento)),
          datosLocalesRepositoryProvider.overrideWithValue(datos),
        ],
      );
      await container.read(sesionProvider.future);
      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');

      await container.read(sesionProvider.notifier).cerrarSesion();
      await pumpEventQueue();

      expect(lento.contenido, isNull);
      expect(lento.operaciones, ['escribir', 'borrar']);
    });

    test('borrar los datos locales borra el correo', () async {
      await entrar();

      final resultado = await container
          .read(sesionProvider.notifier)
          .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

      expect(resultado.isRight(), isTrue);
      expect(await correo.leer(), isNull);
      expect(container.read(sesionProvider).value, isNull);
    });

    test(
      'si el borrado de datos falla, el usuario sigue adentro y el correo se conserva',
      () async {
        await entrar();
        datos.respuesta = const Left(FailureDatosLocalesIlegibles());

        final resultado = await container
            .read(sesionProvider.notifier)
            .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

        expect(resultado.isLeft(), isTrue);
        expect(await correo.leer(), 'ana@example.com');
      },
    );

    test(
      'el cierre que hace la app por la recuperación de contraseña conserva el correo',
      () async {
        await entrar();

        final resultado = await container
            .read(sesionProvider.notifier)
            .cerrarSesion(conservarCorreo: true);

        expect(resultado.isRight(), isTrue);
        expect(container.read(sesionProvider).value, isNull, reason: 'la sesión se cerró');
        expect(await correo.leer(), 'ana@example.com');
      },
    );

    test('con conservarCorreo, un cierre que falla tampoco toca el correo', () async {
      await entrar();
      local.explotar = true;

      final resultado = await container
          .read(sesionProvider.notifier)
          .cerrarSesion(conservarCorreo: true);

      expect(resultado.isLeft(), isTrue);
      expect(await correo.leer(), 'ana@example.com');
    });

    group('cuando el use case de cerrar sesión lanza pero la sesión se cierra igual', () {
      Future<ProviderContainer> conUseCaseQueLanza(UltimoCorreoRepository repoCorreo) async {
        final repo = _MockAuthRepository();
        when(repo.sesionActual).thenAnswer((_) async => const Right(null));
        when(repo.reintentarRevocacionPendiente).thenAnswer((_) async => const Right(unit));
        when(() => repo.expiraciones).thenAnswer((_) => const Stream.empty());
        when(repo.cerrarSesion).thenThrow(const _FallaDeAlmacen());
        final c = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
            databaseHelperProvider.overrideWithValue(helper),
            ultimoCorreoRepositoryProvider.overrideWithValue(repoCorreo),
          ],
        );
        addTearDown(c.dispose);
        await c.read(sesionProvider.future);
        return c;
      }

      test('el correo se borra igual y el error original se propaga', () async {
        await correo.guardar('ana@example.com');
        final c = await conUseCaseQueLanza(correo);

        await expectLater(
          c.read(sesionProvider.notifier).cerrarSesion(),
          throwsA(isA<_FallaDeAlmacen>()),
        );

        expect(await correo.leer(), isNull);
        expect(c.read(sesionProvider).value, isNull);
      });

      test('con conservarCorreo, el correo queda', () async {
        await correo.guardar('ana@example.com');
        final c = await conUseCaseQueLanza(correo);

        await expectLater(
          c.read(sesionProvider.notifier).cerrarSesion(conservarCorreo: true),
          throwsA(isA<_FallaDeAlmacen>()),
        );

        expect(await correo.leer(), 'ana@example.com');
      });

      test(
        'si borrar el correo también falla, no tapa el error original ni deja la DB abierta',
        () async {
          final c = await conUseCaseQueLanza(_CorreoQueExplotaAlBorrar());
          final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 4)));
          await c.read(dbLocalProvider.notifier).abrir(clave);

          await expectLater(
            c.read(sesionProvider.notifier).cerrarSesion(),
            throwsA(isA<_FallaDeAlmacen>()),
          );

          expect(helper.abierta, isFalse);
          expect(clave.destruida, isTrue);
          expect(c.read(sesionProvider).value, isNull);
        },
      );
    });

    test('borrar los datos locales también olvida la marca de «cambié la contraseña con un '
        'enlace» que la corrida tiene en memoria', () async {
      await entrar();
      await cambios.registrar();
      expect(await cambios.hayUnoReciente(), isTrue);

      final resultado = await container
          .read(sesionProvider.notifier)
          .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

      expect(resultado.isRight(), isTrue);
      expect(await cambios.hayUnoReciente(), isFalse);
    });

    test('si el borrado de datos falla, la marca se conserva (el usuario sigue adentro)', () async {
      await entrar();
      await cambios.registrar();
      datos.respuesta = const Left(FailureDatosLocalesIlegibles());

      await container
          .read(sesionProvider.notifier)
          .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

      expect(await cambios.hayUnoReciente(), isTrue);
    });
  });
}
