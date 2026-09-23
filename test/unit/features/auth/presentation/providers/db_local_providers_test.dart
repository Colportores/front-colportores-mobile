// HU-AUTH-009 de punta a punta con el cableado real (ADR-006): login contra el remoto en memoria,
// SQLCipher y el envoltorio en un directorio temporal, la DEK en el almacén en memoria, el cifrado
// de la DEK real y el Argon2id de juguete, que el test pausa para cerrar sesión "mientras envuelve
// la DEK" (revisión del PR #44).
import 'dart:io';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/dispositivo/dispositivo_providers.dart';
import 'package:colportores_mobile/core/dispositivo/fakes/seguridad_dispositivo_fija.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/secure_storage/secure_storage_providers.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/inicializar_db_local_use_case.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/recuperar_db_local_con_password_use_case.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/proveedor_clave_db_falso.dart';

const _email = 'ana@example.com';
const _password = 'secreto123';

const _creada = Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.creada);
const _abierta = Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.abierta);

void main() {
  late Directory directorio;
  late DatabaseHelper helper;
  late AlmacenSeguroEnMemoria almacen;
  late ProveedorClaveDbFalso proveedor;
  late SeguridadDispositivoFija seguridad;
  late ProviderContainer container;

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_db_local_providers_test');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    almacen = AlmacenSeguroEnMemoria();
    proveedor = ProveedorClaveDbFalso();
    seguridad = SeguridadDispositivoFija();
    container = ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        databaseHelperProvider.overrideWithValue(helper),
        almacenSeguroProvider.overrideWithValue(almacen),
        archivoEnvoltorioDekProvider.overrideWithValue(
          ArchivoEnvoltorioDek(directorio: () async => directorio),
        ),
        proveedorClaveDbProvider.overrideWithValue(proveedor),
        seguridadDispositivoProvider.overrideWithValue(seguridad),
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
        .iniciarSesion(email: _email, password: _password);
    expect(falla, isNull);
  }

  Future<void> cerrarSesion() => container.read(sesionProvider.notifier).cerrarSesion();

  Future<Either<Failure, ResultadoInicializacionDb>> inicializar({String? password = _password}) =>
      container.read(inicializarDbLocalUseCaseProvider)(
        InicializarDbLocalParams(password: password),
      );

  test('dado un primer login, crea la DB cifrada con una DEK aleatoria, la envuelve con la '
      'contraseña, la publica y marca el dispositivo', () async {
    await iniciarSesion();

    final r = await inicializar();

    expect(r, _creada);
    expect(container.read(dbLocalProvider), isNotNull);
    expect(await helper.existe(), isTrue);
    final custodia = container.read(custodiaClaveDbProvider);
    expect(await custodia.dbInicializada(), isTrue);
    expect(await custodia.leerDek(), isNotNull);
    expect(await custodia.hayEnvoltorioPorPassword(), isTrue);
    expect(
      proveedor.entregadas.single.destruida,
      isTrue,
      reason: 'la clave del envoltorio no vive',
    );
  });

  test('dado un login posterior, abre la misma DB con la DEK del almacén, sin Argon2id y sin '
      'contraseña (sesión restaurada o Google)', () async {
    await iniciarSesion();
    await inicializar();
    final dek = (await container.read(custodiaClaveDbProvider).leerDek())!.bytes;
    await cerrarSesion();
    expect(helper.abierta, isFalse);
    expect(await helper.existe(), isTrue, reason: 'cerrar sesión conserva la DB (HU-AUTH-006)');

    await iniciarSesion();
    final r = await inicializar(password: null);

    expect(r, _abierta);
    expect(helper.abierta, isTrue);
    expect(proveedor.entregadas, hasLength(1), reason: 'Argon2id no corre en cada apertura');
    expect((await container.read(custodiaClaveDbProvider).leerDek())!.bytes, dek);
  });

  test('dado que el Keystore se rompió con la DB en disco, la contraseña recupera la DEK, '
      'reconstruye el almacén y abre la misma DB (ADR-006)', () async {
    await iniciarSesion();
    await inicializar();
    final db = container.read(dbLocalProvider)!;
    await db.customStatement('CREATE TABLE IF NOT EXISTS prueba (x INTEGER)');
    await db.customStatement('INSERT INTO prueba VALUES (7)');
    await cerrarSesion();
    await almacen.borrarTodo();
    await iniciarSesion();

    final sinDek = await inicializar(password: null);
    expect(
      sinDek,
      const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroRecuperable()),
    );

    final r = await container.read(recuperarDbLocalConPasswordUseCaseProvider)(
      const RecuperarDbLocalParams(password: _password),
    );

    expect(r, const Right<Failure, Unit>(unit));
    final fila = await container
        .read(dbLocalProvider)!
        .customSelect('SELECT x FROM prueba')
        .getSingle();
    expect(fila.read<int>('x'), 7, reason: 'no se perdió nada');
  });

  test('dado que el usuario eligió empezar de nuevo, borra todo y la inicialización crea una DB '
      'nueva', () async {
    await iniciarSesion();
    await inicializar(password: null);
    await cerrarSesion();
    await almacen.borrarTodo();
    await iniciarSesion();
    expect(
      await inicializar(password: null),
      const Left<Failure, ResultadoInicializacionDb>(FailureAlmacenSeguroSinRecuperacion()),
    );

    final r = await container.read(empezarDeNuevoDbLocalUseCaseProvider)(const NoParams());

    expect(r, const Right<Failure, Unit>(unit));
    expect(await helper.existe(), isFalse);
    expect(await inicializar(password: null), _creada);
  });

  test('dado un equipo sin bloqueo de pantalla, no crea nada', () async {
    seguridad.bloqueoPantalla = false;
    await iniciarSesion();

    expect(
      await inicializar(),
      const Left<Failure, ResultadoInicializacionDb>(FailureSinBloqueoPantalla()),
    );
    expect(await helper.existe(), isFalse);
    expect(almacen.contenido, isEmpty);
  });

  group('cierre de sesión mientras se envuelve la DEK (revisión del PR #44)', () {
    Future<Either<Failure, ResultadoInicializacionDb>> cerrarSesionMientrasEnvuelve() async {
      proveedor.pausar();
      final enCurso = inicializar();
      await proveedor.seEstaDerivando;

      // El logout completo, con la DB todavía sin pedir: DbLocalNotifier.cerrar() no tiene nada
      // que cerrar y sale enseguida.
      await cerrarSesion();
      proveedor.continuar();
      return enCurso;
    }

    test(
      'dado un primer login, no abre la DB, no deja la DEK viva ni suelta en el almacén',
      () async {
        await iniciarSesion();

        final r = await cerrarSesionMientrasEnvuelve();

        expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
        expect(helper.abierta, isFalse, reason: 'la DB no puede quedar abierta sin sesión');
        expect(container.read(dbLocalProvider), isNull);
        expect(proveedor.entregadas.single.destruida, isTrue);
        expect(await helper.existe(), isFalse);
        expect(almacen.contenido, isEmpty);
        expect(await container.read(custodiaClaveDbProvider).hayEnvoltorioPorPassword(), isFalse);
      },
    );

    test('dado un logout en vuelo cuando termina Argon2id, la DB termina cerrada igual', () async {
      await iniciarSesion();
      proveedor.pausar();
      final enCurso = inicializar();
      await proveedor.seEstaDerivando;

      // El logout arranca y Argon2id termina mientras el use case de auth todavía corre. Según
      // quién llegue primero, o el chequeo ve el cierre y no abre, o abre y el logout la cierra:
      // en los dos casos no queda nada abierto.
      final logout = cerrarSesion();
      proveedor.continuar();
      await enCurso;
      await logout;

      expect(helper.abierta, isFalse, reason: 'el logout cierra lo que se abrió');
      expect(container.read(dbLocalProvider), isNull);
    });
  });

  group('vigenciaSesionProvider', () {
    test('dado que no hay sesión, no entrega testigo', () async {
      await container.read(sesionProvider.future);

      expect(container.read(vigenciaSesionProvider).tomarTestigo(), isNull);
    });

    test(
      'dado un cierre de la DB pedido con la sesión todavía puesta, el testigo ya no vale',
      () async {
        // Es la ventana de SesionNotifier.cerrarSesion: pidió cerrar la DB y todavía no pasó la
        // sesión a null. Mirando solo la sesión, el chequeo diría "vigente".
        await iniciarSesion();
        final testigo = container.read(vigenciaSesionProvider).tomarTestigo()!;
        expect(testigo.sigueVigente, isTrue);

        await container.read(dbLocalProvider.notifier).cerrar();

        expect(container.read(sesionProvider).value, isNotNull);
        expect(testigo.sigueVigente, isFalse);
      },
    );

    test('dado un logout y un login nuevo, el testigo viejo ya no vale', () async {
      await iniciarSesion();
      final testigo = container.read(vigenciaSesionProvider).tomarTestigo()!;

      await cerrarSesion();
      await iniciarSesion();

      expect(testigo.sigueVigente, isFalse);
    });
  });

  test('dado que nadie inyectó la seguridad del equipo, falla en vez de inventar una', () {
    final sinSeguridad = ProviderContainer(
      overrides: [
        databaseHelperProvider.overrideWithValue(helper),
        almacenSeguroProvider.overrideWithValue(almacen),
        archivoEnvoltorioDekProvider.overrideWithValue(
          ArchivoEnvoltorioDek(directorio: () async => directorio),
        ),
      ],
    );
    addTearDown(sinSeguridad.dispose);

    expect(
      () => sinSeguridad.read(inicializarDbLocalUseCaseProvider),
      throwsA(isA<ProviderException>()),
    );
  });
}
