// El aviso sutil de Hoy cuando las notificaciones siguen apagadas (HU-NOT-001, 24A·03): se muestra
// solo en Hoy, con el texto de la HU, «Ir a configuración» y la ✕; no vuelve una vez cerrado y se
// va solo si las activan. Sobre la pantalla principal con el teléfono de los otros tests.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/notificaciones_arnes.dart';

final _ahora = DateTime(2026, 10, 9, 9, 30);
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

Telefono _conAviso() {
  final telefono = Telefono();
  telefono.recuerdo.pedido = PedidoNotificaciones.ahoraNo;
  return telefono;
}

/// Abre la pantalla principal; un `ProviderScope` nuevo cada vez («cerrar y volver a abrir»).
Future<void> _montar(WidgetTester tester, Telefono telefono) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        ...overridesPestanaMapa(),
        ...telefono.overrides,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('cuándo se muestra', () {
    testWidgets('dijo «Ahora no»: aparece en Hoy con el texto de la HU', (tester) async {
      await _montar(tester, _conAviso());

      expect(avisoApagadas, findsOneWidget);
      expect(find.text(textoAviso), findsOneWidget);
      expect(find.text('Ir a configuración'), findsOneWidget);
    });

    testWidgets('el sistema ya le preguntó y siguen apagadas: aparece también', (tester) async {
      final telefono = Telefono();
      telefono.recuerdo.pedido = PedidoNotificaciones.sistema;
      await _montar(tester, telefono);

      expect(avisoApagadas, findsOneWidget);
    });

    testWidgets('con las notificaciones activadas no ocupa lugar', (tester) async {
      await _montar(tester, Telefono(estado: EstadoSistemaNotificaciones.activadas));

      expect(avisoApagadas, findsNothing);
      expect(avisoIr, findsNothing);
    });

    testWidgets('si todavía no contestó el pedido no se muestra (el pedido va antes)', (
      tester,
    ) async {
      await _montar(tester, Telefono());

      expect(avisoApagadas, findsNothing);
    });

    testWidgets('si el sistema no contesta, no aparece ni rompe la pantalla', (tester) async {
      final telefono = _conAviso();
      telefono.sistema.fallaAlLeer = true;
      await _montar(tester, telefono);

      expect(avisoApagadas, findsNothing);
      expect(principal, findsOneWidget);
    });

    testWidgets('solo está en Hoy: en otra pestaña no se ve, y vuelve al regresar a Hoy', (
      tester,
    ) async {
      await _montar(tester, _conAviso());

      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(avisoApagadas, findsNothing);

      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();
      expect(avisoApagadas, findsOneWidget);
    });
  });

  group('la ✕', () {
    testWidgets('lo cierra y queda anotado', (tester) async {
      final telefono = _conAviso();
      await _montar(tester, telefono);

      await tester.tap(avisoCerrar);
      await tester.pumpAndSettle();

      expect(avisoApagadas, findsNothing);
      expect(telefono.recuerdo.avisoCerrado, isTrue);
    });

    testWidgets('no vuelve al reabrir la app (esta instalación)', (tester) async {
      final telefono = _conAviso();
      await _montar(tester, telefono);
      await tester.tap(avisoCerrar);
      await tester.pumpAndSettle();

      await _montar(tester, telefono);

      expect(avisoApagadas, findsNothing);
    });

    testWidgets('dos toques seguidos no rompen nada', (tester) async {
      final telefono = _conAviso();
      await _montar(tester, telefono);

      await tester.tap(avisoCerrar);
      await tester.tap(avisoCerrar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(avisoApagadas, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si no se pudo guardar, igual se cierra mientras la app siga abierta', (
      tester,
    ) async {
      final telefono = _conAviso();
      telefono.recuerdo.fallaAlAnotar = true;
      await _montar(tester, telefono);

      await tester.tap(avisoCerrar);
      await tester.pumpAndSettle();

      expect(avisoApagadas, findsNothing);
    });
  });

  group('«Ir a configuración»', () {
    testWidgets('abre Configuración › Notificaciones y al volver el aviso sigue', (tester) async {
      await _montar(tester, _conAviso());

      await tester.tap(avisoIr);
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsOneWidget);

      await tester.tap(find.byKey(const Key('notificaciones_atras')));
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsNothing);
      expect(avisoApagadas, findsOneWidget);
    });

    testWidgets('dos toques seguidos abren una sola pantalla', (tester) async {
      await _montar(tester, _conAviso());

      await tester.tap(avisoIr);
      await tester.tap(avisoIr, warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificaciones_atras')));
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsNothing);
      expect(principal, findsOneWidget);
    });

    testWidgets('si desde ahí las activa, al volver el aviso ya no está', (tester) async {
      final telefono = _conAviso();
      await _montar(tester, telefono);
      await tester.tap(avisoIr);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificaciones_activar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('notificaciones_atras')));
      await tester.pumpAndSettle();

      expect(avisoApagadas, findsNothing);
    });
  });

  group('las activa en los ajustes del teléfono', () {
    testWidgets('al volver a la app el aviso se va solo', (tester) async {
      final telefono = _conAviso();
      await _montar(tester, telefono);
      expect(avisoApagadas, findsOneWidget);

      telefono.sistema.estado = EstadoSistemaNotificaciones.activadas;
      final contenedor = contenedorDe(tester);
      await contenedor.read(notificacionesProvider.notifier).refrescar();
      await tester.pumpAndSettle();

      expect(avisoApagadas, findsNothing);
    });
  });

  group('casos límite', () {
    for (final (nombre, tamano, texto) in [
      ('texto al 200 %', const Size(390, 844), 2.0),
      ('texto al 200 % en un teléfono de 360 × 640', const Size(360, 640), 2.0),
    ]) {
      testWidgets('con $nombre ocupa a lo sumo el 40 % del alto y sus botones se alcanzan', (
        tester,
      ) async {
        fijarTamano(tester, tamano: tamano, texto: texto);
        await _montar(tester, _conAviso());

        expect(tester.takeException(), isNull);
        final franja = find
            .ancestor(of: avisoApagadas, matching: find.byType(SingleChildScrollView))
            .first;
        expect(tester.getSize(franja).height, lessThanOrEqualTo(tamano.height * 0.4 + 0.01));
        await tester.ensureVisible(avisoIr);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(avisoCerrar);
        await tester.pump();
        expect(tester.getSize(avisoCerrar).shortestSide, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('el aviso se anuncia como región viva y la ✕ tiene nombre para el lector', (
      tester,
    ) async {
      await _montar(tester, _conAviso());

      expect(tester.getSemantics(avisoApagadas), isSemantics(isLiveRegion: true));
      expect(find.byTooltip('Cerrar aviso'), findsOneWidget);
    });

    testWidgets('cumple las guías de accesibilidad de Flutter', (tester) async {
      await _montar(tester, _conAviso());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });

  test('la clave del aviso cerrado no pisa la del pedido', () {
    // Dos claves distintas: cerrar el aviso no cuenta como haber contestado el pedido.
    final telefono = _conAviso();
    unawaited(telefono.recuerdo.anotarAvisoCerrado());
    expect(telefono.recuerdo.pedido, PedidoNotificaciones.ahoraNo);
  });
}
