import 'dart:async';

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

// #188: un 429 frena toda la subida hasta su Retry-After (tope 60 s; sin
// encabezado, 5 s). La espera es en memoria y el pull sigue.

const _entidades = {'venta', 'jornada', 'producto', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.push('jornada'),
      SyncSpec.pull('producto'),
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

class _Banco {
  _Banco({InMemoryJobStore? jobs, InMemoryLocalStore? store})
      : jobs = jobs ?? InMemoryJobStore(),
        store = store ?? InMemoryLocalStore() {
    motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: this.jobs,
      store: this.store,
      clock: () => ahora,
    );
  }

  final InMemoryJobStore jobs;
  final InMemoryLocalStore store;
  final transport = FakeSyncTransport();
  late final SyncEngine motor;
  DateTime ahora = DateTime.utc(2026, 11, 5, 12);

  void pasan(Duration d) => ahora = ahora.add(d);

  Future<void> encolar(String entidad, String id) =>
      motor.stage(entidad, Op.insert, {'id': id}, clientOpId: 'op-$id');
}

/// Un timer que no corre solo: el test lo dispara cuando mueve el reloj.
class _TimerFalso implements Timer {
  _TimerFalso(this.vence, this._callback);

  final DateTime vence;
  final void Function() _callback;
  bool cancelado = false;
  bool disparado = false;

  void disparar() {
    disparado = true;
    _callback();
  }

  @override
  void cancel() => cancelado = true;

  @override
  bool get isActive => !cancelado && !disparado;

  @override
  int get tick => 0;
}

