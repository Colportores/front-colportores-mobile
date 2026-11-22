// Qué hace el motor cuando la sesión deja de andar (B1, H2).
//
// El `401` es transitorio y eso no se discute: los jobs quedan en PENDING y no
// se pierde una venta. Lo que B1 anotó como riesgo al decidirlo es lo otro —
// "con un refresh roto, los jobs reintentan para siempre en vez de avisar"— y
// es lo que se fija acá.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

({SyncEngine motor, FakeSyncTransport transport, InMemoryJobStore jobs})
    _armar() {
  final transport = FakeSyncTransport();
  final jobs = InMemoryJobStore();
  return (
    motor: SyncEngine(
      specs: SpecRegistry([
        SyncSpec.push('venta'),
      ], allEntities: {'venta'}),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
    ),
    transport: transport,
    jobs: jobs,
  );
}

Future<void> _encolar(SyncEngine m, String id) =>
    m.stage('venta', Op.insert, {'id': id}, clientOpId: 'op-$id');

void main() {
  test('un 401 no invalida la venta: la sesión es nuestra, el dato es del '
      'colportor', () async {
    final (:motor, :transport, :jobs) = _armar();

    await _encolar(motor, 'v-1');
    transport.failWith(401);
    final r = await motor.syncNow();

    expect(r.failure!.kind, FailureKind.transient);

    final estado = await jobs.status();
    expect(estado.invalid, 0,
        reason: 'mandar a la cola de error una venta buena porque el token '
            'venció la esconde detrás de un "reintentar" que el colportor '
            'no tiene por qué entender');
    expect(estado.pending, 1);

    await motor.dispose();
  });

  test('pero deja de ser silencioso: el estado dice desde cuándo', () async {
    final (:motor, :transport, jobs: _) = _armar();
    final vistos = <SyncStatus>[];
    final sub = motor.status.listen(vistos.add);

    await _encolar(motor, 'v-1');
    transport.failWith(401);
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(vistos.last.unauthorizedSince, isNotNull,
        reason: 'sin esto la pantalla dice "sincronizando" toda la jornada y '
            'la cola no baja nunca');

    await sub.cancel();
    await motor.dispose();
  });

  test('interesa desde cuándo, no la última vez', () async {
    final (:motor, :transport, jobs: _) = _armar();
    final vistos = <SyncStatus>[];
    final sub = motor.status.listen(vistos.add);

    await _encolar(motor, 'v-1');
    transport.failWith(401);
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);
    final primera = vistos.last.unauthorizedSince;

    transport.failWith(401);
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(vistos.last.unauthorizedSince, primera,
        reason: 'es el dato con el que la app decide si ya vale la pena '
            'molestar al colportor');

    await sub.cancel();
    await motor.dispose();
  });

  test('un ciclo que funciona lo limpia', () async {
    final (:motor, :transport, jobs: _) = _armar();
    final vistos = <SyncStatus>[];
    final sub = motor.status.listen(vistos.add);

    await _encolar(motor, 'v-1');
    transport.failWith(401);
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(vistos.last.unauthorizedSince, isNotNull);

    // El refresh anduvo y el token nuevo sirve.
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(vistos.last.unauthorizedSince, isNull);
    expect(transport.rowsOf('venta'), hasLength(1));

    await sub.cancel();
    await motor.dispose();
  });

  test('quedarse sin red no lo limpia: no saber no es saber que anda',
      () async {
    final (:motor, :transport, jobs: _) = _armar();
    final vistos = <SyncStatus>[];
    final sub = motor.status.listen(vistos.add);

    await _encolar(motor, 'v-1');
    transport.failWith(401);
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);
    final desde = vistos.last.unauthorizedSince;
    expect(desde, isNotNull);

    transport.offline();
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(vistos.last.unauthorizedSince, desde,
        reason: 'si la falta de red lo limpiara, el aviso aparecería y '
            'desaparecería cada vez que el colportor entra y sale de '
            'cobertura');

    await sub.cancel();
    await motor.dispose();
  });

  test('otra falla del servidor no lo enciende: no toda falla es de sesión',
      () async {
    final (:motor, :transport, jobs: _) = _armar();
    final vistos = <SyncStatus>[];
    final sub = motor.status.listen(vistos.add);

    await _encolar(motor, 'v-1');
    transport.failWith(500);
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(vistos.last.unauthorizedSince, isNull);

    await sub.cancel();
    await motor.dispose();
  });
}
