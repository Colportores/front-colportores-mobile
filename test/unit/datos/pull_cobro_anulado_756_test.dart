// «El teléfono muestra el cobro que anuló la coordinadora» de punta a punta (#756, HU-COB-006, vista
// 30B-05; decisión de Cristian, 23/11, «Anul. al tel»; backend-supabase#306, migración 0203): el motor
// real baja el delta de un servidor falso y lo que baja entra por `DriftLocalStore` a la tabla `cobranza`.
// `cobranza` es `push` crítico con `alsoPull`: sube lo que cobra la colportora y baja el mismo cobro con
// `anulado_at`, `motivo_anulacion` y `anulado_por` cuando lo anula la coordinación desde el panel.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/armado_del_motor.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/services/casas_de_cobros_bajados.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/textos_anular_cobro.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/venta_falsos.dart';

/// La fila de `cobranza` tal como la entrega el servidor en el pull.
Map<String, Object?> _fila(
  String id, {
  String ventaId = 'v-1',
  int monto = 150000,
  int version = 2,
  String? anuladoAt,
  String? motivo,
  String? anuladoPor,
}) => {
  'id': id,
  'venta_id': ventaId,
  'monto': monto,
  'medio': 'EFECTIVO',
  'fecha': t0.toIso8601String(),
  'tarjeta_tipo': null,
  'tarjeta_marca': null,
  'numero_aprobacion': null,
  'referencia_transferencia': null,
  'banco_origen': null,
  'ticket_id': null,
  'anulado_at': anuladoAt,
  'motivo_anulacion': motivo,
  'anulado_por': anuladoPor,
  'corregido_at': null,
  'created_at': t0.toIso8601String(),
  'updated_at': t0.toIso8601String(),
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': version,
};

