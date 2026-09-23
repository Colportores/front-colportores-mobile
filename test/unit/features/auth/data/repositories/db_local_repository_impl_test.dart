// Primitivas de la DB local de HU-AUTH-009 sobre la infraestructura real (ADR-006): SQLCipher en un
// directorio temporal, la custodia de la DEK sobre el almacén en memoria, el envoltorio en disco,
// Argon2id de juguete y el cifrado de la DEK real.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/dispositivo/fakes/seguridad_dispositivo_fija.dart';
import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/db_local_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/proveedor_clave_db_falso.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final class _FallaQueCitaLaContrasenia implements Exception {
  @override
  String toString() => 'falló derivando secreto123';
}

const _parametros = ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1);

T _derecha<T>(Either<Failure, T> r) => r.fold((f) => fail('esperaba Right y vino $f'), (v) => v);

Failure _izquierda<T>(Either<Failure, T> r) => r.fold((f) => f, (_) => fail('esperaba Left'));

void main() {
  late Directory directorio;
  late DatabaseHelper helper;
  late AlmacenSeguroEnMemoria almacen;
  late ProveedorClaveDbFalso proveedor;
  late SeguridadDispositivoFija seguridad;
  late ProviderContainer container;
  late DbLocalRepositoryImpl repo;

  CustodiaClaveDb custodia() => CustodiaClaveDb(
    almacen,
    ArchivoEnvoltorioDek(directorio: () async => directorio),
    proveedor,
    CriptoSodium(),
    parametros: _parametros,
    logger: loggerMudo(),
  );

  DbLocalRepositoryImpl construir({AppLogger? logger}) => DbLocalRepositoryImpl(
    custodia: custodia(),
    seguridad: seguridad,
    helper: helper,
    dbLocal: container.read(dbLocalProvider.notifier),
    logger: logger ?? loggerMudo(),
  );

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_db_local_repo_test');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    almacen = AlmacenSeguroEnMemoria();
    proveedor = ProveedorClaveDbFalso();
    seguridad = SeguridadDispositivoFija();
    container = ProviderContainer(overrides: [databaseHelperProvider.overrideWithValue(helper)]);
    repo = construir();
  });

  tearDown(() async {
    container.dispose();
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  /// Copia de la DEK: la original la toma la DB al abrir.
  ClaveDb copia(ClaveDb dek) => ClaveDb(Uint8List.fromList(dek.bytes));

  test('dado un dispositivo nuevo, el estado es sin marca, sin archivo y sin envoltorio', () async {
    expect(
      _derecha(await repo.estado()),
      const EstadoDbLocal(
        marca: MarcaDbLocal.ausente,
        archivoExiste: false,
        envoltorioExiste: false,
      ),
    );
  });

  test(
    'dado un primer login completo, el estado lo refleja y la DEK del almacén reabre la DB',
    () async {
      final dek = _derecha(await repo.crearDek());
      _derecha(await repo.envolverConPassword(dek, 'secreto123'));
      final paraReabrir = copia(dek);
      _derecha(await repo.abrir(dek));
      _derecha(await repo.marcarInicializada());

      expect(
        _derecha(await repo.estado()),
        const EstadoDbLocal(
          marca: MarcaDbLocal.puesta,
          archivoExiste: true,
          envoltorioExiste: true,
        ),
      );
      expect(container.read(dbLocalProvider), isNotNull, reason: 'la DB queda publicada');

      await container.read(dbLocalProvider.notifier).cerrar();
      final leida = _derecha(await repo.leerDek());
      expect(leida!.bytes, paraReabrir.bytes);
      expect(_derecha(await repo.abrir(leida)), unit, reason: 'abre sin la contraseña');
    },
  );

  test('dada la DEK envuelta, la contraseña la desenvuelve; otra contraseña no', () async {
    final dek = _derecha(await repo.crearDek());
    _derecha(await repo.envolverConPassword(dek, 'secreto123'));

    expect(_derecha(await repo.desenvolverConPassword('secreto123')).bytes, dek.bytes);
    expect(
      _izquierda(await repo.desenvolverConPassword('otra')),
      const FailurePasswordNoAbreDatos(),
    );
  });

  test('dado un equipo sin envoltorio, desenvolver devuelve la falla sin recuperación', () async {
    expect(
      _izquierda(await repo.desenvolverConPassword('secreto123')),
      const FailureAlmacenSeguroSinRecuperacion(),
    );
  });

  test('cuando reconstruye el almacén, la DB vuelve a abrir con la DEK recuperada', () async {
    final dek = _derecha(await repo.crearDek());
    final recuperada = copia(dek);
    _derecha(await repo.abrir(dek));
    _derecha(await repo.marcarInicializada());
    await container.read(dbLocalProvider.notifier).cerrar();
    await almacen.borrarTodo();

    _derecha(await repo.reconstruirAlmacen(recuperada));

    expect(_derecha(await repo.estado()).marca, MarcaDbLocal.puesta);
    expect(_derecha(await repo.abrir(_derecha(await repo.leerDek())!)), unit);
  });

  test('la seguridad del equipo se lee de SeguridadDispositivo', () async {
    seguridad
      ..bloqueoPantalla = false
      ..nivel = NivelAlmacenSeguro.software;

    expect(_derecha(await repo.tieneBloqueoPantalla()), isFalse);
    expect(_derecha(await repo.nivelAlmacenSeguro()), NivelAlmacenSeguro.software);
  });

  test('cuando registra el consentimiento de S10, queda en el almacén', () async {
    _derecha(await repo.registrarConsentimientoAlmacenSoftware());

    expect(almacen.contenido[ClaveSegura.consentimientoAlmacenSoftware], 'true');
  });

  test('cuando descarta, cierra la DB y no deja archivo, DEK, envoltorio ni marca', () async {
    final dek = _derecha(await repo.crearDek());
    _derecha(await repo.envolverConPassword(dek, 'secreto123'));
    _derecha(await repo.abrir(dek));
    _derecha(await repo.marcarInicializada());

    _derecha(await repo.descartar());

    expect(helper.abierta, isFalse);
    expect(container.read(dbLocalProvider), isNull);
    expect(
      _derecha(await repo.estado()),
      const EstadoDbLocal(
        marca: MarcaDbLocal.ausente,
        archivoExiste: false,
        envoltorioExiste: false,
      ),
    );
    expect(almacen.contenido, isEmpty);
  });

  test('dado nada que descartar, descartar no cuenta un cierre de sesión que no hubo', () async {
    _derecha(await repo.descartar());

    expect(container.read(cierresDbLocalProvider).pedidos, 0);
  });

  group('dado que algo falla', () {
    test(
      'dado un almacén que no responde, el estado no es un Left: la marca es ilegible',
      () async {
        almacen.simularFalla = true;

        expect(_derecha(await repo.estado()).marca, MarcaDbLocal.ilegible);
      },
    );

    test('dado una marca corrupta, la marca es ilegible', () async {
      almacen = AlmacenSeguroEnMemoria({ClaveSegura.dbInicializada: 'quizas'});
      repo = construir();

      expect(_derecha(await repo.estado()).marca, MarcaDbLocal.ilegible);
    });

    test('dado que el almacén no guarda la DEK, crearla falla y la DEK no sobrevive', () async {
      almacen.simularFalla = true;

      expect(_izquierda(await repo.crearDek()), const FailureAlmacenSeguro());
    });

    test('dado una DEK corrupta en el almacén, leerla devuelve la falla del almacén', () async {
      almacen = AlmacenSeguroEnMemoria({ClaveSegura.dekDb: 'no es base64!!'});
      repo = construir();

      expect(_izquierda(await repo.leerDek()), const FailureAlmacenSeguro());
    });

    test('dado que la plataforma no responde por la seguridad del equipo, devuelve la falla del '
        'almacén', () async {
      seguridad.simularFalla = true;

      expect(_izquierda(await repo.tieneBloqueoPantalla()), const FailureAlmacenSeguro());
      expect(_izquierda(await repo.nivelAlmacenSeguro()), const FailureAlmacenSeguro());
    });

    test(
      'dada una DEK que no abre el archivo, devuelve clave incorrecta y no borra nada',
      () async {
        final dek = _derecha(await repo.crearDek());
        _derecha(await repo.abrir(dek));
        await container.read(dbLocalProvider.notifier).cerrar();

        final otra = ClaveDb(Uint8List.fromList(List<int>.filled(32, 1)));
        expect(_izquierda(await repo.abrir(otra)), const FailureClaveDbIncorrecta());
        expect(await helper.existe(), isTrue);
      },
    );

    test(
      'dado que la derivación falla con algo desconocido, devuelve inesperado y no loguea el mensaje',
      () async {
        final salida = _SalidaEnMemoria();
        repo = construir(logger: AppLogger(output: salida));
        proveedor.falla = _FallaQueCitaLaContrasenia();
        final dek = ClaveDb(Uint8List(32));

        final r = await repo.envolverConPassword(dek, 'secreto123');

        expect(_izquierda(r), isA<FailureInesperado>());
        expect(salida.lineas.join('\n'), contains('INIT_DB_FAIL'));
        expect(salida.lineas.join('\n'), isNot(contains('secreto123')));
      },
    );
  });

  group('traducir', () {
    test('dado una falla del almacén, de la DEK, de la marca, del equipo o de libsodium, devuelve '
        'la falla de almacenamiento seguro (texto de la HU)', () {
      for (final e in <Exception>[
        const AlmacenSeguroException(operacion: 'leer'),
        const DekCorruptaException('x'),
        const MarcaInicializacionCorruptaException('x'),
        const SeguridadDispositivoException(operacion: 'nivelAlmacen'),
        const CriptoException('derivar', 'x'),
      ]) {
        expect(DbLocalRepositoryImpl.traducir(e), const FailureAlmacenSeguro(), reason: '$e');
      }
      expect(
        const FailureAlmacenSeguro().mensaje,
        'No pudimos preparar el almacenamiento seguro. Probá reinstalar el app o consultá a '
        'soporte.',
      );
    });

    test('dado un envoltorio que no abre con la contraseña, devuelve contraseña que no abre', () {
      expect(
        DbLocalRepositoryImpl.traducir(const EnvoltorioNoAbreException()),
        const FailurePasswordNoAbreDatos(),
      );
    });

    test('dado que no hay envoltorio o no se puede leer, no hay recuperación por contraseña', () {
      expect(
        DbLocalRepositoryImpl.traducir(const SinEnvoltorioException()),
        const FailureAlmacenSeguroSinRecuperacion(),
      );
      expect(
        DbLocalRepositoryImpl.traducir(const EnvoltorioCorruptoException('x')),
        const FailureAlmacenSeguroSinRecuperacion(),
      );
    });

    test('dado un archivo de una versión posterior, devuelve el texto de la HU', () {
      final falla = DbLocalRepositoryImpl.traducir(
        const EsquemaDbPosteriorException(versionArchivo: 9, versionApp: 2),
      );

      expect(falla, const FailureEsquemaPosterior());
      expect(
        falla.mensaje,
        'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
        'datos.',
      );
    });

    test('dado la DB llena o el disco sin espacio, devuelve sin espacio (texto de la HU)', () {
      final llena = SqliteException(extendedResultCode: 13, message: 'database or disk is full');
      const sinEspacio = FileSystemException('no se pudo escribir', '/x', OSError('ENOSPC', 28));

      expect(
        DbLocalRepositoryImpl.traducir(DbLocalException(operacion: 'abrir', causa: llena)),
        const FailureSinEspacio(),
      );
      expect(
        DbLocalRepositoryImpl.traducir(
          const DbLocalException(operacion: 'borrar', causa: sinEspacio),
        ),
        const FailureSinEspacio(),
      );
      expect(
        DbLocalRepositoryImpl.traducir(
          const ArchivoEnvoltorioException(operacion: 'escribir', causa: sinEspacio),
        ),
        const FailureSinEspacio(),
      );
      expect(const FailureSinEspacio().mensaje, 'No hay espacio suficiente para preparar el app');
    });

    test('dado otra falla de la DB o una desconocida, devuelve inesperado', () {
      const otraIo = FileSystemException('permiso', '/x', OSError('EACCES', 13));

      expect(
        DbLocalRepositoryImpl.traducir(const DbLocalException(operacion: 'abrir', causa: otraIo)),
        isA<FailureInesperado>(),
      );
      expect(
        DbLocalRepositoryImpl.traducir(const ArchivoEnvoltorioException(operacion: 'leer')),
        isA<FailureInesperado>(),
      );
      expect(DbLocalRepositoryImpl.traducir(const FormatException()), isA<FailureInesperado>());
    });
  });
}
