// «Entregar ahora» sobre una venta con entregas pendientes (HU-VEN-003, #433; decisión del 30/10 por el
// QA de #584): cumplir lo pendiente es la misma operación que «Marcar como entregado», no una fila
// nueva. Contra las tablas reales, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/entrega_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late VentaLocalDataSourceDrift ventas;
  late CobranzaLocalDataSourceDrift cobranzas;
  late EntregaLocalDataSourceDrift local;

  final sabado = DateTime.utc(2026, 10, 31, 13);
  final ahora = DateTime.utc(2026, 10, 28, 15);
  final hoy = DateTime.utc(2026, 10, 31, 16);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estado = HouseStatusUpdaterDrift(db, encolador: encolador);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<EntregaFila>> filas() =>
      (db.select(db.entregas)..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
  Future<List<AgendaFila>> citas() => db.select(db.agendas).get();

  /// Una venta de 3 unidades de `prod-1`.
  Future<void> vender() async {
    await ventas.registrar(ventaDe('v-1', monto: 150000, talonario: 'T-1'), [itemDe('i-1', 'v-1')]);
    encolador.encolados.clear();
  }

  Future<void> dejarPendiente(List<Entrega> filas) async {
    await local.diferir(
      'v-1',
      fechaPrevista: sabado,
      ahora: ahora,
      filasNuevas: filas,
      idDeLaCita: 'c-1',
    );
    encolador.encolados.clear();
  }

  Entrega pendiente(String id, int cantidad) =>
      entregaDe(id, 'prod-1', cantidad: cantidad, pendiente: true, fechaPrevista: sabado);

  var n = 0;
  String id() => 'n-${++n}';

  Future<EntregaRegistrada> entregarAhora() =>
      local.entregarAhora('v-1', colportorId: 'col-1', ahora: hoy, generarId: id);

  test('cumple la fila pendiente en vez de agregar otra: una sola fila por libro', () async {
    await vender();
    await dejarPendiente([pendiente('e-1', 3)]);

    final r = await entregarAhora();

    expect(r.yaEstaba, isFalse);
    expect(r.quedaPendiente, isFalse);
    final todas = await filas();
    expect(todas.map((f) => [f.id, f.cantidad, f.pendiente, f.fechaEntrega, f.fechaPrevista]), [
      ['e-1', 3, false, hoy, sabado],
    ]);
    // Solo un `update` de la fila: el servidor ve el paso pendiente → entregada una sola vez y
    // descuenta el stock una sola vez. Con saldo la casa no cambia de color (decisión del 28/10).
    expect(cola(), ['entrega:update', 'agenda:update']);
  });

  test('pagada, cumplir lo pendiente deja la casa en «Venta completa» (4)', () async {
    await vender();
    await dejarPendiente([pendiente('e-1', 3)]);
    await cobranzas.registrar(
      Cobranza(
        id: 'cob-1',
        ventaId: 'v-1',
        montoCentavos: 150000,
        medio: MedioCobranza.efectivo,
        fecha: ahora,
        auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: 'col-1'),
      ),
    );
    encolador.encolados.clear();

    final r = await entregarAhora();

    expect(r.colorDeLaCasa?.codigo, 'VENTA_COMPLETA');
    expect(cola(), ['entrega:update', 'agenda:update', 'house_status:update']);
  });

  test('cumple la cita de la entrega y lo dice el resultado para sacarle el aviso', () async {
    await vender();
    await dejarPendiente([pendiente('e-1', 3)]);

    final r = await entregarAhora();

    expect(r.citaCumplidaId, 'c-1');
    expect((await citas()).single.estado, 'CUMPLIDA');
  });

  test('lo que no tenía fila se inserta, y lo pendiente se cumple', () async {
    await vender();
    await dejarPendiente([pendiente('e-1', 2)]);

    final r = await entregarAhora();

    final todas = await filas();
    expect(todas.length, 2);
    expect(todas.every((f) => !f.pendiente && f.fechaEntrega == hoy), isTrue);
    expect(todas.fold<int>(0, (s, f) => s + f.cantidad), 3);
    expect(todas.first.id, 'e-1');
    expect(r.quedaPendiente, isFalse);
    expect(cola(), contains('entrega:insert'));
    expect(cola().where((c) => c == 'entrega:update'), hasLength(1));
  });

  test('un segundo toque no escribe nada ni vuelve a tocar la cita', () async {
    await vender();
    await dejarPendiente([pendiente('e-1', 3)]);
    await entregarAhora();
    encolador.encolados.clear();

    final r = await entregarAhora();

    expect(r.yaEstaba, isTrue);
    expect(r.citaCumplidaId, isNull);
    expect(encolador.encolados, isEmpty);
    expect(await filas(), hasLength(1));
  });

  test('sin pendientes se entrega como siempre: filas nuevas ya entregadas', () async {
    await vender();

    final r = await entregarAhora();

    final todas = await filas();
    expect(todas.map((f) => [f.cantidad, f.pendiente, f.fechaEntrega]), [
      [3, false, hoy],
    ]);
    expect(r.citaCumplidaId, isNull);
    expect(cola(), contains('entrega:insert'));
  });

  test('una venta sin cita (entrega parcial sin fecha) también se cumple, sin cita', () async {
    await vender();
    await local.registrarEntrega('v-1', [
      entregaDe('e-1', 'prod-1', pendiente: false),
      entregaDe('e-2', 'prod-1', cantidad: 2, pendiente: true),
    ]);
    encolador.encolados.clear();

    final r = await entregarAhora();

    expect(r.citaCumplidaId, isNull);
    final todas = await filas();
    expect(todas.map((f) => [f.id, f.pendiente]), [
      ['e-1', false],
      ['e-2', false],
    ]);
  });
}
