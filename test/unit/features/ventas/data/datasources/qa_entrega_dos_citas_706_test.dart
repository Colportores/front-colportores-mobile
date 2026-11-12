// QA de «Entrega cita» (#706) contra las tablas reales: los casos límite de una venta con dos citas de
// entrega que no cubre el implementador (mover una cita a la hora de la otra, cancelar a mano,
// parcial que se junta con la otra visita, toques a la vez, color de la casa).
// Con `--dart-define=QA_HALLAZGOS=true` corren los tests que documentan un hallazgo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late VentaLocalDataSourceDrift local;
  late EntregaLocalDataSourceDrift entregas;
  late AgendaLocalDataSourceDrift agenda;
  final t1 = t0.add(const Duration(days: 3));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    entregas = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    agenda = AgendaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  VentaItem nuevo(String id) => VentaItem(
    id: id,
    ventaId: 'v-39',
    productoId: 'prod-2',
    cantidad: 1,
    precioUnitarioCentavos: 40000,
    subtotalCentavos: 40000,
    auditoria: Auditoria(createdAt: t1, updatedAt: t1, createdBy: 'col-1'),
  );

  Future<AgendaFila> cita(String id) =>
      (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle();

  Future<EntregaFila> fila(String id) =>
      (db.select(db.entregas)..where((e) => e.id.equals(id))).getSingle();

  Future<List<AgendaFila>> citasVivasDeEntrega() async => [
    for (final a in await db.select(db.agendas).get())
      if (a.tipo == TipoAgenda.entrega.codigo && a.estado == 'PROGRAMADA' && a.deletedAt == null) a,
  ];

  /// La 0039 con lo de antes (e-1) para el día siguiente a t0 (cita a-1) y el libro sumado (e-2)
  /// para [despues] (cita a-2).
  Future<({DateTime antes, DateTime despues})> dosCitas({DateTime? despues}) async {
    await local.registrar(ventaDe('v-39', talonario: '0039', monto: 150000), [
      itemDe('i-v-39', 'v-39'),
    ]);
    final antes = t0.add(const Duration(days: 1));
    await entregas.diferir(
      'v-39',
      fechaPrevista: antes,
      ahora: t0,
      filasNuevas: [
        Entrega(
          id: 'e-1',
          ventaId: 'v-39',
          productoId: 'prod-1',
          cantidad: 3,
          pendiente: true,
          fechaPrevista: antes,
          auditoria: auditoriaDe(),
        ),
      ],
      idDeLaCita: 'a-1',
    );
    final r = await local.sumar('v-39', [nuevo('n-1')], sumadoCentavos: 40000, ahora: t1);
    final cuando = despues ?? t1.add(const Duration(days: 5));
    await entregas.diferir(
      'v-39',
      fechaPrevista: cuando,
      ahora: t1,
      filasNuevas: [
        Entrega(
          id: 'e-2',
          ventaId: 'v-39',
          productoId: 'prod-2',
          cantidad: 1,
          pendiente: true,
          fechaPrevista: cuando,
          auditoria: Auditoria(createdAt: t1, updatedAt: t1, createdBy: 'col-1'),
        ),
      ],
      idDeLaCita: 'a-2',
      soloDesde: r.sumadoEl,
    );
    return (antes: antes, despues: cuando);
  }

  Future<void> moverCita(String id, DateTime cuando) => agenda.modificar(
    CambiosDeAgenda(
      agendaId: id,
      tipo: TipoAgenda.entrega,
      fechaProgramada: cuando,
      idNota: 'nota-$id',
    ),
    ahora: t1,
  );

  group('QA #706 · una cita movida a la hora de la otra', () {
    test(
      'las dos citas a la misma hora comparten grupo: una sola tarjeta en «Entregas pendientes»',
      () async {
        final (:antes, despues: _) = await dosCitas();
        await moverCita('a-2', antes);

        final lista = await entregas.observarPendientes().first;

        expect(lista, hasLength(1));
        expect([for (final l in lista.single.lineas) l.entregaId], ['e-1', 'e-2']);
      },
    );

    test(
      'entregar esa visita cierra las DOS citas: ninguna queda programada sin libros',
      () async {
        final (:antes, despues: _) = await dosCitas();
        await moverCita('a-2', antes);
        final unica = (await entregas.observarPendientes().first).single;

        final hecho = await entregas.cumplir(
          'v-39',
          ahora: t1,
          idDeLaCita: 'x',
          agendaId: unica.agendaId,
        );

        expect([for (final e in hecho.entregadas) e.id], ['e-1', 'e-2']);
        expect(
          await citasVivasDeEntrega(),
          isEmpty,
          reason: 'toda la venta quedó entregada: no puede quedar una cita de entrega programada',
        );
      },
      skip: _conHallazgos ? null : 'QA #706: cita fantasma al mover una cita a la hora de la otra',
    );

    test(
      '«Entregado hoy» sobre la cita que quedó sin libros la cierra (no queda sin salida)',
      () async {
        final (:antes, despues: _) = await dosCitas();
        await moverCita('a-2', antes);
        await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-1');

        await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-2');

        expect(await citasVivasDeEntrega(), isEmpty);
      },
      skip: _conHallazgos ? null : 'QA #706: cita fantasma al mover una cita a la hora de la otra',
    );

    test('«Entregar ahora» todo con las dos citas a la misma hora las cierra', () async {
      final (:antes, despues: _) = await dosCitas();
      await moverCita('a-2', antes);

      await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x');

      expect(await citasVivasDeEntrega(), isEmpty);
    });
  });

  group('QA #706 · cancelar una cita a mano', () {
    test('la cita cancelada deja sus libros pendientes, sin cita, y la otra intacta', () async {
      final (:antes, :despues) = await dosCitas();
      await agenda.cancelar('a-2', ahora: t1);

      final lista = await entregas.observarPendientes().first;

      expect(lista, hasLength(2));
      final porFila = {for (final l in lista) l.lineas.single.entregaId: l};
      expect(porFila['e-1']!.agendaId, 'a-1');
      expect(porFila['e-2']!.agendaId, isNull);
      expect(porFila['e-2']!.fechaPrevista, despues);
      expect((await fila('e-1')).fechaPrevista, antes);
    });

    test('entregar la cita que queda no cierra ni entrega lo de la cancelada', () async {
      await dosCitas();
      await agenda.cancelar('a-2', ahora: t1);

      final hecho = await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-1');

      expect([for (final e in hecho.entregadas) e.id], ['e-1']);
      expect((await fila('e-2')).pendiente, isTrue);
      expect(hecho.quedaPendiente, isFalse);
    });

    test('«Entregas pendientes» sigue trayendo lo de la cancelada para poder entregarlo', () async {
      await dosCitas();
      await agenda.cancelar('a-2', ahora: t1);
      await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-1');

      final lista = await entregas.observarPendientes().first;

      expect([for (final l in lista) l.lineas.single.entregaId], ['e-2']);
      expect(lista.single.agendaId, isNull);
      final hecho = await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', entregaIds: {'e-2'});
      expect([for (final e in hecho.entregadas) e.id], ['e-2']);
    });
  });

  group('QA #706 · entrega parcial y toques a la vez', () {
    test(
      'lo que queda de la cita de antes, para la hora de la otra, no deja cita fantasma',
      () async {
        final (:antes, :despues) = await dosCitas();
        // La cita de antes con dos libros: se entrega uno y el otro va a la hora de la cita nueva.
        await db
            .into(db.entregas)
            .insert(
              EntregasCompanion.insert(
                id: 'e-3',
                ventaId: 'v-39',
                productoId: 'prod-2',
                cantidad: 1,
                fechaPrevista: Value(antes),
                createdAt: t0,
                updatedAt: t0,
              ),
            );

        final hecho = await entregas.cumplir(
          'v-39',
          ahora: t1,
          idDeLaCita: 'x',
          entregaIds: {'e-1'},
          nuevaFecha: despues,
        );

        expect([for (final e in hecho.entregadas) e.id], ['e-1']);
        expect((await fila('e-3')).fechaPrevista, despues);
        expect((await cita('a-1')).estado, 'CUMPLIDA');
        expect((await cita('a-2')).estado, 'PROGRAMADA');
        expect(await citasVivasDeEntrega(), hasLength(1));
      },
    );

    test(
      'dos «Marcar entregado» a la vez sobre la misma cita entregan una vez y no tocan la otra',
      () async {
        await dosCitas();

        final r = await Future.wait([
          entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x1', agendaId: 'a-1'),
          entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x2', agendaId: 'a-1'),
        ]);

        expect(r.where((c) => c.entregadas.isNotEmpty), hasLength(1));
        expect(r.where((c) => c.yaEstaba), hasLength(1));
        expect((await fila('e-2')).pendiente, isTrue);
        expect((await cita('a-2')).estado, 'PROGRAMADA');
      },
    );

    test('dos «Entregar otro día» a la vez sobre el mismo libro dejan una sola cita', () async {
      await local.registrar(ventaDe('v-39', talonario: '0039', monto: 150000), [
        itemDe('i-v-39', 'v-39'),
      ]);
      Entrega e1() => Entrega(
        id: 'e-1',
        ventaId: 'v-39',
        productoId: 'prod-1',
        cantidad: 3,
        pendiente: true,
        fechaPrevista: t1,
        auditoria: auditoriaDe(),
      );

      await Future.wait([
        entregas.diferir(
          'v-39',
          fechaPrevista: t1,
          ahora: t0,
          filasNuevas: [e1()],
          idDeLaCita: 'a-1',
        ),
        entregas.diferir(
          'v-39',
          fechaPrevista: t1,
          ahora: t0,
          filasNuevas: [e1()],
          idDeLaCita: 'a-2',
        ),
      ]);

      expect(await citasVivasDeEntrega(), hasLength(1));
    });

    test(
      'entregar una de las dos citas deja la otra programada y entregar la otra las cierra',
      () async {
        await dosCitas();

        await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-1');
        expect((await citasVivasDeEntrega()).map((a) => a.id), ['a-2']);

        await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-2');
        expect(await citasVivasDeEntrega(), isEmpty);
      },
    );

    test('lo que sube al entregar una cita no trae datos de la persona', () async {
      await dosCitas();
      encolador.encolados.clear();

      await entregas.cumplir('v-39', ahora: t1, idDeLaCita: 'x', agendaId: 'a-1');

      final texto = encolador.encolados.map((c) => c.toString()).join();
      expect(texto, isNotEmpty);
      expect(texto, isNot(contains('Pedro')));
      expect(texto, isNot(contains('María')));
    });
  });
}
