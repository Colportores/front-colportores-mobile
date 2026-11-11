// QA de #330 (PR #646, HU-UBI-005, vista 09): lo que la baja con entrevistas agendadas hace con la base
// REAL, incluido el color de la casa (`house_status`, R-UB08) que el test del PR reemplaza por un espía.
// Complementa a `baja_entrevistas_330_drift_test.dart` y `pendientes_ubicacion_drift_test.dart`.
//
// Hallazgo de la ronda 1 (con `skip`, el implementador lo saca al arreglarlo): al cancelar las entrevistas
// con la baja nadie recalcula `house_status`; la casa se reactiva «Entrevista agendada» (amarillo) sin
// ninguna entrevista agendada.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/data/services/pendientes_ubicacion_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
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

void main() {
  final t0 = DateTime.utc(2026, 10, 23, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 10, 24, 8);
  final t2 = DateTime.utc(2026, 10, 25, 9);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late HouseStatusUpdaterDrift casas;
  late UbicacionLocalDataSourceDrift local;
  late RecordatoriosEnMemoria recordatorios;
  late DarDeBajaUbicacionUseCase darDeBaja;
  late ReactivarUbicacionUseCase reactivar;

  UbicacionModel ubicacion(String id) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
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
    // El actualizador REAL de `house_status` (el mismo que usa la app).
    casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
      estadoDeLasCasas: casas,
    );
    recordatorios = RecordatoriosEnMemoria();
    final repo = UbicacionRepositoryImpl(local, logger: loggerMudo());
    darDeBaja = DarDeBajaUbicacionUseCase(
      repo,
      PendientesUbicacionDrift(
        db,
        cuotas: CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas),
        colportorId: 'col-1',
        logger: loggerMudo(),
      ),
      ahora: () => t1,
      recordatorios: recordatorios,
    );
    reactivar = ReactivarUbicacionUseCase(repo, ahora: () => t2);
    await local.insertar(ubicacion('ub-1'));
    await sembrarEspacio(db);
    await sembrarVinculo(db);
  });
  tearDown(() => db.close());

  Future<String?> colorGuardado() async {
    final filas = await (db.select(
      db.houseStatuses,
    )..where((h) => h.ubicacionId.equals('ub-1'))).get();
    return filas.where((h) => h.deletedAt == null).map((h) => h.color).firstOrNull;
  }

  Future<String> estadoDeAgenda(String id) async =>
      (await (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle()).estado;

  DarDeBajaUbicacionParams pedido({bool confirma = true}) => DarDeBajaUbicacionParams(
    id: 'ub-1',
    baseUpdatedAt: t0,
    motivo: 'Ya no existe',
    confirmaPendientes: confirma,
  );

  Future<ResultadoBajaUbicacion> bajar({bool confirma = true}) async => (await darDeBaja(
    pedido(confirma: confirma),
  )).getOrElse(() => throw StateError('era un Left'));

  Future<void> agendarYPintar(String id) async {
    await insertarAgenda(db, agendaDe(id));
    await casas.recalcular('ub-1', ahora: t0, colportorId: 'col-1');
  }

  group('QA #330 · el color de la casa (R-UB08) tras cancelar las entrevistas con la baja', () {
    test('dado una casa con una entrevista agendada, entonces el color de partida es entrevista '
        'programada (precondición del resto)', () async {
      await agendarYPintar('ag-1');

      expect(await colorGuardado(), ColorHouseStatus.entrevistaProgramada.codigo);
    });

    test(
      'dado una casa con una entrevista agendada que se da de baja y se reactiva, cuando '
      'vuelve a la lista, entonces NO queda «Entrevista agendada» (la entrevista quedó cancelada)',
      () async {
        await agendarYPintar('ag-1');
        await bajar();
        final base = (await local.obtener('ub-1'))!.auditoria.updatedAt;

        final r = await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: base));

        expect(r.isRight(), isTrue);
        expect(await estadoDeAgenda('ag-1'), EstadoAgenda.cancelada.codigo);
        expect(
          await colorGuardado(),
          isNot(ColorHouseStatus.entrevistaProgramada.codigo),
          reason:
              'la casa reactivada se pinta amarilla «Entrevista agendada» sin ninguna entrevista',
        );
      },
    );

    test('dado la misma baja, cuando se recalcula el color a mano tras reactivar, entonces la casa '
        'vuelve a «Sin visita» (confirma que el dato correcto sale de recalcular)', () async {
      await agendarYPintar('ag-1');
      await bajar();
      final base = (await local.obtener('ub-1'))!.auditoria.updatedAt;
      await reactivar(ReactivarUbicacionParams(id: 'ub-1', baseUpdatedAt: base));

      await casas.recalcular('ub-1', ahora: t2, colportorId: 'col-1');

      expect(await colorGuardado(), isNull);
    });
  });

  group('QA #330 · casos límite de la baja con entrevistas sobre la base real', () {
    test('dado un edificio con entrevistas en dos deptos, cuando se da de baja, entonces las dos '
        'quedan canceladas, cada una se encola una vez y sus recordatorios se cancelan', () async {
      await db.delete(db.espacioPersonas).go();
      await db.delete(db.espacios).go();
      await sembrarEspacio(db, id: 'esp-1', numeroDepto: '1A');
      await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
      await sembrarVinculo(db, id: 'ep-1', espacioId: 'esp-1', personaId: 'per-1');
      await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
      await insertarAgenda(db, agendaDe('ag-1'));
      await insertarAgenda(db, agendaDe('ag-2', espacio: 'esp-2', vinculo: 'ep-2'));
      encolador.encolados.clear();

      final r = await bajar();

      expect(r, isA<UbicacionDadaDeBaja>());
      final estados = [
        for (final a in await db.select(db.agendas).get()) '${a.id}:${a.estado}:${a.deletedAt}',
      ]..sort();
      expect(estados, ['ag-1:CANCELADA:null', 'ag-2:CANCELADA:null']);
      expect(
        [
          for (final c in encolador.encolados)
            if (c.entidad == 'agenda') c.payload['id'],
        ]..sort(),
        ['ag-1', 'ag-2'],
      );
      expect(recordatorios.llamadas.toList()..sort(), ['cancelar:ag-1', 'cancelar:ag-2']);
    });

    test('dado una baja ya hecha, cuando llega otro pedido de baja, entonces no hay nada que '
        'confirmar ni que cancelar de nuevo', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      await bajar();
      encolador.encolados.clear();
      recordatorios.llamadas.clear();

      final r = await bajar(confirma: false);

      expect(r, isA<BajaSinCambios>());
      expect(encolador.encolados, isEmpty);
      expect(recordatorios.llamadas, isEmpty);
    });

    test('dado una entrevista agendada y una venta con saldo, cuando se pide la baja, entonces '
        'gana el bloqueo y no se cancela ninguna entrevista', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      await VentaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: casas,
      ).registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1', cantidad: 1, precio: 150000)]);

      final r = await bajar();

      expect(r, isA<BajaBloqueada>());
      expect(await estadoDeAgenda('ag-1'), EstadoAgenda.programada.codigo);
      expect(recordatorios.llamadas, isEmpty);
      expect((await local.obtener('ub-1'))!.auditoria.deletedAt, isNull);
    });

    test('dado un fallo al leer lo pendiente, cuando se pide la baja, entonces no se cancela nada '
        'y la ubicación sigue activa (la falla es de revisión, nunca «no hay nada»)', () async {
      await insertarAgenda(db, agendaDe('ag-1'));
      await db.customStatement('DROP TABLE visita');

      final r = await darDeBaja(pedido());

      expect(r.isLeft(), isTrue);
      expect(await estadoDeAgenda('ag-1'), EstadoAgenda.programada.codigo);
      expect((await local.obtener('ub-1'))!.auditoria.deletedAt, isNull);
      expect(recordatorios.llamadas, isEmpty);
    });
  });

  group('QA #330 · privacidad (R-UB01, §7.5)', () {
    test('dado una cobranza y un resumen de pendientes con ids, cuando se imprimen, entonces el '
        'toString no lleva ni el id de la venta ni el de la casa', () {
      const cobranza = CobranzaPendiente(
        montoCentavos: 123456,
        numeroCuota: 2,
        ventaId: 'venta-secreta-1',
        espacioId: 'espacio-secreto-1',
        espacioPersonaId: 'vinculo-secreto-1',
      );
      const resumen = PendientesUbicacion(
        cobranzaPendiente: cobranza,
        tieneVentas: true,
        entrevistasAgendadas: ['agenda-secreta-1'],
      );

      final texto = '$cobranza $resumen';

      expect(texto, isNot(contains('secret')));
      expect(texto, isNot(contains('123456')));
    });
  });
}
