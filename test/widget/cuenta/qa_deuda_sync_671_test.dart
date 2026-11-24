// QA de la deuda con la casa editora que baja con la sincronización (#671, HU-CTA-002, vistas 33A·01 y
// 33B), con las dos mitades reales: el motor de sync contra un servidor falso, la base de Drift en memoria
// y las pantallas de verdad (Mi Cuenta y 33B). Lo que ya cubren los tests de la lectura con un origen en
// memoria (`qa_vista33_deuda_441_test`) no se repite: acá se prueba la tubería entera con la pantalla abierta.
//
// - la primera sincronización llega con la pantalla abierta: de «Estamos bajando tus datos» a la deuda, sin
//   tocar nada y sin pasar nunca por un «$ 0»;
// - sin conexión y sin nada bajado: «Necesitás conexión…»; al volver la conexión el texto cambia solo;
// - una sincronización que falla no deja la pantalla trabada ni inventa una cifra; «Reintentar» no queda
//   deshabilitado;
// - con `--dart-define=QA_CAPTURAS=true`, un PNG por estado nuevo en `.dart_tool/qa_capturas/` (no se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/alquiler_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/pedidos/presentation/providers/pedidos_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_vista33_deuda_441_arnes.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');

const _bajando = 'Estamos bajando tus datos. Probá en unos segundos.';
const _necesitasConexion = 'Necesitás conexión para ver tu deuda con la casa editora.';

Map<String, Object?> _auditoria([int version = 1]) => {
  'created_at': '2026-10-01T10:00:00+00:00',
  'updated_at': '2026-10-01T10:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': version,
};

Map<String, Object?> _cuenta(int deuda, {int version = 1}) => {
  'id': 'cu-col-1',
  'usuario_id': 'col-1',
  'deuda_total': deuda,
  'dinero_depositado': 0,
  'dinero_en_mano': 0,
  'dinero_por_cobrar': 0,
  'deuda_alquiler': 0,
  'alquiler_trasladado': 0,
  'actualizado_en': '2026-10-01T10:00:00+00:00',
  ..._auditoria(version),
  'xmin_w': '1',
};

Map<String, Object?> _pedido(String id, int numero, int monto, String fecha) => {
  'id': id,
  'colportor_id': 'col-1',
  'coordinador_id': null,
  'fecha_pedido': fecha,
  'estado': 'AUTORIZADO',
  'monto_total': monto,
  'origen': 'COLPORTOR',
  'excede_limite': false,
  'monto_autorizado': monto,
  'decidido_por': null,
  'decidido_en': null,
  'motivo_rechazo': null,
  'numero': numero,
  ..._auditoria(),
  'xmin_w': '1',
};

Map<String, Object?> _linea(String pedido, String producto, int cantidad) => {
  'id': 'li-$pedido-$producto',
  'pedido_id': pedido,
  'producto_id': producto,
  'cantidad': cantidad,
  'precio_unitario': 1500,
  'cantidad_recibida': null,
  'colportor_id': 'col-1',
  'cantidad_autorizada': null,
  ..._auditoria(),
  'xmin_w': '1',
};

