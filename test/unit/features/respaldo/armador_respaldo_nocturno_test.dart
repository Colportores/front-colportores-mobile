// Lo que arma el respaldo de la noche sin pantalla (HU-SYNC-005, ADR-009, #583): la sesión guardada,
// Drive conectado, la DB cifrada abierta con la DEK del Keystore y el motor de siempre. Contra
// SQLCipher de verdad (el mismo mecanismo que en el teléfono) y el almacén seguro en memoria.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:colportores_mobile/features/respaldo/data/services/armador_respaldo_nocturno.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/respaldo_nocturno.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/adapters.dart' show ArchiveSinToken;
import 'package:sync_engine/sync_engine.dart' show BackupEntry;
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';
import '../../../helpers/respaldo_drive_falsos.dart';

ClaveDb _clave(int relleno) => ClaveDb(Uint8List.fromList(List<int>.filled(32, relleno)));

/// El Drive en memoria, que como el de verdad no deja hacer nada sin el token de la cuenta.
final class _DriveQueExigeToken extends FakeArchive {
  _DriveQueExigeToken(this._token, String Function(List<int>) digest)
    : super(authorized: true, digest: digest);

  final Future<String?> Function() _token;

  Future<void> _exigir() async {
    if (await _token() == null) throw const ArchiveSinToken('sin token');
  }

  @override
  Future<List<BackupEntry>> list() async {
    await _exigir();
    return super.list();
  }

  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
    DateTime? exportedAt,
    String? keyId,
    String? firma,
  }) async {
    await _exigir();
    return super.upload(
      payload: payload,
      parentId: parentId,
      watermark: watermark,
      exportedAt: exportedAt,
      keyId: keyId,
      firma: firma,
    );
  }
}

final class _Red implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => const Stream.empty();
}

