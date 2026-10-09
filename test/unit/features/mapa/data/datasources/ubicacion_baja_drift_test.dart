// Baja y reactivación de ubicaciones (HU-UBI-005) contra las tablas reales: AppDatabase en memoria
// (sin cifrado), del caso de uso al repositorio y a Drift, con el encolado dentro de la transacción.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
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

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 9, 30, 8, 0, 0, 500);

  UbicacionModel ubicacion({String id = 'ub-1', DateTime? deletedAt, String ciudadId = 'mvd'}) =>
      UbicacionModel(
        id: id,
        tipo: TipoUbicacion.edificio,
        calle: 'Av. Italia',
        numero: '1234',
        lat: -34.891,
        lon: -56.125,
        ciudadId: ciudadId,
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
  late DarDeBajaUbicacionUseCase darDeBaja;
  late ReactivarUbicacionUseCase reactivar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    final repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
    pendientes = _Pendientes();
    darDeBaja = DarDeBajaUbicacionUseCase(repositorio, pendientes, ahora: () => t1);
    reactivar = ReactivarUbicacionUseCase(repositorio, ahora: () => t1);
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

  Future<List<AuditLogFila>> auditoria() =>
      (db.select(db.auditLogLocal)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<List<UbicacionConEspacios>> lista() =>
      local.observarListaDelColportor(colportorId: 'col-1', incluirBajas: true).first;

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

  group('Baja con visitas pendientes propias: doble confirmación', () {
    test(
      'dado 2 visitas pendientes propias, cuando inicia la baja, muestra el resumen literal y no '
      'escribe; con la segunda confirmación, procede',
      () async {
        await local.insertar(ubicacion());
        encolador.encolados.clear();
        pendientes.pendientes = const PendientesUbicacion(visitasPropiasPendientes: 2);

        final r = await okBaja(baja(motivo: 'Ya no existe'));

        expect(r, isA<BajaRequiereConfirmacion>());
        expect((r as BajaRequiereConfirmacion).pendientes.resumen, [
          'Esta ubicación tiene 2 visitas pendientes. Si la das de baja, no podrás registrar '
              'nuevas visitas, pero el historial se conserva.',
        ]);
        expect((await guardada()).auditoria.deletedAt, isNull);
        expect(encolador.encolados, isEmpty);
        expect(await auditoria(), isEmpty, reason: 'sin baja no hay motivo que guardar');

        final confirmada = await okBaja(baja(confirma: true, motivo: 'Ya no existe'));

        expect(confirmada, isA<UbicacionDadaDeBaja>());
        expect((await guardada()).auditoria.deletedAt, t1);
        expect(encolador.encolados, hasLength(1));
        expect(await auditoria(), hasLength(1));
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

  group('Baja bloqueada (decisión de Cristian, 02/10)', () {
    const cobranza = CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2);

    Future<void> comprobarSinEscribir() async {
      expect((await guardada()).auditoria.deletedAt, isNull);
      expect(encolador.encolados, isEmpty);
      expect(await auditoria(), isEmpty);
    }

    test('dado una cobranza pendiente, cuando da de baja, queda bloqueada por la cobranza sin '
        'escribir ni encolar ni guardar el motivo', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();
      pendientes.pendientes = const PendientesUbicacion(
        cobranzaPendiente: cobranza,
        tieneVentas: true,
      );

      final r = await okBaja(baja(motivo: 'Ya no existe', confirma: true));

      expect(r, const BajaBloqueada(bloqueo: BloqueoPorCobranza(cobranza)));
      await comprobarSinEscribir();
    });

    test('dado una venta sin cobranza pendiente, cuando da de baja, queda bloqueada (ventas o '
        'visitas de otro)', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();
      pendientes.pendientes = const PendientesUbicacion(tieneVentas: true);

      final r = await okBaja(baja(motivo: 'Ya no existe'));

      expect(r, const BajaBloqueada(bloqueo: BloqueoPorVentasOVisitasAjenas()));
      await comprobarSinEscribir();
    });

    test('dado una visita de otro colportor, cuando da de baja, queda bloqueada', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();
      pendientes.pendientes = const PendientesUbicacion(tieneVisitasDeOtros: true);

      final r = await okBaja(baja(motivo: 'Ya no existe'));

      expect(r, isA<BajaBloqueada>());
      await comprobarSinEscribir();
    });

    test('dado un bloqueo y además visitas propias pendientes, cuando da de baja, el bloqueo gana: '
        'no pide la segunda confirmación', () async {
      await local.insertar(ubicacion());
      pendientes.pendientes = const PendientesUbicacion(
        visitasPropiasPendientes: 3,
        tieneVisitasDeOtros: true,
      );

      expect(await okBaja(baja()), isA<BajaBloqueada>());
    });

    test('dado un bloqueo, cuando es la baja de la duplicada de una unión (HU-UBI-006), no lo '
        'aplica: esa baja no pasa por los bloqueos', () async {
      await local.insertar(ubicacion());
      await local.insertar(ubicacion(id: 'ub-2'));
      pendientes.pendientes = const PendientesUbicacion(tieneVentas: true);

      final r = await okBaja(
        DarDeBajaUbicacionParams(
          id: 'ub-1',
          baseUpdatedAt: t0,
          conservadaId: 'ub-2',
          motivo: 'duplicado_de_ub-2',
        ),
      );

      expect(r, isA<UbicacionDadaDeBaja>());
    });
  });

  group('Motivo de la baja (audit_log local)', () {
    test('dado una baja con motivo, cuando se confirma, queda una fila de auditoría con el evento, '
        'el uuid, el motivo y el mismo instante que deleted_at', () async {
      await local.insertar(ubicacion());

      await okBaja(baja(motivo: '  Se mudaron  '));

      final filas = await auditoria();
      expect(filas, hasLength(1));
      expect(filas.single.evento, EventoAuditoriaLocal.ubicacionBaja);
      expect(filas.single.uuid, 'ub-1');
      expect(filas.single.motivo, 'Se mudaron');
      expect(filas.single.creadoEn, (await guardada()).auditoria.deletedAt);
    });

    test('dado una baja sin motivo o con el motivo en blanco, cuando se confirma, no se guarda '
        'ninguna fila', () async {
      await local.insertar(ubicacion());
      await okBaja(baja(motivo: '   '));
      expect(await auditoria(), isEmpty);
    });

    test('dado que el encolado falla, cuando da de baja con motivo, no queda ni la baja ni el '
        'motivo (misma transacción)', () async {
      await local.insertar(ubicacion());
      encolador.fallarCon = StateError('motor apagado');

      await fallaBaja(baja(motivo: 'Ya no existe'));

      expect(await auditoria(), isEmpty);
    });

    test('dado un doble toque, cuando el segundo llega con la fila ya de baja, el motivo se guarda '
        'una sola vez', () async {
      await local.insertar(ubicacion());

      await okBaja(baja(motivo: 'Ya no existe'));
      await okBaja(baja(motivo: 'Ya no existe'));

      expect(await auditoria(), hasLength(1));
    });

    test(
      'dado una baja y su reactivación, cuando la vuelve a dar de baja con otro motivo, la Lista '
      'muestra el motivo vigente y la auditoría conserva los dos',
      () async {
        await local.insertar(ubicacion());
        await okBaja(baja(motivo: 'Ya no existe'));
        await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: t1));
        expect((await lista()).single.motivoBaja, isNull, reason: 'activa: no hay motivo');

        final t2 = t1.add(const Duration(days: 1));
        final otraBaja = DarDeBajaUbicacionUseCase(
          UbicacionRepositoryImpl(local, logger: loggerMudo()),
          pendientes,
          ahora: () => t2,
        );
        await otraBaja(
          DarDeBajaUbicacionParams(id: 'ub-1', baseUpdatedAt: t1, motivo: 'Está deshabitada'),
        );

        expect((await lista()).single.motivoBaja, 'Está deshabitada');
        expect((await auditoria()).map((f) => f.motivo), ['Ya no existe', 'Está deshabitada']);
      },
    );

    test('dado una baja con motivo, cuando la Lista pide las bajas, la fila trae el motivo; una '
        'ubicación activa no', () async {
      await local.insertar(ubicacion());
      await local.insertar(ubicacion(id: 'ub-2'));
      await okBaja(baja(motivo: 'No quiere visitas'));

      final filas = {for (final f in await lista()) f.ubicacion.id: f.motivoBaja};

      expect(filas, {'ub-1': 'No quiere visitas', 'ub-2': null});
    });

    test(
      'dado una baja que llegó por el sync (sin motivo local), cuando la Lista la pide, no tiene '
      'motivo',
      () async {
        await local.insertar(ubicacion(deletedAt: t0));

        expect((await lista()).single.motivoBaja, isNull);
      },
    );

    test('dado una baja con motivo, cuando se loguea, el motivo (texto libre) no sale en el '
        'log', () async {
      final salida = _SalidaEnMemoria();
      final conLog = DarDeBajaUbicacionUseCase(
        UbicacionRepositoryImpl(local, logger: AppLogger(output: salida)),
        pendientes,
        ahora: () => t1,
      );
      await local.insertar(ubicacion());

      await conLog(baja(motivo: 'La familia García se mudó a Rivera'));

      expect(salida.lineas, isNotEmpty);
      expect(salida.lineas.join(' '), isNot(contains('García')));
      expect(salida.lineas.join(' '), contains('con_motivo'));
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

        expect(await fallaBaja(baja()), const FailureBajaCambioReciente());
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

    test('dado que la ciudad ya no está en el catálogo, cuando reactiva, se reactiva igual y se '
        'encola el update (la ciudad es una parte más de la dirección)', () async {
      await local.insertar(ubicacion(deletedAt: t0, ciudadId: 'ciudad-que-ya-no-esta'));
      encolador.encolados.clear();

      final r = await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: t0));

      expect(r.isRight(), isTrue);
      final u = await guardada();
      expect((u.auditoria.deletedAt, u.ciudadId), (null, 'ciudad-que-ya-no-esta'));
      expect(encolador.encolados.single.operacion, OperacionSync.update);
    });

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

      expect(r, const Left<Failure, Ubicacion>(FailureReactivacionCambioReciente()));
    });

    test('dado una ubicación que no existe, cuando reactiva, falla como inexistente', () async {
      final r = await reactivar(ReactivarUbicacionParams(id: 'nada', baseUpdatedAt: t0));

      expect(r, const Left<Failure, Ubicacion>(FailureUbicacionInexistente()));
    });
  });

  group('UbicacionLocalDataSourceDrift.cambiarBaja (sin el chequeo previo del caso de uso)', () {
    final vieja = t0.subtract(const Duration(minutes: 1));

    test('dado una baseUpdatedAt vieja, cuando da de baja, lanza UbicacionCambioException sin '
        'escribir ni encolar', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      await expectLater(
        local.cambiarBaja('ub-1', baseUpdatedAt: vieja, updatedAt: t1, deletedAt: t1),
        throwsA(isA<UbicacionCambioException>()),
      );
      expect(await guardada(), ubicacion());
      expect(encolador.encolados, isEmpty);
    });

    test('dado una baseUpdatedAt vieja, cuando reactiva, lanza UbicacionCambioException sin '
        'escribir ni encolar', () async {
      await local.insertar(ubicacion(deletedAt: t0));
      encolador.encolados.clear();

      await expectLater(
        local.cambiarBaja('ub-1', baseUpdatedAt: vieja, updatedAt: t1, deletedAt: null),
        throwsA(isA<UbicacionCambioException>()),
      );
      expect(await guardada(), ubicacion(deletedAt: t0));
      expect(encolador.encolados, isEmpty);
    });

    test(
      'dado un id que no está, cuando cambia la baja, lanza UbicacionInexistenteException',
      () async {
        await expectLater(
          local.cambiarBaja('nada', baseUpdatedAt: t0, updatedAt: t1, deletedAt: t1),
          throwsA(isA<UbicacionInexistenteException>()),
        );
      },
    );

    test('dado una fila que ya está como se pide, cuando cambia la baja con cualquier base, la '
        'devuelve sin escribir ni encolar', () async {
      await local.insertar(ubicacion(deletedAt: t0));
      encolador.encolados.clear();

      final r = await local.cambiarBaja(
        'ub-1',
        baseUpdatedAt: t1.add(const Duration(days: 1)),
        updatedAt: t1,
        deletedAt: t1,
      );

      expect(r, (ubicacion: ubicacion(deletedAt: t0), escribio: false));
      expect(await guardada(), ubicacion(deletedAt: t0));
      expect(encolador.encolados, isEmpty);
    });

    test('dado una baja que escribe, devuelve escribio en true', () async {
      await local.insertar(ubicacion());

      final r = await local.cambiarBaja('ub-1', baseUpdatedAt: t0, updatedAt: t1, deletedAt: t1);

      expect(r.escribio, isTrue);
      expect(r.ubicacion.auditoria.deletedAt, t1);
    });

    test(
      'dado dos toques en "Dar de baja" que se pisan (los dos pasan el chequeo del caso de uso), '
      'cuando terminan, uno la da de baja, el otro no cambia nada y hay un solo tombstone y un solo '
      'evento de baja en el log',
      () async {
        final salida = _SalidaEnMemoria();
        final conLog = DarDeBajaUbicacionUseCase(
          UbicacionRepositoryImpl(local, logger: AppLogger(output: salida)),
          pendientes,
          ahora: () => t1,
        );
        await local.insertar(ubicacion());
        encolador.encolados.clear();

        final resultados = await Future.wait([conLog(baja()), conLog(baja())]);

        expect(pendientes.consultas, 2, reason: 'los dos pasaron el chequeo previo: hubo carrera');
        expect(
          resultados.map((r) => r.getOrElse(() => throw StateError('era un Left')).runtimeType),
          unorderedEquals([UbicacionDadaDeBaja, BajaSinCambios]),
        );
        expect(encolador.encolados.map((c) => c.operacion), [OperacionSync.delete]);
        expect((await guardada()).auditoria.deletedAt, t1);
        expect(salida.lineas.where((l) => l.contains('[UBICACION_BAJA]')), hasLength(1));
        expect(salida.lineas.where((l) => l.contains('[UBICACION_YA_DE_BAJA]')), hasLength(1));
      },
    );

    group('con una ubicación que tiene que seguir activa (la que se conserva)', () {
      Future<void> conservada({DateTime? deletedAt}) => local.insertar(
        UbicacionModel(
          id: 'ub-a',
          tipo: TipoUbicacion.casa,
          lat: -34.9,
          lon: -56.1,
          ciudadId: 'mvd',
          auditoria: Auditoria(createdAt: t0, updatedAt: t0, deletedAt: deletedAt),
        ),
      );

      test('si sigue activa, da de baja la otra', () async {
        await local.insertar(ubicacion());
        await conservada();

        final r = await local.cambiarBaja(
          'ub-1',
          baseUpdatedAt: t0,
          updatedAt: t1,
          deletedAt: t1,
          conservadaId: 'ub-a',
        );

        expect(r.escribio, isTrue);
      });

      test('si quedó de baja, lanza ConservadaDeBajaException sin escribir ni encolar', () async {
        await local.insertar(ubicacion());
        await conservada(deletedAt: t0);
        encolador.encolados.clear();

        await expectLater(
          local.cambiarBaja(
            'ub-1',
            baseUpdatedAt: t0,
            updatedAt: t1,
            deletedAt: t1,
            conservadaId: 'ub-a',
          ),
          throwsA(isA<ConservadaDeBajaException>()),
        );
        expect(await guardada(), ubicacion());
        expect(encolador.encolados, isEmpty);
      });

      test('si ya no está, lanza UbicacionInexistenteException sin escribir', () async {
        await local.insertar(ubicacion());

        await expectLater(
          local.cambiarBaja(
            'ub-1',
            baseUpdatedAt: t0,
            updatedAt: t1,
            deletedAt: t1,
            conservadaId: 'ub-a',
          ),
          throwsA(isA<UbicacionInexistenteException>()),
        );
        expect(await guardada(), ubicacion());
      });

      test('si quedó de baja, tampoco toma el camino del doble toque', () async {
        await local.insertar(ubicacion(deletedAt: t0));
        await conservada(deletedAt: t0);

        await expectLater(
          local.cambiarBaja(
            'ub-1',
            baseUpdatedAt: t0,
            updatedAt: t1,
            deletedAt: t1,
            conservadaId: 'ub-a',
          ),
          throwsA(isA<ConservadaDeBajaException>()),
        );
      });
    });

    test('dado una reactivación, cuando se loguea, dice "reactivada" y no "baja"', () async {
      final salida = _SalidaEnMemoria();
      final repositorio = UbicacionRepositoryImpl(local, logger: AppLogger(output: salida));
      await local.insertar(ubicacion(deletedAt: t0));

      await repositorio.cambiarBaja('ub-1', baja: false, baseUpdatedAt: t0, ahora: t1);

      expect(
        salida.lineas.single,
        startsWith('[INFO][DB][UBICACION_REACTIVADA] ubicación reactivada'),
      );
    });

    test('dado una reactivación de una ubicación ya activa, no deja el evento de reactivación y '
        'devuelve escribio en false', () async {
      final salida = _SalidaEnMemoria();
      final repositorio = UbicacionRepositoryImpl(local, logger: AppLogger(output: salida));
      await local.insertar(ubicacion());

      final r = await repositorio.cambiarBaja('ub-1', baja: false, baseUpdatedAt: t0, ahora: t1);

      expect(r.map((c) => c.escribio), const Right<Failure, bool>(false));
      expect(
        salida.lineas.single,
        startsWith('[INFO][DB][UBICACION_YA_ACTIVA] la ubicación ya estaba activa'),
      );
    });
  });
}
