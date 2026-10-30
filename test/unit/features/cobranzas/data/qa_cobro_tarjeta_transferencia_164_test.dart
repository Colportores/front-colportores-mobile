// QA de HU-COB-002 y HU-COB-003 (#164, PR #572), parte de datos y sync: el caso de uso, el repositorio
// y la base real (AppDatabase en memoria) con el servicio real de `house_status`. Pregunta: ¿lo que la
// colportora carga de la tarjeta o de la transferencia llega a la fila, a la cola del sync y a nada
// más (ni al log ni a `toString`), y un medio nunca arrastra los datos de otro?
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/repositories/cobranza_repository_impl.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/registrar_cobro_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

T _derecha<T>(Either<Failure, T> e) =>
    e.fold((f) => fail('se esperaba un éxito y vino $f'), (v) => v);

Failure _izquierda<T>(Either<Failure, T> e) =>
    e.fold((f) => f, (v) => fail('se esperaba una falla y vino $v'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final ahora = t0.add(const Duration(hours: 2));

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaRepositoryImpl repo;
  late RegistrarCobroUseCase caso;
  late MemoryOutput salidaDeLogs;

  String logs() => salidaDeLogs.buffer.expand((e) => e.lines).join('\n');

  RegistrarCobroParams params({
    String id = 'c-1',
    int monto = 50000,
    MedioCobranza medio = MedioCobranza.efectivo,
    TipoTarjeta? tipo,
    String? marca,
    String? aprobacion,
    String? referencia,
    String? banco,
  }) => RegistrarCobroParams(
    cobroId: id,
    ventaId: 'v-1',
    montoCentavos: monto,
    colportorId: 'col-1',
    medio: medio,
    tarjetaTipo: tipo,
    tarjetaMarca: marca,
    numeroAprobacion: aprobacion,
    referenciaTransferencia: referencia,
    bancoOrigen: banco,
  );

  Future<List<CobranzaFila>> cobros() => db.select(db.cobranzas).get();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final local = CobranzaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    salidaDeLogs = MemoryOutput();
    repo = CobranzaRepositoryImpl(
      local,
      logger: AppLogger(
        logger: Logger(level: Level.all, printer: SimplePrinter(), output: salidaDeLogs),
      ),
    );
    caso = RegistrarCobroUseCase(repo, ahora: () => ahora);
    await sembrarCasa(db);
    final ventas = VentaLocalDataSourceDrift(
      db,
      encolador: EncoladorSyncEnMemoria(),
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: EncoladorSyncEnMemoria()),
    );
    await ventas.registrar(ventaDe('v-1', monto: 150000, talonario: 'T-v-1', vinculo: 'ep-1'), [
      itemDe('i-v-1', 'v-1', cantidad: 1, precio: 150000, productoId: 'prod-1'),
    ]);
  });
  tearDown(() => db.close());

  group('el camino real: caso de uso → repositorio → base → cola', () {
    test(
      'Escenario «Cobro con tarjeta V1»: UYU 800, sin aprobación, se persiste con null y sube',
      () async {
        final r = _derecha(await caso(params(monto: 80000, medio: MedioCobranza.tarjeta)));

        expect(r.venta.saldoCentavos, 70000);
        final f = (await cobros()).single;
        expect(
          [f.medio, f.monto, f.numeroAprobacion, f.tarjetaMarca],
          ['TARJETA', 80000, null, null],
        );
        expect(encolador.encolados.single.payload['numero_aprobacion'], isNull);
        expect(encolador.encolados.single.payload['medio'], 'TARJETA');
      },
    );

    test(
      'tarjeta con todo: crédito, Visa y aprobación llegan a la fila y al payload del sync',
      () async {
        _derecha(
          await caso(
            params(
              medio: MedioCobranza.tarjeta,
              tipo: TipoTarjeta.credito,
              marca: '  Visa ',
              aprobacion: ' 004 471 ',
            ),
          ),
        );

        final f = (await cobros()).single;
        expect([f.tarjetaTipo, f.tarjetaMarca, f.numeroAprobacion], ['CREDITO', 'Visa', '004 471']);
        final p = encolador.encolados.single.payload;
        expect(p['tarjeta_tipo'], 'CREDITO');
        expect(p['tarjeta_marca'], 'Visa');
        expect(p['numero_aprobacion'], '004 471');
        expect(p['referencia_transferencia'], isNull);
        expect(p['banco_origen'], isNull);
      },
    );

    test(
      'Escenario «Cobro por transferencia» con "TX-12345": se persiste y actualiza el saldo',
      () async {
        final r = _derecha(
          await caso(
            params(medio: MedioCobranza.transferencia, referencia: 'TX-12345', banco: 'Itaú'),
          ),
        );

        expect(r.venta.saldoCentavos, 100000);
        final f = (await cobros()).single;
        expect(
          [f.medio, f.referenciaTransferencia, f.bancoOrigen],
          ['TRANSFERENCIA', 'TX-12345', 'Itaú'],
        );
        final p = encolador.encolados.single.payload;
        expect(p['referencia_transferencia'], 'TX-12345');
        expect(p['banco_origen'], 'Itaú');
        expect(p['tarjeta_tipo'], isNull);
        expect(p['numero_aprobacion'], isNull);
      },
    );

    test(
      'un medio nunca arrastra los datos de otro (el servidor lo rechazaría con un CHECK)',
      () async {
        _derecha(
          await caso(
            params(
              id: 'c-t',
              medio: MedioCobranza.tarjeta,
              tipo: TipoTarjeta.debito,
              referencia: 'TX-9',
              banco: 'BROU',
            ),
          ),
        );
        _derecha(
          await caso(
            params(
              id: 'c-x',
              medio: MedioCobranza.transferencia,
              tipo: TipoTarjeta.credito,
              marca: 'Visa',
              aprobacion: '77',
              referencia: 'TX-1',
            ),
          ),
        );
        _derecha(
          await caso(
            params(
              id: 'c-e',
              monto: 100,
              tipo: TipoTarjeta.credito,
              marca: 'Visa',
              aprobacion: '77',
              referencia: 'TX-1',
              banco: 'BROU',
            ),
          ),
        );

        final filas = {for (final f in await cobros()) f.id: f};
        expect(filas['c-t']!.referenciaTransferencia, isNull);
        expect(filas['c-t']!.bancoOrigen, isNull);
        expect(filas['c-x']!.tarjetaTipo, isNull);
        expect(filas['c-x']!.tarjetaMarca, isNull);
        expect(filas['c-x']!.numeroAprobacion, isNull);
        final e = filas['c-e']!;
        expect([
          e.tarjetaTipo,
          e.tarjetaMarca,
          e.numeroAprobacion,
          e.referenciaTransferencia,
          e.bancoOrigen,
        ], everyElement(isNull));
      },
    );

    test('los largos del servidor: 40 caracteres entran, 41 no escriben nada', () async {
      _derecha(
        await caso(
          params(id: 'c-ok', medio: MedioCobranza.tarjeta, marca: 'M' * 40, aprobacion: 'A' * 40),
        ),
      );
      _derecha(
        await caso(
          params(
            id: 'c-ok2',
            medio: MedioCobranza.transferencia,
            referencia: 'R' * 40,
            banco: 'B' * 60,
          ),
        ),
      );
      for (final mal in [
        params(id: 'c-1', medio: MedioCobranza.tarjeta, marca: 'M' * 41),
        params(id: 'c-2', medio: MedioCobranza.tarjeta, aprobacion: 'A' * 41),
        params(id: 'c-3', medio: MedioCobranza.transferencia, referencia: 'R' * 41),
        params(id: 'c-4', medio: MedioCobranza.transferencia, banco: 'B' * 61),
      ]) {
        expect(_izquierda(await caso(mal)), isA<FailureCobroDatoDelMedioInvalido>());
      }
      expect((await cobros()).length, 2);
    });

    // Hallazgo 3 de la QA de #164: el largo se medía en unidades UTF-16 (`String.length`) y el servidor
    // mide caracteres (`char_length`, puntos de código): con emoji el campo dejaba escribir de más.
    test('40 emoji en la referencia son 40 caracteres para el servidor y entran', () async {
      final r = await caso(params(medio: MedioCobranza.transferencia, referencia: '😀' * 40));

      expect(r.isRight(), isTrue, reason: 'el servidor acepta 40 caracteres (char_length)');
    });

    test(
      'espacios no separables, de ancho cero y saltos de línea se limpian; solo espacios = sin dato',
      () async {
        _derecha(
          await caso(
            params(
              medio: MedioCobranza.transferencia,
              referencia: ' TX​-\n12 345\t ',
              banco: ' \n\t ',
            ),
          ),
        );

        final f = (await cobros()).single;
        expect(f.referenciaTransferencia, 'TX - 12 345');
        expect(f.bancoOrigen, isNull);
      },
    );
  });

  group('privacidad: nada de lo cargado va al log ni a toString', () {
    test(
      'un cobro rechazado o que falla no deja la aprobación, la referencia ni el banco en el log',
      () async {
        // Mayor al saldo: rechazado por el repositorio.
        _izquierda(
          await caso(
            params(
              id: 'c-9',
              monto: 999999999,
              medio: MedioCobranza.tarjeta,
              aprobacion: 'SECRETO-APR-991',
              marca: 'SECRETO-MARCA',
            ),
          ),
        );
        // Falla a mitad: el encolado se cae.
        encolador.fallarCon = StateError('SECRETO-REF-77');
        _izquierda(
          await caso(
            params(
              id: 'c-8',
              medio: MedioCobranza.transferencia,
              referencia: 'SECRETO-REF-77',
              banco: 'SECRETO-BANCO',
            ),
          ),
        );

        expect(logs(), contains('_RECHAZADO'));
        expect(logs(), contains('_FAIL'));
        expect(logs(), isNot(contains('SECRETO')));
      },
    );

    test('un cobro con datos del medio que sale bien: el log tampoco los trae', () async {
      _derecha(
        await caso(
          params(
            medio: MedioCobranza.tarjeta,
            marca: 'SECRETO-MARCA',
            aprobacion: 'SECRETO-APR-991',
          ),
        ),
      );
      expect(logs(), isNot(contains('SECRETO')));
    });

    test(
      'toString de los parámetros, del cobro y de las fallas no muestra los datos del medio',
      () async {
        final p = params(
          medio: MedioCobranza.transferencia,
          referencia: 'SECRETO-REF-77',
          banco: 'SECRETO-BANCO',
        );
        expect(p.toString(), isNot(contains('SECRETO')));
        final r = _derecha(await caso(p));
        expect(r.cobranza.toString(), isNot(contains('SECRETO')));
        expect(r.toString(), isNot(contains('SECRETO')));
        expect(const FailureCobroDatoDelMedioInvalido().toString(), isNot(contains('SECRETO')));
      },
    );
  });

  group('reintentos', () {
    test('el mismo id con los mismos datos es el mismo cobro: una fila, una cola', () async {
      final a = caso(params(medio: MedioCobranza.tarjeta, aprobacion: '77'));
      final b = caso(params(medio: MedioCobranza.tarjeta, aprobacion: '77'));
      final rs = [_derecha(await a), _derecha(await b)];

      expect(rs.where((r) => r.yaEstaba), hasLength(1));
      expect(await cobros(), hasLength(1));
      expect(encolador.encolados, hasLength(1));
    });

    test(
      'tras una falla del encolado, el reintento con el mismo id registra una sola vez',
      () async {
        encolador.fallarCon = StateError('x');
        _izquierda(await caso(params(medio: MedioCobranza.tarjeta, aprobacion: '77')));
        expect(await cobros(), isEmpty);

        encolador.fallarCon = null;
        final r = _derecha(await caso(params(medio: MedioCobranza.tarjeta, aprobacion: '77')));

        expect(r.yaEstaba, isFalse);
        expect(await cobros(), hasLength(1));
        expect(encolador.encolados, hasLength(1));
      },
    );
  });
}