Map<String, Object?> _producto(String id, String nombre) => {
  'id': id,
  'nombre': nombre,
  'descripcion': null,
  'tipo': 'LIBRO',
  'categoria': 'ESPIRITUALES',
  'es_bonificable': true,
  'es_misionero': false,
  'precio_base_compra': 1500,
  'casa_editora': null,
  'imagen_url': null,
  ..._auditoria(),
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    red = FakeConnectivityPort();
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      meta: DriftSyncMeta(db),
      connectivity: red,
    );
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> sincronizar(WidgetTester tester) async {
    await tester.runAsync(() => motor.syncNow());
    await asentar(tester);
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await motor.dispose();
      await red.dispose();
      await db.close();
    });
  }

  /// Lo que el servidor le baja a la colportora en la primera sincronización: un pedido de $ 18.400.
  void servidorConUnPedido() {
    servidor
      ..seed('cuenta_colportor', [_cuenta(1840000)])
      ..seed('producto', [_producto('p-1', 'Salud y Hogar')])
      ..seed('pedido_casa_editora', [_pedido('a1', 1, 1840000, '2026-10-02T15:00:00+00:00')])
      ..seed('pedido_item', [_linea('a1', 'p-1', 10)]);
  }

  Future<MonitorQueCambia> montar33B(
    WidgetTester tester, {
    TipoConexion conexion = TipoConexion.wifi,
    Size tamano = const Size(390, 844),
    double escala = 1,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final monitor = MonitorQueCambia(conexion);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbLocalProvider.overrideWithValue(db),
          relojCuentaProvider.overrideWithValue(() => DateTime(2026, 11, 12, 12)),
          monitorConectividadProvider.overrideWithValue(monitor),
          // La nota del alquiler de 33B (#753) lee `cuenta_colportor`, que esta sincronización escribe: su
          // consulta a la DB real quedaría abierta en el reloj falso del test y la sincronización no
          // terminaría (mismo motivo que `pedidosProvider` en 33A). Acá no es lo que se prueba.
          alquilerRepositoryProvider.overrideWithValue(const AlquilerSinBase()),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: const DeudaCasaPage(colportorId: 'col-1'),
        ),
      ),
    );
    await asentar(tester);
    return monitor;
  }

  Future<MonitorQueCambia> montar33A(
    WidgetTester tester, {
    TipoConexion conexion = TipoConexion.wifi,
  }) async {
    final monitor = MonitorQueCambia(conexion);
    await montarCuenta(
      tester,
      RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
      overrides: [
        dbLocalProvider.overrideWithValue(db),
        relojCuentaProvider.overrideWithValue(() => DateTime(2026, 11, 12, 12)),
        monitorConectividadProvider.overrideWithValue(monitor),
        // El enlace «Mis pedidos» de Mi Cuenta (#387) no es lo que se prueba acá: sin esto su consulta a la
        // DB real queda abierta en el reloj falso del test y la sincronización no termina.
        pedidosProvider.overrideWith((ref, colportorId) => Stream.value(const <Pedido>[])),
        // La línea «Alquiler» de Mi Cuenta lee `cuenta_colportor` (#753): mismo motivo.
        alquilerRepositoryProvider.overrideWithValue(const AlquilerSinBase()),
      ],
    );
    await asentar(tester);
    return monitor;
  }

  group('33B con la sincronización real', () {
    testWidgets('la primera sincronización llega con la pantalla abierta: de «Estamos bajando tus '
        'datos» a la deuda, sin tocar nada y sin un \$ 0 en el medio', (tester) async {
      await montar33B(tester);

      expect(find.text(_bajando), findsOneWidget);
      expect(find.text(r'$ 0'), findsNothing);
      expect(find.text('No le debés nada a la casa editora'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);

      servidorConUnPedido();
      await sincronizar(tester);

      expect(find.text(_bajando), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
      expect(find.text('Salud y Hogar × 10'), findsOneWidget);
      expect(find.text('No le debés nada a la casa editora'), findsNothing);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    testWidgets('llega otro pedido con la pantalla ya mostrando la deuda: la lista y el total se '
        'actualizan solos, sin pasar por la carga', (tester) async {
      servidorConUnPedido();
      await tester.runAsync(() => motor.syncNow());
      await montar33B(tester);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.byKey(const Key('deuda_pedido_1')), findsNothing);

      servidor
        ..seed('cuenta_colportor', [_cuenta(2440000, version: 2)])
        ..seed('pedido_casa_editora', [_pedido('a2', 2, 600000, '2026-10-15T15:00:00+00:00')])
        ..seed('pedido_item', [_linea('a2', 'p-1', 4)]);
      await tester.runAsync(() => motor.syncNow());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(
        find.byKey(const Key('deuda_esqueleto_total')),
        findsNothing,
        reason: 'se vuelve a leer sin parpadeo',
      );
      await asentar(tester);

      expect(find.text(r'$ 24.400'), findsOneWidget);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
      expect(find.text('PEDIDO DEL 15/10'), findsOneWidget);
      expect(find.text('Salud y Hogar × 4'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('sin conexión y sin nada bajado dice que hace falta la conexión; al volver la '
        'conexión el texto cambia solo y, al bajar los datos, aparece la deuda', (tester) async {
      final monitor = await montar33B(tester, conexion: TipoConexion.sinConexion);
      expect(find.text(_necesitasConexion), findsOneWidget);
      expect(find.text(_bajando), findsNothing);
      expect(find.text(r'$ 0'), findsNothing);

      monitor.cambiar(TipoConexion.wifi);
      await asentar(tester);
      expect(find.text(_bajando), findsOneWidget, reason: 'con conexión ya no miente');
      expect(find.text(_necesitasConexion), findsNothing);

      servidorConUnPedido();
      await sincronizar(tester);
      expect(find.text(r'$ 18.400'), findsOneWidget);

      // Y si se vuelve a cortar la conexión: la deuda sigue y dice de cuándo es (33A·02).
      monitor.cambiar(TipoConexion.sinConexion);
      await asentar(tester);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.text(_necesitasConexion), findsNothing);
      await cerrar(tester);
    });

    testWidgets('si la primera sincronización falla, la pantalla no se traba ni inventa una cifra; '
        '«Reintentar» sigue habilitado y, cuando la sincronización anda, aparece la deuda', (
      tester,
    ) async {
      servidorConUnPedido();
      servidor.failWith(500);
      await tester.runAsync(() => motor.syncNow());
      await montar33B(tester);

      expect(find.text(_bajando), findsOneWidget);
      expect(find.text(r'$ 0'), findsNothing);

      // Tocar «Reintentar» con la base todavía vacía: vuelve al mismo aviso, no queda en la carga.
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(find.byKey(const Key('deuda_esqueleto_total')), findsNothing);
      expect(find.text(_bajando), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.ancestor(
                of: find.text('Reintentar'),
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
            )
            .enabled,
        isTrue,
      );

      servidor.clearFailures();
      await sincronizar(tester);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    testWidgets('el texto grande (2,0) a 360x640 con la deuda real y un nombre largo no desborda', (
      tester,
    ) async {
      servidor
        ..seed('cuenta_colportor', [_cuenta(99999999999)])
        ..seed('producto', [_producto('p-1', 'Revista 📚 «Vida Feliz» ${'muy ' * 20}larga')])
        ..seed('pedido_casa_editora', [_pedido('a1', 1, 99999999999, '2026-10-02T15:00:00+00:00')])
        ..seed('pedido_item', [_linea('a1', 'p-1', 123456)]);
      await tester.runAsync(() => motor.syncNow());
      await montar33B(tester, tamano: const Size(360, 640), escala: 2);

      expect(find.textContaining('Revista 📚'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });
  });

  group('33A · tarjeta de la deuda con la sincronización real', () {
    testWidgets('la primera sincronización llega con Mi Cuenta abierta: la línea gris da paso a la '
        'cifra, sin un \$ 0 en el medio', (tester) async {
      await montar33A(tester);
      final tarjeta = find.byKey(const Key('cuenta_deuda'));
      expect(tarjeta, findsOneWidget);
      expect(find.descendant(of: tarjeta, matching: find.text(_bajando)), findsOneWidget);
      expect(find.descendant(of: tarjeta, matching: find.text(r'$ 0')), findsNothing);

      servidorConUnPedido();
      await sincronizar(tester);

      expect(find.descendant(of: tarjeta, matching: find.text(_bajando)), findsNothing);
      expect(find.descendant(of: tarjeta, matching: find.text(r'$ 18.400')), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets(
      'sin conexión y sin nada bajado la tarjeta dice que hace falta conexión (no «Estamos '
      'bajando…»); al volver la conexión cambia sola',
      (tester) async {
        final monitor = await montar33A(tester, conexion: TipoConexion.sinConexion);
        final tarjeta = find.byKey(const Key('cuenta_deuda'));
        expect(
          find.descendant(of: tarjeta, matching: find.text(_necesitasConexion)),
          findsOneWidget,
        );

        monitor.cambiar(TipoConexion.wifi);
        await asentar(tester);
        expect(find.descendant(of: tarjeta, matching: find.text(_bajando)), findsOneWidget);
        expect(find.descendant(of: tarjeta, matching: find.text(_necesitasConexion)), findsNothing);
        await cerrar(tester);
      },
    );
  });

  group('capturas (a .dart_tool/qa_capturas/)', skip: !_capturar, () {
    const tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
    for (final nombre in ['33B_sin_red_nada_bajado', '33B_con_red_nada_bajado']) {
      for (final t in tamanos.entries) {
        for (final esc in [1.0, 2.0]) {
          testWidgets('$nombre · ${t.key} · ${esc}x', (tester) async {
            await cargarFuentesReales(tester);
            final raiz = GlobalKey();
            final repo = RepositorioDeDeudaControlable();
            tester.view.physicalSize = t.value;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  ...overridesDeDeuda(repo),
                  monitorConectividadProvider.overrideWithValue(
                    ConexionFija(
                      nombre.contains('sin_red') ? TipoConexion.sinConexion : TipoConexion.wifi,
                    ),
                  ),
                ],
                child: RepaintBoundary(
                  key: raiz,
                  child: MaterialApp(
                    theme: temaClaro(),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(esc)),
                      child: child!,
                    ),
                    home: const DeudaCasaPage(colportorId: 'col-1'),
                  ),
                ),
              ),
            );
            await tester.pump();
            repo.sinSincronizar();
            await tester.pump();
            await tester.pump();
            await _png(tester, raiz, '671_${nombre}_${t.key}_x${esc.toInt()}');
          });
        }
      }
    }
    for (final nombre in ['33A_sin_red_nada_bajado', '33A_con_red_nada_bajado']) {
      for (final t in tamanos.entries) {
        for (final esc in [1.0, 2.0]) {
          testWidgets('$nombre · ${t.key} · ${esc}x', (tester) async {
            await cargarFuentesReales(tester);
            final raiz = GlobalKey();
            final repo = RepositorioDeDeudaControlable();
            await montarCuenta(
              tester,
              RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
              tamano: t.value,
              escala: esc,
              boundary: raiz,
              overrides: [
                ...overridesDeDeuda(repo),
                monitorConectividadProvider.overrideWithValue(
                  QaConexion(
                    nombre.contains('sin_red') ? TipoConexion.sinConexion : TipoConexion.wifi,
                  ),
                ),
              ],
            );
            await tester.pump();
            repo.sinSincronizar();
            await tester.pump();
            await tester.pump();
            await _png(tester, raiz, '671_${nombre}_${t.key}_x${esc.toInt()}');
          });
        }
      }
    }
  });
}

Future<void> _png(WidgetTester tester, GlobalKey raiz, String nombre) async {
  Directory('.dart_tool/qa_capturas').createSync(recursive: true);
  await tester.runAsync(() async {
    final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await r.toImage();
    final bd = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    File('.dart_tool/qa_capturas/$nombre.png').writeAsBytesSync(Uint8List.view(bd.buffer));
  });
}
