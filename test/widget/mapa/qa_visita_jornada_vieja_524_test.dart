// QA de «la visita de hoy va sin jornada si la abierta quedó de otro día» (HU-VIS-005, #524, PR #607).
// Sin vista nueva ni texto nuevo: no aplica el inventario de artboards ni las capturas. Lo que no
// prueban los tests del PR (que fijan 2 horas y 3 resultados):
//
// - la frontera del criterio (ahora − 30 min) minuto a minuto, contra el caso de uso REAL de
//   «Finalizar jornada»: la visita va sin jornada si y solo si la app le pide corregir la hora de fin
//   (un solo criterio de «quedó abierta», HU-JOR-002);
// - reloj atrasado (inicio posterior a ahora), jornada de hace muchos días, dos abiertas (las dos
//   viejas / una vieja y la de hoy);
// - falla a mitad del guardado con jornada vieja (la hoja no queda trabada, una sola visita, sin
//   jornada), la lectura de la jornada que revienta, y el umbral que se cruza entre dos visitas.
//
// Las horas se arman con `DateTime(...)` locales: el resultado no depende del huso del contenedor.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source_drift.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/jornada_repository_impl.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/finalizar_jornada_use_case.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart';
import 'registrar_visita_arnes.dart';

JornadaModel _jornada(String id, DateTime inicio, {String colportorId = 'col-1'}) => JornadaModel(
  id: id,
  colportorId: colportorId,
  inicio: inicio,
  auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: colportorId),
);

