// Las transferencias de materiales contra las tablas reales (HU-STK-005, #512): AppDatabase en memoria,
// mismo esquema y mismos CHECK que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/transferencias/data/datasources/transferencia_local_data_source_drift.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

final _t0 = DateTime.utc(2026, 10, 23, 17, 35);

Transferencia _nueva({
  String id = 't-1',
  List<LineaDeTransferencia>? lineas,
  String origen = 'ana',
  String destino = 'juan',
}) => Transferencia(
  id: id,
  origenId: origen,
  destinoId: destino,
  estado: EstadoDeTransferencia.porAutorizar,
  lineas:
      lineas ??
      [
        LineaDeTransferencia(id: 'l-$id-1', productoId: 'p-1', cantidad: 2),
        LineaDeTransferencia(id: 'l-$id-2', productoId: 'p-2', cantidad: 5),
      ],
  auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: destino),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late TransferenciaLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = TransferenciaLocalDataSourceDrift(db, encolador: encolador);
  });
  tearDown(() => db.close());

  /// Lo que el servidor devuelve por el pull al aceptar la transferencia: su hora, quién la pidió y su
  /// número (lo escribe el `DriftLocalStore`; acá se simula con el UPDATE equivalente).
  Future<void> bajaDelServidor(
    String id, {
    String estado = 'PENDIENTE_AUTORIZACION',
    String? solicitante = 'juan',
    String? motivo,
    int version = 2,
  }) => (db.update(db.transferenciasStock)..where((t) => t.id.equals(id))).write(
    TransferenciasStockCompanion(
      estado: Value(estado),
      solicitanteId: Value(solicitante),
      fechaSolicitud: Value(_t0.add(const Duration(seconds: 4))),
      numero: const Value(18),
      motivoRechazo: Value(motivo),
      syncVersion: Value(version),
    ),
  );

  group('pedir', () {
    test('guarda el encabezado por autorizar y sus líneas', () async {
      final r = await local.pedir(_nueva());

      expect(r.yaEstaba, isFalse);
      final fila = await (db.select(db.transferenciasStock)).getSingle();
      expect(fila.estado, 'PENDIENTE_AUTORIZACION');
      expect(fila.origenId, 'ana');
      expect(fila.destinoId, 'juan');
      expect(fila.fechaSolicitud, isNull);
      final lineas = await (db.select(db.transferenciaItems)).get();
      expect({for (final l in lineas) l.productoId: l.cantidad}, {'p-1': 2, 'p-2': 5});
      expect(lineas.every((l) => l.transferenciaId == 't-1'), isTrue);
    });

    test(
      'encola el encabezado ANTES que sus líneas, con los nombres de columna del cloud',
      () async {
        await local.pedir(_nueva());

        expect(
          [for (final c in encolador.encolados) (c.entidad, c.operacion)],
          [
            ('transferencia_stock', OperacionSync.insert),
            ('transferencia_item', OperacionSync.insert),
            ('transferencia_item', OperacionSync.insert),
          ],
        );
        final encabezado = encolador.encolados.first.payload;
        expect(encabezado.keys.toSet(), {
          'id',
          'origen_id',
          'destino_id',
          'estado',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
        expect(encabezado['estado'], 'PENDIENTE_AUTORIZACION');
        final linea = encolador.encolados[1].payload;
        expect(linea.keys.toSet(), {
          'id',
          'transferencia_id',
          'producto_id',
          'cantidad',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
        expect(linea['transferencia_id'], 't-1');
      },
    );

    test(
      'no sube nada que el servidor fija: ni solicitante, ni número, ni motivo, ni precio',
      () async {
        await local.pedir(_nueva());

        for (final c in encolador.encolados) {
          expect(
            c.payload.keys,
            isNot(
              anyOf(
                contains('solicitante_id'),
                contains('numero'),
                contains('fecha_solicitud'),
                contains('motivo_rechazo'),
                contains('precio_unitario'),
                contains('baja_a_1'),
              ),
            ),
          );
        }
      },
    );

    test('el mismo id es idempotente: no escribe ni encola de nuevo', () async {
      await local.pedir(_nueva());
      encolador.encolados.clear();

      final r = await local.pedir(_nueva());

      expect(r.yaEstaba, isTrue);
      expect(r.transferencia.lineas, hasLength(2));
      expect(encolador.encolados, isEmpty);
      expect(await db.select(db.transferenciasStock).get(), hasLength(1));
      expect(await db.select(db.transferenciaItems).get(), hasLength(2));
    });

    test(
      'todo o nada: si el motor falla al encolar una línea, no queda ni el encabezado',
      () async {
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = 2;

        await expectLater(local.pedir(_nueva()), throwsStateError);

        expect(await db.select(db.transferenciasStock).get(), isEmpty);
        expect(await db.select(db.transferenciaItems).get(), isEmpty);
      },
    );

    test('con las mismas puntas el CHECK de la base lo frena', () async {
      await expectLater(local.pedir(_nueva(origen: 'juan', destino: 'juan')), throwsA(anything));
      expect(await db.select(db.transferenciasStock).get(), isEmpty);
    });

    test('una cantidad cero no entra (CHECK local, el mismo del servidor)', () async {
      await expectLater(
        local.pedir(
          _nueva(
            lineas: const [LineaDeTransferencia(id: 'l-1', productoId: 'p-1', cantidad: 0)],
          ),
        ),
        throwsA(anything),
      );
      expect(await db.select(db.transferenciasStock).get(), isEmpty);
    });
  });

  group('cancelar', () {
    final despues = _t0.add(const Duration(minutes: 5));

    test('pasa a cancelada y encola un update con la versión que tiene', () async {
      await local.pedir(_nueva());
      await bajaDelServidor('t-1', version: 3);
      encolador.encolados.clear();

      final cancelada = await local.cancelar(id: 't-1', colportorId: 'juan', ahora: despues);

      expect(cancelada.estado, EstadoDeTransferencia.cancelada);
      final fila = await db.select(db.transferenciasStock).getSingle();
      expect(fila.estado, 'CANCELADO');
      expect(fila.updatedAt, despues);
      expect(fila.syncVersion, 3);
      final cambio = encolador.encolados.single;
      expect((cambio.entidad, cambio.operacion), ('transferencia_stock', OperacionSync.update));
      expect(cambio.payload['estado'], 'CANCELADO');
      expect(cambio.payload['sync_version'], 3);
      expect(cambio.payload['id'], 't-1');
    });

    test(
      'la que todavía no subió también se cancela (el motor funde la cancelación en el alta)',
      () async {
        await local.pedir(_nueva());
        encolador.encolados.clear();

        final cancelada = await local.cancelar(id: 't-1', colportorId: 'juan', ahora: despues);

        expect(cancelada.estado, EstadoDeTransferencia.cancelada);
        expect(encolador.encolados, hasLength(1));
      },
    );

    test('un segundo toque responde lo mismo sin encolar otro cambio', () async {
      await local.pedir(_nueva());
      await local.cancelar(id: 't-1', colportorId: 'juan', ahora: despues);
      encolador.encolados.clear();

      final otra = await local.cancelar(id: 't-1', colportorId: 'juan', ahora: despues);

      expect(otra.estado, EstadoDeTransferencia.cancelada);
      expect(encolador.encolados, isEmpty);
    });

    test('quien entrega no la cancela', () async {
      await local.pedir(_nueva());
      await bajaDelServidor('t-1');

      await expectLater(
        local.cancelar(id: 't-1', colportorId: 'ana', ahora: despues),
        throwsA(isA<TransferenciaNoCancelableException>()),
      );
      expect(
        (await db.select(db.transferenciasStock).getSingle()).estado,
        'PENDIENTE_AUTORIZACION',
      );
    });

    for (final estado in ['AUTORIZADO', 'EJECUTADO', 'RECHAZADO']) {
      test('$estado: ya no se cancela y no se encola nada', () async {
        await local.pedir(_nueva());
        await bajaDelServidor('t-1', estado: estado, motivo: estado == 'RECHAZADO' ? 'no' : null);
        encolador.encolados.clear();

        await expectLater(
          local.cancelar(id: 't-1', colportorId: 'juan', ahora: despues),
          throwsA(isA<TransferenciaNoCancelableException>()),
        );
        expect(encolador.encolados, isEmpty);
        expect((await db.select(db.transferenciasStock).getSingle()).estado, estado);
      });
    }

    test('una que no existe', () async {
      await expectLater(
        local.cancelar(id: 'nada', colportorId: 'juan', ahora: despues),
        throwsA(isA<TransferenciaNoCancelableException>()),
      );
    });

    test('la que armó la coordinadora no se cancela desde el teléfono', () async {
      await db
          .into(db.transferenciasStock)
          .insert(
            TransferenciasStockCompanion.insert(
              id: 't-c',
              origenId: 'ana',
              destinoId: 'juan',
              createdAt: _t0,
              updatedAt: _t0,
              createdBy: const Value('marta'),
            ),
          );

      await expectLater(
        local.cancelar(id: 't-c', colportorId: 'juan', ahora: despues),
        throwsA(isA<TransferenciaNoCancelableException>()),
      );
    });

    test('todo o nada: si el motor falla, la transferencia sigue por autorizar', () async {
      await local.pedir(_nueva());
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(
        local.cancelar(id: 't-1', colportorId: 'juan', ahora: despues),
        throwsStateError,
      );

      expect(
        (await db.select(db.transferenciasStock).getSingle()).estado,
        'PENDIENTE_AUTORIZACION',
      );
    });
  });

  group('observar', () {
    test('ve las de las dos puntas, con sus líneas, y no las de otros', () async {
      await local.pedir(_nueva());
      await local.pedir(_nueva(id: 't-2', origen: 'juan', destino: 'bruno'));
      await local.pedir(_nueva(id: 't-3', origen: 'ana', destino: 'bruno'));

      final vistas = await local.observar('juan').first;

      expect({for (final t in vistas) t.id}, {'t-1', 't-2'});
      final t1 = vistas.singleWhere((t) => t.id == 't-1');
      expect(t1.lineas, hasLength(2));
      expect(t1.laPidio('juan'), isTrue);
    });

    test('la más nueva primero', () async {
      await local.pedir(_nueva());
      final otra = _nueva(id: 't-2');
      await local.pedir(
        Transferencia(
          id: otra.id,
          origenId: otra.origenId,
          destinoId: otra.destinoId,
          estado: otra.estado,
          lineas: otra.lineas,
          auditoria: Auditoria(
            createdAt: _t0.add(const Duration(hours: 1)),
            updatedAt: _t0.add(const Duration(hours: 1)),
            createdBy: 'juan',
          ),
        ),
      );

      final vistas = await local.observar('juan').first;

      expect([for (final t in vistas) t.id], ['t-2', 't-1']);
    });

    test('una dada de baja no se ve', () async {
      await local.pedir(_nueva());
      await (db.update(db.transferenciasStock)..where((t) => t.id.equals('t-1'))).write(
        TransferenciasStockCompanion(deletedAt: Value(_t0)),
      );

      expect(await local.observar('juan').first, isEmpty);
    });

    test(
      'el estado, el motivo y la hora que baja del servidor se ven; «En cola» desaparece',
      () async {
        await local.pedir(_nueva());
        expect((await local.observar('juan').first).single.enCola, isTrue);

        await bajaDelServidor('t-1', estado: 'RECHAZADO', motivo: 'Ana los necesita esta semana');

        final t = (await local.observar('juan').first).single;
        expect(t.enCola, isFalse);
        expect(t.estado, EstadoDeTransferencia.rechazada);
        expect(t.motivoRechazo, 'Ana los necesita esta semana');
        expect(t.numero, 18);
        expect(t.solicitanteId, 'juan');
      },
    );

    test('quien mira se entera cuando cambia el encabezado o una línea', () async {
      await local.pedir(_nueva());
      final vistas = <List<Transferencia>>[];
      final suscripcion = local.observar('juan').listen(vistas.add);
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();
      expect(vistas.last.single.estado, EstadoDeTransferencia.porAutorizar);

      await bajaDelServidor('t-1', estado: 'AUTORIZADO');
      await pumpEventQueue();
      expect(vistas.last.single.estado, EstadoDeTransferencia.autorizada);

      await db
          .into(db.transferenciaItems)
          .insert(
            TransferenciaItemsCompanion.insert(
              id: 'l-3',
              transferenciaId: 't-1',
              productoId: 'p-3',
              cantidad: 1,
              createdAt: _t0,
              updatedAt: _t0,
            ),
          );
      await pumpEventQueue();
      expect(vistas.last.single.lineas, hasLength(3));
    });

    test('un código de estado que esta versión no conoce no la hace desaparecer', () async {
      await local.pedir(_nueva());
      await db.customStatement('PRAGMA ignore_check_constraints = 1');
      await db.customStatement("UPDATE transferencia_stock SET estado = 'FUTURO'");

      final t = (await local.observar('juan').first).single;

      expect(t.estado, EstadoDeTransferencia.porAutorizar);
    });

    test('con muchas líneas y muchas transferencias las lee todas', () async {
      for (var i = 0; i < 40; i++) {
        await local.pedir(
          _nueva(
            id: 't-$i',
            lineas: [
              for (var j = 0; j < 5; j++)
                LineaDeTransferencia(id: 'l-$i-$j', productoId: 'p-$j', cantidad: j + 1),
            ],
          ),
        );
      }

      final vistas = await local.observar('juan').first;

      expect(vistas, hasLength(40));
      expect(vistas.every((t) => t.lineas.length == 5), isTrue);
    });
  });
}
