// Los tickets contra las tablas reales (HU-COB-007, #426): AppDatabase en memoria, mismo esquema y
// mismos CHECK que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/tickets_falsos.dart';

/// Las columnas de `public.ticket` que manda el teléfono (backend 0067 y 0113). Sin `usuario_id`,
/// `subido_en`, `estado`, `revisado_*`, `motivo_rechazo` ni `campania_validadora_id`: las pone el
/// servidor y el push las descarta.
const _columnasQueSuben = {
  'id',
  'tipo',
  'url_cloud',
  'monto',
  'fecha',
  'numero_autorizacion',
  'tarjeta_tipo',
  'tarjeta_marca',
  'created_at',
  'updated_at',
  'created_by',
  'deleted_at',
  'sync_version',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late TicketLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = TicketLocalDataSourceDrift(db, encolador: encolador);
  });
  tearDown(() => db.close());

  Future<void> cobro(String id, {String medio = 'TARJETA', String? ticketId, DateTime? baja}) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: 'v-1',
          monto: 150000,
          medio: medio,
          fecha: ahoraTicket,
          ticketId: Value(ticketId),
          createdAt: ahoraTicket,
          updatedAt: ahoraTicket,
          deletedAt: Value(baja),
        ),
      );

  Future<TicketRegistrado> registrar(String id, {String? cobroId, Ticket? ticket}) =>
      local.registrar(ticket ?? ticketDePrueba(id), fotoLocalDePrueba(id), cobroId: cobroId);

  /// Hace como el motor al volver el push: el servidor aceptó la fila y le puso su versión.
  Future<void> servidorAcepto(String id, {int version = 1}) => (db.update(
    db.tickets,
  )..where((t) => t.id.equals(id))).write(TicketsCompanion(syncVersion: Value(version)));

  group('registrar', () {
    test(
      'dado un ticket de tarjeta, cuando se registra, guarda la fila, la copia local y encola un '
      'alta solo con las columnas que suben',
      () async {
        final r = await registrar('t-1');

        expect(r.yaEstaba, isFalse);
        final fila = await db.select(db.tickets).getSingle();
        expect(fila.id, 't-1');
        expect(fila.tipo, 'COBRO_TARJETA');
        expect(fila.monto, 150000);
        expect(fila.fecha, ahoraTicket);
        expect(fila.numeroAutorizacion, '123456');
        expect(fila.tarjetaTipo, 'CREDITO');
        expect(fila.tarjetaMarca, 'Visa');
        expect(fila.urlCloud, isNull);
        expect(fila.estado, 'PENDIENTE');
        expect(fila.usuarioId, isNull);
        expect(fila.createdBy, 'col-1');
        expect(fila.syncVersion, 0);
        final foto = await db.select(db.ticketFotosLocales).getSingle();
        expect(foto.ticketId, 't-1');
        expect(foto.tipoDeImagen, 'image/jpeg');
        expect(foto.estado, 'PENDIENTE');
        expect(foto.rutaLocal, '/fotos/t-1.jpg');
        expect(foto.intentos, 0);

        expect(encolador.encolados, hasLength(1));
        final cambio = encolador.encolados.single;
        expect(cambio.entidad, 'ticket');
        expect(cambio.operacion, OperacionSync.insert);
        expect(cambio.payload.keys.toSet(), _columnasQueSuben);
        expect(cambio.payload['url_cloud'], isNull);
        expect(cambio.payload['monto'], 150000);
        expect(cambio.payload['tipo'], 'COBRO_TARJETA');
      },
    );

    test('deja una fila de audit_log local con el id del ticket y sin más', () async {
      await registrar('t-1');

      final audit = await db.select(db.auditLogLocal).getSingle();
      expect(audit.evento, EventoAuditoriaLocal.ticketRegistrado);
      expect(audit.uuid, 't-1');
      expect(audit.motivo, isNull);
    });

    test('con un cobro con tarjeta, lo liga al ticket y encola el alta del ticket ANTES que el '
        'update del cobro', () async {
      await cobro('c-1');

      await registrar('t-1', cobroId: 'c-1');

      final c = await db.select(db.cobranzas).getSingle();
      expect(c.ticketId, 't-1');
      expect(encolador.encolados.map((e) => (e.entidad, e.operacion)), [
        ('ticket', OperacionSync.insert),
        ('cobranza', OperacionSync.update),
      ]);
      expect(encolador.encolados.last.payload['ticket_id'], 't-1');
      expect(encolador.encolados.last.payload['id'], 'c-1');
    });

    test(
      'un cobro cuyo ticket el coordinador rechazó se liga al ticket nuevo; si el anterior no está '
      'rechazado, el cobro conserva el suyo',
      () async {
        await cobro('c-1');
        await registrar('t-1', cobroId: 'c-1');

        // El anterior sigue pendiente: no se pisa.
        await expectLater(
          registrar('t-2', cobroId: 'c-1'),
          throwsA(isA<TicketCobroInvalidoException>()),
        );
        expect((await db.select(db.cobranzas).getSingle()).ticketId, 't-1');

        // El coordinador lo rechaza (baja con el pull): ahora sí.
        await (db.update(db.tickets)..where((t) => t.id.equals('t-1'))).write(
          const TicketsCompanion(estado: Value('RECHAZADO'), motivoRechazo: Value('Ilegible')),
        );
        await registrar('t-2', cobroId: 'c-1');

        expect((await db.select(db.cobranzas).getSingle()).ticketId, 't-2');
        expect(encolador.encolados.last.entidad, 'cobranza');
        expect(encolador.encolados.last.payload['ticket_id'], 't-2');
      },
    );

    test('con el mismo id otra vez, no escribe ni encola nada y dice que ya estaba', () async {
      await cobro('c-1');
      await registrar('t-1', cobroId: 'c-1');

      final otra = await registrar('t-1', cobroId: 'c-1');

      expect(otra.yaEstaba, isTrue);
      expect(otra.ticket.id, 't-1');
      expect(await db.select(db.tickets).get(), hasLength(1));
      expect(await db.select(db.ticketFotosLocales).get(), hasLength(1));
      expect(await db.select(db.auditLogLocal).get(), hasLength(1));
      expect(encolador.encolados, hasLength(2));
    });

    test('un cobro que no existe, dado de baja, que no es de tarjeta o que ya tiene otro ticket se '
        'rechaza y no deja nada', () async {
      await cobro('c-efectivo', medio: 'EFECTIVO');
      await cobro('c-baja', baja: ahoraTicket);
      await cobro('c-otro', ticketId: 't-otro');

      for (final id in ['c-no-existe', 'c-efectivo', 'c-baja', 'c-otro']) {
        await expectLater(
          registrar('t-1', cobroId: id),
          throwsA(isA<TicketCobroInvalidoException>()),
          reason: id,
        );
      }

      expect(await db.select(db.tickets).get(), isEmpty);
      expect(await db.select(db.ticketFotosLocales).get(), isEmpty);
      expect(await db.select(db.auditLogLocal).get(), isEmpty);
      // La cola de verdad vive en la misma DB y se revierte con ella: el doble en memoria no, así que
      // acá solo se mira que el cobro no quedó ligado.
      expect((await db.select(db.cobranzas).get()).map((c) => c.ticketId), [null, null, 't-otro']);
    });

    test('si el encolado falla, se revierte todo: ni ticket, ni copia, ni cobro ligado', () async {
      await cobro('c-1');
      encolador.fallarCon = StateError('sin motor');

      await expectLater(registrar('t-1', cobroId: 'c-1'), throwsStateError);

      expect(await db.select(db.tickets).get(), isEmpty);
      expect(await db.select(db.ticketFotosLocales).get(), isEmpty);
      expect((await db.select(db.cobranzas).getSingle()).ticketId, isNull);
    });

    test('si falla el update del cobro, el ticket tampoco queda', () async {
      await cobro('c-1');
      encolador
        ..fallarCon = StateError('se cayó')
        ..fallarDespuesDe = 1;

      await expectLater(registrar('t-1', cobroId: 'c-1'), throwsStateError);

      expect(await db.select(db.tickets).get(), isEmpty);
      expect((await db.select(db.cobranzas).getSingle()).ticketId, isNull);
    });

    test('el ticket de un depósito se guarda sin tarjeta ni autorización obligatoria', () async {
      await registrar(
        't-d',
        ticket: ticketDePrueba(
          't-d',
          tipo: TipoDeTicket.deposito,
          autorizacion: null,
          tarjeta: null,
          marca: null,
        ),
      );

      final fila = await db.select(db.tickets).getSingle();
      expect(fila.tipo, 'DEPOSITO');
      expect(fila.numeroAutorizacion, isNull);
      expect(fila.tarjetaTipo, isNull);
    });

    test('las dos tablas tienen sus CHECK: monto, tipo, estado y bytes', () async {
      Future<void> ticket(String valores) => db.customStatement(
        'INSERT INTO ticket (id, tipo, monto, estado, created_at, updated_at) VALUES $valores',
      );
      await ticket("('a', 'COBRO_TARJETA', 100, 'PENDIENTE', 1, 1)");
      for (final malo in [
        "('b', 'COBRO_TARJETA', 0, 'PENDIENTE', 1, 1)",
        "('c', 'OTRA_COSA', 100, 'PENDIENTE', 1, 1)",
        "('d', 'COBRO_TARJETA', 100, 'HECHO', 1, 1)",
      ]) {
        await expectLater(ticket(malo), throwsA(anything), reason: malo);
      }
      // Un ticket viejo sin monto ni fecha no frena la fila (ni un pull).
      await ticket("('e', 'OTRO', NULL, 'PENDIENTE', 1, 1)");

      const foto =
          'INSERT INTO ticket_foto_local (ticket_id, tipo_de_imagen, bytes, estado, creada_en) '
          'VALUES ';
      await db.customStatement("$foto('a', 'image/jpeg', 10, 'PENDIENTE', 1)");
      for (final malo in [
        "('b', 'image/jpeg', 0, 'PENDIENTE', 1)",
        "('c', 'image/jpeg', 10, 'HECHA', 1)",
      ]) {
        await expectLater(db.customStatement('$foto$malo'), throwsA(anything), reason: malo);
      }
    });
  });

  group('fotosPorSubir', () {
    test('solo las del ticket que el servidor ya aceptó, con copia local y sin rechazar, el más '
        'viejo primero', () async {
      await registrar('t-nuevo');
      await registrar('t-viejo', ticket: ticketDePrueba('t-viejo'));
      await registrar('t-sin-llegar');
      await registrar('t-subida');
      await registrar('t-rechazada');
      await registrar('t-sin-copia');
      await servidorAcepto('t-nuevo');
      await servidorAcepto('t-viejo');
      await servidorAcepto('t-subida');
      await servidorAcepto('t-rechazada');
      await servidorAcepto('t-sin-copia');
      // El más viejo es el de createdAt menor.
      await (db.update(db.tickets)..where((t) => t.id.equals('t-viejo'))).write(
        TicketsCompanion(createdAt: Value(ahoraTicket.subtract(const Duration(hours: 1)))),
      );
      await local.marcarFotoSubida('t-subida', 'u/t-subida.jpg', ahoraTicket);
      await local.anotarIntentoFallido('t-rechazada', codigo: 'foto_muy_pesada', definitivo: true);
      await local.soltarCopiaLocal('t-subida');
      await (db.update(db.ticketFotosLocales)..where((f) => f.ticketId.equals('t-sin-copia')))
          .write(const TicketFotosLocalesCompanion(rutaLocal: Value(null)));

      final lista = await local.fotosPorSubir();

      expect(lista.map((t) => t.ticket.id), ['t-viejo', 't-nuevo']);
      expect(lista.first.foto.tipoDeImagen, TipoDeImagen.jpeg);
    });

    test(
      'cantidadDeFotosPorSubir emite cuando el servidor acepta la fila y cuando la foto sube',
      () async {
        final cantidades = <int>[];
        final suscripcion = local.cantidadDeFotosPorSubir().listen(cantidades.add);
        await pumpEventQueue();
        await registrar('t-1');
        await pumpEventQueue();
        await servidorAcepto('t-1');
        await pumpEventQueue();
        await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);
        await pumpEventQueue();
        await suscripcion.cancel();

        expect(cantidades, [0, 1, 0]);
      },
    );
  });

  group('marcarFotoSubida', () {
    test('guarda la ruta en url_cloud, marca la copia como subida y encola UN update con la fila '
        'entera', () async {
      await registrar('t-1');
      await servidorAcepto('t-1', version: 3);
      final ahora = ahoraTicket.add(const Duration(minutes: 5));

      final t = await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahora);

      expect(t.urlCloud, 'u/t-1.jpg');
      final fila = await db.select(db.tickets).getSingle();
      expect(fila.urlCloud, 'u/t-1.jpg');
      expect(fila.updatedAt, ahora);
      expect((await db.select(db.ticketFotosLocales).getSingle()).estado, 'SUBIDA');
      final update = encolador.encolados.last;
      expect(update.entidad, 'ticket');
      expect(update.operacion, OperacionSync.update);
      expect(update.payload.keys.toSet(), _columnasQueSuben);
      expect(update.payload['url_cloud'], 'u/t-1.jpg');
      expect(update.payload['sync_version'], 3);
    });

    test('es idempotente: la segunda vez no encola otro update', () async {
      await registrar('t-1');
      await servidorAcepto('t-1');
      await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);
      final antes = encolador.encolados.length;

      await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);

      expect(encolador.encolados, hasLength(antes));
    });

    test('un ticket que no existe es TicketInexistenteException', () async {
      await expectLater(
        local.marcarFotoSubida('no-existe', 'u/x.jpg', ahoraTicket),
        throwsA(isA<TicketInexistenteException>()),
      );
    });

    test('si el encolado del update falla, la ruta no queda guardada', () async {
      await registrar('t-1');
      await servidorAcepto('t-1');
      encolador.fallarCon = StateError('sin motor');

      await expectLater(local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket), throwsStateError);

      expect((await db.select(db.tickets).getSingle()).urlCloud, isNull);
      expect((await db.select(db.ticketFotosLocales).getSingle()).estado, 'PENDIENTE');
    });
  });

  group('anotarIntentoFallido', () {
    test('suma el intento y guarda el código; con definitivo la subida queda rechazada', () async {
      await registrar('t-1');

      await local.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
      var foto = await db.select(db.ticketFotosLocales).getSingle();
      expect((foto.intentos, foto.ultimoError, foto.estado), (1, 'red', 'PENDIENTE'));

      await local.anotarIntentoFallido('t-1', codigo: 'foto_muy_pesada', definitivo: true);
      foto = await db.select(db.ticketFotosLocales).getSingle();
      expect((foto.intentos, foto.ultimoError, foto.estado), (2, 'foto_muy_pesada', 'RECHAZADA'));
    });

    test('una subida que sale después borra el último error', () async {
      await registrar('t-1');
      await servidorAcepto('t-1');
      await local.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);

      await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);

      final foto = await db.select(db.ticketFotosLocales).getSingle();
      expect(foto.ultimoError, isNull);
      expect(foto.intentos, 1);
    });
  });

  group('soltarCopiaLocal', () {
    test(
      'con la foto ya subida, suelta la ruta, devuelve la que había y no toca la nube',
      () async {
        await registrar('t-1');
        await servidorAcepto('t-1');
        await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);
        final antes = encolador.encolados.length;

        final ruta = await local.soltarCopiaLocal('t-1');

        expect(ruta, '/fotos/t-1.jpg');
        expect((await db.select(db.ticketFotosLocales).getSingle()).rutaLocal, isNull);
        expect((await db.select(db.tickets).getSingle()).urlCloud, 'u/t-1.jpg');
        expect(encolador.encolados, hasLength(antes));
      },
    );

    test('con la foto sin subir NO borra: perdería el ticket', () async {
      await registrar('t-1');

      await expectLater(
        local.soltarCopiaLocal('t-1'),
        throwsA(isA<TicketCopiaSinSubirException>()),
      );

      expect((await db.select(db.ticketFotosLocales).getSingle()).rutaLocal, '/fotos/t-1.jpg');
    });

    test('una subida rechazada tampoco deja borrar la copia', () async {
      await registrar('t-1');
      await local.anotarIntentoFallido('t-1', codigo: 'foto_muy_pesada', definitivo: true);

      await expectLater(
        local.soltarCopiaLocal('t-1'),
        throwsA(isA<TicketCopiaSinSubirException>()),
      );
    });

    test('dos veces seguidas: la segunda no encuentra copia y devuelve null', () async {
      await registrar('t-1');
      await servidorAcepto('t-1');
      await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);
      await local.soltarCopiaLocal('t-1');

      expect(await local.soltarCopiaLocal('t-1'), isNull);
    });

    test('un ticket que no existe es TicketInexistenteException', () async {
      await expectLater(
        local.soltarCopiaLocal('no-existe'),
        throwsA(isA<TicketInexistenteException>()),
      );
    });
  });

  group('cobrosConTicketPendiente', () {
    test('el cobro está «con ticket pendiente» hasta que la foto sube', () async {
      await cobro('c-1');
      await cobro('c-sin-ticket');
      final emisiones = <Set<String>>[];
      final suscripcion = local.cobrosConTicketPendiente().listen(emisiones.add);
      await pumpEventQueue();

      await registrar('t-1', cobroId: 'c-1');
      await pumpEventQueue();
      await servidorAcepto('t-1');
      await pumpEventQueue();
      await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);
      await pumpEventQueue();
      await suscripcion.cancel();

      expect(emisiones, [
        <String>{},
        {'c-1'},
        <String>{},
      ]);
    });

    test(
      'a los 4 meses el servidor suelta la ruta y el cobro no vuelve a estar «pendiente»',
      () async {
        await cobro('c-1');
        await registrar('t-1', cobroId: 'c-1');
        await servidorAcepto('t-1');
        await local.marcarFotoSubida('t-1', 'u/t-1.jpg', ahoraTicket);
        // El pull trae el ticket con la foto vencida.
        await (db.update(
          db.tickets,
        )..where((t) => t.id.equals('t-1'))).write(const TicketsCompanion(urlCloud: Value(null)));

        expect(await local.cobrosConTicketPendiente().first, isEmpty);
      },
    );

    test('una foto rechazada tampoco está en la nube: el cobro sigue «pendiente»', () async {
      await cobro('c-1');
      await registrar('t-1', cobroId: 'c-1');
      await local.anotarIntentoFallido('t-1', codigo: 'foto_muy_pesada', definitivo: true);

      expect(await local.cobrosConTicketPendiente().first, {'c-1'});
    });
  });
}
