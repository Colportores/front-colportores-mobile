// QA de la casilla «Unión rechazada» (vista 10 «Posibles duplicados», HU-UBI-006, #679), de punta a
// punta con la base real: la pantalla, el caso de uso, el repositorio, Drift en memoria con su cola de
// sync y el disparo real (`unionesRechazadasProvider`). Los tests del implementador de la pantalla usan
// ubicaciones en memoria: estos prueban que lo que la persona ve sale de lo que se guardó de verdad.
//
// Los que llevan `skip` documentan un hallazgo de QA (`QA #679: …`): el implementador saca el `skip`
// cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/datos/sync_queue_table.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/uniones_locales_table.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/pares_duplicados_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/uniones_rechazadas_providers.dart';
import 'package:drift/drift.dart' show InsertMode, OrderingTerm, Value;
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

/// `--dart-define=QA_HALLAZGOS=true` corre también los tests de los hallazgos (los que llevan `skip`).
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _ocho = Duration(seconds: 8);
final _ahora = DateTime.utc(2026, 11, 10, 9);
const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';

const _textoUb003 =
    'La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.';
const _textoGenerico =
    'No pudimos unir estas dos ubicaciones. Quedaron separadas, como estaban. Revisá el par de nuevo.';

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
Future<void> _esperarBase(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// La app de verdad vigila `unionesRechazadasProvider` desde `app.dart`: acá, desde el anfitrión.
class _Anfitrion extends ConsumerWidget {
  const _Anfitrion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(unionesRechazadasProvider);
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late EncoladorMarcarDuplicadoFalso marcador;
  late UbicacionLocalDataSourceDrift local;
  late List<Override> overrides;

  UbicacionModel ubicacion(
    String id, {
    required double metrosAlNorte,
    required DateTime creada,
    String calle = 'Av. Italia',
    String numero = '1234',
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
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

  /// A (la más vieja) y B, a 300 m con la misma dirección, cada una con su espacio único; B con dos
  /// personas, una visita y una agenda. Con [conSegundoPar], otro par (C y D) en otra calle.
  Future<void> armar(WidgetTester tester, {bool conSegundoPar = false}) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    marcador = EncoladorMarcarDuplicadoFalso();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador, marcarDuplicado: marcador);
    final repo = UbicacionRepositoryImpl(local, logger: loggerMudo());
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
      deshacedorDeUnionesProvider.overrideWithValue(local),
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
      if (conSegundoPar) {
        await local.insertar(
          ubicacion(
            'ub-c',
            metrosAlNorte: 3000,
            creada: DateTime.utc(2026, 8, 2),
            calle: 'Bulevar Artigas',
            numero: '880',
          ),
          espacio: espacio('esp-c', 'ub-c'),
        );
        await local.insertar(
          ubicacion(
            'ub-d',
            metrosAlNorte: 3300,
            creada: DateTime.utc(2026, 8, 6),
            calle: 'Bulevar Artigas',
            numero: '880',
          ),
          espacio: espacio('esp-d', 'ub-d'),
        );
        await sembrarVinculo(db, id: 'ep-d1', espacioId: 'esp-d', personaId: 'per-d1');
      }
      encolador.encolados.clear();
    });
  }

  Future<void> abrir(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('abrir')));
    await _transicion(tester);
    await _esperarBase(tester);
  }

  Future<void> montar(WidgetTester tester, {Size tamano = const Size(390, 844)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: temaClaro(), home: const _Anfitrion()),
      ),
    );
    await _esperarBase(tester, 4);
    await abrir(tester);
  }

  /// Un test con la base real: al terminar desmonta todo (Drift deja un timer al cancelar un
  /// stream), deja correr el reloj y cierra la base.
  void prueba(
    String nombre,
    Future<void> Function(WidgetTester tester) cuerpo, {
    bool conSegundoPar = false,
    String? skip,
  }) {
    testWidgets(nombre, (tester) async {
      await armar(tester, conSegundoPar: conSegundoPar);
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      await tester.runAsync(db.close);
    }, skip: skip != null && !_verHallazgos);
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await _esperarBase(tester);
  }

  /// La persona une el par [clave] (Revisar → «Conservar A y unir») y pasan los 8 s.
  Future<void> unir(WidgetTester tester, String clave) async {
    await tocar(tester, find.byKey(Key('revisar_$clave')));
    await tocar(tester, find.byKey(const Key('comparar_conservar_y_unir')));
    await tester.pump(_ocho + const Duration(seconds: 1));
    await _esperarBase(tester);
  }

  /// El motor deja el trabajo [id] en [estado] (con su [codigo]), como lo hace al recibir la respuesta.
  Future<void> marcarTrabajo(
    WidgetTester tester,
    String id,
    String estado, {
    String codigo = '',
    String rowPk = 'ub-b',
  }) async {
    await tester.runAsync(
      () => db
          .into(db.syncQueue)
          .insertOnConflictUpdate(
            SyncQueueCompanion.insert(
              id: id,
              clientOpId: 'op-$id',
              entity: 'ubicacion',
              op: 'marcar_como_duplicado',
              payload: '{}',
              rowPk: Value(rowPk),
              createdAt: _ahora,
              state: estado,
              code: Value(codigo),
            ),
          ),
    );
    await _esperarBase(tester, 14);
  }

  /// Ana sale de la pantalla y vuelve a entrar (la pantalla vuelve a leer todo desde cero).
  Future<void> reabrir(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('duplicados_volver')));
    await _transicion(tester);
    await abrir(tester);
  }

  /// El servidor rechaza el trabajo [id] y Ana vuelve a entrar a la pantalla.
  Future<void> rechazar(WidgetTester tester, String id, String codigo) async {
    await marcarTrabajo(tester, id, EstadoJob.invalid, codigo: codigo);
    await reabrir(tester);
  }

  Finder aviso(String clave) => find.byKey(Key('union_rechazada_$clave'));
  Finder par(String clave) => find.byKey(Key('par_$clave'));

  Future<String> espacioDeLaVisita(WidgetTester tester, String id) async => (await tester.runAsync(
    () async =>
        (await (db.select(db.visitas)..where((v) => v.id.equals(id))).getSingle()).espacioId,
  ))!;

  Future<bool> estaDeBaja(WidgetTester tester, String id) async => (await tester.runAsync(
    () async =>
        (await (db.select(db.ubicaciones)..where((u) => u.id.equals(id))).getSingle()).deletedAt !=
        null,
  ))!;

  Future<List<UnionLocalFila>> filasDeUnion(WidgetTester tester) async => (await tester.runAsync(
    () => (db.select(db.unionesLocales)..orderBy([(u) => OrderingTerm.asc(u.trabajoId)])).get(),
  ))!;

  group('Escenario: el servidor rechaza el trabajo (de punta a punta)', () {
    prueba(
      'dado que Ana unió A y B y el servidor rechaza con UB003, cuando Ana vuelve a entrar, el par está '
      'con el texto literal de la HU y lo de B volvió a B sin encolar nada',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        expect(par(_parItalia), findsNothing, reason: 'unido: el par sale de la lista');
        expect(await estaDeBaja(tester, 'ub-b'), isTrue);
        expect(await espacioDeLaVisita(tester, 'vis-b1'), 'esp-a');
        encolador.encolados.clear();

        await rechazar(tester, 'trabajo-1', 'UB003');

        expect(par(_parItalia), findsOneWidget, reason: 'las dos quedaron vivas: el par vuelve');
        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoUb003)),
          findsOneWidget,
        );
        expect(find.text(_textoGenerico), findsNothing);
        expect(await estaDeBaja(tester, 'ub-b'), isFalse);
        expect(await espacioDeLaVisita(tester, 'vis-b1'), 'esp-b');
        // Solo se recalcula el color (house_status) de las dos: ni espacios, ni visitas, ni agendas, ni el
        // tombstone de B suben, porque el servidor nunca aplicó la unión.
        expect(
          encolador.encolados.map((e) => e.entidad).toSet().difference({'house_status'}),
          isEmpty,
          reason: 'el servidor nunca aplicó la unión: no hay nada más que avisarle',
        );
        final filas = await filasDeUnion(tester);
        expect(filas.single.estado, EstadoUnionLocal.deshecha);
        expect(filas.single.codigoRechazo, 'UB003');
        expect(tester.takeException(), isNull);
      },
    );

    prueba(
      'dado que Ana unió A y B y sigue en la misma pantalla, cuando el servidor rechaza con UB003 (en '
      'segundos, con red), el par vuelve con su aviso sin que Ana tenga que salir y volver a entrar',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await marcarTrabajo(tester, 'trabajo-1', EstadoJob.invalid, codigo: 'UB003');

        expect(await estaDeBaja(tester, 'ub-b'), isFalse, reason: 'el teléfono sí la deshizo');
        expect(par(_parItalia), findsOneWidget);
        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoUb003)),
          findsOneWidget,
        );
      },
      skip:
          'QA #679: con la pantalla abierta desde antes de la unión, el par sigue oculto '
          '(UnionesPendientesState.ocultas) y el aviso no sale hasta salir y volver a entrar',
    );

    prueba(
      'dado un rechazo con otro código (42501), el aviso es el genérico y «Revisar» sigue abriendo el par',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);

        await rechazar(tester, 'trabajo-1', '42501');

        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoGenerico)),
          findsOneWidget,
        );
        await tocar(tester, find.byKey(const Key('revisar_$_parItalia')));
        expect(find.byKey(const Key('comparar_conservar_y_unir')), findsOneWidget);
      },
    );

    prueba(
      'dado un trabajo que quedó INVALID con la app cerrada, cuando se abre la app y la vista, el par ya '
      'está separado y con su aviso',
      (tester) async {
        // La unión se hizo y el trabajo volvió rechazado antes de que esta app arrancara.
        await tester.runAsync(() async {
          await local.unirDuplicada('ub-a', 'ub-b', ahora: _ahora);
        });
        await marcarTrabajo(tester, 'trabajo-1', EstadoJob.invalid, codigo: 'UB003');
        await montar(tester);

        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoUb003)),
          findsOneWidget,
        );
        expect(await estaDeBaja(tester, 'ub-b'), isFalse);
      },
    );

    prueba(
      'dado un trabajo en curso (PENDING, IN_FLIGHT) o hecho (DONE), cuando cambia la cola, el par no '
      'vuelve ni se toca nada',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);

        for (final estado in [EstadoJob.pending, EstadoJob.inFlight, EstadoJob.done]) {
          await marcarTrabajo(tester, 'trabajo-1', estado);
          await reabrir(tester);
          expect(par(_parItalia), findsNothing, reason: estado);
          expect(await estaDeBaja(tester, 'ub-b'), isTrue, reason: estado);
          expect(await espacioDeLaVisita(tester, 'vis-b1'), 'esp-a', reason: estado);
        }
      },
    );

    prueba(
      'dado el aviso en el par, cuando Ana sale de la pantalla y vuelve a entrar, el aviso sigue ahí '
      '(sale de lo guardado, no de la memoria)',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await rechazar(tester, 'trabajo-1', 'UB003');
        expect(aviso(_parItalia), findsOneWidget);

        await tocar(tester, find.byKey(const Key('duplicados_volver')));
        await _transicion(tester);
        expect(find.byKey(const Key('abrir')), findsOneWidget);
        await abrir(tester);

        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoUb003)),
          findsOneWidget,
        );
      },
    );

    prueba(
      'dado el aviso, cuando Ana decide «Son distintos», el par sale para siempre y el aviso se va con él',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await rechazar(tester, 'trabajo-1', 'UB003');

        await tocar(tester, find.byKey(const Key('revisar_$_parItalia')));
        await tocar(tester, find.byKey(const Key('comparar_son_distintos')));
        await _esperarBase(tester);

        expect(par(_parItalia), findsNothing);
        expect(aviso(_parItalia), findsNothing);
        expect(find.text(_textoUb003), findsNothing);
      },
    );
  });

  group('Escenario: el par se vuelve a unir después del rechazo', () {
    prueba(
      'dado el aviso, cuando Ana vuelve a unir y esa unión también vuelve rechazada con otro código, '
      'manda el último: el aviso es el del segundo rechazo',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await rechazar(tester, 'trabajo-1', 'UB003');
        expect(find.text(_textoUb003), findsOneWidget);

        await unir(tester, _parItalia);
        expect(par(_parItalia), findsNothing, reason: 'la segunda unión vale');
        expect(await estaDeBaja(tester, 'ub-b'), isTrue);

        await rechazar(tester, 'trabajo-2', 'CG001');

        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoGenerico)),
          findsOneWidget,
        );
        expect(find.text(_textoUb003), findsNothing);
        expect(await espacioDeLaVisita(tester, 'vis-b1'), 'esp-b');
        final filas = await filasDeUnion(tester);
        expect(filas.map((f) => f.estado), [EstadoUnionLocal.deshecha, EstadoUnionLocal.deshecha]);
        expect(filas.map((f) => f.codigoRechazo), ['UB003', 'CG001']);
      },
    );

    prueba(
      'dado el aviso, cuando Ana vuelve a unir y el servidor la acepta, el par no vuelve ni hay aviso, '
      'y lo de B queda en A',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await rechazar(tester, 'trabajo-1', 'UB003');
        expect(aviso(_parItalia), findsOneWidget);

        await unir(tester, _parItalia);
        await marcarTrabajo(tester, 'trabajo-2', EstadoJob.done);
        await reabrir(tester);

        expect(par(_parItalia), findsNothing);
        expect(aviso(_parItalia), findsNothing);
        expect(await estaDeBaja(tester, 'ub-b'), isTrue);
        expect(await espacioDeLaVisita(tester, 'vis-b1'), 'esp-a');
      },
    );

    prueba(
      'dado el aviso, mientras Ana tiene el «Deshacer» de la nueva unión (8 s), el par está fuera de la '
      'lista y, al tocar «Deshacer», vuelve con su aviso',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await rechazar(tester, 'trabajo-1', 'UB003');

        await tocar(tester, find.byKey(const Key('revisar_$_parItalia')));
        await tocar(tester, find.byKey(const Key('comparar_conservar_y_unir')));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Deshacer'), findsOneWidget);
        expect(par(_parItalia), findsNothing);

        await tocar(tester, find.text('Deshacer'));
        await tester.pump(_ocho);
        await _esperarBase(tester);

        expect(aviso(_parItalia), findsOneWidget);
        expect(await estaDeBaja(tester, 'ub-b'), isFalse);
        expect((await filasDeUnion(tester)).length, 1, reason: 'no se guardó una unión nueva');
      },
    );
  });

  group('Casos límite: acciones superpuestas y fallas a mitad', () {
    prueba(
      'dado dos uniones rechazadas a la vez (UB003 y 42501), cuando el motor las marca juntas, cada par '
      'vuelve con su aviso y las dos se deshacen una sola vez',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await unir(tester, _parArtigas);
        expect(find.byKey(const Key('duplicados_vacio')), findsOneWidget);

        await tester.runAsync(
          () => db.batch((b) {
            b.insertAll(db.syncQueue, [
              SyncQueueCompanion.insert(
                id: 'trabajo-1',
                clientOpId: 'op-1',
                entity: 'ubicacion',
                op: 'marcar_como_duplicado',
                payload: '{}',
                createdAt: _ahora,
                state: EstadoJob.invalid,
                code: const Value('UB003'),
              ),
              SyncQueueCompanion.insert(
                id: 'trabajo-2',
                clientOpId: 'op-2',
                entity: 'ubicacion',
                op: 'marcar_como_duplicado',
                payload: '{}',
                createdAt: _ahora,
                state: EstadoJob.invalid,
                code: const Value('42501'),
              ),
            ], mode: InsertMode.insertOrReplace);
          }),
        );
        await _esperarBase(tester, 20);
        await reabrir(tester);

        expect(
          find.descendant(of: aviso(_parItalia), matching: find.text(_textoUb003)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: aviso(_parArtigas), matching: find.text(_textoGenerico)),
          findsOneWidget,
        );
        expect(find.text('2 para revisar'), findsOneWidget);
        expect(await estaDeBaja(tester, 'ub-b'), isFalse);
        expect(await estaDeBaja(tester, 'ub-d'), isFalse);
        expect((await filasDeUnion(tester)).map((f) => f.estado).toSet(), {
          EstadoUnionLocal.deshecha,
        });
      },
      conSegundoPar: true,
    );

    prueba(
      'dado que deshacer falla a mitad (una tabla ilegible), cuando llega el rechazo, no se rompe nada: '
      'la unión queda como estaba (B de baja), sin aviso ni pantalla trabada, y la app sigue usable',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await tester.runAsync(() => db.customStatement('ALTER TABLE visita RENAME TO visita_x'));

        await rechazar(tester, 'trabajo-1', 'UB003');

        expect(tester.takeException(), isNull);
        expect(await estaDeBaja(tester, 'ub-b'), isTrue, reason: 'la transacción revirtió todo');
        expect(aviso(_parItalia), findsNothing);
        expect(find.byKey(const Key('duplicados_vacio')), findsOneWidget);
        expect((await filasDeUnion(tester)).single.estado, EstadoUnionLocal.aplicada);
        await tester.runAsync(() => db.customStatement('ALTER TABLE visita_x RENAME TO visita'));
      },
    );

    prueba(
      'dado que deshacer falló una vez, cuando la tabla vuelve y cambia la cola (otro trabajo), la unión '
      'se deshace sin esperar a reabrir la app (el comentario del provider lo promete)',
      (tester) async {
        await montar(tester);
        await unir(tester, _parItalia);
        await tester.runAsync(() => db.customStatement('ALTER TABLE visita RENAME TO visita_x'));
        await marcarTrabajo(tester, 'trabajo-1', EstadoJob.invalid, codigo: 'UB003');
        expect(aviso(_parItalia), findsNothing);
        await tester.runAsync(() => db.customStatement('ALTER TABLE visita_x RENAME TO visita'));

        // Cambia la cola con otro trabajo cualquiera (una venta que sube): la cuenta de uniones por
        // deshacer sigue siendo 1 y `observarUnionesPorDeshacer` no vuelve a emitir.
        await marcarTrabajo(tester, 'otro-trabajo', EstadoJob.pending, rowPk: 'x');
        await reabrir(tester);

        expect(aviso(_parItalia), findsOneWidget);
      },
      skip:
          'QA #679: si deshacer falla, no se reintenta hasta reabrir la app: '
          'observarUnionesPorDeshacer hace distinct() sobre la cuenta y no vuelve a emitir',
    );
  });

  group('Privacidad', () {
    prueba(
      'dado un rechazo, el log del deshacer no lleva calle, número ni texto de personas, solo ids y código',
      (tester) async {
        final lineas = <String>[];
        void oyente(OutputEvent e) => lineas.addAll(e.lines);
        Logger.addOutputListener(oyente);
        addTearDown(() => Logger.removeOutputListener(oyente));
        await montar(tester);
        await unir(tester, _parItalia);

        await rechazar(tester, 'trabajo-1', 'UB003');

        final todo = lineas.join('\n');
        for (final pii in ['Italia', '1234', 'per-b1', 'Atiende']) {
          expect(todo.contains(pii), isFalse, reason: 'el log no debe llevar «$pii»');
        }
      },
    );
  });
}
