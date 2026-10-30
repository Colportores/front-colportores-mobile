// QA de «Registrar depósito» (HU-CTA-004, #442, PR #593): lo que el code review y los tests del
// implementador no tocan. Es la capa de datos, sin vista: la pantalla 33 D es de #443.
//
// Cubre los bordes del día de Montevideo, el texto hostil, la concurrencia con la base real, la
// reversión de la cola real cuando algo falla tarde, un rechazo del servidor que no frena a los demás,
// el registro sin conexión (33D-06) y la privacidad.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';

// 30/10/2026 12:00 en Montevideo (UTC-3).
final _ahora = DateTime.utc(2026, 10, 30, 15);

RegistrarDepositoParams _params(
  String id, {
  int monto = 180000,
  DestinoDeDeposito destino = DestinoDeDeposito.banco,
  ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
  DateTime? fecha,
  String? campaniaId,
  String? ticketId = 't-1',
}) => RegistrarDepositoParams(
  depositoId: id,
  colportorId: 'col-1',
  montoCentavos: monto,
  destino: destino,
  concepto: concepto,
  fecha: fecha,
  campaniaId: campaniaId,
  ticketId: destino.llevaTicket ? ticketId : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late RegistrarDepositoUseCase caso;
  late DateTime Function() reloj;

  setUp(() {
    reloj = () => _ahora;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    caso = RegistrarDepositoUseCase(
      DepositoRepositoryImpl(
        DepositoLocalDataSourceDrift(db, encolador: encolador),
        logger: loggerMudo(),
      ),
      ahora: () => reloj(),
    );
  });
  tearDown(() => db.close());

  Future<List<DepositoFila>> filas() =>
      (db.select(db.depositos)..orderBy([(d) => OrderingTerm.asc(d.id)])).get();

  Failure? falla(Either<Failure, DepositoRegistrado> r) => r.fold((f) => f, (_) => null);

  group('el día de Montevideo (medianoche exacta)', () {
    test(
      'dado las 23:59:59.999 de Montevideo, cuando deposita con esa misma hora, entra',
      () async {
        // 31/10 02:59:59.999Z = 30/10 23:59:59.999 en Montevideo.
        final casiMedianoche = DateTime.utc(2026, 10, 31, 2, 59, 59, 999);
        reloj = () => casiMedianoche;

        final r = await caso(_params('d-1', fecha: casiMedianoche));

        expect(r.isRight(), isTrue);
        expect(await filas(), hasLength(1));
      },
    );

    test('dado las 23:59:59.999 de Montevideo, cuando la fecha es la medianoche siguiente (00:00 '
        'del día de mañana), es FailureDepositoFechaInvalida y no guarda', () async {
      reloj = () => DateTime.utc(2026, 10, 31, 2, 59, 59, 999);

      final r = await caso(_params('d-1', fecha: DateTime.utc(2026, 10, 31, 3)));

      expect(falla(r), isA<FailureDepositoFechaInvalida>());
      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('dado las 00:00 de Montevideo, cuando deposita con una fecha de ayer a las 23:59, entra '
        '(un depósito de anoche cargado a la mañana)', () async {
      reloj = () => DateTime.utc(2026, 10, 31, 3);

      final r = await caso(_params('d-1', fecha: DateTime.utc(2026, 10, 31, 2, 59)));

      expect(r.isRight(), isTrue);
    });

    test('dado la hora de hoy a la noche, cuando la fecha va unas horas después de ahora pero el '
        'mismo día de Montevideo, entra', () async {
      // Ahora = 12:00 Mvd; la fecha = 23:30 Mvd del mismo día.
      final r = await caso(_params('d-1', fecha: DateTime.utc(2026, 10, 31, 2, 30)));

      expect(r.isRight(), isTrue);
    });
  });

  group('fechas límite en la base', () {
    test('dado una fecha anterior a 1970, cuando se registra, vuelve igual de la base', () async {
      final vieja = DateTime.utc(1969, 12, 31, 23, 59, 59, 500);

      final r = await caso(_params('d-1', fecha: vieja));

      expect(r.isRight(), isTrue);
      final leidos = (await DepositoLocalDataSourceDrift(db, encolador: encolador).todos()).single;
      expect(leidos.fecha, vieja);
      expect(encolador.encolados.single.payload['fecha'], '1969-12-31T23:59:59.500Z');
    });

    test('dado una fecha de hace veinte años, cuando se registra, entra (el servidor no tiene '
        'piso)', () async {
      final r = await caso(_params('d-1', fecha: DateTime.utc(2006, 3, 4, 10)));

      expect(r.isRight(), isTrue);
    });

    test('dado una fecha con microsegundos, cuando se registra, se trunca al milisegundo y '
        'coincide con el payload', () async {
      final r = await caso(_params('d-1', fecha: DateTime.utc(2026, 10, 30, 10, 0, 0, 123, 999)));

      final d = r.getOrElse(() => throw StateError('falló')).deposito;
      expect(d.fecha, DateTime.utc(2026, 10, 30, 10, 0, 0, 123));
      expect(encolador.encolados.single.payload['fecha'], '2026-10-30T10:00:00.123Z');
    });
  });

  group('montos límite', () {
    for (final monto in [0, -1, -180000, 2147483648, 9007199254740991, -9007199254740991]) {
      test('dado el monto $monto, cuando se registra, es FailureDepositoMontoInvalido y no '
          'guarda nada', () async {
        final r = await caso(_params('d-1', monto: monto));

        expect(falla(r), isA<FailureDepositoMontoInvalido>());
        expect(await filas(), isEmpty);
        expect(encolador.encolados, isEmpty);
      });
    }

    for (final monto in [1, 99, 100, 2147483647]) {
      test('dado el monto $monto, cuando se registra, se guarda exacto en la base y en el '
          'payload', () async {
        await caso(_params('d-$monto', monto: monto));

        expect((await filas()).single.monto, monto);
        expect(encolador.encolados.single.payload['monto'], monto);
      });
    }
  });

  group('texto hostil en los ids', () {
    const hostiles = [
      "t-1'; DROP TABLE deposito; --",
      '🎫-ñ-ü-日本語-​-🧾',
      'con\nsalto\r\ny\ttab',
      '<script>alert(1)</script>',
    ];
    for (final texto in hostiles) {
      test('dado el ticket «${texto.replaceAll('\n', r'\n').replaceAll('\r', r'\r')}», cuando se '
          'registra, se guarda tal cual y la tabla sigue viva', () async {
        final r = await caso(_params('d-1', ticketId: texto));

        expect(r.isRight(), isTrue);
        final guardado = (await filas()).single;
        expect(guardado.ticketId, texto.trim());
        expect(encolador.encolados.single.payload['ticket_id'], texto.trim());
        expect(await filas(), hasLength(1));
      });
    }

    test('dado un texto pegado de 20 mil caracteres como ticket y como campaña, cuando se '
        'registra, entra y vuelve entero', () async {
      final largo = List.filled(20000, 'ab').join().substring(0, 20000);

      final r = await caso(
        _params('d-1', concepto: ConceptoDeDeposito.alquiler, campaniaId: largo, ticketId: largo),
      );

      expect(r.isRight(), isTrue);
      final g = (await filas()).single;
      expect(g.ticketId, largo);
      expect(g.campaniaId, largo);
    });

    test('dado solo espacios, saltos y tabs como campaña con alquiler, cuando se registra, es '
        'FailureDepositoSinCampania', () async {
      final r = await caso(
        _params('d-1', concepto: ConceptoDeDeposito.alquiler, campaniaId: ' \n\t '),
      );

      expect(falla(r), isA<FailureDepositoSinCampania>());
      expect(await filas(), isEmpty);
    });

    test('dado un id de depósito con solo espacios, cuando se registra, no guarda nada', () async {
      final r = await caso(_params('   '));

      expect(falla(r), isA<FailureDepositoNoGuardado>());
      expect(await filas(), isEmpty);
    });
  });

  group('acciones superpuestas con la base real', () {
    test('dado cinco toques a la vez con el mismo id, cuando se registra, queda una fila, un '
        'encolado y una sola respuesta «nuevo»', () async {
      final rs = await Future.wait([for (var i = 0; i < 5; i++) caso(_params('d-1'))]);

      expect(rs.every((r) => r.isRight()), isTrue);
      final registrados = [for (final r in rs) r.getOrElse(() => throw StateError('falló'))];
      expect(registrados.where((r) => !r.yaEstaba), hasLength(1));
      expect(await filas(), hasLength(1));
      expect(encolador.encolados, hasLength(1));
      final auditorias = await db.select(db.auditLogLocal).get();
      expect(auditorias, hasLength(1));
    });

    test('dado tres depósitos a la vez con el mismo ticket, cuando se registran, entra uno y los '
        'otros dos reciben «Ese ticket ya está registrado en otro depósito»', () async {
      final rs = await Future.wait([for (var i = 0; i < 3; i++) caso(_params('d-$i'))]);

      expect(rs.where((r) => r.isRight()), hasLength(1));
      final fallas = [for (final r in rs) falla(r)].whereType<Failure>().toList();
      expect(fallas, hasLength(2));
      expect(fallas, everyElement(isA<FailureDepositoTicketYaUsado>()));
      expect(fallas.first.mensaje, 'Ese ticket ya está registrado en otro depósito.');
      expect(await filas(), hasLength(1));
      expect(encolador.encolados, hasLength(1));
    });

    test('dado un depósito rechazado por ticket repetido, cuando se corrige con otro ticket y '
        'el mismo id, entra (lo tipeado no se pierde ni queda trabado)', () async {
      await caso(_params('d-1', ticketId: 't-1'));
      final rechazado = await caso(_params('d-2', ticketId: 't-1'));
      expect(falla(rechazado), isA<FailureDepositoTicketYaUsado>());

      final r = await caso(_params('d-2', ticketId: 't-2'));

      expect(r.isRight(), isTrue);
      expect((await filas()).map((f) => f.id), ['d-1', 'd-2']);
    });

    test('dado un depósito a la vez de banco y otro de retiro, cuando se registran, entran los '
        'dos en el orden en que se pidieron', () async {
      await Future.wait([
        caso(_params('d-1')),
        caso(_params('d-2', destino: DestinoDeDeposito.retiroCoordinador)),
      ]);

      expect(encolador.encolados.map((c) => c.payload['id']), ['d-1', 'd-2']);
    });
  });

  group('falla tarde, después de escribir y encolar', () {
    test('dado que la fila de auditoría falla, cuando se registra, no queda el depósito y el '
        'reintento con el mismo id, ya reparada la base, entra', () async {
      await db.customStatement('ALTER TABLE audit_log RENAME TO audit_log_rota');

      final r = await caso(_params('d-1'));

      expect(falla(r), isA<FailureDepositoNoGuardado>());
      expect(falla(r)!.mensaje, 'No pudimos registrar el depósito. No cambió nada.');
      expect(await filas(), isEmpty);

      await db.customStatement('ALTER TABLE audit_log_rota RENAME TO audit_log');
      final reintento = await caso(_params('d-1'));
      expect(reintento.isRight(), isTrue);
      expect(await filas(), hasLength(1));
    });

    test('dado que la falla mantiene ocupada la base, cuando se registran dos seguidos, el '
        'segundo no queda colgado', () async {
      await db.customStatement('ALTER TABLE audit_log RENAME TO audit_log_rota');

      final rs = await Future.wait([caso(_params('d-1')), caso(_params('d-2', ticketId: 't-2'))]);

      expect(rs.map(falla), everyElement(isA<FailureDepositoNoGuardado>()));
      expect(await filas(), isEmpty);
    });
  });

  group('privacidad (convenciones §7.5)', () {
    test('dado Equatable sin stringify (como en main.dart), cuando se imprimen el depósito, el '
        'registrado y los parámetros, no aparecen el ticket, la campaña ni el monto', () async {
      final previo = EquatableConfig.stringify;
      EquatableConfig.stringify = false;
      addTearDown(() => EquatableConfig.stringify = previo);
      final r = await caso(
        _params(
          'd-1',
          monto: 123456,
          concepto: ConceptoDeDeposito.alquiler,
          campaniaId: 'campania-secreta',
          ticketId: 'ticket-secreto',
        ),
      );
      final registrado = r.getOrElse(() => throw StateError('falló'));

      final textos = [
        registrado.toString(),
        registrado.deposito.toString(),
        _params('d-1', ticketId: 'ticket-secreto', monto: 123456).toString(),
        registrado.deposito.auditoria.toString(),
      ].join(' ');

      expect(textos, isNot(contains('ticket-secreto')));
      expect(textos, isNot(contains('campania-secreta')));
      expect(textos, isNot(contains('123456')));
      expect(textos, isNot(contains('col-1')));
    });

    test('dado cualquier falla del depósito, cuando se imprime, no trae ids ni montos', () {
      final fallas = <Failure>[
        const FailureDepositoNoGuardado(causa: 'StateError'),
        const FailureDepositoNoDisponible(),
        const FailureDepositoMontoInvalido(),
        const FailureDepositoFechaInvalida(),
        const FailureDepositoSinTicket(),
        const FailureDepositoRetiroConTicket(),
        const FailureDepositoSinCampania(),
        const FailureDepositoTicketYaUsado(),
      ];
      for (final f in fallas) {
        expect(f.mensaje, isNotEmpty);
        expect(f.mensaje, isNot(contains(RegExp(r'\d{4,}'))));
        expect(f.mensaje.trim(), endsWith('.'));
      }
    });

    test('dado un depósito registrado, cuando se mira el audit_log local, la fila solo trae el '
        'id y el momento', () async {
      await caso(_params('d-1', monto: 424242, ticketId: 'ticket-secreto'));

      final filasAuditoria = await db.select(db.auditLogLocal).get();

      expect(filasAuditoria, hasLength(1));
      expect(filasAuditoria.single.toString(), isNot(contains('ticket-secreto')));
      expect(filasAuditoria.single.toString(), isNot(contains('424242')));
    });
  });

  group('contra el motor real', () {
    late FakeSyncTransport servidor;
    late FakeConnectivityPort red;
    late SyncEngine motor;
    late RegistrarDepositoUseCase conMotor;

    setUp(() {
      servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
      red = FakeConnectivityPort();
      motor = SyncEngine(
        specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
        transport: servidor,
        jobs: DriftJobStore(db),
        store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
        connectivity: red,
      );
      conMotor = RegistrarDepositoUseCase(
        DepositoRepositoryImpl(
          DepositoLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
          logger: loggerMudo(),
        ),
        ahora: () => _ahora,
      );
    });
    tearDown(() async {
      await motor.dispose();
      await red.dispose();
    });

    Future<List<SyncQueueFila>> cola() =>
        (db.select(db.syncQueue)..orderBy([(j) => OrderingTerm.asc(j.createdAt)])).get();

    test('dado que la auditoría falla después de encolar, cuando se registra, la cola real también '
        'se revierte (ni fila ni trabajo huérfano)', () async {
      await db.customStatement('ALTER TABLE audit_log RENAME TO audit_log_rota');

      final r = await conMotor(_params('d-1'));

      expect(falla(r), isA<FailureDepositoNoGuardado>());
      expect(await filas(), isEmpty);
      expect(await cola(), isEmpty);
    });

    test('dado que el servidor rechaza el primer depósito (23514), cuando sincroniza, el segundo '
        'igual llega y el rechazado no se borra del teléfono', () async {
      await conMotor(_params('d-1', ticketId: 't-1'));
      await conMotor(_params('d-2', ticketId: 't-2'));
      final primero = (await cola()).first;
      servidor.rejectJob(primero.clientOpId, '23514', 'deposito_fecha_no_futura');

      await motor.syncNow();

      expect(servidor.rowsOf('deposito').map((f) => f['id']), ['d-2']);
      final estados = {for (final j in await cola()) j.rowPk: j.state};
      expect(estados['d-2'], 'DONE');
      expect(estados['d-1'], isNot('DONE'));
      expect(estados['d-1'], isNot('PENDING'), reason: 'no puede quedar reintentando para siempre');
      expect((await filas()).map((f) => f.id), ['d-1', 'd-2']);
    });

    test('dado que no hay conexión (33D-06), cuando se registra, se guarda y queda pendiente; '
        'al volver la red sube sin duplicarse', () async {
      red.goOffline();

      final r = await conMotor(_params('d-1'));

      expect(r.isRight(), isTrue);
      expect(await filas(), hasLength(1));
      expect(servidor.rowsOf('deposito'), isEmpty);
      expect((await cola()).single.state, 'PENDING');

      red.goWifi();
      await motor.syncNow();
      await motor.syncNow();

      expect(servidor.rowsOf('deposito'), hasLength(1));
      expect((await cola()).single.state, 'DONE');
    });

    test('dado un depósito sincronizado, cuando se registra otro con el mismo id (reentrada), no '
        'se vuelve a encolar ni a subir', () async {
      await conMotor(_params('d-1'));
      await motor.syncNow();

      final otra = await conMotor(_params('d-1'));
      await motor.syncNow();

      expect(otra.getOrElse(() => throw StateError('falló')).yaEstaba, isTrue);
      expect(await cola(), hasLength(1));
      expect(servidor.rowsOf('deposito'), hasLength(1));
    });

    test('dado el payload que sube, cuando se lo mira, no trae colportor_id ni nada de cobros '
        'ni de personas', () async {
      await conMotor(_params('d-1'));

      final payload = jsonDecode((await cola()).single.payload) as Map<String, Object?>;

      expect(payload.keys, isNot(contains('colportor_id')));
      expect(payload.keys.where((k) => k.contains('cobr') || k.contains('person')), isEmpty);
    });
  });
}
