// La baja de una ubicación con entrevistas agendadas (HU-UBI-005, #330) de punta a punta: del caso de uso
// al adaptador real de pendientes, al repositorio y a Drift. Decisión de Cristian (21/10): el aviso sale
// antes de confirmar, las entrevistas se cancelan en la misma transacción que la baja, no se borra nada
// y siguen canceladas al reactivar. Y la unión de duplicados (#208 P4): las ventas viajan con el vínculo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/pendientes_ubicacion_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart' hide t0;
import '../../../../../helpers/duplicados_falsos.dart' show EncoladorMarcarDuplicadoFalso;
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

/// Un [Recordatorios] cuyo plugin se cae: lanza al cancelar.
final class _RecordatoriosQueLanzan implements Recordatorios {
  final llamadas = <String>[];

  @override
  Future<bool> cancelar(String agendaId) async {
    llamadas.add(agendaId);
    throw StateError('el plugin se cayó');
  }

  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) async =>
      ResultadoRecordatorio.programado;

  @override
  Future<bool> puedeAvisar() async => true;
}

void main() {
  final t0 = DateTime.utc(2026, 10, 23, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 10, 24, 8, 0, 0, 500);
  final t2 = DateTime.utc(2026, 10, 25, 9);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late HouseStatusUpdaterEspia casas;
  late UbicacionLocalDataSourceDrift local;
  late RecordatoriosEnMemoria recordatorios;
  late DarDeBajaUbicacionUseCase darDeBaja;
  late ReactivarUbicacionUseCase reactivar;

  DarDeBajaUbicacionUseCase armarBaja(Recordatorios r) {
    final cuotas = CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    return DarDeBajaUbicacionUseCase(
      UbicacionRepositoryImpl(local, logger: loggerMudo()),
      PendientesUbicacionDrift(db, cuotas: cuotas, colportorId: 'col-1', logger: loggerMudo()),
      ahora: () => t1,
      recordatorios: r,
    );
  }

  UbicacionModel ubicacion(String id, {String tipo = 'CASA'}) => UbicacionModel(
    id: id,
    tipo: tipo == 'CASA' ? TipoUbicacion.casa : TipoUbicacion.edificio,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'ciu-1',
    zonaId: 'zona-9',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', syncVersion: 4),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    casas = HouseStatusUpdaterEspia();
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
      estadoDeLasCasas: casas,
    );
    recordatorios = RecordatoriosEnMemoria();
    darDeBaja = armarBaja(recordatorios);
    reactivar = ReactivarUbicacionUseCase(
      UbicacionRepositoryImpl(local, logger: loggerMudo()),
      ahora: () => t2,
    );
    await local.insertar(ubicacion('ub-1'));
    await sembrarEspacio(db);
    await sembrarVinculo(db);
  });
  tearDown(() => db.close());

  DarDeBajaUbicacionParams baja({bool confirma = false}) => DarDeBajaUbicacionParams(
    id: 'ub-1',
    baseUpdatedAt: t0,
    motivo: 'Ya no existe',
    confirmaPendientes: confirma,
  );

  Future<ResultadoBajaUbicacion> okBaja(
    DarDeBajaUbicacionParams p, [
    DarDeBajaUbicacionUseCase? c,
  ]) async => ((c ?? darDeBaja)(p)).then((r) => r.getOrElse(() => throw StateError('era un Left')));

  Future<AgendaFila> agenda(String id) =>
      (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle();

  Future<UbicacionModel> guardada() async => (await local.obtener('ub-1'))!;

  List<String> encoladosDeAgenda() => [
    for (final c in encolador.encolados)
      if (c.entidad == 'agenda') '${c.operacion.name}:${c.payload['id']}:${c.payload['estado']}',
  ];

  group('el aviso antes de confirmar', () {
    test('dado una entrevista agendada, cuando inicia la baja, devuelve el aviso literal y no '
        'escribe ni cancela nada', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      encolador.encolados.clear();

      final r = await okBaja(baja());

      expect(r, isA<BajaRequiereConfirmacion>());
      expect((r as BajaRequiereConfirmacion).pendientes.resumen, [
        'Esta casa tiene 1 entrevista agendada. Si la das de baja, se cancela.',
      ]);
      expect((await guardada()).auditoria.deletedAt, isNull);
      expect((await agenda('ag-1')).estado, EstadoAgenda.programada.codigo);
      expect(encolador.encolados, isEmpty);
      expect(recordatorios.llamadas, isEmpty);
    });
  });

  group('la baja confirmada', () {
    test(
      'dado una entrevista agendada, cuando confirma, la baja y la cancelación van juntas: '
      'la entrevista queda CANCELADA (no borrada), se encola y su recordatorio se cancela',
      () async {
        await insertarAgenda(db, agendaDe('ag-1'));
        encolador.encolados.clear();

        final r = await okBaja(baja(confirma: true));

        expect(r, isA<UbicacionDadaDeBaja>());
        expect((await guardada()).auditoria.deletedAt, t1);
        final a = await agenda('ag-1');
        expect(a.estado, EstadoAgenda.cancelada.codigo);
        expect(a.deletedAt, isNull, reason: 'no se borra nada: queda en el historial');
        expect(a.updatedAt, t1);
        expect(encoladosDeAgenda(), ['update:ag-1:CANCELADA']);
        expect(encolador.encolados.map((c) => c.entidad), ['agenda', 'ubicacion']);
        expect(recordatorios.llamadas, ['cancelar:ag-1']);
      },
    );

    test('dado varias entrevistas, una cumplida y una cobranza, cuando confirma, cancela solo las '
        'entrevistas agendadas', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      await insertarAgenda(db, agendaDe('ag-2'));
      await insertarAgenda(db, agendaDe('ag-3', estado: EstadoAgenda.cumplida));
      await insertarAgenda(db, agendaDe('ag-4', tipo: TipoAgenda.cobranza));

      await okBaja(baja(confirma: true));

      expect((await agenda('ag-1')).estado, 'CANCELADA');
      expect((await agenda('ag-2')).estado, 'CANCELADA');
      expect((await agenda('ag-3')).estado, 'CUMPLIDA');
      expect((await agenda('ag-4')).estado, 'PROGRAMADA');
      expect(recordatorios.llamadas, ['cancelar:ag-1', 'cancelar:ag-2']);
    });

    test('dado que el encolado falla, cuando confirma, no queda ni la baja ni la cancelación ni el '
        'motivo (misma transacción) y no se cancela ningún recordatorio', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      encolador.fallarCon = StateError('motor apagado');

      final r = await darDeBaja(baja(confirma: true));

      expect(r.isLeft(), isTrue);
      expect((await guardada()).auditoria.deletedAt, isNull);
      expect((await agenda('ag-1')).estado, EstadoAgenda.programada.codigo);
      expect(await db.select(db.auditLogLocal).get(), isEmpty);
      expect(recordatorios.llamadas, isEmpty);
    });

    test(
      'dado un doble toque, cuando el segundo llega con la baja hecha, no vuelve a escribir ni a '
      'cancelar nada',
      () async {
        await insertarAgenda(db, agendaDe('ag-1'));
        await okBaja(baja(confirma: true));
        encolador.encolados.clear();
        recordatorios.llamadas.clear();

        final r = await okBaja(baja(confirma: true));

        expect(r, isA<BajaSinCambios>());
        expect(encolador.encolados, isEmpty);
        expect(recordatorios.llamadas, isEmpty);
      },
    );

    test('dado que el plugin de recordatorios se cae, cuando confirma, la baja igual queda hecha '
        '(el aviso es del teléfono, no de la DB)', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      final cae = _RecordatoriosQueLanzan();

      final r = await okBaja(baja(confirma: true), armarBaja(cae));

      expect(r, isA<UbicacionDadaDeBaja>());
      expect((await agenda('ag-1')).estado, 'CANCELADA');
      expect(cae.llamadas, ['ag-1']);
    });

    test(
      'dado una casa sin entrevistas, cuando confirma, no toca la agenda ni los recordatorios',
      () async {
        encolador.encolados.clear();

        await okBaja(baja());

        expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
        expect(recordatorios.llamadas, isEmpty);
      },
    );

    test(
      'dado el motivo en el audit_log, cuando se lee, lleva el mismo instante que deleted_at: la '
      'Lista lo busca por esa igualdad (#332)',
      () async {
        await insertarAgenda(db, agendaDe('ag-1'));

        await okBaja(baja(confirma: true));

        final filas = await db.select(db.auditLogLocal).get();
        expect(filas.single.evento, EventoAuditoriaLocal.ubicacionBaja);
        expect(filas.single.creadoEn, (await guardada()).auditoria.deletedAt);
      },
    );
  });

  group('reactivar', () {
    test('dado una baja con una entrevista cancelada, cuando la reactiva, la entrevista sigue '
        'CANCELADA: reactivar no la resucita', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      await okBaja(baja(confirma: true));
      final base = (await guardada()).auditoria.updatedAt;
      encolador.encolados.clear();

      final r = await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: base));

      expect(r.isRight(), isTrue);
      expect((await guardada()).auditoria.deletedAt, isNull);
      expect((await agenda('ag-1')).estado, EstadoAgenda.cancelada.codigo);
      expect(encoladosDeAgenda(), isEmpty);
    });
  });

  group('unión de duplicados (#208 P4)', () {
    test('dado que B tiene una persona con una venta y una entrevista, cuando se une a A, todo '
        'pasa a A (el vínculo lleva la venta) y se recalcula el color de A en la misma '
        'transacción, sin cancelar la entrevista', () async {
      await local.insertar(ubicacion('ub-a'));
      await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
      await local.insertar(ubicacion('ub-b'));
      await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
      await sembrarVinculo(db, id: 'ep-b', espacioId: 'esp-b', personaId: 'per-b');
      final ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
      await ventas.registrar(ventaDe('v-b', vinculo: 'ep-b'), [itemDe('i-b', 'v-b')]);
      await insertarAgenda(db, agendaDe('ag-b', espacio: 'esp-b', vinculo: 'ep-b'));
      casas.llamadas.clear();

      final r = await local.unirDuplicada('ub-a', 'ub-b', ahora: t1);

      expect(r.escribio, isTrue);
      final vinculo = await (db.select(
        db.espacioPersonas,
      )..where((e) => e.id.equals('ep-b'))).getSingle();
      expect(vinculo.espacioId, 'esp-a', reason: 'la persona de B queda en el espacio de A');
      final venta = await (db.select(db.ventas)..where((v) => v.id.equals('v-b'))).getSingle();
      expect(venta.espacioPersonaId, 'ep-b', reason: 'la venta sigue con su vínculo: viaja con él');
      expect(venta.deletedAt, isNull);
      expect((await agenda('ag-b')).espacioId, 'esp-a');
      expect((await agenda('ag-b')).estado, EstadoAgenda.programada.codigo);
      expect(casas.llamadas.map((l) => l.ubicacionId), contains('ub-a'));
    });
  });
}
