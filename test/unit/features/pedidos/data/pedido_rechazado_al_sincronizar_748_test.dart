// El pedido que el servidor rechazó al sincronizar (HU-STK-009, #748; decisión del 23/11 sobre #387, P5: una
// operación rechazada nunca se descarta): se lee de la cola de sync (`sync_queue`) como «No se envió», con la
// causa del código del rechazo, sin tocar la cola ni borrar nada.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/sync_queue_table.dart';
import 'package:colportores_mobile/features/pedidos/data/datasources/pedido_local_data_source_drift.dart';
import 'package:colportores_mobile/features/pedidos/data/repositories/pedido_repository_impl.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/pedidos_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late PedidoRepositoryImpl repo;
  var n = 0;

  setUp(() {
    n = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = PedidoRepositoryImpl(
      PedidoLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria()),
      logger: loggerMudo(),
    );
  });
  tearDown(() => db.close());

  Future<void> trabajo(
    String entidad,
    String pk, {
    required String estado,
    String codigo = '',
    String op = 'insert',
  }) => db
      .into(db.syncQueue)
      .insert(
        SyncQueueCompanion.insert(
          id: 'job-${++n}',
          clientOpId: 'op-$n',
          entity: entidad,
          op: op,
          payload: '{}',
          createdAt: DateTime.utc(2026, 11, 23, 12, 0, n),
          state: estado,
          code: Value(codigo),
          rowPk: Value(pk),
        ),
      );

  Future<Pedido> leer(String id) async {
    final todos = await repo.observar('col-1').first;
    return todos.singleWhere((p) => p.id == id);
  }

  group('cómo se lee un pedido según su alta en la cola', () {
    test(
      'dado el alta rechazada con 42501, se lee «No se envió» por la fecha fuera de la campaña',
      () async {
        await repo.enviar(pedidoDe());
        await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');

        final p = await leer('ped-1');
        expect(p.estado, EstadoDelPedido.noSeEnvio);
        expect(p.rechazoAlEnviar, CausaDelRechazoAlEnviar.fueraDeLaCampania);
        // No se borra nada: el pedido y sus líneas siguen, con el monto que se armó.
        expect(p.lineas, hasLength(3));
        expect(p.montoCentavos, 1184000);
        expect(await db.select(db.pedidosCasaEditora).get(), hasLength(1));
        expect(await db.select(db.pedidoItems).get(), hasLength(3));
      },
    );

    for (final codigo in ['23514', '23503', '23505', 'FILA_INEXISTENTE', '']) {
      test(
        'dado el alta rechazada con «$codigo», se lee «No se envió» sin afirmar la causa',
        () async {
          await repo.enviar(pedidoDe());
          await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: codigo);

          final p = await leer('ped-1');
          expect(p.estado, EstadoDelPedido.noSeEnvio);
          expect(p.rechazoAlEnviar, CausaDelRechazoAlEnviar.otra);
        },
      );
    }

    test('dado el alta todavía pendiente, en vuelo o en espera, sigue «por autorizar»', () async {
      for (final estado in [
        EstadoJob.pending,
        EstadoJob.inFlight,
        EstadoJob.waiting,
        EstadoJob.blocked,
        EstadoJob.done,
      ]) {
        await db.delete(db.syncQueue).go();
        await db.delete(db.pedidosCasaEditora).go();
        await db.delete(db.pedidoItems).go();
        await repo.enviar(pedidoDe());
        await trabajo('pedido_casa_editora', 'ped-1', estado: estado, codigo: '42501');
        final p = await leer('ped-1');
        expect(p.estado, EstadoDelPedido.porAutorizar, reason: estado);
        expect(p.rechazoAlEnviar, isNull, reason: estado);
      }
    });

    test('dado el rechazo de OTRO pedido, el mío no cambia', () async {
      await repo.enviar(pedidoDe());
      await repo.enviar(pedidoDe(id: 'ped-2', fecha: ahoraPedidos.add(const Duration(hours: 1))));
      await trabajo('pedido_casa_editora', 'ped-2', estado: EstadoJob.invalid, codigo: '42501');

      expect((await leer('ped-1')).estado, EstadoDelPedido.porAutorizar);
      expect((await leer('ped-2')).estado, EstadoDelPedido.noSeEnvio);
    });

    test('dado el rechazo de otra entidad o de otra operación, el pedido no cambia', () async {
      await repo.enviar(pedidoDe());
      await trabajo('venta', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');
      await trabajo(
        'pedido_casa_editora',
        'ped-1',
        estado: EstadoJob.invalid,
        codigo: '42501',
        op: 'update',
      );
      expect((await leer('ped-1')).estado, EstadoDelPedido.porAutorizar);
    });

    test(
      'dado que el pedido ya llegó (tiene número) o que lo cancelé, el rechazo viejo no lo pisa',
      () async {
        await repo.enviar(pedidoDe());
        await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');
        await (db.update(db.pedidosCasaEditora)..where((p) => p.id.equals('ped-1'))).write(
          const PedidosCasaEditoraCompanion(numero: Value(231)),
        );
        expect((await leer('ped-1')).estado, EstadoDelPedido.porAutorizar);

        await (db.update(db.pedidosCasaEditora)..where((p) => p.id.equals('ped-1'))).write(
          const PedidosCasaEditoraCompanion(numero: Value(null), estado: Value('CANCELADO')),
        );
        expect((await leer('ped-1')).estado, EstadoDelPedido.cancelado);
      },
    );

    test(
      'dada una línea rechazada con el alta del pedido sin rechazar, el pedido no se marca (decisión pendiente)',
      () async {
        await repo.enviar(pedidoDe());
        await trabajo('pedido_item', 'ped-1-l1', estado: EstadoJob.invalid, codigo: '23514');
        expect((await leer('ped-1')).estado, EstadoDelPedido.porAutorizar);
      },
    );

    test('dado un pedido rechazado, no se puede cancelar y no se escribe nada', () async {
      await repo.enviar(pedidoDe());
      await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');
      final antes = await db.select(db.syncQueue).get();

      final r = await repo.cancelar(id: 'ped-1', colportorId: 'col-1', ahora: ahoraPedidos);

      expect(r.fold((f) => f, (_) => null), isA<FailurePedidoNoCancelable>());
      expect((await db.select(db.pedidosCasaEditora).getSingle()).estado, 'PENDIENTE_AUTORIZACION');
      expect(await db.select(db.syncQueue).get(), antes);
    });

    test('dado un pedido rechazado, enviar con el mismo id devuelve lo que ya estaba', () async {
      await repo.enviar(pedidoDe());
      await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');
      final r = (await repo.enviar(pedidoDe())).getOrElse(() => throw StateError('falló'));
      expect(r.yaEstaba, isTrue);
      expect(r.pedido.estado, EstadoDelPedido.noSeEnvio);
    });
  });

  group('lo que emite el stream', () {
    test(
      'dado el rechazo que llega con la lista abierta, el pedido pasa a «No se envió» solo; y si la cola '
      'lo reintenta y el servidor lo acepta, vuelve a «por autorizar»',
      () async {
        await repo.enviar(pedidoDe());
        final emisiones = <EstadoDelPedido>[];
        final suscripcion = repo.observar('col-1').listen((l) => emisiones.add(l.single.estado));
        addTearDown(suscripcion.cancel);
        await pumpEventQueue(times: 50);
        expect(emisiones, [EstadoDelPedido.porAutorizar]);

        await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');
        await pumpEventQueue(times: 50);
        expect(emisiones.last, EstadoDelPedido.noSeEnvio);

        // «Reintentar» (HU-SYNC-007) lo devuelve a pendiente.
        await (db.update(db.syncQueue)..where((q) => q.rowPk.equals('ped-1'))).write(
          const SyncQueueCompanion(state: Value(EstadoJob.pending), code: Value('')),
        );
        await pumpEventQueue(times: 50);
        expect(emisiones.last, EstadoDelPedido.porAutorizar);
        expect(emisiones, [
          EstadoDelPedido.porAutorizar,
          EstadoDelPedido.noSeEnvio,
          EstadoDelPedido.porAutorizar,
        ]);
      },
    );

    test(
      'dado un cambio de la cola que no toca a los pedidos, no vuelve a emitir la misma lista',
      () async {
        await repo.enviar(pedidoDe());
        var emisiones = 0;
        final suscripcion = repo.observar('col-1').listen((_) => emisiones++);
        addTearDown(suscripcion.cancel);
        await pumpEventQueue(times: 50);
        expect(emisiones, 1);

        await trabajo('venta', 'v-1', estado: EstadoJob.pending);
        await trabajo('venta', 'v-1', estado: EstadoJob.invalid, codigo: '23514');
        await pumpEventQueue(times: 50);
        expect(emisiones, 1);
      },
    );

    test(
      'dado un colportor sin pedidos, la lista está vacía aunque haya rechazos de otro',
      () async {
        await repo.enviar(pedidoDe());
        await trabajo('pedido_casa_editora', 'ped-1', estado: EstadoJob.invalid, codigo: '42501');
        final deOtro = await repo.observar('col-2').first;
        expect(deOtro, isEmpty);
        // Y la cola quedó como estaba.
        expect(
          await (db.select(db.syncQueue)..orderBy([(q) => OrderingTerm.asc(q.id)])).get(),
          hasLength(1),
        );
      },
    );
  });

  group('EstadoDelPedido y CausaDelRechazoAlEnviar', () {
    test('«No se envió» no es un código del servidor: ni se lee ni se manda', () {
      expect(EstadoDelPedido.desdeCodigo(''), EstadoDelPedido.porAutorizar);
      expect(EstadoDelPedido.noSeEnvio.sePuedeCancelar, isFalse);
      expect(EstadoDelPedido.noSeEnvio.enCamino, isFalse);
    });

    test('solo el 42501 es la fecha fuera de la campaña', () {
      expect(
        CausaDelRechazoAlEnviar.desdeCodigo('42501'),
        CausaDelRechazoAlEnviar.fueraDeLaCampania,
      );
      expect(CausaDelRechazoAlEnviar.desdeCodigo('23514'), CausaDelRechazoAlEnviar.otra);
      expect(CausaDelRechazoAlEnviar.desdeCodigo(''), CausaDelRechazoAlEnviar.otra);
    });
  });
}
