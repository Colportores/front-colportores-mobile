// «Registrar depósito» con el ticket en un solo paso contra la base real (#443): AppDatabase en
// memoria, los repositorios de verdad y la transacción de Drift. Y la campaña a la que paga el
// alquiler.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/transaccion_local_drift.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/campania_del_alquiler_drift.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
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

final _ahora = DateTime.utc(2026, 10, 30, 15);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AlmacenDeFotosEnMemoria almacen;
  late RegistrarDepositoConTicketUseCase caso;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    almacen = AlmacenDeFotosEnMemoria();
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
    caso = RegistrarDepositoConTicketUseCase(
      transaccion: TransaccionLocalDrift(db),
      registrarTicket: RegistrarTicketUseCase(tickets, ahora: () => _ahora),
      registrarDeposito: RegistrarDepositoUseCase(depositos, ahora: () => _ahora),
      almacen: almacen,
      ahora: () => _ahora,
    );
  });
  tearDown(() => db.close());

  RegistrarDepositoConTicketParams params({
    String depositoId = 'd-1',
    String ticketId = 't-1',
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
  }) => RegistrarDepositoConTicketParams(
    depositoId: depositoId,
    ticketId: ticketId,
    colportorId: 'col-1',
    montoCentavos: 180000,
    destino: destino,
    concepto: ConceptoDeDeposito.casaEditora,
    foto: destino.llevaTicket ? fotoDePrueba() : null,
    referencia: '004512',
  );

  test('guarda el ticket, su foto y el depósito; encola el ticket antes que el depósito', () async {
    final r = await caso(params());

    expect(r.isRight(), isTrue);
    final ticket = await db.select(db.tickets).getSingle();
    final deposito = await db.select(db.depositos).getSingle();
    expect(ticket.id, 't-1');
    expect(ticket.tipo, 'DEPOSITO');
    expect(deposito.ticketId, 't-1');
    expect(await db.select(db.ticketFotosLocales).get(), hasLength(1));
    expect(almacen.archivos.keys, ['/fotos/t-1.jpg']);
    expect(encolador.encolados.map((c) => c.entidad), ['ticket', 'deposito']);
  });

  test('si el depósito no se puede encolar, el ticket tampoco queda en la base', () async {
    encolador
      ..fallarCon = StateError('cola llena')
      ..fallarDespuesDe = 1;

    final r = await caso(params());

    expect(r.isLeft(), isTrue);
    expect(await db.select(db.tickets).get(), isEmpty);
    expect(await db.select(db.ticketFotosLocales).get(), isEmpty);
    expect(await db.select(db.depositos).get(), isEmpty);
    expect(almacen.archivos, isEmpty, reason: 'la copia de la foto no queda sin su ticket');
  });

  test('el mismo depósito dos veces (doble toque, reintento) queda uno solo', () async {
    await caso(params());
    final otra = await caso(params());

    expect(otra.fold((_) => null, (ok) => ok.yaEstaba), isTrue);
    expect(await db.select(db.tickets).get(), hasLength(1));
    expect(await db.select(db.depositos).get(), hasLength(1));
  });

  test('el retiro por el coordinador queda sin ticket', () async {
    final r = await caso(params(destino: DestinoDeDeposito.retiroCoordinador));

    expect(r.isRight(), isTrue);
    expect(await db.select(db.tickets).get(), isEmpty);
    expect((await db.select(db.depositos).getSingle()).ticketId, isNull);
  });

  group('CampaniaDelAlquilerDrift', () {
    final hoy = DateTime(2026, 11, 10);

    Future<void> campania(String id, String inicio, {String? fin, DateTime? baja}) => db
        .into(db.campanias)
        .insert(
          CampaniasCompanion.insert(
            id: id,
            nombre: 'Campaña $id',
            fechaInicio: inicio,
            fechaFin: Value(fin),
            createdAt: _ahora,
            updatedAt: _ahora,
            deletedAt: Value(baja),
          ),
        );

    Future<void> inscripcion(String campaniaId, {String usuario = 'col-1', DateTime? baja}) => db
        .into(db.campaniasColportor)
        .insert(
          CampaniasColportorCompanion.insert(
            id: 'cc-$campaniaId-$usuario',
            campaniaId: campaniaId,
            usuarioId: usuario,
            createdAt: _ahora,
            updatedAt: _ahora,
            deletedAt: Value(baja),
          ),
        );

    test('sin inscripciones no hay campaña', () async {
      expect(await CampaniaDelAlquilerDrift(db).leer('col-1', hoy), isNull);
    });

    test(
      'la campaña en curso en la que está inscripto, contando el primero y el último día',
      () async {
        await campania('c-1', '2026-11-10', fin: '2026-12-20');
        await inscripcion('c-1');
        expect(await CampaniaDelAlquilerDrift(db).leer('col-1', hoy), 'c-1');

        expect(await CampaniaDelAlquilerDrift(db).leer('col-1', DateTime(2026, 12, 20)), 'c-1');
        expect(await CampaniaDelAlquilerDrift(db).leer('col-1', DateTime(2026, 12, 21)), isNull);
        expect(await CampaniaDelAlquilerDrift(db).leer('col-1', DateTime(2026, 11, 9)), isNull);
      },
    );

    test('una campaña sin fin sigue en curso', () async {
      await campania('c-1', '2026-01-01');
      await inscripcion('c-1');
      expect(await CampaniaDelAlquilerDrift(db).leer('col-1', hoy), 'c-1');
    });

    test('con dos en curso, la que empezó última', () async {
      await campania('c-vieja', '2026-09-01', fin: '2026-12-31');
      await campania('c-nueva', '2026-11-01', fin: '2026-12-31');
      await inscripcion('c-vieja');
      await inscripcion('c-nueva');
      expect(await CampaniaDelAlquilerDrift(db).leer('col-1', hoy), 'c-nueva');
    });

    test('no cuenta campañas dadas de baja, inscripciones dadas de baja ni las de otro', () async {
      await campania('c-baja', '2026-11-01', baja: _ahora);
      await campania('c-1', '2026-11-01');
      await campania('c-2', '2026-11-01');
      await inscripcion('c-baja');
      await inscripcion('c-1', baja: _ahora);
      await inscripcion('c-2', usuario: 'otro');
      expect(await CampaniaDelAlquilerDrift(db).leer('col-1', hoy), isNull);
    });
  });
}
