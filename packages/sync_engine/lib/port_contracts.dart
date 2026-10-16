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

final _t0 = DateTime.utc(2026, 11, 13, 8);

SyncJob _job(String opId, {String entity = 'venta', int minuto = 0}) => SyncJob(
      clientOpId: opId,
      entity: entity,
      op: Op.insert,
      payload: {'id': 'pk-$opId'},
      createdAt: _t0.add(Duration(minutes: minuto)),
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
  });
}

/// Lo que el motor da por sentado de un [LocalStorePort].
void runLocalStoreContract(String nombre, LocalStorePort Function() crear) {
  group('$nombre · contrato de LocalStorePort', () {
    late LocalStorePort store;
    setUp(() => store = crear());

    test('sin pull previo no hay watermark', () async {
      expect(await store.watermarkOf('replica'), isNull);
    });

    test('applyDelta guarda el watermark del scope', () async {
      await store.applyDelta({
        'producto': [
          {'id': 'p-1', 'sync_version': 1}
        ],
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
  });
}
