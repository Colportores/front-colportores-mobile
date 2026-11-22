// Lo validado y lo «por validar» de los depósitos (#596, «Acredita V1»), contra la tabla real: la
// suma de cada estado, lo que no cuenta (rechazados, dados de baja) y el `Stream` que avisa cuando
// baja del servidor una validación o un rechazo. Insumo de Mi Cuenta (33A) y de Mi plata (33C).
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/totales_de_depositos_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/totales_de_depositos.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

int _ms(DateTime f) => f.toUtc().millisecondsSinceEpoch;

final _hace3Dias = DateTime.utc(2026, 10, 27, 12);
final _hace10Dias = DateTime.utc(2026, 10, 20, 12);
final _corte = DateTime.utc(2026, 10, 23, 12);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DepositoRepositoryImpl repo;
  late TotalesDeDepositosDrift totales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    totales = TotalesDeDepositosDrift(db);
    repo = DepositoRepositoryImpl(
      DepositoLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria()),
      logger: loggerMudo(),
    );
  });
  tearDown(() => db.close());

  /// Una fila de `deposito` como queda después de un pull.
  Future<void> poner(
    String id,
    int monto, {
    DateTime? validadoEn,
    DateTime? rechazadoEn,
    String? motivo,
    DateTime? baja,
    String destino = 'BANCO',
  }) => db.customStatement(
    'INSERT INTO deposito (id, monto, fecha, destino, concepto, ticket_id, validado_en, '
    'rechazado_en, motivo_rechazo, created_at, updated_at, deleted_at) '
    "VALUES ('$id', $monto, 1, '$destino', 'CASA_EDITORA', "
    "${destino == 'RETIRO_COORDINADOR' ? 'NULL' : "'t-$id'"}, "
    '${validadoEn == null ? 'NULL' : _ms(validadoEn)}, '
    '${rechazadoEn == null ? 'NULL' : _ms(rechazadoEn)}, '
    "${motivo == null ? 'NULL' : "'$motivo'"}, 1, 1, "
    '${baja == null ? 'NULL' : _ms(baja)})',
  );

  test('dado que no hay depósitos, cuando se suma, todo es cero', () async {
    expect(
      await totales.leer(),
      const TotalesDeDepositos(validadoCentavos: 0, porValidarCentavos: 0),
    );
  });

  test('dado depósitos en cada estado, cuando se suma, «validado» cuenta solo lo validado y «por '
      'validar» lo que no respondió nadie; lo rechazado no suma a ninguno', () async {
    await poner('d-1', 100000, validadoEn: _hace3Dias);
    await poner('d-2', 50000, validadoEn: _hace10Dias);
    await poner('d-3', 30000);
    await poner('d-4', 20000);
    await poner(
      'd-5',
      600000,
      destino: 'RETIRO_COORDINADOR',
      rechazadoEn: _hace3Dias,
      motivo: 'Recibí menos',
    );

    final t = await totales.leer();

    expect(t.validadoCentavos, 150000);
    expect(t.porValidarCentavos, 50000);
  });

  test('un depósito dado de baja no suma a nada', () async {
    await poner('d-1', 100000, validadoEn: _hace3Dias, baja: _hace3Dias);
    await poner('d-2', 70000, baja: _hace3Dias);

    final t = await totales.leer();

    expect(t.validadoCentavos, 0);
    expect(t.porValidarCentavos, 0);
  });

  test('con las dos marcas (no debería pasar) no se acredita: cuenta como rechazado', () async {
    await poner('d-1', 100000, validadoEn: _hace3Dias, rechazadoEn: _hace3Dias, motivo: 'x');

    final t = await totales.leer();

    expect(t.validadoCentavos, 0);
    expect(t.porValidarCentavos, 0);
  });

  test(
    '«hasta» deja afuera lo que se validó después: la base de «contra la semana pasada»',
    () async {
      await poner('d-1', 100000, validadoEn: _hace10Dias);
      await poner('d-2', 50000, validadoEn: _hace3Dias);

      expect(await totales.validado(), 150000);
      expect(await totales.validado(hasta: _corte), 100000);
      // El borde es inclusivo: validado justo en el corte ya estaba.
      expect(await totales.validado(hasta: _hace10Dias), 100000);
      expect(
        await totales.validado(hasta: _hace10Dias.subtract(const Duration(milliseconds: 1))),
        0,
      );
    },
  );

  test('montos que no entran en 32 bits se suman bien (SQLite usa 64)', () async {
    await poner('d-1', 2147483647, validadoEn: _hace3Dias);
    await poner('d-2', 2147483647, validadoEn: _hace3Dias);

    expect((await totales.validado()), 4294967294);
  });

  test('el repositorio devuelve los totales y cada depósito con su estado', () async {
    await poner('d-1', 100000, validadoEn: _hace3Dias);
    await poner(
      'd-2',
      600000,
      destino: 'RETIRO_COORDINADOR',
      rechazadoEn: _hace3Dias,
      motivo: 'Recibí menos',
    );
    await poner('d-3', 30000);

    final t = (await repo.totales()).getOrElse(() => throw StateError('falló'));
    final lista = (await repo.todos()).getOrElse(() => throw StateError('falló'));

    expect(t.validadoCentavos, 100000);
    expect(t.porValidarCentavos, 30000);
    expect(
      {for (final d in lista) d.id: d.estado},
      {
        'd-1': EstadoDeDeposito.validado,
        'd-2': EstadoDeDeposito.rechazado,
        'd-3': EstadoDeDeposito.porValidar,
      },
    );
    expect(lista.firstWhere((d) => d.id == 'd-2').motivoRechazo, 'Recibí menos');
  });

  test('observar emite al suscribirse y de nuevo cuando baja una validación', () async {
    await poner('d-1', 100000);
    final emisiones = <List<Deposito>>[];
    final suscripcion = repo.observar().listen(emisiones.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();
    expect(emisiones.last.single.estado, EstadoDeDeposito.porValidar);

    // Lo que hace el pull: la misma fila con la validación, por la API de Drift (avisa a quien mira).
    await (db.update(db.depositos)..where((d) => d.id.equals('d-1'))).write(
      DepositosCompanion(validadoEn: Value(_hace3Dias), validadoPor: const Value('coord-1')),
    );
    await pumpEventQueue();

    expect(emisiones.last.single.estado, EstadoDeDeposito.validado);
  });

  test(
    'si la tabla no se puede leer, no devuelve ceros: falla con FailureDepositoNoDisponible',
    () async {
      await db.customStatement('DROP TABLE deposito');

      final t = await repo.totales();
      final lista = await repo.todos();

      expect(t.fold((f) => f, (_) => null), isA<FailureDepositoNoDisponible>());
      expect(lista.fold((f) => f, (_) => null), isA<FailureDepositoNoDisponible>());
      await expectLater(repo.observar(), emitsError(isA<FailureDepositoNoDisponible>()));
    },
  );
}
