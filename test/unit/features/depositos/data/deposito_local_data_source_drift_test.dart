// «Registrar depósito» contra la tabla real (HU-CTA-004, #442): AppDatabase en memoria, mismo esquema
// y mismos CHECK que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

final _ahora = DateTime.utc(2026, 10, 30, 12, 0, 7, 321);

/// Las columnas de `public.deposito` que manda el teléfono (backend 0067, 0114 y 0122). Sin
/// `colportor_id`, `validado_*` ni `rechazado_*`: las pone el servidor y el push las descarta.
const _columnasDelServidor = {
  'id',
  'monto',
  'fecha',
  'destino',
  'concepto',
  'campania_id',
  'ticket_id',
  'created_at',
  'updated_at',
  'created_by',
  'deleted_at',
  'sync_version',
};

Deposito _deposito(
  String id, {
  int monto = 180000,
  DestinoDeDeposito destino = DestinoDeDeposito.banco,
  ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
  String? campaniaId,
  String? ticketId,
  DateTime? fecha,
  DateTime? borrado,
}) => Deposito(
  id: id,
  montoCentavos: monto,
  fecha: fecha ?? _ahora,
  destino: destino,
  concepto: concepto,
  campaniaId: campaniaId,
  ticketId: destino.llevaTicket ? (ticketId ?? 't-$id') : ticketId,
  auditoria: Auditoria(
    createdAt: _ahora,
    updatedAt: _ahora,
    createdBy: 'col-1',
    deletedAt: borrado,
  ),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late DepositoLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = DepositoLocalDataSourceDrift(db, encolador: encolador);
  });
  tearDown(() => db.close());

  Future<List<DepositoFila>> filas() =>
      (db.select(db.depositos)..orderBy([(d) => OrderingTerm.asc(d.id)])).get();

  group('registrar', () {
    test('dado un depósito en el banco, cuando se registra, guarda la fila con sus columnas y la '
        'encola como un alta', () async {
      final r = await local.registrar(_deposito('d-1', ticketId: 't-9'));

      final fila = (await filas()).single;
      expect(fila.id, 'd-1');
      expect(fila.monto, 180000);
      expect(fila.fecha, _ahora);
      expect(fila.destino, 'BANCO');
      expect(fila.concepto, 'CASA_EDITORA');
      expect(fila.campaniaId, isNull);
      expect(fila.ticketId, 't-9');
      expect(fila.createdBy, 'col-1');
      expect(fila.deletedAt, isNull);
      expect(fila.syncVersion, 0);
      expect(r.yaEstaba, isFalse);
      expect(r.deposito.id, 'd-1');
      final cambio = encolador.encolados.single;
      expect(cambio.entidad, 'deposito');
      expect(cambio.operacion, OperacionSync.insert);
      expect(cambio.payload['id'], 'd-1');
    });

    test('dado un retiro por el coordinador de alquiler, cuando se registra, guarda la campaña y '
        'ningún ticket', () async {
      await local.registrar(
        _deposito(
          'd-1',
          destino: DestinoDeDeposito.retiroCoordinador,
          concepto: ConceptoDeDeposito.alquiler,
          campaniaId: 'camp-1',
          monto: 500000,
        ),
      );

      final fila = (await filas()).single;
      expect(fila.destino, 'RETIRO_COORDINADOR');
      expect(fila.concepto, 'ALQUILER');
      expect(fila.campaniaId, 'camp-1');
      expect(fila.ticketId, isNull);
    });

    test(
      'dado el mismo depósito dos veces (doble toque), cuando se registra, queda una sola fila y '
      'un solo encolado, y la segunda dice que ya estaba',
      () async {
        final primera = await local.registrar(_deposito('d-1'));
        final segunda = await local.registrar(_deposito('d-1'));

        expect(await filas(), hasLength(1));
        expect(encolador.encolados, hasLength(1));
        expect(primera.yaEstaba, isFalse);
        expect(segunda.yaEstaba, isTrue);
        expect(segunda.deposito, primera.deposito);
      },
    );

    test(
      'dado el mismo id con otro monto (un reintento tras cambiar el campo), cuando se registra, '
      'no pisa lo que ya estaba',
      () async {
        await local.registrar(_deposito('d-1', monto: 100));

        final r = await local.registrar(_deposito('d-1', monto: 999));

        expect(r.yaEstaba, isTrue);
        expect(r.deposito.montoCentavos, 100);
        expect((await filas()).single.monto, 100);
      },
    );

    test(
      'dado un ticket que ya respalda otro depósito, cuando se registra otro con ese ticket, lanza '
      'DepositoTicketYaUsadoException y no escribe ni encola nada',
      () async {
        await local.registrar(_deposito('d-1', ticketId: 't-1'));
        encolador.encolados.clear();

        await expectLater(
          local.registrar(_deposito('d-2', ticketId: 't-1')),
          throwsA(isA<DepositoTicketYaUsadoException>()),
        );

        expect((await filas()).map((f) => f.id), ['d-1']);
        expect(encolador.encolados, isEmpty);
      },
    );

    test(
      'dado un depósito dado de baja con ese ticket, cuando se registra otro con el mismo ticket, '
      'entra (el servidor solo cuenta los vivos)',
      () async {
        await local.registrar(_deposito('d-1', ticketId: 't-1', borrado: _ahora));

        await local.registrar(_deposito('d-2', ticketId: 't-1'));

        expect((await filas()).map((f) => f.id), ['d-1', 'd-2']);
      },
    );

    test(
      'dado dos depósitos seguidos sin esperar al primero, cuando se registran, entran los dos con '
      'sus encolados en orden',
      () async {
        final a = local.registrar(_deposito('d-1', monto: 100));
        final b = local.registrar(_deposito('d-2', monto: 200));
        await Future.wait([a, b]);

        expect((await filas()).map((f) => f.monto), [100, 200]);
        expect(encolador.encolados.map((c) => c.payload['id']), ['d-1', 'd-2']);
      },
    );

    test(
      'dado dos depósitos seguidos con el mismo ticket sin esperar, cuando se registran, entra uno '
      'solo',
      () async {
        final a = local.registrar(_deposito('d-1', ticketId: 't-1'));
        final b = local.registrar(_deposito('d-2', ticketId: 't-1'));

        final resultados = await Future.wait([
          a.then<Object>((v) => v).catchError((Object e) => e),
          b.then<Object>((v) => v).catchError((Object e) => e),
        ]);

        expect(resultados.whereType<DepositoRegistrado>(), hasLength(1));
        expect(resultados.whereType<DepositoTicketYaUsadoException>(), hasLength(1));
        expect(await filas(), hasLength(1));
        expect(encolador.encolados, hasLength(1));
      },
    );

    test(
      'dado que el motor rechaza el encolado, cuando se registra, no queda ninguna fila a medias y '
      'el reintento con el mismo id entra',
      () async {
        encolador.fallarCon = StateError('motor apagado');

        await expectLater(local.registrar(_deposito('d-1')), throwsStateError);
        expect(await filas(), isEmpty);

        encolador.fallarCon = null;
        final r = await local.registrar(_deposito('d-1'));

        expect(r.yaEstaba, isFalse);
        expect(await filas(), hasLength(1));
        expect(encolador.encolados, hasLength(1));
      },
    );

    test(
      'dado un monto enorme (el tope de la app), cuando se registra, se guarda exacto',
      () async {
        await local.registrar(_deposito('d-1', monto: 2147483647));

        expect((await filas()).single.monto, 2147483647);
      },
    );

    test('dado una fecha con milisegundos, cuando se registra, vuelve igual (UTC, sin perder el '
        'milisegundo)', () async {
      final r = await local.registrar(
        _deposito('d-1', fecha: DateTime.utc(2026, 10, 29, 23, 59, 59, 999)),
      );

      expect(r.deposito.fecha, DateTime.utc(2026, 10, 29, 23, 59, 59, 999));
      expect((await filas()).single.fecha, DateTime.utc(2026, 10, 29, 23, 59, 59, 999));
    });
  });

  group('audit_log local', () {
    Future<List<AuditLogFila>> auditorias() => db.select(db.auditLogLocal).get();

    test(
      'dado un depósito, cuando se registra, deja una fila de auditoría solo con su id',
      () async {
        await local.registrar(_deposito('d-1', monto: 987654, ticketId: 't-SECRETO'));

        final fila = (await auditorias()).single;
        expect(fila.evento, EventoAuditoriaLocal.depositoRegistrado);
        expect(fila.uuid, 'd-1');
        expect(fila.motivo, isNull);
        expect(fila.creadoEn, _ahora);
        expect('${fila.evento}${fila.uuid}${fila.motivo}', isNot(contains('987654')));
      },
    );

    test(
      'dado el mismo depósito dos veces, cuando se registra, la auditoría queda en una sola fila',
      () async {
        await local.registrar(_deposito('d-1'));
        await local.registrar(_deposito('d-1'));

        expect(await auditorias(), hasLength(1));
      },
    );

    test(
      'dado un ticket ya usado o un encolado que falla, cuando se registra, no queda auditoría de '
      'un depósito que no existe',
      () async {
        await local.registrar(_deposito('d-1', ticketId: 't-1'));
        await expectLater(
          local.registrar(_deposito('d-2', ticketId: 't-1')),
          throwsA(isA<DepositoTicketYaUsadoException>()),
        );
        encolador.fallarCon = StateError('motor apagado');
        await expectLater(local.registrar(_deposito('d-3')), throwsStateError);

        expect((await auditorias()).map((a) => a.uuid), ['d-1']);
      },
    );
  });

  group('los CHECK de la tabla (los mismos del servidor)', () {
    DepositosCompanion fila({
      String id = 'x',
      int monto = 100,
      String destino = 'BANCO',
      String concepto = 'CASA_EDITORA',
      String? campaniaId,
      String? ticketId = 't-x',
    }) => DepositosCompanion.insert(
      id: id,
      monto: monto,
      fecha: _ahora,
      destino: destino,
      concepto: concepto,
      campaniaId: Value(campaniaId),
      ticketId: Value(ticketId),
      createdAt: _ahora,
      updatedAt: _ahora,
    );

    test('dado una fila válida, cuando se inserta, entra (la base de la prueba)', () async {
      await db.into(db.depositos).insert(fila());

      expect(await filas(), hasLength(1));
    });

    for (final (nombre, malo) in <(String, DepositosCompanion)>[
      ('monto en cero', fila(monto: 0)),
      ('monto negativo', fila(monto: -5)),
      ('destino desconocido', fila(destino: 'CAJERO')),
      ('concepto desconocido', fila(concepto: 'OTRO')),
      ('retiro por el coordinador con ticket', fila(destino: 'RETIRO_COORDINADOR')),
      ('banco sin ticket', fila(ticketId: null)),
      ('oficina sin ticket', fila(destino: 'OFICINA', ticketId: null)),
      ('alquiler sin campaña', fila(concepto: 'ALQUILER')),
    ]) {
      test('dado $nombre, cuando se inserta, la base lo rechaza', () async {
        await expectLater(db.into(db.depositos).insert(malo), throwsA(anything));

        expect(await filas(), isEmpty);
      });
    }

    test(
      'dado un retiro sin ticket y un alquiler con campaña, cuando se insertan, entran',
      () async {
        await db
            .into(db.depositos)
            .insert(fila(id: 'r', destino: 'RETIRO_COORDINADOR', ticketId: null));
        await db.into(db.depositos).insert(fila(id: 'a', concepto: 'ALQUILER', campaniaId: 'c-1'));

        expect(await filas(), hasLength(2));
      },
    );
  });

  group('todos', () {
    test('dado depósitos de varios días, cuando se leen, vienen el más reciente primero', () async {
      await local.registrar(_deposito('d-1', fecha: DateTime.utc(2026, 10, 1)));
      await local.registrar(_deposito('d-2', fecha: DateTime.utc(2026, 10, 20)));
      await local.registrar(_deposito('d-3', fecha: DateTime.utc(2026, 10, 10)));

      expect((await local.todos()).map((d) => d.id), ['d-2', 'd-3', 'd-1']);
    });

    test('dado un depósito dado de baja, cuando se leen, no aparece', () async {
      await local.registrar(_deposito('d-1'));
      await local.registrar(_deposito('d-2', borrado: _ahora));

      expect((await local.todos()).map((d) => d.id), ['d-1']);
    });

    test('dado nada guardado, cuando se leen, es una lista vacía', () async {
      expect(await local.todos(), isEmpty);
    });

    test('dado un depósito guardado, cuando se lee, vuelve igual al que se registró', () async {
      final original = _deposito(
        'd-1',
        destino: DestinoDeDeposito.oficina,
        concepto: ConceptoDeDeposito.alquiler,
        campaniaId: 'camp-1',
        ticketId: 't-1',
      );
      await local.registrar(original);

      expect((await local.todos()).single, original);
    });

    test('dado muchos depósitos, cuando se leen, vienen todos', () async {
      for (var i = 0; i < 300; i++) {
        await local.registrar(
          _deposito(
            'd-${i.toString().padLeft(3, '0')}',
            monto: i + 1,
            fecha: _ahora.add(Duration(minutes: i)),
          ),
        );
      }

      final todos = await local.todos();

      expect(todos, hasLength(300));
      expect(todos.first.id, 'd-299');
      expect(todos.last.id, 'd-000');
    });
  });

  group('lo que sube', () {
    test(
      'dado un depósito, cuando se encola, el payload lleva las columnas del servidor y nada más',
      () async {
        await local.registrar(_deposito('d-1', ticketId: 't-1'));

        expect(encolador.encolados.single.payload.keys.toSet(), _columnasDelServidor);
      },
    );

    test(
      'dado un depósito, cuando se encola, no lleva dato de ninguna persona ni de ningún cobro',
      () async {
        await local.registrar(_deposito('d-1'));

        final texto = encolador.encolados.single.payload.toString().toLowerCase();
        for (final clave in [
          'persona',
          'cliente',
          'venta',
          'cobranza',
          'cobro',
          'nombre',
          'telefono',
        ]) {
          expect(texto, isNot(contains(clave)));
        }
      },
    );
  });
}
