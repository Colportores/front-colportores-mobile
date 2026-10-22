// Suite de conformidad (§8) — las tres primeras garantías.
//
//   · persona y nota están registradas como local — el test falla si alguien
//     cambia la política.
//   · engine.stage() sobre una entidad local lanza LocalOnlyViolationError.
//   · ninguna entidad de la DB queda sin SyncSpec.
//
// Reemplaza al test artesanal "falla si persona entra en sync_queue": ahora lo
// garantiza el motor y esto lo verifica.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Las entidades de la DB local en V1. Es la lista que hay que actualizar
/// cuando aparece una tabla nueva — y si alguien se olvida, el registro no
/// arranca.
const kEntidadesV1 = {
  // pull
  'producto', 'coleccion', 'precio_por_zona', 'campania', 'zona', 'ciudad',
  'pais',
  // push
  'venta', 'venta_item', 'entrega', 'cobranza', 'visita', 'agenda', 'jornada',
  // push + alsoPull
  'ubicacion', 'espacio', 'house_status',
  // local
  'persona', 'nota',
};

/// La declaración de §3, tal cual la va a escribir la app.
List<SyncSpec> specsV1() => [
      SyncSpec.pull('producto', realtime: true),
      SyncSpec.pull('coleccion'),
      SyncSpec.pull('precio_por_zona', realtime: true),
      SyncSpec.pull('campania'),
      SyncSpec.pull('zona'),
      SyncSpec.pull('ciudad'),
      SyncSpec.pull('pais'),
      SyncSpec.push('venta', critical: true),
      SyncSpec.push('venta_item', critical: true),
      SyncSpec.push('entrega'),
      SyncSpec.push('cobranza', critical: true),
      SyncSpec.push('visita'),
      SyncSpec.push('agenda'),
      SyncSpec.push('jornada', critical: true),
      SyncSpec.push('ubicacion', alsoPull: true),
      SyncSpec.push('espacio', alsoPull: true),
      SyncSpec.push('house_status', alsoPull: true),
      SyncSpec.local('persona'),
      SyncSpec.local('nota'),
    ];

SyncEngine _motor(SpecRegistry specs, {InMemoryJobStore? jobs}) => SyncEngine(
      specs: specs,
      transport: FakeSyncTransport(),
      jobs: jobs ?? InMemoryJobStore(),
      store: InMemoryLocalStore(),
    );

void main() {
  final registro = SpecRegistry(specsV1(), allEntities: kEntidadesV1);

  group('§8 · datos personales', () {
    test('persona y nota están declaradas local', () {
      expect(registro.policyOf('persona'), SyncPolicy.local);
      expect(registro.policyOf('nota'), SyncPolicy.local);
    });

    test('ninguna entidad local aparece entre las que suben o bajan', () {
      expect(registro.pushable, isNot(contains('persona')));
      expect(registro.pushable, isNot(contains('nota')));
      expect(registro.pullable, isNot(contains('persona')));
      expect(registro.pullable, isNot(contains('nota')));
    });

    test('stage() sobre una entidad local lanza LocalOnlyViolationError',
        () async {
      final jobs = InMemoryJobStore();
      final motor = _motor(registro, jobs: jobs);

      await expectLater(
        motor.stage('persona', Op.insert, {'id': 'p1', 'nombre': 'Ana'},
            clientOpId: 'op-1'),
        throwsA(isA<LocalOnlyViolationError>()),
      );

      expect(jobs.all, isEmpty,
          reason: 'ni siquiera llega a entrar en sync_queue');
      await motor.dispose();
    });

    test('stage() sobre una réplica de solo lectura también frena', () async {
      final motor = _motor(registro);
      await expectLater(
        motor.stage('producto', Op.update, {'id': 'p1'}, clientOpId: 'op-1'),
        throwsA(isA<ReadOnlyEntityError>()),
      );
      await motor.dispose();
    });
  });

  group('§2 · toda entidad tiene exactamente una política', () {
    test('una tabla sin SyncSpec revienta al arrancar, no en producción', () {
      expect(
        () => SpecRegistry(specsV1(),
            allEntities: {...kEntidadesV1, 'finanza_personal'}),
        throwsA(isA<UnregisteredEntityError>()
            .having((e) => e.entities, 'entities', ['finanza_personal'])),
      );
    });

    test('declarar la misma entidad dos veces revienta', () {
      expect(
        () => SpecRegistry(
          [...specsV1(), SyncSpec.push('persona')],
          allEntities: kEntidadesV1,
        ),
        throwsA(isA<DuplicateSpecError>()),
      );
    });

    test('preguntar por una entidad no declarada revienta', () {
      expect(() => registro.of('inventada'),
          throwsA(isA<UnregisteredEntityError>()));
    });
  });

  group('§2 · opciones por política', () {
    test('las push con alsoPull también bajan delta', () {
      expect(registro.pullable,
          containsAll(['ubicacion', 'espacio', 'house_status']));
      expect(registro.pushable,
          containsAll(['ubicacion', 'espacio', 'house_status']));
    });

    test('realtime está solo donde lo pide el contrato', () {
      expect(
          registro.realtime, unorderedEquals(['producto', 'precio_por_zona']));
    });

    test('venta, cobranza y jornada son critical', () {
      for (final e in ['venta', 'cobranza', 'jornada']) {
        expect(registro.of(e).critical, isTrue, reason: e);
      }
      expect(registro.of('visita').critical, isFalse);
    });
  });
}
