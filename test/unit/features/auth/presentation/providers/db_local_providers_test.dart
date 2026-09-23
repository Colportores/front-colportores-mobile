// HU-AUTH-009 de punta a punta con el cableado real: login contra el remoto en memoria, SQLCipher
// en un directorio temporal, sal en el almacén en memoria y la derivación de juguete, que el test
// pausa para cerrar sesión "mientras deriva" (revisión del PR #44).
import 'dart:io';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/secure_storage/secure_storage_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/inicializar_db_local_use_case.dart';
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

void main() {
  late Directory directorio;
  late DatabaseHelper helper;
  late AlmacenSeguroEnMemoria almacen;
  late ProveedorClaveDbFalso proveedor;
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
    container = ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        databaseHelperProvider.overrideWithValue(helper),
        almacenSeguroProvider.overrideWithValue(almacen),
        proveedorClaveDbProvider.overrideWithValue(proveedor),
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

  Future<Either<Failure, ResultadoInicializacionDb>> inicializar() => container.read(
    inicializarDbLocalUseCaseProvider,
  )(const InicializarDbLocalParams(password: _password));

  test('dado un primer login, crea la DB cifrada, la publica y marca el dispositivo', () async {
    await iniciarSesion();

    final r = await inicializar();

    expect(r, const Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.creada));
    expect(container.read(dbLocalProvider), isNotNull);
    expect(await helper.existe(), isTrue);
    expect(await container.read(custodiaClaveDbProvider).dbInicializada(), isTrue);
  });

  test('dado un login posterior, vuelve a abrir la misma DB con la sal guardada', () async {
    await iniciarSesion();
    await inicializar();
    final sal = await container.read(custodiaClaveDbProvider).leerSal();
    await cerrarSesion();
    expect(helper.abierta, isFalse);

    await iniciarSesion();
    final r = await inicializar();

    expect(r, const Right<Failure, ResultadoInicializacionDb>(ResultadoInicializacionDb.abierta));
    expect(helper.abierta, isTrue);
    expect(await container.read(custodiaClaveDbProvider).leerSal(), sal);
  });

  group('cierre de sesión durante la derivación (revisión del PR #44)', () {
    Future<Either<Failure, ResultadoInicializacionDb>> cerrarSesionMientrasDeriva() async {
      proveedor.pausar();
      final enCurso = inicializar();
      await proveedor.seEstaDerivando;

      // El logout completo, con la DB todavía sin pedir: DbLocalNotifier.cerrar() no tiene nada
      // que cerrar y sale enseguida.
      await cerrarSesion();
      proveedor.continuar();
      return enCurso;
    }

    test('dado un primer login, no abre la DB, destruye la clave y no deja sal suelta', () async {
      await iniciarSesion();

      final r = await cerrarSesionMientrasDeriva();

      expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
      expect(helper.abierta, isFalse, reason: 'la DB no puede quedar abierta sin sesión');
      expect(container.read(dbLocalProvider), isNull);
      expect(proveedor.entregadas.single.destruida, isTrue);
      expect(await helper.existe(), isFalse);
      expect(almacen.contenido, isEmpty);
    });

    test(
      'dado un login posterior, no abre la DB, destruye la clave y conserva los datos',
      () async {
        await iniciarSesion();
        await inicializar();
        await cerrarSesion();
        await iniciarSesion();

        final r = await cerrarSesionMientrasDeriva();

        expect(r, const Left<Failure, ResultadoInicializacionDb>(FailureSesionCerrada()));
        expect(helper.abierta, isFalse);
        expect(container.read(dbLocalProvider), isNull);
        expect(proveedor.entregadas.last.destruida, isTrue);
        expect(await helper.existe(), isTrue);
        expect(await container.read(custodiaClaveDbProvider).dbInicializada(), isTrue);
      },
    );

    test(
      'dado un logout en vuelo cuando termina la derivación, la DB termina cerrada igual',
      () async {
        await iniciarSesion();
        proveedor.pausar();
        final enCurso = inicializar();
        await proveedor.seEstaDerivando;

        // El logout arranca y la derivación termina mientras el use case de auth todavía corre. Según
        // quién llegue primero, o el chequeo ve el cierre y no abre, o abre y el logout la cierra:
        // en los dos casos no queda nada abierto ni la clave viva.
        final logout = cerrarSesion();
        proveedor.continuar();
        await enCurso;
        await logout;

        expect(helper.abierta, isFalse, reason: 'el logout cierra lo que se abrió');
        expect(container.read(dbLocalProvider), isNull);
        expect(proveedor.entregadas.single.destruida, isTrue);
      },
    );
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

  test('dado que nadie inyectó la derivación (Argon2id pendiente), falla en vez de inventar '
      'una', () {
    final sinDerivacion = ProviderContainer(
      overrides: [
        databaseHelperProvider.overrideWithValue(helper),
        almacenSeguroProvider.overrideWithValue(almacen),
      ],
    );
    addTearDown(sinDerivacion.dispose);

    expect(
      () => sinDerivacion.read(proveedorClaveDbProvider),
      throwsA(
        isA<ProviderException>().having((e) => e.exception, 'exception', isA<UnimplementedError>()),
      ),
    );
    expect(
      () => sinDerivacion.read(inicializarDbLocalUseCaseProvider),
      throwsA(isA<ProviderException>()),
    );
  });
}
