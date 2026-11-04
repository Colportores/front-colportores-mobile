/// Tests de contrato para las implementaciones de los puertos.
///
/// El motor se probó entero contra los fakes de `lib/src/testing/`. Eso deja un
/// agujero: nada garantiza que el `DriftJobStore` de verdad se comporte como el
/// `InMemoryJobStore` con el que se verificó cada invariante. Si el de Drift
/// devuelve los `PENDING` en otro orden, o deja salir un `INVALID` en el claim,
/// el motor hace cosas que ningún test vio.
///
/// Estas suites cierran ese agujero: son la definición ejecutable de cada
/// puerto. La implementación real las corre y, si pasan, el motor se comporta
/// igual que en la VM.
///
/// ```dart
/// // en front-colportores-mobile, con una DB de test
/// void main() {
///   runJobStoreContract('DriftJobStore', () => DriftJobStore(abrirDbEnMemoria()));
///   runLocalStoreContract('DriftLocalStore', () => DriftLocalStore(abrirDbEnMemoria()));
///   runArchiveContract('DriveAdapter', () => DriveAdapter(cuentaDePrueba));
/// }
/// ```
///
/// Los adaptadores que necesitan dispositivo (Drive, keystore) corren estas
/// mismas suites en la mini app de harness, en los hitos I1–I4.
library;

import 'package:test/test.dart';

import 'src/core/model.dart';
import 'src/core/ports.dart';
import 'src/core/queue.dart';

final _t0 = DateTime.utc(2026, 11, 13, 8);

SyncJob _job(String opId, {String entity = 'venta', int minuto = 0}) => SyncJob(
      clientOpId: opId,
      entity: entity,
      op: Op.insert,
      payload: {'id': 'pk-$opId'},
      createdAt: _t0.add(Duration(minutes: minuto)),
    );

/// Una escritura de la fila [fila], como la encola el motor (con `rowPk`).
SyncJob _deFila(String opId, String fila,
        {Op op = Op.update, int? version = 1, int minuto = 0}) =>
    SyncJob(
      clientOpId: opId,
      entity: 'ubicacion',
      op: op,
      payload: {'id': fila},
      syncVersion: op == Op.insert ? null : version,
      createdAt: _t0.add(Duration(minutes: minuto)),
      rowPk: fila,
    );

