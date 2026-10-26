// El servicio de la vista 25 sobre el motor de verdad (con el transporte y las tiendas en memoria):
// lo que la pantalla ve del estado, de «Actualizar ahora» y de lo que el servidor rechazó.
import 'package:colportores_mobile/features/sincronizacion/data/services/servicio_sincronizacion_motor.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

SpecRegistry _registro() => SpecRegistry(
  [SyncSpec.push('venta'), SyncSpec.push('visita'), SyncSpec.pull('producto')],
  allEntities: {'venta', 'visita', 'producto'},
);

typedef _Banco = ({
  SyncEngine motor,
  ServicioSincronizacionMotor servicio,
  FakeSyncTransport transport,
  FakeConnectivityPort red,
});

_Banco _armar() {
  final transport = FakeSyncTransport();
  final red = FakeConnectivityPort();
  final motor = SyncEngine(
    specs: _registro(),
    transport: transport,
    jobs: InMemoryJobStore(),
    store: InMemoryLocalStore(),
    connectivity: red,
  );
  return (
    motor: motor,
    servicio: ServicioSincronizacionMotor(motor),
    transport: transport,
    red: red,
  );
}

Future<void> _stage(SyncEngine motor, String entity, String id) =>
    motor.stage(entity, Op.insert, {'id': id}, clientOpId: 'op-$id');

