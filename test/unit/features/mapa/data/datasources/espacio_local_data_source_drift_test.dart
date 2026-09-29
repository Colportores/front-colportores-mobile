// Gestión de espacios (HU-UBI-007) contra las tablas reales: AppDatabase en memoria, mismo esquema
// y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/espacio_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  final t1 = t0.add(const Duration(minutes: 5));

  UbicacionModel ubicacion({
    String id = 'ub-1',
    TipoUbicacion tipo = TipoUbicacion.edificio,
    DateTime? deletedAt,
  }) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', deletedAt: deletedAt),
  );

  EspacioModel espacio({
    String id = 'esp-1',
    String ubicacionId = 'ub-1',
    String? numeroDepto = '5B',
    DateTime? deletedAt,
  }) => EspacioModel(
    id: id,
    ubicacionId: ubicacionId,
    numeroDepto: numeroDepto,
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', deletedAt: deletedAt),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
  });

  tearDown(() => db.close());

  Future<int> filas(String tabla) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle()).read<int>('n');

  /// Lo encolado como listas: un record compara el Map por identidad, `equals` por dentro.
  List<List<Object?>> cola() =>
      encolador.encolados.map((c) => [c.entidad, c.operacion, c.payload]).toList();

  Matcher rechaza(MotivoRechazoEspacio motivo) =>
      throwsA(isA<EspacioRechazadoException>().having((e) => e.motivo, 'motivo', motivo));

  Future<void> conEdificio() async {
    await local.insertar(ubicacion());
  }

  group('insertarEspacio', () {
    test('dado un edificio, cuando agrega un espacio, lo guarda y encola primero la ubicación (ya '
        'encolada al crearla) y después el espacio con la fila entera', () async {
      final u = ubicacion();
      await local.insertar(u);
      final e = espacio();

      final r = await local.insertarEspacio(e);

      expect(r.yaEstaba, isFalse);
      expect(r.espacio, e);
      expect(await filas('espacio'), 1);
      expect(cola(), [
        ['ubicacion', OperacionSync.insert, u.toJson()],
        ['espacio', OperacionSync.insert, e.toJson()],
      ]);
      final fila = await db.customSelect('SELECT numero_depto FROM espacio').getSingle();
      expect(fila.read<String>('numero_depto'), '5B');
    });

    test('dado un negocio, cuando agrega un espacio, lo guarda', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.negocio));

      await local.insertarEspacio(espacio());

      expect(await filas('espacio'), 1);
    });

    test('dado que ya existe un espacio con ese id, cuando lo agrega de nuevo (doble toque), no '
        'escribe ni encola nada y devuelve el que estaba', () async {
      await conEdificio();
      await local.insertarEspacio(espacio());

      final r = await local.insertarEspacio(espacio(numeroDepto: '9Z'));

      expect(r.yaEstaba, isTrue);
      expect(r.espacio.numeroDepto, '5B');
      expect(await filas('espacio'), 1);
      expect(encolador.encolados, hasLength(2));
    });

    test('dado una ubicación que no existe, cuando agrega un espacio, lo rechaza', () async {
      await expectLater(
        local.insertarEspacio(espacio()),
        rechaza(MotivoRechazoEspacio.ubicacionInexistente),
      );
      expect(await filas('espacio'), 0);
    });

    test('dado una casa, cuando agrega un espacio, lo rechaza: su espacio default no se '
        'gestiona', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.casa));

      await expectLater(
        local.insertarEspacio(espacio()),
        rechaza(MotivoRechazoEspacio.ubicacionCasa),
      );
      expect(await filas('espacio'), 0);
      expect(encolador.encolados, hasLength(1));
    });

    test('dado un edificio dado de baja, cuando agrega un espacio, lo rechaza', () async {
      await local.insertar(ubicacion(deletedAt: t1));

      await expectLater(
        local.insertarEspacio(espacio()),
        rechaza(MotivoRechazoEspacio.ubicacionDeBaja),
      );
      expect(await filas('espacio'), 0);
    });

    test('dado un espacio "5B" activo, cuando agrega " 5b " (otra caja, con espacios) en la misma '
        'ubicación, lo rechaza como duplicado', () async {
      await conEdificio();
      await local.insertarEspacio(espacio());

      await expectLater(
        local.insertarEspacio(espacio(id: 'esp-2', numeroDepto: ' 5b ')),
        rechaza(MotivoRechazoEspacio.deptoDuplicado),
      );
      expect(await filas('espacio'), 1);
    });

    test('dado "5B" en otra ubicación o dado de baja, cuando agrega "5B", lo permite', () async {
      await conEdificio();
      await local.insertar(ubicacion(id: 'ub-2'));
      await local.insertarEspacio(espacio(ubicacionId: 'ub-2'));
      await local.insertarEspacio(espacio(id: 'esp-baja', numeroDepto: '7A', deletedAt: t1));

      await local.insertarEspacio(espacio(id: 'esp-2'));
      await local.insertarEspacio(espacio(id: 'esp-3', numeroDepto: '7A'));

      expect(await filas('espacio'), 4);
    });

    test('dado que el encolado falla, cuando agrega un espacio, no queda la fila', () async {
      await conEdificio();
      encolador
        ..fallarCon = StateError('sin cola')
        ..fallarDespuesDe = encolador.encolados.length;

      await expectLater(local.insertarEspacio(espacio()), throwsStateError);

      expect(await filas('espacio'), 0);
    });
  });

  group('actualizarNumeroDepto', () {
    setUp(() async {
      await conEdificio();
      await local.insertarEspacio(espacio());
      await local.insertarEspacio(espacio(id: 'esp-2', numeroDepto: '6C'));
      encolador.encolados.clear();
    });

    test('dado un espacio "5B", cuando lo cambia a "5C", guarda el número y updated_at, deja '
        'sync_version y encola el update con la fila entera', () async {
      final r = await local.actualizarNumeroDepto('esp-1', numeroDepto: '5C', ahora: t1);

      expect(r.numeroDepto, '5C');
      expect(r.auditoria.updatedAt, t1);
      expect(r.auditoria.createdAt, t0);
      expect(r.auditoria.syncVersion, 0);
      expect(cola(), [
        ['espacio', OperacionSync.update, r.toJson()],
      ]);
    });

    test('dado el mismo número, cuando lo "cambia", no escribe ni encola', () async {
      final r = await local.actualizarNumeroDepto('esp-1', numeroDepto: '5B', ahora: t1);

      expect(r.auditoria.updatedAt, t0);
      expect(encolador.encolados, isEmpty);
    });

    test('dado que otro espacio activo tiene "6c", cuando lo cambia a "6c", lo rechaza', () async {
      await expectLater(
        local.actualizarNumeroDepto('esp-1', numeroDepto: '6c', ahora: t1),
        rechaza(MotivoRechazoEspacio.deptoDuplicado),
      );
      expect(encolador.encolados, isEmpty);
    });

    test('dado un espacio que no existe, lo rechaza', () async {
      await expectLater(
        local.actualizarNumeroDepto('nada', numeroDepto: '1', ahora: t1),
        rechaza(MotivoRechazoEspacio.espacioInexistente),
      );
    });

    test('dado un espacio dado de baja, lo rechaza', () async {
      await local.darDeBajaEspacio('esp-1', ahora: t1);

      await expectLater(
        local.actualizarNumeroDepto('esp-1', numeroDepto: '5C', ahora: t1),
        rechaza(MotivoRechazoEspacio.espacioDeBaja),
      );
    });

    test('dado el espacio de una casa, lo rechaza', () async {
      await local.insertar(ubicacion(id: 'ub-casa', tipo: TipoUbicacion.casa));
      await db.customStatement(
        'INSERT INTO espacio (id, ubicacion_id, created_at, updated_at) '
        "VALUES ('esp-casa', 'ub-casa', 1, 1)",
      );

      await expectLater(
        local.actualizarNumeroDepto('esp-casa', numeroDepto: '1', ahora: t1),
        rechaza(MotivoRechazoEspacio.ubicacionCasa),
      );
    });
  });

  group('darDeBajaEspacio', () {
    setUp(() async {
      await conEdificio();
      await local.insertarEspacio(espacio());
      encolador.encolados.clear();
    });

    test('dado un espacio activo, cuando lo da de baja, marca deleted_at y encola el update con la '
        'fila entera', () async {
      final r = await local.darDeBajaEspacio('esp-1', ahora: t1);

      expect(r.auditoria.deletedAt, t1);
      expect(r.auditoria.updatedAt, t1);
      expect(await filas('espacio'), 1);
      expect(cola(), [
        ['espacio', OperacionSync.update, r.toJson()],
      ]);
    });

    test('dado un espacio ya dado de baja, cuando lo da de baja de nuevo, no escribe ni '
        'encola', () async {
      await local.darDeBajaEspacio('esp-1', ahora: t1);
      encolador.encolados.clear();

      final r = await local.darDeBajaEspacio('esp-1', ahora: t1.add(const Duration(hours: 1)));

      expect(r.auditoria.deletedAt, t1);
      expect(encolador.encolados, isEmpty);
    });

    test('dado un espacio que no existe, lo rechaza', () async {
      await expectLater(
        local.darDeBajaEspacio('nada', ahora: t1),
        rechaza(MotivoRechazoEspacio.espacioInexistente),
      );
    });

    test('dado el espacio de una casa, lo rechaza', () async {
      await local.insertar(ubicacion(id: 'ub-casa', tipo: TipoUbicacion.casa));
      await db.customStatement(
        'INSERT INTO espacio (id, ubicacion_id, created_at, updated_at) '
        "VALUES ('esp-casa', 'ub-casa', 1, 1)",
      );

      await expectLater(
        local.darDeBajaEspacio('esp-casa', ahora: t1),
        rechaza(MotivoRechazoEspacio.ubicacionCasa),
      );
    });

    test('dado que el encolado falla, no queda la baja', () async {
      encolador.fallarCon = StateError('sin cola');

      await expectLater(local.darDeBajaEspacio('esp-1', ahora: t1), throwsStateError);

      expect((await local.buscarEspacio('esp-1'))!.espacio.estaBorrada, isFalse);
    });
  });

  group('restaurarEspacio', () {
    setUp(() async {
      await conEdificio();
      await local.insertarEspacio(espacio());
      await local.darDeBajaEspacio('esp-1', ahora: t1);
      encolador.encolados.clear();
    });

    test(
      'dado un espacio de baja, cuando lo restaura, limpia deleted_at y encola el update',
      () async {
        final t2 = t1.add(const Duration(hours: 1));

        final r = await local.restaurarEspacio('esp-1', ahora: t2);

        expect(r.estaBorrada, isFalse);
        expect(r.auditoria.updatedAt, t2);
        expect(cola(), [
          ['espacio', OperacionSync.update, r.toJson()],
        ]);
      },
    );

    test('dado un espacio activo, cuando lo restaura, no escribe ni encola', () async {
      await local.restaurarEspacio('esp-1', ahora: t1);
      encolador.encolados.clear();

      await local.restaurarEspacio('esp-1', ahora: t1);

      expect(encolador.encolados, isEmpty);
    });

    test('dado que otro espacio activo tomó el número, cuando lo restaura, lo rechaza', () async {
      await local.insertarEspacio(espacio(id: 'esp-2'));

      await expectLater(
        local.restaurarEspacio('esp-1', ahora: t1),
        rechaza(MotivoRechazoEspacio.deptoDuplicado),
      );
    });

    test('dado que el edificio se dio de baja, cuando lo restaura, lo rechaza', () async {
      await db.customStatement('UPDATE ubicacion SET deleted_at = 1');

      await expectLater(
        local.restaurarEspacio('esp-1', ahora: t1),
        rechaza(MotivoRechazoEspacio.ubicacionDeBaja),
      );
    });

    test('dado un espacio que no existe, lo rechaza', () async {
      await expectLater(
        local.restaurarEspacio('nada', ahora: t1),
        rechaza(MotivoRechazoEspacio.espacioInexistente),
      );
    });
  });

  group('lecturas', () {
    setUp(() async {
      await conEdificio();
      await local.insertarEspacio(espacio(id: 'esp-b', numeroDepto: '2B'));
      await local.insertarEspacio(espacio(id: 'esp-a', numeroDepto: '1A'));
      await local.insertarEspacio(espacio(id: 'esp-c', numeroDepto: '3C'));
      await local.darDeBajaEspacio('esp-c', ahora: t1);
    });

    test('listarEspacios devuelve los activos ordenados por numero_depto', () async {
      final r = await local.listarEspacios('ub-1');

      expect(r.map((e) => e.id), ['esp-a', 'esp-b']);
    });

    test('listarEspacios con incluirBajas suma los dados de baja', () async {
      final r = await local.listarEspacios('ub-1', incluirBajas: true);

      expect(r.map((e) => e.id), ['esp-a', 'esp-b', 'esp-c']);
    });

    test('listarEspacios de otra ubicación viene vacío', () async {
      expect(await local.listarEspacios('ub-2'), isEmpty);
    });

    test('contarEspaciosActivos cuenta solo los activos', () async {
      expect(await local.contarEspaciosActivos('ub-1'), 2);
      expect(await local.contarEspaciosActivos('ub-2'), 0);
    });

    test('buscarEspacio devuelve el espacio con su ubicación', () async {
      final r = await local.buscarEspacio('esp-a');

      expect(r!.espacio.numeroDepto, '1A');
      expect(r.ubicacion.id, 'ub-1');
    });

    test('buscarEspacio devuelve null si no existe o si su ubicación no llegó', () async {
      await local.insertarEspacio(espacio(id: 'esp-x', ubicacionId: 'ub-1'));
      await db.customStatement("UPDATE espacio SET ubicacion_id = 'huerfana' WHERE id = 'esp-x'");

      expect(await local.buscarEspacio('nada'), isNull);
      expect(await local.buscarEspacio('esp-x'), isNull);
    });
  });
}
