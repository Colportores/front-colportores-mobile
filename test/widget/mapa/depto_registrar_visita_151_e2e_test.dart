// «Registrar visita» desde la ficha del depto, de punta a punta con la base real (Drift en memoria):
// la pantalla 11·04 + el flujo real de «¿Qué pasó?» (vista 39, C·06) + el estado de la última visita
// leído de la tabla `visita` (HU-VIS-005, #151).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
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
  final ayer = FormatoListaUbicaciones.diaMes(DateTime.utc(2026, 9, 20, 12));

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

  Future<List<VisitaFila>> visitas(WidgetTester tester) =>
      enBase(tester, () => db.select(db.visitas).get());

  final registrar = find.byKey(ClavesVisitaDelDepto.registrar);

  testWidgets(
    'Dado un depto sin visitas, cuando se registra «No contestó» desde su ficha, entonces la '
    'visita queda en ese depto sin persona, el estado dice «No contestó» y «Deshacer» lo devuelve',
    (tester) async {
      await montar(tester);
      expect(find.text('Sin visitas todavía'), findsOneWidget);

      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect(resultados, [true]);
      final visita = (await visitas(tester)).single;
      expect(visita.espacioId, 'esp-1');
      expect(visita.espacioPersonaId, isNull, reason: 'decisión «Sin persona»');
      expect(visita.tipoResultado, 'NO_CONTESTO');
      expect(find.text('No contestó · $hoy'), findsOneWidget);
      expect(find.text('Sin visitas todavía'), findsNothing);
      expect(find.text('CLIENTES · 0'), findsOneWidget, reason: 'sigue en la ficha del depto');

      await tester.tap(find.text('Deshacer'));
      await esperar(tester);

      expect(find.text('Sin visitas todavía'), findsOneWidget);
      expect(find.text('No contestó · $hoy'), findsNothing);
      await cerrar(tester);
    },
  );

  testWidgets(
    'Dado un depto con una entrevista hecha, cuando se registra «Rechazo» encima, entonces el '
    'estado pasa a «Rechazó» con el día nuevo: manda la última visita',
    (tester) async {
      await montar(
        tester,
        sembrar: () => insertarVisita(
          db,
          Visita(
            id: 'vis-vieja',
            espacioId: 'esp-1',
            fecha: DateTime.utc(2026, 9, 20, 12),
            tipoResultado: TipoResultadoVisita.entrevista,
            colportorId: 'col-1',
            auditoria: auditoriaDe(creada: DateTime.utc(2026, 9, 20, 12)),
          ),
        ),
      );
      expect(find.text('Entrevista hecha · $ayer'), findsOneWidget);

      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect(find.text('Rechazó · $hoy'), findsOneWidget);
      expect(find.text('Entrevista hecha · $ayer'), findsNothing);
      expect(await visitas(tester), hasLength(2), reason: 'la entrevista vieja no se toca');
      await cerrar(tester);
    },
  );

  testWidgets(
    'Dado dos registros seguidos, cuando el segundo se hace apenas termina el primero, entonces '
    'quedan las dos visitas y el estado es el del segundo',
    (tester) async {
      await montar(tester);

      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);
      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect(resultados, [true, true]);
      final guardadas = await visitas(tester);
      expect(guardadas.map((v) => v.tipoResultado), unorderedEquals(['NO_CONTESTO', 'RECHAZO']));
      expect(find.text('Rechazó · $hoy'), findsOneWidget);
      await cerrar(tester);
    },
  );

  testWidgets(
    'Dado que «¿Qué pasó?» se cierra sin elegir, cuando se vuelve a la ficha, entonces no se '
    'guardó nada y el estado sigue igual',
    (tester) async {
      await montar(tester);

      await tester.tap(registrar);
      await esperar(tester);
      await tester.tap(find.byKey(ClavesQuePaso.cancelar));
      await esperar(tester);

      expect(resultados, [false]);
      expect(await visitas(tester), isEmpty);
      expect(find.text('Sin visitas todavía'), findsOneWidget);
      await cerrar(tester);
    },
  );
}
