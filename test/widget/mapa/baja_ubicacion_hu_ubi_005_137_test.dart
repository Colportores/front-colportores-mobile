// HU-UBI-005 «Baja de ubicación (soft delete)» (paraguas #137): los escenarios de baja y los casos
// borde de la HU recorridos de punta a punta. La pantalla «Editar ubicación» real, la hoja de baja
// real, los casos de uso reales, el repositorio real y la base real (Drift en memoria), con la cola
// del sync en memoria (no sube nada). Afuera queda lo que no existe en `flutter test` (GPS,
// geocodificador, vista nativa del mapa, ciudades) y el consultor de lo pendiente de la casa
// (visitas, ventas, cobranzas), cuya fuente real es #330: acá se le dice qué sabe el teléfono.
//
// Los tests de widget con un repositorio falso (`modificar_ubicacion_page_test.dart`, `hoja_baja_test.dart`,
// `qa_vista09_baja_205_test.dart`) fijan la pantalla, y los de datos (`ubicacion_baja_drift_test.dart`)
// la base; este archivo fija que las dos mitades se entienden: lo que el colportor toca es lo que
// queda en el teléfono, en la auditoría local y en la cola.
//
// Los escenarios de reactivar («Reactivación», «Reactivación con la ciudad fuera del catálogo»,
// «Reactivar choca con otra casa activa», «Una baja por duplicado no se reactiva» y «Deshacer una
// reactivación») ya los recorre con la base real `qa_vista09_reactivar_334_e2e_test.dart`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_ubicacion_providers.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' show LogOutput, OutputEvent;

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/baja_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

/// El instante en que se toca «Dar de baja» (el reloj de la app): `deleted_at` y `updated_at` de la
/// baja valen esto, con milisegundos.
final _ahora = DateTime.utc(2026, 10, 27, 15, 0, 0, 456);

/// Cuando se creó y se editó la casa por última vez.
final _antes = DateTime.utc(2026, 10, 21, 13, 45, 10, 123);

const _avisoBloqueo =
    'No podés dar de baja esta casa porque tiene ventas o visitas de otro colportor. '
    'Si ya no existe, avisale a tu coordinador.';
const _avisoDosVisitas =
    'Esta ubicación tiene 2 visitas pendientes. Si la das de baja, no podrás registrar nuevas '
    'visitas, pero el historial se conserva.';
const _avisoCambioReciente =
    'Esta ubicación cambió recién. Abrila de nuevo y volvé a darla de baja.';
const _noPudimosRevisar = 'No pudimos revisar la ubicación. Probá de nuevo.';
const _noPudimosDarDeBaja = 'No pudimos dar de baja la ubicación. Probá de nuevo.';

final class _Logs extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// La pantalla que abre la edición y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

  final List<SalidaModificarUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async => salidas.add(
          await ModificarUbicacionPage.abrir(context, colportorId: 'col-1', ubicacionId: 'ubi-1'),
        ),
        child: const Text('abrir'),
      ),
    ),
  );
}

/// El teléfono del colportor `col-1`.
final class _Telefono {
  _Telefono() {
    db = AppDatabase(NativeDatabase.memory(), logger: AppLogger(output: logs));
    local = UbicacionLocalDataSourceDrift(db, encolador: cola);
    repo = UbicacionRepositoryImpl(local, logger: AppLogger(output: logs));
  }

  final cola = EncoladorSyncEnMemoria();
  final logs = _Logs();
  final pendientes = PendientesFalso();
  final mapa = FabricaMapaFalsa();
  final salidas = <SalidaModificarUbicacion?>[];
  late final AppDatabase db;
  late final UbicacionLocalDataSourceDrift local;
  late final UbicacionRepositoryImpl repo;
}

/// La base real no avanza con el reloj falso del test: se le da tiempo real y se bombea.
Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await _traer(tester, f);
  await tester.tap(f);
  await _asentar(tester);
}

/// El teléfono del test en curso: [prueba] lo desmonta y cierra su base al terminar.
_Telefono? _abierto;

/// Un test de la edición con la base real: al terminar desmonta la pantalla (Drift deja un timer al
/// cancelar el stream de los espacios, y el árbol tiene que estar desmontado antes de que el test
/// verifique los timers) y cierra la base.
void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(nombre, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    final t = _abierto;
    if (t != null) await tester.runAsync(t.db.close);
    _abierto = null;
  });
}

