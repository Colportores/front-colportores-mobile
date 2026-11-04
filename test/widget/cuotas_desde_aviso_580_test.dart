// HU-COB-004 / issue #580 — tocar el aviso de la cobranza de una cuota abre las cuotas de esa venta
// (30A-06, `00 Navegacion`: «Notificación o agenda de cobranza»), con la app entera: el recordatorio
// local (con la app abierta o arrancada por el aviso) y el aviso del centro de notificaciones. Una
// agenda que no es cuota sigue abriendo el detalle; la push de cuota vencida (#187) usará el mismo
// destino `agenda/<id>`.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
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
import '../helpers/cuotas_arnes.dart' show paginaLista, volverDeCuotas;
import '../helpers/cuotas_desde_agenda_arnes.dart';
import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/detalle_agenda_arnes.dart';
import '../helpers/persona_falsos.dart';

void main() {
  late RecordatoriosEnMemoria recordatorios;
  late AgendaRepositorioDetalle repo;

  setUp(() {
    recordatorios = RecordatoriosEnMemoria();
    repo = AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDeCuota()));
  });

  Future<void> abrirApp(WidgetTester tester, {bool conSesion = true}) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final plan = planDeLaVenta();
    addTearDown(plan.cerrar);
    final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(
            AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
          ),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          permisoNotificacionesSistemaProvider.overrideWithValue(
            PermisoNotificacionesSistemaEnMemoria(),
          ),
          permisoNotificacionesRepositoryProvider.overrideWithValue(
            PermisoNotificacionesRepositoryEnMemoria(),
          ),
          recordatoriosProvider.overrideWithValue(recordatorios),
          toquesDeRecordatoriosProvider.overrideWithValue(recordatorios),
          agendaRepositoryProvider.overrideWithValue(repo),
          relojVisitaProvider.overrideWithValue(ahoraDelDetalle),
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(casaMataojo()),
          ),
          ...overridesDeLasCuotas(plan),
          // Los enganches de verdad, los mismos que arma `main.dart`.
          ...FlujoDetalleAgenda.enganches(navigatorKeyColportores),
        ],
        child: const ColportoresApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (conSesion) await _ingresar(tester);
  }

  testWidgets(
    'dado la app con la sesión iniciada, cuando se toca el recordatorio de una cuota, se abren '
    'las cuotas de esa venta y no el detalle',
    (tester) async {
      await abrirApp(tester);

      recordatorios.tocar('ag-1');
      await _asentar(tester);

      expect(paginaLista, findsOneWidget);
      expect(find.text('PLAN · 3 CUOTAS SEMANALES'), findsOneWidget);
      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsNothing);

      // Al volver queda la app, no otra pantalla de cuotas.
      await tester.tap(volverDeCuotas);
      await _asentar(tester);
      expect(paginaLista, findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    },
  );

  testWidgets(
    'dado que la app arrancó por el recordatorio de una cuota, cuando la persona ingresa, se '
    'abren las cuotas una sola vez',
    (tester) async {
      recordatorios.tocar('ag-1');
      await abrirApp(tester, conSesion: false);
      expect(paginaLista, findsNothing, reason: 'sin sesión no hay a dónde ir');

      await _ingresar(tester);
      await _asentar(tester);

      expect(paginaLista, findsOneWidget);
      await tester.tap(volverDeCuotas);
      await _asentar(tester);
      expect(paginaLista, findsNothing);
    },
  );

  testWidgets('dos toques seguidos al mismo aviso abren una sola pantalla de cuotas', (
    tester,
  ) async {
    await abrirApp(tester);

    recordatorios
      ..tocar('ag-1')
      ..tocar('ag-1');
    await _asentar(tester);

    expect(paginaLista, findsOneWidget);
    await tester.tap(volverDeCuotas);
    await _asentar(tester);
    expect(paginaLista, findsNothing);
  });

  testWidgets('el recordatorio de una agenda que no es cuota sigue abriendo el detalle', (
    tester,
  ) async {
    repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle());
    await abrirApp(tester);

    recordatorios.tocar('ag-1');
    await _asentar(tester);

    expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
    expect(paginaLista, findsNothing);
  });

  testWidgets('si la agenda no se puede leer, el aviso abre el detalle con su «Reintentar»', (
    tester,
  ) async {
    // La primera lectura (la del aviso) falla; la segunda (la del detalle) también.
    repo.fallasDeLectura.addAll(const [FailureCuotasNoDisponibles(), FailureCuotasNoDisponibles()]);
    await abrirApp(tester);

    recordatorios.tocar('ag-1');
    await _asentar(tester);

    expect(paginaLista, findsNothing);
    expect(find.byKey(ClavesDetalleAgenda.reintentar), findsOneWidget);

    // Y al reintentar con el teléfono bien, el detalle de la cuota ofrece «Ver las cuotas».
    await tester.tap(find.byKey(ClavesDetalleAgenda.reintentar));
    await _asentar(tester);
    expect(find.byKey(ClavesDetalleAgenda.verLasCuotas), findsOneWidget);
  });

  testWidgets('una agenda que ya no está en el teléfono abre el aviso del detalle', (tester) async {
    repo.detalle = null;
    await abrirApp(tester);

    recordatorios.tocar('ag-1');
    await _asentar(tester);

    expect(paginaLista, findsNothing);
    expect(
      find.text('Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.'),
      findsOneWidget,
    );
  });

  testWidgets('dado un aviso del centro de notificaciones con destino a la cobranza de una cuota, '
      'cuando se toca, se abren las cuotas', (tester) async {
    await abrirApp(tester);
    final contexto = tester.element(find.byKey(const Key('inicio_principal')));
    final contenedor = ProviderScope.containerOf(contexto);

    // No se espera: el destino termina cuando se cierran las cuotas.
    unawaited(
      contenedor.read(abridorDestinoNotificacionProvider)(contexto, const DestinoAgenda('ag-1')),
    );
    await _asentar(tester);

    expect(paginaLista, findsOneWidget);
    expect(find.byKey(ClavesDetalleAgenda.titulo), findsNothing);
  });

  testWidgets('el aviso del centro de una agenda que no es cuota abre el detalle', (tester) async {
    repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle());
    await abrirApp(tester);
    final contexto = tester.element(find.byKey(const Key('inicio_principal')));
    final contenedor = ProviderScope.containerOf(contexto);

    unawaited(
      contenedor.read(abridorDestinoNotificacionProvider)(contexto, const DestinoAgenda('ag-1')),
    );
    await _asentar(tester);

    expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
    expect(paginaLista, findsNothing);
  });
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