/// Lo que el motor da por sentado de un [JobStorePort].
void runJobStoreContract(String nombre, JobStorePort Function() crear) {
  group('$nombre · contrato de JobStorePort', () {
    late JobStorePort cola;
    setUp(() => cola = crear());

    test('append deja el job en PENDING y devuelve un id propio', () async {
      final a = await cola.append(_job('op-1'));
      final b = await cola.append(_job('op-2'));

      expect(a, isNot(b), reason: 'dos jobs, dos ids');
      expect((await cola.status()).pending, 2);
    });

    test('claimPending devuelve en orden de creación', () async {
      // A propósito fuera de orden: lo que manda es createdAt, no el insert.
      await cola.append(_job('op-tarde', minuto: 10));
      await cola.append(_job('op-temprano', minuto: 1));

      final tomados = await cola.claimPending(limit: 10);
      expect(tomados.map((j) => j.job.clientOpId), ['op-temprano', 'op-tarde'],
          reason: '§5.5: un update no puede adelantarse al insert de su fila');
    });

    test('lo tomado queda IN_FLIGHT y no vuelve a salir', () async {
      await cola.append(_job('op-1'));

      final primera = await cola.claimPending(limit: 10);
      final segunda = await cola.claimPending(limit: 10);

      expect(primera, hasLength(1));
      expect(segunda, isEmpty,
          reason: 'dos ciclos tomarían el mismo job y lo mandarían dos veces');
      expect((await cola.status()).inFlight, 1);
    });

    test('claimPending respeta el límite', () async {
      for (var i = 0; i < 5; i++) {
        await cola.append(_job('op-$i', minuto: i));
      }
      expect(await cola.claimPending(limit: 2), hasLength(2));
      expect((await cola.status()).pending, 3);
    });

    test('markDone cierra el job', () async {
      final id = await cola.append(_job('op-1'));
      await cola.claimPending(limit: 10);
      await cola.markDone([id], at: _t0);

      final estado = await cola.status();
      expect(estado.inFlight, 0);
      expect(estado.pending, 0);
      expect(estado.invalid, 0);
    });

    test('status dice cuándo se cerró el último job (lastPushAt)', () async {
      expect((await cola.status()).lastPushAt, isNull,
          reason: 'sin nada enviado no hay fecha que mostrar');
      final a = await cola.append(_job('op-1', minuto: 1));
      final b = await cola.append(_job('op-2', minuto: 2));
      await cola.claimPending(limit: 10);

      await cola.markDone([b], at: _t0.add(const Duration(minutes: 5)));
      await cola.markDone([a], at: _t0);

      expect((await cola.status()).lastPushAt, _t0.add(const Duration(minutes: 5)),
          reason: 'es el DONE más nuevo, no el último que se marcó');
    });

    test('markPending devuelve el job a la cola tal cual', () async {
      final id = await cola.append(_job('op-1'));
      await cola.claimPending(limit: 10);
      await cola.markPending([id]);

      expect((await cola.status()).pending, 1);
      expect(await cola.claimPending(limit: 10), hasLength(1),
          reason: 'sin retry counter: vuelve a salir igual que la primera vez');
    });

    test('markInvalid guarda el código y saca el job de circulación', () async {
      final id = await cola.append(_job('op-1'));
      await cola.claimPending(limit: 10);
      await cola.markInvalid(id, code: 'VENTA_SIN_ITEMS', message: 'sin items');

      expect((await cola.status()).invalid, 1);
      expect(await cola.claimPending(limit: 10), isEmpty,
          reason: 'los INVALID no se reintentan solos');
    });

    test('requeue lo devuelve a PENDING y limpia el error anterior', () async {
      final id = await cola.append(_job('op-1'));
      await cola.claimPending(limit: 10);
      await cola.markInvalid(id, code: 'VENTA_SIN_ITEMS');
      await cola.requeue(id);

      expect((await cola.status()).invalid, 0);
      final tomados = await cola.claimPending(limit: 10);
      expect(tomados, hasLength(1));
      expect(tomados.single.code, isEmpty,
          reason: 'el error viejo no puede quedar pegado al job corregido');
    });

    test('listInvalid devuelve los jobs en error, con su código', () async {
      final a = await cola.append(_job('op-a'));
      final b = await cola.append(_job('op-b', minuto: 1));
      await cola.claimPending(limit: 10);
      await cola.markInvalid(a,
          code: 'PRODUCTO_INEXISTENTE', message: 'pk 812');
      await cola.markDone([b], at: _t0);

      final enError = await cola.listInvalid(limit: 100);

      expect(enError, hasLength(1), reason: 'solo los INVALID');
      expect(enError.single.id, a,
          reason: 'el id es lo que la UI le pasa a requeue()');
      expect(enError.single.code, 'PRODUCTO_INEXISTENTE');
      expect(enError.single.message, 'pk 812');
      expect(enError.single.job.entity, 'venta',
          reason: 'la app necesita el job para mostrar de qué se trata');
    });

    test('discardInvalid borra los INVALID que se le pasan', () async {
      final a = await cola.append(_job('op-a'));
      final b = await cola.append(_job('op-b', minuto: 1));
      await cola.claimPending(limit: 10);
      await cola.markInvalid(a, code: 'PK_PRODUCTO_NULO');
      await cola.markInvalid(b, code: 'FECHA_INVALIDA');

      expect(await cola.discardInvalid([a]), 1);
      expect((await cola.status()).invalid, 1);
      expect((await cola.listInvalid(limit: 10)).single.id, b,
          reason: 'se descarta el que se pidió, no la cola entera');
    });

    test('discardInvalid no toca lo que no está en INVALID', () async {
      final pendiente = await cola.append(_job('op-pendiente'));
      final enVuelo = await cola.append(_job('op-vuelo', minuto: 1));
      await cola.claimPending(limit: 1);

      expect(await cola.discardInvalid([pendiente, enVuelo]), 0);
      expect((await cola.status()).pending, 1,
          reason: 'esa venta todavía tiene que subir');
      expect((await cola.status()).inFlight, 1,
          reason: 'hay un ciclo con ese job en la mano; borrarlo por abajo lo '
              'dejaría resolviendo algo que ya no existe');
    });

    test('discardInvalid ignora un id que ya no está', () async {
      final id = await cola.append(_job('op-1'));
      await cola.claimPending(limit: 10);
      await cola.markInvalid(id, code: 'X');

      expect(await cola.discardInvalid([id, 'job-que-no-existe']), 1,
          reason: 'la pantalla descarta la lista que leyó hace un segundo: si '
              'uno de esos jobs ya se movió, el resto igual se borra');
    });

    test('listInvalid respeta el límite', () async {
      for (var i = 0; i < 5; i++) {
        final id = await cola.append(_job('op-$i', minuto: i));
        await cola.claimPending(limit: 10);
        await cola.markInvalid(id, code: 'X');
      }
      expect(await cola.listInvalid(limit: 2), hasLength(2));
    });

    test('purgeDone borra solo los DONE viejos', () async {
      final viejo = await cola.append(_job('op-viejo'));
      final nuevo = await cola.append(_job('op-nuevo', minuto: 1));
      final pendiente = await cola.append(_job('op-pendiente', minuto: 2));
      expect(pendiente, isNotNull);

      final tomados = await cola.claimPending(limit: 2);
      expect(tomados, hasLength(2));
      await cola.markDone([viejo], at: _t0.subtract(const Duration(days: 30)));
      await cola.markDone([nuevo], at: _t0);

      final borrados =
          await cola.purgeDone(_t0.subtract(const Duration(days: 7)));

      expect(borrados, 1, reason: 'solo el DONE anterior al corte');
      expect((await cola.status()).pending, 1,
          reason: 'un job pendiente no se purga jamás');
    });

    test('el estado cuenta cada cosa donde va', () async {
      final a = await cola.append(_job('op-a'));
      final b = await cola.append(_job('op-b', minuto: 1));
      await cola.append(_job('op-c', minuto: 2));

      await cola.claimPending(limit: 2);
      await cola.markInvalid(a, code: 'X');

      final estado = await cola.status();
      expect(estado.pending, 1);
      expect(estado.inFlight, 1);
      expect(estado.invalid, 1);
      expect(b, isNotNull);
    });

    // El reclamo va por **antigüedad**, y las dos mitades importan. Sin la
    // primera, un job que quedó colgado cuando murió el proceso no sube nunca
    // más. Sin la segunda, el ciclo de segundo plano (RF-SY07) —que corre en
    // otro isolate sobre la misma cola— le roba jobs al primer plano que los
    // está mandando, y el colportor paga el viaje dos veces (RR-07).
    group('reclaimInFlight va por antigüedad', () {
      test('lo vencido vuelve a PENDING', () async {
        final cola = crear();
        await cola.append(_job('op-a'));
        await cola.claimPending(limit: 10);

        expect(await cola.reclaimInFlight(Duration.zero), 1);
        expect((await cola.status()).pending, 1);
        expect((await cola.status()).inFlight, 0);
      });

      test('lo recién tomado no se toca: puede estar viajando', () async {
        final cola = crear();
        await cola.append(_job('op-a'));
        await cola.claimPending(limit: 10);

        expect(await cola.reclaimInFlight(const Duration(hours: 1)), 0);
        expect((await cola.status()).inFlight, 1,
            reason: 'reclamarlo acá sería reenviarlo mientras el otro ciclo '
                'todavía lo tiene en la mano');
      });

      test('no toca lo que no está en vuelo', () async {
        final cola = crear();
        await cola.append(_job('op-a'));
        final b = await cola.append(_job('op-b', minuto: 1));
        await cola.claimPending(limit: 1);
        await cola.markInvalid(b, code: 'X');

        await cola.reclaimInFlight(Duration.zero);

        final estado = await cola.status();
        expect(estado.invalid, 1,
            reason: 'un INVALID vuelve a la cola solo con requeue(), nunca '
                'solo (§5.1)');
      });
    });

    // §5.4: las escrituras de una fila, para fundirlas y para que esperen la
    // versión que de verdad tiene el servidor.
    group('escrituras de una fila', () {
      test('unsentFor trae lo sin mandar de esa fila, en orden de creación',
          () async {
        final cola = crear();
        final enVuelo = await cola.append(_deFila('op-1', 'u-1'));
        await cola.claimPending(limit: 1);
        final a = await cola.append(_deFila('op-2', 'u-1', minuto: 2));
        final b = await cola.append(_deFila('op-3', 'u-1', minuto: 1));
        await cola.append(_deFila('op-4', 'u-2', minuto: 3));
        await cola.append(_job('op-5', minuto: 4));

        final deLaFila = await cola.unsentFor('ubicacion', 'u-1');

        expect([for (final q in deLaFila) q.id], [b, a],
            reason: 'ni lo que está en vuelo ($enVuelo) ni otras filas');
      });

      test('unsentFor incluye lo que espera, y no lo que ya terminó', () async {
        final cola = crear();
        final bloqueado = await cola.append(_deFila('op-1', 'u-1'));
        final hecho = await cola.append(_deFila('op-2', 'u-1', minuto: 1));
        final invalido = await cola.append(_deFila('op-3', 'u-1', minuto: 2));
        await cola.claimPending(limit: 3);
        await cola.markBlocked(bloqueado, code: '23505');
        await cola.markDone([hecho], at: _t0);
        await cola.markInvalid(invalido, code: 'X');

        expect([for (final q in await cola.unsentFor('ubicacion', 'u-1')) q.id],
            [bloqueado]);
      });

      test('replacePayload también vale sobre lo PENDING', () async {
        final cola = crear();
        final id = await cola.append(_deFila('op-1', 'u-1'));

        await cola.replacePayload(id, {'id': 'u-1', 'calle': 'nueva'});

        final [q] = await cola.claimPending(limit: 1);
        expect(q.job.payload, {'id': 'u-1', 'calle': 'nueva'});
        expect(q.job.rowPk, 'u-1');
      });

      test('replacePayload no toca lo que ya salió', () async {
        final cola = crear();
        final id = await cola.append(_deFila('op-1', 'u-1'));
        await cola.claimPending(limit: 1);

        expect(() => cola.replacePayload(id, {'id': 'u-1'}), throwsA(anything));
      });

      test(
          'rebaseVersions cambia la versión esperada de lo no aplicado, en '
          'vuelo incluido, y no de las altas', () async {
        final cola = crear();
        final enVuelo = await cola.append(_deFila('op-1', 'u-1'));
        await cola.claimPending(limit: 1);
        final pendiente = await cola.append(_deFila('op-2', 'u-1', minuto: 1));
        final alta =
            await cola.append(_deFila('op-3', 'u-2', op: Op.insert, minuto: 2));
        final otra = await cola.append(_deFila('op-4', 'u-3', minuto: 3));

        await cola.rebaseVersions('ubicacion', {'u-1': 7, 'u-2': 7});
        await cola.markPending([enVuelo]);

        final versiones = {
          for (final q in await cola.claimPending(limit: 10))
            q.id: q.job.syncVersion
        };
        expect(versiones, {enVuelo: 7, pendiente: 7, alta: null, otra: 1});
      });

      test('rebaseVersions no toca lo que ya terminó', () async {
        final cola = crear();
        final id = await cola.append(_deFila('op-1', 'u-1'));
        await cola.claimPending(limit: 1);
        await cola.markInvalid(id, code: 'X');

        await cola.rebaseVersions('ubicacion', {'u-1': 7});

        final [q] = await cola.listInvalid();
        expect(q.job.syncVersion, 1);
      });
    });

    // §2.2: el alta en conflicto (BLOCKED) y lo que cuelga de ella (WAITING).
    group('en espera', () {
      /// Encola [opIds] en orden, los toma y deja el primero BLOCKED y el
      /// resto WAITING de él. Devuelve los ids en el mismo orden.
      Future<List<String>> enEspera(
          JobStorePort cola, List<String> opIds) async {
        final ids = [
          for (final (i, op) in opIds.indexed)
            await cola.append(_job(op, minuto: i)),
        ];
        await cola.claimPending(limit: ids.length);
        await cola.markBlocked(ids.first, code: '23505', message: 'D1');
        for (final id in ids.skip(1)) {
          await cola.markWaiting(id,
              dependsOn: 'pk-${opIds.first}', code: 'ESPERA_ALTA_EN_CONFLICTO');
        }
        return ids;
      }

      test('markBlocked y markWaiting guardan el porqué y lo sacan del claim',
          () async {
        final cola = crear();
        await enEspera(cola, ['op-alta', 'op-espacio']);

        expect(await cola.claimPending(limit: 10), isEmpty,
            reason: 'lo que espera no se reintenta solo');
        final s = await cola.status();
        expect((s.blocked, s.waiting, s.pending, s.inFlight), (1, 1, 0, 0));

        final retenidos = await cola.listHeld();
        expect([for (final q in retenidos) q.state],
            [JobState.blocked, JobState.waiting]);
        expect(retenidos.first.code, '23505');
        expect(retenidos.first.message, 'D1');
        expect(retenidos.first.dependsOn, isNull);
        expect(retenidos.last.dependsOn, 'pk-op-alta');
        expect(retenidos.last.code, 'ESPERA_ALTA_EN_CONFLICTO');
      });

      test('listHeld no trae lo que no espera, y va en orden de creación',
          () async {
        final cola = crear();
        await cola.append(_job('op-suelto', minuto: 30));
        await enEspera(cola, ['op-alta', 'op-espacio', 'op-venta']);

        expect([for (final q in await cola.listHeld()) q.job.clientOpId],
            ['op-alta', 'op-espacio', 'op-venta']);
      });

      test('replacePayload cambia el payload y nada más', () async {
        final cola = crear();
        final [alta, _] = await enEspera(cola, ['op-alta', 'op-espacio']);

        await cola.replacePayload(alta, {'id': 'pk-op-alta', 'calle': 'nueva'});

        final q = (await cola.listHeld()).first;
        expect(q.job.payload, {'id': 'pk-op-alta', 'calle': 'nueva'});
        expect(q.job.clientOpId, 'op-alta',
            reason: 'es el mismo intento: el servidor nunca lo aplicó');
        expect(q.job.op, Op.insert);
        expect(q.state, JobState.blocked);
      });

      test('release los devuelve detrás de todo, en el orden pedido', () async {
        final cola = crear();
        final [alta, espacio] = await enEspera(cola, ['op-alta', 'op-espacio']);
        // Lo que la app encola para resolver el conflicto, antes de liberar.
        await cola.append(_job('op-par', minuto: 60));

        await cola.release([alta, espacio],
            at: _t0.add(const Duration(minutes: 61)));

        final tomados = await cola.claimPending(limit: 10);
        expect([for (final q in tomados) q.job.clientOpId],
            ['op-par', 'op-alta', 'op-espacio']);
        expect(await cola.listHeld(), isEmpty);
      });

      test('release al mismo instante que lo último encolado igual va detrás',
          () async {
        final cola = crear();
        final [alta, espacio] = await enEspera(cola, ['op-alta', 'op-espacio']);
        await cola.append(_job('op-par', minuto: 60));

        await cola.release([alta, espacio],
            at: _t0.add(const Duration(minutes: 60)));

        final tomados = await cola.claimPending(limit: 10);
        expect([for (final q in tomados) q.job.clientOpId],
            ['op-par', 'op-alta', 'op-espacio']);
      });

      test('listPending trae solo los PENDING, en orden de creación', () async {
        final cola = crear();
        await cola.append(_job('op-b', minuto: 20));
        await cola.append(_job('op-a', minuto: 10));
        await enEspera(cola, ['op-alta', 'op-espacio']);

        expect([for (final q in await cola.listPending()) q.job.clientOpId],
            ['op-a', 'op-b']);
        await cola.claimPending(limit: 1);
        expect([for (final q in await cola.listPending()) q.job.clientOpId],
            ['op-b'],
            reason: 'lo que ya se tomó no es PENDING');
      });

      test(
          'release también reubica un PENDING detrás de todo, y sigue PENDING',
          () async {
        final cola = crear();
        final [alta] = await enEspera(cola, ['op-alta']);
        // Lo que cuelga del alta pero nunca llegó a quedar en espera: se
        // encoló antes que el ciclo que lo habría retenido.
        final colgado = await cola.append(_job('op-colgado', minuto: 10));
        await cola.append(_job('op-par', minuto: 20));

        await cola.release([alta, colgado],
            at: _t0.add(const Duration(minutes: 5)));

        final tomados = await cola.claimPending(limit: 10);
        expect([for (final q in tomados) q.job.clientOpId],
            ['op-par', 'op-alta', 'op-colgado']);
      });

      test('release limpia el error y dependsOn', () async {
        final cola = crear();
        final ids = await enEspera(cola, ['op-alta', 'op-espacio']);

        await cola.release(ids, at: _t0.add(const Duration(hours: 1)));
        final tomados = await cola.claimPending(limit: 10);
        await cola.markInvalid(tomados.last.id, code: 'X');

        final [invalido] = await cola.listInvalid();
        expect(invalido.dependsOn, isNull);
        expect((await cola.status()).blocked, 0);
      });

      test('release no toca lo que no espera', () async {
        final cola = crear();
        final suelto = await cola.append(_job('op-suelto'));
        await cola.claimPending(limit: 1);
        await cola.markInvalid(suelto, code: 'X');

        await cola.release([suelto], at: _t0.add(const Duration(hours: 1)));

        expect((await cola.status()).invalid, 1);
      });

      test('discardHeld borra lo que espera y nada más', () async {
        final cola = crear();
        final suelto = await cola.append(_job('op-suelto', minuto: 30));
        final [alta, espacio] = await enEspera(cola, ['op-alta', 'op-espacio']);

        expect(await cola.discardHeld([alta, suelto, 'no-existe']), 1);

        final s = await cola.status();
        expect((s.blocked, s.waiting, s.pending), (0, 1, 1));
        expect([for (final q in await cola.listHeld()) q.id], [espacio]);
      });
    });
  });
}

