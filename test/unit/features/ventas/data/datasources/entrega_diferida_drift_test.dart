// La entrega para otro día contra las tablas reales (HU-VEN-003, #433): AppDatabase en memoria, mismo
// esquema y mismos CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/entrega_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
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
  late EntregaLocalDataSourceDrift local;
  late EntregaRepositoryImpl repo;

  final sabado = DateTime.utc(2026, 10, 31, 13);
  final lunes = DateTime.utc(2026, 11, 2, 13);
  final ahora = DateTime.utc(2026, 10, 28, 15);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estado = HouseStatusUpdaterDrift(db, encolador: encolador);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: estado);
    repo = EntregaRepositoryImpl(local, logger: loggerMudo());
    await sembrarCasa(db);
    await (db.update(
      db.ubicaciones,
    )).write(const UbicacionesCompanion(calle: Value('Grecia'), numero: Value('3310')));
  });
  tearDown(() => db.close());

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<EntregaFila>> entregas() =>
      (db.select(db.entregas)..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
  Future<List<AgendaFila>> citas() => db.select(db.agendas).get();
  Future<String?> color() async =>
      (await db.select(db.houseStatuses).get()).map((h) => h.color).singleOrNull;

  /// Una venta de [monto] con la cantidad de libros que se pide.
  Future<void> vender({int monto = 150000, String id = 'v-1', String vinculo = 'ep-1'}) async {
    await ventas.registrar(ventaDe(id, monto: monto, vinculo: vinculo, talonario: 'T-$id'), [
      itemDe('i-$id', id),
    ]);
    encolador.encolados.clear();
  }

  List<Entrega> dosLibros({DateTime? fecha, String venta = 'v-1'}) => [
    entregaDe('e-1', 'prod-1', pendiente: true, fechaPrevista: fecha, ventaId: venta),
    entregaDe('e-2', 'prod-2', cantidad: 2, pendiente: true, fechaPrevista: fecha, ventaId: venta),
  ];

  Future<void> diferir({
    String venta = 'v-1',
    DateTime? fecha,
    String cita = 'c-1',
    List<Entrega>? filas,
    DateTime? cuando,
  }) => local.diferir(
    venta,
    fechaPrevista: fecha ?? sabado,
    ahora: cuando ?? ahora,
    filasNuevas: filas ?? dosLibros(fecha: fecha ?? sabado, venta: venta),
    idDeLaCita: cita,
  );

  /// Lo mismo que [diferir] pero devuelve el resultado, sin pasar filas nuevas: sirve para volver a
  /// fechar lo que ya está guardado.
  Future<EntregaDiferida> diferirA(DateTime fecha, DateTime cuando, {String cita = 'c-otra'}) =>
      local.diferir(
        'v-1',
        fechaPrevista: fecha,
        ahora: cuando,
        filasNuevas: dosLibros(fecha: fecha),
        idDeLaCita: cita,
      );

  group('diferir', () {
    test(
      'guarda una fila pendiente por producto con la fecha prevista y agenda la entrega, en orden',
      () async {
        await vender();

        final r = await local.diferir(
          'v-1',
          fechaPrevista: sabado,
          ahora: ahora,
          filasNuevas: dosLibros(fecha: sabado),
          idDeLaCita: 'c-1',
        );

        expect(r.yaEstaba, isFalse);
        expect(r.citaNueva, isTrue);
        final filas = await entregas();
        expect(filas.map((f) => [f.id, f.pendiente, f.fechaPrevista, f.fechaEntrega]), [
          ['e-1', true, sabado, null],
          ['e-2', true, sabado, null],
        ]);
        final cita = (await citas()).single;
        expect(cita.id, 'c-1');
        expect(cita.tipo, 'ENTREGA');
        expect(cita.estado, 'PROGRAMADA');
        expect(cita.fechaProgramada, sabado);
        expect(cita.ventaId, 'v-1');
        expect(cita.entregaId, 'e-1');
        expect(
          [cita.espacioId, cita.espacioPersonaId, cita.colportorId],
          ['esp-1', 'ep-1', 'col-1'],
        );
        // Las filas suben antes que la cita que las nombra (la clave foránea del servidor).
        // (El color no cambia —ya era «entrega y cobranza pendientes»—: no se encola house_status.)
        expect(cola(), ['entrega:insert', 'entrega:insert', 'agenda:insert']);
        expect(r.cita.estado, EstadoAgenda.programada);
        expect(r.cita.tipo, TipoAgenda.entrega);
        expect(r.direccion, 'Grecia 3310');
      },
    );

    test('la casa sigue en «Entrega y cobranza pendientes» (1) y lo dice el resultado', () async {
      await vender();

      final r = await diferirA(sabado, ahora);

      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      expect(r.colorDeLaCasa, ColorHouseStatus.entregaYCobranzaPendiente);
    });

    test(
      'lo que sube lleva fecha_prevista, venta_id y entrega_id, y ningún dato de la persona',
      () async {
        await vender();

        await diferir();

        final fila = encolador.encolados.first.payload;
        expect(fila['fecha_prevista'], '2026-10-31T13:00:00.000Z');
        expect(fila['fecha_entrega'], isNull);
        expect(fila['pendiente'], true);
        final cita = encolador.encolados[2].payload;
        expect(cita['tipo'], 'ENTREGA');
        expect(cita['venta_id'], 'v-1');
        expect(cita['entrega_id'], 'e-1');
        expect(cita['estado'], 'PROGRAMADA');
        expect(cita['fecha_programada'], '2026-10-31T13:00:00.000Z');
        expect('${encolador.encolados.map((c) => c.payload)}', isNot(contains('Atiende')));
      },
    );

    test(
      'el segundo toque con la misma fecha no escribe ni encola nada y no duplica la cita',
      () async {
        await vender();
        await diferir();
        encolador.encolados.clear();

        final r = await local.diferir(
          'v-1',
          fechaPrevista: sabado,
          ahora: ahora.add(const Duration(seconds: 1)),
          filasNuevas: dosLibros(fecha: sabado),
          idDeLaCita: 'c-otro',
        );

        expect(r.yaEstaba, isTrue);
        expect(r.citaNueva, isFalse);
        expect(r.cita.id, 'c-1');
        expect(encolador.encolados, isEmpty);
        expect((await citas()).length, 1);
        expect((await entregas()).length, 2);
      },
    );

    test('otra fecha mueve la cita que había y las filas, sin crear una segunda', () async {
      await vender();
      await diferir();
      encolador.encolados.clear();

      final r = await diferirA(lunes, ahora.add(const Duration(minutes: 5)));

      expect(r.yaEstaba, isFalse);
      expect(r.citaNueva, isFalse);
      final cita = (await citas()).single;
      expect([cita.id, cita.fechaProgramada, cita.estado], ['c-1', lunes, 'PROGRAMADA']);
      expect((await entregas()).map((f) => f.fechaPrevista), [lunes, lunes]);
      expect(cola(), ['entrega:update', 'entrega:update', 'agenda:update']);
      expect(encolador.encolados.last.payload['fecha_programada'], '2026-11-02T13:00:00.000Z');
    });

    test('dos cambios de fecha seguidos dejan la última, con una sola cita viva', () async {
      await vender();
      await diferir();

      await diferirA(lunes, ahora.add(const Duration(minutes: 1)));
      await diferirA(sabado, ahora.add(const Duration(minutes: 2)));

      final cita = (await citas()).single;
      expect(cita.fechaProgramada, sabado);
      expect((await entregas()).map((f) => f.fechaPrevista), [sabado, sabado]);
    });

    test(
      '«Poner fecha» a lo que quedó pendiente sin fecha: las filas toman la fecha y se agenda',
      () async {
        await vender();
        await local.entregarAhora('v-1', [
          entregaDe('e-1', 'prod-1'),
          entregaDe('e-2', 'prod-2', pendiente: true),
        ]);
        encolador.encolados.clear();

        final r = await local.diferir(
          'v-1',
          fechaPrevista: sabado,
          ahora: ahora,
          filasNuevas: const [],
          idDeLaCita: 'c-1',
        );

        expect(r.citaNueva, isTrue);
        final filas = await entregas();
        final entregada = filas.firstWhere((f) => f.id == 'e-1');
        final pendiente = filas.firstWhere((f) => f.id == 'e-2');
        // Lo ya entregado no se toca; lo pendiente toma la fecha.
        expect([entregada.pendiente, entregada.fechaPrevista], [false, null]);
        expect([pendiente.pendiente, pendiente.fechaPrevista], [true, sabado]);
        expect((await citas()).single.entregaId, 'e-2');
        expect(cola(), ['entrega:update', 'agenda:insert']);
      },
    );

    test('una cita cancelada a mano no se mueve: «Poner fecha» agenda una nueva', () async {
      await vender();
      await diferir();
      await (db.update(db.agendas)).write(const AgendasCompanion(estado: Value('CANCELADA')));
      encolador.encolados.clear();

      final r = await local.diferir(
        'v-1',
        fechaPrevista: lunes,
        ahora: ahora,
        filasNuevas: const [],
        idDeLaCita: 'c-2',
      );

      expect(r.citaNueva, isTrue);
      final todas = await citas();
      expect(
        todas.map((c) => [c.id, c.estado]),
        unorderedEquals([
          ['c-1', 'CANCELADA'],
          ['c-2', 'PROGRAMADA'],
        ]),
      );
    });

    test('una venta ya entregada entera no se deja para otro día: nada se escribe', () async {
      await vender();
      await local.entregarAhora('v-1', [entregaDe('e-1', 'prod-1')]);
      encolador.encolados.clear();

      await expectLater(diferir(), throwsA(isA<EntregaSinPendientesException>()));

      expect(encolador.encolados, isEmpty);
      expect(await citas(), isEmpty);
      expect((await entregas()).single.fechaPrevista, isNull);
    });

    test('sin filas y sin productos no hay qué agendar', () async {
      await vender();

      await expectLater(
        diferir(filas: const []),
        throwsA(isA<EntregaSinPendientesException>().having((e) => e.sinFilas, 'sinFilas', isTrue)),
      );

      expect(await entregas(), isEmpty);
      expect(await citas(), isEmpty);
    });

    test('una venta que no está en el teléfono no guarda nada', () async {
      await expectLater(diferir(venta: 'v-9'), throwsA(isA<EntregaSinVentaException>()));

      expect(await entregas(), isEmpty);
      expect(await citas(), isEmpty);
    });

    test('una casa que no está en el teléfono frena: la cita cuelga del espacio', () async {
      await vender();
      await (db.update(db.espacioPersonas)).write(EspacioPersonasCompanion(deletedAt: Value(t0)));

      await expectLater(diferir(), throwsA(isA<EntregaSinCasaException>()));

      expect(await entregas(), isEmpty);
      expect(await citas(), isEmpty);
    });

    test('si falla el encolado de la cita, no queda nada: ni filas ni cita ni color', () async {
      await vender();
      final antes = await color();
      encolador.fallarCon = StateError('motor apagado');
      encolador.fallarDespuesDe = 2;

      await expectLater(diferir(), throwsA(isA<StateError>()));

      expect(await entregas(), isEmpty);
      expect(await citas(), isEmpty);
      expect(await color(), antes);
    });
  });

  group('cumplir', () {
    Future<void> dejadaParaElSabado() async {
      await vender();
      await diferir();
      encolador.encolados.clear();
    }

    test('«Entregado hoy» pasa todo a entregado con la fecha real y cumple la cita', () async {
      await dejadaParaElSabado();
      final hoy = DateTime.utc(2026, 10, 31, 16);

      final r = await local.cumplir('v-1', ahora: hoy, idDeLaCita: 'c-x');

      expect(r.yaEstaba, isFalse);
      expect(r.quedaPendiente, isFalse);
      expect(r.citaCumplida, isTrue);
      expect(r.citaConFechaNueva, isFalse);
      expect(r.entregadas.map((e) => e.id), ['e-1', 'e-2']);
      final filas = await entregas();
      expect(filas.map((f) => [f.pendiente, f.fechaEntrega, f.fechaPrevista]), [
        [false, hoy, sabado],
        [false, hoy, sabado],
      ]);
      expect((await citas()).single.estado, 'CUMPLIDA');
      expect(cola(), ['entrega:update', 'entrega:update', 'agenda:update', 'house_status:update']);
      expect(encolador.encolados.last.payload['color'], 'COBRANZA_PENDIENTE');
      expect(r.colorDeLaCasa, ColorHouseStatus.cobranzaPendiente);
    });

    test('entregado y sin saldo, la casa pasa a «Venta completa» (4)', () async {
      await vender(monto: 0);
      await diferir();

      final r = await local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x');

      expect(r.colorDeLaCasa, ColorHouseStatus.ventaCompleta);
      expect(await color(), 'VENTA_COMPLETA');
    });

    test('marcar dos veces no escribe ni encola de nuevo y responde que ya estaba', () async {
      await dejadaParaElSabado();
      await local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x');
      encolador.encolados.clear();

      final r = await local.cumplir(
        'v-1',
        ahora: sabado.add(const Duration(seconds: 2)),
        idDeLaCita: 'c-y',
        entregaIds: {'e-1', 'e-2'},
      );

      expect(r.yaEstaba, isTrue);
      expect(r.entregadas, isEmpty);
      expect(encolador.encolados, isEmpty);
      expect((await entregas()).map((f) => f.fechaEntrega), [sabado, sabado]);
      expect(await color(), 'COBRANZA_PENDIENTE');
    });

    test('sin ids, marcar de nuevo lo ya entregado dice que no hay nada pendiente', () async {
      await dejadaParaElSabado();
      await local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x');

      await expectLater(
        local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-y'),
        throwsA(isA<EntregaSinPendientesException>()),
      );
    });

    test(
      'parcial con fecha nueva: lo marcado se entrega y la cita se mueve a lo que queda',
      () async {
        await dejadaParaElSabado();

        final r = await local.cumplir(
          'v-1',
          ahora: sabado,
          idDeLaCita: 'c-x',
          entregaIds: {'e-1'},
          nuevaFecha: lunes,
        );

        expect(r.quedaPendiente, isTrue);
        expect(r.citaCumplida, isFalse);
        expect(r.citaConFechaNueva, isTrue);
        final filas = await entregas();
        final e1 = filas.firstWhere((f) => f.id == 'e-1');
        final e2 = filas.firstWhere((f) => f.id == 'e-2');
        expect([e1.pendiente, e1.fechaEntrega, e1.fechaPrevista], [false, sabado, sabado]);
        expect([e2.pendiente, e2.fechaEntrega, e2.fechaPrevista], [true, null, lunes]);
        final cita = (await citas()).single;
        expect(
          [cita.id, cita.estado, cita.fechaProgramada, cita.entregaId],
          ['c-1', 'PROGRAMADA', lunes, 'e-2'],
        );
        expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      },
    );

    test('parcial sin fecha nueva: lo que queda se queda sin fecha y la cita se cumple', () async {
      await dejadaParaElSabado();

      final r = await local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x', entregaIds: {'e-1'});

      expect(r.quedaPendiente, isTrue);
      expect(r.citaCumplida, isTrue);
      final e2 = (await entregas()).firstWhere((f) => f.id == 'e-2');
      expect([e2.pendiente, e2.fechaPrevista], [true, null]);
      expect((await citas()).single.estado, 'CUMPLIDA');
    });

    test('parcial de una entrega sin cita (era inmediata) con fecha nueva agenda una', () async {
      await vender();
      await local.entregarAhora('v-1', [
        entregaDe('e-1', 'prod-1'),
        entregaDe('e-2', 'prod-2', pendiente: true),
        entregaDe('e-3', 'prod-3', pendiente: true),
      ]);
      encolador.encolados.clear();

      final r = await local.cumplir(
        'v-1',
        ahora: sabado,
        idDeLaCita: 'c-nueva',
        entregaIds: {'e-2'},
        nuevaFecha: lunes,
      );

      expect(r.citaConFechaNueva, isTrue);
      final cita = (await citas()).single;
      expect([cita.id, cita.fechaProgramada, cita.entregaId], ['c-nueva', lunes, 'e-3']);
      expect(cola(), ['entrega:update', 'entrega:update', 'agenda:insert']);
    });

    test('una fila que no es de la venta frena todo: no se entrega nada', () async {
      await dejadaParaElSabado();

      await expectLater(
        local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x', entregaIds: {'e-1', 'e-99'}),
        throwsA(isA<EntregaAjenaException>()),
      );

      expect((await entregas()).every((f) => f.pendiente), isTrue);
      expect(encolador.encolados, isEmpty);
    });

    test('una venta sin filas de entrega no tiene qué cumplir', () async {
      await vender();

      await expectLater(
        local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x'),
        throwsA(isA<EntregaSinPendientesException>().having((e) => e.sinFilas, 'sinFilas', isTrue)),
      );
    });

    test('si falla el encolado a mitad, no queda a medio entregar', () async {
      await dejadaParaElSabado();
      encolador.fallarCon = StateError('motor apagado');
      encolador.fallarDespuesDe = 1;

      await expectLater(
        local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x'),
        throwsA(isA<StateError>()),
      );

      expect((await entregas()).every((f) => f.pendiente && f.fechaEntrega == null), isTrue);
      expect((await citas()).single.estado, 'PROGRAMADA');
      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test('la cita que se movió desde la Agenda arrastra la fecha de lo pendiente', () async {
      await dejadaParaElSabado();
      final agenda = AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      );

      await agenda.modificar(_cambios('c-1', lunes), ahora: ahora.add(const Duration(minutes: 3)));

      expect((await citas()).single.fechaProgramada, lunes);
      expect((await entregas()).map((f) => f.fechaPrevista), [lunes, lunes]);
      expect(cola(), containsAll(['agenda:update', 'entrega:update']));
    });
  });

  group('observarPendientes', () {
    test('una entrada por venta con sus filas pendientes, la fecha y la cita', () async {
      await vender();
      await diferir();

      final lista = await local.observarPendientes().first;

      expect(lista, [
        EntregaPendiente(
          ventaId: 'v-1',
          espacioPersonaId: 'ep-1',
          lineas: const [
            LineaPendiente(entregaId: 'e-1', productoId: 'prod-1', cantidad: 1),
            LineaPendiente(entregaId: 'e-2', productoId: 'prod-2', cantidad: 2),
          ],
          fechaPrevista: sabado,
          agendaId: 'c-1',
        ),
      ]);
    });

    test('lo entregado no figura y la lista vuelve a vaciarse', () async {
      await vender();
      await diferir();

      await local.cumplir('v-1', ahora: sabado, idDeLaCita: 'c-x');

      expect(await local.observarPendientes().first, isEmpty);
    });

    test('lo que quedó pendiente de una entrega parcial figura sin fecha ni cita', () async {
      await vender();
      await local.entregarAhora('v-1', [
        entregaDe('e-1', 'prod-1'),
        entregaDe('e-2', 'prod-2', pendiente: true),
      ]);

      final lista = await local.observarPendientes().first;

      expect(lista.single.sinFecha, isTrue);
      expect(lista.single.agendaId, isNull);
      expect(lista.single.lineas.map((l) => l.entregaId), ['e-2']);
    });

    test(
      'van primero las que tienen fecha, de la más próxima a la más lejana, y al final las sin fecha',
      () async {
        await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-1', personaId: 'per-2');
        await vender();
        await vender(id: 'v-2', vinculo: 'ep-2');
        await vender(id: 'v-3');
        await diferir(venta: 'v-1', fecha: lunes, cita: 'c-1');
        await diferir(
          venta: 'v-2',
          fecha: sabado,
          cita: 'c-2',
          filas: [
            entregaDe('e-3', 'prod-3', pendiente: true, ventaId: 'v-2', fechaPrevista: sabado),
          ],
        );
        await local.entregarAhora('v-3', [
          entregaDe('e-9', 'prod-9', pendiente: true, ventaId: 'v-3'),
        ]);

        final lista = await local.observarPendientes().first;

        expect(lista.map((e) => e.ventaId), ['v-2', 'v-1', 'v-3']);
      },
    );

    test('con la persona, solo trae las suyas', () async {
      await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-1', personaId: 'per-2');
      await vender();
      await vender(id: 'v-2', vinculo: 'ep-2');
      await diferir();
      await diferir(
        venta: 'v-2',
        cita: 'c-2',
        filas: [entregaDe('e-3', 'prod-3', pendiente: true, ventaId: 'v-2', fechaPrevista: sabado)],
      );

      final de2 = await local.observarPendientes(espacioPersonaId: 'ep-2').first;
      final de1 = await local.observarPendientes(espacioPersonaId: 'ep-1').first;

      expect(de2.map((e) => e.ventaId), ['v-2']);
      expect(de1.map((e) => e.ventaId), ['v-1']);
    });

    test('se vuelve a emitir cuando se deja otra entrega, se mueve la fecha o se cumple', () async {
      await vender();
      final emisiones = <List<EntregaPendiente>>[];
      final sub = local.observarPendientes().listen(emisiones.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emisiones.last, isEmpty);

      await diferir();
      await pumpEventQueue();
      expect(emisiones.last.single.fechaPrevista, sabado);

      await diferirA(lunes, ahora.add(const Duration(minutes: 1)));
      await pumpEventQueue();
      expect(emisiones.last.single.fechaPrevista, lunes);

      await local.cumplir('v-1', ahora: lunes, idDeLaCita: 'c-x');
      await pumpEventQueue();
      expect(emisiones.last, isEmpty);
    });

    test('las ventas dadas de baja y las filas dadas de baja no figuran', () async {
      await vender();
      await diferir();
      await (db.update(
        db.entregas,
      )..where((e) => e.id.equals('e-2'))).write(EntregasCompanion(deletedAt: Value(t0)));

      final lista = await local.observarPendientes().first;
      expect(lista.single.lineas.map((l) => l.entregaId), ['e-1']);

      await (db.update(db.ventas)).write(VentasCompanion(deletedAt: Value(t0)));
      expect(await local.observarPendientes().first, isEmpty);
    });
  });

  group('el repositorio traduce lo que rechaza el teléfono', () {
    test('una venta ya entregada es una validación que dice qué pasó', () async {
      await vender();
      await local.entregarAhora('v-1', [entregaDe('e-1', 'prod-1')]);

      final r = await repo.diferir(
        'v-1',
        fechaPrevista: sabado,
        ahora: ahora,
        filasNuevas: const [],
        idDeLaCita: 'c-1',
      );

      final falla = r.swap().toOption().toNullable();
      expect(falla, isA<FailureValidacion>());
      expect((falla! as FailureValidacion).campos['entrega'], contains('ya está entregada'));
    });

    test('una venta ausente o sin casa es «no se pudo guardar» y no deja nada', () async {
      final ausente = await repo.diferir(
        'v-9',
        fechaPrevista: sabado,
        ahora: ahora,
        filasNuevas: const [],
        idDeLaCita: 'c-1',
      );
      expect(ausente.swap().toOption().toNullable(), isA<FailureEntregaNoGuardada>());

      final sinVenta = await repo.cumplir('v-9', ahora: ahora, idDeLaCita: 'c-1');
      expect(sinVenta.swap().toOption().toNullable(), isA<FailureEntregaNoGuardada>());
    });

    test('una falla inesperada no filtra la excepción: solo su tipo', () async {
      await vender();
      await diferir();
      encolador.fallarCon = StateError('SECRETO con datos');
      encolador.fallarDespuesDe = encolador.encolados.length;

      final r = await repo.cumplir('v-1', ahora: ahora, idDeLaCita: 'c-1');

      final falla = r.swap().toOption().toNullable();
      expect(falla, isA<FailureEntregaNoGuardada>());
      expect(falla!.mensaje, isNot(contains('SECRETO')));
      expect((falla as FailureEntregaNoGuardada).causa, 'StateError');
    });

    test('ids que no son de la venta son una validación del campo productos', () async {
      await vender();
      await diferir();

      final r = await repo.cumplir('v-1', ahora: ahora, idDeLaCita: 'c-1', entregaIds: {'e-99'});

      final falla = r.swap().toOption().toNullable() as FailureValidacion;
      expect(falla.campos.keys, ['productos']);
    });
  });
}

/// Lo que cambia «Modificar agenda» al mover la cita a [cuando]: solo la fecha.
CambiosDeAgenda _cambios(String agendaId, DateTime cuando) => CambiosDeAgenda(
  agendaId: agendaId,
  tipo: TipoAgenda.entrega,
  fechaProgramada: cuando,
  idNota: 'nota-1',
);
