// La recuperación de los datos en un teléfono nuevo (HU-SYNC-006, contrato §7), de punta a punta con
// el código real de los dos lados: el teléfono viejo respalda con su DEK y sube la DEK envuelta con la
// contraseña; el nuevo, sin esa DEK, la desenvuelve con la contraseña, baja la cadena (o las cadenas de
// cada teléfono que la persona tuvo), las fusiona en una sola transacción, reenvía la cola y trae de
// Supabase lo que subió después.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/drift_snapshot.dart';
import 'package:colportores_mobile/features/respaldo/data/services/crypto_con_dek.dart';
import 'package:colportores_mobile/features/respaldo/data/services/envoltorio_en_drive.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_recuperacion_motor.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';
import '../../../helpers/proveedor_clave_db_falso.dart';

const _parametros = ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1);
const _password = 'la que usaba';

Map<String, Object?> _jornadaRemota(String id, String actualizada) => {
  'id': id,
  'colportor_id': 'col-1',
  'inicio': '2026-10-16T08:00:00.000Z',
  'fin': null,
  'acompaniante_id': null,
  'tipo_acompaniamiento': null,
  'total_visitas': 3,
  'total_ventas': 1,
  'created_at': '2026-10-16T08:00:00.000Z',
  'updated_at': actualizada,
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 1,
};

/// Un teléfono: su DB, su custodia de la DEK, y el motor de backup con esa DEK.
final class _Telefono {
  _Telefono(this.nombre, this.directorio, int relleno)
    : db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo()),
      dek = Uint8List.fromList(List<int>.filled(32, relleno)) {
    custodia = CustodiaClaveDb(
      AlmacenSeguroEnMemoria(),
      ArchivoEnvoltorioDek(directorio: () async => directorio),
      ProveedorClaveDbFalso(),
      CriptoSodium(),
      parametros: _parametros,
      logger: loggerMudo(),
    );
    cripto = CryptoConDek(() async => ClaveDb(Uint8List.fromList(dek)));
  }

  final String nombre;
  final Directory directorio;
  final AppDatabase db;
  final Uint8List dek;
  late final CustodiaClaveDb custodia;
  late final CryptoConDek cripto;

  DriftSnapshot get snapshot => DriftSnapshot(db, tablas: entidadesDelBackup);

  BackupService respaldo(ArchivePort drive, {DateTime Function()? clock}) =>
      BackupService(archive: drive, crypto: cripto, snapshot: snapshot, clock: clock);

  Future<void> envolver(String password) =>
      custodia.envolverConPassword(ClaveDb(Uint8List.fromList(dek)), password);

  Future<void> persona(String id, String nombre, {DateTime? actualizada}) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: nombre,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: actualizada ?? DateTime.utc(2026, 10, 1),
        ),
      );

  Future<void> encolar(String op, Map<String, Object?> fila) => DriftJobStore(db).append(
    SyncJob(
      clientOpId: op,
      entity: 'jornada',
      op: Op.insert,
      payload: fila,
      createdAt: DateTime.utc(2026, 11, 2, 20),
      rowPk: fila['id']! as String,
    ),
  );
}

/// Un Drive al que el test le corta la red en una descarga.
class _Drive extends FakeArchive {
  _Drive(DateTime Function() reloj, String Function(List<int>) digest)
    : super(authorized: true, informaHashRemoto: true, clock: reloj, digest: digest);

  int fallas = 0;

  /// Como un archivo que no informa el hash que guardó: un trozo dañado se descubre al bajarlo, no
  /// al listar (Drive real informa el hash y lo descubre antes).
  bool ocultarHashRemoto = false;

  /// Si no es `null`, solo falla la descarga de ese id.
  String? fallaSoloEn;
  Object? errorAlListar;
  final bajadas = <String>[];

  @override
  Future<List<BackupEntry>> list() async {
    if (errorAlListar case final e?) throw e;
    if (ocultarHashRemoto) return [...entries];
    return super.list();
  }

  @override
  Future<List<int>> download(String id) async {
    bajadas.add(id);
    if (fallas > 0 && (fallaSoloEn == null || fallaSoloEn == id)) {
      fallas--;
      throw TimeoutException('se cortó la red');
    }
    return super.download(id);
  }
}

/// Un snapshot que exporta lo que se le diga, para respaldos de otra versión o dañados.
final class _SnapshotAjeno implements SnapshotPort {
  _SnapshotAjeno(this._contenido);

  final String _contenido;

  @override
  Future<List<int>> export({DateTime? since}) async => utf8.encode(_contenido);

  @override
  Future<void> restore(List<List<int>> payloadsInOrder) async {}

  @override
  Future<void> restoreChains(List<List<List<int>>> chains) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory carpeta;
  late _Telefono viejo;
  late _Telefono nuevo;
  late _Drive drive;
  late FakeKeyEnvelopes sobres;
  late FakeSyncTransport servidor;
  late BackupService respaldoNuevo;
  late ServicioRecuperacionMotor servicio;
  late DateTime ahora;
  late bool hayConexion;
  late bool conDrive;
  late bool conDb;
  final clavesAbiertas = <ClaveDb>[];

