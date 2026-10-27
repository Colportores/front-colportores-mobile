// HU-UBI-006 (paraguas #138) de punta a punta con la base real: la pantalla «Posibles duplicados»
// (vista 10), el caso de uso, el repositorio y Drift en memoria con la cola de sync. Los tests de la
// pantalla (`posibles_duplicados_page_test`) usan ubicaciones en memoria y los de Drift
// (`union_pasa_lo_que_cuelga_138_drift_test`) no tienen pantalla: estos prueban que, tocando, la
// persona ve lo que promete la HU y que en el teléfono no cambia nada antes de los 8 s ni se pierde
// nada después. Los escenarios llevan el título de la HU.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/pares_duplicados_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/campo_falsos.dart';
import '../../helpers/duplicados_falsos.dart';
import '../../helpers/logger_mudo.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

const _ocho = Duration(seconds: 8);
final _ahora = DateTime.utc(2026, 10, 27, 9);

/// Deja pasar la transición de página (hasta 800 ms) y lo que se dispara al terminar.
Future<void> _transicion(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pump(const Duration(seconds: 1));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Espera a la base real (que no avanza con el reloj falso del test) y repinta.
Future<void> _esperarBase(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late EncoladorMarcarDuplicadoFalso marcador;
  late UbicacionLocalDataSourceDrift local;
  late List<Override> overrides;

  UbicacionModel ubicacion(String id, {required double metrosAlNorte, required DateTime creada}) =>
      UbicacionModel(
        id: id,
        tipo: TipoUbicacion.casa,
        calle: 'Av. Italia',
        numero: '1234',
        lat: -34.891 + metrosAlNorte / 111195.08,
        lon: -56.125,
        ciudadId: 'mvd',
        auditoria: Auditoria(createdAt: creada, updatedAt: creada, createdBy: 'col-1'),
      );

  EspacioModel espacio(String id, String ubicacionId) => EspacioModel(
    id: id,
    ubicacionId: ubicacionId,
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  /// A (la más vieja) y B, a 300 m con la misma dirección; las dos con su espacio único. B con dos
  /// personas, una visita y una agenda.
  Future<void> armar(WidgetTester tester) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    marcador = EncoladorMarcarDuplicadoFalso();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador, marcarDuplicado: marcador);
    final repo = UbicacionRepositoryImpl(local, logger: AppLogger(output: _SalidaEnMemoria()));
    final pares = ParesDuplicadosRepositoryImpl(
      ParesDuplicadosLocalDataSourceDrift(db),
      logger: loggerMudo(),
    );
    overrides = [
      ...overridesAlta(repo: repo, ahora: _ahora),
      paresDuplicadosRepositoryProvider.overrideWithValue(pares),
      paresParaRevisarProvider.overrideWith(
        (ref, colportorId) => ref.watch(observarParesDuplicadosUseCaseProvider)(colportorId),
      ),
    ];
    await tester.runAsync(() async {
      await local.insertar(
        ubicacion('ub-a', metrosAlNorte: 0, creada: DateTime.utc(2026, 8, 1)),
        espacio: espacio('esp-a', 'ub-a'),
      );
      await local.insertar(
        ubicacion('ub-b', metrosAlNorte: 300, creada: DateTime.utc(2026, 8, 5)),
        espacio: espacio('esp-b', 'ub-b'),
      );
      await sembrarVinculo(db, id: 'ep-a1', espacioId: 'esp-a', personaId: 'per-a1');
      await sembrarVinculo(db, id: 'ep-b1', espacioId: 'esp-b', personaId: 'per-b1');
      await sembrarVinculo(db, id: 'ep-b2', espacioId: 'esp-b', personaId: 'per-b2');
      await insertarVisita(
        db,
        visitaDe(
          'vis-b1',
          espacio: 'esp-b',
          vinculo: 'ep-b1',
          resultado: TipoResultadoVisita.entrevista,
        ),
      );
      await insertarAgenda(db, agendaDe('ag-b1', espacio: 'esp-b', vinculo: 'ep-b2'));
      encolador.encolados.clear();
    });
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: temaClaro(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () =>
                      unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('abrir')));
    await _transicion(tester);
    await _esperarBase(tester);
  }

  /// Un test con la base real: al terminar desmonta todo (Drift deja un timer al cancelar un
  /// stream), deja correr el reloj y cierra la base.
  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      await armar(tester);
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      await tester.runAsync(db.close);
    });
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await _esperarBase(tester);
  }

  Future<void> revisarYUnir(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('revisar_ub-a|ub-b')));
    await tocar(tester, find.byKey(const Key('comparar_conservar_y_unir')));
  }

  Future<Map<String, String>> visitas(WidgetTester tester) async => (await tester.runAsync(
    () async => {for (final v in await db.select(db.visitas).get()) v.id: v.espacioId},
  ))!;

  Future<bool> bDeBaja(WidgetTester tester) async =>
      (await tester.runAsync(() async => (await local.obtener('ub-b'))!.auditoria.estaBorrada))!;

  group('Escenario: Marcar como duplicado y conservar A (de punta a punta)', () {
    prueba('dado un par con lo de B colgando de su espacio, cuando toco «Conservar A y unir», en '
        'esos 8 s no cambia nada, y pasados los 8 s todo pasa a A, B queda de baja y el par '
        'sale de la lista', (tester) async {
      await montar(tester);
      expect(find.byKey(const Key('revisar_ub-a|ub-b')), findsOneWidget);

      await revisarYUnir(tester);
      await tester.pump(_ocho - const Duration(seconds: 1));
      await _esperarBase(tester);

      expect(find.text('Deshacer'), findsOneWidget);
      expect(await visitas(tester), {'vis-b1': 'esp-b'}, reason: 'antes de los 8 s no cambia nada');
      expect(await bDeBaja(tester), isFalse);
      expect(encolador.encolados, isEmpty);
      expect(marcador.encolados, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await _esperarBase(tester);

      expect(await visitas(tester), {'vis-b1': 'esp-a'});
      final vinculos = (await tester.runAsync(
        () async => {for (final v in await db.select(db.espacioPersonas).get()) v.id: v.espacioId},
      ))!;
      expect(vinculos, {'ep-a1': 'esp-a', 'ep-b1': 'esp-a', 'ep-b2': 'esp-a'});
      expect(await bDeBaja(tester), isTrue);
      expect(marcador.encolados, [(duplicadaId: 'ub-b', conservadaId: 'ub-a')]);
      expect(find.byKey(const Key('revisar_ub-a|ub-b')), findsNothing);
      final casa = (await tester.runAsync(
        () => (db.select(db.houseStatuses)..where((h) => h.ubicacionId.equals('ub-a'))).getSingle(),
      ))!;
      expect(
        casa.color,
        'ENTREVISTA_PROGRAMADA',
        reason: 'A se recalcula con la agenda y la entrevista que vinieron de B (3 gana a 5)',
      );
    });

    prueba(
      'dado que toqué «Conservar A y unir», cuando toco «Deshacer» antes de los 8 s, no cambia '
      'nada en la base ni en la cola y el par sigue en la lista',
      (tester) async {
        await montar(tester);
        await revisarYUnir(tester);
        await tester.pump(const Duration(seconds: 3));

        await tocar(tester, find.text('Deshacer'));
        await tester.pump(_ocho);
        await _esperarBase(tester);

        expect(await visitas(tester), {'vis-b1': 'esp-b'});
        expect(await bDeBaja(tester), isFalse);
        expect(encolador.encolados, isEmpty);
        expect(marcador.encolados, isEmpty);
        expect(find.byKey(const Key('revisar_ub-a|ub-b')), findsOneWidget);
      },
    );

    prueba('dado que el trabajo «marcar como duplicado» no se puede encolar, cuando pasan los 8 s, '
        'la unión no se hace, B sigue viva y nada de lo suyo se mueve', (tester) async {
      marcador.fallarCon = StateError('sin motor');
      await montar(tester);

      await revisarYUnir(tester);
      await tester.pump(_ocho);
      await _esperarBase(tester);

      expect(await visitas(tester), {'vis-b1': 'esp-b'});
      expect(await bDeBaja(tester), isFalse);
      expect(
        (await tester.runAsync(() => db.select(db.houseStatuses).get()))!,
        isEmpty,
        reason: 'ni el color de A quedó recalculado a medias',
      );
      expect(find.byKey(const Key('revisar_ub-a|ub-b')), findsOneWidget);
    });
  });
}
