// El cobro en efectivo contra las tablas reales (HU-COB-001, #436): AppDatabase en memoria, mismo
// esquema y mismos CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

Cobranza cobroDe(String id, int monto, {String venta = 'v-1', DateTime? fecha}) => Cobranza(
  id: id,
  ventaId: venta,
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: fecha ?? t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;

  Future<void> sembrarVenta({String id = 'v-1', int monto = 150000}) async {
    final ventas = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await ventas.registrar(ventaDe(id, monto: monto, talonario: 'T-$id'), [
      itemDe('i-$id', id, cantidad: 1, precio: monto),
    ]);
    encolador.encolados.clear();
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = CobranzaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await sembrarCasa(db);
    await sembrarVenta();
  });
  tearDown(() => db.close());

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<CobranzaFila>> cobros() => db.select(db.cobranzas).get();
  Future<String?> colorDeLaCasa() async =>
      (await db.select(db.houseStatuses).getSingleOrNull())?.color;

  group('registrar', () {
    test('un cobro de UYU 500 del total UYU 1500 deja el saldo en 1000 y lo encola', () async {
      final r = await local.registrar(cobroDe('c-1', 50000));

      expect(r.yaEstaba, isFalse);
      expect(
        [r.venta.montoTotalCentavos, r.venta.cobradoCentavos, r.venta.saldoCentavos],
        [150000, 50000, 100000],
      );
      expect(r.ventaPagada, isFalse);
      final fila = (await cobros()).single;
      expect(
        [fila.ventaId, fila.monto, fila.medio, fila.numeroCuota],
        ['v-1', 50000, 'EFECTIVO', null],
      );
      expect(fila.fecha, t0);
      expect(cola(), ['cobranza:insert']);
      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 100000);
      // Con saldo y sin entrega registrada, la casa sigue pendiente.
      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test('un cobro que liquida el saldo deja la venta pagada, pero la casa sigue pendiente '
        'hasta que se registre la entrega', () async {
      await local.registrar(cobroDe('c-1', 100000));
      encolador.encolados.clear();

      final r = await local.registrar(cobroDe('c-2', 50000));

      expect(r.venta.saldoCentavos, 0);
      expect(r.ventaPagada, isTrue);
      // «Venta completa» pide saldo en cero y todo entregado; la entrega llega con #430 (decisión del
      // 28/10, «Pendiente hasta entregar»). El color no cambia, así que no se encola nada de la casa.
      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      expect(cola(), ['cobranza:insert']);
    });

    test('lo que sube no lleva nada de la persona: la venta es un id opaco', () async {
      await local.registrar(cobroDe('c-1', 50000));

      final payload = encolador.encolados.single.payload;
      expect(payload.keys.toSet(), {
        'id',
        'venta_id',
        'monto',
        'medio',
        'fecha',
        'numero_cuota',
        'created_at',
        'updated_at',
        'created_by',
        'deleted_at',
        'sync_version',
      });
      expect(payload['medio'], 'EFECTIVO');
      expect(payload['fecha'], '2026-10-23T13:45:10.123Z');
    });

    test('un cobro mayor al saldo se rechaza y no escribe nada', () async {
      await expectLater(
        local.registrar(cobroDe('c-1', 150001)),
        throwsA(isA<CobroMayorAlSaldoException>().having((e) => e.saldoCentavos, 'saldo', 150000)),
      );

      expect(await cobros(), isEmpty);
      expect(cola(), isEmpty);
      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test('dos cobros seguidos no suman más que la venta', () async {
      await local.registrar(cobroDe('c-1', 100000));

      await expectLater(
        local.registrar(cobroDe('c-2', 60000)),
        throwsA(isA<CobroMayorAlSaldoException>().having((e) => e.saldoCentavos, 'saldo', 50000)),
      );
      expect((await cobros()).length, 1);
    });

    test('dos toques a la vez con el mismo id: un solo cobro', () async {
      final resultados = await Future.wait([
        local.registrar(cobroDe('c-1', 50000)),
        local.registrar(cobroDe('c-1', 50000)),
      ]);

      expect((await cobros()).length, 1);
      expect(resultados.where((r) => r.yaEstaba).length, 1);
      expect(cola(), ['cobranza:insert']);
    });

    test('dos cobros distintos a la vez: los dos entran en orden y el saldo es la resta', () async {
      await Future.wait([
        local.registrar(cobroDe('c-1', 40000)),
        local.registrar(cobroDe('c-2', 60000)),
      ]);

      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 50000);
    });

    test('una venta que no está o está dada de baja no se cobra', () async {
      await expectLater(
        local.registrar(cobroDe('c-1', 100, venta: 'v-9')),
        throwsA(isA<CobroSinVentaException>()),
      );
      await db.customStatement('UPDATE venta SET deleted_at = 1 WHERE id = ?', ['v-1']);
      await expectLater(
        local.registrar(cobroDe('c-2', 100)),
        throwsA(isA<CobroSinVentaException>()),
      );
      expect(await cobros(), isEmpty);
    });

    test('la fecha no puede ser anterior a la venta, pero sí el mismo día', () async {
      await expectLater(
        local.registrar(cobroDe('c-1', 100, fecha: t0.subtract(const Duration(days: 1)))),
        throwsA(isA<CobroFechaAnteriorException>()),
      );
      await local.registrar(cobroDe('c-2', 100, fecha: t0.subtract(const Duration(hours: 2))));
      expect((await cobros()).length, 1);
    });

    test('si el encolado falla se revierte todo: ni cobro ni casa cambiada', () async {
      encolador.fallarCon = StateError('cola');

      await expectLater(local.registrar(cobroDe('c-1', 150000)), throwsA(isA<StateError>()));

      expect(await cobros(), isEmpty);
      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      encolador.fallarCon = null;
      await local.registrar(cobroDe('c-1', 150000));
      expect((await cobros()).length, 1);
    });

    test('un cobro dado de baja deja de contar en el saldo', () async {
      await local.registrar(cobroDe('c-1', 50000));
      await db.customStatement('UPDATE cobranza SET deleted_at = 1 WHERE id = ?', ['c-1']);

      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 150000);
    });
  });

  group('lectura', () {
    test('ventasConSaldoDe: solo las que deben, la más vieja primero, con qué se vendió', () async {
      await sembrarVenta(id: 'v-2', monto: 24000);
      await db.customStatement('UPDATE venta SET fecha = ? WHERE id = ?', [
        t0.add(const Duration(days: 2)).millisecondsSinceEpoch,
        'v-2',
      ]);
      await sembrarVenta(id: 'v-3', monto: 1000);
      await local.registrar(cobroDe('c-3', 1000, venta: 'v-3'));

      final ventas = await local.ventasConSaldoDe('per-1');

      expect([for (final v in ventas) v.ventaId], ['v-1', 'v-2']);
      expect(ventas.first.numeroTalonario, 'T-v-1');
      expect(ventas.first.descripcion, '1 producto');
    });

    test('saldosPorPersona suma lo que debe cada una y omite a quien no debe nada', () async {
      await sembrarVenta(id: 'v-2', monto: 24000);
      await local.registrar(cobroDe('c-1', 50000));

      expect(await local.saldosPorPersona(['per-1', 'per-9']), {'per-1': 124000});
      await local.registrar(cobroDe('c-2', 100000));
      await local.registrar(cobroDe('c-3', 24000, venta: 'v-2'));
      expect(await local.saldosPorPersona(['per-1']), isEmpty);
    });
  });
}
