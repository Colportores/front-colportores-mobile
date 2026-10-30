// QA de la lectura de la ficha de una persona (HU-UBI-009, #403, PR #588): lo que la colportora ve en
// la cuenta y en el historial sale de las tablas `venta`, `venta_item`, `entrega` y `cobranza` de la DB
// real en memoria. Los tests del PR prueban cada consulta y el caso de uso con datos "limpios"; estos
// prueban la cuenta del canvas (32B·01), los datos hostiles (baja, otra persona, talonarios repetidos,
// productos que el catálogo no trae), la ficha abierta mientras la base cambia, la falla a mitad de la
// lectura y la privacidad.
import 'dart:async';
import 'dart:io';

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
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_persona_use_cases.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/ficha_persona_use_cases.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CuentaDePersonaLocalDataSourceDrift local;
  late ObservarFichaDePersonaUseCase observar;

  Future<void> persona(String id, {String nombre = 'María'}) => db
      .into(db.personas)
      .insert(PersonasCompanion.insert(id: id, nombre: nombre, createdAt: t0, updatedAt: t0));

  Future<void> producto(String id, String nombre) => db
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

  Future<void> venta(
    String id, {
    int monto = 450000,
    String talonario = '0042',
    String vinculo = 'ep-1',
    DateTime? fecha,
    DateTime? borrada,
  }) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: vinculo,
          numeroTalonario: talonario,
          montoTotal: monto,
          fecha: fecha ?? DateTime.utc(2026, 10, 12, 14),
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<void> renglon(String id, String ventaId, String productoId, {int cantidad = 1}) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(productoId),
          cantidad: cantidad,
          precioUnitario: 1000,
          subtotal: 1000 * cantidad,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> cobro(
    String id,
    String ventaId,
    int monto, {
    DateTime? fecha,
    String medio = 'EFECTIVO',
    DateTime? borrado,
  }) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: ventaId,
          monto: monto,
          medio: medio,
          fecha: fecha ?? DateTime.utc(2026, 10, 20, 16),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrado),
        ),
      );

  Future<void> entrega(
    String id,
    String ventaId,
    String productoId, {
    DateTime? cuando,
    DateTime? creada,
    bool pendiente = false,
    DateTime? borrada,
    int cantidad = 1,
  }) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: productoId,
          cantidad: cantidad,
          pendiente: Value(pendiente),
          fechaEntrega: Value(cuando),
          createdAt: creada ?? t0,
          updatedAt: creada ?? t0,
          deletedAt: Value(borrada),
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await sembrarCasa(db);
    await persona('per-1');
    await producto('pro-1', 'Salud y Hogar');
    await producto('pro-2', 'Nuestros Hijos');
    local = CuentaDePersonaLocalDataSourceDrift(db);
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

  Future<void> esperarA(bool Function() condicion, {int segundos = 5}) async {
    final limite = DateTime.now().add(Duration(seconds: segundos));
    while (!condicion() && DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<FichaDePersona?> ficha([String id = 'per-1']) =>
      observar(personaId: id, espacioId: 'esp-1').first;

  group('la cuenta del canvas 32B·01 con la base real', () {
    test('comprado, pagado, saldo y entregas pendientes salen de los números del canvas', () async {
      // Canvas: «Salud y Hogar + Nuestros Hijos» $ 4.500, cobros de $ 600 (efectivo) y el resto hasta
      // $ 3.300 pagado, saldo $ 1.200; falta entregar «Nuestros Hijos × 1».
      await venta('ven-1');
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-1', 'pro-2');
      await cobro('cob-1', 'ven-1', 60000);
      await cobro('cob-2', 'ven-1', 270000, medio: 'TRANSFERENCIA');
      await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 13, 15));

      final f = (await ficha())!;
      final cuenta = f.resumen!;

      expect(cuenta.compradoCentavos, 450000);
      expect(cuenta.pagadoCentavos, 330000);
      expect(cuenta.saldoCentavos, 120000);
      expect(cuenta.tieneSaldo, isTrue);
      // «Entregado 1 de 2»: dos libros vendidos, uno entregado (decisión del 30/10: se cuentan unidades).
      expect(cuenta.entregasHechas, 1);
      expect(cuenta.entregasTotales, 2);
      expect(cuenta.entregasPendientes, 1, reason: 'falta «Nuestros Hijos»');
      final cobros = f.historial.whereType<CobroEnFicha>().toList();
      expect(cobros.map((c) => c.efectivo), [false, true]);
      expect(
        FormatoFicha.titulo(cobros.firstWhere((c) => c.id == 'cob-1')),
        '\$ 600 en efectivo',
        reason: 'canvas: «\$ 600 en efectivo»',
      );
      expect(
        FormatoFicha.titulo(cobros.firstWhere((c) => c.id == 'cob-2')),
        '\$ 2.700',
        reason: 'un cobro que no es en efectivo no dice «en efectivo»',
      );
      expect(FormatoFicha.subtitulo(cobros.first), 'Venta 0042');
    });

    test('la hoja de la baja con saldo dice lo que dice el canvas 32D·02', () async {
      await venta('ven-1');
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-1', 'pro-2');
      await cobro('cob-1', 'ven-1', 330000);
      await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 13, 15));

      final r = await ConsultarCuentaDePersonaUseCase(CuentasDePersonasDrift(local))('per-1');
      final cuenta = r.getOrElse(() => null)!;

      expect(
        TextosBajaPersona.resumenDeSaldo('María', cuenta),
        'María te debe \$ 1.200 y tiene 1 entrega pendiente.',
      );
      expect(
        TextosBajaPersona.deudaSigue('María', cuenta.saldoCentavos),
        'La deuda de \$ 1.200 sigue en tu cuenta aunque María esté de baja.',
      );
    });

    test('sin ventas la persona no tiene cuenta: la baja no pide segunda confirmación', () async {
      final r = await ConsultarCuentaDePersonaUseCase(CuentasDePersonasDrift(local))('per-1');
      expect(r.getOrElse(() => throw StateError('falló')), isNull);
    });

    test('«Con saldo» muestra solo la venta que todavía debe', () async {
      await venta('ven-1', monto: 100000, talonario: '0001');
      await venta('ven-2', monto: 50000, talonario: '0002');
      await cobro('cob-1', 'ven-1', 100000);
      await cobro('cob-2', 'ven-2', 20000);

      final f = (await ficha())!;
      final filtrado = FiltroDeHistorialDeFicha.aplicar(
        f.historial,
        FiltroDeHistorial.conSaldo,
        resumen: f.resumen,
      );

      expect(filtrado.map((m) => m.id), ['ven-2']);
    });

    test('QA #403: «Con saldo» no confunde dos ventas con el mismo talonario (de otro año)', () async {
      // El talonario es único «por colportor y año»: la misma persona puede tener la 0042 de 2025 y
      // la 0042 de 2026. La tarjeta dice «Saldo \$ 500» pero el filtro cruza los cobros por talonario.
      await venta('ven-a', monto: 100000, talonario: '0042', fecha: DateTime.utc(2025, 3, 1));
      await venta('ven-b', monto: 50000, talonario: '0042', fecha: DateTime.utc(2026, 3, 1));
      await cobro('cob-a', 'ven-a', 100000);

      final f = (await ficha())!;
      expect(f.resumen!.saldoCentavos, 50000);
      final filtrado = FiltroDeHistorialDeFicha.aplicar(
        f.historial,
        FiltroDeHistorial.conSaldo,
        resumen: f.resumen,
      );

      expect(filtrado.map((m) => m.id), ['ven-b']);
    });
  });

  group('datos hostiles', () {
    test('lo dado de baja no cuenta ni se muestra, y lo de otra persona no se mezcla', () async {
      await persona('per-2', nombre: 'Jorge');
      await sembrarVinculo(db, id: 'ep-2', personaId: 'per-2');
      await venta('ven-1', monto: 100000, talonario: '0001');
      await renglon('it-1', 'ven-1', 'pro-1');
      await venta('ven-baja', monto: 999000, talonario: '0002', borrada: t0);
      await renglon('it-2', 'ven-baja', 'pro-1');
      await venta('ven-otro', monto: 777000, talonario: '0003', vinculo: 'ep-2');
      await cobro('cob-ok', 'ven-1', 10000);
      await cobro('cob-baja', 'ven-1', 20000, borrado: t0);
      await cobro('cob-venta-baja', 'ven-baja', 30000);
      await cobro('cob-otro', 'ven-otro', 40000);
      await entrega('ent-ok', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 13));
      await entrega('ent-baja', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 14), borrada: t0);
      await entrega('ent-venta-baja', 'ven-baja', 'pro-1', cuando: DateTime.utc(2026, 10, 15));
      await entrega('ent-otro', 'ven-otro', 'pro-1', cuando: DateTime.utc(2026, 10, 16));

      final mov = await local.movimientos('per-1');
      final cuenta = (await local.resumenDe('per-1'))!;

      expect(mov.map((m) => m.id).toSet(), {'cob-ok', 'ent-ok'});
      expect(cuenta.compradoCentavos, 100000);
      expect(cuenta.pagadoCentavos, 10000);
      expect(cuenta.saldoCentavos, 90000);
    });

    test(
      'la persona de un depto dado de baja y con un vínculo viejo suma todos sus vínculos',
      () async {
        await sembrarEspacio(db, id: 'esp-2', numeroDepto: '5C');
        await sembrarVinculo(db, id: 'ep-viejo', espacioId: 'esp-2', borrado: t0);
        await venta('ven-1', monto: 100000, talonario: '0001');
        await venta('ven-2', monto: 200000, talonario: '0002', vinculo: 'ep-viejo');
        await cobro('cob-1', 'ven-2', 50000);

        final cuenta = (await local.resumenDe('per-1'))!;
        final mov = await local.movimientos('per-1');

        expect(cuenta.compradoCentavos, 300000);
        expect(cuenta.saldoCentavos, 250000);
        expect(mov.map((m) => m.id), ['cob-1']);
      },
    );

    test('una venta cobrada de más no resta de lo que debe otra', () async {
      await venta('ven-1', monto: 100000, talonario: '0001');
      await venta('ven-2', monto: 80000, talonario: '0002');
      await cobro('cob-1', 'ven-1', 150000);

      final cuenta = (await local.resumenDe('per-1'))!;

      expect(cuenta.pagadoCentavos, 150000);
      expect(cuenta.saldoCentavos, 80000, reason: 'nunca negativo ni compensado entre ventas');
    });

    test('una venta sin renglones no cuenta como entrega y no rompe nada', () async {
      await venta('ven-1', monto: 100000);

      final cuenta = (await local.resumenDe('per-1'))!;

      expect(cuenta.entregasTotales, 0);
      expect(cuenta.entregasHechas, 0);
      expect(cuenta.entregasPendientes, 0);
      expect(cuenta.saldoCentavos, 100000);
    });

    test('un id con comillas y SQL no rompe la consulta ni trae lo de otros', () async {
      await venta('ven-1');

      const hostil = "x' OR '1'='1";
      expect(await local.resumenDe(hostil), isNull);
      expect(await local.movimientos(hostil), isEmpty);
      expect(await local.resumenDe(''), isNull);
    });

    test(
      'entregas: fecha vacía usa la de creación, producto ajeno es «Producto» y emoji se conserva',
      () async {
        await producto('pro-3', 'Bíblia ✝️ «Edición» "especial"');
        await venta('ven-1');
        await entrega('ent-1', 'ven-1', 'pro-1', creada: DateTime.utc(2026, 10, 14, 9));
        await entrega('ent-2', 'ven-1', 'pro-fantasma', cuando: DateTime.utc(2026, 10, 15, 9));
        await entrega(
          'ent-3',
          'ven-1',
          'pro-3',
          cuando: DateTime.utc(2026, 10, 16, 9),
          cantidad: 3,
        );

        final mov = (await local.movimientos('per-1')).cast<EntregaEnFicha>();
        final porId = {for (final m in mov) m.id: m};

        expect(porId['ent-1']!.fecha, DateTime.utc(2026, 10, 14, 9));
        expect(porId['ent-2']!.lineas.single.nombre, 'Producto');
        expect(porId['ent-3']!.lineas.single.nombre, 'Bíblia ✝️ «Edición» "especial"');
        expect(FormatoFicha.titulo(porId['ent-3']!), 'Bíblia ✝️ «Edición» "especial" × 3');
      },
    );

    test(
      'una entrega en dos momentos son dos tarjetas; dos ventas en el mismo instante, también',
      () async {
        final mismoInstante = DateTime.utc(2026, 10, 13, 15);
        await venta('ven-1', talonario: '0001');
        await venta('ven-2', talonario: '0002');
        await entrega('e1a', 'ven-1', 'pro-1', cuando: mismoInstante);
        await entrega('e1b', 'ven-1', 'pro-2', cuando: mismoInstante);
        await entrega('e1c', 'ven-1', 'pro-2', cuando: DateTime.utc(2026, 10, 14, 15));
        await entrega('e2a', 'ven-2', 'pro-1', cuando: mismoInstante);

        final mov = (await local.movimientos('per-1')).cast<EntregaEnFicha>();

        expect(mov, hasLength(3));
        final conDos = mov.firstWhere((m) => m.lineas.length == 2);
        expect(conDos.lineas.map((l) => l.nombre), ['Salud y Hogar', 'Nuestros Hijos']);
      },
    );

    test('el orden con la misma fecha es estable entre lecturas', () async {
      final mismo = DateTime.utc(2026, 10, 20, 16);
      await venta('ven-1');
      await cobro('cob-b', 'ven-1', 100, fecha: mismo);
      await cobro('cob-a', 'ven-1', 100, fecha: mismo);
      await cobro('cob-c', 'ven-1', 100, fecha: mismo);
      await entrega('ent-1', 'ven-1', 'pro-1', cuando: mismo);

      final primera = (await local.movimientos('per-1')).map((m) => m.id).toList();
      final segunda = (await local.movimientos('per-1')).map((m) => m.id).toList();

      expect(primera, segunda);
      expect(primera, hasLength(4));
    });

    test('el centavo suelto y los importes grandes se leen sin perder nada', () async {
      await venta('ven-1', monto: 99999999999, talonario: 'AB-0042/2026 ñ');
      await cobro('cob-1', 'ven-1', 1);

      final cuenta = (await local.resumenDe('per-1'))!;
      final cobros = (await local.movimientos('per-1')).cast<CobroEnFicha>();

      expect(cuenta.compradoCentavos, 99999999999);
      expect(cuenta.saldoCentavos, 99999999998);
      expect(cobros.single.numeroTalonario, 'AB-0042/2026 ñ');
    });

    test('con 50 ventas de la misma persona la ficha sigue cargando en menos de 500 ms', () async {
      await db.batch((b) {
        b.insertAll(db.ventas, [
          for (var i = 0; i < 50; i++)
            VentasCompanion.insert(
              id: 'v-$i',
              espacioPersonaId: 'ep-1',
              numeroTalonario: 'T$i',
              montoTotal: 100000,
              fecha: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
              colportorId: 'col-1',
              createdAt: t0,
              updatedAt: t0,
            ),
        ]);
        b.insertAll(db.ventaItems, [
          for (var i = 0; i < 50; i++)
            for (var j = 0; j < 3; j++)
              VentaItemsCompanion.insert(
                id: 'i-$i-$j',
                ventaId: 'v-$i',
                productoId: Value(j.isEven ? 'pro-1' : 'pro-2'),
                cantidad: 1,
                precioUnitario: 1000,
                subtotal: 1000,
                createdAt: t0,
                updatedAt: t0,
              ),
        ]);
        b.insertAll(db.cobranzas, [
          for (var i = 0; i < 50; i++)
            CobranzasCompanion.insert(
              id: 'c-$i',
              ventaId: 'v-$i',
              monto: 5000,
              medio: 'EFECTIVO',
              fecha: DateTime.utc(2026, 2, 1).add(Duration(days: i)),
              createdAt: t0,
              updatedAt: t0,
            ),
        ]);
      });

      final reloj = Stopwatch()..start();
      final f = (await ficha())!;
      reloj.stop();

      expect(f.historial.length, greaterThanOrEqualTo(100));
      expect(f.resumen!.saldoCentavos, 50 * 95000);
      expect(reloj.elapsedMilliseconds, lessThan(500));
    });
  });

  group('la ficha abierta mientras la base cambia', () {
    test('una venta dada de baja con la ficha abierta saca la cuenta y sus cobros', () async {
      await venta('ven-1');
      await renglon('it-1', 'ven-1', 'pro-1');
      await cobro('cob-1', 'ven-1', 100000);
      final fichas = <FichaDePersona?>[];
      final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen(fichas.add);
      await esperarA(() => fichas.isNotEmpty);
      expect(fichas.last!.resumen, isNotNull);

      await (db.update(db.ventas)..where((v) => v.id.equals('ven-1'))).write(
        VentasCompanion(deletedAt: Value(DateTime.utc(2026, 10, 25))),
      );
      await esperarA(() => fichas.last?.resumen == null);

      expect(fichas.last!.resumen, isNull, reason: 'pasa a «Sin movimientos aún»');
      expect(fichas.last!.historial, isEmpty);
      await sub.cancel();
    });

    test(
      'anular (dar de baja) un cobro con la ficha abierta sube el saldo y lo saca del historial',
      () async {
        await venta('ven-1', monto: 100000);
        await cobro('cob-1', 'ven-1', 100000);
        final fichas = <FichaDePersona?>[];
        final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen(fichas.add);
        await esperarA(() => fichas.isNotEmpty && fichas.last?.resumen?.saldoCentavos == 0);
        expect(fichas.last!.resumen!.saldoCentavos, 0);

        await (db.update(db.cobranzas)..where((c) => c.id.equals('cob-1'))).write(
          CobranzasCompanion(deletedAt: Value(DateTime.utc(2026, 10, 25))),
        );
        await esperarA(() => fichas.last?.resumen?.saldoCentavos == 100000);

        expect(fichas.last!.resumen!.saldoCentavos, 100000);
        expect(fichas.last!.historial.map((m) => m.id), isNot(contains('cob-1')));
        await sub.cancel();
      },
    );

    test('un renglón que llega después de la venta actualiza «Entregado» sin reabrir', () async {
      await venta('ven-1');
      final fichas = <FichaDePersona?>[];
      final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen(fichas.add);
      await esperarA(() => fichas.isNotEmpty);
      expect(fichas.last!.resumen!.entregasTotales, 0);

      await renglon('it-1', 'ven-1', 'pro-1');
      await esperarA(() => fichas.last?.resumen?.entregasTotales == 1);
      expect(fichas.last!.resumen!.entregasTotales, 1);
      expect(fichas.last!.resumen!.entregasHechas, 0);

      await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 21));
      await esperarA(() => fichas.last?.resumen?.entregasHechas == 1);
      expect(fichas.last!.resumen!.entregasHechas, 1);
      await sub.cancel();
    });

    test('corregir el monto de la venta actualiza comprado y saldo', () async {
      await venta('ven-1', monto: 100000);
      final fichas = <FichaDePersona?>[];
      final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen(fichas.add);
      await esperarA(() => fichas.isNotEmpty);

      await (db.update(
        db.ventas,
      )..where((v) => v.id.equals('ven-1'))).write(const VentasCompanion(montoTotal: Value(80000)));
      await esperarA(() => fichas.last?.resumen?.compradoCentavos == 80000);

      expect(fichas.last!.resumen!.compradoCentavos, 80000);
      expect(fichas.last!.resumen!.saldoCentavos, 80000);
      await sub.cancel();
    });

    test(
      'una ráfaga de 25 cobros termina en la ficha correcta, sin errores ni duplicados',
      () async {
        await venta('ven-1', monto: 1000000);
        final fichas = <FichaDePersona?>[];
        final errores = <Object>[];
        final sub = observar(
          personaId: 'per-1',
          espacioId: 'esp-1',
        ).listen(fichas.add, onError: errores.add);
        await esperarA(() => fichas.isNotEmpty);

        await Future.wait([
          for (var i = 0; i < 25; i++)
            cobro(
              'cob-${i.toString().padLeft(2, '0')}',
              'ven-1',
              1000,
              fecha: DateTime.utc(2026, 10, 1).add(Duration(hours: i)),
            ),
        ]);
        await esperarA(() => fichas.last?.resumen?.pagadoCentavos == 25000);

        expect(errores, isEmpty);
        expect(fichas.last!.resumen!.pagadoCentavos, 25000);
        final ids = fichas.last!.historial.whereType<CobroEnFicha>().map((m) => m.id).toList();
        expect(ids.toSet(), hasLength(25));
        await sub.cancel();
      },
    );

    test('cancelar la suscripción en pleno cambio no deja errores sueltos', () async {
      await venta('ven-1');
      final errores = <Object>[];
      await runZonedGuarded(() async {
        final sub = observar(personaId: 'per-1', espacioId: 'esp-1').listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 30));
        unawaited(cobro('cob-1', 'ven-1', 100));
        await sub.cancel();
        await cobro('cob-2', 'ven-1', 100);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }, (e, _) => errores.add(e));

      expect(errores, isEmpty);
    });
  });

  group('cuando la lectura falla a mitad', () {
    test(
      'si la tabla de cobros no se puede leer, sale un error y no una ficha sin cobros',
      () async {
        await venta('ven-1');
        await cobro('cob-1', 'ven-1', 100);
        await db.customStatement('ALTER TABLE cobranza RENAME TO cobranza_x');
        final fichas = <FichaDePersona?>[];
        final errores = <Object>[];
        final sub = observar(
          personaId: 'per-1',
          espacioId: 'esp-1',
        ).listen(fichas.add, onError: errores.add);
        await esperarA(() => errores.isNotEmpty);

        expect(errores, isNotEmpty, reason: 'la ficha dice «No pudimos leer…» y ofrece Reintentar');
        expect(
          fichas.where((f) => f != null && f.historial.whereType<CobroEnFicha>().isEmpty),
          isEmpty,
          reason: 'nunca una ficha «completa» sin sus cobros',
        );
        await sub.cancel();
      },
    );

    test('al volver la tabla, una lectura nueva (Reintentar) trae la ficha completa', () async {
      await venta('ven-1');
      await cobro('cob-1', 'ven-1', 100);
      await db.customStatement('ALTER TABLE cobranza RENAME TO cobranza_x');
      final errores = <Object>[];
      final s1 = observar(
        personaId: 'per-1',
        espacioId: 'esp-1',
      ).listen((_) {}, onError: errores.add);
      await esperarA(() => errores.isNotEmpty);
      await s1.cancel();
      await db.customStatement('ALTER TABLE cobranza_x RENAME TO cobranza');

      final f = (await ficha())!;

      expect(f.historial.whereType<CobroEnFicha>(), hasLength(1));
      expect(f.resumen!.pagadoCentavos, 100);
    });

    test('la cuenta de la baja no da por hecho que no debe nada si la base no responde', () async {
      await venta('ven-1');
      await db.customStatement('ALTER TABLE cobranza RENAME TO cobranza_x');

      final r = await ConsultarCuentaDePersonaUseCase(CuentasDePersonasDrift(local))('per-1');

      expect(r.isLeft(), isTrue, reason: 'un error de lectura no es «sin deuda»');
    });
  });

  group('privacidad', () {
    test(
      'las entidades de la cuenta y los movimientos no llevan el nombre ni el teléfono',
      () async {
        await db.customStatement("UPDATE persona SET telefono = '099123456', apellido = 'Pérez'");
        await venta('ven-1');
        await renglon('it-1', 'ven-1', 'pro-1');
        await cobro('cob-1', 'ven-1', 100);
        await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 21));

        final cuenta = (await local.resumenDe('per-1'))!;
        final mov = await local.movimientos('per-1');
        final texto = [cuenta.toString(), ...mov.map((m) => m.toString())].join(' ');

        for (final dato in ['María', 'Pérez', '099123456', '099']) {
          expect(texto, isNot(contains(dato)));
        }
      },
    );

    test('el adaptador de la cuenta no escribe en ningún log', () {
      final fuente = File(
        'lib/features/mapa/data/datasources/cuenta_de_persona_local_data_source_drift.dart',
      ).readAsStringSync();
      final adaptador = File(
        'lib/features/mapa/data/services/cuenta_de_persona_drift.dart',
      ).readAsStringSync();

      for (final codigo in [fuente, adaptador]) {
        expect(codigo, isNot(contains('print(')));
        expect(codigo, isNot(contains('debugPrint')));
        expect(codigo, isNot(contains('logger')));
        expect(codigo, isNot(contains('Logger')));
      }
    });
  });
}
