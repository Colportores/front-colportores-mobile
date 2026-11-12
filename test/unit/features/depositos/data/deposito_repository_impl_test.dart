// El repositorio de depósitos traduce todo a un Failure y no filtra datos al log (HU-CTA-004, #442).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

class _Capturador extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final _ahora = DateTime.utc(2026, 10, 30, 12);

Deposito _deposito(String id, {String ticketId = 't-1'}) => Deposito(
  id: id,
  montoCentavos: 987654,
  fecha: _ahora,
  destino: DestinoDeDeposito.banco,
  concepto: ConceptoDeDeposito.casaEditora,
  ticketId: ticketId,
  auditoria: Auditoria(createdAt: _ahora, updatedAt: _ahora, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late _Capturador salida;
  late DepositoRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    salida = _Capturador();
    repo = DepositoRepositoryImpl(
      DepositoLocalDataSourceDrift(db, encolador: encolador),
      logger: AppLogger(output: salida),
    );
  });
  tearDown(() => db.close());

  test('dado un depósito, cuando se registra, devuelve el depósito registrado', () async {
    final r = await repo.registrar(_deposito('d-1'));

    final registrado = r.getOrElse(() => throw StateError('falló'));
    expect(registrado.deposito.id, 'd-1');
    expect(registrado.yaEstaba, isFalse);
  });

  test('dado un ticket ya usado, cuando se registra otro depósito con él, es '
      'FailureDepositoTicketYaUsado y se loguea sin datos', () async {
    await repo.registrar(_deposito('d-1'));

    final r = await repo.registrar(_deposito('d-2'));

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureDepositoTicketYaUsado>());
    final todo = salida.lineas.join('\n');
    expect(todo, contains('DEPOSITO_ALTA_RECHAZADO'));
    expect(todo, isNot(contains('987654')));
  });

  test('dado una falla cualquiera, cuando se registra, es «No pudimos registrar el depósito» y no '
      'filtra el dato al log ni a la falla', () async {
    encolador.fallarCon = StateError('INSERT INTO deposito ... monto = 987654 ticket = SECRETO-77');

    final r = await repo.registrar(_deposito('d-1'));

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureDepositoNoGuardado>());
    expect(falla!.mensaje, 'No pudimos registrar el depósito. No cambió nada.');
    expect((falla as FailureDepositoNoGuardado).causa, 'StateError');
    final todo = salida.lineas.join('\n');
    expect(todo, contains('DEPOSITO_ALTA_FAIL'));
    expect(todo, isNot(contains('SECRETO-77')));
    expect(todo, isNot(contains('987654')));
    expect('$falla', isNot(contains('SECRETO-77')));
  });

  test('dado que falló, cuando se reintenta con el mismo id, registra una sola vez', () async {
    encolador.fallarCon = StateError('motor apagado');
    expect((await repo.registrar(_deposito('d-1'))).isLeft(), isTrue);
    encolador.fallarCon = null;

    final primero = await repo.registrar(_deposito('d-1'));
    final segundo = await repo.registrar(_deposito('d-1'));

    expect(primero.getOrElse(() => throw StateError('falló')).yaEstaba, isFalse);
    expect(segundo.getOrElse(() => throw StateError('falló')).yaEstaba, isTrue);
    expect(encolador.encolados, hasLength(1));
    expect((await repo.todos()).getOrElse(() => throw StateError('falló')), hasLength(1));
  });

  test('dado depósitos guardados, cuando se leen, vienen en una lista', () async {
    await repo.registrar(_deposito('d-1', ticketId: 't-1'));
    await repo.registrar(_deposito('d-2', ticketId: 't-2'));

    final r = await repo.todos();

    expect(r.getOrElse(() => throw StateError('falló')).map((d) => d.id), ['d-2', 'd-1']);
  });

  test(
    'dado que la base no se puede leer, cuando se leen los depósitos, es FailureDepositoNoDisponible '
    '(no «nada depositado»)',
    () async {
      await db.customStatement('DROP TABLE deposito');

      final r = await repo.todos();

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureDepositoNoDisponible>());
      expect(salida.lineas.join('\n'), contains('DEPOSITO_LECTURA_FAIL'));
    },
  );
}
