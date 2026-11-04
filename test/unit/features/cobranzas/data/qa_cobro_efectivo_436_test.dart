// QA de HU-COB-001 (#436, PR #564), parte de datos y sync, sin vista: el caso de uso, el repositorio
// y la base real (AppDatabase en memoria, mismo esquema y CHECK que en el dispositivo) con el
// servicio real de `house_status`. Pregunta: ¿una colportora que cobra sin conexión termina con el
// saldo, la cola y la casa que la HU promete, y con un aviso que la guía cuando algo sale mal?
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/repositories/cobranza_repository_impl.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/registrar_cobro_use_case.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/services/house_status_updater.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

/// Un servicio de `house_status` que se cae: el recálculo falla a mitad de la escritura.
final class _EstadoDeLasCasasRoto implements HouseStatusUpdater {
  @override
  Future<HouseStatus?> recalcular(
    String ubicacionId, {
    required DateTime ahora,
    required String colportorId,
  }) async => throw StateError('SECRETO recalculo');
}

T _derecha<T>(Either<Failure, T> e) =>
    e.fold((f) => fail('se esperaba un éxito y vino $f'), (v) => v);

Failure _izquierda<T>(Either<Failure, T> e) =>
    e.fold((f) => f, (v) => fail('se esperaba una falla y vino $v'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // «Ahora» del teléfono: unas horas después de las ventas sembradas (t0 = 23/10 13:45 UTC).
  var ahora = t0.add(const Duration(hours: 2));

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;
  late CobranzaRepositoryImpl repo;
  late RegistrarCobroUseCase caso;
  late MemoryOutput salidaDeLogs;

  String logs() => salidaDeLogs.buffer.expand((e) => e.lines).join('\n');

  void armar({HouseStatusUpdater? casas, EncoladorSyncEnMemoria? cola}) {
    encolador = cola ?? EncoladorSyncEnMemoria();
    local = CobranzaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas ?? HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    salidaDeLogs = MemoryOutput();
    repo = CobranzaRepositoryImpl(
      local,
      logger: AppLogger(
        logger: Logger(level: Level.all, printer: SimplePrinter(), output: salidaDeLogs),
      ),
    );
    caso = RegistrarCobroUseCase(repo, ahora: () => ahora);
  }

  Future<void> sembrarVenta({
    String id = 'v-1',
    int monto = 150000,
    DateTime? fecha,
    String vinculo = 'ep-1',
    List<ComponenteVendido>? componentes,
    String? coleccion,
  }) async {
    final ventas = VentaLocalDataSourceDrift(
      db,
      encolador: EncoladorSyncEnMemoria(),
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: EncoladorSyncEnMemoria()),
    );
    await ventas
        .registrar(ventaDe(id, monto: monto, talonario: 'T-$id', fecha: fecha, vinculo: vinculo), [
          itemDe(
            'i-$id',
            id,
            cantidad: 1,
            precio: monto,
            coleccionId: coleccion,
            productoId: coleccion == null ? 'prod-1' : null,
            componentes: componentes,
          ),
        ]);
  }

  RegistrarCobroParams params({
    String id = 'c-1',
    String venta = 'v-1',
    int monto = 50000,
    DateTime? fecha,
  }) => RegistrarCobroParams(
    cobroId: id,
    ventaId: venta,
    montoCentavos: monto,
    colportorId: 'col-1',
    fecha: fecha,
  );

  Future<List<CobranzaFila>> cobros() => db.select(db.cobranzas).get();
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<String?> colorDeLaCasa() async =>
      (await db.select(db.houseStatuses).getSingleOrNull())?.color;
  Future<int> saldo([String venta = 'v-1']) async =>
      (_derecha(await repo.ventaConSaldo(venta)))!.saldoCentavos;

  Future<VentaConSaldo> saldoVenta(String id) async => _derecha(await repo.ventaConSaldo(id))!;

  setUp(() async {
    ahora = t0.add(const Duration(hours: 2));
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    armar();
    await sembrarCasa(db);
    await sembrarVenta();
  });
  tearDown(() => db.close());

  group(
    'criterios de aceptación de la HU, con el camino real (caso de uso → repositorio → base)',
    () {
      test('Escenario «Cobro de UYU 500 del total UYU 1500»: dado que tengo una venta con saldo '
          'UYU 1500, cuando registro pago efectivo UYU 500, entonces el saldo pasa a UYU 1000 y se '
          'persiste y encola sync', () async {
        expect(await saldo(), 150000);

        final r = _derecha(await caso(params(monto: 50000)));

        expect(r.venta.saldoCentavos, 100000);
        expect(await saldo(), 100000);
        final fila = (await cobros()).single;
        expect([fila.ventaId, fila.monto, fila.medio], ['v-1', 50000, 'EFECTIVO']);
        expect(cola(), ['cobranza:insert']);
        expect(encolador.encolados.single.payload['monto'], 50000);
      });

      test('Escenario «Cobro que liquida saldo»: dado una venta con saldo UYU 500, cuando registro '
          'pago UYU 500, entonces el saldo es 0 (la casa, por la decisión del 28/10, espera a la '
          'entrega)', () async {
        await sembrarVenta(id: 'v-2', monto: 50000);

        final r = _derecha(await caso(params(venta: 'v-2', monto: 50000)));

        expect(r.venta.saldoCentavos, 0);
        expect(r.ventaPagada, isTrue);
        expect(await saldo('v-2'), 0);
        // La HU dice `sale_complete`; la decisión de Cristian (28/10, «Pendiente hasta entregar») la
        // precisa: pagada y sin entregar sigue en «entrega y cobranza pendientes».
        expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      });

      test('`fecha_pago` por defecto es ahora y el cobro queda con quién lo hizo', () async {
        await caso(params());

        final fila = (await cobros()).single;
        expect(fila.fecha, ahora.toUtc());
        expect(fila.createdBy, 'col-1');
        expect(fila.numeroCuota, isNull);
      });

      test(
        'una fecha pasada se guarda tal cual (la colportora cobró ayer y lo carga hoy)',
        () async {
          final ayer = ahora.subtract(const Duration(days: 1));
          await sembrarVenta(
            id: 'v-0',
            monto: 1000,
            fecha: ahora.subtract(const Duration(days: 3)),
          );

          _derecha(await caso(params(venta: 'v-0', monto: 1000, fecha: ayer)));

          expect((await cobros()).single.fecha, ayer);
        },
      );
    },
  );

  group('validación de lo que se escribe', () {
    test('un monto vacío, cero, negativo o más grande que el entero del servidor no escribe nada '
        'y avisa qué hacer', () async {
      for (final monto in [0, -1, -50000, RegistrarCobroUseCase.maximoCentavos + 1]) {
        final f = _izquierda(await caso(params(monto: monto)));
        expect(f, isA<FailureCobroMontoInvalido>(), reason: 'monto $monto');
        expect(f.mensaje, 'Ingresá el monto que te pagaron.');
      }
      expect(await cobros(), isEmpty);
      expect(cola(), isEmpty);
      expect(await saldo(), 150000);
    });

    test('un monto mayor al saldo se rechaza con el texto del canvas y el saldo para armar el '
        'aviso; igual al saldo entra', () async {
      final f = _izquierda(await caso(params(monto: 150001)));

      expect(f, isA<FailureCobroMayorAlSaldo>());
      expect(f.mensaje, 'El cobro es mayor que el saldo de la venta. Ingresá hasta ese monto.');
      expect((f as FailureCobroMayorAlSaldo).saldoCentavos, 150000);
      expect(await cobros(), isEmpty);

      _derecha(await caso(params(id: 'c-2', monto: 150000)));
      expect(await saldo(), 0);
    });

    test(
      'el centavo mínimo entra, y cobrar de a un centavo hasta el final cierra en cero',
      () async {
        await sembrarVenta(id: 'v-c', monto: 40);
        for (var i = 0; i < 40; i++) {
          _derecha(await caso(params(id: 'c-$i', venta: 'v-c', monto: 1)));
        }

        expect(await saldo('v-c'), 0);
        expect(
          _izquierda(await caso(params(id: 'c-x', venta: 'v-c', monto: 1))),
          isA<FailureCobroMayorAlSaldo>(),
        );
        expect((await cobros()).length, 40);
      },
    );

    test(
      'una venta del máximo del entero se cobra entera y después no admite ni un centavo',
      () async {
        const maximo = RegistrarCobroUseCase.maximoCentavos;
        await sembrarVenta(id: 'v-m', monto: maximo);

        _derecha(await caso(params(id: 'c-1', venta: 'v-m', monto: maximo - 1)));
        expect(await saldo('v-m'), 1);
        _derecha(await caso(params(id: 'c-2', venta: 'v-m', monto: 1)));

        expect(await saldo('v-m'), 0);
        final f = _izquierda(await caso(params(id: 'c-3', venta: 'v-m', monto: 1)));
        expect((f as FailureCobroMayorAlSaldo).saldoCentavos, 0);
      },
    );

    test('los ids con espacios se limpian; vacíos o solo espacios no escriben nada', () async {
      _derecha(await caso(params(id: '  c-1  ', venta: ' v-1 ')));
      expect((await cobros()).single.id, 'c-1');

      for (final mal in [
        params(id: ''),
        params(id: '   '),
        params(venta: ''),
        params(id: 'c-9', venta: '\t'),
      ]) {
        expect(_izquierda(await caso(mal)), isA<FailureCobroNoGuardado>());
      }
      expect((await cobros()).length, 1);
    });

    test('la fecha: hoy a las 23:59 de Montevideo entra; 00:00 de mañana no, aunque falte un '
        'instante (3 h de diferencia con UTC)', () async {
      // 28/10 23:30 en Montevideo = 29/10 02:30 UTC.
      ahora = DateTime.utc(2026, 10, 29, 2, 30);

      _derecha(
        await caso(
          params(id: 'c-1', monto: 100, fecha: DateTime.utc(2026, 10, 29, 2, 59, 59, 999)),
        ),
      );
      final f = _izquierda(
        await caso(params(id: 'c-2', monto: 100, fecha: DateTime.utc(2026, 10, 29, 3))),
      );

      expect(f, isA<FailureCobroFechaInvalida>());
      expect(f.mensaje, 'La fecha no puede ser antes de la venta ni después de hoy.');
      expect((await cobros()).length, 1);
    });

    test('la fecha no puede ser de un día anterior a la venta (día de Montevideo), pero el mismo '
        'día sí aunque sea antes de la hora de la venta', () async {
      // La venta es del 29/10 00:10 en Montevideo = 29/10 03:10 UTC.
      ahora = DateTime.utc(2026, 10, 29, 12);
      await sembrarVenta(id: 'v-n', monto: 10000, fecha: DateTime.utc(2026, 10, 29, 3, 10));

      final ayerALaNoche = await caso(
        params(id: 'c-1', venta: 'v-n', monto: 100, fecha: DateTime.utc(2026, 10, 29, 2, 50)),
      );
      expect(_izquierda(ayerALaNoche), isA<FailureCobroFechaInvalida>());
      _derecha(
        await caso(
          params(id: 'c-2', venta: 'v-n', monto: 100, fecha: DateTime.utc(2026, 10, 29, 3)),
        ),
      );

      expect((await cobros()).single.id, 'c-2');
    });

    test('una fecha rechazada o un monto mayor al saldo no gastan el id: se corrige y se vuelve a '
        'enviar con el mismo', () async {
      expect(_izquierda(await caso(params(monto: 999999999))), isA<FailureCobroMayorAlSaldo>());
      expect(
        _izquierda(await caso(params(fecha: ahora.add(const Duration(days: 2))))),
        isA<FailureCobroFechaInvalida>(),
      );

      final r = _derecha(await caso(params(monto: 100)));

      expect(r.yaEstaba, isFalse);
      expect((await cobros()).single.monto, 100);
    });
  });

  group('falla a mitad de la acción', () {
    test('si el encolado falla no queda nada, el aviso dice que se puede reintentar y el mismo '
        'id entra después', () async {
      encolador.fallarCon = StateError('SECRETO 099123456 calle Mataojo');

      final f = _izquierda(await caso(params()));

      expect(f, isA<FailureCobroNoGuardado>());
      expect(f.mensaje, 'No pudimos guardar el cobro. No se registró nada: probá de nuevo.');
      expect((f as FailureCobroNoGuardado).causa, 'StateError');
      expect(await cobros(), isEmpty);
      expect(await saldo(), 150000);
      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      expect(logs(), isNot(contains('SECRETO')));
      expect(logs(), isNot(contains('Mataojo')));
      expect(logs(), contains('COBRO_ALTA_FAIL'));

      encolador.fallarCon = null;
      final r = _derecha(await caso(params()));
      expect(r.yaEstaba, isFalse);
      expect(await saldo(), 100000);
    });

    test('si el recálculo del color de la casa falla se revierte el cobro entero: ni fila ni saldo '
        'cambiado, y se puede reintentar', () async {
      armar(casas: _EstadoDeLasCasasRoto());

      final f = _izquierda(await caso(params()));

      expect(f, isA<FailureCobroNoGuardado>());
      expect(await cobros(), isEmpty);
      expect(await saldo(), 150000);
      expect(logs(), isNot(contains('SECRETO')));

      armar();
      _derecha(await caso(params()));
      expect(await saldo(), 100000);
    });

    test(
      'si la tabla de cobros no existe ninguna lectura ni escritura lanza: todo vuelve como falla '
      'con causa de tipo y sin el SQL',
      () async {
        await db.customStatement('DROP TABLE cobranza');

        final alta = _izquierda(await caso(params()));
        final venta = _izquierda(await repo.ventaConSaldo('v-1'));
        final lista = _izquierda(await repo.ventasConSaldoDe('per-1'));

        expect([alta, venta, lista], everyElement(isA<FailureCobroNoGuardado>()));
        final causa = (alta as FailureCobroNoGuardado).causa!;
        expect(causa, isNot(contains(' ')));
        expect(causa.toLowerCase(), isNot(contains('select')));
        expect(logs().toLowerCase(), isNot(contains('insert into')));
        expect(logs().toLowerCase(), isNot(contains('select')));
      },
    );

    test(
      'si falla un cobro no arrastra a los otros: el siguiente entra y el saldo es el correcto',
      () async {
        encolador.fallarCon = StateError('x');
        _izquierda(await caso(params(id: 'c-1', monto: 40000)));
        encolador.fallarCon = null;
        _derecha(await caso(params(id: 'c-2', monto: 30000)));

        expect(await saldo(), 120000);
        expect([for (final c in await cobros()) c.id], ['c-2']);
      },
    );
  });

  group('acciones superpuestas y reentrada', () {
    test('un segundo toque con el mismo id, antes o después de terminar el primero, es el mismo '
        'cobro: un solo registro, una sola fila en la cola, y la respuesta lo dice', () async {
      final a = caso(params());
      final b = caso(params());
      final resultados = [_derecha(await a), _derecha(await b)];

      expect(resultados.where((r) => r.yaEstaba).length, 1);
      expect((await cobros()).length, 1);
      expect(cola(), ['cobranza:insert']);
      expect(await saldo(), 100000);

      final tarde = _derecha(await caso(params()));
      expect(tarde.yaEstaba, isTrue);
      expect(tarde.venta.saldoCentavos, 100000);
      expect(cola(), ['cobranza:insert']);
    });

    test('el mismo id con otro monto no pisa lo ya guardado (el primero manda)', () async {
      _derecha(await caso(params(monto: 50000)));

      final r = _derecha(await caso(params(monto: 90000)));

      expect(r.yaEstaba, isTrue);
      expect(r.cobranza.montoCentavos, 50000);
      expect((await cobros()).single.monto, 50000);
    });

    test('seis cobros distintos de UYU 300 a la vez sobre una venta de UYU 1500: entran cinco, el '
        'sexto se rechaza con saldo 0 y la suma nunca pasa de la venta', () async {
      final r = await Future.wait([
        for (var i = 0; i < 6; i++) caso(params(id: 'c-$i', monto: 30000)),
      ]);

      expect(r.where((e) => e.isRight()).length, 5);
      final f = r.firstWhere((e) => e.isLeft());
      expect(_izquierda(f), isA<FailureCobroMayorAlSaldo>());
      expect((_izquierda(f) as FailureCobroMayorAlSaldo).saldoCentavos, 0);
      expect(await saldo(), 0);
      expect((await cobros()).fold<int>(0, (a, c) => a + c.monto), 150000);
      expect(cola().length, 5);
    });

    test('cobros a la vez sobre ventas distintas no se mezclan', () async {
      await sembrarVenta(id: 'v-2', monto: 24000);

      await Future.wait([
        caso(params(id: 'c-1', venta: 'v-1', monto: 10000)),
        caso(params(id: 'c-2', venta: 'v-2', monto: 24000)),
        caso(params(id: 'c-3', venta: 'v-1', monto: 10000)),
      ]);

      expect(await saldo('v-1'), 130000);
      expect(await saldo('v-2'), 0);
    });

    test(
      'cobrar una venta ya pagada con un id nuevo se rechaza con saldo 0 (no hay saldo a favor)',
      () async {
        _derecha(await caso(params(id: 'c-1', monto: 150000)));

        final f = _izquierda(await caso(params(id: 'c-2', monto: 100)));

        expect(f, isA<FailureCobroMayorAlSaldo>());
        expect((f as FailureCobroMayorAlSaldo).saldoCentavos, 0);
        expect((await cobros()).length, 1);
      },
    );

    test(
      'una venta que se dio de baja mientras tanto no se cobra: aviso que manda a elegir otra',
      () async {
        await db.customStatement('UPDATE venta SET deleted_at = 1 WHERE id = ?', ['v-1']);

        final f = _izquierda(await caso(params()));

        expect(f, isA<FailureCobroSinVenta>());
        expect(f.mensaje, contains('Volvé atrás y elegí otra'));
        expect(await cobros(), isEmpty);
      },
    );

    test('un cobro dado de baja devuelve el saldo; el siguiente puede volver a cobrarlo', () async {
      _derecha(await caso(params(id: 'c-1', monto: 150000)));
      await db.customStatement('UPDATE cobranza SET deleted_at = 1 WHERE id = ?', ['c-1']);

      expect(await saldo(), 150000);
      _derecha(await caso(params(id: 'c-2', monto: 150000)));
      expect(await saldo(), 0);
    });
  });

  group('la casa', () {
    test(
      'un cobro en una casa con varias ventas no cambia el color y no encola la casa de más',
      () async {
        await caso(params(id: 'c-0', monto: 100)); // primera vez: crea la fila de house_status
        await sembrarVenta(id: 'v-2', monto: 24000);
        encolador.encolados.clear();

        _derecha(await caso(params(id: 'c-1', venta: 'v-2', monto: 24000)));

        expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
        expect(cola(), ['cobranza:insert']);
      },
    );

    test(
      'si la ubicación de la casa se dio de baja el cobro se guarda igual (no se pierde un cobro '
      'por una fila que falta)',
      () async {
        await db.customStatement('UPDATE ubicacion SET deleted_at = 1 WHERE id = ?', ['ub-1']);

        _derecha(await caso(params()));

        expect(await saldo(), 100000);
        expect(cola(), ['cobranza:insert']);
      },
    );

    test('una venta cuyo espacio ya no está tampoco impide cobrar', () async {
      await db.customStatement('DELETE FROM espacio WHERE id = ?', ['esp-1']);

      _derecha(await caso(params()));

      expect(await saldo(), 100000);
    });
  });

  group('lecturas que usan las pantallas', () {
    test('una venta que no existe o está de baja es «no hay», no un error', () async {
      expect(_derecha(await repo.ventaConSaldo('v-9')), isNull);
      await db.customStatement('UPDATE venta SET deleted_at = 1 WHERE id = ?', ['v-1']);
      expect(_derecha(await repo.ventaConSaldo('v-1')), isNull);
    });

    test('una persona sin ventas, o sin nada que deba, da lista vacía', () async {
      expect(_derecha(await repo.ventasConSaldoDe('per-9')), isEmpty);
      _derecha(await caso(params(monto: 150000)));
      expect(_derecha(await repo.ventasConSaldoDe('per-1')), isEmpty);
    });

    test('un vínculo dado de baja no muestra sus ventas', () async {
      await db.customStatement('UPDATE espacio_persona SET deleted_at = 1 WHERE id = ?', ['ep-1']);

      expect(_derecha(await repo.ventasConSaldoDe('per-1')), isEmpty);
    });

    test(
      'la descripción de lo vendido: colección de 1 libro, de varios, productos sueltos',
      () async {
        await sembrarVenta(
          id: 'v-a',
          monto: 1000,
          coleccion: 'col-1',
          componentes: const [ComponenteVendido(productoId: 'p-1')],
        );
        await sembrarVenta(
          id: 'v-b',
          monto: 1000,
          coleccion: 'col-1',
          componentes: const [
            ComponenteVendido(productoId: 'p-1', cantidad: 2),
            ComponenteVendido(productoId: 'p-2', cantidad: 3),
          ],
        );

        expect((await saldoVenta('v-a')).descripcion, 'Colección de 1 libro');
        expect((await saldoVenta('v-b')).descripcion, 'Colección de 5 libros');
        expect((await saldoVenta('v-1')).descripcion, '1 producto');
      },
    );

    test(
      'muchas ventas: 300 ventas con saldo salen todas, la más vieja primero y sin repetir',
      () async {
        for (var i = 0; i < 300; i++) {
          await sembrarVenta(
            id: 'm-${i.toString().padLeft(3, '0')}',
            monto: 1000 + i,
            fecha: t0.add(Duration(minutes: 300 - i)),
          );
        }

        final ventas = _derecha(await repo.ventasConSaldoDe('per-1'));

        expect(ventas.length, 301);
        expect(ventas.first.ventaId, 'v-1');
        expect(ventas[1].ventaId, 'm-299');
        expect(ventas.last.ventaId, 'm-000');
        expect({for (final v in ventas) v.ventaId}.length, 301);
      },
    );

    test(
      'el saldo de las personas (la línea «Saldo» de «¿Con quién?») suma ventas y resta cobros',
      () async {
        await sembrarVenta(id: 'v-2', monto: 24000);
        await caso(params(monto: 50000));
        final saldos = SaldosDePersonasLocal(local);

        expect(await saldos.saldosPendientes(['per-1', 'per-9']), {'per-1': 124000});
        expect(await saldos.saldosPendientes(const []), isEmpty);
      },
    );

    test('VentaConSaldo nunca da un saldo negativo, aunque los cobros se pasen', () {
      final v = VentaConSaldo(
        ventaId: 'v',
        numeroTalonario: '1',
        fecha: t0,
        montoTotalCentavos: 100,
        cobradoCentavos: 250,
      );

      expect(v.saldoCentavos, 0);
      expect(v.tieneSaldo, isFalse);
    });
  });

  group('lo que sube y lo que se loguea (privacidad, ADR-004, R-CB03)', () {
    test('la fila encolada son exactamente las columnas del servidor y ningún valor nombra a la '
        'persona, el talonario ni lo vendido', () async {
      await caso(params());

      final payload = encolador.encolados.single.payload;
      expect(payload.keys.toSet(), {
        'id',
        'venta_id',
        'monto',
        'medio',
        'fecha',
        'numero_cuota',
        'tarjeta_tipo',
        'tarjeta_marca',
        'numero_aprobacion',
        'referencia_transferencia',
        'banco_origen',
        'ticket_id',
        'created_at',
        'updated_at',
        'created_by',
        'deleted_at',
        'sync_version',
      });
      final texto = jsonEncode(payload);
      for (final ajeno in ['per-1', 'ep-1', 'esp-1', 'T-v-1', 'producto']) {
        expect(texto, isNot(contains(ajeno)), reason: ajeno);
      }
      // Lo que el servidor valida: entero > 0, medio del catálogo, fecha ISO con zona, cuota nula.
      expect(payload['monto'], isA<int>());
      expect(payload['medio'], 'EFECTIVO');
      expect(DateTime.parse(payload['fecha']! as String).isUtc, isTrue);
      expect(payload['numero_cuota'], isNull);
    });

    test('los rechazos y las fallas loguean ids y códigos, nunca el monto, el saldo ni el texto de '
        'la excepción', () async {
      await caso(params(monto: 777777777)); // mayor al saldo
      await db.customStatement('UPDATE venta SET deleted_at = 1 WHERE id = ?', ['v-1']);
      await caso(params(id: 'c-2'));
      await sembrarVenta(id: 'v-2', monto: 24000, fecha: ahora.subtract(const Duration(days: 1)));
      await caso(params(id: 'c-3', venta: 'v-2', fecha: ahora.subtract(const Duration(days: 9))));
      encolador.fallarCon = StateError('SECRETO');
      await caso(params(id: 'c-4', venta: 'v-2', monto: 100));

      final salida = logs();
      expect(salida, contains('COBRO_ALTA_RECHAZADO'));
      for (final prohibido in ['777777777', '150000', '24000', 'SECRETO', 'per-1', 'T-v']) {
        expect(salida, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('los avisos y el resultado del cobro no llevan datos de la persona en su texto', () async {
      await sembrarVenta(id: 'v-2', monto: 24000);
      final r = _derecha(await caso(params(venta: 'v-2', monto: 100)));
      final f = _izquierda(await caso(params(id: 'c-2', monto: 999999999)));

      for (final texto in ['${r.cobranza.id}${r.cobranza.ventaId}', f.mensaje, f.toString()]) {
        expect(texto, isNot(contains('per-1')));
      }
    });
  });

  group('sync', () {
    test('`cobranza` sube como escritura crítica, después de la venta y de sus ítems', () {
      final entidades = [for (final s in specsDeLaApp) s.entity];

      expect(entidades, containsAllInOrder(['venta', 'venta_item', 'cobranza']));
      final spec = specsDeLaApp.firstWhere((s) => s.entity == 'cobranza');
      expect(spec.critical, isTrue);
      expect(spec.alsoPull, isFalse);
      expect(spec.pullable, isFalse);
      expect(spec.pk, 'id');
    });
  });
}