final _anulacion = t0.add(const Duration(hours: 30)).toIso8601String();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;
  late CobranzaLocalDataSourceDrift local;
  late String colorSinCobro;
  late String colorSaldada;

  Future<String?> color() async => (await db.select(db.houseStatuses).get())
      .where((h) => h.deletedAt == null)
      .firstOrNull
      ?.color;

  /// Lo que quedó en la cola de sync, por entidad y operación.
  Future<List<String>> cola() async => [
    for (final j in await db.select(db.syncQueue).get()) '${j.entity}:${j.op}',
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    red = FakeConnectivityPort();
    motor = armarMotorDeSync(
      db: db,
      leerDek: () async => null,
      tokenDrive: () async => null,
      transporte: servidor,
      conectividad: red,
      archivo: FakeArchive(),
      recalcularCasasAlBajarCobros: true,
    );
    // Lo que ya había en el teléfono (una venta de $ 1.500 saldada con un cobro de $ 1.500), escrito
    // sin pasar por la cola del motor: lo que sigue prueba solo lo que baja.
    final encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
    await VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    ).registrar(ventaDe('v-1', monto: 150000), [itemDe('i-1', 'v-1', cantidad: 1, precio: 150000)]);
    // Todo entregado: así el saldo en cero pinta «venta completa» y el saldo que vuelve, «pendiente».
    await db
        .into(db.entregas)
        .insert(
          EntregasCompanion.insert(
            id: 'e-1',
            ventaId: 'v-1',
            productoId: 'prod-1',
            cantidad: 1,
            pendiente: const Value(false),
            fechaEntrega: Value(t0),
            createdAt: t0,
            updatedAt: t0,
          ),
        );
    colorSinCobro = (await color())!;
    await local.registrar(_cobro('c-1', 150000));
    colorSaldada = (await color())!;
    expect(colorSaldada, isNot(colorSinCobro), reason: 'el cobro tiene que cambiar el color');
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  test('el catálogo declara `cobranza` como push, crítico y con pull', () {
    final spec = specsDeLaApp.singleWhere((s) => s.entity == 'cobranza');

    expect(spec.policy, SyncPolicy.push);
    expect(spec.alsoPull, isTrue);
    expect(spec.critical, isTrue);
    expect(spec.pullable, isTrue);
  });

  test('el cobro que anuló la coordinación baja anulado, con el motivo de la lista, y el saldo de '
      'la venta vuelve', () async {
    expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 0);
    servidor.seed('cobranza', [
      _fila('c-1', anuladoAt: _anulacion, motivo: 'Monto equivocado', anuladoPor: 'coord-1'),
    ]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 1);
    final cobro = (await db.select(db.cobranzas).getSingle());
    expect(cobro.anuladoAt, t0.add(const Duration(hours: 30)));
    expect(cobro.motivoAnulacion, 'Monto equivocado');
    expect(cobro.deletedAt, isNull, reason: 'anular no es dar de baja');
    expect(cobro.syncVersion, 2);
    final venta = (await local.ventaConSaldo('v-1'))!;
    expect(venta.saldoCentavos, 150000, reason: 'el saldo vuelve a como estaba');
  });

  test('se ve en el detalle como «Anulado · motivo» (30B-05)', () async {
    servidor.seed('cobranza', [
      _fila('c-1', anuladoAt: _anulacion, motivo: 'Cliente equivocado', anuladoPor: 'coord-1'),
    ]);
    await motor.syncNow();

    final detalle = (await local.detalle('c-1'))!;

    expect(detalle.cobranza.estaAnulado, isTrue);
    expect(
      TextosAnularCobro.estadoAnulado(detalle.cobranza.motivoAnulacion),
      'Anulado · Cliente equivocado',
    );
    expect(detalle.venta.saldoCentavos, 150000);
  });

  test('la casa vuelve a su color de antes del cobro y el cambio sube con la cola', () async {
    servidor.seed('cobranza', [
      _fila('c-1', anuladoAt: _anulacion, motivo: 'Monto equivocado', anuladoPor: 'coord-1'),
    ]);

    await motor.syncNow();

    expect(await color(), colorSinCobro);
    final encolados = await cola();
    expect(encolados.where((j) => j.startsWith('house_status:')), hasLength(1));
    expect(
      encolados.where((j) => j.startsWith('cobranza:')),
      isEmpty,
      reason: 'lo que baja del servidor no vuelve a subir',
    );

    await motor.syncNow();

    final subidos = servidor.batches.expand((b) => b.jobs).map((j) => j.entity).toList();
    expect(subidos, ['house_status']);
  });

  test(
    'con «Otro» baja «Otro» y nada más: el texto de la coordinación no está en el teléfono',
    () async {
      servidor.seed('cobranza', [
        _fila('c-1', anuladoAt: _anulacion, motivo: 'Otro', anuladoPor: 'coord-1'),
      ]);

      await motor.syncNow();

      final cobro = await db.select(db.cobranzas).getSingle();
      expect(cobro.motivoAnulacion, 'Otro');
      expect(TextosAnularCobro.estadoAnulado(MotivoDeAnulacion.otro), 'Anulado · Otro');
      expect(await db.select(db.auditLogLocal).get(), isEmpty);
    },
  );

  test(
    'lo que la colportora anuló ella misma no cambia al volver a bajar (el eco del push)',
    () async {
      await local.anular(
        cobranzaId: 'c-1',
        motivo: MotivoDeAnulacion.montoEquivocado,
        colportorId: 'col-1',
        ahora: t0.add(const Duration(hours: 2)),
      );
      final colorAntes = await color();
      final antes = await db.select(db.cobranzas).getSingle();
      servidor.seed('cobranza', [
        _fila(
          'c-1',
          anuladoAt: antes.anuladoAt!.toIso8601String(),
          motivo: 'Monto equivocado',
          anuladoPor: 'col-1',
        ),
      ]);

      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      expect(await color(), colorAntes);
      final despues = await db.select(db.cobranzas).getSingle();
      expect(despues.anuladoAt, antes.anuladoAt);
      expect(despues.motivoAnulacion, antes.motivoAnulacion);
      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 150000);
    },
  );

  test('si Ana tenía la pantalla de anular abierta cuando bajó la anulación, confirmar no escribe '
      'nada de más: el cobro ya está anulado', () async {
    servidor.seed('cobranza', [
      _fila('c-1', anuladoAt: _anulacion, motivo: 'Cliente equivocado', anuladoPor: 'coord-1'),
    ]);
    await motor.syncNow();
    await motor.syncNow(); // sube el cambio de color de la casa
    final subidosAntes = servidor.jobsReceived;

    final r = await local.anular(
      cobranzaId: 'c-1',
      motivo: MotivoDeAnulacion.montoEquivocado,
      colportorId: 'col-1',
      ahora: t0.add(const Duration(hours: 31)),
    );
    await motor.syncNow();

    expect(r.yaEstaba, isTrue);
    expect(r.detalle.venta.saldoCentavos, 150000);
    final cobro = await db.select(db.cobranzas).getSingle();
    expect(
      cobro.motivoAnulacion,
      'Cliente equivocado',
      reason: 'queda el motivo de la coordinación',
    );
    expect(await db.select(db.auditLogLocal).get(), isEmpty);
    expect(servidor.jobsReceived, subidosAntes, reason: 'no vuelve a subir nada');
  });

  test('pull idempotente: el segundo no aplica cambios ni encola otra vez la casa', () async {
    servidor.seed('cobranza', [
      _fila('c-1', anuladoAt: _anulacion, motivo: 'Monto equivocado', anuladoPor: 'coord-1'),
    ]);
    await motor.syncNow();
    await motor.syncNow(); // sube el cambio de color de la casa
    final lotes = servidor.batches.length;

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 0);
    expect(servidor.batches.length, lotes, reason: 'no hay nada nuevo que subir');
    expect(await color(), colorSinCobro);
  });

  test('un cobro de otra venta que el teléfono no tiene baja igual y no traba el pull', () async {
    servidor.seed('cobranza', [
      _fila('c-9', ventaId: 'v-que-no-esta', anuladoAt: _anulacion, motivo: 'Otro'),
      _fila('c-1', anuladoAt: _anulacion, motivo: 'Monto equivocado', anuladoPor: 'coord-1'),
    ]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 2);
    expect(await color(), colorSinCobro);
  });

  test('un cobro vivo que baja no toca el color de la casa ni encola nada', () async {
    servidor.seed('cobranza', [_fila('c-1', version: 1)]);

    await motor.syncNow();

    expect(await color(), colorSaldada);
    expect(await cola(), isEmpty);
  });

  test(
    'si el recálculo del color falla, el cobro ya quedó anulado y el pull no se traba',
    () async {
      final casas = CasasDeCobrosBajados(
        db,
        encolador: EncoladorSyncEnMemoria(fallarCon: StateError('sin cola')),
      );
      await db.customStatement('UPDATE cobranza SET anulado_at = 1, motivo_anulacion = \'Otro\'');

      await casas({
        'cobranza': [_fila('c-1', anuladoAt: _anulacion, motivo: 'Otro')],
      });

      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 150000);
    },
  );
}

Cobranza _cobro(String id, int monto) => Cobranza(
  id: id,
  ventaId: 'v-1',
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);
