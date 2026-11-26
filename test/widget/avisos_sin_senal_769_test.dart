// «Avisos s/red» (Cristian, 24/11; #769, backend-supabase 0207): Configuración › Notificaciones, sección AVISOS
// (vista 24), con los avisos guardados en el teléfono. Diego, sin señal en la calle, apaga «Tickets» o cambia
// otro aviso: el cambio se ve y se guarda al instante y sube con la sincronización. Nunca sale un aviso de
// conexión al guardar (decisión P2 del 26/11): si no se pudo guardar es porque falló la base del teléfono, y
// entonces va el aviso de error de siempre («No pudimos guardar… Volvió a como estaba.» con «Reintentar»).
//
// La pantalla real, el repositorio real y la base real (Drift en memoria); afuera solo el motor de sync, cuya
// cola en memoria no sube nada: justo lo que pasa sin señal.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/preferencias_de_avisos_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/avisos_del_servidor_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/notificaciones_arnes.dart';

final _pedidos = find.byKey(const Key('aviso_pedidos_interruptor'));
final _tickets = find.byKey(const Key('aviso_tickets_interruptor'));
final _cuotas = find.byKey(const Key('aviso_cuotas_interruptor'));
final _errorGuardar = find.byKey(const Key('avisos_error_guardar'));
final _reintentarGuardar = find.byKey(const Key('avisos_error_reintentar'));
final _errorLeer = find.byKey(const Key('avisos_error_leer'));
final _reintentarLeer = find.byKey(const Key('avisos_reintentar_leer'));

const _textoError = 'No pudimos guardar el cambio. El interruptor volvió a como estaba.';

/// El teléfono de la colportora `col-1`: la base real y la cola del sync (que no sube nada).
final class _Base {
  _Base() : db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());

  final AppDatabase db;
  final cola = EncoladorSyncEnMemoria();

  PreferenciasDeAvisosLocalDataSourceDrift get local => PreferenciasDeAvisosLocalDataSourceDrift(
    db,
    encolador: cola,
    usuarioId: () => 'col-1',
    ahora: () => DateTime.utc(2026, 11, 26, 15),
  );
}

/// La base real no avanza con el reloj falso del test: se le da tiempo real y se bombea.
Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _sembrar(
  WidgetTester tester,
  _Base b,
  Map<String, Object?>? notif, {
  int version = 3,
}) async {
  await tester.runAsync(
    () => b.db.customStatement(
      'INSERT INTO preferencia_de_avisos (id, notif_preferences, created_at, updated_at, sync_version) '
      "VALUES ('col-1', ${notif == null ? 'NULL' : "'${_json(notif)}'"}, 1, 1, $version)",
    ),
  );
}

String _json(Map<String, Object?> m) =>
    '{${m.entries.map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}').join(',')}}';

Future<Map<String, Object?>?> _guardado(WidgetTester tester, _Base b) =>
    tester.runAsync(() => b.local.leer()).then((v) => v);

