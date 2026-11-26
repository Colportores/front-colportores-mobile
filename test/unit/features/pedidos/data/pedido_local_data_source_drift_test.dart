// Los pedidos contra la base real (#387): AppDatabase en memoria. Qué se guarda, qué sube por el sync (solo
// `id` y `estado` del pedido; `id`, `pedido_id`, `producto_id` y `cantidad` de la línea) y en qué orden, la
// idempotencia por id, la cancelación y la lectura.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/pedidos/data/datasources/pedido_local_data_source_drift.dart';
import 'package:colportores_mobile/features/pedidos/data/models/pedido_model.dart';
import 'package:colportores_mobile/features/pedidos/data/repositories/pedido_repository_impl.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/pedidos_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late PedidoLocalDataSourceDrift local;
  late PedidoRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = PedidoLocalDataSourceDrift(db, encolador: encolador);
    repo = PedidoRepositoryImpl(local, logger: loggerMudo());
  });
  tearDown(() => db.close());

  group('el payload que sube', () {
    test(
      'el pedido manda solo id y estado (más la auditoría); la línea, id, pedido_id, producto_id y cantidad',
      () {
        final p = pedidoDe();
        final encabezado = PedidoModel.encabezadoAJson(p.id, p.estado, p.auditoria);
        expect(encabezado.keys.toSet(), {
          'id',
          'estado',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
        expect(encabezado['estado'], 'PENDIENTE_AUTORIZACION');
        final linea = PedidoModel.lineaAJson(p.lineas.first, p.id, p.auditoria);
        expect(linea.keys.toSet(), {
          'id',
          'pedido_id',
          'producto_id',
          'cantidad',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
        // El precio de la línea lo copia el servidor: nadie lo tipea.
        expect(linea.containsKey('precio_unitario'), isFalse);
        expect(encabezado.containsKey('monto_total'), isFalse);
        expect(encabezado.containsKey('excede_limite'), isFalse);
      },
    );
  });

  group('enviar', () {
    test(
      'dado un pedido, cuando se envía, entonces se guarda con sus líneas y encola el pedido ANTES que las líneas',
      () async {
        final r = await repo.enviar(pedidoDe(excedeLimite: true));
        expect(r.isRight(), isTrue);

        final filas = await db.select(db.pedidosCasaEditora).get();
        expect(filas, hasLength(1));
        expect(filas.single.estado, 'PENDIENTE_AUTORIZACION');
        expect(filas.single.montoTotal, 1184000);
        expect(filas.single.excedeLimite, isTrue);
        expect(filas.single.colportorId, 'col-1');
        expect(await db.select(db.pedidoItems).get(), hasLength(3));

        expect(encolador.encolados.map((e) => (e.entidad, e.operacion)), [
          ('pedido_casa_editora', OperacionSync.insert),
          ('pedido_item', OperacionSync.insert),
          ('pedido_item', OperacionSync.insert),
          ('pedido_item', OperacionSync.insert),
        ]);
        expect(encolador.encolados.first.payload['estado'], 'PENDIENTE_AUTORIZACION');
      },
    );

    test(
      'dado el mismo id dos veces, entonces no escribe ni encola de nuevo y dice que ya estaba',
      () async {
        await repo.enviar(pedidoDe());
        final segunda = (await repo.enviar(pedidoDe())).getOrElse(() => throw StateError('falló'));
        expect(segunda.yaEstaba, isTrue);
        expect(segunda.pedido.lineas, hasLength(3));
        expect(await db.select(db.pedidosCasaEditora).get(), hasLength(1));
        expect(await db.select(db.pedidoItems).get(), hasLength(3));
        expect(encolador.encolados, hasLength(4));
      },
    );

    test(
      'dado que el motor rechaza una línea, entonces nada queda guardado (todo o nada) y la falla es la de guardar',
      () async {
        encolador.fallarCon = StateError('motor apagado');
        encolador.fallarDespuesDe = 2;
        final r = await repo.enviar(pedidoDe());
        expect(r.fold((f) => f, (_) => null), isA<FailurePedidoNoGuardado>());
        expect(await db.select(db.pedidosCasaEditora).get(), isEmpty);
        expect(await db.select(db.pedidoItems).get(), isEmpty);
      },
    );

    test('dado un reintento tras la falla, entonces el mismo id se guarda normalmente', () async {
      encolador.fallarCon = StateError('motor apagado');
      expect((await repo.enviar(pedidoDe())).isLeft(), isTrue);
      encolador.fallarCon = null;
      final r = await repo.enviar(pedidoDe());
      expect(r.getOrElse(() => throw StateError('falló')).yaEstaba, isFalse);
      expect(await db.select(db.pedidosCasaEditora).get(), hasLength(1));
    });
  });

  group('cancelar', () {
    test(
      'dado un pedido por autorizar, cuando se cancela, entonces queda CANCELADO, no se borra y encola el update',
      () async {
        await repo.enviar(pedidoDe());
        encolador.encolados.clear();
        final r = await repo.cancelar(id: 'ped-1', colportorId: 'col-1', ahora: ahoraPedidos);
        expect(r.getOrElse(() => throw StateError('falló')).estado, EstadoDelPedido.cancelado);
        final fila = await db.select(db.pedidosCasaEditora).getSingle();
        expect(fila.estado, 'CANCELADO');
        expect(fila.deletedAt, isNull, reason: 'el pedido no se borra');
        expect(encolador.encolados, hasLength(1));
        expect(encolador.encolados.single.entidad, 'pedido_casa_editora');
        expect(encolador.encolados.single.operacion, OperacionSync.update);
        expect(encolador.encolados.single.payload['estado'], 'CANCELADO');
      },
    );

    test(
      'dado un pedido ya cancelado, entonces cancelar de nuevo responde lo mismo sin encolar',
      () async {
        await repo.enviar(pedidoDe());
        await repo.cancelar(id: 'ped-1', colportorId: 'col-1', ahora: ahoraPedidos);
        encolador.encolados.clear();
        final r = await repo.cancelar(id: 'ped-1', colportorId: 'col-1', ahora: ahoraPedidos);
        expect(r.getOrElse(() => throw StateError('falló')).estado, EstadoDelPedido.cancelado);
        expect(encolador.encolados, isEmpty);
      },
    );

    test(
      'dados un pedido ya autorizado, uno ajeno o uno que no existe, entonces no se puede cancelar',
      () async {
        await repo.enviar(pedidoDe(id: 'ped-1'));
        await (db.update(db.pedidosCasaEditora)..where((p) => p.id.equals('ped-1'))).write(
          const PedidosCasaEditoraCompanion(estado: Value('AUTORIZADO')),
        );
        await repo.enviar(pedidoDe(id: 'ped-2'));
        encolador.encolados.clear();
        for (final (id, colportor) in [
          ('ped-1', 'col-1'),
          ('ped-2', 'otra'),
          ('no-hay', 'col-1'),
        ]) {
          final r = await repo.cancelar(id: id, colportorId: colportor, ahora: ahoraPedidos);
          expect(r.fold((f) => f, (_) => null), isA<FailurePedidoNoCancelable>(), reason: id);
        }
        expect(encolador.encolados, isEmpty);
        expect((await db.select(db.pedidosCasaEditora).get()).map((p) => p.estado).toSet(), {
          'AUTORIZADO',
          'PENDIENTE_AUTORIZACION',
        });
      },
    );
  });

  group('observar', () {
    test(
      'dados varios pedidos, entonces salen el más nuevo primero, con sus líneas, solo los de la colportora',
      () async {
        await repo.enviar(pedidoDe(id: 'viejo', fecha: DateTime.utc(2026, 10, 1)));
        await repo.enviar(pedidoDe(id: 'nuevo', fecha: DateTime.utc(2026, 11, 20)));
        final ajeno = Pedido(
          id: 'ajeno',
          colportorId: 'otra',
          estado: EstadoDelPedido.porAutorizar,
          lineas: const [],
          fecha: ahoraPedidos,
          montoCentavos: 1,
          auditoria: Auditoria(createdAt: ahoraPedidos, updatedAt: ahoraPedidos),
        );
        await repo.enviar(ajeno);
        final lista = await repo.observar('col-1').first;
        expect(lista.map((p) => p.id), ['nuevo', 'viejo']);
        expect(lista.first.lineas, hasLength(3));
      },
    );

    test(
      'dado un pedido que bajó del servidor, entonces se ve su número, su monto autorizado y el motivo',
      () async {
        await db
            .into(db.pedidosCasaEditora)
            .insert(
              PedidosCasaEditoraCompanion.insert(
                id: 'srv-1',
                colportorId: 'col-1',
                fechaPedido: DateTime.utc(2026, 10, 20),
                estado: 'RECHAZADO',
                montoTotal: const Value(2196000),
                motivoRechazo: const Value('Depositá lo que tenés en mano y pedí de nuevo'),
                numero: const Value(231),
                createdAt: DateTime.utc(2026, 10, 20),
                updatedAt: DateTime.utc(2026, 10, 20),
              ),
            );
        final p = (await repo.observar('col-1').first).single;
        expect(p.estado, EstadoDelPedido.rechazado);
        expect(p.numero, 231);
        expect(p.llego, isTrue);
        expect(p.motivoRechazo, 'Depositá lo que tenés en mano y pedí de nuevo');
      },
    );

    test('dado un borrador del servidor, entonces no se muestra', () async {
      await db
          .into(db.pedidosCasaEditora)
          .insert(
            PedidosCasaEditoraCompanion.insert(
              id: 'b-1',
              colportorId: 'col-1',
              fechaPedido: ahoraPedidos,
              estado: 'BORRADOR',
              createdAt: ahoraPedidos,
              updatedAt: ahoraPedidos,
            ),
          );
      expect(await repo.observar('col-1').first, isEmpty);
    });

    test('dado que cambia un pedido, entonces el stream emite de nuevo', () async {
      final emisiones = <int>[];
      final sub = repo.observar('col-1').listen((l) => emisiones.add(l.length));
      await pumpEventQueueDeDrift();
      await repo.enviar(pedidoDe());
      await pumpEventQueueDeDrift();
      await sub.cancel();
      expect(emisiones.first, 0);
      expect(emisiones.last, 1);
    });
  });
}

/// Deja correr las microtareas y los timers cortos de Drift entre un cambio y su emisión.
Future<void> pumpEventQueueDeDrift() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
