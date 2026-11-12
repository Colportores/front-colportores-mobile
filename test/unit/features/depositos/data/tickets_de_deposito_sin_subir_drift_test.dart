// 38A-08 contra la base real (#443, decisión «Ticket dep.» del 10/11): cuántos tickets de depósito no
// pudieron subir su foto. Cuenta solo los pendientes con un intento fallido de depósitos vivos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/transaccion_local_drift.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/tickets_de_deposito_sin_subir_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/data/repositories/ticket_repository_impl.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/registrar_ticket_use_case.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/tickets_falsos.dart';

final _ahora = DateTime.utc(2026, 11, 10, 15);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TicketLocalDataSourceDrift ticketsLocal;
  late RegistrarDepositoConTicketUseCase registrar;
  late TicketsDeDepositoSinSubirDrift sinSubir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final almacen = AlmacenDeFotosEnMemoria();
    ticketsLocal = TicketLocalDataSourceDrift(db, encolador: encolador);
    final tickets = TicketRepositoryImpl(
      ticketsLocal,
      almacen,
      logger: loggerMudo(),
      ahora: () => _ahora,
    );
    final depositos = DepositoRepositoryImpl(
      DepositoLocalDataSourceDrift(db, encolador: encolador),
      logger: loggerMudo(),
    );
    registrar = RegistrarDepositoConTicketUseCase(
      transaccion: TransaccionLocalDrift(db),
      registrarTicket: RegistrarTicketUseCase(tickets, ahora: () => _ahora),
      registrarDeposito: RegistrarDepositoUseCase(depositos, ahora: () => _ahora),
      almacen: almacen,
      ahora: () => _ahora,
    );
    sinSubir = TicketsDeDepositoSinSubirDrift(db);
  });
  tearDown(() => db.close());

  Future<void> depositar(
    String n, {
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
    DateTime? fecha,
  }) async {
    final r = await registrar(
      RegistrarDepositoConTicketParams(
        fecha: fecha,
        depositoId: 'd-$n',
        ticketId: 't-$n',
        colportorId: 'col-1',
        montoCentavos: 100000,
        destino: destino,
        concepto: ConceptoDeDeposito.casaEditora,
        foto: destino.llevaTicket ? fotoDePrueba() : null,
      ),
    );
    expect(r.isRight(), isTrue);
  }

  Future<int> contar() => sinSubir.observar().first;

  test('recién registrado, la foto espera su primer intento: no es una falla', () async {
    await depositar('1');
    expect(await contar(), 0);
  });

  test('un intento fallido que se reintenta cuenta; el retiro (sin ticket) no', () async {
    await depositar('1');
    await depositar('2', destino: DestinoDeDeposito.retiroCoordinador);
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
    expect(await contar(), 1);
  });

  test('cuando la foto sube, deja de contar', () async {
    await depositar('1');
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
    await ticketsLocal.marcarFotoSubida('t-1', 'col-1/t-1.jpg', _ahora);
    expect(await contar(), 0);
  });

  test('dos depósitos con la foto trabada cuentan dos; uno borrado no cuenta', () async {
    await depositar('1');
    await depositar('2');
    await depositar('3');
    for (final t in ['t-1', 't-2', 't-3']) {
      await ticketsLocal.anotarIntentoFallido(t, codigo: 'red', definitivo: false);
    }
    await (db.update(
      db.depositos,
    )..where((d) => d.id.equals('d-3'))).write(DepositosCompanion(deletedAt: Value(_ahora)));
    expect(await contar(), 2);
  });

  test('rechazada para siempre no entra en «lo reintentamos solo»', () async {
    await depositar('1');
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true);
    expect(await contar(), 0);
  });

  test('avisa cada cambio, sin repetir el mismo número', () async {
    await depositar('1');
    final vistos = <int>[];
    final escucha = sinSubir.observar().listen(vistos.add);
    await pumpEventQueue();
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
    await pumpEventQueue();
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
    await pumpEventQueue();
    await ticketsLocal.marcarFotoSubida('t-1', 'col-1/t-1.jpg', _ahora);
    await pumpEventQueue();
    await escucha.cancel();
    expect(vistos, [0, 1, 0]);
  });

  group('rechazadas para siempre (P1 del 10/11)', () {
    Future<List<DateTime>> rechazados() => sinSubir.observarRechazados().first;
    final dia8 = DateTime.utc(2026, 11, 8, 15);
    final dia9 = DateTime.utc(2026, 11, 9, 15);

    test('sin rechazos no hay fechas; un intento que se reintenta no es un rechazo', () async {
      await depositar('1');
      await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
      expect(await rechazados(), isEmpty);
    });

    test('la rechazada da la fecha de su depósito, y no cuenta para 38A-08', () async {
      await depositar('1', fecha: dia9);
      await ticketsLocal.anotarIntentoFallido(
        't-1',
        codigo: 'copia_local_ausente',
        definitivo: true,
      );
      expect(await rechazados(), [dia9]);
      expect(await contar(), 0);
    });

    test(
      'varias, la más vieja primero; borrado, validado o rechazado por el coordinador no cuenta',
      () async {
        await depositar('1', fecha: dia9);
        await depositar('2', fecha: dia8);
        await depositar('3', fecha: dia8);
        await depositar('4', fecha: dia8);
        await depositar('5', fecha: dia8);
        for (final t in ['t-1', 't-2', 't-3', 't-4', 't-5']) {
          await ticketsLocal.anotarIntentoFallido(t, codigo: 'muy_grande', definitivo: true);
        }
        await (db.update(
          db.depositos,
        )..where((d) => d.id.equals('d-3'))).write(DepositosCompanion(deletedAt: Value(_ahora)));
        await (db.update(
          db.depositos,
        )..where((d) => d.id.equals('d-4'))).write(DepositosCompanion(validadoEn: Value(_ahora)));
        await (db.update(
          db.depositos,
        )..where((d) => d.id.equals('d-5'))).write(DepositosCompanion(rechazadoEn: Value(_ahora)));
        expect(await rechazados(), [dia8, dia9]);
      },
    );

    test('avisa cuando aparece una, sin repetir', () async {
      await depositar('1', fecha: dia9);
      final vistos = <List<DateTime>>[];
      final escucha = sinSubir.observarRechazados().listen(vistos.add);
      await pumpEventQueue();
      await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
      await pumpEventQueue();
      await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true);
      await pumpEventQueue();
      await escucha.cancel();
      expect(vistos, [
        <DateTime>[],
        [dia9],
      ]);
    });
  });
}
