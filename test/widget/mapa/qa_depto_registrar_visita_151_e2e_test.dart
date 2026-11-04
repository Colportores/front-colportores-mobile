// QA de «Registrar visita» desde la ficha del depto (vista 11·04, HU-VIS-005, #151, PR #574), de punta
// a punta con la base real (Drift en memoria) y el arnés del PR: los escenarios de la HU que pasan por
// la agenda (la cita del depto se cumple o no se cumple; la visita espontánea) y el `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ultima_visita_del_espacio_drift.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/personas_del_espacio_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_visita_del_depto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';
import 'registrar_visita_arnes.dart' show renglon;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final navegador = GlobalKey<NavigatorState>();
  final resultados = <Object?>[];

  /// El día que dice el estado de una visita registrada «ahora» en estos tests (25/10, 15:00 UTC).
  final hoy = FormatoListaUbicaciones.diaMes(DateTime.utc(2026, 10, 25, 15));

  Future<T> enBase<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> montar(WidgetTester tester, {Future<void> Function()? sembrar}) async {
    resultados.clear();
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    var agendas = 0;
    final local = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      generarId: () => 'age-esp-${++agendas}',
    );
    await enBase(tester, () async {
      await sembrarEdificio(db);
      await sembrar?.call();
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var v = 0;
    var minutos = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agendaRepositoryProvider.overrideWithValue(AgendaRepositoryImpl(local)),
          generadorIdVisitaProvider.overrideWithValue(() => 'vis-${++v}'),
          relojVisitaProvider.overrideWithValue(
            () => DateTime.utc(2026, 10, 25, 15).add(Duration(minutes: minutos++)),
          ),
          personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(contextoActivo()),
          ),
          lectorUltimaVisitaDelEspacioProvider.overrideWithValue(UltimaVisitaDelEspacioDrift(db)),
          // Como `main.dart`: «¿Qué pasó?» se abre con el contexto del propio `Navigator`.
          registrarVisitaDesdeLaCasaProvider.overrideWithValue(
            (datos) async =>
                FlujoRegistrarVisita.abrir(
                  navegador.currentContext!,
                  datos,
                  colportorId: 'col-1',
                ).then((r) {
                  resultados.add(r);
                  return r;
                }),
          ),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          navigatorKey: navegador,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => PersonasDelEspacioPage.abrir(
                    context,
                    espacioId: 'esp-1',
                    colportorId: 'col-1',
                  ),
                  child: const Text('abrir depto'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir depto'));
    await esperar(tester);
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  final registrar = find.byKey(ClavesVisitaDelDepto.registrar);

  Future<List<AgendaFila>> agendas(WidgetTester tester) =>
      enBase(tester, () => db.select(db.agendas).get());

  testWidgets(
    'Dado un depto con una entrevista programada, cuando se registra «No contestó» desde su ficha, '
    'entonces la agenda pasa a NO_CUMPLIDA (escenario «Registrar NO_CONTESTO» de la HU)',
    (tester) async {
      await montar(tester, sembrar: () => insertarAgenda(db, agendaDe('age-1')));
      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      final visita = (await enBase(tester, () => db.select(db.visitas).get())).single;
      final agenda = (await agendas(tester)).singleWhere((a) => a.id == 'age-1');
      expect(agenda.estado, 'NO_CUMPLIDA');
      expect(agenda.visitaId, visita.id);
      await cerrar(tester);
    },
  );

  testWidgets(
    'Dado un depto sin agenda, cuando se registra «Rechazo» desde su ficha, entonces se crea la '
    'agenda atrasada CUMPLIDA con la visita en una sola vez (visita espontánea de la HU)',
    (tester) async {
      await montar(tester);
      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      final visitas = await enBase(tester, () => db.select(db.visitas).get());
      expect(visitas, hasLength(1));
      final as = await agendas(tester);
      expect(as, hasLength(1));
      expect(as.single.estado, 'CUMPLIDA');
      expect(as.single.visitaId, visitas.single.id);
      expect(find.text('Rechazó · $hoy'), findsOneWidget);
      await cerrar(tester);
    },
  );

  testWidgets(
    'Dado un depto, cuando se registra «Rechazo» desde su ficha, entonces la casa queda «rejected» '
    '(house_status de la HU)',
    (tester) async {
      await montar(tester);
      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      final h = await enBase(tester, () => db.select(db.houseStatuses).get());
      expect(h.single.ubicacionId, 'ub-1');
      expect(h.single.color, 'RECHAZO');
      await cerrar(tester);
    },
  );

  testWidgets(
    'Dado dos deptos del edificio, cuando se registra una visita en el 1A, entonces la ficha del 2B '
    'sigue sin estado (no se mezclan)',
    (tester) async {
      await montar(tester);
      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);
      final del2B = await enBase(
        tester,
        () => UltimaVisitaDelEspacioDrift(db).observar('esp-2').first,
      );
      expect(del2B, isNull);
      await cerrar(tester);
    },
  );
}