void main() {
  late Directory directorio;
  late DatabaseHelper helper;
  late RespaldoDriveArmado drive;
  late _Red red;
  late ArmadorDeRespaldoNocturno armador;
  late CustodiaClaveDb custodia;

  /// El Drive en memoria del respaldo de la noche: la cadena y la clave envuelta que viaja con ella.
  FakeArchive? archivoCreado;
  late FakeKeyEnvelopes envoltoriosDrive;

  Future<void> guardarSesion(String usuarioId) => drive.almacen.escribir(
    ClaveSegura.sesionAuth,
    jsonEncode({
      'access_token': 'a.b.c',
      'user': {'id': usuarioId},
    }),
  );

  Future<void> guardarDek(int relleno) => drive.almacen.escribir(
    ClaveSegura.dekDb,
    base64Encode(List<int>.filled(ClaveDb.bytesEsperados, relleno)),
  );

  /// Crea la DB cifrada en disco con la DEK `relleno`, como la deja la app, y la cierra.
  Future<void> crearDb(int relleno) async {
    await helper.abrir(_clave(relleno));
    await helper.cerrar();
  }

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_nocturno_test');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    drive = RespaldoDriveArmado();
    red = _Red();
    final cripto = CriptoSodium();
    archivoCreado = null;
    envoltoriosDrive = FakeKeyEnvelopes();
    custodia = CustodiaClaveDb(
      drive.almacen,
      ArchivoEnvoltorioDek(directorio: () async => directorio),
      cripto,
      cripto,
      parametros: const ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1),
      logger: loggerMudo(),
    );
    armador = ArmadorDeRespaldoNocturno(
      almacen: drive.almacen,
      baseLocal: helper,
      custodia: custodia,
      drive: drive.repo,
      google: drive.google,
      conectividad: red,
      armarDrive: (token, digest) {
        // El mismo Drive en todas las noches del test.
        archivoCreado ??= _DriveQueExigeToken(token, digest);
        return (archivo: archivoCreado!, envoltorios: envoltoriosDrive);
      },
      logger: loggerMudo(),
    );
  });

  tearDown(() async {
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  group('cuando no hay nada para respaldar devuelve null y no abre la DB', () {
    test('sin sesión guardada', () async {
      await drive.repo.conectar('u-1');
      await crearDb(7);
      await guardarDek(7);

      expect(await armador.abrir(), isNull);
      expect(helper.abierta, isFalse);
    });

    test('con sesión pero sin Drive conectado', () async {
      await guardarSesion('u-1');
      await crearDb(7);
      await guardarDek(7);

      expect(await armador.abrir(), isNull);
      expect(helper.abierta, isFalse);
    });

    test('con el Drive de otra persona del teléfono', () async {
      await guardarSesion('u-2');
      await drive.repo.conectar('u-1');
      await crearDb(7);
      await guardarDek(7);

      expect(await armador.abrir(), isNull);
    });

    test('con el permiso de Drive revocado', () async {
      await guardarSesion('u-1');
      await drive.repo.conectar('u-1');
      await drive.repo.marcarPermisoRevocado('u-1');
      await crearDb(7);
      await guardarDek(7);

      expect(await armador.abrir(), isNull);
    });

    test('sin archivo de DB', () async {
      await guardarSesion('u-1');
      await drive.repo.conectar('u-1');
      await guardarDek(7);

      expect(await armador.abrir(), isNull);
      expect(await helper.existe(), isFalse, reason: 'no crea una DB vacía de noche');
    });

    test('sin DEK en el Keystore', () async {
      await guardarSesion('u-1');
      await drive.repo.conectar('u-1');
      await crearDb(7);

      expect(await armador.abrir(), isNull);
    });

    test('con una DEK que no abre la DB: no la toca', () async {
      await guardarSesion('u-1');
      await drive.repo.conectar('u-1');
      await crearDb(7);
      await guardarDek(9);
      final antes = await (await helper.archivo()).length();

      expect(await armador.abrir(), isNull);
      expect(helper.abierta, isFalse);
      expect(await (await helper.archivo()).length(), antes);
    });
  });

  group('con sesión, Drive y DB', () {
    setUp(() async {
      await guardarSesion('u-1');
      await drive.repo.conectar('u-1');
      await crearDb(7);
      await guardarDek(7);
    });

    test('abre la DB cifrada con la DEK del Keystore y la cierra al terminar', () async {
      final sesion = await armador.abrir();

      expect(sesion, isNotNull);
      expect(helper.abierta, isTrue);
      expect(await sesion!.ultimaVerificacion(), isNull, reason: 'nunca se verificó');

      await sesion.cerrar();

      expect(helper.abierta, isFalse);
    });

    test('sin Wi-Fi no sube nada y pide reintentar', () async {
      red.tipo = TipoConexion.datosMoviles;

      final desenlace = await RespaldoNocturno(
        abrir: armador.abrir,
        logger: loggerMudo(),
      ).ejecutar();

      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(helper.abierta, isFalse, reason: 'la DB se cierra aunque no haya subido');
    });

    test(
      'sin token de Drive el respaldo falla y se reintenta, sin marcar el permiso revocado',
      () async {
        drive.google.token = null;
        final sesion = (await armador.abrir())!;

        final resultado = await sesion.servicio.respaldar(OrigenRespaldo.nocturno);
        await sesion.cerrar();

        expect(
          resultado,
          isA<RespaldoFallido>().having((f) => f.causa, 'causa', CausaFalloRespaldo.otra),
        );
        final estado = (await drive.repo.estado('u-1')).fold((f) => throw f, (e) => e);
        expect(
          estado,
          isA<DriveConectada>(),
          reason: 'sin pantalla no se afirma que perdió el permiso',
        );
      },
    );

    test('si el plugin de Google falla al pedir el token, es lo mismo: se reintenta', () async {
      drive.google.errorAlPedirToken = StateError('sin actividad');
      final sesion = (await armador.abrir())!;

      final resultado = await sesion.servicio.respaldar(OrigenRespaldo.nocturno);
      await sesion.cerrar();

      expect(resultado, isA<RespaldoFallido>());
      expect(
        (await drive.repo.estado('u-1')).fold((f) => throw f, (e) => e),
        isA<DriveConectada>(),
      );
    });

    group('la clave envuelta con la contraseña viaja con el respaldo de la noche', () {
      Future<ResultadoRespaldo> respaldarDeNoche() async {
        final sesion = (await armador.abrir())!;
        final resultado = await sesion.servicio.respaldar(OrigenRespaldo.nocturno);
        await sesion.cerrar();
        return resultado;
      }

      test(
        'el respaldo guardado deja en Drive la clave envuelta, con la llave de su cadena',
        () async {
          await custodia.envolverConPassword(_clave(7), 'la contraseña');

          final resultado = await respaldarDeNoche();

          expect(resultado, isA<RespaldoHecho>());
          expect(envoltoriosDrive.subidas, 1);
          final llavesDeLaCadena = archivoCreado!.entries.map((e) => e.keyId).toSet();
          expect(llavesDeLaCadena, hasLength(1));
          expect(
            envoltoriosDrive.guardados.keys,
            llavesDeLaCadena,
            reason: 'sin ella el respaldo no se abre en un teléfono nuevo (ADR-006)',
          );
          expect(
            utf8.decode(envoltoriosDrive.guardados.values.single),
            (await custodia.leerEnvoltorioCodificado())!,
          );
        },
      );

      test('la noche siguiente, con el mismo envoltorio, no lo vuelve a subir', () async {
        await custodia.envolverConPassword(_clave(7), 'la contraseña');

        await respaldarDeNoche();
        await respaldarDeNoche();

        expect(envoltoriosDrive.subidas, 1);
      });

      test('si Drive no recibe la clave envuelta, el respaldo igual queda guardado', () async {
        await custodia.envolverConPassword(_clave(7), 'la contraseña');
        envoltoriosDrive.failOnPut = true;

        final resultado = await respaldarDeNoche();

        expect(resultado, isA<RespaldoHecho>());
        expect(envoltoriosDrive.guardados, isEmpty);
        expect(archivoCreado!.entries, isNotEmpty, reason: 'la cadena se subió');
      });

      test(
        'sin contraseña elegida todavía no hay nada que subir y el respaldo se guarda',
        () async {
          final resultado = await respaldarDeNoche();

          expect(resultado, isA<RespaldoHecho>());
          expect(envoltoriosDrive.subidas, 0);
        },
      );
    });
  });
}
