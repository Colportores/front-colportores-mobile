// «Cargar de nuevo» del ticket rechazado de un cobro con tarjeta (#728, regla R7) contra las tablas
// reales: el historial dice a qué cobro vivo está ligado cada ticket suelto y lo lee para precargar la
// foto del ticket (vista 29 C).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/historial_de_tickets_drift.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/tickets_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TicketLocalDataSourceDrift local;
  late HistorialDeTicketsDrift historial;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = TicketLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
    historial = HistorialDeTicketsDrift(db);
  });
  tearDown(() => db.close());

  Future<void> cobro(String id, {DateTime? anulado, DateTime? baja}) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: 'v-1',
          monto: 150000,
          medio: 'TARJETA',
          fecha: ahoraTicket,
          tarjetaTipo: const Value('CREDITO'),
          tarjetaMarca: const Value('Visa'),
          numeroAprobacion: const Value('123456'),
          createdAt: ahoraTicket,
          updatedAt: ahoraTicket,
          anuladoAt: Value(anulado),
          deletedAt: Value(baja),
        ),
      );

  Future<void> ticket(String id, {String? cobroId}) =>
      local.registrar(ticketDePrueba(id), fotoLocalDePrueba(id), cobroId: cobroId);

  Future<void> rechazar(String id) => (db.update(db.tickets)..where((t) => t.id.equals(id))).write(
    const TicketsCompanion(estado: Value('RECHAZADO'), syncVersion: Value(2)),
  );

  Future<ItemDelHistorial> item(String ticketId) async =>
      (await historial.leer()).items.firstWhere((i) => i.ticketId == ticketId);

  test('el ticket rechazado ligado a su cobro vivo se puede cargar de nuevo', () async {
    await cobro('c-1');
    await ticket('t-1', cobroId: 'c-1');
    await rechazar('t-1');

    final i = await item('t-1');

    expect(i.lugar, LugarDelTicket.cobroConTarjeta);
    expect(i.estado, EstadoDelItem.rechazado);
    expect(i.cobroId, 'c-1');
    expect(i.sePuedeCargarDeNuevo, isTrue);
  });

  test('si el cobro se anuló, el ticket rechazado no ofrece cargar de nuevo', () async {
    await cobro('c-1', anulado: ahoraTicket);
    await ticket('t-1', cobroId: 'c-1');
    await rechazar('t-1');

    final i = await item('t-1');

    expect(i.cobroId, isNull);
    expect(i.sePuedeCargarDeNuevo, isFalse);
  });

  test('si el cobro se dio de baja, tampoco', () async {
    await cobro('c-1');
    await ticket('t-1', cobroId: 'c-1');
    await rechazar('t-1');
    await (db.update(
      db.cobranzas,
    )..where((c) => c.id.equals('c-1'))).write(CobranzasCompanion(deletedAt: Value(ahoraTicket)));

    expect((await item('t-1')).sePuedeCargarDeNuevo, isFalse);
  });

  test('un ticket que no está ligado a ningún cobro no ofrece cargar de nuevo', () async {
    await ticket('t-1');
    await rechazar('t-1');

    expect((await item('t-1')).cobroId, isNull);
    expect((await item('t-1')).sePuedeCargarDeNuevo, isFalse);
  });

  test('cargado el ticket nuevo, el rechazado queda en el historial sin el botón', () async {
    await cobro('c-1');
    await ticket('t-1', cobroId: 'c-1');
    await rechazar('t-1');
    await ticket('t-2', cobroId: 'c-1');

    final h = await historial.leer();

    expect(h.items.map((i) => i.ticketId), containsAll(['t-1', 't-2']));
    final viejo = h.items.firstWhere((i) => i.ticketId == 't-1');
    final nuevo = h.items.firstWhere((i) => i.ticketId == 't-2');
    expect(viejo.estado, EstadoDelItem.rechazado);
    expect(viejo.sePuedeCargarDeNuevo, isFalse, reason: 'el cobro ya tiene el ticket nuevo');
    expect(nuevo.cobroId, 'c-1');
    expect(nuevo.sePuedeCargarDeNuevo, isFalse, reason: 'el nuevo no está rechazado');
  });

  test('el historial avisa cuando el cobro cambia de ticket', () async {
    await cobro('c-1');
    await ticket('t-1', cobroId: 'c-1');
    await rechazar('t-1');

    final emitidos = <bool>[];
    final escucha = historial.observar().listen(
      (h) => emitidos.add(h.items.firstWhere((i) => i.ticketId == 't-1').sePuedeCargarDeNuevo),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await ticket('t-2', cobroId: 'c-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await escucha.cancel();

    expect(emitidos.first, isTrue);
    expect(emitidos.last, isFalse);
  });

  group('cobroConTarjeta', () {
    test('devuelve el cobro con lo que se precarga en la foto del ticket', () async {
      await cobro('c-1');

      final c = await historial.cobroConTarjeta('c-1');

      expect(c, isNotNull);
      expect(c!.id, 'c-1');
      expect(c.montoCentavos, 150000);
      expect(c.medio, MedioCobranza.tarjeta);
      expect(c.tarjetaTipo, TipoTarjeta.credito);
      expect(c.tarjetaMarca, 'Visa');
      expect(c.numeroAprobacion, '123456');
    });

    test('un cobro que no está, anulado o dado de baja es null', () async {
      await cobro('c-2', anulado: ahoraTicket);
      await cobro('c-3', baja: ahoraTicket);

      expect(await historial.cobroConTarjeta('c-1'), isNull);
      expect(await historial.cobroConTarjeta('c-2'), isNull);
      expect(await historial.cobroConTarjeta('c-3'), isNull);
    });
  });
}
