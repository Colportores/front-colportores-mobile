// HU-VEN-005 (#429): la ficha de la persona compone lo que compró, lo que recibió y lo que debe, con la
// base real en memoria. Escenario de la HU («Vista compuesta»): María con 3 ventas, 2 entregas pendientes
// y 1 cobro pendiente ve todo con los totales correctos. Escenario de HU-VEN-002 («Venta + entrega
// inmediata»): lo entregado al vender aparece como «entregado» en su ficha.
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
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/ficha_persona_use_cases.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ObservarFichaDePersonaUseCase observar;

  Future<void> venta(String id, {required int monto, String talonario = '0042'}) => db
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

  Future<void> renglon(String id, String ventaId, String producto, {int cantidad = 1}) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(producto),
          cantidad: cantidad,
          precioUnitario: 1000,
          subtotal: 1000 * cantidad,
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

  Future<void> entrega(
    String id,
    String ventaId,
    String producto,
    DateTime cuando, {
    int cantidad = 1,
  }) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: producto,
          cantidad: cantidad,
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
    for (final (id, nombre) in [('pro-1', 'Salud y Hogar'), ('pro-2', 'Nuestros Hijos')]) {
      await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              id: id,
              nombre: nombre,
              tipo: 'LIBRO',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
    }
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

  Future<FichaDePersona> ficha() async =>
      (await observar(personaId: 'per-1', espacioId: 'esp-1').first)!;

  group('Vista compuesta: 3 ventas, 2 entregas pendientes y 1 cobro pendiente', () {
    /// María: ven-1 ($ 1.200, 2 libros, entregó uno y pagó $ 600), ven-2 ($ 300, 1 libro sin entregar,
    /// pagada), ven-3 ($ 200, 1 libro entregado, pagada).
    Future<void> sembrarAMaria() async {
      await venta('ven-1', monto: 120000, talonario: '0042');
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-1', 'pro-2');
      await entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 13, 15));
      await cobro('cob-1', 'ven-1', 60000, DateTime.utc(2026, 10, 20, 16));

      await venta('ven-2', monto: 30000, talonario: '0043');
      await renglon('it-3', 'ven-2', 'pro-2');
      await cobro('cob-2', 'ven-2', 30000, DateTime.utc(2026, 10, 14, 10));

      await venta('ven-3', monto: 20000, talonario: '0044');
      await renglon('it-4', 'ven-3', 'pro-1');
      await entrega('ent-3', 'ven-3', 'pro-1', DateTime.utc(2026, 10, 15, 11));
      await cobro('cob-3', 'ven-3', 20000, DateTime.utc(2026, 10, 15, 11));
    }

    test('los cuatro totales de la cuenta suman lo de las tres ventas', () async {
      await sembrarAMaria();

      final cuenta = (await ficha()).resumen!;

      expect(cuenta.compradoCentavos, 170000);
      expect(cuenta.pagadoCentavos, 110000);
      expect(cuenta.saldoCentavos, 60000);
      expect(cuenta.entregasHechas, 2);
      expect(cuenta.entregasTotales, 4);
      expect(cuenta.entregasPendientes, 2);
      expect(TextosBajaPersona.entregas(cuenta), '2 de 4');
    });

    test('el saldo es solo de la venta con cobro pendiente: lo de otra no lo tapa', () async {
      await sembrarAMaria();
      // Un cobro de más en ven-3 no le resta a lo que debe en ven-1.
      await cobro('cob-extra', 'ven-3', 5000, DateTime.utc(2026, 10, 16, 9));

      final cuenta = (await ficha()).resumen!;

      expect(cuenta.saldoCentavos, 60000);
    });

    test('«Con saldo» deja solo la venta que todavía se debe', () async {
      await sembrarAMaria();
      final f = await ficha();

      final conSaldo = FiltroDeHistorialDeFicha.aplicar(
        f.historial,
        FiltroDeHistorial.conSaldo,
        resumen: f.resumen,
      );

      expect(conSaldo.map((m) => m.id), ['ven-1']);
    });

    test('cada cobro dice de qué venta es y cada entrega hecha lleva su venta', () async {
      await sembrarAMaria();

      final f = await ficha();

      final cobros = f.historial.whereType<CobroEnFicha>().toList();
      expect(
        {for (final c in cobros) c.id: c.ventaId},
        {'cob-1': 'ven-1', 'cob-2': 'ven-2', 'cob-3': 'ven-3'},
      );
      expect(
        {for (final c in cobros) c.id: c.numeroTalonario},
        {'cob-1': '0042', 'cob-2': '0043', 'cob-3': '0044'},
      );
      final entregas = f.historial.whereType<EntregaEnFicha>().toList();
      expect({for (final e in entregas) e.id: e.ventaId}, {'ent-1': 'ven-1', 'ent-3': 'ven-3'});
      expect(entregas.every((e) => !e.pendiente), isTrue);
    });

    test('el historial junta ventas, entregas y cobros, el más nuevo primero', () async {
      await sembrarAMaria();

      final f = await ficha();

      final ids = f.historial.map((m) => m.id).toList();
      // Con la misma fecha manda el id, de mayor a menor: la entrega de ven-3 va antes que su cobro.
      expect(ids.take(5), ['cob-1', 'ent-3', 'cob-3', 'cob-2', 'ent-1']);
      expect(ids.skip(5), unorderedEquals(['ven-1', 'ven-2', 'ven-3']));
    });

    test('al entregar lo que faltaba la cuenta y la ficha se actualizan sola', () async {
      await sembrarAMaria();
      final fichas = <FichaDePersona?>[];
      final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen(fichas.add);
      Future<void> esperarA(bool Function() condicion) async {
        final limite = DateTime.now().add(const Duration(seconds: 5));
        while (!condicion() && DateTime.now().isBefore(limite)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await esperarA(() => fichas.isNotEmpty);
      expect(fichas.last!.resumen!.entregasPendientes, 2);

      await entrega('ent-2', 'ven-1', 'pro-2', DateTime.utc(2026, 10, 22, 9));
      await esperarA(() => fichas.last?.resumen?.entregasPendientes == 1);
      expect(fichas.last!.resumen!.entregasPendientes, 1);
      expect(fichas.last!.historial.map((m) => m.id), contains('ent-2'));

      await sub.cancel();
    });
  });

  group('HU-VEN-002 · Venta + entrega inmediata: el material aparece como «entregado»', () {
    test(
      'una venta de 3 libros entregada al vender figura «Entregado 3 de 3» y como entrega',
      () async {
        await venta('ven-1', monto: 90000);
        await renglon('it-1', 'ven-1', 'pro-1', cantidad: 3);
        await entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 12, 14), cantidad: 3);

        final f = await ficha();

        final cuenta = f.resumen!;
        expect(TextosBajaPersona.entregas(cuenta), '3 de 3');
        expect(cuenta.entregasPendientes, 0);
        final hecha = f.historial.whereType<EntregaEnFicha>().single;
        expect(hecha.pendiente, isFalse);
        expect(hecha.ventaId, 'ven-1');
        expect(hecha.lineas.single.nombre, 'Salud y Hogar');
        expect(hecha.lineas.single.cantidad, 3);
      },
    );

    test('y no cuenta como pendiente: el filtro «Entrega pendiente» no la trae', () async {
      await venta('ven-1', monto: 90000);
      await renglon('it-1', 'ven-1', 'pro-1', cantidad: 3);
      await entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 12, 14), cantidad: 3);

      final f = await ficha();

      expect(
        FiltroDeHistorialDeFicha.aplicar(
          f.historial,
          FiltroDeHistorial.entregaPendiente,
          resumen: f.resumen,
        ),
        isEmpty,
      );
    });

    test('un combo entregado al vender es una sola entrega con sus productos', () async {
      await venta('ven-1', monto: 120000);
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-1', 'pro-2');
      final cuando = DateTime.utc(2026, 10, 12, 14);
      await entrega('ent-1', 'ven-1', 'pro-1', cuando);
      await entrega('ent-2', 'ven-1', 'pro-2', cuando);

      final f = await ficha();

      final entregas = f.historial.whereType<EntregaEnFicha>().toList();
      expect(entregas, hasLength(1));
      expect(entregas.single.lineas.map((l) => l.nombre), ['Salud y Hogar', 'Nuestros Hijos']);
      expect(TextosBajaPersona.entregas(f.resumen!), '2 de 2');
    });
  });
}