  /// Los motores que armó el servicio, uno por recuperación: el servicio cierra el suyo al terminar.
  final motoresArmados = <SyncEngine>[];

  SyncEngine armarMotor() {
    final m = SyncEngine(
      specs: registroDeLaApp(nuevo.db.allTables.map((t) => t.actualTableName)),
      backup: respaldoNuevo,
      transport: servidor,
      jobs: DriftJobStore(nuevo.db),
      store: DriftLocalStore(nuevo.db, entidades: entidadesQueEscribeElMotor),
    );
    motoresArmados.add(m);
    return m;
  }

  Future<void> subirEnvoltorioDelViejo() async {
    final resultado = await EnvoltorioEnDrive(
      envoltorios: () async => sobres,
      keyId: viejo.cripto.keyId,
      envoltorioLocal: viejo.custodia.leerEnvoltorioCodificado,
      desactualizado: () async => false,
      logger: loggerMudo(),
    ).sincronizar();
    expect(resultado, ResultadoEnvoltorio.subido);
  }

  /// El teléfono viejo respalda dos veces (base + patch) y deja su envoltorio en Drive.
  Future<void> respaldarElViejo({bool conEnvoltorio = true}) async {
    await viejo.envolver(_password);
    final servicioViejo = viejo.respaldo(drive, clock: () => ahora);
    await servicioViejo.backupNow(watermark: 'w-0');
    ahora = ahora.add(const Duration(hours: 24));
    await viejo.persona('per-2', 'Beto', actualizada: ahora);
    await servicioViejo.backupNow(watermark: 'w-0');
    if (conEnvoltorio) await subirEnvoltorioDelViejo();
  }

  /// Un tercer teléfono de la persona, con otra clave y su propio respaldo (más nuevo que el del viejo).
  Future<_Telefono> respaldarOtro(
    String password, {
    bool conEnvoltorio = true,
    String marca = 'w-9',
    Future<void> Function(_Telefono otro)? antes,
  }) async {
    final otro = _Telefono(
      'otro',
      await Directory('${carpeta.path}/otro').create(recursive: true),
      3,
    );
    addTearDown(otro.db.close);
    await otro.envolver(password);
    if (antes != null) await antes(otro);
    await otro
        .respaldo(drive, clock: () => ahora.add(const Duration(days: 2)))
        .backupNow(watermark: marca);
    if (conEnvoltorio) {
      await EnvoltorioEnDrive(
        envoltorios: () async => sobres,
        keyId: otro.cripto.keyId,
        envoltorioLocal: otro.custodia.leerEnvoltorioCodificado,
        desactualizado: () async => false,
        logger: loggerMudo(),
      ).sincronizar();
    }
    return otro;
  }

  Future<RespaldoEnDrive> elRespaldo() async {
    final busqueda = await servicio.buscar();
    return (busqueda as RespaldoEncontrado).respaldo;
  }

  Future<List<String>> personasDelNuevo() async =>
      [for (final p in await nuevo.db.select(nuevo.db.personas).get()) '${p.id}:${p.nombre}']
        ..sort();

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('recuperacion_');
    viejo = _Telefono('viejo', await Directory('${carpeta.path}/viejo').create(), 1);
    nuevo = _Telefono('nuevo', await Directory('${carpeta.path}/nuevo').create(), 2);
    drive = _Drive(() => ahora, viejo.cripto.digest);
    sobres = FakeKeyEnvelopes();
    servidor = FakeSyncTransport();
    ahora = DateTime.utc(2026, 11, 2, 22);
    hayConexion = true;
    conDrive = true;
    clavesAbiertas.clear();
    motoresArmados.clear();
    conDb = true;

    respaldoNuevo = nuevo.respaldo(drive, clock: () => ahora);
    servicio = ServicioRecuperacionMotor(
      armarMotor: () => conDb ? armarMotor() : null,
      archivo: () async => conDrive ? (drive, sobres) : null,
      llavePropia: nuevo.cripto.keyId,
      abrirEnvoltorio: (envoltorio, password) async {
        final clave = await nuevo.custodia.abrirEnvoltorio(envoltorio, password);
        clavesAbiertas.add(clave);
        return clave;
      },
      snapshot: () => nuevo.snapshot,
      hayConexion: () async => hayConexion,
      ahora: () => DateTime.utc(2026, 11, 4, 9),
      logger: loggerMudo(),
    );

