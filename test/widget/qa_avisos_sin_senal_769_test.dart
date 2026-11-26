// QA de #769 (PR #773, «Avisos s/red», vista 24 grupo B, sección AVISOS): la pantalla real con el repositorio y
// la base reales (Drift en memoria), llevada a 360x640 y 412x915 con el texto al 100 % y al 200 %, con las
// guías de accesibilidad de Flutter en cada estado y los casos límite que el implementador no recorre (él
// prueba en una pantalla alta de 3200 dp: acá se prueba en la del teléfono).
//
// Corre las capturas PNG con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, que no se
// commitea).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/preferencias_de_avisos_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/avisos_del_servidor_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_vista37_387_arnes.dart' show cargarFuentes37, capturar37;

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];

/// Texto al 100 % y al 200 %; con las fuentes reales de la app (anchos y desbordes) y con Ahem (el contraste: con
/// fuentes reales la guía mide el antialias del texto chico y da falsos positivos).
/// Primero con Ahem (el contraste) y después con las fuentes reales: cargarlas vale para todo el archivo.
final _matriz = <(String, Size, double, bool)>[
  for (final reales in const [false, true])
    for (final escala in const [1.0, 2.0])
      for (final (nombre, tamano) in _tamanos) (nombre, tamano, escala, reales),
];

Future<void> _fuentes(WidgetTester tester, bool reales) async {
  if (reales) await cargarFuentes37(tester);
}

void _sinDesborde(WidgetTester tester, bool reales) {
  final e = tester.takeException();
  if (reales) expect(e, isNull);
}

final _pedidos = find.byKey(const Key('aviso_pedidos_interruptor'));
final _tickets = find.byKey(const Key('aviso_tickets_interruptor'));
final _cuotas = find.byKey(const Key('aviso_cuotas_interruptor'));
final _horaCuota = find.byKey(const Key('aviso_cuotas_hora'));
final _errorGuardar = find.byKey(const Key('avisos_error_guardar'));
final _reintentarGuardar = find.byKey(const Key('avisos_error_reintentar'));
final _errorLeer = find.byKey(const Key('avisos_error_leer'));
final _reintentarLeer = find.byKey(const Key('avisos_reintentar_leer'));

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

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _sembrar(WidgetTester tester, _Base b) => tester.runAsync(
  () => b.db.customStatement(
    'INSERT INTO preferencia_de_avisos (id, notif_preferences, created_at, updated_at, sync_version) '
    "VALUES ('col-1', '{}', 1, 1, 3)",
  ),
);

