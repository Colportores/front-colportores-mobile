// La venta contra las tablas reales (HU-VEN-001, #423): AppDatabase en memoria, mismo esquema y mismos
// CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late VentaLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<VentaFila>> ventas() => db.select(db.ventas).get();
  Future<List<VentaItemFila>> items() => db.select(db.ventaItems).get();
  Future<List<AuditLogFila>> auditoria() => db.select(db.auditLogLocal).get();
  Future<List<HouseStatusFila>> casas() => db.select(db.houseStatuses).get();

  group('registrar', () {
    test('guarda la venta y sus ítems, los encola (la venta primero) y pinta la casa', () async {
      final r = await local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);

      expect(r.yaEstaba, isFalse);
      final venta = (await ventas()).single;
      expect(
        [venta.numeroTalonario, venta.montoTotal, venta.espacioPersonaId],
        ['T-100', 150000, 'ep-1'],
      );
      expect(venta.fecha, t0);
      final item = (await items()).single;
      expect(
        [item.productoId, item.cantidad, item.precioUnitario, item.subtotal],
        ['prod-1', 3, 50000, 150000],
      );
      expect(cola(), ['venta:insert', 'venta_item:insert', 'house_status:insert']);
      expect((await casas()).single.color, 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test(
      'lo que sube no lleva nada de la persona: ids opacos y, de prosa, solo el motivo',
      () async {
        await local.registrar(ventaDe('v-1', motivo: 'descuento'), [itemDe('i-1', 'v-1')]);

        final venta = encolador.encolados.first.payload;
        expect(
          venta.keys,
          containsAll(['id', 'espacio_persona_id', 'numero_talonario', 'monto_total']),
        );
        expect(venta['monto_total'], 150000);
        expect(venta['motivo_monto_manual'], 'descuento');
        expect(venta['fecha'], '2026-10-23T13:45:10.123Z');
        expect('$venta', isNot(contains('Atiende')));
      },
    );

    test('la venta sube cuántos renglones lleva para que el servidor exija el motivo del total '
        'cambiado en los dos sentidos (#608, «Total arriba»)', () async {
      await local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1'), itemDe('i-2', 'v-1')]);

      final venta = encolador.encolados.first;
      expect(venta.entidad, 'venta');
      expect(venta.payload['items_esperados'], 2);
      expect((await ventas()).single.toJson().containsKey('items_esperados'), isFalse);
    });

    test('un combo guarda lo que traía y sube como arreglo jsonb', () async {
      const componentes = [
        ComponenteVendido(productoId: 'libro-1'),
        ComponenteVendido(productoId: 'revista-1', cantidad: 2),
      ];

      await local.registrar(ventaDe('v-1', monto: 120000), [
        itemDe(
          'i-1',
          'v-1',
          productoId: null,
          coleccionId: 'combo-1',
          componentes: componentes,
          cantidad: 1,
          precio: 120000,
        ),
      ]);

      final item = (await items()).single;
      expect([item.productoId, item.coleccionId], [null, 'combo-1']);
      expect(item.componentes, [
        {'producto_id': 'libro-1', 'cantidad': 1},
        {'producto_id': 'revista-1', 'cantidad': 2},
      ]);
      expect(encolador.encolados[1].payload['componentes'], item.componentes);
      expect(encolador.encolados[1].payload['producto_id'], isNull);
    });

    test(
      'el monto a mano deja la diferencia en el audit_log local, sin el texto del motivo',
      () async {
        await local.registrar(
          ventaDe('v-1', monto: 135000, motivo: 'descuento por pago en efectivo'),
          [itemDe('i-1', 'v-1')],
          diferenciaCentavos: -15000,
        );

        final fila = (await auditoria()).single;
        expect(
          [fila.evento, fila.uuid, fila.motivo],
          ['venta_monto_manual', 'v-1', 'diferencia_centavos:-15000'],
        );
        expect(fila.creadoEn, t0);
      },
    );

    test('sin cambio a mano no hay fila en el audit_log', () async {
      await local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);

      expect(await auditoria(), isEmpty);
    });

    test(
      'la misma venta dos veces (doble toque o reintento) no escribe ni encola de nuevo',
      () async {
        await local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);
        final antes = cola();

        final segunda = await local.registrar(ventaDe('v-1'), [itemDe('i-2', 'v-1')]);

        expect(segunda.yaEstaba, isTrue);
        expect(segunda.venta.id, 'v-1');
        expect(segunda.items.single.id, 'i-1', reason: 'responde con lo que ya estaba');
        expect(cola(), antes);
        expect(await ventas(), hasLength(1));
        expect(await items(), hasLength(1));
      },
    );

    test('dos ventas seguidas en paralelo con el mismo talonario: entra una sola', () async {
      final resultados = await Future.wait([
        local
            .registrar(ventaDe('v-1', talonario: '0042'), [itemDe('i-1', 'v-1')])
            .then<Object>((v) => v, onError: (Object e) => e),
        local
            .registrar(ventaDe('v-2', talonario: '0042'), [itemDe('i-2', 'v-2')])
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);

      expect(resultados.whereType<TalonarioRepetidoException>(), hasLength(1));
      expect(await ventas(), hasLength(1));
    });
  });

  group('talonario único por colportor y año', () {
    setUp(() => local.registrar(ventaDe('v-1', talonario: '0042'), [itemDe('i-1', 'v-1')]));

    test('el mismo número el mismo año se rechaza con el día de la venta que lo usó', () async {
      final mas = ventaDe('v-2', talonario: '0042', fecha: t0.add(const Duration(days: 3)));

      await expectLater(
        local.registrar(mas, [itemDe('i-2', 'v-2')]),
        throwsA(
          isA<TalonarioRepetidoException>()
              .having((e) => e.numero, 'numero', '0042')
              .having((e) => e.ventaDel, 'ventaDel', DateTime(2026, 10, 23)),
        ),
      );
      expect(await ventas(), hasLength(1));
      expect(cola().where((c) => c.startsWith('venta')), ['venta:insert', 'venta_item:insert']);
    });

    test('el mismo número el año siguiente entra', () async {
      final proximoAnio = ventaDe('v-2', talonario: '0042', fecha: DateTime.utc(2027, 2, 1, 12));

      await local.registrar(proximoAnio, [itemDe('i-2', 'v-2')]);

      expect(await ventas(), hasLength(2));
    });

    test(
      'el 31/12 de noche en Uruguay cuenta como el año viejo aunque en UTC sea el nuevo',
      () async {
        // 2027-01-01 02:30 UTC = 31/12/2026 23:30 en Montevideo: mismo año que la venta de octubre.
        final finDeAnio = ventaDe('v-2', talonario: '0042', fecha: DateTime.utc(2027, 1, 1, 2, 30));

        await expectLater(
          local.registrar(finDeAnio, [itemDe('i-2', 'v-2')]),
          throwsA(isA<TalonarioRepetidoException>()),
        );
      },
    );

    test('otro colportor puede usar el mismo número', () async {
      await local.registrar(ventaDe('v-2', talonario: '0042', colportor: 'col-2'), [
        itemDe('i-2', 'v-2'),
      ]);

      expect(await ventas(), hasLength(2));
    });

    test('un número distinto entra; «0042» y «42» son distintos como en el servidor', () async {
      await local.registrar(ventaDe('v-2', talonario: '42'), [itemDe('i-2', 'v-2')]);

      expect(await ventas(), hasLength(2));
    });

    test('«t-100», «T-100 » y «T-100» son el mismo talonario (sin mayúsculas ni espacios de los '
        'bordes, #608 «Talonario =»)', () async {
      await local.registrar(ventaDe('v-t', talonario: 'T-100'), [itemDe('i-t', 'v-t')]);

      for (final variante in ['t-100', 'T-100 ', ' t-100', 'T-100\n']) {
        await expectLater(
          local.registrar(ventaDe('v-x', talonario: variante), [itemDe('i-x', 'v-x')]),
          throwsA(isA<TalonarioRepetidoException>()),
          reason: 'la variante «$variante» es el mismo talonario',
        );
      }
      expect((await ventas()).map((v) => v.id), ['v-1', 'v-t']);
    });

    test('las letras con tilde también se comparan sin mayúsculas ni minúsculas', () async {
      await local.registrar(ventaDe('v-t', talonario: 'Ñ-7'), [itemDe('i-t', 'v-t')]);

      final usado = await local.talonarioUsado(colportorId: 'col-1', numero: 'ñ-7', fecha: t0);

      expect(usado?.ventaId, 'v-t');
    });

    test('«0100» y «100» siguen siendo distintos aunque cambien las mayúsculas', () async {
      await local.registrar(ventaDe('v-t', talonario: '0100'), [itemDe('i-t', 'v-t')]);

      final otro = await local.talonarioUsado(colportorId: 'col-1', numero: '100', fecha: t0);

      expect(otro, isNull);
    });

    test('talonarioUsado avisa con otra escritura del mismo número', () async {
      await local.registrar(ventaDe('v-t', talonario: 'T-100'), [itemDe('i-t', 'v-t')]);

      final usado = await local.talonarioUsado(colportorId: 'col-1', numero: ' t-100 ', fecha: t0);

      expect(usado?.ventaId, 'v-t');
    });

    test('una venta dada de baja libera su número', () async {
      await (db.update(
        db.ventas,
      )..where((v) => v.id.equals('v-1'))).write(VentasCompanion(deletedAt: Value(t0)));

      await local.registrar(ventaDe('v-2', talonario: '0042'), [itemDe('i-2', 'v-2')]);

      expect(await ventas(), hasLength(2));
    });

    test('talonarioUsado avisa mientras escribe, sin guardar nada', () async {
      final usado = await local.talonarioUsado(colportorId: 'col-1', numero: ' 0042 ', fecha: t0);
      final libre = await local.talonarioUsado(colportorId: 'col-1', numero: '0043', fecha: t0);

      expect(usado!.ventaId, 'v-1');
      expect(usado.fecha, t0);
      expect(libre, isNull);
    });
  });

  group('todo o nada', () {
    test(
      'si el encolado falla a mitad, no queda ni la venta ni sus ítems ni la casa pintada',
      () async {
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = 1;

        await expectLater(
          local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]),
          throwsA(isA<StateError>()),
        );

        expect(await ventas(), isEmpty);
        expect(await items(), isEmpty);
        expect(await casas(), isEmpty);
        expect(await auditoria(), isEmpty);
      },
    );

    test(
      'si falla lo previo (la visita de la entrevista), la venta tampoco se guarda (R44)',
      () async {
        await expectLater(
          local.registrar(
            ventaDe('v-1'),
            [itemDe('i-1', 'v-1')],
            antesDeGuardar: () async => throw StateError('no se pudo guardar la visita'),
          ),
          throwsA(isA<StateError>()),
        );

        expect(await ventas(), isEmpty);
        expect(cola(), isEmpty);
      },
    );

    test('lo previo corre dentro de la misma transacción y antes de la venta', () async {
      await local.registrar(
        ventaDe('v-1'),
        [itemDe('i-1', 'v-1')],
        antesDeGuardar: () => encolador.encolar('visita', OperacionSync.insert, {'id': 'vis'}),
      );

      expect(cola().take(2), ['visita:insert', 'venta:insert']);
    });

    test('un ítem que rompe un CHECK del servidor revierte toda la venta', () async {
      final roto = itemDe('i-1', 'v-1', productoId: null, coleccionId: null);

      await expectLater(local.registrar(ventaDe('v-1'), [roto]), throwsA(anything));

      expect(await ventas(), isEmpty);
    });

    test('sin el vínculo persona ↔ espacio no hay venta', () async {
      await expectLater(
        local.registrar(ventaDe('v-1', vinculo: 'ep-fantasma'), [itemDe('i-1', 'v-1')]),
        throwsA(isA<VentaSinPersonaException>()),
      );
      await (db.update(
        db.espacioPersonas,
      )..where((e) => e.id.equals('ep-1'))).write(EspacioPersonasCompanion(deletedAt: Value(t0)));
      await expectLater(
        local.registrar(ventaDe('v-2'), [itemDe('i-1', 'v-2')]),
        throwsA(isA<VentaSinPersonaException>()),
      );
      expect(await ventas(), isEmpty);
    });
  });

  group('house_status', () {
    test(
      'una venta con algo para cobrar deja la casa en «entrega y cobranza pendientes» (1)',
      () async {
        await local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);

        final casa = (await casas()).single;
        expect([casa.color, casa.prioridad], ['ENTREGA_Y_COBRANZA_PENDIENTE', 1]);
      },
    );

    test('una venta de \$ 0 (todo regalado) no pinta la casa por sí sola', () async {
      await local.registrar(ventaDe('v-1', monto: 0), [itemDe('i-1', 'v-1', precio: 0)]);

      expect(await casas(), isEmpty);
    });

    test('si la ubicación del espacio no está en el teléfono la venta se guarda igual', () async {
      await (db.delete(db.ubicaciones)).go();

      await local.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);

      expect(await ventas(), hasLength(1));
      expect(await casas(), isEmpty);
    });

    test('en un edificio la venta pinta la casa del depto, no la de otro', () async {
      final otra = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      addTearDown(otra.close);
      await sembrarEdificio(otra);
      final enOtra = VentaLocalDataSourceDrift(
        otra,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(otra, encolador: encolador),
      );

      await enOtra.registrar(ventaDe('v-1', vinculo: 'ep-2'), [itemDe('i-1', 'v-1')]);

      final casa = (await otra.select(otra.houseStatuses).get()).single;
      expect(casa.ubicacionId, 'ub-1');
      expect(casa.tipoUbicacion, 'EDIFICIO');
    });
  });
}
