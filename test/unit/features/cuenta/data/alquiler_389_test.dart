// «Mi alquiler» (HU-CTA-007, vista 38C, #389) contra la base real: AppDatabase en memoria con las
// réplicas `campania`, `campania_colportor` y `deposito`. Qué campañas cuentan, cuánto se pagó, lo que
// espera validación, lo rechazado y lo devuelto, lo pagado de más (que dice el servidor), y el `Stream` que avisa cuando baja
// un pago o cambia el monto.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/alquiler_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/alquiler_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/campania_del_alquiler_drift.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/totales_de_depositos_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

int _ms(DateTime f) => f.toUtc().millisecondsSinceEpoch;

final _ahora = DateTime.utc(2026, 11, 22, 15);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AlquilerLocalDataSourceDrift fuente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = AlquilerLocalDataSourceDrift(db);
  });
  tearDown(() => db.close());

  /// Una campaña como queda después de un pull; [monto] en centavos, `null` = no cobra alquiler.
  Future<void> campania(
    String id, {
    int? monto,
    String inicio = '2026-09-01',
    String? fin,
    bool baja = false,
    String? nombre,
  }) => db.customStatement(
    'INSERT INTO campania (id, nombre, fecha_inicio, fecha_fin, alquiler_monto, created_at, '
    'updated_at, deleted_at) '
    "VALUES ('$id', '${nombre ?? 'Campaña $id'}', '$inicio', ${fin == null ? 'NULL' : "'$fin'"}, "
    '${monto ?? 'NULL'}, 1, 1, ${baja ? _ms(_ahora) : 'NULL'})',
  );

  Future<void> inscripcion(String campaniaId, {String usuario = 'col-1', bool baja = false}) =>
      db.customStatement(
        'INSERT INTO campania_colportor (id, campania_id, usuario_id, created_at, updated_at, '
        "deleted_at) VALUES ('cc-$campaniaId-$usuario', '$campaniaId', '$usuario', 1, 1, "
        '${baja ? _ms(_ahora) : 'NULL'})',
      );

  /// La cuenta de [usuario] como la baja el pull, con lo que el servidor dice que trasladó (centavos).
  Future<void> cuenta(
    int trasladado, {
    String usuario = 'col-1',
    bool baja = false,
    String id = 'cu-1',
  }) => db.customStatement(
    'INSERT INTO cuenta_colportor (id, usuario_id, alquiler_trasladado, created_at, updated_at, '
    "deleted_at) VALUES ('$id', '$usuario', $trasladado, 1, 1, ${baja ? 9 : 'NULL'})",
  );

  var n = 0;

  /// Un depósito como queda después de un pull.
  Future<void> pago(
    String? campaniaId,
    int monto, {
    DateTime? fecha,
    bool validado = false,
    bool rechazado = false,
    bool anulado = false,
    bool baja = false,
    String concepto = 'ALQUILER',
    String destino = 'RETIRO_COORDINADOR',
    String? motivo,
  }) {
    n++;
    return db.customStatement(
      'INSERT INTO deposito (id, monto, fecha, destino, concepto, campania_id, ticket_id, '
      'validado_en, rechazado_en, anulado_at, motivo_rechazo, created_at, updated_at, deleted_at) '
      "VALUES ('d-$n', $monto, ${_ms(fecha ?? DateTime.utc(2026, 10, 15, 12))}, '$destino', "
      "'$concepto', ${campaniaId == null ? 'NULL' : "'$campaniaId'"}, "
      "${destino == 'RETIRO_COORDINADOR' ? 'NULL' : "'t-$n'"}, "
      '${validado ? 5 : 'NULL'}, ${rechazado ? 6 : 'NULL'}, ${anulado ? 7 : 'NULL'}, '
      "${motivo == null ? 'NULL' : "'$motivo'"}, 1, 1, ${baja ? 8 : 'NULL'})",
    );
  }

  test('dado que no hay inscripciones, cuando se lee, no hay alquiler', () async {
    expect(await fuente.leer('col-1'), AlquilerDelColportor.vacio);
    expect((await fuente.leer('col-1')).hayAlquiler, isFalse);
  });

  test('dado una campaña que cobra y ningún pago, cuando se lee, falta todo el monto', () async {
    await campania('c-1', monto: 1850000, nombre: 'Primavera 2026');
    await inscripcion('c-1');

    final alquiler = await fuente.leer('col-1');

    expect(alquiler.campanias, hasLength(1));
    final c = alquiler.campanias.single;
    expect(c.campania, 'Primavera 2026');
    expect(c.montoCentavos, 1850000);
    expect(c.pagadoCentavos, 0);
    expect(c.saldoCentavos, 1850000);
    expect(c.pagos, isEmpty);
    expect(alquiler.saldoCentavos, 1850000);
  });

  test('dado campañas que no cobran, de baja, o inscripciones ajenas o de baja, cuando se lee, '
      'ninguna cuenta', () async {
    await campania('c-sin'); // sin monto
    await campania('c-cero', monto: 0);
    await campania('c-baja', monto: 100000, baja: true);
    await campania('c-ajena', monto: 100000);
    await campania('c-dada-de-baja', monto: 100000);
    await inscripcion('c-sin');
    await inscripcion('c-cero');
    await inscripcion('c-baja');
    await inscripcion('c-ajena', usuario: 'otro');
    await inscripcion('c-dada-de-baja', baja: true);

    expect((await fuente.leer('col-1')).hayAlquiler, isFalse);
    expect((await fuente.leer('otro')).campanias.map((c) => c.campaniaId), ['c-ajena']);
  });

  test(
    'dado pagos en cada estado, cuando se lee, solo lo validado baja el saldo y cada uno sale en '
    'la lista con su estado',
    () async {
      await campania('c-1', monto: 1850000);
      await inscripcion('c-1');
      await pago('c-1', 600000, validado: true, fecha: DateTime.utc(2026, 10, 15, 12));
      await pago('c-1', 200000, fecha: DateTime.utc(2026, 11, 20, 12)); // por validar
      await pago(
        'c-1',
        300000,
        rechazado: true,
        motivo: 'el monto no coincide',
        fecha: DateTime.utc(2026, 11, 1, 12),
      );
      await pago(
        'c-1',
        400000,
        validado: true,
        anulado: true,
        fecha: DateTime.utc(2026, 10, 20, 12),
      );

      final c = (await fuente.leer('col-1')).campanias.single;

      expect(c.pagadoCentavos, 600000);
      expect(c.porValidarCentavos, 200000);
      expect(c.saldoCentavos, 1250000);
      // El más nuevo primero.
      expect(c.pagos.map((p) => p.estado), [
        EstadoDePagoDeAlquiler.porValidar,
        EstadoDePagoDeAlquiler.rechazado,
        EstadoDePagoDeAlquiler.devuelto,
        EstadoDePagoDeAlquiler.validado,
      ]);
      expect(c.pagos[1].motivoDelRechazo, 'el monto no coincide');
      expect(c.pagos[0].motivoDelRechazo, isNull);
    },
  );

  test(
    'dado un depósito rechazado que tenía validado_en, cuando se lee, ante la duda no se acredita',
    () async {
      await campania('c-1', monto: 1000000);
      await inscripcion('c-1');
      await pago('c-1', 500000, validado: true, rechazado: true);

      final c = (await fuente.leer('col-1')).campanias.single;

      expect(c.pagadoCentavos, 0);
      expect(c.pagos.single.estado, EstadoDePagoDeAlquiler.rechazado);
    },
  );

  /// El ticket `t-<n>` del último depósito de banco, como queda después de un pull.
  Future<void> ticketDelUltimo(String estado, {String? motivo}) => db.customStatement(
    'INSERT INTO ticket (id, tipo, estado, motivo_rechazo, created_at, updated_at) '
    "VALUES ('t-$n', 'DEPOSITO', '$estado', ${motivo == null ? 'NULL' : "'$motivo'"}, 1, 1)",
  );

  test(
    'dado un depósito de banco cuyo ticket rechazó el coordinador, cuando se lee, sale «rechazado» '
    'con su motivo y no cuenta como «por validar»',
    () async {
      await campania('c-1', monto: 1000000);
      await inscripcion('c-1');
      await pago('c-1', 150000, destino: 'BANCO');
      await ticketDelUltimo('RECHAZADO', motivo: 'la foto no se lee');
      await pago('c-1', 200000, destino: 'OFICINA');
      await ticketDelUltimo('PENDIENTE');
      await pago('c-1', 300000, destino: 'BANCO', validado: true);
      await ticketDelUltimo('VALIDADO');

      final c = (await fuente.leer('col-1')).campanias.single;

      expect(c.porValidarCentavos, 200000);
      expect(c.pagadoCentavos, 300000);
      expect(c.saldoCentavos, 700000);
      final rechazado = c.pagos.singleWhere((p) => p.estado == EstadoDePagoDeAlquiler.rechazado);
      expect(rechazado.montoCentavos, 150000);
      expect(rechazado.motivoDelRechazo, 'la foto no se lee');
    },
  );

  test(
    'un ticket rechazado sin motivo no inventa uno, y un depósito ya validado no se rechaza por su '
    'ticket',
    () async {
      await campania('c-1', monto: 1000000);
      await inscripcion('c-1');
      await pago('c-1', 150000, destino: 'BANCO');
      await ticketDelUltimo('RECHAZADO');
      await pago('c-1', 250000, destino: 'BANCO', validado: true);
      await ticketDelUltimo('RECHAZADO');

      final c = (await fuente.leer('col-1')).campanias.single;

      expect(c.pagadoCentavos, 250000);
      expect(c.porValidarCentavos, 0);
      expect(c.pagos.where((p) => p.estado == EstadoDePagoDeAlquiler.rechazado), hasLength(1));
      expect(
        c.pagos.singleWhere((p) => p.estado == EstadoDePagoDeAlquiler.rechazado).motivoDelRechazo,
        isNull,
      );
    },
  );

  test(
    'cuando baja el rechazo del ticket, el Stream avisa y el pago deja de estar «por validar»',
    () async {
      await campania('c-1', monto: 1000000);
      await inscripcion('c-1');
      await pago('c-1', 150000, destino: 'BANCO');
      await ticketDelUltimo('PENDIENTE');
      final emitidos = <int>[];
      final sub = fuente.observar('col-1').listen((a) => emitidos.add(a.porValidarCentavos));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await db.customStatement("UPDATE ticket SET estado = 'RECHAZADO'");
      db.markTablesUpdated({db.tickets});
      await pumpEventQueue();

      expect(emitidos, [150000, 0]);
    },
  );

  test('dado depósitos de casa editora, sin campaña, de otra campaña o dados de baja, cuando se '
      'lee, no cuentan para esta campaña', () async {
    await campania('c-1', monto: 1000000);
    await campania('c-2', monto: 1000000, inicio: '2026-10-01');
    await inscripcion('c-1');
    await pago('c-1', 100000, validado: true, concepto: 'CASA_EDITORA');
    await pago('c-1', 100000, validado: true, baja: true);
    await pago('c-2', 100000, validado: true); // pago a una campaña en la que no está
    await pago('c-1', 250000, validado: true);

    final c = (await fuente.leer('col-1')).campanias.single;

    expect(c.pagos, hasLength(1));
    expect(c.pagadoCentavos, 250000);
  });

  test('dado que pagó \$U 3.000 de un alquiler de \$U 2.500 y el servidor trasladó \$U 500, cuando '
      'se lee, el alquiler queda en 0 y los \$U 500 de más salen de la cuenta', () async {
    await campania('c-1', monto: 250000);
    await inscripcion('c-1');
    await pago('c-1', 300000, validado: true);
    await cuenta(50000);

    final alquiler = await fuente.leer('col-1');
    final c = alquiler.campanias.single;

    expect(c.saldoCentavos, 0);
    expect(c.estaPago, isTrue);
    expect(alquiler.trasladadoCentavos, 50000);
    expect(alquiler.hayTraslado, isTrue);
    expect(alquiler.saldoCentavos, 0);
  });

  group('lo trasladado sale del servidor, no de los pagos (#753)', () {
    test(
      'pagado sobre el monto pero la cuenta todavía no bajó: no se calcula, queda en 0',
      () async {
        await campania('c-1', monto: 250000);
        await inscripcion('c-1');
        await pago('c-1', 300000, validado: true);

        final alquiler = await fuente.leer('col-1');

        expect(alquiler.campanias.single.saldoCentavos, 0);
        expect(alquiler.trasladadoCentavos, 0);
        expect(alquiler.hayTraslado, isFalse);
      },
    );

    test('el servidor manda aunque los pagos digan otra cosa', () async {
      await campania('c-1', monto: 250000);
      await inscripcion('c-1');
      await pago('c-1', 100000, validado: true);
      await cuenta(70000);

      expect((await fuente.leer('col-1')).trasladadoCentavos, 70000);
    });

    test(
      'quien se dio de baja y ya no tiene campañas con alquiler igual lee lo trasladado',
      () async {
        await campania('c-1', monto: 250000);
        await inscripcion('c-1', baja: true);
        await cuenta(250000);

        final alquiler = await fuente.leer('col-1');

        expect(alquiler.hayAlquiler, isFalse);
        expect(alquiler.trasladadoCentavos, 250000);
      },
    );

    test('la cuenta de otra colportora, una dada de baja o un valor negativo no cuentan', () async {
      await cuenta(40000, usuario: 'col-2', id: 'cu-2');
      expect((await fuente.leer('col-1')).trasladadoCentavos, 0);

      await cuenta(30000, baja: true);
      expect((await fuente.leer('col-1')).trasladadoCentavos, 0);

      await db.customStatement(
        "UPDATE cuenta_colportor SET deleted_at = NULL, alquiler_trasladado = -5 WHERE id = 'cu-1'",
      );
      expect((await fuente.leer('col-1')).trasladadoCentavos, 0);
    });

    test(
      'el Stream avisa cuando el pull baja el traslado y cuando se deshace (reactivación)',
      () async {
        await campania('c-1', monto: 250000);
        await inscripcion('c-1');
        await cuenta(0);
        final emitidos = <int>[];
        final sub = fuente.observar('col-1').listen((a) => emitidos.add(a.trasladadoCentavos));
        addTearDown(sub.cancel);
        await pumpEventQueue();

        await db.customStatement('UPDATE cuenta_colportor SET alquiler_trasladado = 50000');
        db.markTablesUpdated({db.cuentasColportor});
        await pumpEventQueue();
        await db.customStatement('UPDATE cuenta_colportor SET alquiler_trasladado = 0');
        db.markTablesUpdated({db.cuentasColportor});
        await pumpEventQueue();

        expect(emitidos, [0, 50000, 0]);
      },
    );
  });

  test('dado que el coordinador cambió el monto después de un pago, cuando se lee, el saldo se '
      'recalcula', () async {
    await campania('c-1', monto: 1000000);
    await inscripcion('c-1');
    await pago('c-1', 600000, validado: true);
    expect((await fuente.leer('col-1')).campanias.single.saldoCentavos, 400000);

    await db.customStatement("UPDATE campania SET alquiler_monto = 500000 WHERE id = 'c-1'");

    final c = (await fuente.leer('col-1')).campanias.single;
    expect(c.saldoCentavos, 0);
  });

  test(
    'dado dos campañas, cuando se lee, cada saldo va por separado y la más nueva primero',
    () async {
      await campania('c-vieja', monto: 1000000, inicio: '2026-03-01');
      await campania('c-nueva', monto: 2000000, inicio: '2026-09-01');
      await inscripcion('c-vieja');
      await inscripcion('c-nueva');
      await pago('c-vieja', 1000000, validado: true);
      await pago('c-nueva', 500000, validado: true);

      final alquiler = await fuente.leer('col-1');

      expect(alquiler.campanias.map((c) => c.campaniaId), ['c-nueva', 'c-vieja']);
      expect(alquiler.campanias.map((c) => c.saldoCentavos), [1500000, 0]);
      expect(alquiler.saldoCentavos, 1500000);
    },
  );

  test(
    'dado que el teléfono bajó datos, cuando se lee, trae la hora de la última bajada',
    () async {
      await campania('c-1', monto: 1000000);
      await inscripcion('c-1');
      expect((await fuente.leer('col-1')).bajadoEn, isNull);

      await DriftSyncMeta(db).write(lastPullAt: DateTime.utc(2026, 11, 21, 21));

      expect((await fuente.leer('col-1')).bajadoEn, DateTime.utc(2026, 11, 21, 21));
    },
  );

  group('el Stream', () {
    test(
      'emite al suscribirse, de nuevo cuando baja un pago validado o cambia el monto, y no repite '
      'lo que no cambió',
      () async {
        await campania('c-1', monto: 1000000);
        await inscripcion('c-1');
        final emitidos = <AlquilerDelColportor>[];
        final sub = fuente.observar('col-1').listen(emitidos.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(emitidos.map((a) => a.saldoCentavos), [1000000]);

        await pago('c-1', 400000, validado: true);
        db.markTablesUpdated({db.depositos});
        await pumpEventQueue();
        expect(emitidos.map((a) => a.saldoCentavos), [1000000, 600000]);

        // Un pago a una campaña que no es de este colportor: no cambia nada que se vea.
        await pago('c-ajena', 100, validado: true);
        db.markTablesUpdated({db.depositos});
        await pumpEventQueue();
        expect(emitidos, hasLength(2));

        await db.customStatement("UPDATE campania SET alquiler_monto = 700000 WHERE id = 'c-1'");
        db.markTablesUpdated({db.campanias});
        await pumpEventQueue();
        expect(emitidos.map((a) => a.saldoCentavos), [1000000, 600000, 300000]);
      },
    );

    test('un pago que el coordinador devolvió deja de contar apenas baja del servidor', () async {
      await campania('c-1', monto: 1000000);
      await inscripcion('c-1');
      await pago('c-1', 400000, validado: true);
      final emitidos = <int>[];
      final sub = fuente.observar('col-1').listen((a) => emitidos.add(a.saldoCentavos));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await db.customStatement('UPDATE deposito SET anulado_at = 9');
      db.markTablesUpdated({db.depositos});
      await pumpEventQueue();

      expect(emitidos, [600000, 1000000]);
    });
  });

  group('el repositorio', () {
    test('si la base falla, el Stream falla con FailureAlquilerNoDisponible y no emite «sin '
        'alquiler»', () async {
      final repo = AlquilerRepositoryImpl(fuente, logger: loggerMudo());
      // Una tabla que falta: la lectura lanza dentro del Stream.
      await db.customStatement('DROP TABLE deposito');

      final emitidos = <AlquilerDelColportor>[];
      final errores = <Object>[];
      final sub = repo.observar('col-1').listen(emitidos.add, onError: errores.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(emitidos, isEmpty);
      expect(errores, isNotEmpty);
      expect(errores.first, isA<FailureAlquilerNoDisponible>());
    });

    test('sin base abierta, falla con FailureAlquilerNoDisponible', () {
      expect(
        const AlquilerSinBase().observar('col-1'),
        emitsError(isA<FailureAlquilerNoDisponible>()),
      );
    });
  });

  group('un pago anulado en las sumas de depósitos', () {
    test('no suma a «Depositado» ni a «por validar», y su efectivo vuelve a «en mano»', () async {
      await pago('c-1', 600000, validado: true, destino: 'BANCO');
      await pago('c-1', 400000, validado: true, anulado: true, destino: 'BANCO');
      final totales = TotalesDeDepositosDrift(db);

      expect(await totales.validado(), 600000);
      expect(await totales.porValidar(), 0);
      expect(await totales.sacadoDeLaMano(), 600000);
      expect((await totales.listar()).map((d) => d.montoCentavos), [600000]);
    });
  });

  group('las campañas a las que puede pagar el alquiler (CampaniaDelAlquilerDrift.enCurso)', () {
    final hoy = DateTime(2026, 11, 22);

    test('si alguna cobra alquiler solo cuentan las que cobran', () async {
      await campania('c-cobra', monto: 1000000, inicio: '2026-09-01', fin: '2026-12-31');
      await campania('c-no-cobra', inicio: '2026-10-01', fin: '2026-12-31');
      await inscripcion('c-cobra');
      await inscripcion('c-no-cobra');

      final lista = await CampaniaDelAlquilerDrift(db).enCurso('col-1', hoy);

      expect(lista.map((c) => c.id), ['c-cobra']);
      expect(await CampaniaDelAlquilerDrift(db).leer('col-1', hoy), 'c-cobra');
    });

    test(
      'si ninguna cobra (o el pull no trajo el monto) cuentan todas, la más nueva primero',
      () async {
        await campania('c-vieja', inicio: '2026-09-01', fin: '2026-12-31');
        await campania('c-nueva', inicio: '2026-11-01', fin: '2026-12-31');
        await inscripcion('c-vieja');
        await inscripcion('c-nueva');

        final lista = await CampaniaDelAlquilerDrift(db).enCurso('col-1', hoy);

        expect(lista.map((c) => c.id), ['c-nueva', 'c-vieja']);
        expect(lista.first.nombre, 'Campaña c-nueva');
      },
    );

    test('una campaña que ya terminó no está en curso', () async {
      await campania('c-1', monto: 1000000, inicio: '2026-03-01', fin: '2026-06-30');
      await inscripcion('c-1');

      expect(await CampaniaDelAlquilerDrift(db).enCurso('col-1', hoy), isEmpty);
    });
  });
}
