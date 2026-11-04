// QA de HU-COB-005 (#167, PR #575): el saldo pendiente reactivo contra la DB real en memoria. Es un
// enabler sin pantalla: no hay artboards, así que el QA prueba lo que una vista va a consumir —que el
// saldo se actualice solo también cuando el cambio llega por el pull, que dos cobros a la vez no dejen
// valores inventados, que un segundo suscriptor vea el valor de ahora, que el error no lleve datos
// al log y que los providers se recuperen cuando se abre la DB— y que el saldo de la ubicación diga
// lo mismo que el color de la casa (R-UB08).
import 'dart:async';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/repositories/saldo_pendiente_repository_impl.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Table, TableInfo, UpdateKind, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

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

/// Lo que un `Stream` fue emitiendo, en orden.
final class _Escucha<T> {
  _Escucha(Stream<T> origen) {
    _sub = origen.listen(valores.add, onError: errores.add);
  }

  late final StreamSubscription<T> _sub;
  final valores = <T>[];
  final errores = <Object>[];

  Future<void> hasta(bool Function() condicion) async {
    for (var i = 0; i < 600 && !condicion(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condicion(), isTrue, reason: 'no llegó lo esperado: $valores');
  }

  Future<void> quieto() => Future<void>.delayed(const Duration(milliseconds: 150));

  Future<void> cerrar() => _sub.cancel();
}

/// Una DB «abierta» que el test puede abrir y cerrar a mano (como el login y el logout).
class _DbDelTest extends DbLocalNotifier {
  @override
  AppDatabase? build() => null;

  void poner(AppDatabase? db) => state = db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;
  late VentaLocalDataSourceDrift ventas;
  late HouseStatusUpdaterDrift casas;

  Future<void> vender(String id, int monto, {String vinculo = 'ep-1'}) async {
    await ventas.registrar(ventaDe(id, monto: monto, talonario: 'T-$id', vinculo: vinculo), [
      itemDe('i-$id', id, cantidad: 1, precio: monto),
    ]);
    encolador.encolados.clear();
  }