Future<void> _abrir(WidgetTester tester, _Base b, {Telefono? telefono}) async {
  final t = telefono ?? Telefono(estado: EstadoSistemaNotificaciones.activadas);
  t.repositorioDeAvisos = AvisosDelServidorLocal(b.local);
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: t.overrides,
      child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
    ),
  );
  await _asentar(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

bool _prendido(WidgetTester tester, Finder f) => tester.widget<SwitchListTile>(f).value;

/// Ningún aviso de conexión en la pantalla (ni el de guardar ni el de leer).
void _sinAvisosDeConexion() {
  expect(find.textContaining('onexión'), findsNothing);
  expect(find.textContaining('Necesitás'), findsNothing);
}

void main() {
  late _Base base;

  setUp(() => base = _Base());
  tearDown(() async {
    await base.db.close();
  });

  group('lee lo que bajó con la sincronización', () {
    testWidgets('los interruptores muestran lo guardado en el teléfono, sin ir al servidor', (
      tester,
    ) async {
      await _sembrar(tester, base, {'tickets': false, 'cuotas': false});

      await _abrir(tester, base);

      expect(_prendido(tester, _tickets), isFalse);
      expect(_prendido(tester, _cuotas), isFalse);
      expect(_prendido(tester, _pedidos), isTrue);
      expect(_errorLeer, findsNothing);
      _sinAvisosDeConexion();
    });

    testWidgets(
      'sin lo que bajó todavía (primer uso sin señal) están los valores de siempre, sin error',
      (tester) async {
        await _abrir(tester, base);

        expect(_prendido(tester, _pedidos), isTrue);
        expect(_prendido(tester, _tickets), isTrue);
        expect(_errorLeer, findsNothing);
        _sinAvisosDeConexion();
      },
    );
  });

  group('sin señal el cambio se guarda al instante y queda en la cola', () {
    testWidgets(
      'apagar «Tickets»: el interruptor cambia, se guarda en el teléfono y no sale ningún aviso',
      (tester) async {
        await _sembrar(tester, base, {'pedidos': true});
        await _abrir(tester, base);

        await _tocar(tester, _tickets);

        expect(_prendido(tester, _tickets), isFalse);
        expect(_errorGuardar, findsNothing);
        _sinAvisosDeConexion();
        expect((await _guardado(tester, base))!['tickets'], isFalse);
        final cambio = base.cola.encolados.single;
        expect(cambio.entidad, 'preferencia_de_avisos');
        expect(cambio.operacion, OperacionSync.update);
        expect((cambio.payload['notif_preferences']! as Map)['tickets'], isFalse);
        expect(cambio.payload['sync_version'], 3, reason: 'la versión de la fila que bajó');
      },
    );

    testWidgets(
      'dos cambios seguidos sin esperar: se guardan los dos y el último no pisa al primero',
      (tester) async {
        await _sembrar(tester, base, {});
        await _abrir(tester, base);

        await tester.ensureVisible(_pedidos);
        await tester.pump();
        await tester.tap(_pedidos);
        await tester.pump();
        await tester.ensureVisible(_cuotas);
        await tester.pump();
        await tester.tap(_cuotas);
        await _asentar(tester);

        expect(_prendido(tester, _pedidos), isFalse);
        expect(_prendido(tester, _cuotas), isFalse);
        final guardado = (await _guardado(tester, base))!;
        expect((guardado['pedidos'], guardado['cuotas']), (false, false));
        final ultimo = base.cola.encolados.last.payload['notif_preferences']! as Map;
        expect((ultimo['pedidos'], ultimo['cuotas']), (false, false));
        _sinAvisosDeConexion();
      },
    );

    testWidgets('prender y apagar el mismo aviso seguido deja lo último', (tester) async {
      await _sembrar(tester, base, {});
      await _abrir(tester, base);

      await _tocar(tester, _tickets);
      await _tocar(tester, _tickets);

      expect(_prendido(tester, _tickets), isTrue);
      expect((await _guardado(tester, base))!['tickets'], isTrue);
    });

    testWidgets('salir y volver a entrar muestra lo que quedó guardado', (tester) async {
      await _sembrar(tester, base, {});
      await _abrir(tester, base);
      await _tocar(tester, _tickets);

      await tester.pumpWidget(const SizedBox.shrink());
      await _abrir(tester, base);

      expect(_prendido(tester, _tickets), isFalse);
    });
  });

  group('antes de la primera sincronización (la fila todavía no bajó)', () {
    testWidgets(
      'el cambio no se guarda en silencio: el interruptor vuelve, dice que no pudo y, cuando baja la fila, se puede',
      (tester) async {
        await _abrir(tester, base);

        await _tocar(tester, _tickets);

        expect(_prendido(tester, _tickets), isTrue, reason: 'volvió a como estaba');
        expect(find.text(_textoError), findsOneWidget);
        _sinAvisosDeConexion();
        expect(base.cola.encolados, isEmpty);

        await _sembrar(tester, base, {});
        await _tocar(tester, _reintentarGuardar);

        expect(_errorGuardar, findsNothing);
        expect(_prendido(tester, _tickets), isFalse);
        expect((await _guardado(tester, base))!['tickets'], isFalse);
        expect(base.cola.encolados.single.operacion, OperacionSync.update);
      },
    );
  });

  group('si la base del teléfono no puede guardar', () {
    testWidgets('el interruptor vuelve a como estaba, dice qué pasó y «Reintentar» lo guarda', (
      tester,
    ) async {
      await _sembrar(tester, base, {});
      await _abrir(tester, base);
      base.cola.fallarCon = StateError('la base no responde');

      await _tocar(tester, _tickets);

      expect(_prendido(tester, _tickets), isTrue, reason: 'volvió a como estaba');
      expect(find.text(_textoError), findsOneWidget);
      expect(_reintentarGuardar, findsOneWidget);
      _sinAvisosDeConexion();
      expect(
        (await _guardado(tester, base))!['tickets'],
        isNot(isFalse),
        reason: 'no se escribió nada',
      );

      base.cola.fallarCon = null;
      await _tocar(tester, _reintentarGuardar);

      expect(_errorGuardar, findsNothing);
      expect(_prendido(tester, _tickets), isFalse);
      expect((await _guardado(tester, base))!['tickets'], isFalse);
    });

    testWidgets(
      'dos cambios que fallan seguidos: los dos vuelven a como estaban, queda un aviso y nada se traba',
      (tester) async {
        await _sembrar(tester, base, {});
        await _abrir(tester, base);
        base.cola.fallarCon = StateError('la base no responde');

        await tester.ensureVisible(_pedidos);
        await tester.pump();
        await tester.tap(_pedidos);
        await tester.pump();
        await tester.ensureVisible(_tickets);
        await tester.pump();
        await tester.tap(_tickets);
        await _asentar(tester);

        expect(_errorGuardar, findsOneWidget);
        expect(_prendido(tester, _pedidos), isTrue);
        expect(_prendido(tester, _tickets), isTrue);
        _sinAvisosDeConexion();

        base.cola.fallarCon = null;
        await _tocar(tester, _reintentarGuardar);

        expect(_errorGuardar, findsNothing);
        expect(_prendido(tester, _tickets), isFalse, reason: 'lo último que se pidió se guardó');
        // Y se puede seguir cambiando: ningún estado de «guardando» quedó trabado.
        await _tocar(tester, _pedidos);
        expect(_prendido(tester, _pedidos), isFalse);
        final guardado = (await _guardado(tester, base))!;
        expect((guardado['pedidos'], guardado['tickets']), (false, false));
      },
    );

    testWidgets('si no se puede leer, dice que no pudo leer (no «sin conexión») y deja reintentar', (
      tester,
    ) async {
      await _sembrar(tester, base, {});
      await tester.runAsync(() => base.db.customStatement('DROP TABLE preferencia_de_avisos'));

      await _abrir(tester, base);

      expect(find.text('No pudimos leer tus avisos.'), findsOneWidget);
      expect(_reintentarLeer, findsOneWidget);
      _sinAvisosDeConexion();

      await tester.runAsync(
        () => base.db.customStatement(
          'CREATE TABLE preferencia_de_avisos (id TEXT NOT NULL PRIMARY KEY, notif_preferences TEXT NULL, '
          'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NULL, '
          'deleted_at INTEGER NULL, sync_version INTEGER NOT NULL DEFAULT 0)',
        ),
      );
      await _tocar(tester, _reintentarLeer);

      expect(_errorLeer, findsNothing);
      expect(_prendido(tester, _tickets), isTrue);
    });
  });

  testWidgets(
    'con el texto al 200 % el error de guardar se ve entero y «Reintentar» se puede tocar',
    (tester) async {
      await _sembrar(tester, base, {});
      tester.view.physicalSize = const Size(360, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas)
        ..repositorioDeAvisos = AvisosDelServidorLocal(base.local);
      await tester.pumpWidget(
        ProviderScope(
          overrides: t.overrides,
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const NotificacionesPage(),
          ),
        ),
      );
      await _asentar(tester);
      base.cola.fallarCon = StateError('la base no responde');

      await _tocar(tester, _cuotas);

      expect(tester.takeException(), isNull);
      expect(find.text(_textoError), findsOneWidget);
      await tester.ensureVisible(_reintentarGuardar);
      await tester.pump();
      expect(tester.getSize(_reintentarGuardar).shortestSide, greaterThanOrEqualTo(48));
    },
  );
}