/// Lo que el motor da por sentado de un [LocalStorePort].
///
/// [fila] es la que se aplica en el delta de prueba: una entidad que la
/// implementación acepte, con su fila. Una DB real no tiene tablas genéricas.
void runLocalStoreContract(
  String nombre,
  LocalStorePort Function() crear, {
  ({String entidad, Map<String, Object?> fila}) fila = (
    entidad: 'producto',
    fila: const {'id': 'p-1', 'sync_version': 1},
  ),
}) {
  group('$nombre · contrato de LocalStorePort', () {
    late LocalStorePort store;
    setUp(() => store = crear());

    test('sin pull previo no hay watermark', () async {
      expect(await store.watermarkOf('replica'), isNull);
    });

    test('applyDelta guarda el watermark del scope', () async {
      await store.applyDelta({
        fila.entidad: [fila.fila],
      }, scope: 'replica', watermark: 'w-1');

      expect(await store.watermarkOf('replica'), 'w-1');
    });

    test('los scopes no se pisan', () async {
      await store.applyDelta(const {}, scope: 'replica', watermark: 'w-1');
      await store.applyDelta(const {}, scope: 'mirror', watermark: 'w-99');

      expect(await store.watermarkOf('replica'), 'w-1');
      expect(await store.watermarkOf('mirror'), 'w-99');
    });

    test('un delta vacío igual guarda el watermark', () async {
      // La fase 1 de §7 lo usa para dejar puesto el watermark del backup sin
      // escribir ninguna fila. Si esta implementación se saltea el guardado
      // cuando no hay filas, la reconciliación arranca desde cero y rebaja
      // todo lo que la DB restaurada ya tenía.
      await store
          .applyDelta(const {}, scope: 'mirror', watermark: 'w-del-backup');
      expect(await store.watermarkOf('mirror'), 'w-del-backup');
    });

    test('applyDelta sin watermark escribe la fila y deja el que había',
        () async {
      // El LWW (§5.4) aplica la `server_row` de un conflicto sin pasar por una
      // página de pull. Con `''` el backend contesta 22023 en la próxima
      // reconciliación; con el watermark pisado, se saltearía lo que falta.
      await store.applyDelta(const {}, scope: 'mirror', watermark: 'w-1');
      await store.applyDelta({
        fila.entidad: [fila.fila],
      }, scope: 'mirror', watermark: null);
      expect(await store.watermarkOf('mirror'), 'w-1');

      await store.applyDelta({
        fila.entidad: [fila.fila],
      }, scope: 'otro', watermark: null);
      expect(await store.watermarkOf('otro'), isNull,
          reason: 'no se inventa un watermark vacío');
    });

    test('aplicar dos veces avanza el watermark, no lo retrocede', () async {
      await store.applyDelta(const {}, scope: 'replica', watermark: 'w-1');
      await store.applyDelta(const {}, scope: 'replica', watermark: 'w-2');
      expect(await store.watermarkOf('replica'), 'w-2');
    });
  });
}

