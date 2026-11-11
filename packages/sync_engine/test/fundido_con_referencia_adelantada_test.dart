// I3 (#183): una escritura que se funde en un alta pendiente y trae una
// referencia a una fila cuyo alta se encoló después.
//
// La agenda que se agenda sin señal y se cumple con una visita antes de subir:
// el cumplimiento (`visita_id`, `estado`) se funde en el alta de la agenda
// (§2.2 compactación) y el alta conserva su lugar, delante de la visita. El
// servidor aplica el lote en orden y comprueba cada FK en el momento (`23503`):
// la agenda quedaba INVALID y la cita cumplida no subía nunca. El servidor
// falso no comprueba FK, por eso no lo mostraba nadie.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

SpecRegistry _registro() => SpecRegistry(
  [
    SyncSpec.push('agenda'),
    SyncSpec.push('visita'),
    SyncSpec.push('nota_cita'),
    SyncSpec.push('house_status', pk: 'ubicacion_id'),
    SyncSpec.push('ubicacion'),
  ],
  allEntities: {'agenda', 'visita', 'nota_cita', 'house_status', 'ubicacion'},
);

({SyncEngine motor, FakeSyncTransport transport}) _armar() {
  final transport = FakeSyncTransport(
    pkFieldPorEntidad: const {'house_status': 'ubicacion_id'},
  );
  return (
    motor: SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
    ),
    transport: transport,
  );
}

List<String> _orden(FakeSyncTransport t) => [
  for (final b in t.batches)
    for (final j in b.jobs) '${j.entity}:${j.payload[t.pkFieldPorEntidad[j.entity] ?? 'id']}',
];

void main() {
  test('la agenda cumplida sube detrás de la visita que nombra', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('agenda', Op.insert, {
      'id': 'a-1',
      'espacio_id': 'e-1',
      'estado': 'PROGRAMADA',
      'visita_id': null,
    });
    await motor.stage('visita', Op.insert, {'id': 'v-1', 'espacio_id': 'e-1'});
    await motor.stage('agenda', Op.update, {
      'id': 'a-1',
      'estado': 'CUMPLIDA',
      'visita_id': 'v-1',
    }, syncVersion: 0);
    final resultado = await motor.syncNow();

    expect(_orden(transport), ['visita:v-1', 'agenda:a-1']);
    expect(resultado.invalidated, 0);
    final agenda = transport.rowsOf('agenda').single;
    expect(agenda['estado'], 'CUMPLIDA');
    expect(agenda['visita_id'], 'v-1');
    expect(agenda['espacio_id'], 'e-1', reason: 'el alta no pierde sus columnas');
  });

  test('lo que cuelga de la agenda se va con ella, en su orden', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('agenda', Op.insert, {'id': 'a-1', 'visita_id': null});
    await motor.stage('nota_cita', Op.insert, {'id': 'n-1', 'agenda_id': 'a-1'});
    await motor.stage('visita', Op.insert, {'id': 'v-1'});
    await motor.stage('agenda', Op.update, {
      'id': 'a-1',
      'visita_id': 'v-1',
    }, syncVersion: 0);
    await motor.syncNow();

    expect(_orden(transport), ['visita:v-1', 'agenda:a-1', 'nota_cita:n-1']);
  });

  test('sin referencias hacia adelante conserva su lugar en la cola', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('agenda', Op.insert, {'id': 'a-1', 'estado': 'X'});
    await motor.stage('visita', Op.insert, {'id': 'v-1'});
    await motor.stage('agenda', Op.update, {
      'id': 'a-1',
      'estado': 'CANCELADA',
    }, syncVersion: 0);
    await motor.syncNow();

    expect(_orden(transport), ['agenda:a-1', 'visita:v-1']);
  });

  test('nombrar un alta que ya está atrás de sí no la mueve', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('visita', Op.insert, {'id': 'v-1'});
    await motor.stage('agenda', Op.insert, {'id': 'a-1', 'visita_id': null});
    await motor.stage('agenda', Op.update, {
      'id': 'a-1',
      'visita_id': 'v-1',
    }, syncVersion: 0);
    await motor.syncNow();

    expect(_orden(transport), ['visita:v-1', 'agenda:a-1']);
  });

  test('el color de la casa no cuenta como una fila nombrable', () async {
    // house_status tiene como PK el id de la ubicación: una ubicación que se
    // edita antes de subir no se corre detrás del color de su propia casa.
    final (:motor, :transport) = _armar();

    await motor.stage('ubicacion', Op.insert, {'id': 'u-1', 'calle': 'A'});
    await motor.stage('house_status', Op.insert, {
      'ubicacion_id': 'u-1',
      'color': 'VERDE',
    });
    await motor.stage('ubicacion', Op.update, {
      'id': 'u-1',
      'calle': 'B',
    }, syncVersion: 0);
    await motor.syncNow();

    expect(_orden(transport), ['ubicacion:u-1', 'house_status:u-1']);
    expect(transport.rowsOf('ubicacion').single['calle'], 'B');
  });

  test('un reintento tras un error transitorio no vuelve a reordenar', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('agenda', Op.insert, {'id': 'a-1', 'visita_id': null});
    await motor.stage('visita', Op.insert, {'id': 'v-1'});
    await motor.stage('agenda', Op.update, {
      'id': 'a-1',
      'visita_id': 'v-1',
    }, syncVersion: 0);
    transport.offline();
    expect((await motor.syncNow()).ok, isFalse);
    transport.online();
    await motor.syncNow();

    final ultimo = transport.batches.last.jobs;
    expect([for (final j in ultimo) j.entity], ['visita', 'agenda']);
    expect(transport.rowsOf('agenda').single['visita_id'], 'v-1');
  });
}
