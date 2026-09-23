// Primitivas de la DB local de HU-AUTH-009 sobre la infraestructura real: SQLCipher en un
// directorio temporal, la custodia de la sal sobre el almacén en memoria y la derivación de juguete.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
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

T _derecha<T>(Either<Failure, T> r) => r.fold((f) => fail('esperaba Right y vino $f'), (v) => v);

Failure _izquierda<T>(Either<Failure, T> r) => r.fold((f) => f, (_) => fail('esperaba Left'));

void main() {
  late Directory directorio;
  late DatabaseHelper helper;
  late AlmacenSeguroEnMemoria almacen;
  late ProveedorClaveDbFalso proveedor;
  late ProviderContainer container;
  late DbLocalRepositoryImpl repo;

  DbLocalRepositoryImpl construir({AppLogger? logger}) => DbLocalRepositoryImpl(
    custodia: CustodiaClaveDb(almacen, logger: loggerMudo()),
    proveedorClave: proveedor,
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
    container = ProviderContainer(overrides: [databaseHelperProvider.overrideWithValue(helper)]);
    repo = construir();
  });

  tearDown(() async {
    container.dispose();
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  Future<ClaveDb> derivar(String password, Uint8List sal) async =>
      _derecha(await repo.derivarClave(password: password, sal: sal));

  test('dado un dispositivo nuevo, el estado es sin marca y sin archivo', () async {
    expect(
      _derecha(await repo.estado()),
      const EstadoDbLocal(inicializada: false, archivoExiste: false),
    );
    expect(_derecha(await repo.leerSal()), isNull);
  });

  test('cuando genera la sal, la guarda y leerla devuelve la misma', () async {
    final sal = _derecha(await repo.generarSal());

    expect(sal, hasLength(32));
    expect(_derecha(await repo.leerSal()), sal);
  });

  test('cuando crea la DB y marca, el estado lo refleja y la DB queda publicada', () async {
    final sal = _derecha(await repo.generarSal());

    _derecha(await repo.abrir(await derivar('secreto123', sal)));
    _derecha(await repo.marcarInicializada());

    expect(container.read(dbLocalProvider), isNotNull);
    expect(
      _derecha(await repo.estado()),
      const EstadoDbLocal(inicializada: true, archivoExiste: true),
    );
  });

  test('dado otra contraseña, abrir la DB existente devuelve clave incorrecta y destruye la '
      'clave', () async {
    final sal = _derecha(await repo.generarSal());
    _derecha(await repo.abrir(await derivar('secreto123', sal)));
    await container.read(dbLocalProvider.notifier).cerrar();
    final otra = await derivar('otra-clave', sal);

    final r = await repo.abrir(otra);

    expect(_izquierda(r), const FailureClaveDbIncorrecta());
    expect(otra.destruida, isTrue);
    expect(container.read(dbLocalProvider), isNull);
  });

  test('dado la DB abierta, descartar la cierra, borra el archivo y olvida sal y marca', () async {
    final sal = _derecha(await repo.generarSal());
    final clave = await derivar('secreto123', sal);
    _derecha(await repo.abrir(clave));
    _derecha(await repo.marcarInicializada());

    _derecha(await repo.descartar());

    expect(container.read(dbLocalProvider), isNull);
    expect(helper.abierta, isFalse);
    expect(clave.destruida, isTrue);
    expect(await helper.existe(), isFalse);
    expect(almacen.contenido, isEmpty);
  });

  test('dado nada abierto, descartar no cuenta como un cierre de sesión', () async {
    _derecha(await repo.generarSal());

    _derecha(await repo.descartar());

    expect(container.read(dbLocalProvider.notifier).cierresPedidos, 0);
    expect(almacen.contenido, isEmpty);
  });

  group('traducción de fallas', () {
    test('dado el almacén seguro roto, devuelve la falla de almacenamiento seguro', () async {
      almacen.simularFalla = true;

      expect(_izquierda(await repo.estado()), const FailureAlmacenSeguro());
      expect(_izquierda(await repo.generarSal()), const FailureAlmacenSeguro());
      expect(_izquierda(await repo.marcarInicializada()), const FailureAlmacenSeguro());
      expect(_izquierda(await repo.descartar()), const FailureAlmacenSeguro());
    });

    test('dado una sal corrupta, devuelve la falla de almacenamiento seguro', () async {
      almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.salDb: base64Encode([1, 2, 3]),
      });
      repo = construir();

      expect(_izquierda(await repo.leerSal()), const FailureAlmacenSeguro());
    });

    test('dado una marca corrupta, devuelve la falla de almacenamiento seguro', () async {
      almacen = AlmacenSeguroEnMemoria({ClaveSegura.dbInicializada: 'quizas'});
      repo = construir();

      expect(_izquierda(await repo.estado()), const FailureAlmacenSeguro());
    });

    test('dado que la derivación falla, devuelve inesperado y no loguea el mensaje', () async {
      final salida = _SalidaEnMemoria();
      repo = construir(logger: AppLogger(output: salida));
      proveedor.falla = _FallaQueCitaLaContrasenia();

      final r = await repo.derivarClave(password: 'secreto123', sal: Uint8List(32));

      expect(_izquierda(r), isA<FailureInesperado>());
      expect(salida.lineas.join('\n'), contains('INIT_DB_FAIL'));
      expect(salida.lineas.join('\n'), isNot(contains('secreto123')));
    });

    test('dado la DB llena o el disco sin espacio, devuelve sin espacio', () {
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
    });

    test('dado otra falla de la DB o una desconocida, devuelve inesperado', () {
      const otraIo = FileSystemException('permiso', '/x', OSError('EACCES', 13));

      expect(
        DbLocalRepositoryImpl.traducir(const DbLocalException(operacion: 'abrir', causa: otraIo)),
        isA<FailureInesperado>(),
      );
      expect(
        DbLocalRepositoryImpl.traducir(const DbLocalException(operacion: 'abrir', causa: 'x')),
        isA<FailureInesperado>(),
      );
      expect(DbLocalRepositoryImpl.traducir(const FormatException()), isA<FailureInesperado>());
    });
  });
}
