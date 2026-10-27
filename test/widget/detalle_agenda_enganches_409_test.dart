// HU-VIS-003 / issue #409 — los enganches del detalle de una agenda con la app entera: tocar un
// recordatorio (con la app ya abierta o arrancada por el aviso) y tocar un aviso del centro de
// notificaciones abren el detalle real (23C·01), una sola vez y con la agenda de ese aviso.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_detalle_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/agendar_visita_arnes.dart' show casaMataojo, mariaFernandez;
import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/detalle_agenda_arnes.dart';
import '../helpers/persona_falsos.dart';

void main() {
  late RecordatoriosEnMemoria recordatorios;
  late AgendaRepositorioDetalle repo;

  setUp(() {
    recordatorios = RecordatoriosEnMemoria();
    repo = AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDelDetalle(id: 'ag-1')));
  });

  Future<void> abrirApp(WidgetTester tester, {required bool conSesion}) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sesionGuardada = AuthLocalDataSourceEnMemoria();
    final recuerdo = PermisoNotificacionesRepositoryEnMemoria();
    final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
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
          agendaRepositoryProvider.overrideWithValue(repo),
          relojVisitaProvider.overrideWithValue(ahoraDelDetalle),
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(casaMataojo()),
          ),
          // Los enganches de verdad, los mismos que arma `main.dart`.
          ...FlujoDetalleAgenda.enganches(navigatorKeyColportores),
        ],
        child: const ColportoresApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (conSesion) await _ingresar(tester);
  }

  testWidgets('dado que la app arrancó por un recordatorio, cuando la persona ingresa, se abre el '
      'detalle real de esa agenda una sola vez', (tester) async {
    recordatorios.tocar('ag-1');
    await abrirApp(tester, conSesion: false);
    expect(
      find.byKey(ClavesDetalleAgenda.titulo),
      findsNothing,
      reason: 'sin sesión no hay a dónde ir',
    );

    await _ingresar(tester);
    await _asentar(tester);

    expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
    expect(find.text('María Fernández · Mataojo 2044 · Depto 3B'), findsOneWidget);
    expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
    expect(repo.lecturas, 1, reason: 'una sola apertura');
  });

  testWidgets(
    'dado la app con la sesión iniciada, cuando se toca un recordatorio, se abre el detalle '
    'de esa agenda',
    (tester) async {
      await abrirApp(tester, conSesion: true);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsNothing);

      recordatorios.tocar('ag-1');
      await _asentar(tester);

      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(find.text('Sáb 24/10 · 14:30'), findsOneWidget);
    },
  );

  testWidgets('una agenda que ya no está en el teléfono: el recordatorio abre el aviso, no una '
      'pantalla rota', (tester) async {
    repo.detalle = null;
    await abrirApp(tester, conSesion: true);
    recordatorios.tocar('ag-1');
    await _asentar(tester);
    expect(
      find.text('Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'dado un aviso del centro de notificaciones con destino a una agenda, cuando se toca, '
    'se abre el detalle de esa agenda',
    (tester) async {
      await abrirApp(tester, conSesion: true);
      final contexto = tester.element(find.byKey(const Key('inicio_principal')));
      final contenedor = ProviderScope.containerOf(contexto);

      // No se espera: el destino termina cuando se cierra el detalle.
      unawaited(
        contenedor.read(abridorDestinoNotificacionProvider)(contexto, const DestinoAgenda('ag-1')),
      );
      await _asentar(tester);

      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
    },
  );
}

Future<void> _ingresar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.ensureVisible(find.byKey(const Key('login_enviar')));
  await tester.tap(find.byKey(const Key('login_enviar')));
  await tester.pumpAndSettle();
}

/// Deja correr los fotogramas sin esperar a los indicadores que giran para siempre.
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
