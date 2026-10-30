// La ficha de una persona armada de punta a punta con la base real en memoria (HU-UBI-009, #403): el
// caso de uso junta el historial (visitas, ventas, entregas y cobros por fecha) y la cuenta (comprado,
// entregado, pagado, saldo), con los criterios de la HU y la lectura en menos de 500 ms.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/cuenta_de_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ficha_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/espacio_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ficha_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/nota_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/cuenta_de_persona_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/ficha_persona_use_cases.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ObservarFichaDePersonaUseCase observar;

  Future<void> venta(String id, {int monto = 120000, String talonario = '0042'}) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: 'ep-1',
          numeroTalonario: talonario,
          montoTotal: monto,
          fecha: DateTime.utc(2026, 10, 12, 14),
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> renglon(String id, String ventaId, String producto) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(producto),
          cantidad: 1,
          precioUnitario: 1000,
          subtotal: 1000,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> cobro(String id, String ventaId, int monto, DateTime fecha) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: ventaId,
          monto: monto,
          medio: 'EFECTIVO',
          fecha: fecha,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> entrega(String id, String ventaId, String producto, DateTime cuando) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: producto,
          cantidad: 1,
          pendiente: const Value(false),
          fechaEntrega: Value(cuando),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await sembrarCasa(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(id: 'per-1', nombre: 'María', createdAt: t0, updatedAt: t0),
        );
    await db
        .into(db.productos)
        .insert(
          ProductosCompanion.insert(
            id: 'pro-1',
            nombre: 'Salud y Hogar',
            tipo: 'LIBRO',
            createdAt: t0,
            updatedAt: t0,
          ),
        );
    final local = CuentaDePersonaLocalDataSourceDrift(db);
    observar = ObservarFichaDePersonaUseCase(
      fichas: FichaPersonaRepositoryImpl(FichaPersonaLocalDataSourceDrift(db)),
      notas: NotaPersonaRepositoryImpl(NotaPersonaLocalDataSourceDrift(db)),
      espacios: EspacioRepositoryImpl(
        UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria()),
        logger: loggerMudo(),
      ),
      cuentas: CuentasDePersonasDrift(local),
      movimientos: MovimientosDeCuentaDrift(local),
    );
  });
  tearDown(() => db.close());

  /// Espera hasta [tope] a que [condicion] se cumpla: el caso de uso junta varias lecturas de la base
  /// y `pumpEventQueue` solo no alcanza.
  Future<void> esperarA(bool Function() condicion) async {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (!condicion() && DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<FichaDePersona?> ficha() => observar(personaId: 'per-1', espacioId: 'esp-1').first;

  test('sin ventas la persona no tiene cuenta ni historial', () async {
    final f = (await ficha())!;

    expect(f.resumen, isNull);
    expect(f.historial, isEmpty);
  });

  test('la venta, su entrega y sus cobros entran al historial por fecha y a la cuenta', () async {
    await venta('ven-1');
    await renglon('it-1', 'ven-1', 'pro-1');
    await entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 13, 15));
    await cobro('cob-1', 'ven-1', 60000, DateTime.utc(2026, 10, 20, 16));

    final f = (await ficha())!;

    expect(f.historial.map((m) => m.id), ['cob-1', 'ent-1', 'ven-1']);
    final entregaEnFicha = f.historial[1] as EntregaEnFicha;
    expect(entregaEnFicha.lineas.single.nombre, 'Salud y Hogar');
    final cuenta = f.resumen!;
    expect(cuenta.compradoCentavos, 120000);
    expect(cuenta.pagadoCentavos, 60000);
    expect(cuenta.saldoCentavos, 60000);
    expect(cuenta.entregasHechas, 1);
    expect(cuenta.entregasTotales, 1);
  });

  test('la ficha se actualiza sola cuando se registra un cobro o una entrega', () async {
    await venta('ven-1');
    await renglon('it-1', 'ven-1', 'pro-1');
    final fichas = <FichaDePersona?>[];
    final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen(fichas.add);
    await esperarA(() => fichas.isNotEmpty);
    expect(fichas.last!.resumen!.saldoCentavos, 120000);
    expect(fichas.last!.resumen!.entregasHechas, 0);

    await cobro('cob-1', 'ven-1', 120000, DateTime.utc(2026, 10, 20, 16));
    await esperarA(() => fichas.last?.resumen?.saldoCentavos == 0);
    expect(fichas.last!.resumen!.saldoCentavos, 0);
    expect(fichas.last!.historial.map((m) => m.id), contains('cob-1'));

    await entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 21, 9));
    await esperarA(() => fichas.last?.resumen?.entregasHechas == 1);
    expect(fichas.last!.resumen!.entregasHechas, 1);
    expect(fichas.last!.historial.map((m) => m.id), contains('ent-1'));

    await sub.cancel();
  });

  test('con cientos de movimientos la primera lectura tarda menos de 500 ms', () async {
    await venta('ven-1', monto: 100000000);
    await renglon('it-1', 'ven-1', 'pro-1');
    for (var i = 0; i < 300; i++) {
      await cobro(
        'cob-${i.toString().padLeft(3, '0')}',
        'ven-1',
        100,
        DateTime.utc(2026, 10, 1).add(Duration(hours: i)),
      );
    }
    for (var i = 0; i < 100; i++) {
      await insertarVisita(db, visitaDe('vis-${i.toString().padLeft(3, '0')}'));
    }

    final reloj = Stopwatch()..start();
    final f = (await ficha())!;
    reloj.stop();

    expect(f.historial, hasLength(401));
    expect(reloj.elapsedMilliseconds, lessThan(500));
  });
}
