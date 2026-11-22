// QA del aviso de la foto rechazada para siempre (#443, PR #686) contra la base real: las dos consultas de
// 38A-08 (la que se reintenta y la que ya no) no se pisan en ningún estado de la foto, la foto de un
// ticket que no es de un depósito no cuenta y muchas rechazadas salen en orden estable.
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
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
  late TicketsDeDepositoSinSubirDrift consultas;

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
    consultas = TicketsDeDepositoSinSubirDrift(db);
  });
  tearDown(() => db.close());

  Future<void> depositar(
    String n, {
    DateTime? fecha,
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
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

  Future<List<DateTime>> rechazados() => consultas.observarRechazados().first;
  Future<int> sinSubir() => consultas.observar().first;

  test(
    'los estados de la foto se reparten sin pisarse: espera, reintenta, rechazada, subida',
    () async {
      final dia = DateTime.utc(2026, 11, 9, 15);
      for (var n = 1; n <= 4; n++) {
        await depositar('$n', fecha: dia.subtract(Duration(days: n)));
      }
      // 1: espera su primer intento · 2: reintenta · 3: rechazada · 4: subida.
      await ticketsLocal.anotarIntentoFallido('t-2', codigo: 'red', definitivo: false);
      await ticketsLocal.anotarIntentoFallido('t-3', codigo: 'muy_grande', definitivo: true);
      await ticketsLocal.marcarFotoSubida('t-4', 'col-1/t-4.jpg', _ahora);
      expect(await sinSubir(), 1);
      expect(await rechazados(), [dia.subtract(const Duration(days: 3))]);
    },
  );

  test('un reintento que termina en rechazo pasa de una consulta a la otra', () async {
    await depositar('1', fecha: DateTime.utc(2026, 11, 9, 15));
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
    expect(await sinSubir(), 1);
    expect(await rechazados(), isEmpty);
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true);
    expect(await sinSubir(), 0);
    expect(await rechazados(), hasLength(1));
  });

  test('la foto de un ticket que ningún depósito usa (un cobro) no cuenta', () async {
    await depositar('1', fecha: DateTime.utc(2026, 11, 9, 15));
    await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true);
    await db.delete(db.depositos).go();
    expect(await rechazados(), isEmpty);
  });

  test('el retiro del coordinador (sin ticket) no da aviso', () async {
    await depositar('1', destino: DestinoDeDeposito.retiroCoordinador);
    expect(await rechazados(), isEmpty);
  });

  test('200 rechazadas con la misma fecha salen todas y en el mismo orden cada vez', () async {
    final dia = DateTime.utc(2026, 11, 9, 15);
    for (var i = 0; i < 200; i++) {
      await depositar('$i', fecha: dia);
      await ticketsLocal.anotarIntentoFallido('t-$i', codigo: 'muy_grande', definitivo: true);
    }
    final a = await rechazados();
    final b = await rechazados();
    expect(a, hasLength(200));
    expect(a, b);
    expect(a.every((f) => f == dia), isTrue);
  });

  test('el aviso nace solo del estado de la foto: el motivo escrito no sale', () async {
    await depositar('1', fecha: DateTime.utc(2026, 11, 9, 15));
    await ticketsLocal.anotarIntentoFallido(
      't-1',
      codigo: 'Pedro Pérez 099123456',
      definitivo: true,
    );
    final fechas = await rechazados();
    expect(fechas, hasLength(1));
    expect(fechas.toString(), isNot(contains('Pedro')));
    expect(fechas.toString(), isNot(contains('099123456')));
  });
}
