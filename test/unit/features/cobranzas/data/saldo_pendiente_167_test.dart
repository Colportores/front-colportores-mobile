// El saldo pendiente reactivo (HU-COB-005, #167) contra las tablas reales: AppDatabase en memoria,
// con la fórmula `saldo = monto de la venta − cobros válidos` por venta, por persona, por ubicación
// y en total, y con cada `Stream` avisando solo cuando el valor cambia.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Table, TableInfo, UpdateKind, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

/// Un cobro en efectivo de [monto] centavos de la venta [venta].
Cobranza cobroDe(String id, int monto, {String venta = 'v-1'}) => Cobranza(
  id: id,
  ventaId: venta,
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

/// Lo que un `Stream` fue emitiendo, en orden.
final class Escucha<T> {
  Escucha(Stream<T> origen) {
    _sub = origen.listen(valores.add, onError: errores.add);
  }

  late final StreamSubscription<T> _sub;
  final valores = <T>[];
  final errores = <Object>[];

  /// Espera hasta que se cumpla [condicion] (las lecturas de Drift terminan en otra vuelta).
  Future<void> hasta(bool Function() condicion) async {
    for (var i = 0; i < 400 && !condicion(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condicion(), isTrue, reason: 'no llegó lo esperado: $valores');
  }

  /// Deja pasar un rato para comprobar que **no** llega nada más.
  Future<void> quieto() => Future<void>.delayed(const Duration(milliseconds: 150));

  Future<void> cerrar() => _sub.cancel();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;
  late VentaLocalDataSourceDrift ventas;

  Future<void> vender(
    String id,
    int monto, {
    String vinculo = 'ep-1',
    String colportor = 'col-1',
  }) async {
    await ventas.registrar(
      ventaDe(id, monto: monto, talonario: 'T-$id', vinculo: vinculo, colportor: colportor),
      [itemDe('i-$id', id, cantidad: 1, precio: monto)],
    );
    encolador.encolados.clear();
  }

  /// Da de baja una fila avisando a Drift qué tabla cambió (como lo hace el pull al escribir): un
  /// `customStatement` suelto no despierta a los `Stream`.
  Future<void> darDeBaja(String tabla, String id, TableInfo<Table, Object?> info) =>
      db.customUpdate(
        'UPDATE $tabla SET deleted_at = 1 WHERE id = ?',
        variables: [Variable<String>(id)],
        updates: {info},
        updateKind: UpdateKind.update,
      );

  /// Un edificio `ub-1` con dos personas (`ep-1` de `per-1`, `ep-2` de `per-2`) y una casa `ub-2`
  /// con `per-3` (`ep-3`).
  setUp(() async {
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
    await sembrarUbicacion(db, id: 'ub-2');
    await sembrarEspacio(db, id: 'esp-3', ubicacionId: 'ub-2');
    await sembrarVinculo(db, id: 'ep-3', espacioId: 'esp-3', personaId: 'per-3');
  });
  tearDown(() => db.close());

  group('el escenario de la HU', () {
    test('venta de UYU 1500 con un cobro de UYU 500: al registrar otro de UYU 300 el saldo pasa de '
        '1000 a 700 sin recargar, en la venta, la persona, la ubicación y el total', () async {
      await vender('v-1', 150000);
      await local.registrar(cobroDe('c-1', 50000));
      final venta = Escucha(local.observarVentaConSaldo('v-1'));
      final persona = Escucha(local.observarSaldoDePersona('per-1'));
      final ubicacion = Escucha(local.observarSaldoDeUbicacion('ub-1'));
      final total = Escucha(local.observarSaldoTotal('col-1'));
      await persona.hasta(() => persona.valores.isNotEmpty);
      await venta.hasta(() => venta.valores.isNotEmpty);
      await ubicacion.hasta(() => ubicacion.valores.isNotEmpty);
      await total.hasta(() => total.valores.isNotEmpty);

      await local.registrar(cobroDe('c-2', 30000));

      await persona.hasta(() => persona.valores.length == 2);
      await venta.hasta(() => venta.valores.length == 2);
      await ubicacion.hasta(() => ubicacion.valores.length == 2);
      await total.hasta(() => total.valores.length == 2);
      expect(persona.valores, [100000, 70000]);
      expect(ubicacion.valores, [100000, 70000]);
      expect(total.valores, [100000, 70000]);
      expect([for (final v in venta.valores) v!.saldoCentavos], [100000, 70000]);
      expect(venta.valores.last!.cobradoCentavos, 80000);
      for (final e in [persona, ubicacion, total, venta]) {
        await e.cerrar();
      }
    });
  });

  group('los cortes', () {
    test('cada corte suma lo suyo: persona, ubicación y colportor', () async {
      await vender('v-1', 150000);
      await vender('v-2', 80000);
      await vender('v-3', 40000, vinculo: 'ep-2');
      await vender('v-4', 30000, vinculo: 'ep-3');
      await vender('v-5', 99000, vinculo: 'ep-3', colportor: 'col-2');
      await local.registrar(cobroDe('c-1', 50000));
      await local.registrar(cobroDe('c-4', 30000, venta: 'v-4'));

      expect(await local.observarSaldoDePersona('per-1').first, 180000);
      expect(await local.observarSaldoDePersona('per-2').first, 40000);
      expect(await local.observarSaldoDeUbicacion('ub-1').first, 220000);
      expect(await local.observarSaldoDeUbicacion('ub-2').first, 99000);
      // El total es de las ventas del colportor: las de `col-2` no entran.
      expect(await local.observarSaldoTotal('col-1').first, 220000);
      expect(await local.observarSaldoTotal('col-2').first, 99000);
    });

    test('sin ventas, o con todo pagado, el saldo es 0 (no hay error ni nulo)', () async {
      expect(await local.observarSaldoDePersona('per-1').first, 0);
      expect(await local.observarSaldoTotal('col-1').first, 0);
      await vender('v-1', 10000);
      await local.registrar(cobroDe('c-1', 10000));

      expect(await local.observarSaldoDePersona('per-1').first, 0);
      expect(await local.observarSaldoDeUbicacion('ub-1').first, 0);
      expect((await local.observarVentaConSaldo('v-1').first)!.tieneSaldo, isFalse);
    });

    test('un id que no existe es 0 y una venta que no existe es nula', () async {
      expect(await local.observarSaldoDePersona('nadie').first, 0);
      expect(await local.observarSaldoDeUbicacion('ninguna').first, 0);
      expect(await local.observarSaldoTotal('nadie').first, 0);
      expect(await local.observarVentaConSaldo('v-9').first, isNull);
    });

    test('coincide con lo que ya leía el cobro: saldosPorPersona y ventasConSaldoDe', () async {
      await vender('v-1', 150000);
      await vender('v-2', 80000);
      await local.registrar(cobroDe('c-1', 50000));
      await local.registrar(cobroDe('c-2', 80000, venta: 'v-2'));

      final enVentas = (await local.ventasConSaldoDe(
        'per-1',
      )).fold<int>(0, (a, v) => a + v.saldoCentavos);

      expect(await local.observarSaldoDePersona('per-1').first, enVentas);
      expect(await local.saldosPorPersona(['per-1', 'per-2']), {'per-1': 100000});
    });

    test('una venta cobrada de más no resta de lo que deben las demás', () async {
      await vender('v-1', 150000);
      await vender('v-2', 80000);
      // Un cobro de más que llegó por el pull (la regla de «no más que el saldo» es de quien escribe).
      await db
          .into(db.cobranzas)
          .insert(
            CobranzasCompanion.insert(
              id: 'c-x',
              ventaId: 'v-1',
              monto: 200000,
              medio: 'EFECTIVO',
              fecha: t0,
              createdAt: t0,
              updatedAt: t0,
            ),
          );

      expect(await local.observarSaldoDePersona('per-1').first, 80000);
      expect(await local.observarSaldoTotal('col-1').first, 80000);
      expect((await local.observarVentaConSaldo('v-1').first)!.saldoCentavos, 0);
    });

    test('con montos grandes y muchas ventas el total es exacto (centavos enteros)', () async {
      var esperado = 0;
      for (var i = 0; i < 150; i++) {
        final monto = 1234567891 + i;
        await vender('v-$i', monto);
        if (i.isEven) {
          await local.registrar(cobroDe('c-$i', 1000 + i, venta: 'v-$i'));
          esperado += monto - (1000 + i);
        } else {
          esperado += monto;
        }
      }

      expect(await local.observarSaldoTotal('col-1').first, esperado);
      expect(await local.observarSaldoDePersona('per-1').first, esperado);
      expect(await local.observarSaldoDeUbicacion('ub-1').first, esperado);
    });

    test('el vínculo dado de baja saca la venta de la persona y de la ubicación, no del total: '
        'nada se pierde de lo que le deben al colportor', () async {
      await vender('v-1', 150000);
      await vender('v-2', 80000, vinculo: 'ep-2');
      await darDeBaja('espacio_persona', 'ep-2', db.espacioPersonas);

      expect(await local.observarSaldoDePersona('per-2').first, 0);
      expect(await local.observarSaldoDeUbicacion('ub-1').first, 150000);
      expect(await local.observarSaldoTotal('col-1').first, 230000);
    });
  });

  group('cobros y ventas que no cuentan', () {
    test('un cobro dado de baja (o anulado) deja de contar y el saldo vuelve a subir', () async {
      await vender('v-1', 150000);
      await local.registrar(cobroDe('c-1', 50000));
      final persona = Escucha(local.observarSaldoDePersona('per-1'));
      final venta = Escucha(local.observarVentaConSaldo('v-1'));
      await persona.hasta(() => persona.valores.isNotEmpty && venta.valores.isNotEmpty);

      await darDeBaja('cobranza', 'c-1', db.cobranzas);

      await persona.hasta(() => persona.valores.length == 2);
      await venta.hasta(() => venta.valores.length == 2);
      expect(persona.valores, [100000, 150000]);
      expect(venta.valores.last!.cobradoCentavos, 0);
      await persona.cerrar();
      await venta.cerrar();
    });

    test('una venta dada de baja sale del saldo y su stream emite nulo', () async {
      await vender('v-1', 150000);
      await vender('v-2', 80000);
      final total = Escucha(local.observarSaldoTotal('col-1'));
      final venta = Escucha(local.observarVentaConSaldo('v-1'));
      await total.hasta(() => total.valores.isNotEmpty && venta.valores.isNotEmpty);

      await darDeBaja('venta', 'v-1', db.ventas);

      await total.hasta(() => total.valores.length == 2);
      await venta.hasta(() => venta.valores.length == 2);
      expect(total.valores, [230000, 80000]);
      expect(venta.valores.last, isNull);
      await total.cerrar();
      await venta.cerrar();
    });
  });

  group('cuándo avisa', () {
    test(
      'solo cuando el valor cambia: lo que pasa en otra persona no lo vuelve a emitir',
      () async {
        await vender('v-1', 150000);
        await vender('v-4', 30000, vinculo: 'ep-3');
        final persona = Escucha(local.observarSaldoDePersona('per-1'));
        final otra = Escucha(local.observarSaldoDePersona('per-3'));
        await persona.hasta(() => persona.valores.isNotEmpty && otra.valores.isNotEmpty);

        await local.registrar(cobroDe('c-4', 10000, venta: 'v-4'));

        await otra.hasta(() => otra.valores.length == 2);
        await persona.quieto();
        expect(persona.valores, [150000]);
        expect(otra.valores, [30000, 20000]);
        await persona.cerrar();
        await otra.cerrar();
      },
    );

    test('al reentrar, el stream nuevo arranca con el valor de ahora', () async {
      await vender('v-1', 150000);
      final primera = Escucha(local.observarSaldoDePersona('per-1'));
      await primera.hasta(() => primera.valores.isNotEmpty);
      await primera.cerrar();

      await local.registrar(cobroDe('c-1', 50000));

      final segunda = Escucha(local.observarSaldoDePersona('per-1'));
      await segunda.hasta(() => segunda.valores.isNotEmpty);
      expect(segunda.valores, [100000]);
      await segunda.cerrar();
    });

    test('un doble toque (el mismo cobro dos veces) descuenta una sola vez', () async {
      await vender('v-1', 150000);
      final persona = Escucha(local.observarSaldoDePersona('per-1'));
      await persona.hasta(() => persona.valores.isNotEmpty);

      await Future.wait([
        local.registrar(cobroDe('c-1', 50000)),
        local.registrar(cobroDe('c-1', 50000)),
      ]);

      await persona.hasta(() => persona.valores.last == 100000);
      await persona.quieto();
      expect(persona.valores, [150000, 100000]);
      await persona.cerrar();
    });

    test('dos cobros seguidos antes de que se asiente el primero: ninguno se pisa ni se pierde, y '
        'el saldo nunca sube ni baja de más', () async {
      await vender('v-1', 150000);
      final persona = Escucha(local.observarSaldoDePersona('per-1'));
      final total = Escucha(local.observarSaldoTotal('col-1'));
      await persona.hasta(() => persona.valores.isNotEmpty && total.valores.isNotEmpty);

      await Future.wait([
        local.registrar(cobroDe('c-1', 40000)),
        local.registrar(cobroDe('c-2', 60000)),
      ]);

      await persona.hasta(() => persona.valores.last == 50000);
      await total.hasta(() => total.valores.last == 50000);
      expect(persona.valores.first, 150000);
      // Baja de a escalones, sin pasar nunca por un valor de más.
      for (var i = 1; i < persona.valores.length; i++) {
        expect(persona.valores[i], lessThan(persona.valores[i - 1]));
      }
      expect(persona.valores.every((v) => v >= 50000), isTrue);
      await persona.cerrar();
      await total.cerrar();
    });

    test('si el cobro falla a mitad (el encolado revienta) el saldo no se mueve, y al reintentar '
        'baja', () async {
      await vender('v-1', 150000);
      final persona = Escucha(local.observarSaldoDePersona('per-1'));
      await persona.hasta(() => persona.valores.isNotEmpty);

      encolador.fallarCon = StateError('cola');
      await expectLater(local.registrar(cobroDe('c-1', 50000)), throwsA(isA<StateError>()));
      await persona.quieto();
      expect(persona.valores, [150000]);

      encolador.fallarCon = null;
      await local.registrar(cobroDe('c-1', 50000));
      await persona.hasta(() => persona.valores.length == 2);
      expect(persona.valores, [150000, 100000]);
      await persona.cerrar();
    });

    test('una venta nueva sube el saldo sin recargar', () async {
      await vender('v-1', 150000);
      final total = Escucha(local.observarSaldoTotal('col-1'));
      final ubicacion = Escucha(local.observarSaldoDeUbicacion('ub-1'));
      await total.hasta(() => total.valores.isNotEmpty && ubicacion.valores.isNotEmpty);

      await vender('v-2', 70000, vinculo: 'ep-2');

      await total.hasta(() => total.valores.length == 2);
      await ubicacion.hasta(() => ubicacion.valores.length == 2);
      expect(total.valores, [150000, 220000]);
      expect(ubicacion.valores, [150000, 220000]);
      await total.cerrar();
      await ubicacion.cerrar();
    });
  });
}