/// Lo que el motor da por sentado de un [ArchivePort].
///
/// [crear] tiene que devolver un archivo **vacío y autorizado**. Contra Drive
/// real, eso significa una carpeta de pruebas que se limpia entre corridas.
void runArchiveContract(String nombre, ArchivePort Function() crear) {
  group('$nombre · contrato de ArchivePort', () {
    late ArchivePort archivo;
    setUp(() => archivo = crear());

    test('un archivo nuevo está vacío', () async {
      expect(await archivo.list(), isEmpty);
    });

    test('la primera subida es la base de la cadena', () async {
      final base = await archivo
          .upload(payload: const [1, 2, 3], parentId: null, watermark: 'w-1');

      expect(base.isBase, isTrue);
      expect(base.parentId, isNull);
      expect(base.watermark, 'w-1');
      expect(base.contentHash, isNotEmpty);
    });

    test('cada subida es una entrada nueva, con id propio', () async {
      final base = await archivo
          .upload(payload: const [1], parentId: null, watermark: 'w-1');
      final inc = await archivo
          .upload(payload: const [2], parentId: base.id, watermark: 'w-2');

      expect(inc.id, isNot(base.id));
      expect(inc.parentId, base.id);
      expect(await archivo.list(), hasLength(2));
    });

    test('download devuelve exactamente lo que se subió', () async {
      const payload = [10, 20, 30, 255, 0];
      final e = await archivo.upload(
          payload: payload, parentId: null, watermark: 'w-1');

      expect(await archivo.download(e.id), payload,
          reason: 'un byte cambiado rompe el descifrado del backup entero');
    });

    test('el hash distingue payloads distintos', () async {
      final a = await archivo
          .upload(payload: const [1, 2, 3], parentId: null, watermark: 'w-1');
      final b = await archivo
          .upload(payload: const [9, 9, 9], parentId: a.id, watermark: 'w-2');

      expect(a.contentHash, isNot(b.contentHash),
          reason: 'sin esto, verifyChain no detecta una entrada corrupta');
    });

    test('list sobrevive al orden: la cadena se arma por parentId', () async {
      final base = await archivo
          .upload(payload: const [1], parentId: null, watermark: 'w-1');
      await archivo
          .upload(payload: const [2], parentId: base.id, watermark: 'w-2');

      final ids = (await archivo.list()).map((e) => e.id).toSet();
      expect(ids, hasLength(2),
          reason: 'list no puede perder ni repetir entradas');
    });

    test('exportedAt viaja con la entrada y vuelve en list', () async {
      final instante = DateTime.utc(2026, 10, 28, 22, 15, 3, 120);
      final e = await archivo.upload(
        payload: const [1],
        parentId: null,
        watermark: 'w-1',
        exportedAt: instante,
      );

      expect(e.exportedAt, instante);
      expect((await archivo.list()).single.exportedAt, instante,
          reason: 'el incremental siguiente parte de este instante, no de la '
              'fecha de subida: sin él se pierden las filas escritas mientras '
              'subía');
    });

    test('delete saca la entrada del listado y borrar dos veces no falla',
        () async {
      final base = await archivo
          .upload(payload: const [1], parentId: null, watermark: 'w-1');
      final otra = await archivo
          .upload(payload: const [2], parentId: null, watermark: 'w-2');

      await archivo.delete(base.id);
      await archivo.delete(base.id);

      expect((await archivo.list()).map((e) => e.id), [otra.id]);
    });
  });
}

