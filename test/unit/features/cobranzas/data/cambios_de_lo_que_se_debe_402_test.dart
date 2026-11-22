// El aviso con el que la hoja de la casa vuelve a leer lo que debe cada persona (HU-COB-005, #402),
// contra las tablas reales: AppDatabase en memoria. El escenario de la HU de punta a punta: venta de
// UYU 1500 con un cobro de UYU 500; al registrar otro de UYU 300 el saldo pasa a UYU 700 sin recargar.
import 'dart:async';

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

Cobranza _cobro(String id, int monto, {String venta = 'v-1'}) => Cobranza(
  id: id,
  ventaId: venta,
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;
  late VentaLocalDataSourceDrift ventas;
  late StreamSubscription<void> aviso;
  var avisos = 0;

  /// Deja pasar el tiempo que Drift tarda en avisar de un cambio.
  Future<void> esperar() => Future<void>.delayed(const Duration(milliseconds: 60));

  setUp(() async {
    avisos = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estadoDeLasCasas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = CobranzaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: estadoDeLasCasas,
    );
    ventas = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: estadoDeLasCasas,
    );
    await sembrarEdificio(db);
  });
  tearDown(() async {
    await aviso.cancel();
    await db.close();
  });

  Future<void> vender(String id, int monto) async {
    await ventas.registrar(ventaDe(id, monto: monto, talonario: 'T-$id', vinculo: 'ep-1'), [
      itemDe('i-$id', id, cantidad: 1, precio: monto),
    ]);
  }

  void escuchar() {
    aviso = local.alCambiarLoQueSeDebe().listen((_) => avisos++);
  }

  test('avisa al suscribirse, para que la hoja lea lo de ahora', () async {
    escuchar();
    await esperar();

    expect(avisos, 1);
  });

  test('avisa cuando se registra una venta y cuando se registra un cobro', () async {
    escuchar();
    await esperar();
    final alAbrir = avisos;

    await vender('v-1', 150000);
    await esperar();
    final trasLaVenta = avisos;
    await local.registrar(_cobro('c-1', 50000));
    await esperar();

    expect(trasLaVenta, greaterThan(alAbrir));
    expect(avisos, greaterThan(trasLaVenta));
  });

  test(
    'el escenario de la HU: 1500 con un cobro de 500, otro de 300 deja a la persona en 700',
    () async {
      await vender('v-1', 150000);
      await local.registrar(_cobro('c-1', 50000));
      final lecturas = <Map<String, int>>[];
      aviso = local.alCambiarLoQueSeDebe().listen((_) async {
        lecturas.add(await local.saldosPorPersona(['per-1']));
      });
      await esperar();
      expect(lecturas.last, {'per-1': 100000});

      await local.registrar(_cobro('c-2', 30000));
      await esperar();

      expect(lecturas.last, {'per-1': 70000});
    },
  );

  test('dos cobros seguidos: la última lectura ya ve los dos', () async {
    await vender('v-1', 150000);
    final lecturas = <Map<String, int>>[];
    aviso = local.alCambiarLoQueSeDebe().listen((_) async {
      lecturas.add(await local.saldosPorPersona(['per-1']));
    });
    await esperar();

    await local.registrar(_cobro('c-1', 50000));
    await local.registrar(_cobro('c-2', 30000));
    await esperar();

    expect(lecturas.last, {'per-1': 70000});
  });

  test('pagada la venta entera, la persona deja de aparecer con saldo', () async {
    await vender('v-1', 150000);
    final lecturas = <Map<String, int>>[];
    aviso = local.alCambiarLoQueSeDebe().listen((_) async {
      lecturas.add(await local.saldosPorPersona(['per-1']));
    });
    await esperar();
    expect(lecturas.last, {'per-1': 150000});

    await local.registrar(_cobro('c-1', 150000));
    await esperar();

    expect(lecturas.last, isEmpty);
  });

  test('al cancelar la suscripción no llega nada más', () async {
    escuchar();
    await esperar();
    await aviso.cancel();
    final antes = avisos;

    await vender('v-1', 150000);
    await esperar();

    expect(avisos, antes);
  });
}
