// #769 (revisión de #773): «Reintentar» tras bajar la fila de preferencias no pisa lo del servidor con los valores de
// siempre (la lectura de antes de la primera sincronización era la de «sin fila»).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
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

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets(
    'Reintentar tras bajar la fila no pisa lo que ya había en el servidor, solo suma el cambio pedido',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      addTearDown(db.close);
      final cola = EncoladorSyncEnMemoria();
      final local = PreferenciasDeAvisosLocalDataSourceDrift(
        db,
        encolador: cola,
        usuarioId: () => 'col-1',
        ahora: () => DateTime.utc(2026, 11, 26, 15),
      );
      final t = Telefono(estado: EstadoSistemaNotificaciones.activadas)
        ..repositorioDeAvisos = AvisosDelServidorLocal(local);
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: t.overrides,
          child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
        ),
      );
      await _asentar(tester);
      final tickets = find.byKey(const Key('aviso_tickets_interruptor'));
      await tester.ensureVisible(tickets);
      await tester.tap(tickets);
      await _asentar(tester);
      expect(find.byKey(const Key('avisos_error_guardar')), findsOneWidget);
      // baja la fila del servidor con lo que la persona ya tenia: pedidos apagado y cuotas a las 07:00
      await tester.runAsync(
        () => db.customStatement(
          'INSERT INTO preferencia_de_avisos (id, notif_preferences, created_at, updated_at, sync_version) '
          '''VALUES ('col-1', '{"pedidos":false,"hora_cuota":"07:00"}', 1, 1, 3)''',
        ),
      );
      final antes = await tester.runAsync(() => local.leer());
      expect(antes, {'pedidos': false, 'hora_cuota': '07:00'});
      final reintentar = find.byKey(const Key('avisos_error_reintentar'));
      await tester.ensureVisible(reintentar);
      await tester.tap(reintentar);
      await _asentar(tester);
      final despues = await tester.runAsync(() => local.leer());
      // Lo que la persona ya tenía (Pedidos apagado, cuotas a las 07:00) sigue, y se suma lo que pidió (Tickets).
      expect(despues, containsPair('pedidos', false));
      expect(despues, containsPair('hora_cuota', '07:00'));
      expect(despues, containsPair('tickets', false));
      // La pantalla muestra lo que quedó guardado (Pedidos apagado), no los valores de siempre.
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('aviso_pedidos_interruptor'))).value,
        isFalse,
      );
    },
  );
}
