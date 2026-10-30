// Arnés de los tests del permiso de notificaciones (HU-NOT-001, vista 24, grupo A): el teléfono (lo
// que dice el sistema y lo que recuerda la app, que sobreviven a «cerrar y volver a abrir la app»),
// la app entera con la sesión ya iniciada y una pantalla suelta.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'agendas_para_recordar_falsas.dart';
import 'db_local_repository_en_memoria.dart';

/// El teléfono: lo que dice el sistema, lo que la app recuerda, la sesión y la conexión.
final class Telefono {
  Telefono({EstadoSistemaNotificaciones estado = EstadoSistemaNotificaciones.apagadas})
    : sistema = PermisoNotificacionesSistemaEnMemoria(estado: estado);

  final PermisoNotificacionesSistemaEnMemoria sistema;
  final recuerdo = PermisoNotificacionesRepositoryEnMemoria();
  final sesionGuardada = AuthLocalDataSourceEnMemoria();
  final conexion = _Conexion();

  /// Las preferencias de los recordatorios (HU-NOT-004), los recordatorios del teléfono y las agendas
  /// que esperan el suyo.
  final preferencias = PreferenciasRecordatoriosRepositoryEnMemoria();
  final recordatorios = RecordatoriosEnMemoria();
  final agendas = AgendasParaRecordarEnMemoria();

  List<Override> get overrides => [
    preferenciasRecordatoriosRepositoryProvider.overrideWithValue(preferencias),
    recordatoriosProvider.overrideWithValue(recordatorios),
    agendasParaRecordarProvider.overrideWithValue(agendas),
    permisoNotificacionesSistemaProvider.overrideWithValue(sistema),
    permisoNotificacionesRepositoryProvider.overrideWithValue(recuerdo),
    monitorConectividadProvider.overrideWithValue(conexion),
  ];
}

final class _Conexion implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;
  final _cambios = StreamController<TipoConexion>.broadcast();

  void cambiarA(TipoConexion nuevo) {
    tipo = nuevo;
    _cambios.add(nuevo);
  }

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => _cambios.stream;
}

final pedidoPagina = find.byKey(const Key('permiso_notificaciones_pagina'));
final pedidoActivar = find.byKey(const Key('permiso_notificaciones_activar'));
final pedidoAhoraNo = find.byKey(const Key('permiso_notificaciones_ahora_no'));
final pedidoFallo = find.byKey(const Key('permiso_notificaciones_fallo'));
final pedidoPidiendo = find.byKey(const Key('permiso_notificaciones_pidiendo'));
final principal = find.byKey(const Key('inicio_principal'));
final avisoApagadas = find.byKey(const Key('aviso_notificaciones_texto'));
final avisoIr = find.byKey(const Key('aviso_notificaciones_ir'));
final avisoCerrar = find.byKey(const Key('aviso_notificaciones_cerrar'));
final toastActivadas = find.byKey(const Key('notificaciones_activadas_aviso'));
final paginaNotificaciones = find.byKey(const Key('notificaciones_pagina'));

const textoToast = 'Notificaciones activadas.';
const textoToastSinConexion =
    'Activadas. Los recordatorios ya funcionan; los avisos de tu coordinador empiezan a llegar '
    'cuando haya conexión.';
const textoAviso = 'Las notificaciones están apagadas. Podés activarlas en configuración.';
const textoApagadas =
    'Las notificaciones están apagadas en el teléfono. Estas opciones valen cuando las actives.';
const textoBloqueadas =
    'Las notificaciones están bloqueadas en los ajustes del teléfono. Desde la app no las '
    'podemos activar.';

/// Abre la app entera con la sesión de `ana@example.com` ya iniciada (o la inicia la primera vez) y
/// la DB local lista. Un `ProviderScope` nuevo cada vez: «cerrar y volver a abrir la app» con el
/// mismo [telefono].
Future<void> abrirApp(WidgetTester tester, Telefono telefono, {bool iniciarSesion = true}) async {
  _tamanoDeTelefonoSiNoSeFijo(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(telefono.sesionGuardada),
        ...telefono.overrides,
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (iniciarSesion && find.byKey(const Key('login_enviar')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
    await tester.ensureVisible(find.byKey(const Key('login_enviar')));
    await tester.tap(find.byKey(const Key('login_enviar')));
    await tester.pumpAndSettle();
  }
}

/// Una pantalla suelta (con el tema de la app) sobre el mismo teléfono.
Future<void> abrirPantalla(
  WidgetTester tester,
  Telefono telefono,
  Widget pantalla, {
  Key? clave,
}) async {
  _tamanoDeTelefonoSiNoSeFijo(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: clave ?? UniqueKey(),
      overrides: telefono.overrides,
      child: MaterialApp(theme: temaClaro(), home: pantalla),
    ),
  );
  await tester.pumpAndSettle();
}

/// Como [abrirPantalla], pero sin esperar a que termine de cargar: para ver el estado «cargando».
Future<void> abrirPantallaSinEsperar(
  WidgetTester tester,
  Telefono telefono,
  Widget pantalla,
) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: telefono.overrides,
      child: MaterialApp(theme: temaClaro(), home: pantalla),
    ),
  );
  await tester.pump();
}

/// Un test que no eligió el tamaño con [fijarTamano] corre en un teléfono común de 390 × 844 (la
/// superficie por defecto de los tests es de escritorio, 800 × 600).
bool _tamanoElegido = false;

void _tamanoDeTelefonoSiNoSeFijo(WidgetTester tester) {
  if (_tamanoElegido) return;
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Sale de la app y vuelve (por ejemplo, a los ajustes del teléfono y de regreso).
void volverALaApp(WidgetTester tester) {
  for (final estado in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(estado);
  }
}

void fijarTamano(WidgetTester tester, {Size tamano = const Size(390, 844), double texto = 1}) {
  _tamanoElegido = true;
  addTearDown(() => _tamanoElegido = false);
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// El contenedor de providers de la app abierta.
ProviderContainer contenedorDe(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
