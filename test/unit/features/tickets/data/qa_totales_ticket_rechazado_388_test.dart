// QA #388 (r4): un depósito de banco cuyo TICKET el coordinador rechazó (`ticket.estado = RECHAZADO`)
// tiene que dejar de sumar a «Por validar» y a «lo depositado» en Mi Cuenta y volver a «En mano», como
// `efectivo_en_mano()` del servidor (migración 0152). Si no, «Cargar de nuevo» (38B·02) abre el
// formulario con ese monto y «Tenés $ 0 en mano» apaga el botón: la persona no puede corregir el ticket.
//
// Contra la base real (AppDatabase en memoria) y el arnés de `historial_de_tickets_drift_388_test`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/transaccion_local_drift.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/totales_de_depositos_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/historial_de_tickets_drift.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/data/repositories/ticket_repository_impl.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
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
  late RegistrarDepositoConTicketUseCase registrar;
  late HistorialDeTicketsDrift historial;
  late TotalesDeDepositosDrift totales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final almacen = AlmacenDeFotosEnMemoria();
    final tickets = TicketRepositoryImpl(
      TicketLocalDataSourceDrift(db, encolador: encolador),
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
    historial = HistorialDeTicketsDrift(db);
    totales = TotalesDeDepositosDrift(db);
  });
  tearDown(() => db.close());

  /// Un depósito de banco de $ 1.000 que ya llegó al servidor, con su ticket.
  Future<void> depositoEnElServidor() async {
    final r = await registrar(
      RegistrarDepositoConTicketParams(
        depositoId: 'd-1',
        ticketId: 't-1',
        colportorId: 'col-1',
        montoCentavos: 100000,
        destino: DestinoDeDeposito.banco,
        concepto: ConceptoDeDeposito.casaEditora,
        foto: fotoDePrueba(),
        referencia: '001',
      ),
    );
    expect(r.isRight(), isTrue, reason: '$r');
    await (db.update(
      db.depositos,
    )..where((d) => d.id.equals('d-1'))).write(const DepositosCompanion(syncVersion: Value(1)));
    await (db.update(
      db.tickets,
    )..where((t) => t.id.equals('t-1'))).write(const TicketsCompanion(syncVersion: Value(1)));
  }

  Future<void> elCoordinador(String estado, {String? motivo}) =>
      (db.update(db.tickets)..where((t) => t.id.equals('t-1'))).write(
        TicketsCompanion(estado: Value(estado), motivoRechazo: Value(motivo)),
      );

  test('línea base: el depósito por validar suma a «Por validar» y sale de la mano', () async {
    await depositoEnElServidor();

    expect(await totales.porValidar(), 100000);
    expect(await totales.sacadoDeLaMano(), 100000);
    expect(await totales.listar(), hasLength(1));
  });

  test('línea base: el historial ya cuenta ese depósito como «Rechazado» y recargable', () async {
    await depositoEnElServidor();
    await elCoordinador('RECHAZADO', motivo: 'La foto no se lee');

    final item = (await historial.leer()).items.single;

    expect(item.estado, EstadoDelItem.rechazado);
    expect(item.sePuedeCargarDeNuevo, isTrue);
  });

  test('un depósito cuyo ticket se rechazó no suma a «Por validar» ni a lo depositado, y su plata '
      'vuelve a la mano (como efectivo_en_mano() del servidor)', () async {
    await depositoEnElServidor();
    await elCoordinador('RECHAZADO', motivo: 'La foto no se lee');

    expect(await totales.porValidar(), 0, reason: 'el historial lo dice «No se acreditó»');
    expect(await totales.validado(), 0);
    expect(
      await totales.sacadoDeLaMano(),
      0,
      reason: 'si no, «Cargar de nuevo» dice «\$ 0 en mano»',
    );
    expect(await totales.listar(), isEmpty);
  });

  test(
    'un depósito validado cuyo ticket quedó rechazado tampoco acredita (ante la duda, no)',
    () async {
      await depositoEnElServidor();
      await (db.update(
        db.depositos,
      )..where((d) => d.id.equals('d-1'))).write(DepositosCompanion(validadoEn: Value(_ahora)));
      await elCoordinador('RECHAZADO', motivo: 'La foto no se lee');

      expect(await totales.validado(), 0);
      expect(await totales.porValidar(), 0);
      expect(await totales.sacadoDeLaMano(), 0);
    },
  );

  test('un ticket pendiente o validado no cambia nada: el depósito sigue sumando', () async {
    await depositoEnElServidor();
    await elCoordinador('VALIDADO');
    await (db.update(
      db.depositos,
    )..where((d) => d.id.equals('d-1'))).write(DepositosCompanion(validadoEn: Value(_ahora)));

    expect(await totales.validado(), 100000);
    expect(await totales.sacadoDeLaMano(), 100000);
    expect((await totales.listar()).single.validado, isTrue);
  });

  test(
    'Mi Cuenta se entera cuando baja el rechazo del ticket, sin que cambie el depósito',
    () async {
      await depositoEnElServidor();
      final tablas = totales.tablas;

      expect(tablas, containsAll([db.depositos, db.tickets]));
    },
  );

  test(
    'el pago de alquiler devuelto sale del historial como «Devuelto», no como «Validado»',
    () async {
      await depositoEnElServidor();
      await elCoordinador('VALIDADO');
      await (db.update(db.depositos)..where((d) => d.id.equals('d-1'))).write(
        DepositosCompanion(validadoEn: Value(_ahora), anuladoAt: Value(_ahora)),
      );

      final item = (await historial.leer()).items.single;

      expect(item.estado, EstadoDelItem.devuelto);
      expect(item.validadoEn, isNull);
      expect(item.sePuedeCargarDeNuevo, isFalse);
      expect(await totales.validado(), 0);
      expect(await totales.sacadoDeLaMano(), 0, reason: 'su efectivo vuelve a estar en mano');
    },
  );

  test(
    'recargar un rechazado deja las dos filas en el historial: el rechazado y el nuevo en cola',
    () async {
      await depositoEnElServidor();
      await elCoordinador('RECHAZADO', motivo: 'La foto no se lee');
      // «Cargar de nuevo» registra otro depósito `d-2`/`t-2`; el rechazado queda en el historial.
      final r = await registrar(
        RegistrarDepositoConTicketParams(
          depositoId: 'd-2',
          ticketId: 't-2',
          colportorId: 'col-1',
          montoCentavos: 100000,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.casaEditora,
          foto: fotoDePrueba(),
          referencia: '002',
        ),
      );
      expect(r.isRight(), isTrue, reason: '$r');

      final items = (await historial.leer()).items;

      expect(items, hasLength(2));
      expect(
        items.map((i) => i.estado),
        containsAll([EstadoDelItem.rechazado, EstadoDelItem.enCola]),
      );
    },
  );
}