void main() {
  group('ServicioSincronizacionMotor', () {
    late _Banco b;

    setUp(() => b = _armar());
    tearDown(() async {
      await b.motor.dispose();
      await b.red.dispose();
    });

    group('estado', () {
      test('should count the queued operations as pending and report no dates yet', () async {
        await _stage(b.motor, 'venta', 'v-1');
        await _stage(b.motor, 'visita', 'vi-1');

        final estado = await b.servicio.estado();

        expect(estado.pendientes, 2);
        expect(estado.invalidas, 0);
        expect(estado.ultimoEnvio, isNull);
        expect(estado.ultimaActualizacion, isNull);
        expect(estado.ultimoRespaldo, isNull);
        expect(estado.actualizacionEnEspera, isFalse);
        expect(estado.sesionSinRenovar, isFalse);
      });

      test('should show the last send and the last update after a manual sync', () async {
        await _stage(b.motor, 'venta', 'v-1');

        await b.servicio.actualizarAhora();
        final estado = await b.servicio.estado();

        expect(estado.pendientes, 0);
        expect(estado.ultimoEnvio, isNotNull);
        expect(estado.ultimaActualizacion, isNotNull);
      });

      test('should emit the new state through cambios while someone listens', () async {
        final vistos = <EstadoSincronizacion>[];
        final escucha = b.servicio.cambios.listen(vistos.add);

        await _stage(b.motor, 'venta', 'v-1');
        await b.servicio.actualizarAhora();
        await pumpEventQueue();
        await escucha.cancel();

        expect(vistos, isNotEmpty);
        expect(vistos.last.pendientes, 0);
      });

      test(
        'should flag the update as waiting when the saving mode holds the pull on mobile data',
        () async {
          b.servicio.aplicarModoAhorro(activo: true);
          b.red.goMobile();

          await b.motor.trigger(SyncTrigger.appResumed);
          final estado = await b.servicio.estado();

          expect(estado.actualizacionEnEspera, isTrue);
          expect(estado.ultimaActualizacion, isNull);
        },
      );
    });

    group('actualizarAhora', () {
      test('should send what is pending and bring the changes (HU-SYNC-007)', () async {
        for (var i = 1; i <= 5; i++) {
          await _stage(b.motor, 'venta', 'v-$i');
        }
        b.transport.seed('producto', [
          {'id': 'p-1'},
          {'id': 'p-2'},
        ]);

        final resultado = await b.servicio.actualizarAhora();

        expect(resultado, isA<ActualizacionCompleta>());
        final ok = resultado as ActualizacionCompleta;
        expect(ok.enviadas, 5);
        expect(ok.recibidas, 2);
        expect(ok.rechazadas, 0);
        expect((await b.servicio.estado()).pendientes, 0);
      });

      test('should bring the changes even with the saving mode on and mobile data', () async {
        b.servicio.aplicarModoAhorro(activo: true);
        b.red.goMobile();
        b.transport.seed('producto', [
          {'id': 'p-1'},
        ]);

        final resultado = await b.servicio.actualizarAhora();

        expect((resultado as ActualizacionCompleta).recibidas, 1);
      });

      test('should say the server did not answer and keep what was pending', () async {
        await _stage(b.motor, 'venta', 'v-1');
        b.transport.offline();

        final resultado = await b.servicio.actualizarAhora();

        expect(resultado, const ActualizacionFallida(MotivoFallaActualizacion.servidor));
        expect((await b.servicio.estado()).pendientes, 1);
      });

      test('should say the session cannot be renewed on a 401', () async {
        await _stage(b.motor, 'venta', 'v-1');
        b.transport.failWith(401);

        final resultado = await b.servicio.actualizarAhora();

        expect(resultado, const ActualizacionFallida(MotivoFallaActualizacion.sesion));
        final estado = await b.servicio.estado();
        expect(estado.pendientes, 1);
        expect(estado.sesionSinRenovar, isTrue);
      });

      test('should count the operations the server rejected and keep the rest sent', () async {
        await _stage(b.motor, 'venta', 'v-1');
        await _stage(b.motor, 'visita', 'vi-1');
        b.transport.rejectJob('op-v-1', '23514', 'precio inexistente');

        final resultado = await b.servicio.actualizarAhora();

        final ok = resultado as ActualizacionCompleta;
        expect(ok.enviadas, 1);
        expect(ok.rechazadas, 1);
        final estado = await b.servicio.estado();
        expect(estado.invalidas, 1);
        expect(estado.pendientes, 0);
      });
    });

    group('operaciones fallidas', () {
      test('should list table, type, date and code without the row', () async {
        await b.motor.stage('venta', Op.update, {
          'id': 'v-1',
          'cliente': 'Juan Pérez',
        }, clientOpId: 'op-1');
        b.transport.rejectJob('op-1', '23514', 'Key (email)=(juan@correo.com) already exists');
        await b.servicio.actualizarAhora();

        final fallidas = await b.servicio.operacionesFallidas();

        expect(fallidas, hasLength(1));
        final f = fallidas.single;
        expect(f.tabla, 'venta');
        expect(f.tipo, TipoOperacion.cambio);
        expect(f.codigo, '23514');
        expect(f.error, isNot(contains('juan@correo.com')));
        expect([f.id, f.tabla, f.codigo, f.error].join(' '), isNot(contains('Juan Pérez')));
      });

      test('should map each operation to its type', () async {
        await b.motor.stage('venta', Op.insert, {'id': 'a'}, clientOpId: 'op-a');
        await b.motor.stage('visita', Op.delete, {'id': 'b'}, clientOpId: 'op-b');
        b.transport
          ..rejectJob('op-a', 'X')
          ..rejectJob('op-b', 'X');
        await b.servicio.actualizarAhora();

        final tipos = {for (final f in await b.servicio.operacionesFallidas()) f.tabla: f.tipo};

        expect(tipos, {'venta': TipoOperacion.alta, 'visita': TipoOperacion.baja});
      });

      test('should requeue every rejected operation and send them again', () async {
        await _stage(b.motor, 'venta', 'v-1');
        await _stage(b.motor, 'venta', 'v-2');
        b.transport
          ..rejectJob('op-v-1', 'X')
          ..rejectJob('op-v-2', 'X');
        await b.servicio.actualizarAhora();
        expect((await b.servicio.estado()).invalidas, 2);
        b.transport.clearRejections();

        final reencoladas = await b.servicio.reintentarFallidas();
        final resultado = await b.servicio.actualizarAhora();

        expect(reencoladas, 2);
        expect((resultado as ActualizacionCompleta).enviadas, 2);
        expect((await b.servicio.estado()).invalidas, 0);
      });

      test('should requeue only the chosen one', () async {
        await _stage(b.motor, 'venta', 'v-1');
        await _stage(b.motor, 'venta', 'v-2');
        b.transport
          ..rejectJob('op-v-1', 'X')
          ..rejectJob('op-v-2', 'X');
        await b.servicio.actualizarAhora();
        final primera = (await b.servicio.operacionesFallidas()).first;
        b.transport.clearRejections();

        final reencoladas = await b.servicio.reintentarFallidas(id: primera.id);
        final estado = await b.servicio.estado();

        expect(reencoladas, 1);
        expect(estado.invalidas, 1);
        expect(estado.pendientes, 1);
      });

      test('should send it again and keep it listed if the server rejects it again', () async {
        await _stage(b.motor, 'venta', 'v-1');
        b.transport.rejectJob('op-v-1', '23514', 'sin precio');
        await b.servicio.actualizarAhora();

        await b.servicio.reintentarFallidas();
        final resultado = await b.servicio.actualizarAhora();

        expect((resultado as ActualizacionCompleta).rechazadas, 1);
        expect(await b.servicio.operacionesFallidas(), hasLength(1));
      });
    });
  });

  group('ServicioSincronizacionSinMotor', () {
    test('should fail the state read so the screen offers to retry', () async {
      const servicio = ServicioSincronizacionSinMotor();

      await expectLater(servicio.estado(), throwsStateError);
      expect(
        await servicio.actualizarAhora(),
        const ActualizacionFallida(MotivoFallaActualizacion.servidor),
      );
      expect(await servicio.operacionesFallidas(), isEmpty);
    });
  });
}