final class _SinBackup implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late JornadaLocalDataSourceDrift jornadas;
  final navegador = GlobalKey<NavigatorState>();
  final resultados = <bool>[];
  var ahora = DateTime(2026, 10, 25, 15);
  var lecturaFalla = false;

  Future<T> enBase<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> abrirHoja(WidgetTester tester) async {
    await tester.tap(find.text('registrar visita'));
    await esperar(tester);
  }

  Future<void> montar(
    WidgetTester tester, {
    required DateTime reloj,
    Future<void> Function()? sembrar,
  }) async {
    resultados.clear();
    ahora = reloj;
    lecturaFalla = false;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    jornadas = JornadaLocalDataSourceDrift(db, encolador: encolador);
    final local = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await enBase(tester, () async {
      await sembrarCasa(db);
      await sembrarVinculo(db, id: 'ep-pedro', personaId: 'pedro');
      await sembrar?.call();
      encolador.encolados.clear();
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var v = 0;
    final personas = PersonaRepositorioFalso()
      ..sembrar([clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agendaRepositoryProvider.overrideWithValue(AgendaRepositoryImpl(local)),
          jornadaLocalDataSourceProvider.overrideWithValue(
            _JornadasQueFallan(jornadas, () => lecturaFalla),
          ),
          generadorIdVisitaProvider.overrideWithValue(() => 'vis-${++v}'),
          relojVisitaProvider.overrideWithValue(() => ahora),
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaGrecia())),
          saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'pedro': 120000})),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          navigatorKey: navegador,
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  resultados.add(
                    await FlujoRegistrarVisita.abrir(navegador.currentContext!, (
                      ubicacionId: 'ub-1',
                      espacioId: 'esp-1',
                      agendaId: null,
                    ), colportorId: 'col-1'),
                  );
                },
                child: const Text('registrar visita'),
              ),
            ),
          ),
        ),
      ),
    );
    await abrirHoja(tester);
  }

  Future<List<VisitaFila>> visitas(WidgetTester tester) =>
      enBase(tester, () => db.select(db.visitas).get());

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  group('la frontera de «quedó abierta» (ahora − 30 min), contra «Finalizar jornada»', () {
    // Jornada del 24/10 a las 23:59. A las 00:29 todavía cuenta como de hoy (ahora − 30 min = 23:59);
    // desde las 00:30 ya no.
    final inicio = DateTime(2026, 10, 24, 23, 59);
    for (final (hora, minuto, deHoy) in [
      (0, 0, true),
      (0, 20, true),
      (0, 29, true),
      (0, 30, false),
      (0, 31, false),
      (9, 0, false),
    ]) {
      testWidgets('dado una jornada de las 23:59 y son las ${hora.toString().padLeft(2, '0')}:'
          '${minuto.toString().padLeft(2, '0')}, la visita ${deHoy ? 'lleva' : 'va sin'} jornada y '
          'coincide con lo que haría «Finalizar jornada»', (tester) async {
        final reloj = DateTime(2026, 10, 25, hora, minuto);
        await montar(
          tester,
          reloj: reloj,
          sembrar: () => jornadas.insertar(_jornada('jor-n', inicio)),
        );

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        expect(resultados, [true]);
        final v = (await visitas(tester)).single;
        expect(v.jornadaId, deHoy ? 'jor-n' : isNull);

        // El mismo instante, con el caso de uso real de finalizar: pide corregir si y solo si la
        // visita fue sin jornada.
        final repo = JornadaRepositoryImpl(jornadas);
        final finalizar = FinalizarJornadaUseCase(repo, _SinBackup(), ahora: () => reloj);
        final r = await enBase(
          tester,
          () => finalizar(const FinalizarJornadaParams(colportorId: 'col-1')),
        );
        final pideCorregir = r.fold((f) => f is FailureJornadaDeDiaAnterior, (_) => false);
        expect(
          pideCorregir,
          !deHoy,
          reason: 'un solo criterio de «jornada que quedó abierta» (HU-JOR-002 / #326)',
        );
        await cerrar(tester);
      });
    }
  });

  group('datos límite de la jornada', () {
    testWidgets(
      'dado que el reloj del teléfono quedó ANTES del inicio de la jornada (lo atrasaron), '
      'la visita lleva la jornada: no es de otro día y no se inventa que lo sea',
      (tester) async {
        await montar(
          tester,
          reloj: DateTime(2026, 10, 25, 10),
          sembrar: () => jornadas.insertar(_jornada('jor-futura', DateTime(2026, 10, 25, 12))),
        );

        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await esperar(tester);

        expect((await visitas(tester)).single.jornadaId, 'jor-futura');
        await cerrar(tester);
      },
    );

    testWidgets(
      'dado que el reloj quedó en un día ANTERIOR al inicio de la jornada, la visita lleva '
      'la jornada',
      (tester) async {
        await montar(
          tester,
          reloj: DateTime(2026, 10, 20, 10),
          sembrar: () => jornadas.insertar(_jornada('jor-futura', DateTime(2026, 10, 25, 12))),
        );

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        expect((await visitas(tester)).single.jornadaId, 'jor-futura');
        await cerrar(tester);
      },
    );

    testWidgets('dado una jornada que quedó abierta hace 40 días, la visita va sin jornada', (
      tester,
    ) async {
      await montar(
        tester,
        reloj: DateTime(2026, 10, 25, 15),
        sembrar: () => jornadas.insertar(_jornada('jor-vieja', DateTime(2026, 9, 15, 9))),
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado dos jornadas abiertas y las dos viejas, la visita va sin jornada', (
      tester,
    ) async {
      await montar(
        tester,
        reloj: DateTime(2026, 10, 25, 15),
        sembrar: () async {
          for (final (id, dia) in [('jor-a', 22), ('jor-b', 23)]) {
            final i = DateTime.utc(2026, 10, dia, 12);
            await db
                .into(db.jornadas)
                .insert(
                  JornadasCompanion.insert(
                    id: id,
                    colportorId: 'col-1',
                    inicio: i,
                    createdAt: i,
                    updatedAt: i,
                  ),
                );
          }
        },
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado dos jornadas abiertas, una vieja y la de hoy, la visita lleva la de hoy', (
      tester,
    ) async {
      await montar(
        tester,
        reloj: DateTime(2026, 10, 25, 15),
        sembrar: () async {
          for (final (id, i) in [
            ('jor-vieja', DateTime(2026, 10, 23, 12)),
            ('jor-hoy', DateTime(2026, 10, 25, 9)),
          ]) {
            await db
                .into(db.jornadas)
                .insert(
                  JornadasCompanion.insert(
                    id: id,
                    colportorId: 'col-1',
                    inicio: i,
                    createdAt: i,
                    updatedAt: i,
                  ),
                );
          }
        },
      );

      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, 'jor-hoy');
      await cerrar(tester);
    });

    testWidgets('dado que leer la jornada revienta, la visita se guarda igual, sin jornada', (
      tester,
    ) async {
      await montar(
        tester,
        reloj: DateTime(2026, 10, 25, 15),
        sembrar: () => jornadas.insertar(_jornada('jor-hoy', DateTime(2026, 10, 25, 9))),
      );
      lecturaFalla = true;

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect(resultados, [true]);
      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });
  });

  group('casos límite del flujo con la jornada vieja', () {
    testWidgets('dado que el guardado falla a mitad con una jornada vieja, la hoja no queda '
        'trabada, el aviso guía y el reintento guarda UNA visita sin jornada', (tester) async {
      await montar(
        tester,
        reloj: DateTime(2026, 10, 25, 15),
        sembrar: () => jornadas.insertar(_jornada('jor-ayer', DateTime(2026, 10, 23, 12))),
      );
      encolador.fallarCon = StateError('cola llena');

      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect(resultados, isEmpty, reason: 'la hoja sigue abierta');
      expect(find.text('Guardando…'), findsNothing);
      expect(find.text('No pudimos guardar la visita. Probá de nuevo.'), findsOneWidget);
      expect(await visitas(tester), isEmpty);

      encolador.fallarCon = null;
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect(resultados, [true]);
      final v = await visitas(tester);
      expect(v, hasLength(1));
      expect(v.single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets(
      'dado que entre dos visitas el reloj cruza el borde (00:20 → 00:40), la primera lleva '
      'la jornada de las 23:30 y la segunda va sin jornada',
      (tester) async {
        await montar(
          tester,
          reloj: DateTime(2026, 10, 25, 0, 20),
          sembrar: () => jornadas.insertar(_jornada('jor-noche', DateTime(2026, 10, 24, 23, 30))),
        );
        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        ahora = DateTime(2026, 10, 25, 0, 40);
        await abrirHoja(tester);
        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await esperar(tester);

        final porTipo = {for (final f in await visitas(tester)) f.tipoResultado: f.jornadaId};
        expect(porTipo, {'NO_CONTESTO': 'jor-noche', 'RECHAZO': null});
        await cerrar(tester);
      },
    );

    testWidgets('dado que la colportora cierra la jornada vieja y no empieza otra, las visitas '
        'siguientes van sin jornada (no se inventa una)', (tester) async {
      await montar(
        tester,
        reloj: DateTime(2026, 10, 25, 15),
        sembrar: () => jornadas.insertar(_jornada('jor-ayer', DateTime(2026, 10, 23, 12))),
      );
      final fin = DateTime.utc(2026, 10, 23, 18);
      await enBase(
        tester,
        () => jornadas.finalizar(
          JornadaModel(
            id: 'jor-ayer',
            colportorId: 'col-1',
            inicio: DateTime(2026, 10, 23, 12),
            fin: fin,
            auditoria: Auditoria(
              createdAt: DateTime(2026, 10, 23, 12),
              updatedAt: fin,
              createdBy: 'col-1',
            ),
          ),
        ),
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });
  });
}

/// La jornada local real; con [_falla] en `true`, leer la activa revienta.
final class _JornadasQueFallan implements JornadaLocalDataSource {
  _JornadasQueFallan(this._dentro, this._falla);

  final JornadaLocalDataSourceDrift _dentro;
  final bool Function() _falla;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    if (_falla()) throw StateError('disco ilegible');
    return _dentro.obtenerActiva(colportorId);
  }

  @override
  Future<void> insertar(JornadaModel jornada) => _dentro.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) => _dentro.finalizar(jornada);

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) =>
      _dentro.siguienteA(colportorId: colportorId, inicio: inicio);
}