    await viejo.persona('per-1', 'Ana');
    await viejo.encolar(
      'op-pendiente',
      _jornadaRemota('jor-pendiente', '2026-11-02T20:00:00.000Z'),
    );
  });

  tearDown(() async {
    for (final m in motoresArmados) {
      await m.dispose();
    }
    await viejo.db.close();
    await nuevo.db.close();
    await carpeta.delete(recursive: true);
  });

  group('buscar', () {
    test('un Drive sin respaldos no ofrece nada', () async {
      expect(await servicio.buscar(), isA<SinRespaldoEnDrive>());
    });

    test('el respaldo de otro teléfono se ofrece con fecha, partes y peso', () async {
      await respaldarElViejo();

      final r = await elRespaldo();

      expect(r.partes, 2);
      expect(r.completo, isTrue);
      expect(r.tieneLlave, isTrue);
      expect(r.bytes, greaterThan(0));
      expect(r.fecha, DateTime.utc(2026, 11, 3, 22));
    });

    test('lo que respaldó este mismo teléfono no es algo para traer', () async {
      await respaldoNuevo.backupNow(watermark: 'w-0');

      expect(await servicio.buscar(), isA<SinRespaldoEnDrive>());
    });

    test('con el de este teléfono y el del viejo, ofrece solo el del viejo', () async {
      await respaldarElViejo();
      await respaldoNuevo.backupNow(watermark: 'w-0');

      final r = await elRespaldo();

      expect(r.llave, await viejo.cripto.keyId());
    });

    test('un respaldo sin la clave envuelta se ofrece, pero dice que no se puede abrir', () async {
      await respaldarElViejo(conEnvoltorio: false);

      expect((await elRespaldo()).tieneLlave, isFalse);
    });

    test('más de un respaldo: los ofrece todos juntos, sin elegir por la persona', () async {
      await respaldarElViejo();
      await respaldarOtro('otra');

      final busqueda = await servicio.buscar();

      expect(busqueda, isA<VariosRespaldosEnDrive>());
      expect((busqueda as VariosRespaldosEnDrive).respaldos, hasLength(2));
    });

    test(
      'si de dos solo uno tiene la clave envuelta, van los dos y uno dice que no se puede abrir',
      () async {
        await respaldarElViejo();
        await respaldarOtro('otra', conEnvoltorio: false);

        final busqueda = await servicio.buscar() as VariosRespaldosEnDrive;

        expect(busqueda.respaldos.map((r) => r.tieneLlave), unorderedEquals([true, false]));
      },
    );

    test('sin permiso de Drive pide conectarlo', () async {
      conDrive = false;
      expect(await servicio.buscar(), isA<DriveSinPermiso>());

      conDrive = true;
      drive.errorAlListar = const ArchiveUnauthorized('sin permiso');
      expect(await servicio.buscar(), isA<DriveSinPermiso>());
    });

    test('sin conexión lo dice; cualquier otra falla se puede reintentar; nunca lanza', () async {
      drive.errorAlListar = TimeoutException('sin red');
      expect(await servicio.buscar(), isA<BusquedaSinConexion>());

      drive.errorAlListar = StateError('raro');
      hayConexion = false;
      expect(await servicio.buscar(), isA<BusquedaSinConexion>());

      hayConexion = true;
      expect(await servicio.buscar(), isA<BusquedaFallida>());
    });
  });

  group('recuperar: de punta a punta', () {
    setUp(() async {
      await respaldarElViejo();
      // Lo que subió el teléfono viejo después del último respaldo y antes de perderse.
      servidor.seed('jornada', [_jornadaRemota('jor-posterior', '2026-11-03T23:00:00.000Z')]);
    });

    test(
      'restaura la DB, reenvía la cola y trae lo que subió después; informa de cuándo son los datos',
      () async {
        final avances = <ProgresoRecuperacion>[];

        final resultado = await servicio.recuperar(
          respaldos: [await elRespaldo()],
          password: _password,
          alAvanzar: avances.add,
        );

        final hecho = (resultado as RecuperacionHecha).informe;
        expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto']);
        expect(
          servidor.rowsOf('jornada').map((f) => f['id']),
          contains('jor-pendiente'),
          reason: 'el job que estaba en la cola del viejo se reenvió',
        );
        final jornadas = [for (final j in await nuevo.db.select(nuevo.db.jornadas).get()) j.id];
        expect(
          jornadas,
          contains('jor-posterior'),
          reason: 'la reconciliación trajo lo posterior al respaldo',
        );
        expect(hecho.parcial, isFalse);
        expect([hecho.partesRestauradas, hecho.partesTotales], [2, 2]);
        expect(hecho.trabajosReenviados, 1);
        expect(hecho.totalDeFilasTraidas, greaterThan(0));
        expect(hecho.fechaDelRespaldo, DateTime.utc(2026, 11, 3, 22));
        expect(
          hecho.ventanaPerdida,
          DateTime.utc(2026, 11, 4, 9).difference(DateTime.utc(2026, 11, 3, 22)),
        );
        expect(avances.map((a) => a.paso).toSet().toList(), [
          PasoRecuperacion.buscando,
          PasoRecuperacion.bajando,
          PasoRecuperacion.aplicando,
          PasoRecuperacion.reenviando,
          PasoRecuperacion.reconciliando,
          PasoRecuperacion.listo,
        ]);
        expect(avances.where((a) => a.paso == PasoRecuperacion.bajando).map((a) => a.hechas), [
          0,
          1,
        ]);
        expect(
          avances.firstWhere((a) => a.paso == PasoRecuperacion.aplicando).sePuedeCancelar,
          isFalse,
        );
      },
    );

    test('el motor de la recuperación se cierra al terminar, salga como salga', () async {
      await servicio.recuperar(respaldos: [await elRespaldo()], password: 'otra');
      await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

      expect(motoresArmados, isNotEmpty);
      for (final m in motoresArmados) {
        await expectLater(m.recover(), throwsStateError, reason: 'un motor cerrado ya no recupera');
      }
    });

    test('la clave del teléfono viejo se destruye al terminar, salga como salga', () async {
      await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);
      expect(clavesAbiertas.single.destruida, isTrue);
    });

    test(
      'el respaldo siguiente de este teléfono parte de una base con lo restaurado y deja intacta la cadena vieja',
      () async {
        await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);
        final entradasViejas = drive.entries.map((e) => e.id).toList();

        final siguiente = await respaldoNuevo.backupNow(watermark: 'w-n');

        expect(siguiente.isBase, isTrue);
        expect(siguiente.keyId, await nuevo.cripto.keyId());
        expect(
          drive.entries.map((e) => e.id),
          containsAll(entradasViejas),
          reason: 'no se borra lo de otro teléfono',
        );
        final claro =
            jsonDecode(utf8.decode(await nuevo.cripto.decrypt(await drive.download(siguiente.id))))
                as Map<String, Object?>;
        final filas = (((claro['tablas']! as Map)['persona']! as Map)['filas']! as List);
        expect(filas.map((f) => (f as Map)['nombre']), containsAll(['Ana', 'Beto']));
      },
    );

    test('con datos que el teléfono ya tenía, no se pierde nada', () async {
      await nuevo.persona('per-3', 'Carla', actualizada: DateTime.utc(2026, 11, 4));

      await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

      expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto', 'per-3:Carla']);
    });

    test(
      'la contraseña equivocada no abre nada: la DB queda como estaba y se puede reintentar',
      () async {
        final r = await elRespaldo();

        expect(
          await servicio.recuperar(respaldos: [r], password: 'otra'),
          isA<ContrasenaNoAbreElRespaldo>(),
        );
        expect(await personasDelNuevo(), isEmpty);
        expect(drive.bajadas, isEmpty, reason: 'ni se bajó la cadena');

        expect(
          await servicio.recuperar(respaldos: [r], password: _password),
          isA<RecuperacionHecha>(),
        );
      },
    );

    test('un respaldo sin clave envuelta no se intenta', () async {
      final r = RespaldoEnDrive(
        llave: await viejo.cripto.keyId(),
        fecha: ahora,
        partes: 2,
        bytes: 1,
        completo: true,
        tieneLlave: false,
      );

      expect(
        await servicio.recuperar(respaldos: [r], password: _password),
        isA<SinLlaveParaElRespaldo>(),
      );
    });

    test('si la clave envuelta desapareció de Drive, lo dice', () async {
      final r = await elRespaldo();
      sobres.guardados.clear();

      expect(
        await servicio.recuperar(respaldos: [r], password: _password),
        isA<SinLlaveParaElRespaldo>(),
      );
    });

    test('un envoltorio de una versión más nueva de la app pide actualizar', () async {
      final r = await elRespaldo();
      sobres.guardados[r.llave!] = utf8.encode(jsonEncode({'v': 99}));

      expect(
        await servicio.recuperar(respaldos: [r], password: _password),
        isA<RespaldoDeVersionMasNueva>(),
      );
    });

    test('un envoltorio dañado no se toma por una contraseña equivocada', () async {
      final r = await elRespaldo();
      sobres.guardados[r.llave!] = utf8.encode('esto no es un envoltorio');

      expect(
        await servicio.recuperar(respaldos: [r], password: _password),
        isA<SinLlaveParaElRespaldo>(),
      );
    });

    test(
      'cambiar la contraseña sube el envoltorio nuevo; el respaldo anterior se abre con la nueva y no con la vieja',
      () async {
        final r = await elRespaldo();
        await viejo.envolver('contraseña nueva');
        await subirEnvoltorioDelViejo();

        expect(
          await servicio.recuperar(respaldos: [r], password: _password),
          isA<ContrasenaNoAbreElRespaldo>(),
        );
        expect(
          await servicio.recuperar(respaldos: [r], password: 'contraseña nueva'),
          isA<RecuperacionHecha>(),
        );
        expect(await personasDelNuevo(), [
          'per-1:Ana',
          'per-2:Beto',
        ], reason: 'la misma DEK abre el respaldo hecho antes');
      },
    );

    group('cuando algo sale mal a mitad', () {
      test('una parte dañada: restaura hasta la última buena y lo avisa', () async {
        drive.ocultarHashRemoto = true;
        drive.corrupt(drive.entries.last.id);

        final r = await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

        final informe = (r as RecuperacionHecha).informe;
        expect(informe.parcial, isTrue);
        expect([informe.partesRestauradas, informe.partesTotales], [1, 2]);
        expect(informe.fechaDelRespaldo, DateTime.utc(2026, 11, 2, 22));
        expect(await personasDelNuevo(), ['per-1:Ana'], reason: 'lo del patch dañado no entró');
      });

      test('la base dañada: no hay nada que restaurar y la DB queda como estaba', () async {
        drive.ocultarHashRemoto = true;
        drive.corrupt(drive.entries.first.id);
        await nuevo.persona('per-3', 'Carla');

        final r = await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

        expect(r, isA<RespaldoIlegible>());
        expect(await personasDelNuevo(), ['per-3:Carla']);
      });

      test(
        'se corta la red: no se toca la DB y reintentar sigue desde la parte donde quedó',
        () async {
          final respaldo = await elRespaldo();
          drive.fallas = 100;
          drive.bajadas.clear();

          final primero = await servicio.recuperar(respaldos: [respaldo], password: _password);

          expect(primero, isA<RecuperacionSinConexion>());
          expect(await personasDelNuevo(), isEmpty);

          drive.fallas = 0;
          drive.bajadas.clear();
          final segundo = await servicio.recuperar(respaldos: [respaldo], password: _password);

          expect(segundo, isA<RecuperacionHecha>());
          expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto']);
        },
      );

      test('se corta la red a mitad: lo ya bajado no se vuelve a bajar al reintentar', () async {
        final respaldo = await elRespaldo();
        final segunda = drive.entries.last.id;
        drive
          ..fallas = 100
          ..fallaSoloEn = segunda
          ..bajadas.clear();

        final primero = await servicio.recuperar(respaldos: [respaldo], password: _password);

        expect(primero, isA<RecuperacionSinConexion>());
        expect(
          (primero as RecuperacionSinConexion).hechas,
          1,
          reason: 'la primera parte ya estaba abajo',
        );
        expect(await personasDelNuevo(), isEmpty);

        drive
          ..fallas = 0
          ..bajadas.clear();
        final segundo = await servicio.recuperar(respaldos: [respaldo], password: _password);

        expect(segundo, isA<RecuperacionHecha>());
        expect(drive.bajadas, [segunda], reason: 'solo la parte que faltaba');
        expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto']);
      });

      test(
        'si la red cae sin que el teléfono sepa que no hay conexión, igual se reconoce',
        () async {
          drive.fallas = 100;
          hayConexion = false;

          final r = await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

          expect(r, isA<RecuperacionSinConexion>());
        },
      );

      test('cancelar antes de empezar no baja nada', () async {
        final cancelar = CancelacionRecuperacion()..cancelar();
        final respaldo = await elRespaldo();

        final r = await servicio.recuperar(
          respaldos: [respaldo],
          password: _password,
          cancelar: cancelar,
        );

        expect(r, isA<RecuperacionCancelada>());
        expect(drive.bajadas, isEmpty);
        expect(await personasDelNuevo(), isEmpty);
      });

      test('cancelar en medio de la descarga descarta todo y deja la DB como estaba', () async {
        final cancelar = CancelacionRecuperacion();
        final respaldo = await elRespaldo();

        final r = await servicio.recuperar(
          respaldos: [respaldo],
          password: _password,
          cancelar: cancelar,
          alAvanzar: (p) {
            if (p.paso == PasoRecuperacion.bajando && p.hechas == 1) cancelar.cancelar();
          },
        );

        expect(r, isA<RecuperacionCancelada>());
        expect(await personasDelNuevo(), isEmpty);
        expect(clavesAbiertas.single.destruida, isTrue);
        expect(
          await DriftJobStore(nuevo.db).status().then((s) => s.pending),
          0,
          reason: 'la cola tampoco se tocó',
        );
      });

      test('dos recuperaciones seguidas: la segunda no duplica nada', () async {
        final respaldo = await elRespaldo();

        await servicio.recuperar(respaldos: [respaldo], password: _password);
        final otra = await servicio.recuperar(respaldos: [respaldo], password: _password);

        expect(otra, isA<RecuperacionHecha>());
        expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto']);
        expect(await nuevo.db.select(nuevo.db.syncQueue).get(), hasLength(1));
      });

      test('Drive dejó de dar permiso a mitad: lo dice, sin tocar nada', () async {
        final respaldo = await elRespaldo();
        conDrive = false;

        expect(
          await servicio.recuperar(respaldos: [respaldo], password: _password),
          isA<RecuperacionSinPermiso>(),
        );
        expect(await personasDelNuevo(), isEmpty);
      });

      test('sin la DB abierta no hay con qué recuperar y no lanza', () async {
        final respaldo = await elRespaldo();
        conDb = false;

        expect(
          await servicio.recuperar(respaldos: [respaldo], password: _password),
          isA<RecuperacionFallida>(),
        );
      });
    });
  });

  group('varios respaldos juntos (HU-SYNC-006, «Varios resp.»)', () {
    setUp(() async {
      await respaldarElViejo();
      servidor.seed('jornada', [_jornadaRemota('jor-posterior', '2026-11-03T23:00:00.000Z')]);
    });

    Future<List<RespaldoEnDrive>> losRespaldos() async =>
        (await servicio.buscar() as VariosRespaldosEnDrive).respaldos;

    Future<void> conLaPersonaYLaCola(_Telefono otro) async {
      await otro.persona('per-9', 'Zoe');
      await otro.encolar('op-otro', _jornadaRemota('jor-otro', '2026-11-04T01:00:00.000Z'));
    }

    test('se recuperan todos los que abre la contraseña y se fusionan en la DB', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);
      final respaldos = await losRespaldos();

      final r = await servicio.recuperar(respaldos: respaldos, password: _password);

      final informe = (r as RecuperacionHecha).informe;
      expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto', 'per-9:Zoe']);
      expect(informe.respaldosSinAbrir, 0);
      expect(informe.parcial, isFalse);
      expect([informe.partesRestauradas, informe.partesTotales], [3, 3]);
      expect(
        informe.fechaDelRespaldo,
        respaldos.map((r) => r.fecha).reduce((a, b) => a.isAfter(b) ? a : b),
      );
      expect(clavesAbiertas, hasLength(2));
      expect(
        clavesAbiertas.every((c) => c.destruida),
        isTrue,
        reason: 'ninguna clave vieja se queda',
      );
    });

    test('la cola de cada respaldo se reenvía: no se pierde ninguna venta', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);

      final r = await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      expect((r as RecuperacionHecha).informe.trabajosReenviados, 2);
      expect(
        servidor.rowsOf('jornada').map((f) => f['id']),
        containsAll(['jor-pendiente', 'jor-otro']),
      );
    });

    for (final alReves in [false, true]) {
      test('la misma fila en dos respaldos queda con la más nueva, sin importar el orden'
          '${alReves ? ' (al revés)' : ''}', () async {
        await respaldarOtro(
          _password,
          antes: (otro) =>
              otro.persona('per-1', 'Ana (la nueva)', actualizada: DateTime.utc(2026, 11, 1)),
        );
        final respaldos = await losRespaldos();

        await servicio.recuperar(
          respaldos: alReves ? respaldos.reversed.toList() : respaldos,
          password: _password,
        );

        expect(await personasDelNuevo(), contains('per-1:Ana (la nueva)'));
      });
    }

    test('la fila más vieja de otro teléfono no pisa a la más nueva', () async {
      await respaldarOtro(
        _password,
        antes: (otro) =>
            otro.persona('per-1', 'Ana (vieja)', actualizada: DateTime.utc(2026, 9, 1)),
      );

      await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      expect(await personasDelNuevo(), contains('per-1:Ana'));
      expect(await personasDelNuevo(), isNot(contains('per-1:Ana (vieja)')));
    });

    test('lo que ya tenía el teléfono no se pierde', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);
      await nuevo.persona('per-3', 'Carla', actualizada: DateTime.utc(2026, 11, 4));

      await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto', 'per-3:Carla', 'per-9:Zoe']);
    });

    test('el pull parte del watermark del respaldo más viejo', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);

      await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      expect(
        servidor.pulls.first.watermark,
        'w-0',
        reason: 'el de aquel teléfono que respaldó antes',
      );
    });

    test('el avance cuenta las partes de todos: «n de 3»', () async {
      await respaldarOtro(_password);
      final avances = <ProgresoRecuperacion>[];

      await servicio.recuperar(
        respaldos: await losRespaldos(),
        password: _password,
        alAvanzar: avances.add,
      );

      final bajando = avances.where((a) => a.paso == PasoRecuperacion.bajando).toList();
      expect(bajando.map((a) => a.total).toSet(), {3});
      expect(bajando.map((a) => a.hechas), [0, 1, 2]);
    });

    test(
      'si la contraseña abre solo algunos, se recuperan esos y el informe dice cuántos no se abrieron',
      () async {
        await respaldarOtro('otra contraseña', antes: conLaPersonaYLaCola);
        final entradasAntes = drive.entries.map((e) => e.id).toList();
        final sobresAntes = Map.of(sobres.guardados);

        final r = await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

        final informe = (r as RecuperacionHecha).informe;
        expect(informe.respaldosSinAbrir, 1);
        expect(await personasDelNuevo(), [
          'per-1:Ana',
          'per-2:Beto',
        ], reason: 'lo de Zoe no se abrió');
        expect(
          drive.entries.map((e) => e.id),
          entradasAntes,
          reason: 'no se borra ni se pisa nada en Drive',
        );
        expect(sobres.guardados, sobresAntes);
      },
    );

    test('un respaldo sin la clave envuelta no frena a los otros: queda contado', () async {
      await respaldarOtro(_password, conEnvoltorio: false, antes: conLaPersonaYLaCola);

      final r = await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      expect((r as RecuperacionHecha).informe.respaldosSinAbrir, 1);
      expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto']);
    });

    test('un respaldo con la base dañada queda afuera y los demás entran', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);
      drive.ocultarHashRemoto = true;
      drive.corrupt(drive.entries.first.id); // la base del teléfono viejo

      final r = await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      final informe = (r as RecuperacionHecha).informe;
      expect(informe.respaldosSinAbrir, 1);
      expect(await personasDelNuevo(), ['per-9:Zoe'], reason: 'solo lo del otro teléfono');
    });

    test(
      'un respaldo cuya base no se descifra con su propia clave queda afuera y los demás entran',
      () async {
        // Un teléfono cuyo respaldo se cifró con otra clave que la que guarda su envoltorio: el hash
        // coincide (el archivo está entero), pero la base no se descifra.
        final otro = _Telefono('roto', await Directory('${carpeta.path}/roto').create(), 3);
        addTearDown(otro.db.close);
        await otro.envolver(_password);
        await otro.persona('per-9', 'Zoe');
        final ajena = CryptoConDek(() async => ClaveDb(Uint8List.fromList(List.filled(32, 8))));
        await BackupService(
          archive: drive,
          crypto: ajena,
          snapshot: otro.snapshot,
          clock: () => ahora.add(const Duration(days: 2)),
        ).backupNow(watermark: 'w-9');
        await EnvoltorioEnDrive(
          envoltorios: () async => sobres,
          keyId: ajena.keyId,
          envoltorioLocal: otro.custodia.leerEnvoltorioCodificado,
          desactualizado: () async => false,
          logger: loggerMudo(),
        ).sincronizar();
        final respaldos = await losRespaldos();
        expect(respaldos, hasLength(2));

        final r = await servicio.recuperar(respaldos: respaldos, password: _password);

        final informe = (r as RecuperacionHecha).informe;
        expect(informe.respaldosSinAbrir, 1);
        expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto'], reason: 'entró el que abre');
        expect(
          clavesAbiertas.every((c) => c.destruida),
          isTrue,
          reason: 'ninguna clave vieja se queda',
        );
      },
    );

    test('si la contraseña no abre ninguno, no se baja ni se toca nada', () async {
      await respaldarOtro('otra contraseña');

      final r = await servicio.recuperar(respaldos: await losRespaldos(), password: 'ninguna');

      expect(r, isA<ContrasenaNoAbreElRespaldo>());
      expect(drive.bajadas, isEmpty);
      expect(await personasDelNuevo(), isEmpty);
    });

    test('si ninguno tiene la clave envuelta, lo dice', () async {
      sobres.guardados.clear();
      await respaldarOtro(_password, conEnvoltorio: false);

      expect(
        await servicio.recuperar(respaldos: await losRespaldos(), password: _password),
        isA<SinLlaveParaElRespaldo>(),
      );
    });

    test(
      'reintentar después de recuperar sigue contando los que no se abrieron y no duplica nada',
      () async {
        await respaldarOtro('otra contraseña', antes: conLaPersonaYLaCola);
        final respaldos = await losRespaldos();

        await servicio.recuperar(respaldos: respaldos, password: _password);
        final otra = await servicio.recuperar(respaldos: respaldos, password: _password);

        expect((otra as RecuperacionHecha).informe.respaldosSinAbrir, 1);
        expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto']);
        expect(await nuevo.db.select(nuevo.db.syncQueue).get(), hasLength(1));
      },
    );

    test('un corte de red en la reconciliación y «Reintentar»: sigue contando el que no tenía base '
        'usable y el que la contraseña no abre (#656)', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);
      drive.ocultarHashRemoto = true;
      drive.corrupt(drive.entries.first.id); // la base del teléfono viejo
      final respaldos = await losRespaldos();
      // Un tercero que la contraseña no abre, para sumar al que no tiene base usable.
      final sinClave = RespaldoEnDrive(
        llave: 'sin-sobre',
        fecha: respaldos.first.fecha,
        partes: 1,
        bytes: 1,
        completo: true,
        tieneLlave: false,
      );
      final todos = [...respaldos, sinClave];
      servidor.failTransient(100);

      final primero = await servicio.recuperar(respaldos: todos, password: _password);

      expect(primero, isA<RecuperacionSinConexion>());
      expect(await personasDelNuevo(), ['per-9:Zoe'], reason: 'el restore ya entró');

      servidor.clearFailures();
      final segundo = await servicio.recuperar(respaldos: todos, password: _password);

      expect(
        (segundo as RecuperacionHecha).informe.respaldosSinAbrir,
        2,
        reason: 'la base dañada y el que no abre',
      );
      expect(await personasDelNuevo(), ['per-9:Zoe'], reason: 'no se restaura de nuevo');
    });

    test('cancelar a mitad de la descarga no toca la DB y destruye las dos claves', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);
      final cancelar = CancelacionRecuperacion();

      final r = await servicio.recuperar(
        respaldos: await losRespaldos(),
        password: _password,
        cancelar: cancelar,
        alAvanzar: (p) {
          if (p.paso == PasoRecuperacion.bajando && p.hechas == 2) cancelar.cancelar();
        },
      );

      expect(r, isA<RecuperacionCancelada>());
      expect(await personasDelNuevo(), isEmpty);
      expect(clavesAbiertas, hasLength(2));
      expect(clavesAbiertas.every((c) => c.destruida), isTrue);
    });

    test('uno de otra versión de la app frena a todos: nada se aplica a medias', () async {
      final otro = _Telefono('futuro', await Directory('${carpeta.path}/futuro').create(), 4);
      addTearDown(otro.db.close);
      await otro.envolver(_password);
      final futuro = jsonEncode({
        'formato': 1,
        'esquema': nuevo.db.schemaVersion + 5,
        'completo': true,
        'tablas': <String, Object?>{},
      });
      await BackupService(
        archive: drive,
        crypto: otro.cripto,
        snapshot: _SnapshotAjeno(futuro),
        clock: () => ahora.add(const Duration(days: 2)),
      ).backupNow(watermark: 'w-f');
      await EnvoltorioEnDrive(
        envoltorios: () async => sobres,
        keyId: otro.cripto.keyId,
        envoltorioLocal: otro.custodia.leerEnvoltorioCodificado,
        desactualizado: () async => false,
        logger: loggerMudo(),
      ).sincronizar();
      await nuevo.persona('per-3', 'Carla');

      final r = await servicio.recuperar(respaldos: await losRespaldos(), password: _password);

      expect(r, isA<RespaldoDeVersionMasNueva>());
      expect(await personasDelNuevo(), [
        'per-3:Carla',
      ], reason: 'ni siquiera el respaldo bueno entró');
    });

    test('un doble toque no arma dos recuperaciones: la segunda espera y no duplica', () async {
      await respaldarOtro(_password, antes: conLaPersonaYLaCola);
      final respaldos = await losRespaldos();

      final resultados = await Future.wait([
        servicio.recuperar(respaldos: respaldos, password: _password),
        servicio.recuperar(respaldos: respaldos, password: _password),
      ]);

      expect(resultados.whereType<RecuperacionHecha>(), isNotEmpty);
      expect(await personasDelNuevo(), ['per-1:Ana', 'per-2:Beto', 'per-9:Zoe']);
      expect(await nuevo.db.select(nuevo.db.syncQueue).get(), hasLength(2));
    });
  });

  group('lo que trae el respaldo no es de esta app', () {
    test(
      'de una versión más nueva: se rechaza con los dos números y la DB queda intacta',
      () async {
        await nuevo.persona('per-3', 'Carla');
        await viejo.envolver(_password);
        final futuro = jsonEncode({
          'formato': 1,
          'esquema': nuevo.db.schemaVersion + 5,
          'completo': true,
          'tablas': <String, Object?>{},
        });
        await BackupService(
          archive: drive,
          crypto: viejo.cripto,
          snapshot: _SnapshotAjeno(futuro),
          clock: () => ahora,
        ).backupNow(watermark: 'w-1');
        await subirEnvoltorioDelViejo();

        final r = await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

        expect(r, isA<RespaldoDeVersionMasNueva>());
        expect((r as RespaldoDeVersionMasNueva).esquemaDelRespaldo, nuevo.db.schemaVersion + 5);
        expect(r.esquemaDeLaApp, nuevo.db.schemaVersion);
        expect(await personasDelNuevo(), ['per-3:Carla']);
      },
    );

    test(
      'si la base de su único respaldo no se descifra, es ilegible y la DB queda igual',
      () async {
        await nuevo.persona('per-3', 'Carla');
        final ajena = CryptoConDek(() async => ClaveDb(Uint8List.fromList(List.filled(32, 8))));
        // El envoltorio de `viejo` (DEK 1) en la llave de una cadena cifrada con otra clave.
        await viejo.envolver(_password);
        await BackupService(
          archive: drive,
          crypto: ajena,
          snapshot: viejo.snapshot,
          clock: () => ahora,
        ).backupNow(watermark: 'w-1');
        await EnvoltorioEnDrive(
          envoltorios: () async => sobres,
          keyId: ajena.keyId,
          envoltorioLocal: viejo.custodia.leerEnvoltorioCodificado,
          desactualizado: () async => false,
          logger: loggerMudo(),
        ).sincronizar();

        final r = await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

        expect(r, isA<RespaldoIlegible>());
        expect(await personasDelNuevo(), ['per-3:Carla']);
      },
    );

    test('que no es un respaldo de la app: ilegible', () async {
      await viejo.envolver(_password);
      await BackupService(
        archive: drive,
        crypto: viejo.cripto,
        snapshot: _SnapshotAjeno('esto no es un respaldo'),
        clock: () => ahora,
      ).backupNow(watermark: 'w-1');
      await subirEnvoltorioDelViejo();

      final r = await servicio.recuperar(respaldos: [await elRespaldo()], password: _password);

      expect(r, isA<RespaldoIlegible>());
      expect(await personasDelNuevo(), isEmpty);
    });
  });
}
