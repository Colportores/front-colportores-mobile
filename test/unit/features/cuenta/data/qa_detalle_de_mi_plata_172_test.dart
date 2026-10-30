// QA de «Mi plata» (HU-CTA-003, #172), el cálculo contra tablas reales: los bordes que el implementador
// no cubrió. Cada lista tiene que sumar lo que dice su tarjeta de Mi Cuenta.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/detalle_de_mi_plata_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/devolucion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

final _dia20 = DateTime.utc(2026, 10, 20, 15);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CobranzaLocalDataSourceDrift cobranzas;
  late VentaLocalDataSourceDrift ventas;
  late DevolucionLocalDataSourceDrift devoluciones;
  late DetalleDeMiPlataLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    devoluciones = DevolucionLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    );
    local = DetalleDeMiPlataLocalDataSourceDrift(db, cobranzas: cobranzas);
    await sembrarEdificio(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(
            id: 'per-1',
            nombre: 'María',
            apellido: const Value('Fernández'),
            createdAt: _dia20,
            updatedAt: _dia20,
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> vender(String id, int monto) => ventas.registrar(
    ventaDe(id, monto: monto, fecha: _dia20, talonario: 'T-$id', colportor: 'col-1'),
    [itemDe('i-$id', id, productoId: 'p-$id', cantidad: 1, precio: monto)],
  );

  Future<void> cobrar(String id, String venta, int monto, MedioCobranza medio) =>
      cobranzas.registrar(
        Cobranza(
          id: id,
          ventaId: venta,
          montoCentavos: monto,
          medio: medio,
          fecha: _dia20,
          auditoria: Auditoria(createdAt: _dia20, updatedAt: _dia20, createdBy: 'col-1'),
        ),
      );

  Future<void> devolverAhora(String id, String venta) => devoluciones.registrar(
    PedidoDeDevolucion(
      id: id,
      ventaId: venta,
      colportorId: 'col-1',
      unidadesPorRenglon: {'i-$venta': 1},
      queHacer: QueHacerConLaDiferencia.devolverAhora,
      ahora: DateTime.utc(2026, 10, 22, 10),
    ),
  );

  group('En mano: la lista contra la cifra', () {
    test(
      'dado que se devuelve en el momento la plata de una venta cobrada con tarjeta y no hay '
      'efectivo, la lista suma lo que dice la cifra',
      () async {
        await vender('v-1', 150000);
        await cobrar('c-1', 'v-1', 150000, MedioCobranza.tarjeta);
        await devolverAhora('d-1', 'v-1');

        final d = await local.leer('col-1');

        expect(
          d.enMano.fold<int>(0, (s, m) => s + m.centavos),
          d.enManoCentavos,
          reason:
              'la cifra se corta en 0 pero la lista queda con una fila de − \$ 1.500: no suma lo que '
              'dice la tarjeta',
        );
      },
      skip:
          'QA #172: En mano nunca es negativo en la cifra, pero la lista conserva la fila que resta y no suma',
    );

    test('dado que hay efectivo de otra venta, la devolución de la venta con tarjeta resta de él y '
        'la lista suma', () async {
      await vender('v-1', 150000);
      await cobrar('c-1', 'v-1', 150000, MedioCobranza.tarjeta);
      await vender('v-2', 400000);
      await cobrar('c-2', 'v-2', 400000, MedioCobranza.efectivo);
      await devolverAhora('d-1', 'v-1');

      final d = await local.leer('col-1');

      expect(d.enManoCentavos, 250000);
      expect(d.enMano.fold<int>(0, (s, m) => s + m.centavos), d.enManoCentavos);
    });
  });

  group('Por cobrar y Debo a clientes: bordes', () {
    test(
      'una persona con nombre en blanco sale como «Cliente sin nombre», no con una fila vacía',
      () async {
        await db
            .into(db.personas)
            .insert(
              PersonasCompanion.insert(
                id: 'per-2',
                nombre: '   ',
                apellido: const Value(''),
                createdAt: _dia20,
                updatedAt: _dia20,
              ),
            );
        await db.customStatement(
          "UPDATE espacio_persona SET persona_id = 'per-2' WHERE id = 'ep-1'",
        );
        await vender('v-1', 100000);

        final d = await local.leer('col-1');

        expect(d.porCobrar.single.cliente.trim(), isNotEmpty);
      },
      skip:
          'QA #172: una persona con nombre y apellido en blanco sale con la fila vacía (" · desde 20/10")',
    );

    test('toString del detalle no vuelca los nombres de los clientes (PII)', () async {
      await vender('v-1', 100000);

      final d = await local.leer('col-1');

      expect(d.toString(), isNot(contains('María')));
      expect(d.porCobrar.single.toString(), isNot(contains('Fernández')));
    });
  });
}
