// «Venta crece» contra las tablas reales (HU-VEN-001, #693): AppDatabase en memoria, mismo esquema que
// en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/venta_que_crece_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
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
  late EntregaLocalDataSourceDrift entregas;
  final t1 = t0.add(const Duration(days: 3));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    entregas = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  /// La venta 0039 de `ep-1`: 3 libros a $ 500 ($ 1.500), sin cobrar ni entregar.
  Future<void> venta39({String id = 'v-39', DateTime? fecha, String? motivo, int? monto}) async {
    await local.registrar(
      ventaDe(
        id,
        talonario: '00${id.substring(2)}',
        fecha: fecha,
        motivo: motivo,
        monto: monto ?? 150000,
      ),
      [itemDe('i-$id', id)],
    );
    encolador.encolados.clear();
  }

  Future<void> cobrar(String ventaId, int monto, {String id = 'c-1'}) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: ventaId,
          monto: monto,
          medio: 'EFECTIVO',
          fecha: t0,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> entregarTodo(String ventaId, {String id = 'e-1', DateTime? cuando}) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: 'prod-1',
          cantidad: 3,
          pendiente: const Value(false),
          fechaEntrega: Value(cuando ?? t0),
          createdAt: cuando ?? t0,
          updatedAt: cuando ?? t0,
        ),
      );

  VentaItem nuevo(String id, String ventaId, {int precio = 40000, int cantidad = 1}) => VentaItem(
    id: id,
    ventaId: ventaId,
    productoId: 'prod-2',
    cantidad: cantidad,
    precioUnitarioCentavos: precio,
    subtotalCentavos: cantidad * precio,
    auditoria: Auditoria(createdAt: t1, updatedAt: t1, createdBy: 'col-1'),
  );

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  group('ventas abiertas de la persona', () {
    test('con saldo o con algo por entregar está abierta; pagada y entregada, no', () async {
      await venta39();
      await venta39(id: 'v-40', fecha: t0.add(const Duration(days: 1)));
      await cobrar('v-40', 150000);
      await entregarTodo('v-40');

      final abiertas = await local.abiertasDe('per-1');

      expect([for (final v in abiertas) v.ventaId], ['v-39']);
      expect(abiertas.single.saldoCentavos, 150000);
      expect(abiertas.single.entregada, isFalse);
      expect(abiertas.single.renglones.single.cantidad, 3);
    });

    test('pagada y sin entregar sigue abierta (entrega pendiente)', () async {
      await venta39();
      await cobrar('v-39', 150000);

      final abierta = (await local.abiertasDe('per-1')).single;
      expect([abierta.tieneSaldo, abierta.entregada], [false, false]);
    });

    test('entregada con saldo sigue abierta y dice cuándo se entregó', () async {
      await venta39();
      await entregarTodo('v-39', cuando: t0);

      final abierta = (await local.abiertasDe('per-1')).single;
      expect([abierta.tieneSaldo, abierta.entregada, abierta.entregadaEl], [true, true, t0]);
    });

    test('una venta anulada (dada de baja) no está abierta', () async {
      await venta39();
      await (db.update(
        db.ventas,
      )..where((v) => v.id.equals('v-39'))).write(VentasCompanion(deletedAt: Value(t1)));

      expect(await local.abiertasDe('per-1'), isEmpty);
    });

    test('de la más reciente a la más vieja, y nunca la de otra persona de la casa', () async {
      await sembrarVinculo(db, id: 'ep-9', personaId: 'per-9');
      await venta39();
      await venta39(id: 'v-41', fecha: t0.add(const Duration(days: 2)));
      await local.registrar(ventaDe('v-50', talonario: '0050', vinculo: 'ep-9'), [
        itemDe('i-50', 'v-50'),
      ]);

      final abiertas = await local.abiertasDe('per-1');
      expect([for (final v in abiertas) v.ventaId], ['v-41', 'v-39']);
    });

    test('se vuelve a leer sola cuando la venta se paga y entrega', () async {
      await venta39();
      final lecturas = <List<String>>[];
      final sub = local
          .observarAbiertasDe('per-1')
          .listen((l) => lecturas.add([for (final v in l) v.ventaId]));
      await pumpEventQueue();
      await cobrar('v-39', 150000);
      await entregarTodo('v-39');
      await pumpEventQueue();
      await sub.cancel();

      expect(lecturas.first, ['v-39']);
      expect(lecturas.last, isEmpty);
    });
  });

  group('sumar', () {
    test('la venta sube primero con el total y los renglones esperados nuevos, después el renglón '
        'nuevo; lo de antes no se toca', () async {
      await venta39();

      final r = await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);

      expect(r.yaEstaba, isFalse);
      expect(
        [r.totalAnteriorCentavos, r.venta.montoTotalCentavos, r.sumadoCentavos],
        [150000, 190000, 40000],
      );
      expect(r.venta.numeroTalonario, '0039');
      // La casa sigue del mismo color (entrega y cobranza pendientes): no se vuelve a encolar.
      expect(cola(), ['venta:update', 'venta_item:insert']);
      expect(encolador.encolados.first.payload['items_esperados'], 2);
      expect(encolador.encolados.first.payload['monto_total'], 190000);
      final items = await (db.select(db.ventaItems)..where((i) => i.ventaId.equals('v-39'))).get();
      expect(items.map((i) => i.id), containsAll(['i-v-39', 'n-1']));
      final viejo = items.firstWhere((i) => i.id == 'i-v-39');
      expect([viejo.cantidad, viejo.subtotal], [3, 150000]);
    });

    test('el total y el saldo suben; lo pagado no cambia', () async {
      await venta39();
      await cobrar('v-39', 100000);

      await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);

      final abierta = (await local.abiertasDe('per-1')).single;
      expect(
        [abierta.montoTotalCentavos, abierta.pagadoCentavos, abierta.saldoCentavos],
        [190000, 100000, 90000],
      );
    });

    test('un doble toque o un reintento con los mismos renglones no suma dos veces', () async {
      await venta39();
      await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);
      encolador.encolados.clear();

      final otra = await local.sumar(
        'v-39',
        [nuevo('n-1', 'v-39')],
        sumadoCentavos: 40000,
        ahora: t1,
      );

      expect(otra.yaEstaba, isTrue);
      expect(otra.venta.montoTotalCentavos, 190000);
      expect(encolador.encolados, isEmpty);
      expect((await db.select(db.ventas).getSingle()).montoTotal, 190000);
    });

    test('una venta pagada y entregada está cerrada y no crece («Venta cerrada»)', () async {
      await venta39();
      await cobrar('v-39', 150000);
      await entregarTodo('v-39');

      await expectLater(
        local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1),
        throwsA(isA<VentaCerradaException>()),
      );
      expect((await db.select(db.ventas).getSingle()).montoTotal, 150000);
      expect(await (db.select(db.ventaItems)..where((i) => i.id.equals('n-1'))).get(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('el repositorio dice «Venta cerrada» con el número del talonario', () async {
      await venta39();
      await cobrar('v-39', 150000);
      await entregarTodo('v-39');
      final repo = VentaQueCreceRepositoryImpl(local, logger: loggerMudo());

      final r = await repo.sumar(
        'v-39',
        [nuevo('n-1', 'v-39')],
        numeroTalonario: '0039',
        sumadoCentavos: 40000,
        ahora: t1,
      );

      expect(r.fold((f) => f, (_) => null), const FailureVentaCerrada(numeroTalonario: '0039'));
    });

    test(
      'con el monto de lo sumado cambiado guarda el motivo y anota la diferencia, sin el texto',
      () async {
        await venta39();

        await local.sumar(
          'v-39',
          [nuevo('n-1', 'v-39')],
          sumadoCentavos: 30000,
          ahora: t1,
          motivoMontoManual: 'descuento del libro nuevo',
          diferenciaCentavos: -10000,
        );

        final venta = await db.select(db.ventas).getSingle();
        expect([venta.montoTotal, venta.motivoMontoManual], [180000, 'descuento del libro nuevo']);
        final fila = (await db.select(db.auditLogLocal).get()).single;
        expect([fila.evento, fila.motivo], ['venta_monto_manual', 'diferencia_centavos:-10000']);
      },
    );

    test('sin motivo nuevo la venta conserva el suyo', () async {
      await venta39(motivo: 'redondeo', monto: 140000);

      await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);

      final venta = await db.select(db.ventas).getSingle();
      expect([venta.montoTotal, venta.motivoMontoManual], [180000, 'redondeo']);
    });

    test('la cita de cobranza de la persona cuenta como agendada; sin citas, nada', () async {
      await venta39();
      expect(await local.citasDe('v-39'), (cobranzaAgendada: false, entregaAgendada: false));

      await insertarAgenda(db, agendaDe('a-1', tipo: TipoAgenda.cobranza, fecha: t1));

      expect(await local.citasDe('v-39'), (cobranzaAgendada: true, entregaAgendada: false));
    });
  });

  group('la entrega de lo sumado', () {
    test(
      'entregar el libro nuevo no se frena por lo que la venta ya entregó y no lo toca',
      () async {
        await venta39();
        await entregarTodo('v-39');
        final r = await local.sumar(
          'v-39',
          [nuevo('n-1', 'v-39')],
          sumadoCentavos: 40000,
          ahora: t1,
        );

        final registrada = await entregas.registrarEntrega('v-39', [
          Entrega(
            id: 'e-2',
            ventaId: 'v-39',
            productoId: 'prod-2',
            cantidad: 1,
            pendiente: false,
            fechaEntrega: t1,
            auditoria: Auditoria(createdAt: t1, updatedAt: t1, createdBy: 'col-1'),
          ),
        ], soloDesde: r.sumadoEl);

        expect(registrada.yaEstaba, isFalse);
        expect(registrada.entregas.map((e) => e.id), ['e-2']);
        final todas = await db.select(db.entregas).get();
        expect(todas.map((e) => e.id), containsAll(['e-1', 'e-2']));
        expect(todas.firstWhere((e) => e.id == 'e-1').fechaEntrega, t0);
      },
    );

    test('un segundo toque sobre lo sumado no entrega dos veces', () async {
      await venta39();
      final r = await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);
      Entrega fila(String id) => Entrega(
        id: id,
        ventaId: 'v-39',
        productoId: 'prod-2',
        cantidad: 1,
        pendiente: false,
        fechaEntrega: t1,
        auditoria: Auditoria(createdAt: t1, updatedAt: t1, createdBy: 'col-1'),
      );
      await entregas.registrarEntrega('v-39', [fila('e-2')], soloDesde: r.sumadoEl);

      final otra = await entregas.registrarEntrega('v-39', [fila('e-3')], soloDesde: r.sumadoEl);

      expect(otra.yaEstaba, isTrue);
      expect((await db.select(db.entregas).get()).map((e) => e.id), ['e-2']);
    });

    test('dejar el libro nuevo para otro día crea su cita si la venta no tenía', () async {
      await venta39();
      await entregarTodo('v-39');
      final r = await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);
      final cuando = t1.add(const Duration(days: 2));

      final diferida = await entregas.diferir(
        'v-39',
        fechaPrevista: cuando,
        ahora: t1,
        filasNuevas: [
          Entrega(
            id: 'e-2',
            ventaId: 'v-39',
            productoId: 'prod-2',
            cantidad: 1,
            pendiente: true,
            fechaPrevista: cuando,
            auditoria: Auditoria(createdAt: t1, updatedAt: t1, createdBy: 'col-1'),
          ),
        ],
        idDeLaCita: 'a-9',
        soloDesde: r.sumadoEl,
      );

      expect(diferida.entregas.map((e) => e.id), ['e-2']);
      expect([diferida.cita.id, diferida.citaNueva], ['a-9', isTrue]);
    });

    test('si lo de antes ya tiene su cita de entrega, no se agenda otra ni se mueve', () async {
      await venta39();
      final antes = t0.add(const Duration(days: 1));
      await entregas.diferir(
        'v-39',
        fechaPrevista: antes,
        ahora: t0,
        filasNuevas: [
          Entrega(
            id: 'e-1',
            ventaId: 'v-39',
            productoId: 'prod-1',
            cantidad: 3,
            pendiente: true,
            fechaPrevista: antes,
            auditoria: auditoriaDe(),
          ),
        ],
        idDeLaCita: 'a-1',
      );
      final r = await local.sumar('v-39', [nuevo('n-1', 'v-39')], sumadoCentavos: 40000, ahora: t1);

      await expectLater(
        entregas.diferir(
          'v-39',
          fechaPrevista: t1.add(const Duration(days: 5)),
          ahora: t1,
          filasNuevas: const [],
          idDeLaCita: 'a-2',
          soloDesde: r.sumadoEl,
        ),
        throwsA(isA<EntregaYaAgendadaException>()),
      );
      final cita = await (db.select(db.agendas)..where((a) => a.id.equals('a-1'))).getSingle();
      expect(cita.fechaProgramada, antes);
      expect(await local.citasDe('v-39'), (cobranzaAgendada: false, entregaAgendada: true));
    });
  });
}