/// Lo que el motor da por sentado de un [SyncMetaPort] (HU-SYNC-007).
void runSyncMetaContract(String nombre, SyncMetaPort Function() crear) {
  group('$nombre · contrato de SyncMetaPort', () {
    late SyncMetaPort meta;
    setUp(() => meta = crear());

    test('sin nada anotado, todo es null: «todavía no hubo»', () async {
      final m = await meta.read();

      expect(m.lastPullAt, isNull);
      expect(m.lastBackupAt, isNull);
      expect(m.lastPushAt, isNull);
      expect(m.lastPushNetwork, isNull);
    });

    test('lo anotado vuelve igual', () async {
      await meta.write(
        lastPullAt: _t0,
        lastBackupAt: _t0.add(const Duration(hours: 1)),
        lastPushAt: _t0.add(const Duration(hours: 2)),
        lastPushNetwork: SyncNetwork.mobile,
      );

      final m = await meta.read();
      expect(m.lastPullAt, _t0);
      expect(m.lastBackupAt, _t0.add(const Duration(hours: 1)));
      expect(m.lastPushAt, _t0.add(const Duration(hours: 2)));
      expect(m.lastPushNetwork, SyncNetwork.mobile);
    });

    test('anotar un campo no borra los demás', () async {
      await meta.write(lastPullAt: _t0, lastBackupAt: _t0);
      await meta.write(lastPullAt: _t0.add(const Duration(minutes: 5)));

      final m = await meta.read();
      expect(m.lastPullAt, _t0.add(const Duration(minutes: 5)));
      expect(m.lastBackupAt, _t0,
          reason: 'un campo null es «no lo toques», nunca «borralo»');
    });

    test('un envío más viejo que el anotado no lo pisa', () async {
      final nuevo = _t0.add(const Duration(hours: 1));
      await meta.write(lastPushAt: nuevo, lastPushNetwork: SyncNetwork.wifi);
      await meta.write(lastPushAt: _t0, lastPushNetwork: SyncNetwork.mobile);

      final m = await meta.read();
      expect(m.lastPushAt, nuevo);
      expect(m.lastPushNetwork, SyncNetwork.wifi,
          reason: 'la red es la del envío más nuevo');
    });

    test('un envío nuevo sin red conocida borra la red del anterior', () async {
      await meta.write(lastPushAt: _t0, lastPushNetwork: SyncNetwork.mobile);
      await meta.write(lastPushAt: _t0.add(const Duration(minutes: 1)));

      final m = await meta.read();
      expect(m.lastPushAt, _t0.add(const Duration(minutes: 1)));
      expect(m.lastPushNetwork, isNull,
          reason: 'decir «por datos» de un envío que salió por otra red miente');
    });
  });
}
