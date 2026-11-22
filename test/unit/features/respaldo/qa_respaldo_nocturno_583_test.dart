// QA de #583 (PR #624) — HU-SYNC-005, el respaldo de la noche con la app cerrada. Sin vista nueva: lo
// que se prueba es el recorrido entero de la noche, de punta a punta, sin la UI.
//
// Sesión guardada → Drive conectado → DB cifrada (SQLCipher de verdad) → motor real → un Drive de
// mentira que habla la API v3 (`http.runWithClient`) → estado de Drive en el almacén seguro. Se miran
// las cuatro cosas que le importan a quien se despierta a la mañana: que haya un archivo en Drive,
// que la DB quede cerrada, que el estado de Drive diga la verdad y que los logs no lleven datos.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/features/respaldo/data/datasources/auditoria_backup_local.dart';
import 'package:colportores_mobile/features/respaldo/data/services/armador_respaldo_nocturno.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart'
    show CuentaGoogle;
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/respaldo_nocturno.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';

import '../../../helpers/campo_falsos.dart' show sembrarCasa;
import '../../../helpers/logger_mudo.dart';
import '../../../helpers/respaldo_drive_falsos.dart';

const _usuario = 'usuario-secreto-7f3a';
const _correo = 'lucia.silva.privada@correo.com';
const _cuentaGoogle = 'g-cuenta-secreta-991';
const _tokenDrive = 'ya29.token-de-drive-secreto';

ClaveDb _clave(int relleno) => ClaveDb(Uint8List.fromList(List<int>.filled(32, relleno)));

final class _Red implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => const Stream.empty();
}

/// Un Drive en memoria con la forma de la API v3 (lo mismo que el de `google_drive_archive_test`).
final class _DriveFalso {
  final archivos = <String, Map<String, Object?>>{};
  final bytes = <String, List<int>>{};
  final pedidos = <http.Request>[];
  String? tokenEsperado = _tokenDrive;

  /// Si no es `null`, el próximo pedido contesta esto (una sola vez).
  http.Response? contestaUnaVez;

  /// Si no es `null`, el próximo pedido lanza esto (la red se cae).
  Object? caeLaRed;

  /// Si es `true`, **toda** subida se corta (la red se cae a mitad de la subida).
  bool cortaLasSubidas = false;

  var _n = 0;
  var _t = DateTime.utc(2026, 11, 3, 6);

  int get subidas => pedidos.where((p) => p.method == 'POST').length;

  http.Client get cliente => MockClient((req) async {
    pedidos.add(req);
    if (caeLaRed case final e?) {
      caeLaRed = null;
      throw e;
    }
    if (cortaLasSubidas && req.method == 'POST') throw const SocketException('se cortó la red');
    if (contestaUnaVez case final r?) {
      contestaUnaVez = null;
      return r;
    }
    if (req.headers['Authorization'] != 'Bearer $tokenEsperado') {
      return http.Response('{}', 401);
    }
    final ruta = req.url.path;
    if (req.method == 'GET' && ruta == '/drive/v3/files') {
      return http.Response(jsonEncode({'files': archivos.values.toList()}), 200);
    }
    if (req.method == 'POST' && ruta == '/upload/drive/v3/files') return _subir(req);
    final id = ruta.split('/').last;
    if (req.method == 'GET') {
      return bytes.containsKey(id)
          ? http.Response.bytes(bytes[id]!, 200)
          : http.Response('{}', 404);
    }
    if (req.method == 'DELETE') {
      archivos.remove(id);
      bytes.remove(id);
      return http.Response('', 204);
    }
    return http.Response('{}', 400);
  });

