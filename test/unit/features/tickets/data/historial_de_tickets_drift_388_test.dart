// «Mis tickets» (vista 38B, HU-COB-009, #388) contra la base real: AppDatabase en memoria, los
// repositorios de verdad y lo que baja del servidor escrito a mano (`sync_version`, `estado`,
// `motivo_rechazo`, `validado_en`).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/transaccion_local_drift.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/historial_de_tickets_drift.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/data/repositories/ticket_repository_impl.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
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
  });
  tearDown(() => db.close());

  Future<void> depositar(
    String n, {
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
    ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
    DateTime? fecha,
    TipoDeTarjeta? tarjeta,
  }) async {
    final r = await registrar(
      RegistrarDepositoConTicketParams(
        fecha: fecha,
        depositoId: 'd-$n',
        ticketId: 't-$n',
        colportorId: 'col-1',
        montoCentavos: 100000,
        destino: destino,
        concepto: concepto,
        campaniaId: concepto == ConceptoDeDeposito.alquiler ? 'camp-1' : null,
        foto: destino.llevaTicket ? fotoDePrueba() : null,
        referencia: '00$n',
        tarjetaTipo: tarjeta,
      ),
    );
    expect(r.isRight(), isTrue, reason: '$r');
  }

  /// Lo que hace el servidor al recibir la fila: le pone versión.
  Future<void> llegoAlServidor(String n) async {
    await (db.update(
      db.depositos,
    )..where((d) => d.id.equals('d-$n'))).write(const DepositosCompanion(syncVersion: Value(1)));
    await (db.update(
      db.tickets,
    )..where((t) => t.id.equals('t-$n'))).write(const TicketsCompanion(syncVersion: Value(1)));
  }

  test(
    'un depósito con ticket recién registrado es una sola fila «en cola», con su foto local',
    () async {
      await depositar('1', tarjeta: TipoDeTarjeta.debito);

      final h = await historial.leer();

      expect(h.items, hasLength(1));
      final item = h.items.single;
      expect(item.id, 'd-1');
      expect(item.ticketId, 't-1');
      expect(item.estado, EstadoDelItem.enCola);
      expect(item.lugar, LugarDelTicket.banco);
      expect(item.concepto, ConceptoDeDeposito.casaEditora);
      expect(item.numeroAutorizacion, '001');
      expect(item.tarjetaTipo, TipoDeTarjeta.debito);
      expect(item.hayCopiaLocal, isTrue);
      expect(item.fotoSubida, isFalse);
      expect(h.bajadoEn, isNull, reason: 'el teléfono todavía no bajó nada');
    },
  );

  test(
    'cuando llega al servidor espera la validación; el coordinador lo valida o lo rechaza',
    () async {
      await depositar('1');
      await depositar('2');
      await depositar('3', concepto: ConceptoDeDeposito.alquiler);
      await llegoAlServidor('1');
      await llegoAlServidor('2');
      await llegoAlServidor('3');
      // El pull trae lo que decidió el coordinador.
      await (db.update(db.depositos)..where((d) => d.id.equals('d-2'))).write(
        DepositosCompanion(validadoEn: Value(DateTime.utc(2026, 11, 11, 15))),
      );
      await (db.update(
        db.tickets,
      )..where((t) => t.id.equals('t-2'))).write(const TicketsCompanion(estado: Value('VALIDADO')));
      await (db.update(db.tickets)..where((t) => t.id.equals('t-3'))).write(
        const TicketsCompanion(
          estado: Value('RECHAZADO'),
          motivoRechazo: Value('La foto no se lee'),
        ),
      );

      final porId = {for (final i in (await historial.leer()).items) i.id: i};

      expect(porId['d-1']!.estado, EstadoDelItem.porValidar);
      expect(porId['d-2']!.estado, EstadoDelItem.validado);
      expect(porId['d-2']!.validadoEn, DateTime.utc(2026, 11, 11, 15));
      expect(porId['d-3']!.estado, EstadoDelItem.rechazado);
      expect(porId['d-3']!.motivoRechazo, 'La foto no se lee');
      expect(porId['d-3']!.concepto, ConceptoDeDeposito.alquiler);
    },
  );

  test('un retiro por el coordinador es una fila sin ticket', () async {
    await depositar('1', destino: DestinoDeDeposito.retiroCoordinador);

    final item = (await historial.leer()).items.single;

    expect(item.lugar, LugarDelTicket.retiro);
    expect(item.ticketId, isNull);
    expect(item.hayCopiaLocal, isFalse);
    expect(item.estado, EstadoDelItem.enCola);
  });

  test('un ticket de un cobro con tarjeta (sin depósito) sale como fila propia', () async {
    await depositar('1');
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't-cobro',
            tipo: 'COBRO_TARJETA',
            createdAt: _ahora,
            updatedAt: _ahora,
            monto: const Value(150000),
            fecha: Value(DateTime.utc(2026, 11, 9, 15)),
            numeroAutorizacion: const Value('9981'),
            tarjetaTipo: const Value('CREDITO'),
            syncVersion: const Value(2),
          ),
        );

    final items = (await historial.leer()).items;

    expect(items.map((i) => i.id), ['d-1', 't-cobro'], reason: 'el de hoy primero');
    final cobro = items.last;
    expect(cobro.lugar, LugarDelTicket.cobroConTarjeta);
    expect(cobro.depositoId, isNull);
    expect(cobro.tarjetaTipo, TipoDeTarjeta.credito);
    expect(cobro.estado, EstadoDelItem.porValidar);
    expect(cobro.hayCopiaLocal, isFalse);
  });

  test('el ticket de un depósito no aparece dos veces', () async {
    await depositar('1');
    await depositar('2');

    final h = await historial.leer();

    expect(h.items.map((i) => i.id).toSet(), {'d-1', 'd-2'});
    expect(h.items, hasLength(2));
  });

  test('un depósito dado de baja no aparece, ni su ticket como si fuera suelto', () async {
    await depositar('1');
    await depositar('2');
    await (db.update(
      db.depositos,
    )..where((d) => d.id.equals('d-2'))).write(DepositosCompanion(deletedAt: Value(_ahora)));

    final items = (await historial.leer()).items;

    expect(items.map((i) => i.id), ['d-1']);
  });

  test('un ticket dado de baja no aparece; su depósito queda sin ticket', () async {
    await depositar('1');
    await (db.update(
      db.tickets,
    )..where((t) => t.id.equals('t-1'))).write(TicketsCompanion(deletedAt: Value(_ahora)));

    final item = (await historial.leer()).items.single;

    expect(item.id, 'd-1');
    expect(item.numeroAutorizacion, isNull);
    expect(item.hayCopiaLocal, isTrue, reason: 'la copia de la foto sigue en el teléfono');
  });

  test('la fila más nueva va primero; con la misma fecha, la de id más alto (UUID v7: la que se cargó después)', () async {
    await depositar('1', fecha: DateTime.utc(2026, 11, 1, 15));
    await depositar('3', fecha: DateTime.utc(2026, 11, 8, 15));
    await depositar('2', fecha: DateTime.utc(2026, 11, 8, 15));

    final items = (await historial.leer()).items;

    expect(items.map((i) => i.id), ['d-3', 'd-2', 'd-1']);
  });

  test('sin nada registrado: lista vacía', () async {
    expect((await historial.leer()).items, isEmpty);
  });

  test('trae la última bajada del servidor', () async {
    await DriftSyncMeta(db).write(lastPullAt: _ahora);

    expect((await historial.leer()).bajadoEn, _ahora);
  });

  test(
    'observar: emite el estado de ahora y de nuevo con cada cambio, sin pasar por la lista vacía',
    () async {
      final primero = await historial.observar().first;
      expect(primero.items, isEmpty);

      final conUno = historial.observar().firstWhere((h) => h.items.length == 1);
      await depositar('1');
      expect(
        (await conUno.timeout(const Duration(seconds: 5))).items.single.estado,
        EstadoDelItem.enCola,
      );

      final validado = historial.observar().firstWhere(
        (h) => h.items.isNotEmpty && h.items.first.estado == EstadoDelItem.validado,
      );
      await (db.update(db.depositos)..where((d) => d.id.equals('d-1'))).write(
        DepositosCompanion(validadoEn: Value(_ahora), syncVersion: const Value(1)),
      );
      await (db.update(
        db.tickets,
      )..where((t) => t.id.equals('t-1'))).write(const TicketsCompanion(syncVersion: Value(1)));
      expect((await validado.timeout(const Duration(seconds: 5))).items.single.validadoEn, _ahora);
    },
  );
}