/// Monta el teléfono con una casa (o la que se pida) y la pantalla anfitriona; abre la edición.
Future<_Telefono> _montar(
  WidgetTester tester, {
  String calle = 'Av. Italia',
  String numero = '1234',
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool abrir = true,
  bool conEspacio = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = _Telefono();
  await tester.runAsync(() async {
    await t.local.insertar(
      UbicacionModel.fromEntity(
        ubicacionGuardada(calle: calle, numero: numero, creada: _antes, actualizada: _antes),
      ),
    );
    if (conEspacio) {
      await t.db
          .into(t.db.espacios)
          .insert(
            EspaciosCompanion.insert(
              id: 'esp-1',
              ubicacionId: 'ubi-1',
              createdAt: _antes,
              updatedAt: _antes,
              syncVersion: const Value(2),
            ),
          );
    }
    t.cola.encolados.clear();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesAlta(
          gps: GpsFalso(),
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
          ),
          ciudades: CiudadesFalsas(),
          repo: t.repo,
          ahora: _ahora,
          mapa: t.mapa,
        ),
        consultorPendientesUbicacionProvider.overrideWithValue(t.pendientes),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(t.salidas),
      ),
    ),
  );
  _abierto = t;
  if (abrir) await _abrir(tester);
  return t;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
}

// ------------------------------------------------------------------ lo que se ve

/// «Dar de baja» de la pantalla de edición (el que abre la hoja).
Finder get _abrirBaja => find.text('Dar de baja');

Finder get _hoja => find.byType(BottomSheet);

/// El botón rojo de la hoja de baja.
Finder get _botonBaja => find.descendant(
  of: _hoja,
  matching: find.widgetWithText(FilledButton, 'Dar de baja'),
  skipOffstage: false,
);

Finder _enLaHoja(Finder f) => find.descendant(of: _hoja, matching: f);

Finder get _enElAviso =>
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton));

/// Elige uno de los motivos de la hoja.
Future<void> _elegirMotivo(WidgetTester tester, String motivo) =>
    _tocar(tester, _enLaHoja(find.text(motivo)));

/// Abre la hoja de baja y espera a que termine de «Revisar la ubicación…».
Future<void> _abrirHojaDeBaja(WidgetTester tester) async {
  await _tocar(tester, _abrirBaja);
  await _asentar(tester);
}

// ------------------------------------------------------------------ lo que quedó en el teléfono

Future<UbicacionFila> _fila(WidgetTester tester, _Telefono t) async => (await tester.runAsync(
  () => (t.db.select(t.db.ubicaciones)..where((u) => u.id.equals('ubi-1'))).getSingle(),
))!;

Future<List<AuditLogFila>> _auditoria(WidgetTester tester, _Telefono t) async =>
    (await tester.runAsync(
      () => (t.db.select(t.db.auditLogLocal)..orderBy([(a) => OrderingTerm.asc(a.id)])).get(),
    ))!;

Future<List<EspacioFila>> _espacios(WidgetTester tester, _Telefono t) async =>
    (await tester.runAsync(() => t.db.select(t.db.espacios).get()))!;

Future<int> _enLaListaActiva(WidgetTester tester, _Telefono t) async => (await tester.runAsync(
  () => t.repo.observarListaDelColportor(colportorId: 'col-1').first,
))!.length;

Future<int> _enLaListaConBajas(WidgetTester tester, _Telefono t) async => (await tester.runAsync(
  () => t.repo.observarListaDelColportor(colportorId: 'col-1', incluirBajas: true).first,
))!.length;

Future<int> _enElMapa(WidgetTester tester, _Telefono t) async => (await tester.runAsync(
  () => t.repo
      .observarMarcadoresEnArea(
        colportorId: 'col-1',
        area: const AreaMapa(sur: -35, oeste: -57, norte: -34, este: -56),
      )
      .first,
))!.length;

/// Que la casa siga activa y que nada se haya escrito (ni cola ni auditoría).
Future<void> _expectIntacta(WidgetTester tester, _Telefono t) async {
  final fila = await _fila(tester, t);
  expect(fila.deletedAt, isNull, reason: 'la casa sigue activa');
  expect(fila.updatedAt, _antes, reason: 'no se tocó la fila');
  expect(t.cola.encolados, isEmpty, reason: 'no se encoló nada');
  expect(await _auditoria(tester, t), isEmpty, reason: 'no hay baja que auditar');
}

