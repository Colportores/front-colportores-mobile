// «Entregar ahora» con filas tildadas contra las tablas reales (HU-VEN-002, #432): AppDatabase en
// memoria, mismo esquema y mismos CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/entrega_repository_impl.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/entrega_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

class _Capturador extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late VentaLocalDataSourceDrift ventas;
  late EntregaLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estado = HouseStatusUpdaterDrift(db, encolador: encolador);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<EntregaFila>> entregas() => db.select(db.entregas).get();
  Future<String?> color() async =>
      (await db.select(db.houseStatuses).get()).map((h) => h.color).singleOrNull;

  /// Una venta de [monto] con un libro; la deja registrada (y la casa pintada).
  Future<void> vender({int monto = 150000}) async {
    await ventas.registrar(ventaDe('v-1', monto: monto), [itemDe('i-1', 'v-1')]);
    encolador.encolados.clear();
  }

  group('registrarEntrega', () {
    test('guarda una fila por producto, las encola y recalcula la casa en la misma tanda', () async {
      await vender();

      final r = await local.registrarEntrega('v-1', [
        entregaDe('e-1', 'prod-1', cantidad: 3),
        entregaDe('e-2', 'prod-2'),
      ]);

      expect(r.yaEstaba, isFalse);
      expect(r.quedaPendiente, isFalse);
      final filas = await entregas();
      expect(filas.map((f) => f.id), unorderedEquals(['e-1', 'e-2']));
      final primera = filas.firstWhere((f) => f.id == 'e-1');
      expect(
        [primera.ventaId, primera.productoId, primera.cantidad, primera.pendiente],
        ['v-1', 'prod-1', 3, false],
      );
      expect(primera.fechaEntrega, t0);
      // La casa ya estaba en «Entrega y cobranza pendientes» y sigue igual: el color no cambió, así
      // que `house_status` no se encola.
      expect(cola(), ['entrega:insert', 'entrega:insert']);
    });

    test('entregado y con saldo, la casa sigue en «Entrega y cobranza pendientes» (1)', () async {
      // Decisión del 28/10: con saldo la casa no sale del 1 por entregar (`CalculadorColorCasa`).
      await vender();
      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

      final r = await local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]);

      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      expect(r.colorDeLaCasa, ColorHouseStatus.entregaYCobranzaPendiente);
    });

    test('con una fila pendiente la casa sigue en «Entrega y cobranza pendientes» (1)', () async {
      await vender();

      final r = await local.registrarEntrega('v-1', [
        entregaDe('e-1', 'prod-1'),
        entregaDe('e-2', 'prod-2', pendiente: true),
      ]);

      expect(r.quedaPendiente, isTrue);
      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      final pendiente = (await entregas()).firstWhere((f) => f.id == 'e-2');
      expect([pendiente.pendiente, pendiente.fechaEntrega], [true, null]);
    });

    test('una venta de \$ 0 entregada no pinta la casa por sí sola', () async {
      await vender(monto: 0);
      expect(await color(), isNull);

      final r = await local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]);

      expect(await color(), isNull);
      expect(r.colorDeLaCasa, isNull);
    });

    test('una venta de \$ 0 con algo pendiente sigue sin pintar la casa', () async {
      await vender(monto: 0);

      final r = await local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1', pendiente: true)]);

      expect(await color(), isNull);
      expect(r.colorDeLaCasa, isNull);
    });

    test('lo que sube lleva las claves de public.entrega y ningún dato de la persona', () async {
      await vender();

      await local.registrarEntrega('v-1', [
        entregaDe('e-1', 'prod-1', cantidad: 2),
        entregaDe('e-2', 'prod-2', pendiente: true),
      ]);

      final entregada = encolador.encolados.first.payload;
      expect(
        entregada.keys,
        unorderedEquals([
          'id',
          'venta_id',
          'producto_id',
          'cantidad',
          'fecha_entrega',
          'pendiente',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        ]),
      );
      expect(entregada['fecha_entrega'], '2026-10-23T13:45:10.123Z');
      expect(entregada['pendiente'], false);
      expect(entregada.containsKey('stock_inconsistente'), isFalse);
      final pendiente = encolador.encolados[1].payload;
      expect([pendiente['pendiente'], pendiente['fecha_entrega']], [true, null]);
      expect('${encolador.encolados.map((c) => c.payload)}', isNot(contains('Atiende')));
    });

    test(
      'el segundo toque no escribe ni encola de nuevo y responde con lo de la primera',
      () async {
        await vender();
        await local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]);
        final antes = cola();

        final segunda = await local.registrarEntrega('v-1', [entregaDe('e-9', 'prod-1')]);

        expect(segunda.yaEstaba, isTrue);
        expect(segunda.entregas.map((e) => e.id), ['e-1']);
        expect(segunda.colorDeLaCasa, ColorHouseStatus.entregaYCobranzaPendiente);
        expect(cola(), antes);
        expect(await entregas(), hasLength(1));
      },
    );

    test('una venta que no está en el teléfono no se entrega', () async {
      await expectLater(
        local.registrarEntrega('v-x', [entregaDe('e-1', 'prod-1', ventaId: 'v-x')]),
        throwsA(isA<EntregaSinVentaException>()),
      );
      expect(await entregas(), isEmpty);
      expect(cola(), isEmpty);
    });

    test('una venta dada de baja no se entrega', () async {
      await vender();
      await (db.update(db.ventas)).write(VentasCompanion(deletedAt: Value(t0)));

      await expectLater(
        local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]),
        throwsA(isA<EntregaSinVentaException>()),
      );
    });

    test('si el encolado falla, no queda ninguna fila: todo o nada', () async {
      await vender();
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(
        local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]),
        throwsA(anything),
      );

      expect(await entregas(), isEmpty);
      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });
  });

  test('deLaVenta devuelve las filas vivas de esa venta', () async {
    await vender();
    await local.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]);

    expect((await local.deLaVenta('v-1')).map((e) => e.id), ['e-1']);
    expect(await local.deLaVenta('v-2'), isEmpty);
  });

  group('EntregaRepositoryImpl', () {
    late _Capturador salida;
    late EntregaRepositoryImpl repo;

    setUp(() {
      salida = _Capturador();
      repo = EntregaRepositoryImpl(local, logger: AppLogger(output: salida));
    });

    test('guarda y devuelve lo entregado', () async {
      await vender();

      final r = await repo.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]);

      expect(r.getOrElse(() => throw StateError('falló')).entregas.single.id, 'e-1');
      expect((await repo.deLaVenta('v-1')).getOrElse(() => const []), hasLength(1));
    });

    test('una venta ausente es FailureEntregaNoGuardada, nunca una excepción', () async {
      final r = await repo.registrarEntrega('v-x', [entregaDe('e-1', 'prod-1', ventaId: 'v-x')]);

      expect(r.fold((f) => f, (_) => null), isA<FailureEntregaNoGuardada>());
    });

    test('una falla de la base no filtra la sentencia ni datos al log ni a la falla', () async {
      await vender();
      await db.close();

      final r = await repo.registrarEntrega('v-1', [entregaDe('e-1', 'prod-1')]);

      final falla = r.fold((f) => f, (_) => null) as FailureEntregaNoGuardada;
      expect(falla.mensaje, contains('No pudimos guardar la entrega'));
      expect(falla.causa, isNot(contains('INSERT')));
      expect(salida.lineas.join('\n'), isNot(contains('INSERT')));
      expect(salida.lineas.join('\n'), isNot(contains('María')));
    });

    test('si no se puede leer, deLaVenta devuelve FailureEntregaNoDisponible', () async {
      await db.close();

      final r = await repo.deLaVenta('v-1');

      expect(r.fold((f) => f, (_) => null), isA<FailureEntregaNoDisponible>());
    });
  });
}