  /// Un UPDATE que avisa a Drift qué tabla cambió (como el pull).
  Future<void> marcar(String tabla, String id, TableInfo<Table, Object?> info) => db.customUpdate(
    'UPDATE $tabla SET deleted_at = 1 WHERE id = ?',
    variables: [Variable<String>(id)],
    updates: {info},
    updateKind: UpdateKind.update,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  group('el pull despierta el saldo (la HU dice «sin recargar pantalla»)', () {
    Map<String, Object?> cobroDelCloud(String id, int monto, {String? baja}) => {
      'id': id,
      'venta_id': 'v-1',
      'monto': monto,
      'medio': 'EFECTIVO',
      'fecha': '2026-10-23T13:45:10.123Z',
      'created_at': '2026-10-23T13:45:10.123Z',
      'updated_at': '2026-10-23T13:45:10.123Z',
      'deleted_at': baja,
    };

    test('un cobro que llega por el pull baja el saldo de la venta, la persona, la ubicación y el '
        'total; el mismo cobro con deleted_at lo vuelve a subir', () async {
      await vender('v-1', 150000);
      final store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
      final venta = _Escucha(local.observarVentaConSaldo('v-1'));
      final persona = _Escucha(local.observarSaldoDePersona('per-1'));
      final ubicacion = _Escucha(local.observarSaldoDeUbicacion('ub-1'));
      final total = _Escucha(local.observarSaldoTotal('col-1'));
      await total.hasta(() => total.valores.isNotEmpty && venta.valores.isNotEmpty);

      await store.applyDelta(
        {
          'cobranza': [cobroDelCloud('c-pull', 50000)],
        },
        scope: 'cobranza',
        watermark: null,
      );

      await total.hasta(() => total.valores.length == 2);
      await persona.hasta(() => persona.valores.length == 2);
      await ubicacion.hasta(() => ubicacion.valores.length == 2);
      await venta.hasta(() => venta.valores.length == 2);
      expect(
        [persona.valores.last, ubicacion.valores.last, total.valores.last],
        [100000, 100000, 100000],
      );
      expect(venta.valores.last!.cobradoCentavos, 50000);

      await store.applyDelta(
        {
          'cobranza': [cobroDelCloud('c-pull', 50000, baja: '2026-10-24T10:00:00.000Z')],
        },
        scope: 'cobranza',
        watermark: null,
      );

      await total.hasta(() => total.valores.length == 3);
      expect(total.valores, [150000, 100000, 150000]);
      expect(venta.valores.last!.cobradoCentavos, 0);
      for (final e in [venta, persona, ubicacion, total]) {
        await e.cerrar();
      }
    });

    test('una venta que llega por el pull sube el saldo, y un cobro que llega antes que su venta '
        'cuenta cuando la venta aparece (el orden del pull no importa)', () async {
      final store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
      final total = _Escucha(local.observarSaldoTotal('col-1'));
      final persona = _Escucha(local.observarSaldoDePersona('per-1'));
      await total.hasta(() => total.valores.isNotEmpty && persona.valores.isNotEmpty);

      await store.applyDelta(
        {
          'cobranza': [cobroDelCloud('c-1', 40000)],
        },
        scope: 'cobranza',
        watermark: null,
      );
      await total.quieto();
      expect(total.valores, [0], reason: 'un cobro sin venta no cuenta ni emite');

      await store.applyDelta(
        {
          'venta': [
            {
              'id': 'v-1',
              'espacio_persona_id': 'ep-1',
              'numero_talonario': 'T-1',
              'monto_total': 150000,
              'fecha': '2026-10-23T13:45:10.123Z',
              'colportor_id': 'col-1',
              'created_at': '2026-10-23T13:45:10.123Z',
              'updated_at': '2026-10-23T13:45:10.123Z',
            },
          ],
        },
        scope: 'venta',
        watermark: null,
      );

      await total.hasta(() => total.valores.length == 2);
      await persona.hasta(() => persona.valores.length == 2);
      expect(total.valores, [0, 110000]);
      expect(persona.valores, [0, 110000]);
      await total.cerrar();
      await persona.cerrar();
    });
  });

  group('acciones superpuestas y varios suscriptores', () {
    test('dos cobros a la vez en dos personas: el total termina en lo justo y nunca se emite un '
        'valor que no sea uno de los cuatro estados posibles', () async {
      await vender('v-1', 150000);
      await vender('v-2', 80000, vinculo: 'ep-2');
      final total = _Escucha(local.observarSaldoTotal('col-1'));
      final ubicacion = _Escucha(local.observarSaldoDeUbicacion('ub-1'));
      final p1 = _Escucha(local.observarSaldoDePersona('per-1'));
      final p2 = _Escucha(local.observarSaldoDePersona('per-2'));
      await total.hasta(() => total.valores.isNotEmpty && p1.valores.isNotEmpty);

      final r = await Future.wait([
        local.registrar(_cobro('c-1', 50000)),
        local.registrar(_cobro('c-2', 30000, venta: 'v-2')),
      ]);

      expect(r.length, 2);
      await total.hasta(() => total.valores.last == 150000);
      await ubicacion.hasta(() => ubicacion.valores.last == 150000);
      await p1.hasta(() => p1.valores.last == 100000);
      await p2.hasta(() => p2.valores.last == 50000);
      expect(
        total.valores.toSet().difference({230000, 180000, 200000, 150000}),
        isEmpty,
        reason: 'se emitió un total que no existe: ${total.valores}',
      );
      expect(await local.observarSaldoTotal('col-1').first, 150000);
      for (final e in [total, ubicacion, p1, p2]) {
        await e.cerrar();
      }
    });

    test(
      'un suscriptor que llega después de un cobro ve el valor de ahora, no el de antes; los dos '
      'terminan iguales',
      () async {
        await vender('v-1', 150000);
        final a = _Escucha(local.observarSaldoDePersona('per-1'));
        await a.hasta(() => a.valores.isNotEmpty);
        await local.registrar(_cobro('c-1', 50000));
        await a.hasta(() => a.valores.length == 2);

        final b = _Escucha(local.observarSaldoDePersona('per-1'));
        await b.hasta(() => b.valores.isNotEmpty);
        expect(b.valores.first, 100000);

        await local.registrar(_cobro('c-2', 30000));
        await a.hasta(() => a.valores.last == 70000);
        await b.hasta(() => b.valores.last == 70000);
        await a.cerrar();
        await b.cerrar();
      },
    );

    test('150 ventas con su stream: un cobro en una sola despierta solo a esa (las otras no emiten '
        'de nuevo) y todo llega a tiempo', () async {
      for (var i = 0; i < 150; i++) {
        await vender('v-$i', 10000 + i);
      }
      final escuchas = [
        for (var i = 0; i < 150; i++) _Escucha(local.observarVentaConSaldo('v-$i')),
      ];
      await escuchas.last.hasta(() => escuchas.every((e) => e.valores.isNotEmpty));

      final reloj = Stopwatch()..start();
      await local.registrar(_cobro('c-7', 500, venta: 'v-7'));
      await escuchas[7].hasta(() => escuchas[7].valores.length == 2);
      await escuchas[7].quieto();
      reloj.stop();

      expect(escuchas[7].valores.last!.saldoCentavos, 10007 - 500);
      expect([for (final e in escuchas) e.valores.length].where((n) => n != 1).length, 1);
      expect(reloj.elapsed, lessThan(const Duration(seconds: 5)));
      for (final e in escuchas) {
        await e.cerrar();
      }
    });
  });

  group('privacidad', () {
    test('la falla del saldo deja en el log solo el corte y el tipo de la excepción: ningún id, '
        'monto ni nombre', () async {
      final salida = MemoryOutput();
      final repo = SaldoPendienteRepositoryImpl(
        local,
        logger: AppLogger(
          logger: Logger(level: Level.all, printer: SimplePrinter(), output: salida),
        ),
      );
      await vender('v-1', 150000);
      await db.customStatement('DROP TABLE cobranza');

      for (final s in [
        repo.observarDePersona('per-1'),
        repo.observarDeUbicacion('ub-1'),
        repo.observarTotal('col-1'),
        repo.observarVenta('v-1'),
      ]) {
        await expectLater(s, emitsError(isA<FailureSaldoNoDisponible>()));
      }

      final log = salida.buffer.expand((e) => e.lines).join('\n');
      expect(log, contains('COBRO_SALDO_STREAM_FAIL'));
      for (final dato in ['per-1', 'ub-1', 'col-1', 'v-1', '150000', 'T-v-1']) {
        expect(log, isNot(contains(dato)), reason: 'el log filtra «$dato»');
      }
      expect(const FailureSaldoNoDisponible().toString(), isNot(contains('per-')));
    });
  });

  group('coherencia con el color de la casa (R-UB08)', () {
    // `house_status` mira solo los espacios ACTIVOS de la ubicación; el saldo de la ubicación cuenta
    // los de cualquier espacio (la decisión «Deuda baja» del 27/10: dar de baja no esconde lo que se
    // debe). Cuando difieren, la casa dice una cosa y la hoja otra.
    test(
      'QA #167: un depto dado de baja con deuda: la casa no la pinta y el saldo de la ubicación '
      'la cuenta',
      () async {
        await vender('v-1', 150000);
        await marcar('espacio', 'esp-1', db.espacios);
        await marcar('espacio', 'esp-2', db.espacios);

        final casa = await casas.recalcular('ub-1', ahora: t0, colportorId: 'col-1');
        final saldo = await local.observarSaldoDeUbicacion('ub-1').first;

        expect(casa != null, saldo > 0, reason: 'casa=$casa, saldo de la ubicación=$saldo');
      },
      skip:
          'QA #167: «ubicación» cuenta espacios dados de baja y house_status no (ver PENDIENTES P1, mapa §2)',
    );
  });

  group('los providers y el ciclo de la sesión', () {
    ProviderContainer armar() {
      final c = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(_DbDelTest.new),
          encoladorSyncProvider.overrideWithValue(encolador),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> hasta(bool Function() condicion) async {
      for (var i = 0; i < 600 && !condicion(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(condicion(), isTrue);
    }

    test('arranque en frío: sin DB el saldo falla; cuando la DB se abre se recupera solo, y al '
        'cerrar la sesión vuelve a fallar en vez de dejar un monto viejo', () async {
      await vender('v-1', 150000);
      final c = armar();
      final persona = c.listen(saldoDeLaPersonaProvider('per-1'), (_, _) {});
      final total = c.listen(saldoTotalDelColportorProvider('col-1'), (_, _) {});
      await hasta(() => persona.read() is AsyncError<int> && total.read() is AsyncError<int>);
      expect(persona.read().error, isA<FailureSaldoNoDisponible>());

      (c.read(dbLocalProvider.notifier) as _DbDelTest).poner(db);
      await hasta(() => persona.read().value == 150000 && total.read().value == 150000);
      expect(persona.read().hasError, isFalse);

      (c.read(dbLocalProvider.notifier) as _DbDelTest).poner(null);
      await hasta(() => persona.read() is AsyncError<int>);
      expect(persona.read().error, isA<FailureSaldoNoDisponible>());
    });

    test('reentrar a la pantalla (soltar el provider y volver a mirarlo) arranca con el valor de '
        'ahora, no con el de la primera vez', () async {
      await vender('v-1', 150000);
      final c = armar();
      (c.read(dbLocalProvider.notifier) as _DbDelTest).poner(db);
      var sub = c.listen(saldoDeLaPersonaProvider('per-1'), (_, _) {});
      await hasta(() => sub.read().value == 150000);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await local.registrar(_cobro('c-1', 50000));
      sub = c.listen(saldoDeLaPersonaProvider('per-1'), (_, _) {});

      await hasta(() => sub.read().value == 100000);
      sub.close();
    });
  });
}
