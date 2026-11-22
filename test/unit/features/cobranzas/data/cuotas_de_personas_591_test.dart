// La cuota que toca de cada persona en la hoja de la casa (HU-COB-005, #591), contra las tablas reales:
// AppDatabase en memoria. Cada cuota es una cita de cobranza (decisión «Plan cuotas»); el adaptador
// elige, entre las cuotas sin cubrir de todas las ventas de la persona, la vencida más vieja o, si no
// hay vencidas, la abierta más próxima (decisión P2 de #402).
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/pedido_de_plan.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CuotasLocalDataSourceDrift cuotas;
  late CobranzaLocalDataSourceDrift cobros;
  late VentaLocalDataSourceDrift ventas;
  late CuotasDePersonasLocal adaptador;

  // Los planes se arman el 10/10 y se cobra después.
  final armado = DateTime.utc(2026, 10, 10, 14);

  Cobranza cobro(String id, int monto, {String venta = 'v-1', DateTime? creado}) {
    final cuando = creado ?? DateTime.utc(2026, 10, 11, 12);
    return Cobranza(
      id: id,
      ventaId: venta,
      montoCentavos: monto,
      medio: MedioCobranza.efectivo,
      fecha: cuando,
      auditoria: Auditoria(createdAt: cuando, updatedAt: cuando, createdBy: 'col-1'),
    );
  }

  Future<void> vender(String id, {int monto = 250000, String vinculo = 'ep-1'}) async {
    await ventas.registrar(
      ventaDe(
        id,
        monto: monto,
        talonario: 'T-$id',
        vinculo: vinculo,
        fecha: DateTime.utc(2026, 10, 9, 12),
      ),
      [itemDe('i-$id', id, cantidad: 1, precio: monto)],
    );
  }

  /// Un plan de la venta [venta] con una cuota por cada [dias] (día del mes de octubre, 10:00). Las
  /// cuotas valen [monto] salvo la última, que es lo que falta del saldo (no se escribe a mano,
  /// decisión del 03/11, #608).
  Future<void> plan(String venta, List<int> dias, {int monto = 50000}) async {
    final saldo = (await cuotas.leerPlan(venta))!.venta.saldoCentavos;
    await cuotas.crearPlan(
      NuevoPlanDeCuotas(
        ventaId: venta,
        colportorId: 'col-1',
        ahora: armado,
        cuotas: [
          for (var i = 0; i < dias.length; i++)
            NuevaCuota(
              agendaId: '$venta-q${i + 1}',
              fecha: DateTime(2026, 10, dias[i], 10),
              montoCentavos: i == dias.length - 1 ? saldo - monto * i : monto,
            ),
        ],
      ),
    );
  }

  Future<Map<String, DateTime>> lee([List<String> ids = const ['per-1']]) =>
      adaptador.proximaCuotaDe(ids);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cuotas = CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobros = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    adaptador = CuotasDePersonasLocal(cobros);
    await sembrarEdificio(db);
    // La misma persona (per-1) también vive en el depto 2B.
    await sembrarVinculo(db, id: 'ep-3', espacioId: 'esp-2', personaId: 'per-1');
  });
  tearDown(() => db.close());

  group('dada una venta con plan de cuotas', () {
    test('cuando todas las cuotas están por venir, es la más próxima', () async {
      await vender('v-1');
      await plan('v-1', [26, 28, 30]);

      expect(await lee(), {'per-1': DateTime(2026, 10, 26, 10)});
    });

    test('cuando una cuota ya se cobró entera, pasa a la siguiente', () async {
      await vender('v-1');
      await plan('v-1', [26, 28, 30]);

      await cobros.registrar(cobro('c-1', 50000));

      expect(await lee(), {'per-1': DateTime(2026, 10, 28, 10)});
    });

    test('cuando una cuota se pagó en parte, sigue siendo la que toca', () async {
      await vender('v-1');
      await plan('v-1', [26, 28]);

      await cobros.registrar(cobro('c-1', 20000));

      expect(await lee(), {'per-1': DateTime(2026, 10, 26, 10)});
    });

    test('cuando hay cuotas vencidas, es la vencida más vieja, no la más próxima', () async {
      await vender('v-1');
      await plan('v-1', [12, 14, 26]);

      // Sin importar «hoy»: la más temprana de las abiertas es la vencida más vieja si hay vencidas.
      expect(await lee(), {'per-1': DateTime(2026, 10, 12, 10)});
    });

    test('cuando se cobraron todas las cuotas, la persona no tiene cuota', () async {
      await vender('v-1', monto: 100000);
      await plan('v-1', [26, 28]);

      await cobros.registrar(cobro('c-1', 100000));

      expect(await lee(), isEmpty);
    });

    test('cuando se cancela la cita de una cuota, deja de contar', () async {
      await vender('v-1');
      await plan('v-1', [26, 28]);

      await (db.update(db.agendas)..where((a) => a.id.equals('v-1-q1'))).write(
        const AgendasCompanion(estado: Value('CANCELADA')),
      );

      expect(await lee(), {'per-1': DateTime(2026, 10, 28, 10)});
    });
  });

  group('varias ventas y varios vínculos', () {
    test('la vencida de una venta gana a la próxima de otra (P2 de #402)', () async {
      await vender('v-1');
      await vender('v-2', monto: 120000);
      await plan('v-1', [26, 27]);
      await plan('v-2', [12, 13], monto: 60000);

      expect(await lee(), {'per-1': DateTime(2026, 10, 12, 10)});
    });

    test('sin vencidas, gana la abierta más próxima de todas las ventas', () async {
      await vender('v-1');
      await vender('v-2', monto: 120000);
      await plan('v-1', [30, 31]);
      await plan('v-2', [26, 27], monto: 60000);

      expect(await lee(), {'per-1': DateTime(2026, 10, 26, 10)});
    });

    test('suma las ventas de todos los vínculos de la persona (otro depto)', () async {
      await vender('v-1');
      await vender('v-3', monto: 90000, vinculo: 'ep-3');
      await plan('v-1', [30, 31]);
      await plan('v-3', [27, 28], monto: 45000);

      expect(await lee(), {'per-1': DateTime(2026, 10, 27, 10)});
    });

    test('una venta sin plan no tapa la cuota de la otra', () async {
      await vender('v-1');
      await vender('v-2', monto: 120000);
      await plan('v-2', [26, 27], monto: 60000);

      expect(await lee(), {'per-1': DateTime(2026, 10, 26, 10)});
    });

    test('una venta dada de baja no aporta cuotas', () async {
      await vender('v-1');
      await vender('v-2', monto: 120000);
      await plan('v-1', [30, 31]);
      await plan('v-2', [12, 13], monto: 60000);

      await (db.update(db.ventas)..where((v) => v.id.equals('v-2'))).write(
        VentasCompanion(deletedAt: Value(DateTime.utc(2026, 10, 15))),
      );

      expect(await lee(), {'per-1': DateTime(2026, 10, 30, 10)});
    });

    test('un vínculo dado de baja no aporta cuotas', () async {
      await vender('v-1');
      await vender('v-3', monto: 90000, vinculo: 'ep-3');
      await plan('v-1', [30, 31]);
      await plan('v-3', [12, 13], monto: 45000);

      await (db.update(db.espacioPersonas)..where((e) => e.id.equals('ep-3'))).write(
        EspacioPersonasCompanion(deletedAt: Value(DateTime.utc(2026, 10, 15))),
      );

      expect(await lee(), {'per-1': DateTime(2026, 10, 30, 10)});
    });

    test('cada persona tiene la suya y quien no tiene plan no figura', () async {
      await vender('v-1');
      await vender('v-2', monto: 120000, vinculo: 'ep-2');
      await plan('v-1', [26, 27]);

      expect(await lee(['per-1', 'per-2', 'per-9']), {'per-1': DateTime(2026, 10, 26, 10)});
    });
  });

  group('casos sin cuota', () {
    test('persona sin ventas: no figura', () async {
      expect(await lee(), isEmpty);
    });

    test('lista de personas vacía: nada', () async {
      expect(await lee(const []), isEmpty);
    });

    test('venta sin plan (la fila dice solo «Debe \$ X»): no figura', () async {
      await vender('v-1');

      expect(await lee(), isEmpty);
    });

    test('una cita de cobranza sin monto (no es una cuota) no cuenta', () async {
      await vender('v-1');
      await db
          .into(db.agendas)
          .insert(
            AgendasCompanion.insert(
              id: 'a-libre',
              espacioId: 'esp-1',
              espacioPersonaId: const Value('ep-1'),
              tipo: 'COBRANZA',
              fechaProgramada: DateTime.utc(2026, 10, 26, 13),
              colportorId: 'col-1',
              ventaId: const Value('v-1'),
              createdAt: armado,
              updatedAt: armado,
            ),
          );

      expect(await lee(), isEmpty);
    });
  });

  group('el aviso de cambios (alCambiarLoQueSeDebe)', () {
    late StreamSubscription<void> aviso;
    var avisos = 0;
    Future<void> esperar() => Future<void>.delayed(const Duration(milliseconds: 60));

    setUp(() => avisos = 0);
    tearDown(() => aviso.cancel());

    test('cuando cambia la fecha de una cuota, la hoja se entera y lee la nueva', () async {
      await vender('v-1');
      await plan('v-1', [26, 28]);
      final lecturas = <Map<String, DateTime>>[];
      aviso = cobros.alCambiarLoQueSeDebe().listen((_) async {
        avisos++;
        lecturas.add(await lee());
      });
      await esperar();
      final alAbrir = avisos;
      expect(lecturas.last, {'per-1': DateTime(2026, 10, 26, 10)});

      // Solo cambia la tabla `agenda`: ni la venta ni los cobros se tocan.
      await (db.update(db.agendas)..where((a) => a.id.equals('v-1-q1'))).write(
        AgendasCompanion(fechaProgramada: Value(DateTime(2026, 10, 27, 10).toUtc())),
      );
      await esperar();

      expect(avisos, greaterThan(alAbrir));
      expect(lecturas.last, {'per-1': DateTime(2026, 10, 27, 10)});
    });

    test('cuando se arma un plan, avisa', () async {
      await vender('v-1');
      aviso = cobros.alCambiarLoQueSeDebe().listen((_) => avisos++);
      await esperar();
      final alAbrir = avisos;

      await plan('v-1', [26, 28]);
      await esperar();

      expect(avisos, greaterThan(alAbrir));
    });
  });
}
