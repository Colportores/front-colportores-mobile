// El detalle de «Mi plata» (HU-CTA-003, #172 y #431) contra las tablas reales: AppDatabase en memoria.
// Cada lista tiene que sumar lo que dice su tarjeta de Mi Cuenta (HU-CTA-001): Depositado (los
// depósitos que validó el coordinador, y aparte los que esperan), En mano (los cobros en efectivo) y
// Por cobrar (el saldo de cada venta viva, por cliente).
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/detalle_de_mi_plata_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/resumen_de_cuenta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/detalle_de_mi_plata_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/detalle_de_mi_plata.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/totales_de_depositos.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/devolucion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

final _ahora = DateTime.utc(2026, 10, 30, 12);

int _ms(DateTime f) => f.toUtc().millisecondsSinceEpoch;

/// Ventas recientes (la devolución tiene un plazo de 72 h desde la venta).
final _dia20 = DateTime.utc(2026, 10, 20, 15);
final _dia21 = DateTime.utc(2026, 10, 21, 15);
final _dia23 = DateTime.utc(2026, 10, 23, 15);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift cobranzas;
  late VentaLocalDataSourceDrift ventas;
  late DevolucionLocalDataSourceDrift devoluciones;
  late DetalleDeMiPlataLocalDataSourceDrift local;

  Future<void> sembrarPersona(String id, String nombre, String apellido) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: nombre,
          apellido: Value(apellido),
          createdAt: _dia20,
          updatedAt: _dia20,
        ),
      );

  setUp(() async {
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
    local = DetalleDeMiPlataLocalDataSourceDrift(db, cobranzas: cobranzas);
    await sembrarEdificio(db);
    await sembrarPersona('per-1', 'María', 'Fernández');
    await sembrarPersona('per-2', 'Pedro', 'Gómez');
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

  Future<void> devolver(String id, DateTime fecha, {String venta = 'v-1'}) async {
    await devoluciones.registrar(
      PedidoDeDevolucion(
        id: id,
        ventaId: venta,
        colportorId: 'col-1',
        unidadesPorRenglon: {'i-$venta': 1},
        ahora: fecha,
      ),
    );
  }

  /// Una fila de `deposito` como queda después de un pull.
  Future<void> depositar(
    String id,
    int monto,
    DateTime fecha, {
    DateTime? validadoEn,
    DateTime? rechazadoEn,
    DateTime? baja,
    String destino = 'BANCO',
    String concepto = 'CASA_EDITORA',
  }) => db.customStatement(
    'INSERT INTO deposito (id, monto, fecha, destino, concepto, campania_id, ticket_id, '
    'validado_en, rechazado_en, created_at, updated_at, deleted_at) '
    "VALUES ('$id', $monto, ${_ms(fecha)}, '$destino', '$concepto', "
    "${concepto == 'ALQUILER' ? "'camp-1'" : 'NULL'}, "
    "${destino == 'RETIRO_COORDINADOR' ? 'NULL' : "'t-$id'"}, "
    '${validadoEn == null ? 'NULL' : _ms(validadoEn)}, '
    '${rechazadoEn == null ? 'NULL' : _ms(rechazadoEn)}, 1, 1, '
    '${baja == null ? 'NULL' : _ms(baja)})',
  );

  /// El teléfono bajó algo del servidor (sin esto, «Depositado» no tiene cifra).
  Future<void> bajada() => DriftSyncMeta(db).write(lastPullAt: _ahora);

  Future<DetalleDeMiPlata> leer({String colportor = 'col-1'}) => local.leer(colportor);

  /// Las tres sumas del detalle contra las cifras de Mi Cuenta: nunca deben distinguirse.
  Future<void> esperarQueCoincidaConMiCuenta(DetalleDeMiPlata d) async {
    final resumen = await ResumenDeCuentaLocalDataSourceDrift(
      db,
      cobranzas: cobranzas,
      ahora: () => _ahora,
    ).leer('col-1');
    expect(d.depositado?.validadoCentavos, resumen.depositado?.totalCentavos);
    expect(d.enManoCentavos, resumen.enMano.totalCentavos);
    expect(d.porCobrarCentavos, resumen.porCobrar.totalCentavos);
    expect(d.porCobrar.fold<int>(0, (s, c) => s + c.centavos), d.porCobrarCentavos);
  }

  group('una cuenta sin movimientos (33C·03)', () {
    test('dado que no vendió nada ni bajó nada del servidor, el detalle está vacío', () async {
      expect(await leer(), DetalleDeMiPlata.vacio);
    });
  });

  group('«En mano» (33C·01)', () {
    test('dado que cobró en efectivo, cada cobro sale con el cliente, la fecha y el monto, del más '
        'viejo al más nuevo', () async {
      await vender('v-1', 150000, _dia20);
      await vender('v-2', 80000, _dia21, vinculo: 'ep-2');
      await cobrar('c-2', 60000, _dia23, venta: 'v-2');
      await cobrar('c-1', 120000, _dia21);

      final d = await leer();

      expect(d.enMano, [
        MovimientoEnMano(cliente: 'María Fernández', fecha: _dia21, centavos: 120000),
        MovimientoEnMano(cliente: 'Pedro Gómez', fecha: _dia23, centavos: 60000),
      ]);
      expect(d.enManoCentavos, 180000);
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('la tarjeta y la transferencia no pasan por la mano: no salen en la lista', () async {
      await vender('v-1', 150000, _dia20);
      await cobrar('c-1', 50000, _dia20, medio: MedioCobranza.tarjeta);
      await cobrar('c-2', 20000, _dia21, medio: MedioCobranza.transferencia);
      await cobrar('c-3', 10000, _dia21);

      final d = await leer();

      expect(d.enMano.map((m) => m.centavos), [10000]);
      expect(d.enManoCentavos, 10000);
    });

    test('un cobro dado de baja no sale', () async {
      await vender('v-1', 150000, _dia20);
      await cobrar('c-1', 50000, _dia20);
      await db.customUpdate(
        'UPDATE cobranza SET deleted_at = 1 WHERE id = ?',
        variables: [const Variable<String>('c-1')],
        updates: {db.cobranzas},
      );

      expect((await leer()).enMano, isEmpty);
    });

    test('una devolución no resta de la mano: nunca queda plata a favor del cliente (Cristian, '
        '03/11, «Devol. saldo»)', () async {
      await vender('v-1', 150000, _dia20);
      await cobrar('c-1', 100000, _dia20);
      await devolver('d-1', DateTime.utc(2026, 10, 22, 10));

      final d = await leer();

      expect(d.enMano, [
        MovimientoEnMano(cliente: 'María Fernández', fecha: _dia20, centavos: 100000),
      ]);
      expect(d.enManoCentavos, 100000);
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('una venta dada de baja no se lleva el efectivo que ya se cobró', () async {
      await vender('v-1', 150000, _dia20);
      await cobrar('c-1', 50000, _dia20);
      await db.customUpdate(
        'UPDATE venta SET deleted_at = 1 WHERE id = ?',
        variables: [const Variable<String>('v-1')],
        updates: {db.ventas},
      );

      final d = await leer();

      expect(d.enMano.map((m) => m.centavos), [50000]);
      expect(d.enManoCentavos, 50000);
    });
  });

  group('«Por cobrar» (33C·02)', () {
    test('dado que dos clientes deben, sale una fila por cliente con desde cuándo y cuánto, la '
        'deuda más vieja primero', () async {
      await vender('v-1', 150000, _dia21);
      await vender('v-2', 80000, _dia20, vinculo: 'ep-2');
      await cobrar('c-1', 30000, _dia23);

      final d = await leer();

      expect(d.porCobrar, [
        SaldoDeCliente(cliente: 'Pedro Gómez', desde: _dia20, centavos: 80000),
        SaldoDeCliente(cliente: 'María Fernández', desde: _dia21, centavos: 120000),
      ]);
      expect(d.porCobrarCentavos, 200000);
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('un cliente con dos ventas suma en una sola fila, desde la más vieja', () async {
      await vender('v-1', 100000, _dia21);
      await vender('v-2', 50000, _dia20);

      final d = await leer();

      expect(d.porCobrar, [
        SaldoDeCliente(cliente: 'María Fernández', desde: _dia20, centavos: 150000),
      ]);
    });

    test('una devolución baja lo que debe el cliente, hasta el saldo', () async {
      await vender('v-1', 150000, _dia20);
      await cobrar('c-1', 50000, _dia20);
      await devolver('d-1', DateTime.utc(2026, 10, 22, 10));

      final d = await leer();

      // Lo devuelto vale más que lo que faltaba: la deuda queda en cero y no hay plata a favor.
      expect(d.porCobrar, isEmpty);
      expect(d.porCobrarCentavos, 0);
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('el que ya pagó todo no aparece', () async {
      await vender('v-1', 100000, _dia20);
      await cobrar('c-1', 100000, _dia21);

      expect((await leer()).porCobrar, isEmpty);
    });

    test(
      'una persona dada de baja con saldo sigue en la lista (decisión del 23/10, 32D·03)',
      () async {
        await vender('v-1', 120000, _dia20);
        await db.customUpdate(
          'UPDATE espacio_persona SET deleted_at = 1 WHERE id = ?',
          variables: [const Variable<String>('ep-1')],
          updates: {db.espacioPersonas},
        );
        await db.customUpdate(
          'UPDATE persona SET deleted_at = 1 WHERE id = ?',
          variables: [const Variable<String>('per-1')],
          updates: {db.personas},
        );

        final d = await leer();

        expect(d.porCobrar, [
          SaldoDeCliente(cliente: 'María Fernández', desde: _dia20, centavos: 120000),
        ]);
        await esperarQueCoincidaConMiCuenta(d);
      },
    );

    test('las ventas de otro colportor no entran', () async {
      await vender('v-1', 100000, _dia20);
      await vender('v-2', 70000, _dia20, colportor: 'col-2', vinculo: 'ep-2');

      final d = await leer();

      expect(d.porCobrar.map((s) => s.cliente), ['María Fernández']);
      expect(d.porCobrarCentavos, 100000);
    });

    test(
      'si todavía no bajó el nombre de la persona, la fila lo dice en vez de quedar vacía',
      () async {
        await vender('v-1', 100000, _dia20);
        await db.customUpdate('DELETE FROM persona', updates: {db.personas});

        final d = await leer();

        expect(d.porCobrar.single.cliente, DetalleDeMiPlataLocalDataSourceDrift.clienteSinNombre);
        expect(d.porCobrar.single.centavos, 100000);
      },
    );

    test('una persona sin apellido sale solo con el nombre', () async {
      await db.customUpdate(
        "UPDATE persona SET apellido = '' WHERE id = 'per-1'",
        updates: {db.personas},
      );
      await vender('v-1', 100000, _dia20);

      expect((await leer()).porCobrar.single.cliente, 'María');
    });
  });

  group('«Depositado» (33C)', () {
    final dia20 = DateTime.utc(2026, 10, 20, 15);
    final dia22 = DateTime.utc(2026, 10, 22, 15);
    final dia25 = DateTime.utc(2026, 10, 25, 15);

    test('dado que el teléfono todavía no bajó nada del servidor, no hay cifra: ni un cero '
        'inventado', () async {
      await depositar('d-1', 100000, dia20, validadoEn: dia22);

      expect((await leer()).depositado, isNull);
    });

    test('dado que bajó y no hay depósitos, la categoría existe y está en cero', () async {
      await bajada();

      final d = await leer();

      expect(d.depositado, const DepositadoEnMiPlata(validados: [], porValidar: []));
      expect(d.depositado!.validadoCentavos, 0);
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('lo validado suma a la cifra y lo que espera va aparte, cada uno del más viejo al más '
        'nuevo', () async {
      await bajada();
      await depositar('d-3', 30000, dia25);
      await depositar('d-1', 100000, dia22, validadoEn: dia25);
      await depositar('d-2', 50000, dia20, validadoEn: dia22, concepto: 'ALQUILER');
      await depositar('d-4', 20000, dia20, destino: 'RETIRO_COORDINADOR');

      final d = await leer();

      expect(d.depositado!.validados, [
        DepositoDeLaLista(
          montoCentavos: 50000,
          fecha: dia20,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.alquiler,
          validado: true,
        ),
        DepositoDeLaLista(
          montoCentavos: 100000,
          fecha: dia22,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.casaEditora,
          validado: true,
        ),
      ]);
      expect(d.depositado!.porValidar, [
        DepositoDeLaLista(
          montoCentavos: 20000,
          fecha: dia20,
          destino: DestinoDeDeposito.retiroCoordinador,
          concepto: ConceptoDeDeposito.casaEditora,
          validado: false,
        ),
        DepositoDeLaLista(
          montoCentavos: 30000,
          fecha: dia25,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.casaEditora,
          validado: false,
        ),
      ]);
      expect(d.depositado!.validadoCentavos, 150000);
      expect(d.depositado!.porValidarCentavos, 50000);
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('un depósito rechazado o dado de baja no sale en ninguna lista', () async {
      await bajada();
      await depositar('d-1', 100000, dia20, rechazadoEn: dia22, destino: 'RETIRO_COORDINADOR');
      await depositar('d-2', 70000, dia20, validadoEn: dia22, baja: dia25);
      await depositar('d-3', 40000, dia20, baja: dia25);
      // Con las dos marcas (no debería pasar) no se acredita: ante la duda, no se suma.
      await depositar('d-4', 90000, dia20, validadoEn: dia22, rechazadoEn: dia22);

      final d = await leer();

      expect(d.depositado, const DepositadoEnMiPlata(validados: [], porValidar: []));
      await esperarQueCoincidaConMiCuenta(d);
    });

    test('cuando baja la validación de un depósito, pasa de «por validar» a «validado» sin '
        'recargar', () async {
      await bajada();
      await depositar('d-1', 100000, dia20);
      final emitidos = <DetalleDeMiPlata>[];
      final sub = local.observar('col-1').listen(emitidos.add);
      await pumpEventQueue();
      expect(emitidos.last.depositado!.porValidarCentavos, 100000);
      expect(emitidos.last.depositado!.validadoCentavos, 0);

      await db.customUpdate(
        'UPDATE deposito SET validado_en = ${_ms(dia22)} WHERE id = ?',
        variables: [const Variable<String>('d-1')],
        updates: {db.depositos},
      );
      await pumpEventQueue();

      expect(emitidos.last.depositado!.porValidarCentavos, 0);
      expect(emitidos.last.depositado!.validadoCentavos, 100000);
      await sub.cancel();
    });

    test('los depósitos de alquiler también suman, igual que en Mi Cuenta', () async {
      await vender('v-1', 150000, _dia20);
      await cobrar('c-1', 50000, _dia20);
      await bajada();
      await depositar('d-1', 100000, dia20, validadoEn: dia22);
      await depositar('d-2', 25000, dia25, validadoEn: dia25, concepto: 'ALQUILER');

      await esperarQueCoincidaConMiCuenta(await leer());
    });
  });

  group('al día solo', () {
    test(
      'al registrar un cobro el detalle se actualiza sin recargar, y no repite lo que no cambió',
      () async {
        await vender('v-1', 150000, _dia20);
        final emitidos = <DetalleDeMiPlata>[];
        final sub = local.observar('col-1').listen(emitidos.add);
        await pumpEventQueue();
        expect(emitidos.last.enMano, isEmpty);

        await cobrar('c-1', 50000, _dia21);
        await pumpEventQueue();

        expect(emitidos.last.enMano.map((m) => m.centavos), [50000]);
        expect(emitidos.last.porCobrar.single.centavos, 100000);
        final cantidad = emitidos.length;
        // Un cambio que no mueve el detalle no vuelve a emitir.
        await db.customUpdate('UPDATE venta SET updated_at = updated_at', updates: {db.ventas});
        await pumpEventQueue();
        expect(emitidos.length, cantidad);
        await sub.cancel();
      },
    );
  });

  group('si la base no se puede leer', () {
    test('el Stream falla con FailureCuentaNoDisponible y no emite ceros', () async {
      await vender('v-1', 150000, _dia20);
      final repo = DetalleDeMiPlataRepositoryImpl(local);
      await db.customStatement('DROP TABLE cobranza');

      await expectLater(repo.observar('col-1'), emitsError(isA<FailureCuentaNoDisponible>()));
    });

    test('sin DB abierta también falla con FailureCuentaNoDisponible', () async {
      await expectLater(
        const DetalleDeMiPlataSinBase().observar('col-1'),
        emitsError(isA<FailureCuentaNoDisponible>()),
      );
    });
  });
}
