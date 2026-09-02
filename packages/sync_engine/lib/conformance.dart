/// La suite de conformidad del contrato (§8).
///
/// El paquete la **publica** para que corra en el CI de la app: no alcanza con
/// que el motor esté bien, hay que verificar que la app lo declaró bien. Un
/// `SyncSpec` mal puesto es una fuga de datos personales, y eso no lo puede
/// atrapar un test que viva de este lado.
///
/// En el repo de la app, un archivo de test de una línea:
///
/// ```dart
/// import 'package:sync_engine/conformance.dart';
///
/// void main() => runConformanceSuite(ConformanceFixture(
///       specs: appSyncSpecs,
///       allEntities: appDb.allTables.map((t) => t.actualTableName).toSet(),
///       adapters: appSyncAdapters,
///     ));
/// ```
library;

import 'package:test/test.dart';

import 'src/core/adapter.dart';
import 'src/core/engine.dart';
import 'src/core/errors.dart';
import 'src/core/model.dart';
import 'src/core/spec.dart';
import 'src/testing/fake_sync_transport.dart';
import 'src/testing/in_memory_stores.dart';

export 'src/core/adapter.dart' show SyncTableAdapter;
export 'src/core/spec.dart' show SyncSpec;

/// Lo que la app le da a la suite para que la pueda verificar.
class ConformanceFixture {
  const ConformanceFixture({
    required this.specs,
    required this.allEntities,
    this.adapters = const [],
    this.samples = const {},
    this.mustBeLocal = const {'persona', 'nota'},
  });

  /// La declaración de §3, tal como la arma la app.
  final List<SyncSpec> specs;

  /// **Todas** las tablas de la DB local, no solo las declaradas. Es lo que
  /// permite detectar la tabla nueva que nadie registró.
  final Set<String> allEntities;

  /// Un adaptador por entidad `push`/`pull`.
  final List<SyncTableAdapter<Object?>> adapters;

  /// Filas de ejemplo por entidad remota, para el round-trip. Sin ejemplo, un
  /// adaptador no se puede verificar y la suite lo dice.
  final Map<String, List<Object?>> samples;

  /// Las entidades que el contrato exige que sean `local`.
  ///
  /// No es configurable por comodidad: está acá para que agregar una entidad
  /// con datos personales sea un cambio explícito y revisable en el CI de la
  /// app, no un olvido.
  final Set<String> mustBeLocal;
}