Future<void> _abrir(
  WidgetTester tester,
  _Base b, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  Telefono? telefono,
}) async {
  final t = telefono ?? Telefono(estado: EstadoSistemaNotificaciones.activadas);
  t.repositorioDeAvisos = AvisosDelServidorLocal(b.local);
  fijarTamano(tester, tamano: tamano, texto: escala);
  await abrirPantalla(tester, t, const NotificacionesPage());
  await _asentar(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

bool _prendido(WidgetTester tester, Finder f) => tester.widget<SwitchListTile>(f).value;

/// Las cuatro guías de accesibilidad de Flutter sobre lo que se ve ahora.
Future<void> _guias(WidgetTester tester, bool reales) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!reales) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// El rectángulo de [f] cabe en la pantalla visible (sin desplazar).
bool _enPantalla(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  final v = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= 0 && r.bottom <= v.height && r.left >= 0 && r.right <= v.width;
}

void main() {
  late _Base base;

  setUp(() => base = _Base());
  tearDown(() async => base.db.close());

  group('24B · con la fila bajada (preferencias, sin conexión de por medio)', () {
    for (final (nombre, tamano, escala, reales) in _matriz) {
      {
        testWidgets(
          '$nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'}: se ve, guías y sin desbordar',
          (tester) async {
            await _fuentes(tester, reales);
            await _sembrar(tester, base);
            await _abrir(tester, base, tamano: tamano, escala: escala);

            expect(_tickets, findsOneWidget);
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_24B_preferencias_${nombre}_$escala');
          },
        );

        testWidgets(
          '$nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'} · sin señal: apagar un aviso guarda y no avisa de '
          'conexión',
          (tester) async {
            await _fuentes(tester, reales);
            await _sembrar(tester, base);
            final t = Telefono(estado: EstadoSistemaNotificaciones.activadas)
              ..conexion.cambiarA(TipoConexion.sinConexion);
            await _abrir(tester, base, tamano: tamano, escala: escala, telefono: t);

            await _tocar(tester, _tickets);

            expect(_prendido(tester, _tickets), isFalse);
            expect(find.textContaining('onexión'), findsNothing);
            expect(find.textContaining('Necesitás'), findsNothing);
            expect(_errorGuardar, findsNothing);
            expect(base.cola.encolados, hasLength(1));
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
          },
        );

        testWidgets(
          '$nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'} · sin fila (primer sync pendiente): el error dice '
          'qué pasó, está a la vista y «Reintentar» se puede tocar',
          (tester) async {
            await _fuentes(tester, reales);
            await _abrir(tester, base, tamano: tamano, escala: escala);

            await _tocar(tester, _cuotas);

            expect(_errorGuardar, findsOneWidget);
            expect(_reintentarGuardar, findsOneWidget);
            expect(_prendido(tester, _cuotas), isTrue, reason: 'volvió a como estaba');
            if (reales) {
              expect(
                _enPantalla(tester, _errorGuardar),
                isTrue,
                reason: 'el aviso de error tiene que verse sin desplazar tras tocar el interruptor',
              );
            }
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_24B_sin_fila_error_${nombre}_$escala');
          },
        );

        testWidgets(
          '$nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'} · error al leer: «Reintentar» y guías',
          (tester) async {
            await _fuentes(tester, reales);
            await _sembrar(tester, base);
            await tester.runAsync(
              () => base.db.customStatement('DROP TABLE preferencia_de_avisos'),
            );
            await _abrir(tester, base, tamano: tamano, escala: escala);

            expect(_errorLeer, findsOneWidget);
            expect(_reintentarLeer, findsOneWidget);
            expect(find.textContaining('onexión'), findsNothing);
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_24B_error_leer_${nombre}_$escala');
          },
        );
      }
    }
  });

  group('casos límite del guardado en el teléfono', () {
    testWidgets('falla a mitad: el botón vuelve a servir y un cambio nuevo se guarda', (
      tester,
    ) async {
      await _sembrar(tester, base);
      await _abrir(tester, base);
      base.cola.fallarCon = StateError('la base no responde');

      await _tocar(tester, _pedidos);
      expect(_prendido(tester, _pedidos), isTrue);
      expect(_errorGuardar, findsOneWidget);

      base.cola.fallarCon = null;
      // Otro cambio distinto (no el «Reintentar»): el aviso se va y se guarda.
      await _tocar(tester, _tickets);
      expect(_errorGuardar, findsNothing);
      expect(_prendido(tester, _tickets), isFalse);
      final guardado = await tester.runAsync(() => base.local.leer());
      expect(guardado!['tickets'], isFalse);
    });

    testWidgets('cambiar la hora de cuotas sin fila: error de la hora y la hora no cambia', (
      tester,
    ) async {
      await _abrir(tester, base);
      final antes = find.byKey(const Key('aviso_cuotas_hora_valor'));
      final textoAntes = tester.widget<Text>(antes).data;

      await tester.ensureVisible(_horaCuota);
      await tester.pump();
      await tester.tap(_horaCuota);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), '7');
      await tester.enterText(campos.at(1), '30');
      await tester.pump();
      await tester.tap(find.text('OK'));
      await _asentar(tester);

      expect(find.textContaining('No pudimos guardar la hora'), findsOneWidget);
      expect(tester.widget<Text>(antes).data, textoAntes);
      expect(find.textContaining('onexión'), findsNothing);
    });

    testWidgets('salir y volver con la fila sin bajar y reintentar cuando baja', (tester) async {
      await _abrir(tester, base);
      await _tocar(tester, _tickets);
      expect(_errorGuardar, findsOneWidget);

      // Se vuelve a abrir la pantalla (reentrada): arranca sin el error de antes.
      await _abrir(tester, base);
      expect(_errorGuardar, findsNothing);

      await _sembrar(tester, base);
      await _tocar(tester, _tickets);
      expect(_errorGuardar, findsNothing);
      expect(_prendido(tester, _tickets), isFalse);
    });

    testWidgets('tres toques rápidos al mismo aviso sin fila: un solo error y ni un job encolado', (
      tester,
    ) async {
      await _abrir(tester, base);
      await tester.ensureVisible(_tickets);
      await tester.pump();
      await tester.tap(_tickets);
      await tester.tap(_tickets);
      await tester.tap(_tickets);
      await _asentar(tester);

      expect(_errorGuardar, findsOneWidget);
      expect(base.cola.encolados, isEmpty);
      expect(_prendido(tester, _tickets), isTrue);
    });
  });
}
