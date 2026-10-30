// El resumen de Mi Cuenta (HU-CTA-001, #170) contra las tablas reales: AppDatabase en memoria, con
// «En mano» (efectivo cobrado menos lo reembolsado al devolver), «Por cobrar» (el saldo de las
// ventas vivas) y la diferencia contra la semana pasada, que sale de lo que ya había hace 7 días.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/resumen_de_cuenta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/resumen_de_cuenta_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/devolucion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

/// «Ahora» de los tests: el jueves 30/10 a las 12:00. Hace una semana fue el 23/10 a las 12:00.
final _ahora = DateTime.utc(2026, 10, 30, 12);
final _haceUnaSemana = DateTime.utc(2026, 10, 23, 12);

/// Un día de la semana pasada, y uno de esta semana.
final _antes = DateTime.utc(2026, 10, 12, 15);
final _despues = DateTime.utc(2026, 10, 28, 15);

/// Una venta de hace poco más de una semana y la devolución que se le hace dos días después (el
/// plazo de devolución es de 72 h desde la venta): la venta ya estaba hace 7 días, la devolución no.
final _ventaReciente = DateTime.utc(2026, 10, 22, 15);
final _devolucion = DateTime.utc(2026, 10, 24, 10);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift cobranzas;
  late VentaLocalDataSourceDrift ventas;
  late DevolucionLocalDataSourceDrift devoluciones;
  late ResumenDeCuentaLocalDataSourceDrift local;
  var reloj = _ahora;

  setUp(() async {
    reloj = _ahora;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    devoluciones = DevolucionLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    );
    local = ResumenDeCuentaLocalDataSourceDrift(db, cobranzas: cobranzas, ahora: () => reloj);
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  Future<void> vender(
    String id,
    int monto,
    DateTime fecha, {
    String colportor = 'col-1',
    String vinculo = 'ep-1',
  }) async {
    await ventas.registrar(
      ventaDe(
        id,
        monto: monto,
        fecha: fecha,
        talonario: 'T-$id',
        colportor: colportor,
        vinculo: vinculo,
      ),
      [itemDe('i-$id', id, productoId: 'p-$id', cantidad: 1, precio: monto)],
    );
  }

  Future<void> cobrar(
    String id,
    int monto,
    DateTime fecha, {
    String venta = 'v-1',
    MedioCobranza medio = MedioCobranza.efectivo,
  }) async {
    await cobranzas.registrar(
      Cobranza(
        id: id,
        ventaId: venta,
        montoCentavos: monto,
        medio: medio,
        fecha: fecha,
        auditoria: Auditoria(createdAt: fecha, updatedAt: fecha, createdBy: 'col-1'),
      ),
    );
  }

  Future<void> devolver(
    String id,
    DateTime fecha, {
    String venta = 'v-1',
    QueHacerConLaDiferencia queHacer = QueHacerConLaDiferencia.devolverAhora,
  }) async {
    await devoluciones.registrar(
      PedidoDeDevolucion(
        id: id,
        ventaId: venta,
        colportorId: 'col-1',
        unidadesPorRenglon: {'i-$venta': 1},
        queHacer: queHacer,
        ahora: fecha,
      ),
    );
  }

  Future<ResumenDeCuenta> leer({String colportor = 'col-1'}) => local.leer(colportor);

  group('la cuenta nueva (33A·04)', () {
    test(
      'dado que no vendió nada, cuando abre Mi Cuenta, las dos cifras están en cero y no hay con '
      'qué comparar',
      () async {
        final r = await leer();

        expect(r.enMano, const CifraDeCuenta(totalCentavos: 0));
        expect(r.porCobrar, const CifraDeCuenta(totalCentavos: 0));
        expect(r.enMano.tieneComparacion, isFalse);
        expect(r.porCobrar.tieneComparacion, isFalse);
      },
    );

    test('dado que su primera venta es de esta semana, cuando abre Mi Cuenta, ve el total pero la '
        'diferencia no se inventa: nada de la semana anterior', () async {
      await vender('v-1', 150000, _despues);
      await cobrar('c-1', 40000, _despues);

      final r = await leer();

      expect(r.enMano.totalCentavos, 40000);
      expect(r.porCobrar.totalCentavos, 110000);
      expect(r.enMano.variacionCentavos, isNull);
      expect(r.porCobrar.variacionCentavos, isNull);
    });
  });

  group('la diferencia contra la semana pasada', () {
    test('dado un cobro en efectivo de hace dos semanas y otro de esta semana, cuando abre Mi '
        'Cuenta, «En mano» sube lo de esta semana', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 50000, _antes);
      await cobrar('c-2', 30000, _despues);

      final r = await leer();

      expect(r.enMano, const CifraDeCuenta(totalCentavos: 80000, variacionCentavos: 30000));
    });

    test('dado que cobró deuda de esta semana y vendió más, «Por cobrar» se compara con lo que se '
        'debía hace 7 días, no con cero', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 50000, _antes);
      await vender('v-2', 80000, _despues);
      await cobrar('c-2', 30000, _despues, venta: 'v-2');
      await cobrar('c-3', 20000, _despues, venta: 'v-1');

      final r = await leer();

      // Hace 7 días debían 1.000 (v-1); ahora 800 (v-1: 800) + 500 (v-2).
      expect(r.porCobrar.totalCentavos, 80000 + 50000);
      expect(r.porCobrar.variacionCentavos, 130000 - 100000);
    });

    test('dado que cobró deuda vieja, «Por cobrar» baja y la diferencia es negativa', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 50000, _despues);

      final r = await leer();

      expect(r.porCobrar.totalCentavos, 100000);
      expect(r.porCobrar.variacionCentavos, -50000);
    });

    test(
      'dado que nada se movió en la semana, la diferencia es 0 (distinto de «sin datos»)',
      () async {
        await vender('v-1', 150000, _antes);
        await cobrar('c-1', 50000, _antes);

        final r = await leer();

        expect(r.enMano.variacionCentavos, 0);
        expect(r.porCobrar.variacionCentavos, 0);
        expect(r.enMano.tieneComparacion, isTrue);
      },
    );

    test('dado que el reloj avanza, la ventana de 7 días corre sola: el cobro que ayer era de esta '
        'semana hoy es de antes', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 30000, _despues);
      expect((await leer()).enMano.variacionCentavos, 30000);

      reloj = _despues.add(const Duration(days: 7, hours: 1));

      expect((await leer()).enMano.variacionCentavos, 0);
    });

    test('el límite es exacto: un cobro justo hace 7 días ya estaba la semana pasada', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 30000, _haceUnaSemana);

      final r = await leer();

      expect(r.enMano, const CifraDeCuenta(totalCentavos: 30000, variacionCentavos: 0));
    });
  });

  group('«En mano»', () {
    test('solo cuenta el efectivo: la tarjeta y la transferencia no pasan por la mano', () async {
      await vender('v-1', 300000, _despues);
      await cobrar('c-1', 50000, _despues);
      await cobrar('c-2', 70000, _despues, medio: MedioCobranza.tarjeta);
      await cobrar('c-3', 90000, _despues, medio: MedioCobranza.transferencia);

      final r = await leer();

      expect(r.enMano.totalCentavos, 50000);
      // Los tres cobros bajan lo que falta cobrar.
      expect(r.porCobrar.totalCentavos, 300000 - 50000 - 70000 - 90000);
    });

    test('un cobro dado de baja no cuenta: ni en mano ni en lo que falta cobrar', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 50000, _despues);
      await db.customUpdate(
        'UPDATE cobranza SET deleted_at = 1 WHERE id = ?',
        variables: [const Variable<String>('c-1')],
        updates: {db.cobranzas},
      );

      final r = await leer();

      expect(r.enMano.totalCentavos, 0);
      expect(r.porCobrar.totalCentavos, 150000);
    });

    test('dado que devolvió plata al cliente en el momento, se resta de «En mano» (decisión del '
        '30/10)', () async {
      await vender('v-1', 150000, _ventaReciente);
      await cobrar('c-1', 150000, _ventaReciente);
      await devolver('d-1', _devolucion);

      final r = await leer();

      // Devolvió el único libro de la venta: los $ 1.500 que le había cobrado en efectivo vuelven al
      // cliente.
      expect(r.enMano.totalCentavos, 0);
    });

    test('la devolución de esta semana no cambia cómo estaba «En mano» hace 7 días', () async {
      await vender('v-1', 150000, _ventaReciente);
      await cobrar('c-1', 150000, _ventaReciente);
      await devolver('d-1', _devolucion);

      final r = await leer();

      // Hace 7 días tenía $ 1.500 en mano; ahora 0: bajó $ 1.500.
      expect(r.enMano.variacionCentavos, -150000);
    });

    test('«Se lo devuelvo después» no saca plata de la mano: todavía no se devolvió', () async {
      await vender('v-1', 150000, _ventaReciente);
      await cobrar('c-1', 150000, _ventaReciente);
      await devolver('d-1', _devolucion, queHacer: QueHacerConLaDiferencia.devolverDespues);

      final r = await leer();

      expect(r.enMano.totalCentavos, 150000);
    });

    test('nunca queda negativa: un reembolso mayor al efectivo cobrado deja cero', () async {
      await vender('v-1', 150000, _ventaReciente);
      await cobrar('c-1', 50000, _ventaReciente, medio: MedioCobranza.tarjeta);
      await cobrar('c-2', 20000, _ventaReciente);
      await devolver('d-1', _devolucion);

      final r = await leer();

      expect(r.enMano.totalCentavos, 0);
    });

    test('una venta dada de baja no se lleva el efectivo ya cobrado: sigue en mano', () async {
      await vender('v-1', 150000, _antes);
      await cobrar('c-1', 50000, _antes);
      await db.customUpdate(
        'UPDATE venta SET deleted_at = 1 WHERE id = ?',
        variables: [const Variable<String>('v-1')],
        updates: {db.ventas},
      );

      final r = await leer();

      expect(r.enMano.totalCentavos, 50000);
      expect(r.porCobrar.totalCentavos, 0);
    });
  });

  group('«Por cobrar»', () {
    test('coincide con el saldo total que ya mira el resto de la app', () async {
      await vender('v-1', 150000, _antes);
      await vender('v-2', 80000, _despues, vinculo: 'ep-2');
      await cobrar('c-1', 50000, _antes);
      await devolver('d-1', _despues.add(const Duration(hours: 5)), venta: 'v-2');

      final r = await leer();

      expect(r.porCobrar.totalCentavos, await cobranzas.observarSaldoTotal('col-1').first);
    });

    test('una persona dada de baja con saldo sigue sumando (decisión del 23/10, 32D·03)', () async {
      await vender('v-1', 150000, _antes);
      await db.customUpdate(
        'UPDATE espacio_persona SET deleted_at = 1 WHERE id = ?',
        variables: [const Variable<String>('ep-1')],
        updates: {db.espacioPersonas},
      );

      final r = await leer();

      expect(r.porCobrar.totalCentavos, 150000);
    });

    test('las ventas de otro colportor no entran', () async {
      await vender('v-1', 150000, _antes);
      await vender('v-2', 99000, _antes, colportor: 'col-2');

      expect((await leer()).porCobrar.totalCentavos, 150000);
      expect((await leer(colportor: 'col-2')).porCobrar.totalCentavos, 99000);
    });
  });

  group('al día solo', () {
    test('al registrar un cobro el resumen se actualiza sin recargar, y no repite lo que no '
        'cambió', () async {
      await vender('v-1', 150000, _antes);
      final vistos = <ResumenDeCuenta>[];
      final errores = <Object>[];
      final sub = local.observar('col-1').listen(vistos.add, onError: errores.add);
      Future<void> hasta(bool Function() condicion) async {
        for (var i = 0; i < 400 && !condicion(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(condicion(), isTrue, reason: 'no llegó lo esperado: $vistos');
      }

      await hasta(() => vistos.length == 1);
      expect(vistos.single.porCobrar.totalCentavos, 150000);

      await cobrar('c-1', 50000, _despues);

      await hasta(() => vistos.length == 2);
      expect(vistos.last.enMano.totalCentavos, 50000);
      expect(vistos.last.porCobrar.totalCentavos, 100000);
      // Un cambio que no mueve ninguna cifra (un cobro de otro colportor) no emite de nuevo.
      await vender('v-9', 10000, _despues, colportor: 'col-2');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(vistos, hasLength(2));
      expect(errores, isEmpty);
      await sub.cancel();
    });
  });

  group('si la base no se puede leer', () {
    test(
      'el Stream falla con FailureCuentaNoDisponible y no emite ceros; el log no lleva datos',
      () async {
        await vender('v-1', 150000, _antes);
        final repo = ResumenDeCuentaRepositoryImpl(local);
        await db.customStatement('DROP TABLE cobranza');

        await expectLater(repo.observar('col-1'), emitsError(isA<FailureCuentaNoDisponible>()));
      },
    );

    test('sin DB abierta también falla con FailureCuentaNoDisponible', () async {
      await expectLater(
        const ResumenDeCuentaSinBase().observar('col-1'),
        emitsError(isA<FailureCuentaNoDisponible>()),
      );
    });
  });
}