/// Corre la suite. Llamala desde `main()` de un test de la app.
void runConformanceSuite(ConformanceFixture fixture) {
  late SpecRegistry registro;

  setUpAll(() {
    registro = SpecRegistry(fixture.specs, allEntities: fixture.allEntities);
  });

  group('§2 · datos personales', () {
    test('las entidades con PII están declaradas local', () {
      for (final entidad in fixture.mustBeLocal) {
        expect(registro.policyOf(entidad), SyncPolicy.local,
            reason: '$entidad no puede salir del dispositivo por sync. '
                'Si esto falla, alguien le cambió la política.');
      }
    });

    test('ninguna entidad local sube ni baja', () {
      for (final entidad in fixture.mustBeLocal) {
        expect(registro.pushable, isNot(contains(entidad)));
        expect(registro.pullable, isNot(contains(entidad)));
      }
    });

    test('stage() sobre una entidad local lanza LocalOnlyViolationError',
        () async {
      final (:engine, :jobs, transport: _, store: _) = _armar(registro);

      for (final entidad in fixture.mustBeLocal) {
        await expectLater(
          engine.stage(entidad, Op.insert, const {'id': 'x'},
              clientOpId: 'op-conformidad'),
          throwsA(isA<LocalOnlyViolationError>()),
          reason: entidad,
        );
      }

      expect(jobs.all, isEmpty, reason: 'no llega ni a entrar en sync_queue');
      await engine.dispose();
    });

    test('ninguna entidad local tiene adaptador', () {
      final conAdaptador = fixture.adapters.map((a) => a.remoteName).toSet();
      for (final entidad in fixture.mustBeLocal) {
        expect(conAdaptador, isNot(contains(entidad)),
            reason: 'un adaptador es una forma remota, y $entidad no tiene');
      }
    });
  });

  group('§2 · toda entidad tiene exactamente una política', () {
    test('ninguna tabla de la DB quedó sin SyncSpec', () {
      // El constructor de SpecRegistry ya lo verifica; esto lo deja explícito
      // en el reporte del CI, con el nombre de la tabla que falta.
      expect(
        () => SpecRegistry(fixture.specs, allEntities: fixture.allEntities),
        returnsNormally,
      );
    });

    test('cada entidad push/pull tiene su SyncTableAdapter', () {
      final conAdaptador = fixture.adapters.map((a) => a.remoteName).toSet();
      final necesarias = {...registro.pushable, ...registro.pullable};
      expect(necesarias.difference(conAdaptador), isEmpty,
          reason: 'sin adaptador, esa entidad no se puede serializar');
    });
  });

  group('§8 · round-trip de los adaptadores', () {
    for (final adaptador in fixture.adapters) {
      final ejemplos = fixture.samples[adaptador.remoteName];

      test('${adaptador.remoteName}: toSyncJson → fromSyncJson es identidad',
          () {
        expect(ejemplos, isNotNull,
            reason: 'falta una fila de ejemplo en samples para '
                '${adaptador.remoteName}: sin eso el adaptador no se verifica');
        expect(ejemplos, isNotEmpty);

        for (final fila in ejemplos!) {
          final ida = adaptador.toSyncJson(fila);
          final vuelta = adaptador.toSyncJson(adaptador.fromSyncJson(ida));
          expect(vuelta, equals(ida),
              reason: 'un campo se pierde o se transforma en el viaje');
        }
      });
    }
  });

  group('§5.1 · máquina de estados', () {
    test('un 422 termina en INVALID y no se reintenta solo', () async {
      final (:engine, :jobs, :transport, store: _) = _armar(registro);
      final entidad = _entidadDePrueba(registro);
      final id = await engine.stage(entidad, Op.insert, const {'id': 'c-1'},
          clientOpId: 'op-422');
      await engine.settled;

      transport.failWith(422, code: 'CONFORMIDAD');
      await engine.syncNow();
      expect(jobs.byId(id).state, JobState.invalid);

      await engine.syncNow();
      expect(jobs.byId(id).state, JobState.invalid,
          reason: 'los INVALID no vuelven solos: solo requeue()');

      await engine.requeue(id);
      await engine.syncNow();
      expect(jobs.byId(id).state, JobState.done);
      await engine.dispose();
    });

    test('discard() saca un INVALID de la cola y no vuelve', () async {
      final (:engine, :jobs, :transport, store: _) = _armar(registro);
      final entidad = _entidadDePrueba(registro);
      final id = await engine.stage(entidad, Op.insert, const {'id': 'c-3'},
          clientOpId: 'op-descarte');
      await engine.settled;

      transport.failWith(422, code: 'CONFORMIDAD');
      await engine.syncNow();
      expect(jobs.byId(id).state, JobState.invalid);

      expect(await engine.discard([id]), 1);
      expect(jobs.all.map((j) => j.id), isNot(contains(id)),
          reason: 'descartar borra: no deja el mismo job con otro nombre');
      expect((await jobs.status()).invalid, 0,
          reason: 'el contador de la pantalla tiene que bajar');

      // `failWith` se consume sola, así que este ciclo ya sale bien: lo que
      // se está probando es que no quede nada que mandar.
      await engine.syncNow();
      expect(jobs.all, isEmpty, reason: 'un descartado no se reintenta solo');
      await engine.dispose();
    });

    test('discard() no toca lo que todavía va a subir', () async {
      final (:engine, :jobs, transport: _, store: _) = _armar(registro);
      final entidad = _entidadDePrueba(registro);
      final id = await engine.stage(entidad, Op.insert, const {'id': 'c-4'},
          clientOpId: 'op-pendiente');
      await engine.settled;

      expect(await engine.discard([id]), 0,
          reason: 'un PENDING es una venta que todavía no viajó; borrarla '
              'desde la cola de error sería perderla sin que nadie lo pida');
      expect(jobs.byId(id).state, JobState.pending);
      await engine.dispose();
    });

    test('un timeout termina en PENDING y se reintenta al trigger siguiente',
        () async {
      final (:engine, :jobs, :transport, store: _) = _armar(registro);
      final entidad = _entidadDePrueba(registro);
      final id = await engine.stage(entidad, Op.insert, const {'id': 'c-2'},
          clientOpId: 'op-timeout');
      await engine.settled;

      transport.failTransient();
      expect((await engine.syncNow()).ok, isFalse);
      expect(jobs.byId(id).state, JobState.pending,
          reason: 'sin retry counter: vuelve a la cola tal cual');

      expect((await engine.trigger(SyncTrigger.connectivity)).ok, isTrue);
      expect(jobs.byId(id).state, JobState.done);
      await engine.dispose();
    });
  });

  group('§7 · recuperación de dispositivo', () {
    test(
        'sin backup se recupera lo sincronizado y se reporta la pérdida de PII',
        () async {
      final (:engine, :transport, :store, jobs: _) = _armar(registro);
      final entidad = registro.pushable.first;
      transport.seed(entidad, [
        {'id': 'r-1'}
      ]);

      final reporte = await engine.recover();

      expect(reporte.hadBackup, isFalse);
      expect(reporte.lostPersonalData, isTrue,
          reason: 'el reporte lo dice sin eufemismos; es el argumento con el '
              'que la app insiste en autorizar el backup en el onboarding');
      expect(store.rows[entidad], hasLength(1),
          reason: 'lo que sí había sincronizado vuelve');

      for (final local in fixture.mustBeLocal) {
        expect(store.rows.containsKey(local), isFalse);
      }
      await engine.dispose();
    });
  });
}

/// Una entidad `push` sobre la que probar la máquina de estados.
///
/// Se prefiere una que no sea `critical`: esas disparan un ciclo al stagear, y
/// el test quedaría dependiendo de quién gana la carrera.
String _entidadDePrueba(SpecRegistry registro) {
  final noCritical = registro.pushable.where((e) => !registro.of(e).critical);
  return noCritical.isEmpty ? registro.pushable.first : noCritical.first;
}

({
  SyncEngine engine,
  InMemoryJobStore jobs,
  InMemoryLocalStore store,
  FakeSyncTransport transport,
}) _armar(SpecRegistry registro) {
  final jobs = InMemoryJobStore();
  final store = InMemoryLocalStore();
  final transport = FakeSyncTransport();
  return (
    engine: SyncEngine(
      specs: registro,
      transport: transport,
      jobs: jobs,
      store: store,
    ),
    jobs: jobs,
    store: store,
    transport: transport,
  );
}
