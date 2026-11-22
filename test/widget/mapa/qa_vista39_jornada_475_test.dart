// QA de «la visita de la hoja de la casa lleva la jornada abierta» (HU-VIS-005, vista 39 C·06, #475,
// PR #519). Lo que no prueban los tests del PR (fakes de la agenda y de la jornada en memoria):
//
// - de punta a punta con la base real (Drift en memoria, la misma para la jornada y la agenda): la
//   fila de `visita` guarda el `jornada_id`, y el job que sube al servidor lo lleva, con y sin
//   jornada, con la jornada cerrada o de otra persona;
// - los casos límite con la base real: la jornada que se cierra mientras la hoja está abierta, la
//   falla del guardado con reintento (mismo id, jornada del momento), la lectura lenta de la jornada
//   con un doble toque, y «Cobranza» con el cobro ya hecho;
// - privacidad: el `jornada_id` es un UUID de la jornada, no un dato de la persona; nada del flujo
//   escribe en los logs.
//
// No hay vista nueva ni cambia ningún texto: no aplica el inventario de artboards ni las capturas.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source_drift.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
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

final _inicio = DateTime.utc(2026, 10, 25, 12);

JornadaModel _jornada(String id, {String colportorId = 'col-1', DateTime? inicio}) {
  final i = inicio ?? _inicio;
  return JornadaModel(
    id: id,
    colportorId: colportorId,
    inicio: i,
    auditoria: Auditoria(createdAt: i, updatedAt: i, createdBy: colportorId),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late JornadaLocalDataSourceDrift jornadas;
  final navegador = GlobalKey<NavigatorState>();
  final resultados = <bool>[];
  Completer<void>? lecturaLenta;

  Future<T> enBase<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Monta la app con la jornada y la agenda sobre la MISMA base real y abre «¿Qué pasó?» como lo hace
  /// `main.dart`, con el contexto del propio `Navigator`.
  Future<void> montar(
    WidgetTester tester, {
    Future<void> Function()? sembrar,
    bool cobrar = false,
    Size tamano = const Size(412, 915),
    DateTime? ahora,
  }) async {
    resultados.clear();
    lecturaLenta = null;
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
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var v = 0;
    var minutos = 0;
    final personas = PersonaRepositorioFalso()
      ..sembrar([clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agendaRepositoryProvider.overrideWithValue(AgendaRepositoryImpl(local)),
          jornadaLocalDataSourceProvider.overrideWithValue(
            _JornadasLentas(jornadas, () => lecturaLenta),
          ),
          generadorIdVisitaProvider.overrideWithValue(() => 'vis-${++v}'),
          relojVisitaProvider.overrideWithValue(
            () => (ahora ?? DateTime.utc(2026, 10, 25, 15)).add(Duration(minutes: minutos++)),
          ),
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaGrecia())),
          saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'pedro': 120000})),
          if (cobrar) cobrarDesdeLaCasaProvider.overrideWithValue((c) async => true),
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
    await tester.tap(find.text('registrar visita'));
    await esperar(tester);
  }

  Future<List<VisitaFila>> visitas(WidgetTester tester) =>
      enBase(tester, () => db.select(db.visitas).get());

  Iterable<Map<String, Object?>> subidas(String entidad) =>
      encolador.encolados.where((c) => c.entidad == entidad).map((c) => c.payload);

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  group('HU-VIS-005 con la base real: el jornada_id de la visita', () {
    testWidgets(
      'dado una jornada abierta en la base, cuando toco «No contestó», la fila de visita y el job de '
      'sync llevan su id',
      (tester) async {
        await montar(tester, sembrar: () => jornadas.insertar(_jornada('jor-1')));

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        expect(resultados, [true]);
        final v = (await visitas(tester)).single;
        expect(v.tipoResultado, 'NO_CONTESTO');
        expect(v.jornadaId, 'jor-1');
        final subida = subidas('visita').single;
        expect(subida['jornada_id'], 'jor-1');
        expect(subida['colportor_id'], 'col-1');
        await cerrar(tester);
      },
    );

    testWidgets('dado una jornada abierta, cuando toco «Rechazo», la visita lleva su id', (
      tester,
    ) async {
      await montar(tester, sembrar: () => jornadas.insertar(_jornada('jor-1')));

      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      final v = (await visitas(tester)).single;
      expect(v.tipoResultado, 'RECHAZO');
      expect(v.jornadaId, 'jor-1');
      expect(subidas('visita').single['jornada_id'], 'jor-1');
      await cerrar(tester);
    });

    testWidgets('dado una jornada abierta y un cobro hecho, cuando se guarda la «Cobranza», la '
        'visita lleva su id y el vínculo de la persona', (tester) async {
      await montar(tester, cobrar: true, sembrar: () => jornadas.insertar(_jornada('jor-1')));

      await tester.tap(renglon(OpcionQuePaso.cobranza));
      await esperar(tester);

      expect(resultados, [true]);
      final v = (await visitas(tester)).single;
      expect(v.tipoResultado, 'COBRANZA');
      expect(v.jornadaId, 'jor-1');
      expect(v.espacioPersonaId, 'ep-pedro');
      expect(subidas('visita').single['jornada_id'], 'jor-1');
      await cerrar(tester);
    });

    testWidgets('dado que no hay ninguna jornada, cuando toco «No contestó», la visita va sin '
        'jornada (jornada_id nulo, no inventado)', (tester) async {
      await montar(tester);

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect(resultados, [true]);
      expect((await visitas(tester)).single.jornadaId, isNull);
      expect(subidas('visita').single['jornada_id'], isNull);
      await cerrar(tester);
    });

    testWidgets(
      'dado que la jornada ya se cerró, cuando toco «Rechazo», la visita va sin jornada',
      (tester) async {
        await montar(
          tester,
          sembrar: () async {
            await jornadas.insertar(_jornada('jor-1'));
            final fin = _inicio.add(const Duration(hours: 3));
            await jornadas.finalizar(
              JornadaModel(
                id: 'jor-1',
                colportorId: 'col-1',
                inicio: _inicio,
                fin: fin,
                auditoria: Auditoria(createdAt: _inicio, updatedAt: fin, createdBy: 'col-1'),
              ),
            );
          },
        );

        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await esperar(tester);

        expect((await visitas(tester)).single.jornadaId, isNull);
        await cerrar(tester);
      },
    );

    testWidgets('dado que la única jornada abierta es de otra colportora, cuando toco «No '
        'contestó», la visita va sin jornada (nunca la ajena)', (tester) async {
      await montar(
        tester,
        sembrar: () => jornadas.insertar(_jornada('jor-ajena', colportorId: 'col-2')),
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado dos jornadas abiertas (después de un recover), cuando toco «No contestó», '
        'la visita lleva la más reciente, la misma que muestra la pantalla principal', (
      tester,
    ) async {
      await montar(
        tester,
        sembrar: () async {
          // Dos abiertas solo se llega por `recover()`: se siembran directo en la tabla.
          for (final (id, dia) in [('jor-vieja', 24), ('jor-nueva', 25)]) {
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

      expect((await visitas(tester)).single.jornadaId, 'jor-nueva');
      await cerrar(tester);
    });
  });

  group('casos límite con la base real', () {
    testWidgets('dado que la jornada se cierra con la hoja abierta, cuando toco «Rechazo», la '
        'visita va sin jornada (se lee al guardar)', (tester) async {
      await montar(tester, sembrar: () => jornadas.insertar(_jornada('jor-1')));
      final fin = _inicio.add(const Duration(hours: 1));
      await enBase(
        tester,
        () => jornadas.finalizar(
          JornadaModel(
            id: 'jor-1',
            colportorId: 'col-1',
            inicio: _inicio,
            fin: fin,
            auditoria: Auditoria(createdAt: _inicio, updatedAt: fin, createdBy: 'col-1'),
          ),
        ),
      );

      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado que la lectura de la jornada es lenta, cuando toco dos veces «No contestó», '
        'hay una sola visita con la jornada y la hoja no queda trabada', (tester) async {
      await montar(tester, sembrar: () => jornadas.insertar(_jornada('jor-1')));
      lecturaLenta = Completer<void>();

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(renglon(OpcionQuePaso.noContesto), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Guardando…'),
        findsOneWidget,
        reason: 'mientras lee, la hoja dice que guarda',
      );
      expect(await visitas(tester), isEmpty);

      lecturaLenta!.complete();
      await esperar(tester);

      expect(resultados, [true]);
      final v = await visitas(tester);
      expect(v, hasLength(1));
      expect(v.single.jornadaId, 'jor-1');
      expect(subidas('visita'), hasLength(1));
      await cerrar(tester);
    });

    testWidgets('dado que el guardado falla a mitad (la cola de sync revienta), cuando se '
        'reintenta con la base de vuelta, la hoja no queda trabada, no se duplica y lleva la '
        'jornada', (tester) async {
      await montar(tester, sembrar: () => jornadas.insertar(_jornada('jor-1')));
      encolador.fallarCon = StateError('cola llena');

      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect(resultados, isEmpty, reason: 'la hoja sigue abierta');
      expect(find.text('Guardando…'), findsNothing);
      expect(
        find.text('No pudimos guardar la visita. Probá de nuevo.'),
        findsOneWidget,
        reason: 'el aviso guía: dice qué pasó y qué hacer',
      );
      expect(await visitas(tester), isEmpty, reason: 'ni la visita ni la jornada quedan a medias');

      encolador.fallarCon = null;
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect(resultados, [true]);
      final v = (await visitas(tester)).single;
      expect(v.jornadaId, 'jor-1');
      expect(subidas('visita'), hasLength(1));
      await cerrar(tester);
    });

    testWidgets(
      'dado que se guardó una visita, cuando la jornada se cierra y se guarda otra desde la misma '
      'casa, la primera conserva su jornada y la segunda va sin jornada',
      (tester) async {
        await montar(tester, sembrar: () => jornadas.insertar(_jornada('jor-1')));
        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);
        expect(resultados, [true]);

        final fin = _inicio.add(const Duration(hours: 2));
        await enBase(
          tester,
          () => jornadas.finalizar(
            JornadaModel(
              id: 'jor-1',
              colportorId: 'col-1',
              inicio: _inicio,
              fin: fin,
              auditoria: Auditoria(createdAt: _inicio, updatedAt: fin, createdBy: 'col-1'),
            ),
          ),
        );
        await tester.tap(find.text('registrar visita'));
        await esperar(tester);
        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await esperar(tester);

        final v = await visitas(tester);
        expect(v, hasLength(2));
        final porId = {for (final f in v) f.tipoResultado: f.jornadaId};
        expect(porId, {'NO_CONTESTO': 'jor-1', 'RECHAZO': null});
        await cerrar(tester);
      },
    );
  });

  group('HU-VIS-005 (#524): la jornada que quedó abierta de otro día no es la de hoy', () {
    testWidgets('dado una jornada del 23/10 que quedó abierta, cuando el 25/10 toco «No contestó», '
        'la visita va sin jornada (jornada_id nulo, también en el job que sube)', (tester) async {
      await montar(
        tester,
        sembrar: () =>
            jornadas.insertar(_jornada('jor-ayer', inicio: DateTime.utc(2026, 10, 23, 12))),
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect(resultados, [true]);
      expect((await visitas(tester)).single.jornadaId, isNull);
      expect(subidas('visita').single['jornada_id'], isNull);
      await cerrar(tester);
    });

    testWidgets('dado una jornada que quedó abierta, cuando toco «Rechazo», la visita va sin '
        'jornada', (tester) async {
      await montar(
        tester,
        sembrar: () =>
            jornadas.insertar(_jornada('jor-ayer', inicio: DateTime.utc(2026, 10, 23, 12))),
      );

      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado una jornada que quedó abierta y un cobro hecho, la «Cobranza» va sin '
        'jornada', (tester) async {
      await montar(
        tester,
        cobrar: true,
        sembrar: () =>
            jornadas.insertar(_jornada('jor-ayer', inicio: DateTime.utc(2026, 10, 23, 12))),
      );

      await tester.tap(renglon(OpcionQuePaso.cobranza));
      await esperar(tester);

      final v = (await visitas(tester)).single;
      expect(v.tipoResultado, 'COBRANZA');
      expect(v.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado una jornada de las 23:30 y son las 00:10, todavía es la de hoy (ahora − 30 '
        'min cae en el día del inicio) y la visita la lleva', (tester) async {
      await montar(
        tester,
        ahora: DateTime(2026, 10, 25, 0, 10),
        sembrar: () =>
            jornadas.insertar(_jornada('jor-noche', inicio: DateTime(2026, 10, 24, 23, 30))),
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, 'jor-noche');
      await cerrar(tester);
    });

    testWidgets('dado una jornada de las 23:30 y son las 00:40, ya quedó abierta de otro día y la '
        'visita va sin jornada', (tester) async {
      await montar(
        tester,
        ahora: DateTime(2026, 10, 25, 0, 40),
        sembrar: () =>
            jornadas.insertar(_jornada('jor-noche', inicio: DateTime(2026, 10, 24, 23, 30))),
      );

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);

      expect((await visitas(tester)).single.jornadaId, isNull);
      await cerrar(tester);
    });

    testWidgets('dado que la colportora cierra la vieja y empieza la de hoy, las visitas '
        'siguientes llevan la nueva y la primera sigue sin jornada', (tester) async {
      await montar(
        tester,
        sembrar: () =>
            jornadas.insertar(_jornada('jor-ayer', inicio: DateTime.utc(2026, 10, 23, 12))),
      );
      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await esperar(tester);
      expect(resultados, [true]);

      final fin = DateTime.utc(2026, 10, 23, 18);
      await enBase(tester, () async {
        await jornadas.finalizar(
          JornadaModel(
            id: 'jor-ayer',
            colportorId: 'col-1',
            inicio: DateTime.utc(2026, 10, 23, 12),
            fin: fin,
            auditoria: Auditoria(
              createdAt: DateTime.utc(2026, 10, 23, 12),
              updatedAt: fin,
              createdBy: 'col-1',
            ),
          ),
        );
        await jornadas.insertar(_jornada('jor-hoy', inicio: DateTime.utc(2026, 10, 25, 14)));
      });
      await tester.tap(find.text('registrar visita'));
      await esperar(tester);
      await tester.tap(renglon(OpcionQuePaso.rechazo));
      await esperar(tester);

      final porTipo = {for (final f in await visitas(tester)) f.tipoResultado: f.jornadaId};
      expect(porTipo, {'NO_CONTESTO': null, 'RECHAZO': 'jor-hoy'});
      await cerrar(tester);
    });

    testWidgets('dado una jornada que quedó abierta y un guardado lento, cuando toco dos veces '
        '«No contestó», hay una sola visita sin jornada y la hoja no queda trabada', (
      tester,
    ) async {
      await montar(
        tester,
        sembrar: () =>
            jornadas.insertar(_jornada('jor-ayer', inicio: DateTime.utc(2026, 10, 23, 12))),
      );
      final compuerta = lecturaLenta = Completer<void>();

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(renglon(OpcionQuePaso.noContesto), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      compuerta.complete();
      await esperar(tester);

      final v = await visitas(tester);
      expect(v, hasLength(1));
      expect(v.single.jornadaId, isNull);
      expect(resultados, [true]);
      await cerrar(tester);
    });
  });
}

/// La jornada local real con una compuerta: mientras [_compuerta] devuelve un `Completer`, leer la
/// jornada activa espera a que se complete (una lectura lenta del disco).
final class _JornadasLentas implements JornadaLocalDataSource {
  _JornadasLentas(this._dentro, this._compuerta);

  final JornadaLocalDataSourceDrift _dentro;
  final Completer<void>? Function() _compuerta;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    final c = _compuerta();
    if (c != null) await c.future;
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
