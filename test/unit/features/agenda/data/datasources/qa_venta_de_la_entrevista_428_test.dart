// QA de #428: «Sí, registrar la venta» contra las tablas reales (AppDatabase en memoria). La visita
// `VENTA` y la venta se guardan en UNA transacción: si la venta no se completa (R44) no queda ni la
// visita, ni la cola de sync, ni el color de la casa.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cerrar_entrevista_con_venta_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaLocalDataSourceDrift agenda;
  late VentaLocalDataSourceDrift ventas;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final updater = HouseStatusUpdaterDrift(db, encolador: encolador);
    var n = 0;
    agenda = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: updater,
      generarId: () => 'age-esp-${++n}',
    );
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: updater);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<List<VisitaFila>> visitas() => db.select(db.visitas).get();
  Future<List<VentaFila>> filasDeVentas() => db.select(db.ventas).get();
  Future<List<HouseStatusFila>> casas() => db.select(db.houseStatuses).get();
  Future<List<AgendaFila>> agendas() => db.select(db.agendas).get();
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  Future<void> guardarVisita() async {
    await agenda.registrarVisita(visitaDe('vis-1', resultado: TipoResultadoVisita.venta));
  }

  group('la visita VENTA y la venta, en una sola transacción', () {
    test('dado que la venta se guarda, la visita queda VENTA, la venta lleva su id y la casa se '
        'pinta', () async {
      await ventas.registrar(ventaDe('v-1', visitaId: 'vis-1'), [
        itemDe('i-1', 'v-1'),
      ], antesDeGuardar: guardarVisita);

      final visita = (await visitas()).single;
      expect(visita.tipoResultado, 'VENTA');
      expect((await filasDeVentas()).single.visitaId, 'vis-1');
      final c = cola();
      expect(
        c.indexOf('visita:insert'),
        lessThan(c.indexOf('venta:insert')),
        reason: 'el servidor necesita la visita antes que la venta (FK)',
      );
      expect((await casas()).single.color, 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test(
      'dado que la visita no se puede guardar, no queda ni la venta ni nada en la cola',
      () async {
        await expectLater(
          ventas.registrar(
            ventaDe('v-1', visitaId: 'vis-1'),
            [itemDe('i-1', 'v-1')],
            antesDeGuardar: () => throw const VisitaDeLaVentaNoGuardada(FailureInesperado()),
          ),
          throwsA(isA<VisitaDeLaVentaNoGuardada>()),
        );

        expect(await visitas(), isEmpty);
        expect(await filasDeVentas(), isEmpty);
        expect(await agendas(), isEmpty);
        expect(cola(), isEmpty);
        expect(await casas(), isEmpty);
      },
    );

    test(
      'dado que la venta falla DESPUÉS de guardar la visita, la visita se revierte (R44)',
      () async {
        await expectLater(
          ventas.registrar(
            ventaDe('v-1', visitaId: 'vis-1'),
            [itemDe('i-1', 'v-1')],
            antesDeGuardar: () async {
              await guardarVisita();
              // Desde acá, encolar la venta falla: la transacción entera se deshace.
              encolador.fallarCon = StateError('disco lleno');
            },
          ),
          throwsA(isA<StateError>()),
        );

        expect(await visitas(), isEmpty, reason: 'sin venta no hay visita VENTA');
        expect(await filasDeVentas(), isEmpty);
        expect(await agendas(), isEmpty);
        expect(await casas(), isEmpty);
      },
    );

    test('dado un reintento tras la falla, queda una sola visita y una sola venta', () async {
      await expectLater(
        ventas.registrar(
          ventaDe('v-1', visitaId: 'vis-1'),
          [itemDe('i-1', 'v-1')],
          antesDeGuardar: () async {
            await guardarVisita();
            encolador.fallarCon = StateError('disco lleno');
          },
        ),
        throwsA(isA<StateError>()),
      );
      encolador.fallarCon = null;

      for (var i = 0; i < 2; i++) {
        await ventas.registrar(ventaDe('v-1', visitaId: 'vis-1'), [
          itemDe('i-1', 'v-1'),
        ], antesDeGuardar: guardarVisita);
      }

      expect(await visitas(), hasLength(1));
      expect(await filasDeVentas(), hasLength(1));
    });

    test('dado el talonario repetido, la visita VENTA no se guarda', () async {
      await ventas.registrar(ventaDe('v-0'), [itemDe('i-0', 'v-0')]);
      final antes = cola().length;

      await expectLater(
        ventas.registrar(ventaDe('v-1', visitaId: 'vis-1'), [
          itemDe('i-1', 'v-1'),
        ], antesDeGuardar: guardarVisita),
        throwsA(anything),
      );

      expect(await visitas(), isEmpty);
      expect(cola(), hasLength(antes));
    });
  });

  group('privacidad', () {
    test('el toString de la venta de la entrevista no deja salir la nota ni el nombre', () {
      const venta = VentaDeLaEntrevista(
        espacioId: 'esp-1',
        espacioPersonaId: 'ep-1',
        colportorId: 'col-1',
        visita: RegistrarResultadoVisitaParams(
          ids: IdsResultadoVisita(visita: 'vis-1', nota: 'nota-1'),
          espacioId: 'esp-1',
          espacioPersonaId: 'ep-1',
          colportorId: 'col-1',
          resultado: TipoResultadoVisita.venta,
          nota: 'volver con la esposa de Pedro Gómez',
        ),
      );

      expect('$venta', isNot(contains('esposa')));
      expect('$venta', isNot(contains('Pedro')));
      expect(
        '${const VisitaDeLaVentaNoGuardada(FailureInesperado(causa: 'Pedro Gómez'))}',
        isNot(contains('Pedro')),
      );
    });
  });
}