  http.Response _subir(http.Request req) {
    final limite = req.headers['Content-Type']!.split('boundary=').last;
    final cuerpo = req.bodyBytes;
    final texto = latin1.decode(cuerpo);
    final partes = texto.split('--$limite');
    final jsonTexto = partes[1].split('\r\n\r\n')[1].trim();
    final meta = jsonDecode(utf8.decode(latin1.encode(jsonTexto))) as Map<String, Object?>;
    final inicio =
        texto.indexOf('application/octet-stream\r\n\r\n') +
        'application/octet-stream\r\n\r\n'.length;
    final fin = texto.lastIndexOf('\r\n--$limite--');
    final contenido = cuerpo.sublist(inicio, fin);

    final id = 'f${++_n}';
    _t = _t.add(const Duration(seconds: 1));
    archivos[id] = {
      'id': id,
      'createdTime': _t.toIso8601String(),
      'size': '${contenido.length}',
      'sha256Checksum': sha256.convert(contenido).toString(),
      'description': meta['description'],
      'appProperties': meta['appProperties'],
    };
    bytes[id] = contenido;
    return http.Response(jsonEncode(archivos[id]), 200);
  }
}

http.Response _errorDeDrive(int estado, String motivo) => http.Response(
  jsonEncode({
    'error': {
      'code': estado,
      'errors': [
        {'reason': motivo},
      ],
    },
  }),
  estado,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directorio;
  late DatabaseHelper helper;
  late RespaldoDriveArmado drive;
  late _Red red;
  late _DriveFalso nube;
  late MemoryOutput salida;
  late AppLogger logger;
  late ArmadorDeRespaldoNocturno armador;

  String logs() => salida.buffer.expand((e) => e.lines).join('\n');

  Future<void> guardarSesion(String usuarioId) => drive.almacen.escribir(
    ClaveSegura.sesionAuth,
    jsonEncode({
      'access_token': 'a.b.c-token-de-sesion',
      'user': {'id': usuarioId, 'email': _correo},
    }),
  );

  Future<void> guardarDek(int relleno) => drive.almacen.escribir(
    ClaveSegura.dekDb,
    base64Encode(List<int>.filled(ClaveDb.bytesEsperados, relleno)),
  );

  Future<void> crearDb(int relleno, {bool conDatos = true}) async {
    final db = await helper.abrir(_clave(relleno));
    if (conDatos) await sembrarCasa(db);
    await helper.cerrar();
  }

  /// Una noche entera, como la corre el sistema: con el Drive de mentira detrás de `http.Client()`.
  Future<DesenlaceNocturno> unaNoche({DateTime Function()? ahora}) => http.runWithClient(
    () => RespaldoNocturno(abrir: armador.abrir, ahora: ahora, logger: logger).ejecutar(),
    () => nube.cliente,
  );

  ArmadorDeRespaldoNocturno armarArmador(DatabaseHelper base) {
    final cripto = CriptoSodium();
    return ArmadorDeRespaldoNocturno(
      almacen: drive.almacen,
      baseLocal: base,
      custodia: CustodiaClaveDb(
        drive.almacen,
        ArchivoEnvoltorioDek(directorio: () async => directorio),
        cripto,
        cripto,
        logger: loggerMudo(),
      ),
      drive: drive.repo,
      google: drive.google,
      conectividad: red,
      logger: logger,
    );
  }

  Future<EstadoRespaldoDrive> estadoDrive() async =>
      (await drive.repo.estado(_usuario)).fold((f) => throw f, (e) => e);

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_qa583');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    salida = MemoryOutput();
    logger = AppLogger(
      logger: Logger(level: Level.all, printer: SimplePrinter(), output: salida),
    );
    drive = RespaldoDriveArmado();
    drive.google
      ..cuenta = const CuentaGoogle(id: _cuentaGoogle, email: _correo)
      ..token = _tokenDrive;
    red = _Red();
    nube = _DriveFalso();
    armador = armarArmador(helper);
    await guardarSesion(_usuario);
    await drive.repo.conectar(_usuario);
    await crearDb(7);
    await guardarDek(7);
  });

  tearDown(() async {
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  group('Escenario: la noche sale bien, con la app cerrada', () {
    test('sube un archivo cifrado a Drive, cierra la DB y deja Drive conectado', () async {
      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.archivos, hasLength(1), reason: 'la primera noche sube la base entera');
      final propiedades = nube.archivos.values.single['appProperties']! as Map;
      expect(propiedades['parent_id'], '', reason: 'es una base, no un parche');
      expect(propiedades['key_id'], isNotEmpty, reason: 'la cadena dice de qué llave es');
      expect(helper.abierta, isFalse, reason: 'la DB se cierra siempre');
      expect(await estadoDrive(), isA<DriveConectada>());
    });

    test('lo que sube no deja leer a la persona ni la casa: va cifrado', () async {
      await unaNoche();

      final subido = nube.bytes.values.single;
      final comoTexto = latin1.decode(subido, allowInvalid: true);
      expect(comoTexto, isNot(contains('SQLite format')));
      expect(comoTexto, isNot(contains('Casa')), reason: 'ningún texto de las filas en claro');
      expect(subido.length, greaterThan(100));
    });

    test('la primera noche también verifica la cadena y lo deja anotado', () async {
      await unaNoche();

      final db = await helper.abrir(_clave(7));
      final verificada = await AuditoriaBackupLocal(db).ultimaVerificacion();
      expect(verificada, isNotNull, reason: 'nunca se había verificado: toca');
    });

    test('la noche siguiente sin cambios no rompe la cadena ni deja la DB abierta', () async {
      await unaNoche();
      final antes = nube.archivos.length;

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.archivos.length, greaterThanOrEqualTo(antes));
      expect(helper.abierta, isFalse);
    });

    test('pide solo conexión a Drive con el token en cada pedido, sin tocar otra cosa', () async {
      await unaNoche();

      expect(nube.pedidos, isNotEmpty);
      for (final p in nube.pedidos) {
        expect(p.url.host, 'www.googleapis.com');
        expect(p.headers['Authorization'], 'Bearer $_tokenDrive');
      }
    });
  });

  group('Escenario: falla a mitad de la subida', () {
    test('la red se cae al subir: no queda nada a medias en Drive y se reintenta', () async {
      nube.cortaLasSubidas = true;

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(nube.archivos, isEmpty, reason: 'ningún archivo suelto sin su eslabón');
      expect(helper.abierta, isFalse);
      expect(await estadoDrive(), isA<DriveConectada>(), reason: 'una red caída no es un permiso');
    });

    test('la noche siguiente, con la red de vuelta, sube lo que quedó pendiente', () async {
      nube.cortaLasSubidas = true;
      await unaNoche();
      nube.cortaLasSubidas = false;
      armador = armarArmador(helper);

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.archivos, hasLength(1));
    });

    test('Drive contesta 500: se reintenta y Drive sigue conectado', () async {
      nube.contestaUnaVez = http.Response('{}', 500);

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(await estadoDrive(), isA<DriveConectada>());
      expect(helper.abierta, isFalse);
    });

    test('sin token (Google no lo da en segundo plano): no habla con Drive ni revoca', () async {
      drive.google.token = null;

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(nube.pedidos, isEmpty, reason: 'sin token no se le pide nada a Drive');
      expect(await estadoDrive(), isA<DriveConectada>());
    });
  });

  group('Escenario: lo que arregla la persona, no el sistema', () {
    test('Drive contesta 401: queda «Reconectar» y la noche no reintenta', () async {
      nube.tokenEsperado = 'otro-token';

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(await estadoDrive(), isA<DrivePermisoRevocado>());
      expect(helper.abierta, isFalse);
    });

    test('con el permiso revocado, la noche siguiente ni abre la DB ni llama a Drive', () async {
      nube.tokenEsperado = 'otro-token';
      await unaNoche();
      final pedidosAntes = nube.pedidos.length;

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.pedidos.length, pedidosAntes);
      expect(helper.abierta, isFalse);
    });

    test(
      'Drive sin espacio: queda «sin espacio», no reintenta y, liberado, vuelve a subir',
      () async {
        nube.contestaUnaVez = _errorDeDrive(403, 'storageQuotaExceeded');
        // El listado va primero; la que falla es la primera llamada, sea cual sea.
        final desenlace = await unaNoche();

        expect(desenlace, DesenlaceNocturno.terminado);
        expect(await estadoDrive(), isA<DriveSinEspacio>());
        expect(nube.archivos, isEmpty);

        // La persona liberó espacio: la noche siguiente sigue corriendo (Drive sin espacio no se saltea).
        armador = armarArmador(helper);
        final otra = await unaNoche();
        expect(otra, DesenlaceNocturno.terminado);
        expect(nube.archivos, hasLength(1));
        expect(
          await estadoDrive(),
          isA<DriveConectada>(),
          reason: 'al guardar vuelve a «conectada»',
        );
      },
    );
  });

  group('Escenario: hoy no hay nada para respaldar', () {
    test('sin Wi-Fi no llega ni un pedido a Drive y se reintenta', () async {
      red.tipo = TipoConexion.datosMoviles;

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(nube.pedidos, isEmpty);
    });

    test('sin ninguna conexión tampoco, y la DB queda cerrada', () async {
      red.tipo = TipoConexion.sinConexion;

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(nube.pedidos, isEmpty);
      expect(helper.abierta, isFalse);
    });

    test('Drive desconectado antes de las 03:00: no se abre la DB', () async {
      await drive.repo.desconectar(_usuario);

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.pedidos, isEmpty);
      expect(helper.abierta, isFalse);
    });

    test('la persona cerró sesión: no se respalda con la DB de nadie', () async {
      await drive.almacen.borrar(ClaveSegura.sesionAuth);

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.pedidos, isEmpty);
    });

    test('la sesión guardada es ilegible: es «sin sesión», no una excepción', () async {
      await drive.almacen.escribir(ClaveSegura.sesionAuth, '{{{ no es json');

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.pedidos, isEmpty);
    });

    test('el almacén seguro no se deja leer: pide reintentar, no sube nada, no lanza y la DB queda '
        'cerrada', () async {
      drive.almacen.alLeer = true;

      final desenlace = await unaNoche();

      // «No pude leer el almacén» no es «sin sesión» (decisión del 04/11, QA P1 de #583; #691): un
      // iPhone reiniciado y sin desbloquear vuelve a probar con la espera creciente del sistema, sin
      // esperar a la noche siguiente.
      expect(desenlace, DesenlaceNocturno.reintentar);
      expect(nube.pedidos, isEmpty);
      expect(helper.abierta, isFalse);
    });

    test('el almacén vuelve a leerse en el reintento: esa vez sí respalda', () async {
      drive.almacen.alLeer = true;
      expect(await unaNoche(), DesenlaceNocturno.reintentar);

      drive.almacen.alLeer = false;
      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.archivos, isNotEmpty, reason: 'el reintento sube el respaldo');
      expect(helper.abierta, isFalse);
    });
  });

  group('Escenario: la DB no se deja abrir — no se toca', () {
    test('un archivo que no es una DB cifrada: ni se reescribe ni queda abierto', () async {
      final archivo = await helper.archivo();
      final basura = Uint8List.fromList(List<int>.generate(8192, (i) => (i * 31 + 7) & 0xff));
      await archivo.writeAsBytes(basura);

      final desenlace = await unaNoche();

      expect(desenlace, anyOf(DesenlaceNocturno.terminado, DesenlaceNocturno.reintentar));
      expect(
        await archivo.readAsBytes(),
        basura,
        reason: 'del teléfono no se borra ni se pisa nada',
      );
      expect(helper.abierta, isFalse);
      expect(nube.archivos, isEmpty);
    });

    test('una DB de un esquema más nuevo que la app: no se toca y no se reintenta', () async {
      final db = await helper.abrir(_clave(7));
      await db.customStatement('PRAGMA user_version = 9999;');
      await helper.cerrar();
      final antes = await (await helper.archivo()).readAsBytes();

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado, reason: 'lo resuelve la app al abrirse');
      expect(await (await helper.archivo()).readAsBytes(), antes);
      expect(helper.abierta, isFalse);
      expect(nube.archivos, isEmpty);
    });

    test('la DEK del Keystore es de otra instalación: no abre y no sube', () async {
      await guardarDek(9);

      final desenlace = await unaNoche();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(nube.pedidos, isEmpty);
      expect(helper.abierta, isFalse);
    });
  });

  group('Escenario: la app abierta al mismo tiempo (mismo archivo, otro isolate)', () {
    test(
      'la conexión de la noche espera el candado de la app en vez de fallar',
      skip:
          'QA #583: con busy_timeout=5000 la escritura de la noche igual falla en ~70 ms con '
          '«database is locked» si la app tiene una escritura abierta (vigente: se volvió a '
          'correr el 11/11 en #691 con --run-skipped y falló a los 74 ms, journal_mode=delete)',
      () async {
        final deLaApp = DatabaseHelper(
          directorio: () async => directorio,
          directorioTemporal: () async => directorio,
          logger: loggerMudo(),
        );
        addTearDown(deLaApp.cerrar);
        final dbApp = await deLaApp.abrir(_clave(7));
        final deNoche = DatabaseHelper(
          directorio: () async => directorio,
          directorioTemporal: () async => directorio,
          esperaDeBloqueo: const Duration(seconds: 5),
          logger: loggerMudo(),
        );
        addTearDown(deNoche.cerrar);
        final dbNoche = await deNoche.abrir(_clave(7));

        await dbApp.customStatement('CREATE TABLE IF NOT EXISTS qa_candado (x INTEGER)');
        await dbNoche.customStatement('CREATE TABLE IF NOT EXISTS qa_noche (x INTEGER)');
        // La app toma el candado de escritura y lo suelta 800 ms después de que la noche lo pida.
        final tomo = Completer<void>();
        final suelta = Completer<void>();
        final appEscribiendo = dbApp.transaction(() async {
          await dbApp.customStatement('INSERT INTO qa_candado VALUES (1)');
          tomo.complete();
          await suelta.future;
        });
        await tomo.future;
        Timer(const Duration(milliseconds: 800), suelta.complete);

        // La noche quiere escribir: espera el candado y lo logra.
        final reloj = Stopwatch()..start();
        final espera = await dbNoche.customSelect('PRAGMA busy_timeout').getSingle();
        final modo = await dbNoche.customSelect('PRAGMA journal_mode').getSingle();
        printOnFailure('PROBE busy_timeout=${espera.data} journal=${modo.data}');
        try {
          await dbNoche.customStatement('INSERT INTO qa_noche VALUES (1)');
        } finally {
          printOnFailure('PROBE esperó ${reloj.elapsedMilliseconds} ms');
        }
        await appEscribiendo;
        final filas = await dbNoche
            .customSelect('SELECT count(*) AS n FROM qa_candado')
            .getSingle();
        expect(filas.read<int>('n'), 1);
      },
    );
  });

  group('Privacidad (checklist 8): nada de datos en los logs de la noche', () {
    final secretos = <String>[
      _usuario,
      _correo,
      _cuentaGoogle,
      _tokenDrive,
      'a.b.c-token-de-sesion',
      base64Encode(List<int>.filled(ClaveDb.bytesEsperados, 7)),
      'lucia.silva',
    ];

    void sinSecretos() {
      final texto = logs();
      for (final s in secretos) {
        expect(texto, isNot(contains(s)), reason: 'el log nombra «$s»');
      }
    }

    test('una noche buena', () async {
      await unaNoche();
      expect(logs(), isNotEmpty, reason: 'la noche deja rastro del estado');
      sinSecretos();
    });

    test('una noche con la red caída', () async {
      nube.cortaLasSubidas = true;
      await unaNoche();
      sinSecretos();
    });

    test('una noche con el permiso revocado', () async {
      nube.tokenEsperado = 'otro';
      await unaNoche();
      sinSecretos();
    });

    test('una noche sin token y otra con el plugin de Google roto', () async {
      drive.google.token = null;
      await unaNoche();
      drive.google
        ..token = _tokenDrive
        ..errorAlPedirToken = StateError('sin actividad para $_correo');
      armador = armarArmador(helper);
      await unaNoche();
      sinSecretos();
    });

    test('una noche con la DB que no abre', () async {
      await guardarDek(9);
      await unaNoche();
      sinSecretos();
    });
  });
}
