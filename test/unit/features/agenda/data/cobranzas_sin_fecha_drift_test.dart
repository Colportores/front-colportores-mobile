// 42B·01G (decisión del 10/11, P4 del PR #681): el grupo «Sin fecha» de la Agenda lee, contra las
// tablas reales en memoria, las ventas del colportor que todavía se deben y no tienen ninguna cobranza
// agendada: el saldo de siempre (cobros y devoluciones), sin lo borrado, sin lo de otro colportor, y
// reactivo (agendarle la cobranza la saca).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/cobranzas_sin_fecha_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CobranzasSinFechaDrift fuente;

  Future<void> sembrarPersona() => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: 'per-1',
          nombre: 'Pedro',
          apellido: const Value('Gómez'),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> sembrarVenta(
    String id, {
    int monto = 120000,
    String colportor = 'col-1',
    String talonario = '0042',
    DateTime? fecha,
    DateTime? borrada,
  }) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: 'ep-1',
          numeroTalonario: talonario,
          montoTotal: monto,
          fecha: fecha ?? t0,
          colportorId: colportor,
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<void> sembrarCobro(String id, String ventaId, int monto, {DateTime? borrado}) => db
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
          deletedAt: Value(borrado),
        ),
      );

  Future<void> sembrarCita(
    String id, {
    String tipo = 'COBRANZA',
    String estado = 'PROGRAMADA',
    String? ventaId,
    String? vinculo = 'ep-1',
    DateTime? borrada,
  }) => db
      .into(db.agendas)
      .insert(
        AgendasCompanion.insert(
          id: id,
          espacioId: 'esp-1',
          espacioPersonaId: Value(vinculo),
          tipo: tipo,
          fechaProgramada: DateTime.utc(2026, 11, 12, 14),
          estado: Value(estado),
          colportorId: 'col-1',
          ventaId: Value(ventaId),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = CobranzasSinFechaDrift(db);
    await sembrarCasa(db);
    await sembrarPersona();
  });
  tearDown(() => db.close());

  test('una venta con saldo y sin cita sale con su saldo, la persona y la venta', () async {
    await sembrarVenta('v-1');
    await sembrarCobro('c-1', 'v-1', 30000);

    final lista = await fuente.leer('col-1');

    expect(lista, hasLength(1));
    expect(lista.single.ventaId, 'v-1');
    expect(lista.single.numeroTalonario, '0042');
    expect(lista.single.saldoCentavos, 90000);
    expect(lista.single.nombrePersona, 'Pedro Gómez');
    expect(lista.single.espacioId, 'esp-1');
    expect(lista.single.espacioPersonaId, 'ep-1');
  });

  test('una venta pagada no sale; un cobro borrado no cuenta', () async {
    await sembrarVenta('v-1', monto: 50000);
    await sembrarCobro('c-1', 'v-1', 50000);
    await sembrarVenta('v-2', monto: 50000, talonario: '0043');
    await sembrarCobro('c-2', 'v-2', 50000, borrado: t0);

    final lista = await fuente.leer('col-1');

    expect([for (final c in lista) c.ventaId], ['v-2']);
    expect(lista.single.saldoCentavos, 50000);
  });

  test(r'una venta de $0 (solo misioneros cobrados aparte) no sale', () async {
    await sembrarVenta('v-1', monto: 0);

    expect(await fuente.leer('col-1'), isEmpty);
  });

  test('con una cobranza programada de esa persona en esa casa, no sale', () async {
    await sembrarVenta('v-1');
    await sembrarCita('a-1');

    expect(await fuente.leer('col-1'), isEmpty);
  });

  test('con una cuota programada de esa venta (venta_id), no sale', () async {
    await sembrarVenta('v-1');
    await sembrarCita('a-1', ventaId: 'v-1', vinculo: null);

    expect(await fuente.leer('col-1'), isEmpty);
  });

  test('una cita cancelada, cumplida, borrada o de entrevista no cuenta como agendada', () async {
    await sembrarVenta('v-1');
    await sembrarCita('a-1', estado: 'CANCELADA');
    await sembrarCita('a-2', estado: 'CUMPLIDA');
    await sembrarCita('a-3', borrada: t0);
    await sembrarCita('a-4', tipo: 'ENTREVISTA');

    expect([for (final c in await fuente.leer('col-1')) c.ventaId], ['v-1']);
  });

  test('una cuota programada de OTRA venta no tapa a esta', () async {
    await sembrarVenta('v-1');
    await sembrarVenta('v-2', talonario: '0043');
    await sembrarCita('a-1', ventaId: 'v-2');

    expect([for (final c in await fuente.leer('col-1')) c.ventaId], ['v-1']);
  });

  test('ni las borradas ni las de otro colportor; la más vieja primero', () async {
    await sembrarVenta('v-2', fecha: t0.add(const Duration(days: 1)), talonario: '0043');
    await sembrarVenta('v-1');
    await sembrarVenta('v-3', borrada: t0);
    await sembrarVenta('v-4', colportor: 'col-2');

    expect([for (final c in await fuente.leer('col-1')) c.ventaId], ['v-1', 'v-2']);
  });

  test('con la casa dada de baja la venta no sale (no hay a dónde ir)', () async {
    await sembrarVenta('v-1');
    await (db.update(
      db.ubicaciones,
    )..where((u) => u.id.equals('ub-1'))).write(UbicacionesCompanion(deletedAt: Value(t0)));

    expect(await fuente.leer('col-1'), isEmpty);
  });

  test('es reactiva: agendar la cobranza la saca y cobrar todo también', () async {
    await sembrarVenta('v-1');
    await sembrarVenta('v-2', talonario: '0043');
    final emisiones = <List<String>>[];
    final sub = fuente
        .observar('col-1')
        .listen((l) => emisiones.add([for (final c in l) c.ventaId]));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    expect(emisiones.last, ['v-1', 'v-2']);

    await sembrarCita('a-1', ventaId: 'v-1');
    await pumpEventQueue();
    expect(emisiones.last, ['v-2']);

    await sembrarCobro('c-1', 'v-2', 120000);
    await pumpEventQueue();
    expect(emisiones.last, isEmpty);
  });

  test('una lista larga (60 ventas) sale entera', () async {
    for (var i = 0; i < 60; i++) {
      await sembrarVenta('v-${i.toString().padLeft(2, '0')}', talonario: '$i');
    }

    expect(await fuente.leer('col-1'), hasLength(60));
  });
}
