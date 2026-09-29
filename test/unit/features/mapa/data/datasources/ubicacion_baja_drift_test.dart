// Baja y reactivación de ubicaciones (HU-UBI-005) contra las tablas reales: AppDatabase en memoria
// (sin cifrado), del caso de uso al repositorio y a Drift, con el encolado dentro de la transacción.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/catalogo_ciudades.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _Pendientes implements ConsultorPendientesUbicacion {
  PendientesUbicacion pendientes = PendientesUbicacion.ninguno;
  Failure? falla;
  var consultas = 0;

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async {
    consultas++;
    return falla != null ? Left(falla!) : Right(pendientes);
  }
}

final class _Catalogo implements CatalogoCiudades {
  var existeLaCiudad = true;

  @override
  Future<Either<Failure, bool>> existe(String ciudadId) async => Right(existeLaCiudad);
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 9, 30, 8, 0, 0, 500);

  UbicacionModel ubicacion({DateTime? deletedAt}) => UbicacionModel(
    id: 'ub-1',
    tipo: TipoUbicacion.edificio,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    zonaId: 'zona-9',
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: 'col-1',
      deletedAt: deletedAt,
      syncVersion: 4,
    ),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;
  late _Pendientes pendientes;
  late _Catalogo catalogo;
  late DarDeBajaUbicacionUseCase darDeBaja;
  late ReactivarUbicacionUseCase reactivar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    final repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
    pendientes = _Pendientes();
    catalogo = _Catalogo();
    darDeBaja = DarDeBajaUbicacionUseCase(repositorio, pendientes, ahora: () => t1);
    reactivar = ReactivarUbicacionUseCase(repositorio, catalogo, ahora: () => t1);
  });

  tearDown(() => db.close());

  DarDeBajaUbicacionParams baja({DateTime? base, bool confirma = false, String? motivo}) =>
      DarDeBajaUbicacionParams(
        id: 'ub-1',
        baseUpdatedAt: base ?? t0,
        confirmaPendientes: confirma,
        motivo: motivo,
      );

  Future<ResultadoBajaUbicacion> okBaja(DarDeBajaUbicacionParams p) async =>
      (await darDeBaja(p)).getOrElse(() => throw StateError('era un Left'));

  Future<Failure> fallaBaja(DarDeBajaUbicacionParams p) async =>
      (await darDeBaja(p)).swap().getOrElse(() => throw StateError('era un Right'));

  Future<UbicacionModel> guardada() async => (await local.obtener('ub-1'))!;

  Future<void> espacio(String id) => db
      .into(db.espacios)
      .insert(EspaciosCompanion.insert(id: id, ubicacionId: 'ub-1', createdAt: t0, updatedAt: t0));

  group('Baja simple sin pendientes', () {
    test(
      'dado una ubicación sin pendientes, cuando confirma "Dar de baja", se setea deleted_at, sale '
      'de la lista activa y se encola el tombstone con la fila entera',
      () async {
        await local.insertar(ubicacion());
        await espacio('e1');
        encolador.encolados.clear();

        final r = await okBaja(baja(motivo: 'Se mudó'));

        final u = await guardada();
        expect(r, isA<UbicacionDadaDeBaja>());
        expect(u.auditoria.deletedAt, t1);
        expect(u.auditoria.updatedAt, t1);
        expect(u.auditoria.syncVersion, 4, reason: 'la sube el servidor al aceptar el delete');
        expect(
          await local.observarDelColportor(colportorId: 'col-1').first,
          isEmpty,
          reason: 'ya no está en la lista activa',
        );
        expect(
          (await local.observarDelColportor(colportorId: 'col-1', incluirBajas: true).first)
              .single
              .id,
          'ub-1',
        );
        expect(encolador.encolados.map((c) => [c.entidad, c.operacion, c.payload]).toList(), [
          [
            'ubicacion',
            OperacionSync.delete,
            {
              ...ubicacion().toJson(),
              'updated_at': t1.toIso8601String(),
              'deleted_at': t1.toIso8601String(),
            },
          ],
        ]);
      },
    );

    test('dado una ubicación con espacios, cuando la da de baja, no da de baja los espacios (sin '
        'cascada) y no encola nada de ellos', () async {
      await local.insertar(ubicacion());
      await espacio('e1');
      encolador.encolados.clear();

      await okBaja(baja());

      expect(await local.contarEspaciosActivos('ub-1'), 1);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
    });
  });

  group('Baja con pendientes: doble confirmación', () {
    test(
      'dado 2 cobranzas activas, cuando inicia la baja, muestra el resumen literal y no escribe; '
      'con la segunda confirmación, procede',
      () async {
        await local.insertar(ubicacion());
        encolador.encolados.clear();
        pendientes.pendientes = const PendientesUbicacion(cobranzasActivas: 2);

        final r = await okBaja(baja());

        expect(r, isA<BajaRequiereConfirmacion>());
        expect((r as BajaRequiereConfirmacion).pendientes.resumen, [
          'Esta ubicación tiene 2 cobranzas activas. Si la das de baja, no podrás registrar nuevos '
              'cobros, pero el historial se conserva.',
        ]);
        expect((await guardada()).auditoria.deletedAt, isNull);
        expect(encolador.encolados, isEmpty);

        final confirmada = await okBaja(baja(confirma: true));

        expect(confirmada, isA<UbicacionDadaDeBaja>());
        expect((await guardada()).auditoria.deletedAt, t1);
        expect(encolador.encolados, hasLength(1));
      },
    );

    test('dado que no se puede consultar lo pendiente, cuando da de baja, devuelve esa falla sin '
        'escribir', () async {
      await local.insertar(ubicacion());
      pendientes.falla = const FailureInesperado();

      expect(await fallaBaja(baja()), isA<FailureInesperado>());
      expect((await guardada()).auditoria.deletedAt, isNull);
    });
  });

  group('Doble toque, edición concurrente y transacción', () {
    test('dado un doble toque en "Dar de baja", cuando el segundo llega con la fila ya de baja, no '
        'escribe ni encola de nuevo', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      await okBaja(baja());
      final segundo = await okBaja(baja());

      expect(segundo, isA<BajaSinCambios>());
      expect(encolador.encolados, hasLength(1));
      expect(pendientes.consultas, 1);
    });

    test(
      'dado que el pull cambió la fila entre que se cargó la pantalla y la baja, cuando la da de '
      'baja, no escribe y falla como cambio concurrente',
      () async {
        await local.insertar(ubicacion());
        encolador.encolados.clear();
        await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
          UbicacionesCompanion(updatedAt: Value(t0.add(const Duration(minutes: 5)))),
        );

        expect(await fallaBaja(baja()), const FailureUbicacionCambio());
        expect((await guardada()).auditoria.deletedAt, isNull);
        expect(encolador.encolados, isEmpty);
      },
    );

    test('dado que el encolado falla, cuando la da de baja, la fila queda activa', () async {
      await local.insertar(ubicacion());
      encolador.fallarCon = StateError('motor apagado');

      expect(await fallaBaja(baja()), isA<FailureInesperado>());
      expect((await guardada()).auditoria.deletedAt, isNull);
    });

    test('dado una ubicación que no existe o sin id, cuando la da de baja, falla', () async {
      expect(
        await fallaBaja(DarDeBajaUbicacionParams(id: 'nada', baseUpdatedAt: t0)),
        isA<FailureUbicacionInexistente>(),
      );
      expect(
        await fallaBaja(DarDeBajaUbicacionParams(id: '  ', baseUpdatedAt: t0)),
        isA<FailureValidacion>(),
      );
    });
  });

  group('Reactivación', () {
    test('dado una baja, cuando presiona "Reactivar", deleted_at vuelve a NULL, vuelve a la lista '
        'activa y se encola el update de reactivación', () async {
      await local.insertar(ubicacion(deletedAt: t0));
      encolador.encolados.clear();

      final r = (await reactivar(
        ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: t0),
      )).getOrElse(() => throw StateError('era un Left'));

      expect(r.estaBorrada, isFalse);
      final u = await guardada();
      expect(
        (u.auditoria.deletedAt, u.auditoria.updatedAt, u.auditoria.syncVersion),
        (null, t1, 4),
      );
      expect(await local.observarDelColportor(colportorId: 'col-1').first, hasLength(1));
      expect(encolador.encolados.single.operacion, OperacionSync.update);
      expect(encolador.encolados.single.payload['deleted_at'], isNull);
    });

    test(
      'dado que la ciudad ya no está en el catálogo, cuando reactiva, se bloquea sin escribir',
      () async {
        await local.insertar(ubicacion(deletedAt: t0));
        encolador.encolados.clear();
        catalogo.existeLaCiudad = false;

        final r = await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: t0));

        expect(r, const Left<Failure, Ubicacion>(FailureCiudadFueraDeCatalogo()));
        expect((await guardada()).auditoria.deletedAt, t0);
        expect(encolador.encolados, isEmpty);
      },
    );

    test('dado una ubicación ya activa (doble toque), cuando reactiva, devuelve la ubicación sin '
        'escribir', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      final r = await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: t1));

      expect(r.isRight(), isTrue);
      expect(encolador.encolados, isEmpty);
    });

    test('dado que la fila cambió desde que "Ver bajas" la cargó, cuando reactiva, falla como '
        'cambio concurrente', () async {
      await local.insertar(ubicacion(deletedAt: t0));

      final r = await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: t1));

      expect(r, const Left<Failure, Ubicacion>(FailureUbicacionCambio()));
    });

    test('dado una ubicación que no existe, cuando reactiva, falla como inexistente', () async {
      final r = await reactivar(ReactivarUbicacionParams(id: 'nada', baseUpdatedAt: t0));

      expect(r, const Left<Failure, Ubicacion>(FailureUbicacionInexistente()));
    });
  });
}
