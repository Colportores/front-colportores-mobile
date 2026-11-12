// HU-NOT-002 / issue #453 — «Tocar el recordatorio abre el detalle de esa visita»: con la app entera,
// el recordatorio que abrió la app (o que se toca después) llega al enganche de la vista 23.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

void main() {
  late RecordatoriosEnMemoria recordatorios;
  late List<String> abiertas;

  setUp(() {
    recordatorios = RecordatoriosEnMemoria();
    abiertas = [];
  });

  Future<void> abrirApp(WidgetTester tester, {required bool conSesion}) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sesionGuardada = AuthLocalDataSourceEnMemoria();
    final recuerdo = PermisoNotificacionesRepositoryEnMemoria();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(
            AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
          ),
          authLocalDataSourceProvider.overrideWithValue(sesionGuardada),
          permisoNotificacionesSistemaProvider.overrideWithValue(
            PermisoNotificacionesSistemaEnMemoria(),
          ),
          permisoNotificacionesRepositoryProvider.overrideWithValue(recuerdo),
          recordatoriosProvider.overrideWithValue(recordatorios),
          toquesDeRecordatoriosProvider.overrideWithValue(recordatorios),
          abridorDetalleAgendaProvider.overrideWithValue(abiertas.add),
        ],
        child: const ColportoresApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (conSesion) {
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.ensureVisible(find.byKey(const Key('login_enviar')));
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('dado que la app arrancó por un recordatorio, cuando la persona ingresa, se abre el '
      'detalle de esa visita una sola vez', (tester) async {
    recordatorios.tocar('ag-1');
    await abrirApp(tester, conSesion: false);
    expect(abiertas, isEmpty, reason: 'sin sesión no hay a dónde ir');

    await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
    await tester.ensureVisible(find.byKey(const Key('login_enviar')));
    await tester.tap(find.byKey(const Key('login_enviar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    expect(abiertas, ['ag-1']);
  });

  testWidgets('dado la app con la sesión iniciada, cuando se toca un recordatorio, se abre el '
      'detalle de esa visita', (tester) async {
    await abrirApp(tester, conSesion: true);
    expect(abiertas, isEmpty);

    recordatorios.tocar('ag-2');
    await tester.pump();

    expect(abiertas, ['ag-2']);
  });
}