void main() {
  group('Escenario: Baja simple sin pendientes', () {
    prueba('dado una casa sin pendientes, cuando confirma «Dar de baja», entonces se setea '
        'deleted_at, sale del mapa y de la lista activa y se encola el tombstone', (tester) async {
      final t = await _montar(tester, conEspacio: true);
      expect(await _enLaListaActiva(tester, t), 1);
      expect(await _enElMapa(tester, t), 1);
      final antes = await _fila(tester, t);

      await _abrirHojaDeBaja(tester);
      expect(_enLaHoja(find.text('Revisando la ubicación…')), findsNothing);
      expect(find.text('¿Dar de baja Av. Italia 1234?'), findsOneWidget);
      expect(t.pendientes.consultadas, ['ubi-1']);
      await _elegirMotivo(tester, 'Ya no existe');
      await _tocar(tester, _botonBaja);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      expect(find.text('abrir'), findsOneWidget, reason: 'volvió a la pantalla anterior');
      final fila = await _fila(tester, t);
      expect(fila.deletedAt, _ahora);
      expect(fila.updatedAt, _ahora);
      expect(fila.syncVersion, antes.syncVersion, reason: 'la sube el servidor, no el teléfono');
      expect(await _enLaListaActiva(tester, t), 0, reason: 'desaparece de la lista activa');
      expect(await _enElMapa(tester, t), 0, reason: 'y del mapa');
      expect(await _enLaListaConBajas(tester, t), 1, reason: 'sigue en «Con bajas»');
      expect(
        [for (final c in t.cola.encolados) (c.entidad, c.operacion)],
        [('ubicacion', OperacionSync.delete)],
      );
      expect(t.cola.encolados.single.payload['id'], 'ubi-1');
      expect(t.cola.encolados.single.payload['deleted_at'], _ahora.toIso8601String());
      final auditoria = await _auditoria(tester, t);
      expect(auditoria, hasLength(1));
      expect(auditoria.single.evento, EventoAuditoriaLocal.ubicacionBaja);
      expect(auditoria.single.uuid, 'ubi-1');
      expect(auditoria.single.motivo, 'Ya no existe');
      expect(auditoria.single.creadoEn, _ahora, reason: 'el mismo instante que deleted_at');
    });

    prueba('dado una casa con espacios, cuando la da de baja, entonces los espacios no se '
        'borran en cascada ni se encola nada de ellos', (tester) async {
      final t = await _montar(tester, conEspacio: true);

      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Está deshabitada');
      await _tocar(tester, _botonBaja);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      final espacios = await _espacios(tester, t);
      expect(espacios.single.deletedAt, isNull, reason: 'el espacio sigue activo');
      expect(espacios.single.updatedAt, _antes);
      expect([for (final c in t.cola.encolados) c.entidad], ['ubicacion']);
    });

    for (final (escrito, guardado) in <(String, String)>[
      ('Se mudó doña Estela', 'Se mudó doña Estela'),
      ('', 'Otro'),
      ('a' * 130, 'a' * 120),
    ]) {
      prueba('dado «Otro» con ${escrito.length} caracteres escritos, entonces el motivo '
          'guardado tiene ${guardado.length}', (tester) async {
        final t = await _montar(tester);
        await _abrirHojaDeBaja(tester);
        await _elegirMotivo(tester, 'Otro');
        if (escrito.isNotEmpty) {
          await tester.enterText(_enLaHoja(find.byType(TextField)), escrito);
          await _asentar(tester);
        }
        await _tocar(tester, _botonBaja);

        expect(t.salidas.single, isA<UbicacionBajaRealizada>());
        expect((await _auditoria(tester, t)).single.motivo, guardado);
      });
    }

    prueba('dado que no eligió un motivo, entonces «Dar de baja» está apagado y no se escribe '
        'nada', (tester) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);

      expect(tester.widget<FilledButton>(_botonBaja).onPressed, isNull);
      expect(find.text('Elegí un motivo para dar de baja.'), findsOneWidget);
      await tester.tap(_botonBaja, warnIfMissed: false);
      await _asentar(tester);

      await _expectIntacta(tester, t);
      expect(t.salidas, isEmpty);
    });
  });

  group('Escenario: Baja con visitas pendientes propias, doble confirmación', () {
    prueba('dado 2 visitas pendientes mías, entonces el aviso dice el literal de la HU, solo '
        'procede tras la segunda confirmación y el historial queda', (tester) async {
      final t = await _montar(tester, conEspacio: true);
      t.pendientes.pendientes = const PendientesUbicacion(visitasPropiasPendientes: 2);

      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'No quiere visitas');
      await _tocar(tester, _botonBaja);

      expect(find.text(_avisoDosVisitas), findsOneWidget);
      await _expectIntacta(tester, t);
      expect(t.salidas, isEmpty);

      // «Cancelar» en el aviso: la hoja sigue abierta con el motivo elegido y no se escribió nada.
      await _tocar(
        tester,
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')),
      );
      expect(find.text(_avisoDosVisitas), findsNothing);
      expect(_botonBaja, findsOneWidget);
      expect(tester.widget<FilledButton>(_botonBaja).onPressed, isNotNull);
      await _expectIntacta(tester, t);

      // Segunda vuelta: ahora sí confirma.
      await _tocar(tester, _botonBaja);
      expect(find.text(_avisoDosVisitas), findsOneWidget);
      await _tocar(tester, _enElAviso);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      expect((await _fila(tester, t)).deletedAt, _ahora);
      expect([for (final c in t.cola.encolados) c.entidad], ['ubicacion']);
      expect((await _auditoria(tester, t)).single.motivo, 'No quiere visitas');
      expect((await _espacios(tester, t)).single.deletedAt, isNull);
    });

    prueba('dado una sola visita pendiente, entonces el aviso dice «1 visita pendiente»', (
      tester,
    ) async {
      final t = await _montar(tester);
      t.pendientes.pendientes = const PendientesUbicacion(visitasPropiasPendientes: 1);

      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');
      await _tocar(tester, _botonBaja);

      expect(find.textContaining('Esta ubicación tiene 1 visita pendiente.'), findsOneWidget);
      await _expectIntacta(tester, t);
    });
  });

  group('Escenario: Baja bloqueada, casa con ventas o con visita de otro colportor', () {
    final bloqueos = <(String, PendientesUbicacion)>[
      ('una venta', const PendientesUbicacion(tieneVentas: true)),
      ('una visita de otro colportor', const PendientesUbicacion(tieneVisitasDeOtros: true)),
      (
        'ventas y visitas de otro colportor',
        const PendientesUbicacion(tieneVentas: true, tieneVisitasDeOtros: true),
      ),
      (
        'una cobranza pendiente',
        const PendientesUbicacion(
          tieneVentas: true,
          cobranzaPendiente: CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2),
        ),
      ),
    ];
    for (final (nombre, pendientes) in bloqueos) {
      prueba('dado $nombre, entonces la app no ofrece «Dar de baja», muestra el aviso que '
          'guía y no escribe nada', (tester) async {
        final t = await _montar(tester, conEspacio: true);
        t.pendientes.pendientes = pendientes;

        await _abrirHojaDeBaja(tester);

        expect(find.text('Todavía no se puede dar de baja'), findsOneWidget);
        if (pendientes.cobranzaPendiente != null) {
          expect(
            find.text(
              'Tiene una cobranza pendiente de \$U 1.450 (2.ª cuota). '
              'Registrá el cobro antes de darla de baja.',
            ),
            findsOneWidget,
          );
        } else {
          expect(find.text(_avisoBloqueo), findsOneWidget);
        }
        expect(_botonBaja, findsNothing, reason: 'no se ofrece «Dar de baja»');
        expect(find.text('MOTIVO · OBLIGATORIO'), findsNothing);
        await _tocar(tester, find.text('Entendido'));

        expect(find.text('Todavía no se puede dar de baja'), findsNothing);
        expect(_abrirBaja, findsOneWidget, reason: 'sigue en la edición');
        expect(t.salidas, isEmpty, reason: 'la edición sigue abierta');
        await _expectIntacta(tester, t);
        expect((await _espacios(tester, t)).single.deletedAt, isNull);
      });
    }

    prueba('dado que llega una venta por el sync mientras la hoja pide el motivo, entonces '
        'al confirmar la hoja pasa al aviso de bloqueo y no escribe', (tester) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');
      t.pendientes.pendientes = const PendientesUbicacion(tieneVentas: true);

      await _tocar(tester, _botonBaja);

      expect(find.text(_avisoBloqueo), findsOneWidget);
      expect(_botonBaja, findsNothing);
      await _expectIntacta(tester, t);
      expect(t.salidas, isEmpty);
    });
  });

  group('Escenario: Edge, no se puede revisar lo pendiente', () {
    prueba('dado que el teléfono todavía no puede revisar la casa, entonces dice «No pudimos '
        'revisar la ubicación» con «Reintentar», no deja pasar la baja y al poder, sigue', (
      tester,
    ) async {
      final t = await _montar(tester);
      t.pendientes.falla = const FailurePendientesNoDisponibles();

      await _abrirHojaDeBaja(tester);

      expect(find.text(_noPudimosRevisar), findsOneWidget);
      expect(_botonBaja, findsNothing, reason: 'ante la duda se bloquea');
      expect(find.text('MOTIVO · OBLIGATORIO'), findsNothing);

      // Reintenta y sigue sin poder: no cambia nada.
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text(_noPudimosRevisar), findsOneWidget);
      expect(t.pendientes.consultadas, ['ubi-1', 'ubi-1']);
      await _expectIntacta(tester, t);

      // Reintenta y ahora sí puede: pide el motivo.
      t.pendientes.falla = null;
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text(_noPudimosRevisar), findsNothing);
      await _elegirMotivo(tester, 'Ya no existe');
      await _tocar(tester, _botonBaja);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      expect((await _fila(tester, t)).deletedAt, _ahora);
    });

    prueba('dado que el consultor se rompe, entonces es la misma pantalla de «No pudimos '
        'revisar», sin escribir', (tester) async {
      final t = await _montar(tester);
      t.pendientes.lanza = StateError('puerto roto');

      await _abrirHojaDeBaja(tester);

      expect(find.text(_noPudimosRevisar), findsOneWidget);
      expect(_botonBaja, findsNothing);
      await _expectIntacta(tester, t);
    });
  });

  group('Casos límite de la baja', () {
    prueba('dado un doble toque en «Dar de baja», entonces se escribe una sola baja (una '
        'fila de auditoría y un tombstone)', (tester) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');

      // Dos toques sin `pump` entre medio: prueban la guarda síncrona.
      await tester.tap(_botonBaja);
      await tester.tap(_botonBaja, warnIfMissed: false);
      await _asentar(tester);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      expect(await _auditoria(tester, t), hasLength(1));
      expect([for (final c in t.cola.encolados) c.operacion], [OperacionSync.delete]);
      final log = t.logs.lineas.join('\n');
      expect('UBICACION_BAJA'.allMatches(log), hasLength(1));
      expect(log, isNot(contains('UBICACION_YA_DE_BAJA')));
    });

    prueba('dado que la casa ya se dio de baja mientras la hoja estaba abierta (otro toque o '
        'el sync), entonces la hoja se cierra como hecha y no escribe una segunda baja', (
      tester,
    ) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');
      await tester.runAsync(() async {
        await (t.db.update(t.db.ubicaciones)..where((u) => u.id.equals('ubi-1'))).write(
          UbicacionesCompanion(deletedAt: Value(_antes.add(const Duration(hours: 1)))),
        );
      });

      await _tocar(tester, _botonBaja);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      expect(t.cola.encolados, isEmpty, reason: 'el servidor ya la conoce de baja: nada que subir');
      expect(await _auditoria(tester, t), isEmpty);
      expect(
        t.logs.lineas.join('\n'),
        isNot(contains('UBICACION_BAJA')),
        reason: 'el caso de uso corta antes de llegar al repositorio',
      );
    });

    prueba('dado que la casa cambió mientras la hoja estaba abierta, entonces dice «cambió '
        'recién», no escribe, el botón sigue habilitado y al abrirla de nuevo la baja se hace', (
      tester,
    ) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');
      final cambio = _antes.add(const Duration(hours: 1));
      await tester.runAsync(() async {
        await (t.db.update(t.db.ubicaciones)..where((u) => u.id.equals('ubi-1'))).write(
          UbicacionesCompanion(updatedAt: Value(cambio)),
        );
      });

      await _tocar(tester, _botonBaja);

      expect(find.text(_avisoCambioReciente), findsOneWidget);
      expect(tester.widget<FilledButton>(_botonBaja).onPressed, isNotNull);
      expect((await _fila(tester, t)).deletedAt, isNull);
      expect(t.cola.encolados, isEmpty);
      expect(await _auditoria(tester, t), isEmpty);
      expect(t.salidas, isEmpty);

      // Reintentar con la misma hoja vuelve a fallar: el aviso manda a abrirla de nuevo.
      await _tocar(tester, _botonBaja);
      expect(find.text(_avisoCambioReciente), findsOneWidget);
      expect((await _fila(tester, t)).deletedAt, isNull);

      // Cierra la hoja y la edición, abre de nuevo y ahora sí.
      await _tocar(tester, _enLaHoja(find.text('Cancelar')));
      await _tocar(tester, find.byTooltip('Cerrar'));
      await _abrir(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');
      await _tocar(tester, _botonBaja);

      expect(t.salidas.last, isA<UbicacionBajaRealizada>());
      expect((await _fila(tester, t)).deletedAt, _ahora);
    });

    prueba('dado una falla a mitad de la baja (el motor de sync no encola), entonces nada '
        'queda a medias, el botón vuelve a habilitarse con el motivo y el reintento funciona', (
      tester,
    ) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Otro');
      await tester.enterText(_enLaHoja(find.byType(TextField)), 'Se mudó doña Estela');
      await _asentar(tester);
      t.cola.fallarCon = StateError('motor apagado');

      await _tocar(tester, _botonBaja);

      expect(find.text(_noPudimosDarDeBaja), findsOneWidget);
      expect(find.text('Dando de baja…'), findsNothing, reason: 'no queda trabado en «ocupado»');
      expect(tester.widget<FilledButton>(_botonBaja).onPressed, isNotNull);
      expect(t.salidas, isEmpty);
      await _expectIntacta(tester, t);
      expect(
        tester.widget<TextField>(_enLaHoja(find.byType(TextField))).controller!.text,
        'Se mudó doña Estela',
        reason: 'el motivo escrito se conserva',
      );
      final log = t.logs.lineas.join('\n');
      expect(log, isNot(contains('doña Estela')), reason: 'el motivo es texto libre: no va al log');
      expect(log, isNot(contains('Italia')));

      t.cola.fallarCon = null;
      await _tocar(tester, _botonBaja);

      expect(t.salidas.single, isA<UbicacionBajaRealizada>());
      expect((await _fila(tester, t)).deletedAt, _ahora);
      expect([for (final c in t.cola.encolados) c.operacion], [OperacionSync.delete]);
      expect((await _auditoria(tester, t)).single.motivo, 'Se mudó doña Estela');
    });

    prueba('dado que cierra la hoja con «Cancelar», cierra la edición y vuelve a abrir, '
        'entonces no se escribió nada y «Dar de baja» sigue funcionando', (tester) async {
      final t = await _montar(tester);
      await _abrirHojaDeBaja(tester);
      await _elegirMotivo(tester, 'Ya no existe');
      await _tocar(tester, _enLaHoja(find.text('Cancelar')));
      await _expectIntacta(tester, t);
      expect(t.salidas, isEmpty);

      await _tocar(tester, find.byTooltip('Cerrar'));
      expect(find.text('abrir'), findsOneWidget);
      await _expectIntacta(tester, t);

      await _abrir(tester);
      await _abrirHojaDeBaja(tester);
      expect(
        tester.widget<FilledButton>(_botonBaja).onPressed,
        isNull,
        reason: 'la hoja nueva no arrastra el motivo de la anterior',
      );
      await _elegirMotivo(tester, 'No quiere visitas');
      await _tocar(tester, _botonBaja);

      expect(t.salidas, [
        null,
        isA<UbicacionBajaRealizada>(),
      ], reason: 'cerrar sin baja, y luego baja');
      expect((await _auditoria(tester, t)).single.motivo, 'No quiere visitas');
      expect(
        t.pendientes.consultadas,
        ['ubi-1', 'ubi-1', 'ubi-1'],
        reason: 'cada hoja revisa de nuevo, y la baja vuelve a mirar al escribirse',
      );
    });

    for (final (nombre, tamano, escala) in [
      ('320×568 al 200 %', const Size(320, 568), 2.0),
      ('360×640 al 200 %', const Size(360, 640), 2.0),
    ]) {
      prueba('dado una dirección muy larga en $nombre, entonces la hoja entra, se puede dar '
          'de baja y no hay desbordes', (tester) async {
        final t = await _montar(
          tester,
          calle: 'Avenida Doctor Doctor Doctor Presidente General Don José Gervasio Artigas',
          numero: '12345',
          tamano: tamano,
          escala: escala,
        );

        await _abrirHojaDeBaja(tester);
        await _elegirMotivo(tester, 'Está deshabitada');
        await _tocar(tester, _botonBaja);

        expect(tester.takeException(), isNull);
        expect(t.salidas.single, isA<UbicacionBajaRealizada>());
        expect((await _fila(tester, t)).deletedAt, _ahora);
        expect((await _auditoria(tester, t)).single.motivo, 'Está deshabitada');
      });
    }
  });
}