/// Un motor cuyos timers (el debounce de `critical` y la reanudación del 429)
/// son de mentira y avanzan con el reloj inyectado, para probar que la subida
/// se reanuda sola al vencer la espera sin esperar de verdad.
class _BancoConReloj {
  _BancoConReloj() {
    motor = runZoned(
      () => SyncEngine(
        specs: SpecRegistry([
          SyncSpec.push('venta', critical: true),
        ], allEntities: const {'venta'}),
        transport: transport,
        jobs: jobs,
        store: InMemoryLocalStore(),
        clock: () => ahora,
      ),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duracion, callback) {
          final t = _TimerFalso(ahora.add(duracion), callback);
          timers.add(t);
          return t;
        },
      ),
    );
  }

  final jobs = InMemoryJobStore();
  final transport = FakeSyncTransport();
  final timers = <_TimerFalso>[];
  late final SyncEngine motor;
  DateTime ahora = DateTime.utc(2026, 11, 5, 12);

  Future<void> venta(String id) =>
      motor.stage('venta', Op.insert, {'id': id}, clientOpId: 'op-$id');

  /// Mueve el reloj [d] y dispara, en orden, los timers que vencieron.
  Future<void> avanza(Duration d) async {
    final meta = ahora.add(d);
    while (true) {
      final vencidos = timers.where((t) => t.isActive && !t.vence.isAfter(meta))
          .toList()
        ..sort((a, b) => a.vence.compareTo(b.vence));
      if (vencidos.isEmpty) break;
      final t = vencidos.first;
      if (t.vence.isAfter(ahora)) ahora = t.vence;
      t.disparar();
      await _asentar();
    }
    ahora = meta;
  }

  /// Deja terminar los ciclos que dispararon los timers.
  Future<void> _asentar() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  group('429 con Retry-After', () {
    test('no se sube nada hasta que pasa lo que pidió el servidor', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));

      final primero = await b.motor.syncNow();
      expect(primero.failure?.status, 429);
      expect(b.transport.batches, hasLength(1));
      expect(b.jobs.withState(JobState.pending), hasLength(1),
          reason: 'el 429 no pierde el job: vuelve a PENDING');

      // A los 29 s sigue frenado: ni siquiera se llama al transporte.
      b.pasan(const Duration(seconds: 29));
      final durante = await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1), reason: 'sin reintento');
      expect(durante.pushed, 0);
      expect(durante.pushPausedUntil,
          DateTime.utc(2026, 11, 5, 12).add(const Duration(seconds: 30)));
      expect(b.jobs.withState(JobState.pending), hasLength(1));

      // Vencida la espera, el siguiente intento sube.
      b.pasan(const Duration(seconds: 1));
      final despues = await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2));
      expect(despues.pushed, 1);
      expect(despues.pushPausedUntil, isNull);
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });

    test('un Retry-After más largo que el tope espera 60 s', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(hours: 1));
      await b.motor.syncNow();

      b.pasan(const Duration(seconds: 59));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1));

      b.pasan(const Duration(seconds: 1));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2));
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });
  });

  group('429 sin Retry-After', () {
    test('espera 5 s fijos en vez de reintentar al instante', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429);
      await b.motor.syncNow();

      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1), reason: 'sin ráfaga');

      b.pasan(const Duration(seconds: 4));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1));

      b.pasan(const Duration(seconds: 1));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2));
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });

    test('un Retry-After en cero cuenta como sin encabezado', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: Duration.zero);
      await b.motor.syncNow();

      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1));
      b.pasan(const Duration(seconds: 5));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2));
      await b.motor.dispose();
    });
  });

  group('alcance de la espera', () {
    test('una ráfaga de triggers durante la espera no genera reintentos',
        () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();

      for (final t in [
        SyncTrigger.connectivity,
        SyncTrigger.appResumed,
        SyncTrigger.criticalWrite,
        SyncTrigger.manual,
        SyncTrigger.manual,
      ]) {
        await b.motor.trigger(t);
      }
      expect(b.transport.batches, hasLength(1),
          reason: 'un solo intento contra el servidor que pidió esperar');
      await b.motor.dispose();
    });

    test('frena la subida de todas las entidades, no solo la que rebotó',
        () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();

      // Una escritura nueva de otra entidad durante la espera tampoco sale
      // (si saliera sin lo que nombra, el servidor contestaría 23503).
      await b.encolar('jornada', 'j1');
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1));
      expect(b.jobs.withState(JobState.pending), hasLength(2));

      b.pasan(const Duration(seconds: 30));
      await b.motor.syncNow();
      expect(b.transport.rowsOf('venta'), hasLength(1));
      expect(b.transport.rowsOf('jornada'), hasLength(1));
      await b.motor.dispose();
    });

    test('la bajada sigue mientras la subida espera', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();
      expect(b.transport.pulls, isEmpty,
          reason: 'el ciclo que recibió el 429 se corta, como cualquier falla');

      final durante = await b.motor.syncNow();
      expect(b.transport.pulls, hasLength(1));
      expect(durante.ok, isTrue);
      expect(durante.pushPausedUntil, isNotNull);
      await b.motor.dispose();
    });

    test('el realtime no sube nunca, con o sin espera', () async {
      final b = _Banco();
      final r = await b.motor.trigger(SyncTrigger.realtime);
      expect(r.pushPausedUntil, isNull);
      await b.motor.dispose();
    });

    test('otras fallas transitorias no frenan la subida', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(503);
      await b.motor.syncNow();

      final r = await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2), reason: 'reintenta ya');
      expect(r.pushPausedUntil, isNull);
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });

    test('un 429 del pull también frena la subida', () async {
      final b = _Banco();
      b.transport.failWith(429, retryAfter: const Duration(seconds: 20));
      final r = await b.motor.syncNow();
      expect(r.failure?.status, 429);
      expect(b.transport.pulls, hasLength(1));

      await b.encolar('venta', 'v1');
      await b.motor.syncNow();
      expect(b.transport.batches, isEmpty, reason: 'la subida espera');

      b.pasan(const Duration(seconds: 20));
      await b.motor.syncNow();
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });
  });

  group('casos límite', () {
    test('un segundo 429 al volver renueva la espera', () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 10));
      await b.motor.syncNow();

      b.pasan(const Duration(seconds: 10));
      b.transport.failWith(429, retryAfter: const Duration(seconds: 20));
      final otra = await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2));
      expect(otra.pushPausedUntil, b.ahora.add(const Duration(seconds: 20)));

      b.pasan(const Duration(seconds: 19));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(2));

      b.pasan(const Duration(seconds: 1));
      await b.motor.syncNow();
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });

    test('la espera no se persiste: un motor nuevo sobre la misma cola sube',
        () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();
      await b.motor.dispose();

      // La app se cerró y se volvió a abrir con la cola en disco.
      final b2 = _Banco(jobs: b.jobs, store: b.store);
      await b2.motor.syncNow();
      expect(b2.transport.rowsOf('venta'), hasLength(1));
      await b2.motor.dispose();
    });

    test('lo que se escribe durante la espera sube al vencer, sin pérdidas',
        () async {
      final b = _Banco();
      await b.encolar('venta', 'v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();

      for (var i = 2; i <= 4; i++) {
        await b.encolar('venta', 'v$i');
        await b.motor.syncNow();
      }
      expect(b.transport.batches, hasLength(1));

      b.pasan(const Duration(seconds: 30));
      await b.motor.syncNow();
      expect(b.transport.rowsOf('venta'), hasLength(4));
      expect(b.jobs.withState(JobState.pending), isEmpty);
      await b.motor.dispose();
    });
  });

  group('reanudación al vencer la espera', () {
    test('dos ventas critical dentro de la espera suben solas a los 65 s',
        () async {
      final b = _BancoConReloj();
      await b.venta('v0');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();
      expect(b.transport.batches, hasLength(1));

      // Dos ventas critical dentro de la espera: sus triggers se descartan
      // porque la subida está frenada.
      await b.venta('v1');
      await b.venta('v2');
      await b.avanza(const Duration(seconds: 10));
      expect(b.transport.batches, hasLength(1), reason: 'sigue frenada');

      // Sin ningún trigger más, el motor despierta solo al vencer.
      await b.avanza(const Duration(seconds: 55));
      expect(b.transport.rowsOf('venta'), hasLength(3));
      expect(b.jobs.withState(JobState.pending), isEmpty);
      expect(b.transport.batches, hasLength(2), reason: 'un solo intento');
      await b.motor.dispose();
    });

    test('un trigger durante la espera no sube, pero la reanudación sí',
        () async {
      final b = _BancoConReloj();
      await b.venta('v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();

      b.ahora = b.ahora.add(const Duration(seconds: 5));
      for (final t in [SyncTrigger.appResumed, SyncTrigger.criticalWrite]) {
        await b.motor.trigger(t);
      }
      expect(b.transport.batches, hasLength(1));

      await b.avanza(const Duration(seconds: 26));
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });

    test('sin Retry-After también despierta, a los 5 s', () async {
      final b = _BancoConReloj();
      await b.venta('v1');
      b.transport.failWith(429);
      await b.motor.syncNow();

      await b.avanza(const Duration(seconds: 4));
      expect(b.transport.batches, hasLength(1));
      await b.avanza(const Duration(seconds: 1));
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });

    test('si al volver hay otro 429, espera de nuevo: nunca una ráfaga',
        () async {
      final b = _BancoConReloj();
      await b.venta('v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 10));
      await b.motor.syncNow();
      b.transport.failWith(429, retryAfter: const Duration(seconds: 20));

      await b.avanza(const Duration(seconds: 10));
      expect(b.transport.batches, hasLength(2), reason: 'un intento al vencer');
      expect(b.transport.rowsOf('venta'), isEmpty);

      await b.avanza(const Duration(seconds: 19));
      expect(b.transport.batches, hasLength(2), reason: 'espera renovada');
      await b.avanza(const Duration(seconds: 1));
      expect(b.transport.batches, hasLength(3));
      expect(b.transport.rowsOf('venta'), hasLength(1));
      expect(b.jobs.withState(JobState.pending), isEmpty);
      await b.motor.dispose();
    });

    test('dispose cancela la reanudación pendiente', () async {
      final b = _BancoConReloj();
      await b.venta('v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();
      await b.motor.dispose();

      expect(b.timers.where((t) => t.isActive), isEmpty,
          reason: 'ningún timer queda vivo tras dispose');
      await b.avanza(const Duration(seconds: 65));
      expect(b.transport.batches, hasLength(1));
    });

    test('un reloj que retrocede no deja la subida frenada horas', () async {
      final b = _BancoConReloj();
      await b.venta('v1');
      b.transport.failWith(429, retryAfter: const Duration(seconds: 30));
      await b.motor.syncNow();

      // La hora del teléfono se corrige 3 h hacia atrás.
      b.ahora = b.ahora.subtract(const Duration(hours: 3));
      final r = await b.motor.syncNow();
      expect(r.pushPausedUntil, isNull);
      expect(b.transport.rowsOf('venta'), hasLength(1));
      await b.motor.dispose();
    });
  });
}
