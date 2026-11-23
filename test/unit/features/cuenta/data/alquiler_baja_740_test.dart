// «Mi alquiler» con la campaña de la baja (HU-CTA-007, #740) contra la base real: AppDatabase en memoria
// con las réplicas `campania`, `campania_colportor`, `deposito` y `alquiler_decision`. Qué campañas de baja
// cuentan, lo que queda por decidir con la cuenta del servidor (backend-supabase 0201), cada destino, lo
// pagado después de la última decisión, la decisión deshecha y el `Stream` que avisa cuando baja una decisión.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/alquiler_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

int _ms(DateTime f) => f.toUtc().millisecondsSinceEpoch;

final _t0 = DateTime.utc(2026, 11, 10, 12);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AlquilerLocalDataSourceDrift fuente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = AlquilerLocalDataSourceDrift(db);
  });
  tearDown(() => db.close());

  Future<void> campania(
    String id, {
    int? monto = 250000,
    String inicio = '2026-09-01',
    bool baja = false,
  }) => db.customStatement(
    'INSERT INTO campania (id, nombre, fecha_inicio, alquiler_monto, created_at, updated_at, '
    "deleted_at) VALUES ('$id', 'Campaña $id', '$inicio', ${monto ?? 'NULL'}, 1, 1, "
    '${baja ? 8 : 'NULL'})',
  );

  var filas = 0;

  /// La inscripción como queda después de un pull; [baja] la deja dada de baja.
  Future<void> inscripcion(String campaniaId, {String usuario = 'col-1', bool baja = false}) {
    filas++;
    return db.customStatement(
      'INSERT INTO campania_colportor (id, campania_id, usuario_id, created_at, updated_at, '
      "deleted_at) VALUES ('cc-$filas', '$campaniaId', '$usuario', 1, 1, ${baja ? 8 : 'NULL'})",
    );
  }

  Future<void> pago(
    String campaniaId,
    int monto, {
    DateTime? validadoEn,
    bool validado = true,
    bool anulado = false,
    bool rechazado = false,
  }) {
    filas++;
    return db.customStatement(
      'INSERT INTO deposito (id, monto, fecha, destino, concepto, campania_id, validado_en, '
      'rechazado_en, anulado_at, created_at, updated_at) '
      "VALUES ('d-$filas', $monto, ${_ms(_t0)}, 'RETIRO_COORDINADOR', 'ALQUILER', '$campaniaId', "
      '${validado ? _ms(validadoEn ?? _t0) : 'NULL'}, ${rechazado ? 6 : 'NULL'}, '
      "${anulado ? 7 : 'NULL'}, 1, 1)",
    );
  }

  /// Una decisión como queda después de un pull; [creada] es su `created_at`.
  Future<void> decision(
    String campaniaId,
    String destino,
    int monto, {
    String usuario = 'col-1',
    DateTime? creada,
    bool baja = false,
  }) {
    filas++;
    final en = _ms(creada ?? _t0.add(const Duration(days: 1)));
    return db.customStatement(
      'INSERT INTO alquiler_decision (id, usuario_id, campania_id, decision, monto, decidido_en, '
      "created_at, updated_at, deleted_at) VALUES ('ad-$filas', '$usuario', '$campaniaId', "
      "'$destino', $monto, $en, $en, $en, ${baja ? 9 : 'NULL'})",
    );
  }

  Future<AlquilerDeBaja> laBaja() async => (await fuente.leer('col-1')).bajas.single;

  group('qué campañas de baja aparecen', () {
    test(
      'Ana se dio de baja de Otoño después de pagar \$ 5.000: aparece con lo que pagó y todo por '
      'decidir',
      () async {
        await campania('otono');
        await inscripcion('otono', baja: true);
        await pago('otono', 500000);

        final alquiler = await fuente.leer('col-1');

        expect(alquiler.hayAlquiler, isTrue);
        expect(alquiler.campanias, isEmpty);
        final baja = alquiler.bajas.single;
        expect(baja.campaniaId, 'otono');
        expect(baja.campania, 'Campaña otono');
        expect(baja.pagos.single.montoCentavos, 500000);
        expect(baja.decisiones, isEmpty);
        expect(baja.porDecidirCentavos, 500000);
        expect(baja.hayPorDecidir, isTrue);
        // Quien se da de baja no tiene saldo: la línea de Mi Cuenta dice «Al día».
        expect(alquiler.saldoCentavos, 0);
      },
    );

    test('una baja sin pagos ni decisiones no aparece: no hay nada que decir', () async {
      await campania('otono');
      await inscripcion('otono', baja: true);

      final alquiler = await fuente.leer('col-1');

      expect(alquiler.bajas, isEmpty);
      expect(alquiler.hayAlquiler, isFalse);
    });

    test(
      'la campaña de la baja aparece aunque no cobre alquiler y aunque tenga monto en 0',
      () async {
        await campania('sin-monto', monto: null);
        await campania('en-cero', monto: 0, inicio: '2026-10-01');
        await inscripcion('sin-monto', baja: true);
        await inscripcion('en-cero', baja: true);
        await pago('sin-monto', 100000);
        await pago('en-cero', 100000);

        expect((await fuente.leer('col-1')).bajas.map((b) => b.campaniaId), [
          'en-cero',
          'sin-monto',
        ]);
      },
    );

    test(
      'si la persona volvió a la campaña (inscripción vigente) es una campaña como cualquiera, no '
      'una baja',
      () async {
        await campania('c-1');
        await inscripcion('c-1', baja: true);
        await inscripcion('c-1');
        await pago('c-1', 100000);

        final alquiler = await fuente.leer('col-1');

        expect(alquiler.bajas, isEmpty);
        expect(alquiler.campanias.single.campaniaId, 'c-1');
      },
    );

    test(
      'no cuentan la baja de otra persona, una campaña dada de baja ni los pagos de otra campaña',
      () async {
        await campania('c-ajena');
        await campania('c-borrada', baja: true);
        await campania('c-propia');
        await campania('c-otra');
        await inscripcion('c-ajena', usuario: 'otro', baja: true);
        await inscripcion('c-borrada', baja: true);
        await inscripcion('c-propia', baja: true);
        await pago('c-ajena', 100000);
        await pago('c-borrada', 100000);
        await pago('c-otra', 100000); // sin inscripción: no es una baja
        await pago('c-propia', 30000);

        final alquiler = await fuente.leer('col-1');

        expect(alquiler.bajas.map((b) => b.campaniaId), ['c-propia']);
        expect(alquiler.bajas.single.pagos.single.montoCentavos, 30000);
        expect((await fuente.leer('otro')).bajas.map((b) => b.campaniaId), ['c-ajena']);
      },
    );

    test(
      'con dos bajas y una campaña vigente: la vigente aparte y las bajas con la más nueva primero',
      () async {
        await campania('vigente', inicio: '2026-11-01');
        await campania('vieja', inicio: '2026-03-01');
        await campania('nueva', inicio: '2026-09-01');
        await inscripcion('vigente');
        await inscripcion('vieja', baja: true);
        await inscripcion('nueva', baja: true);
        await pago('vieja', 100000);
        await pago('nueva', 200000);

        final alquiler = await fuente.leer('col-1');

        expect(alquiler.campanias.map((c) => c.campaniaId), ['vigente']);
        expect(alquiler.bajas.map((b) => b.campaniaId), ['nueva', 'vieja']);
      },
    );
  });

  group('lo que queda por decidir (la cuenta del servidor, 0201)', () {
    setUp(() async {
      await campania('e1');
      await inscripcion('e1', baja: true);
    });

    test(
      '«a cuenta del próximo depósito»: lo decidido se descuenta y no queda nada por decidir',
      () async {
        await pago('e1', 50000);
        await pago('e1', 20000);
        await decision('e1', 'A_CUENTA_PROXIMO_DEPOSITO', 70000);

        final baja = await laBaja();

        expect(baja.decisiones.single.destino, DestinoDeLoPagado.aCuentaDelProximoDeposito);
        expect(baja.decisiones.single.montoCentavos, 70000);
        expect(baja.porDecidirCentavos, 0);
        expect(baja.hayPorDecidir, isFalse);
      },
    );

    test('«se lo queda el coordinador»: lo decidido se descuenta', () async {
      await pago('e1', 40000);
      await decision('e1', 'SE_LO_QUEDA_EL_COORDINADOR', 40000);

      final baja = await laBaja();

      expect(baja.decisiones.single.destino, DestinoDeLoPagado.seLoQuedaElCoordinador);
      expect(baja.porDecidirCentavos, 0);
    });

    test('«devolver»: sus pagos bajan anulados, la lista los marca devueltos y no queda nada por '
        'decidir', () async {
      await pago('e1', 70000, anulado: true);
      await decision('e1', 'DEVOLVER_AL_COLPORTOR', 70000);

      final baja = await laBaja();

      expect(baja.decisiones.single.destino, DestinoDeLoPagado.devolverAlColportor);
      expect(baja.pagos.single.estado, EstadoDePagoDeAlquiler.devuelto);
      expect(baja.pagadoCentavos, 0);
      expect(baja.porDecidirCentavos, 0);
    });

    test(
      'un pago de después de la última decisión vuelve a quedar «por decidir», solo lo nuevo',
      () async {
        await pago('e1', 70000, validadoEn: _t0);
        await decision('e1', 'A_CUENTA_PROXIMO_DEPOSITO', 70000);
        await pago('e1', 10000, validadoEn: _t0.add(const Duration(days: 2)));

        final baja = await laBaja();

        expect(baja.porDecidirCentavos, 10000);
        expect(baja.decisiones, hasLength(1));
      },
    );

    test('devolver solo lo nuevo: los 70.000 siguen a cuenta, los 10.000 anulados, la más nueva '
        'primero y nada por decidir', () async {
      await pago('e1', 70000);
      await pago('e1', 10000, anulado: true);
      await decision('e1', 'A_CUENTA_PROXIMO_DEPOSITO', 70000);
      await decision(
        'e1',
        'DEVOLVER_AL_COLPORTOR',
        10000,
        creada: _t0.add(const Duration(days: 3)),
      );

      final baja = await laBaja();

      expect(baja.decisiones.map((d) => d.destino), [
        DestinoDeLoPagado.devolverAlColportor,
        DestinoDeLoPagado.aCuentaDelProximoDeposito,
      ]);
      expect(baja.porDecidirCentavos, 0);
    });

    test('devolver todo y pagar de nuevo: lo nuevo queda por decidir', () async {
      await pago('e1', 70000, anulado: true);
      await decision('e1', 'DEVOLVER_AL_COLPORTOR', 70000);
      await pago('e1', 5000, validadoEn: _t0.add(const Duration(days: 4)));

      final baja = await laBaja();

      expect(baja.porDecidirCentavos, 5000);
      expect(baja.decisiones, hasLength(1));
    });

    test('lo por validar y lo rechazado no se decide: no cuenta como pagado', () async {
      await pago('e1', 30000, validado: false);
      await pago('e1', 20000, validado: false, rechazado: true);

      final baja = await laBaja();

      expect(baja.pagos, hasLength(2));
      expect(baja.pagadoCentavos, 0);
      expect(baja.porDecidirCentavos, 0);
      expect(baja.hayPorDecidir, isFalse);
    });

    test(
      'una decisión deshecha (la persona volvió y se dio de baja otra vez) baja como baja lógica y '
      'no cuenta: vuelve a quedar todo por decidir',
      () async {
        await pago('e1', 40000);
        await decision('e1', 'SE_LO_QUEDA_EL_COORDINADOR', 40000, baja: true);

        final baja = await laBaja();

        expect(baja.decisiones, isEmpty);
        expect(baja.porDecidirCentavos, 40000);
      },
    );

    test('lo decidido nunca deja el «por decidir» en negativo', () async {
      await pago('e1', 10000);
      await decision('e1', 'A_CUENTA_PROXIMO_DEPOSITO', 70000);

      expect((await laBaja()).porDecidirCentavos, 0);
    });

    test(
      'solo cuentan las decisiones propias y de esa campaña, y un destino desconocido se ignora',
      () async {
        await campania('e2', inicio: '2026-10-01');
        await inscripcion('e2', baja: true);
        await pago('e1', 40000);
        await decision('e1', 'SE_LO_QUEDA_EL_COORDINADOR', 40000, usuario: 'otro');
        await decision('e2', 'SE_LO_QUEDA_EL_COORDINADOR', 40000);
        await decision('e1', 'DESTINO_DEL_FUTURO', 40000);

        final alquiler = await fuente.leer('col-1');

        final e1 = alquiler.bajas.singleWhere((b) => b.campaniaId == 'e1');
        expect(e1.decisiones, isEmpty);
        expect(e1.porDecidirCentavos, 40000);
        // e2 no tiene pagos pero sí una decisión vigente: aparece con lo que se decidió.
        final e2 = alquiler.bajas.singleWhere((b) => b.campaniaId == 'e2');
        expect(e2.decisiones.single.montoCentavos, 40000);
        expect(e2.porDecidirCentavos, 0);
      },
    );

    test('la fecha de la decisión es el `created_at` de la fila, en UTC', () async {
      await pago('e1', 40000);
      final cuando = DateTime.utc(2026, 11, 12, 15, 30);
      await decision('e1', 'A_CUENTA_PROXIMO_DEPOSITO', 40000, creada: cuando);

      expect((await laBaja()).decisiones.single.decididaEn, cuando);
    });
  });

  group('el Stream', () {
    test(
      'cuando baja la decisión del coordinador, emite lo nuevo, y no repite lo que no cambió',
      () async {
        await campania('e1');
        await inscripcion('e1', baja: true);
        await pago('e1', 500000);
        final emitidos = <int>[];
        final sub = fuente
            .observar('col-1')
            .listen((a) => emitidos.add(a.bajas.single.porDecidirCentavos));
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(emitidos, [500000]);

        await decision('e1', 'A_CUENTA_PROXIMO_DEPOSITO', 500000);
        db.markTablesUpdated({db.alquilerDecisiones});
        await pumpEventQueue();
        expect(emitidos, [500000, 0]);

        // La decisión de otra persona: no cambia nada que se vea.
        await decision('e1', 'DEVOLVER_AL_COLPORTOR', 1, usuario: 'otro');
        db.markTablesUpdated({db.alquilerDecisiones});
        await pumpEventQueue();
        expect(emitidos, [500000, 0]);
      },
    );

    test('cuando una decisión se deshace por el pull, la baja vuelve a «por decidir»', () async {
      await campania('e1');
      await inscripcion('e1', baja: true);
      await pago('e1', 500000);
      await decision('e1', 'SE_LO_QUEDA_EL_COORDINADOR', 500000);
      final emitidos = <int>[];
      final sub = fuente
          .observar('col-1')
          .listen((a) => emitidos.add(a.bajas.single.porDecidirCentavos));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await db.customStatement('UPDATE alquiler_decision SET deleted_at = 9');
      db.markTablesUpdated({db.alquilerDecisiones});
      await pumpEventQueue();

      expect(emitidos, [0, 500000]);
    });
  });
}
