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
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:colportores_mobile/features/auth/data/datasources/sesion_usuario_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/cierre_forzado.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/reenvios_guardados.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_cierre_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/cierre_forzado_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/ultimo_correo_repository.dart';
import 'package:colportores_mobile/features/auth/domain/services/reloj_sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
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

  /// Si no es `null`, [leerSesion] no sigue hasta que el test la complete: el arranque con la
  /// sesión todavía leyéndose (#311).
  Completer<void>? puerta;

  @override
  Future<SesionModel?> leerSesion() async {
    await puerta?.future;
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

/// Reloj de la sesión cuya lectura se puede retener (el Keystore lento): con [retener] en `true`,
/// cada lectura espera su propio turno en [turnos], que el test completa en el orden que quiera.
final class _RelojPorTurnos implements RelojSesion {
  _RelojPorTurnos(this._sistema);

  final DateTime Function() _sistema;
  bool retener = false;
  final turnos = <Completer<DateTime>>[];

  @override
  Future<DateTime> ahora() {
    if (!retener) return Future.value(_sistema());
    final turno = Completer<DateTime>();
    turnos.add(turno);
    return turno.future;
  }

  @override
  Future<void> registrar(DateTime visto) async {}
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

/// Un cierre guardado que, contra su contrato, lanza al borrar: el cierre de sesión que ya está
/// fallando no puede perder el error original por eso.
final class _CierreQueExplotaAlBorrar implements CierreForzadoRepository {
  @override
  Future<CierreForzado?> leer() async => null;

  @override
  Future<void> guardar(CierreForzado cierre) async {}

  @override
  Future<void> borrar() async => throw StateError('el almacén no responde');
}

/// Reenvíos guardados que, contra su contrato, lanzan al olvidar: cerrar sesión o entrar no pueden
/// fallar por eso.
final class _ReenviosQueExplotan implements BloqueoReenvioVerificacionRepository {
  @override
  Future<ReenviosGuardados> leer({required DateTime ahora}) async => ReenviosGuardados.vacio;

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) async {}

  @override
  Future<void> guardarEspera(String correo, DateTime vence, {required DateTime ahora}) async {}

  @override
  Future<void> olvidar(String correo) async => throw StateError('el almacén no responde');

  @override
  Future<void> olvidarTodo() async => throw StateError('el almacén no responde');
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

    test('con un registro que deja sesión, el aviso también desaparece', () async {
      remote.vencidaPorInactividadAlArrancar = true;
      await container.read(sesionProvider.future);
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
    late ProviderContainer container;

    ProviderContainer crear() => ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(local),
        databaseHelperProvider.overrideWithValue(helper),
        ultimoCorreoRepositoryProvider.overrideWithValue(correo),
        datosLocalesRepositoryProvider.overrideWithValue(datos),
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
  });

  group('SesionNotifier — motivo del último cierre (decisión de Cristian, 07/10, #302)', () {
    late Directory directorio;
    late DatabaseHelper helper;
    late AuthRemoteDataSourceEnMemoria remote;
    late _LocalQueFalla local;
    late UltimoCorreoEnMemoria correo;
    late CierreForzadoEnMemoria cierres;
    late _DatosQueBorran datos;
    late BloqueoReenvioVerificacionEnMemoria reenvios;
    late DateTime ahora;
    late ProviderContainer container;

    /// Un arranque de la app: lo que está en el almacén seguro (el correo y el motivo del cierre)
    /// sobrevive entre arranques; el remoto, la sesión en memoria y los avisos empiezan de cero.
    /// Para que además haya sesión guardada, se pasa el mismo [sesionLocal] del arranque anterior.
    ProviderContainer arrancar({
      _LocalQueFalla? sesionLocal,
      CierreForzadoRepository? repo,
      BloqueoReenvioVerificacionRepository? reenviosGuardados,
      bool verificarAlRegistrar = false,
      RelojSesion? reloj,
    }) {
      remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
        requiereVerificacionAlRegistrar: verificarAlRegistrar,
      );
      local = sesionLocal ?? _LocalQueFalla();
      return ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remote),
          authLocalDataSourceProvider.overrideWithValue(local),
          databaseHelperProvider.overrideWithValue(helper),
          ultimoCorreoRepositoryProvider.overrideWithValue(correo),
          cierreForzadoRepositoryProvider.overrideWithValue(repo ?? cierres),
          datosLocalesRepositoryProvider.overrideWithValue(datos),
          bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(
            reenviosGuardados ?? reenvios,
          ),
          relojSesionProvider.overrideWithValue(
            reloj ?? RelojSesionEnMemoria(sistema: () => ahora),
          ),
        ],
      );
    }

    /// Cierra la app y la vuelve a abrir dos horas después, sin sesión guardada.
    Future<Object?> reiniciar({CierreForzadoRepository? repo}) async {
      container.dispose();
      ahora = ahora.add(const Duration(hours: 2));
      container = arrancar(repo: repo);
      return container.read(sesionProvider.future);
    }

    setUp(() async {
      directorio = await Directory.systemTemp.createTemp('colportores_cierre_forzado_test');
      helper = DatabaseHelper(
        directorio: () async => directorio,
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      ahora = DateTime.now().toUtc();
      correo = UltimoCorreoEnMemoria();
      cierres = CierreForzadoEnMemoria();
      datos = _DatosQueBorran();
      reenvios = BloqueoReenvioVerificacionEnMemoria();
      container = arrancar();
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

    /// El cierre de la DB pasa por el isolate de drift: `pumpEventQueue` solo no alcanza.
    Future<void> esperarCierreDeSesion() async {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    CierreForzado cierre(MotivoExpiracion motivo, [DateTime? fecha]) =>
        CierreForzado(motivo: motivo, fecha: fecha ?? ahora);

    test('dado el arranque en que se descarta la sesión por 30 días sin uso, cuando termina de '
        'leerla, el motivo y la fecha quedan guardados', () async {
      remote.vencidaPorInactividadAlArrancar = true;

      expect(await container.read(sesionProvider.future), isNull);

      expect(await cierres.leer(), cierre(MotivoExpiracion.inactividad));
    });

    test('dado un arranque sin cierre de por medio, no se guarda ni se avisa nada', () async {
      expect(await container.read(sesionProvider.future), isNull);

      expect(await cierres.leer(), isNull);
      expect(container.read(avisoSesionProvider), isNull);
      expect(container.read(reingresoSesionProvider), isNull);
    });

    test('Escenario: segundo arranque — la sesión ya se descartó y no hay nada que detectar, pero '
        'el aviso de la vista 17 sigue, con el correo de la cuenta', () async {
      await correo.guardar('ana@example.com');
      remote.vencidaPorInactividadAlArrancar = true;
      await container.read(sesionProvider.future);
      final fechaDelCierre = ahora;

      expect(await reiniciar(), isNull);

      expect(container.read(avisoSesionProvider), const FailureSesionExpiradaPorInactividad());
      final reingreso = container.read(reingresoSesionProvider)!;
      expect(reingreso.motivo, MotivoExpiracion.inactividad);
      expect(reingreso.email, 'ana@example.com');
      expect(
        await cierres.leer(),
        cierre(MotivoExpiracion.inactividad, fechaDelCierre),
        reason: 'la fecha es la del cierre, no la del arranque que lo volvió a ver',
      );
    });

    test('el aviso vale en cada arranque sin sesión, no solo en el segundo', () async {
      remote.vencidaPorInactividadAlArrancar = true;
      await container.read(sesionProvider.future);

      for (var arranque = 2; arranque <= 4; arranque++) {
        await reiniciar();

        expect(
          container.read(avisoSesionProvider),
          const FailureSesionExpiradaPorInactividad(),
          reason: 'arranque $arranque',
        );
      }
    });

    test('la sesión revocada por el servidor también: vuelve al login con su aviso y en el '
        'arranque siguiente sigue', () async {
      await correo.guardar('ana@example.com');
      await entrar();

      remote.simularExpiracion(MotivoExpiracion.revocada);
      await esperarCierreDeSesion();
      expect(await cierres.leer(), cierre(MotivoExpiracion.revocada));

      await reiniciar();

      expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
      final reingreso = container.read(reingresoSesionProvider)!;
      expect(reingreso.motivo, MotivoExpiracion.revocada);
      expect(reingreso.email, 'ana@example.com');
    });

    test('con la app abierta y 30 días sin uso, el cierre queda guardado y el arranque siguiente '
        'lo avisa', () async {
      await entrar();

      remote.simularExpiracion(MotivoExpiracion.inactividad);
      await esperarCierreDeSesion();

      expect(await cierres.leer(), cierre(MotivoExpiracion.inactividad));
      await reiniciar();
      expect(container.read(avisoSesionProvider), const FailureSesionExpiradaPorInactividad());
    });

    test('un fin de sesión con el login ya a la vista (nadie adentro) también se guarda', () async {
      await container.read(sesionProvider.future);

      remote.simularExpiracion(MotivoExpiracion.revocada);
      await esperarCierreDeSesion();

      expect(await cierres.leer(), cierre(MotivoExpiracion.revocada));
    });

    test(
      'el segundo arranque sin correo guardado: el aviso sale igual, sin correo que precargar',
      () async {
        remote.vencidaPorInactividadAlArrancar = true;
        await container.read(sesionProvider.future);

        await reiniciar();

        expect(container.read(avisoSesionProvider), isNotNull);
        expect(container.read(reingresoSesionProvider)!.email, isNull);
      },
    );

    group('el motivo se borra cuando la persona entra', () {
      setUp(() async {
        remote.vencidaPorInactividadAlArrancar = true;
        await container.read(sesionProvider.future);
        await reiniciar();
        expect(container.read(avisoSesionProvider), isNotNull);
      });

      test('al iniciar sesión: el arranque siguiente es un login común', () async {
        final falla = await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
        await pumpEventQueue();

        expect(falla, isNull);
        expect(container.read(avisoSesionProvider), isNull);
        expect(await cierres.leer(), isNull);
        await reiniciar();
        expect(container.read(avisoSesionProvider), isNull);
        expect(container.read(reingresoSesionProvider), isNull);
      });

      test('al registrarse con una sesión que queda adentro', () async {
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

        expect(await cierres.leer(), isNull);
        expect(container.read(avisoSesionProvider), isNull);
        expect(await correo.leer(), 'nueva@example.com');
      });

      test('y también al registrarse sin sesión (falta verificar el email): decisión del 07/10, '
          'el arranque siguiente es un login común con el correo de la cuenta nueva', () async {
        container.dispose();
        container = arrancar(verificarAlRegistrar: true);
        await container.read(sesionProvider.future);
        expect(container.read(avisoSesionProvider), isNotNull);

        final resultado = await container
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

        expect(resultado.getOrElse(() => throw StateError('falló el registro')).sesion, isNull);
        expect(container.read(avisoSesionProvider), isNull);
        expect(container.read(reingresoSesionProvider), isNull);
        expect(await cierres.leer(), isNull);
        expect(await correo.leer(), 'nueva@example.com');
        await reiniciar();
        expect(container.read(avisoSesionProvider), isNull);
        expect(container.read(reingresoSesionProvider), isNull);
      });

      test('un registro que falla no lo borra: el aviso sigue en el arranque siguiente', () async {
        final resultado = await container
            .read(sesionProvider.notifier)
            .registrar(
              nombre: 'Ana',
              apellido: 'Pérez',
              cedula: '12345672',
              email: 'esto-no-es-un-correo',
              password: 'Secreto123',
              aceptaTerminos: true,
              aceptaTradeOffE2E: true,
            );
        await pumpEventQueue();

        expect(resultado.isLeft(), isTrue);
        expect(await cierres.leer(), isNotNull);
        expect(container.read(avisoSesionProvider), isNotNull);
      });

      test(
        'una contraseña incorrecta no lo borra: el aviso sigue en el arranque siguiente',
        () async {
          final falla = await container
              .read(sesionProvider.notifier)
              .iniciarSesion(email: 'ana@example.com', password: 'equivocada1');
          await pumpEventQueue();

          expect(falla, isA<FailureCredencialesInvalidas>());
          expect(await cierres.leer(), isNotNull);
          await reiniciar();
          expect(container.read(avisoSesionProvider), isNotNull);
        },
      );
    });

    test('una sesión restaurada al arrancar descarta un motivo viejo que haya quedado', () async {
      await entrar();
      await cierres.guardar(cierre(MotivoExpiracion.revocada));
      container.dispose();
      container = arrancar(sesionLocal: local);

      final sesion = await container.read(sesionProvider.future);
      await pumpEventQueue();

      expect(sesion, isNotNull);
      expect(await cierres.leer(), isNull);
      expect(container.read(avisoSesionProvider), isNull);
    });

    // Ojo: acá `build()` ya esperó el guardado cuando se entra, así que esto prueba solo el orden de
    // la cola del repositorio en el arranque. La carrera real —el fin de sesión llega por el stream
    // con la app abierta y la persona entra antes de que termine— la cubren
    // `qa_sesion_vencida_302_test.dart` (el almacén lento y la lectura lenta del reloj, M1 y M1b).
    test(
      'detectar el cierre en el arranque con el almacén lento y entrar: queda sin cierre',
      () async {
        final lento = _AlmacenLento();
        container.dispose();
        container = arrancar(repo: CierreForzadoRepositoryImpl(lento, logger: loggerMudo()));
        remote.vencidaPorInactividadAlArrancar = true;
        await container.read(sesionProvider.future);

        await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
        await pumpEventQueue();

        expect(lento.contenido, isNull);
        expect(lento.operaciones, ['escribir', 'borrar']);
      },
    );

    // HU-AUTH-002, #325: lo que el teléfono recuerda del reenvío del email de verificación (candado de
    // una hora y espera de 60 s) no sobrevive a la cuenta: entrar lo olvida, cerrar sesión a propósito
    // y «Borrar datos locales» también. Nada de esto guarda ni lee la dirección más allá de su hora.
    group('el reenvío de verificación guardado (#325)', () {
      Future<void> guardarReenvios() async {
        const hora = Duration(minutes: 60);
        const minuto = Duration(seconds: 60);
        await reenvios.guardar('ana@example.com', ahora.add(hora), ahora: ahora);
        await reenvios.guardarEspera('ana@example.com', ahora.add(minuto), ahora: ahora);
        await reenvios.guardar('luis@example.com', ahora.add(hora), ahora: ahora);
        await reenvios.guardarEspera('marta@example.com', ahora.add(minuto), ahora: ahora);
      }

      test('al iniciar sesión se olvida el de esa cuenta; los de las otras quedan', () async {
        await guardarReenvios();
        await container.read(sesionProvider.future);

        final falla = await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
        await pumpEventQueue();

        expect(falla, isNull);
        final guardados = await reenvios.leer(ahora: ahora);
        expect(guardados.bloqueos.keys, ['luis@example.com']);
        expect(guardados.esperas.keys, ['marta@example.com']);
      });

      test('una contraseña incorrecta no olvida nada', () async {
        await guardarReenvios();
        await container.read(sesionProvider.future);

        final falla = await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: 'ana@example.com', password: 'equivocada1');
        await pumpEventQueue();

        expect(falla, isA<FailureCredencialesInvalidas>());
        final guardados = await reenvios.leer(ahora: ahora);
        expect(guardados.bloqueos.keys, containsAll(['ana@example.com', 'luis@example.com']));
        expect(guardados.esperas.keys, containsAll(['ana@example.com', 'marta@example.com']));
      });

      test('al cerrar sesión a propósito no queda ninguno, de ninguna dirección', () async {
        await entrar();
        await guardarReenvios();

        final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

        expect(resultado.isRight(), isTrue);
        expect((await reenvios.leer(ahora: ahora)).estaVacio, isTrue);
      });

      test('el cierre que hace la app por la recuperación de contraseña los conserva', () async {
        await entrar();
        await guardarReenvios();

        final resultado = await container
            .read(sesionProvider.notifier)
            .cerrarSesion(conservarCorreo: true);

        expect(resultado.isRight(), isTrue);
        expect((await reenvios.leer(ahora: ahora)).bloqueos, hasLength(2));
      });

      test('si cerrar sesión falla (el usuario sigue adentro) se conservan', () async {
        await entrar();
        await guardarReenvios();
        local.explotar = true;

        final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

        expect(resultado.isLeft(), isTrue);
        expect((await reenvios.leer(ahora: ahora)).bloqueos, hasLength(2));
      });

      test('al borrar los datos locales no queda ninguno', () async {
        await entrar();
        await guardarReenvios();

        final resultado = await container
            .read(sesionProvider.notifier)
            .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

        expect(resultado.isRight(), isTrue);
        expect((await reenvios.leer(ahora: ahora)).estaVacio, isTrue);
      });

      test('si el borrado de datos falla, el usuario sigue adentro y se conservan', () async {
        await entrar();
        await guardarReenvios();
        datos.respuesta = const Left(FailureDatosLocalesIlegibles());

        final resultado = await container
            .read(sesionProvider.notifier)
            .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

        expect(resultado.isLeft(), isTrue);
        expect((await reenvios.leer(ahora: ahora)).bloqueos, hasLength(2));
      });

      test(
        'registrarse sin sesión (falta verificar el email) no olvida el envío del alta',
        () async {
          await guardarReenvios();
          container.dispose();
          container = arrancar(verificarAlRegistrar: true);
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

          expect((await reenvios.leer(ahora: ahora)).bloqueos, hasLength(2));
        },
      );

      test(
        'si el almacén de reenvíos explota, entrar y cerrar sesión siguen funcionando',
        () async {
          container.dispose();
          container = arrancar(reenviosGuardados: _ReenviosQueExplotan());
          await container.read(sesionProvider.future);

          final falla = await container
              .read(sesionProvider.notifier)
              .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
          await pumpEventQueue();
          expect(falla, isNull);
          expect(container.read(sesionProvider).value, isNotNull);

          final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

          expect(resultado.isRight(), isTrue);
          expect(container.read(sesionProvider).value, isNull);
        },
      );
    });

    group('se borra con el correo', () {
      test('al cerrar sesión a propósito', () async {
        await entrar();
        await cierres.guardar(cierre(MotivoExpiracion.inactividad));

        await container.read(sesionProvider.notifier).cerrarSesion();

        expect(await cierres.leer(), isNull);
        expect(await correo.leer(), isNull);
      });

      test('si cerrar sesión falla (el usuario sigue adentro) se conserva', () async {
        await entrar();
        await cierres.guardar(cierre(MotivoExpiracion.inactividad));
        local.explotar = true;

        final resultado = await container.read(sesionProvider.notifier).cerrarSesion();

        expect(resultado.isLeft(), isTrue);
        expect(await cierres.leer(), cierre(MotivoExpiracion.inactividad));
      });

      test('el cierre que hace la app por la recuperación de contraseña lo conserva', () async {
        await entrar();
        await cierres.guardar(cierre(MotivoExpiracion.inactividad));

        final resultado = await container
            .read(sesionProvider.notifier)
            .cerrarSesion(conservarCorreo: true);

        expect(resultado.isRight(), isTrue);
        expect(await cierres.leer(), cierre(MotivoExpiracion.inactividad));
        expect(await correo.leer(), 'ana@example.com');
      });

      test('al borrar los datos locales', () async {
        await entrar();
        await cierres.guardar(cierre(MotivoExpiracion.revocada));

        final resultado = await container
            .read(sesionProvider.notifier)
            .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

        expect(resultado.isRight(), isTrue);
        expect(await cierres.leer(), isNull);
        expect(await correo.leer(), isNull);
      });

      test('si el borrado de datos falla, el usuario sigue adentro y se conserva', () async {
        await entrar();
        await cierres.guardar(cierre(MotivoExpiracion.revocada));
        datos.respuesta = const Left(FailureDatosLocalesIlegibles());

        final resultado = await container
            .read(sesionProvider.notifier)
            .borrarDatosLocales(incluirBackupDrive: false, reintento: true);

        expect(resultado.isLeft(), isTrue);
        expect(await cierres.leer(), cierre(MotivoExpiracion.revocada));
      });

      group('cuando el use case de cerrar sesión lanza pero la sesión se cierra igual', () {
        Future<ProviderContainer> conUseCaseQueLanza(CierreForzadoRepository repoCierre) async {
          final repo = _MockAuthRepository();
          when(repo.sesionActual).thenAnswer((_) async => const Right(null));
          when(repo.reintentarRevocacionPendiente).thenAnswer((_) async => const Right(unit));
          when(() => repo.expiraciones).thenAnswer((_) => const Stream.empty());
          when(repo.cerrarSesion).thenThrow(const _FallaDeAlmacen());
          final c = ProviderContainer(
            overrides: [
              authRepositoryProvider.overrideWithValue(repo),
              databaseHelperProvider.overrideWithValue(helper),
              ultimoCorreoRepositoryProvider.overrideWithValue(correo),
              cierreForzadoRepositoryProvider.overrideWithValue(repoCierre),
            ],
          );
          addTearDown(c.dispose);
          await c.read(sesionProvider.future);
          return c;
        }

        test('se borra igual y el error original se propaga', () async {
          await cierres.guardar(cierre(MotivoExpiracion.inactividad));
          final c = await conUseCaseQueLanza(cierres);

          await expectLater(
            c.read(sesionProvider.notifier).cerrarSesion(),
            throwsA(isA<_FallaDeAlmacen>()),
          );

          expect(await cierres.leer(), isNull);
          expect(c.read(sesionProvider).value, isNull);
        });

        test('con conservarCorreo, queda', () async {
          await cierres.guardar(cierre(MotivoExpiracion.inactividad));
          final c = await conUseCaseQueLanza(cierres);

          await expectLater(
            c.read(sesionProvider.notifier).cerrarSesion(conservarCorreo: true),
            throwsA(isA<_FallaDeAlmacen>()),
          );

          expect(await cierres.leer(), cierre(MotivoExpiracion.inactividad));
        });

        test(
          'si borrarlo también falla, no tapa el error original ni deja la DB abierta',
          () async {
            final c = await conUseCaseQueLanza(_CierreQueExplotaAlBorrar());
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
    });

    // #311 (seguimiento de #302/#308): dos fines de sesión casi juntos y un fin de sesión que llega
    // antes de que `build()` termine de leer la sesión. La carrera del guardado contra «Entrar» está
    // en `qa_sesion_vencida_302_test.dart` (M1, M1b).
    group('fines de sesión que se pisan (#311)', () {
      const unMesDespues = Duration(days: 31);

      /// La app abierta con una sesión adentro y el reloj de la sesión retenible.
      Future<_RelojPorTurnos> entrarConRelojRetenible() async {
        final reloj = _RelojPorTurnos(() => ahora);
        container.dispose();
        container = arrancar(reloj: reloj);
        await entrar();
        return reloj;
      }

      /// Un arranque con la sesión guardada en el teléfono, que todavía se está leyendo cuando
      /// llegan [motivos] por el stream (uno detrás de otro); después termina de leerse.
      Future<Object?> arrancarConFinesDeSesionAntesDeLeerLaSesion(
        List<MotivoExpiracion> motivos,
      ) async {
        await correo.guardar('ana@example.com');
        await entrar();
        container.dispose();
        container = arrancar(sesionLocal: local);
        local.puerta = Completer<void>();
        final lectura = container.read(sesionProvider.future);
        await pumpEventQueue();

        motivos.forEach(remote.simularExpiracion);
        await pumpEventQueue();
        local.puerta!.complete();
        final sesion = await lectura;
        await esperarCierreDeSesion();
        return sesion;
      }

      for (final (descripcion, primeroElQueSeVe) in [
        ('el que se ve termina de leer el reloj primero', true),
        ('el que se ve termina de leer el reloj último', false),
      ]) {
        test(
          'dos fines de sesión casi juntos con motivos distintos (el stream revoca y la revisión '
          'al volver ve los 30 días): $descripcion, el motivo guardado es el del aviso que se '
          've',
          () async {
            final reloj = await entrarConRelojRetenible();
            final tarde = ahora.add(unMesDespues);
            reloj.retener = true;

            remote.simularExpiracion(MotivoExpiracion.revocada);
            await pumpEventQueue();
            final revision = container.read(sesionProvider.notifier).revisarVigencia();
            await pumpEventQueue();
            expect(reloj.turnos, hasLength(2), reason: 'el guardado de la revocada y la revisión');
            reloj.turnos[1].complete(tarde);
            await pumpEventQueue();
            expect(reloj.turnos, hasLength(3), reason: 'la revisión vio 30 días y guarda el suyo');
            expect(
              container.read(avisoSesionProvider),
              const FailureSesionExpiradaPorInactividad(),
              reason: 'el último en llegar es el aviso que se ve',
            );

            if (primeroElQueSeVe) {
              reloj.turnos[2].complete(tarde);
              await esperarCierreDeSesion();
              reloj.turnos[0].complete(ahora);
            } else {
              reloj.turnos[0].complete(ahora);
              await esperarCierreDeSesion();
              reloj.turnos[2].complete(tarde);
            }
            await revision;
            await esperarCierreDeSesion();

            expect(
              container.read(avisoSesionProvider),
              const FailureSesionExpiradaPorInactividad(),
            );
            expect((await cierres.leer())!.motivo, MotivoExpiracion.inactividad);
            expect(container.read(sesionProvider).value, isNull);
            await reiniciar();
            expect(
              container.read(avisoSesionProvider),
              const FailureSesionExpiradaPorInactividad(),
              reason: 'el arranque siguiente avisa lo mismo que se vio',
            );
          },
        );
      }

      test(
        'la revisión al volver termina de leer cuando la persona ya cerró sesión a propósito: no '
        'queda ningún aviso ni motivo guardado',
        () async {
          final reloj = await entrarConRelojRetenible();
          reloj.retener = true;
          final revision = container.read(sesionProvider.notifier).revisarVigencia();
          await pumpEventQueue();
          expect(reloj.turnos, hasLength(1));

          reloj.retener = false;
          final cerro = await container.read(sesionProvider.notifier).cerrarSesion();
          reloj.turnos.single.complete(ahora.add(unMesDespues));
          await revision;
          await esperarCierreDeSesion();

          expect(cerro.isRight(), isTrue);
          expect(container.read(sesionProvider).value, isNull);
          expect(container.read(avisoSesionProvider), isNull);
          expect(container.read(reingresoSesionProvider), isNull);
          expect(await cierres.leer(), isNull);
        },
      );

      test('la revisión al volver termina de leer cuando el servidor ya revocó la sesión: el aviso '
          'es el de la revocación, no el de los 30 días', () async {
        final reloj = await entrarConRelojRetenible();
        reloj.retener = true;
        final revision = container.read(sesionProvider.notifier).revisarVigencia();
        await pumpEventQueue();

        reloj.retener = false;
        remote.simularExpiracion(MotivoExpiracion.revocada);
        await esperarCierreDeSesion();
        reloj.turnos.single.complete(ahora.add(unMesDespues));
        await revision;
        await esperarCierreDeSesion();

        expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
        expect((await cierres.leer())!.motivo, MotivoExpiracion.revocada);
        expect(container.read(sesionProvider).value, isNull);
      });

      test(
        'el fin de sesión llega por el stream antes de que termine de leerse la sesión guardada: '
        'al terminar de leerla se cierra, con su aviso y el motivo guardado',
        () async {
          final sesion = await arrancarConFinesDeSesionAntesDeLeerLaSesion([
            MotivoExpiracion.revocada,
          ]);

          expect(
            sesion,
            isNotNull,
            reason: 'la lectura devolvió la sesión; el cierre es posterior',
          );
          expect(
            container.read(sesionProvider).value,
            isNull,
            reason: 'no queda abierta con aviso',
          );
          expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
          final reingreso = container.read(reingresoSesionProvider)!;
          expect(reingreso.motivo, MotivoExpiracion.revocada);
          expect(reingreso.email, 'ana@example.com');
          expect(await cierres.leer(), cierre(MotivoExpiracion.revocada));
          await reiniciar();
          expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
        },
      );

      test('dos fines de sesión antes de que termine de leerse la sesión: el aviso y el motivo '
          'guardado son los del último', () async {
        await arrancarConFinesDeSesionAntesDeLeerLaSesion([
          MotivoExpiracion.revocada,
          MotivoExpiracion.inactividad,
        ]);

        expect(container.read(sesionProvider).value, isNull);
        expect(container.read(avisoSesionProvider), const FailureSesionExpiradaPorInactividad());
        expect(await cierres.leer(), cierre(MotivoExpiracion.inactividad));
      });

      test(
        'después del cierre por un fin de sesión temprano la persona vuelve a entrar: sin aviso, '
        'sin motivo guardado y con la sesión abierta',
        () async {
          await arrancarConFinesDeSesionAntesDeLeerLaSesion([MotivoExpiracion.revocada]);
          expect(container.read(avisoSesionProvider), isNotNull);

          final falla = await container
              .read(sesionProvider.notifier)
              .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
          await pumpEventQueue();

          expect(falla, isNull);
          expect(container.read(sesionProvider).value, isNotNull);
          expect(container.read(avisoSesionProvider), isNull);
          expect(await cierres.leer(), isNull);
        },
      );

      test('el fin de sesión antes de leer la sesión cuando no había ninguna guardada: el login '
          'sale con el aviso y el motivo queda guardado', () async {
        container.dispose();
        container = arrancar();
        local.puerta = Completer<void>();
        final lectura = container.read(sesionProvider.future);
        await pumpEventQueue();

        remote.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        local.puerta!.complete();
        expect(await lectura, isNull);
        await esperarCierreDeSesion();

        expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
        expect(await cierres.leer(), cierre(MotivoExpiracion.revocada));
      });

      test('el fin de sesión antes de leer la sesión cuando había un motivo guardado de antes: '
          'gana el que llegó y es el que queda en disco', () async {
        await cierres.guardar(cierre(MotivoExpiracion.inactividad));
        container.dispose();
        container = arrancar();
        local.puerta = Completer<void>();
        final lectura = container.read(sesionProvider.future);
        await pumpEventQueue();

        remote.simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        local.puerta!.complete();
        await lectura;
        await esperarCierreDeSesion();

        expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
        expect((await cierres.leer())!.motivo, MotivoExpiracion.revocada);
      });

      test('el mismo fin de sesión dos veces seguidas con la app abierta: se cierra una vez, con '
          'su aviso y su motivo guardado', () async {
        await entrar();

        remote
          ..simularExpiracion(MotivoExpiracion.revocada)
          ..simularExpiracion(MotivoExpiracion.revocada);
        await esperarCierreDeSesion();

        expect(container.read(sesionProvider).value, isNull);
        expect(container.read(avisoSesionProvider), const FailureSesionRevocada());
        expect(await cierres.leer(), cierre(MotivoExpiracion.revocada));
      });
    });

    group('con el almacén seguro roto o con basura', () {
      test('si no se puede guardar, el aviso de este arranque sale igual y el siguiente es un '
          'login común (no se inventa)', () async {
        final roto = AlmacenSeguroEnMemoria()..simularFalla = true;
        final repo = CierreForzadoRepositoryImpl(roto, logger: loggerMudo());
        container.dispose();
        container = arrancar(repo: repo);
        remote.vencidaPorInactividadAlArrancar = true;

        expect(await container.read(sesionProvider.future), isNull);
        expect(container.read(avisoSesionProvider), isNotNull);

        await reiniciar(repo: repo);
        expect(container.read(avisoSesionProvider), isNull);
      });

      test('un valor guardado ilegible es un login común, sin aviso ni saludo', () async {
        final almacen = AlmacenSeguroEnMemoria({ClaveSegura.cierreForzado: 'cualquier cosa'});

        await reiniciar(repo: CierreForzadoRepositoryImpl(almacen, logger: loggerMudo()));

        expect(container.read(avisoSesionProvider), isNull);
        expect(container.read(reingresoSesionProvider), isNull);
      });

      test(
        'con el almacén seguro real: el arranque siguiente lee lo que guardó el anterior',
        () async {
          final almacen = AlmacenSeguroEnMemoria();
          container.dispose();
          container = arrancar(repo: CierreForzadoRepositoryImpl(almacen, logger: loggerMudo()));
          remote.vencidaPorInactividadAlArrancar = true;
          await container.read(sesionProvider.future);
          expect(almacen.contenido.keys, [ClaveSegura.cierreForzado]);

          await reiniciar(repo: CierreForzadoRepositoryImpl(almacen, logger: loggerMudo()));

          expect(container.read(avisoSesionProvider), const FailureSesionExpiradaPorInactividad());
        },
      );
    });
  });
}
