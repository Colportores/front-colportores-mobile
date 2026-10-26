// Falsos y arnés de la vista 25 (estado de sincronización, «Actualizar ahora» y modo ahorro,
// HU-SYNC-007 y HU-SYNC-008): un servicio de sync controlable desde el test, el teléfono (conexión,
// modo ahorro guardado) y la pantalla suelta con el tema de la app.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/sync/modo_ahorro_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/sincronizacion/data/repositories/modo_ahorro_repository_impl.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/services/servicio_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/pages/sincronizacion_page.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/providers/sincronizacion_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// El motor de sync visto desde la pantalla, controlado por el test.
final class ServicioSincronizacionFalso implements ServicioSincronizacion {
  ServicioSincronizacionFalso({
    this.actual = const EstadoSincronizacion(),
    List<OperacionFallida> fallidas = const [],
  }) : fallidas = List.of(fallidas);

  /// El estado que ve la pantalla.
  EstadoSincronizacion actual;
  final _cambios = StreamController<EstadoSincronizacion>.broadcast();

  List<OperacionFallida> fallidas;

  /// Si es `true`, [estado] lanza (el motor no se deja leer).
  bool fallaAlLeer = false;

  /// Si no es `null`, [estado] espera a que se complete (la pantalla muestra «cargando»).
  Completer<void>? lecturaLenta;

  /// Si no es `null`, [actualizarAhora] espera a que el test lo complete (queda «Actualizando…»).
  Completer<ResultadoActualizacion>? actualizacionEnCurso;

  /// Lo que contesta [actualizarAhora] cuando no hay [actualizacionEnCurso].
  ResultadoActualizacion resultado = const ActualizacionCompleta();

  /// Si es `true`, [actualizarAhora] lanza (algo salió mal por dentro).
  bool lanzaAlActualizar = false;

  /// Si es `true`, [operacionesFallidas] lanza.
  bool fallaAlLeerFallidas = false;

  /// Si es `true`, [reintentarFallidas] lanza.
  bool lanzaAlReintentar = false;

  int llamadasActualizar = 0;
  final reintentos = <String?>[];
  final modoAhorroAplicado = <bool>[];

  /// Cambia el estado y avisa, como cuando el motor emite.
  void emitir(EstadoSincronizacion nuevo) {
    actual = nuevo;
    _cambios.add(nuevo);
  }

  @override
  Future<EstadoSincronizacion> estado() async {
    if (lecturaLenta case final espera?) await espera.future;
    if (fallaAlLeer) throw StateError('no se pudo leer');
    return actual;
  }

  @override
  Stream<EstadoSincronizacion> get cambios => _cambios.stream;

  @override
  Future<ResultadoActualizacion> actualizarAhora() async {
    llamadasActualizar++;
    if (lanzaAlActualizar) throw StateError('falló por dentro');
    if (actualizacionEnCurso case final espera?) return espera.future;
    return resultado;
  }

  @override
  Future<List<OperacionFallida>> operacionesFallidas() async {
    if (fallaAlLeerFallidas) throw StateError('no se pudo leer');
    return List.of(fallidas);
  }

  @override
  Future<int> reintentarFallidas({String? id}) async {
    reintentos.add(id);
    if (lanzaAlReintentar) throw StateError('no se pudo reencolar');
    if (id == null) {
      final n = fallidas.length;
      fallidas = [];
      return n;
    }
    fallidas = fallidas.where((f) => f.id != id).toList();
    return 1;
  }

  @override
  void aplicarModoAhorro({required bool activo}) => modoAhorroAplicado.add(activo);

  Future<void> cerrar() => _cambios.close();
}

/// Una conexión que el test mueve.
final class ConexionFalsa implements MonitorConectividad {
  ConexionFalsa([this.tipo = TipoConexion.wifi]);

  TipoConexion tipo;
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

/// El teléfono de la pantalla de sincronización: el motor, la conexión y el modo ahorro guardado.
final class TelefonoSync {
  TelefonoSync({
    EstadoSincronizacion estado = const EstadoSincronizacion(
      ultimoEnvio: null,
      ultimaActualizacion: null,
    ),
    List<OperacionFallida> fallidas = const [],
    TipoConexion conexion = TipoConexion.wifi,
    bool modoAhorro = false,
    this.respaldoConfigurado = false,
    this.conectarDrive,
    DateTime? ahora,
  }) : servicio = ServicioSincronizacionFalso(actual: estado, fallidas: fallidas),
       red = ConexionFalsa(conexion),
       guardado = ModoAhorroRepositoryEnMemoria(activo: modoAhorro),
       ahora = ahora ?? DateTime(2026, 10, 26, 14, 35);

  final ServicioSincronizacionFalso servicio;
  final ConexionFalsa red;
  final ModoAhorroRepositoryEnMemoria guardado;
  final bool respaldoConfigurado;
  final VoidCallback? conectarDrive;
  final DateTime ahora;

  List<Override> get overrides => [
    servicioSincronizacionProvider.overrideWithValue(servicio),
    monitorConectividadProvider.overrideWithValue(red),
    modoAhorroRepositoryProvider.overrideWithValue(guardado),
    modoAhorroInicialProvider.overrideWithValue(guardado.activo),
    ahoraSincronizacionProvider.overrideWithValue(() => ahora),
    respaldoConfiguradoProvider.overrideWithValue(respaldoConfigurado),
    conectarDriveProvider.overrideWithValue(conectarDrive),
  ];
}

/// Una operación rechazada de ejemplo: «Venta del 22/10».
OperacionFallida operacionFallida({
  String id = 'op-1',
  String tabla = 'venta',
  TipoOperacion tipo = TipoOperacion.alta,
  DateTime? fecha,
  String codigo = '23514',
  String error = 'Nuestros Hijos ya no tiene precio en Montevideo',
}) => OperacionFallida(
  id: id,
  tabla: tabla,
  tipo: tipo,
  fecha: fecha ?? DateTime(2026, 10, 22, 14, 20),
  codigo: codigo,
  error: error,
);

/// La pantalla de sincronización suelta, con el tema de la app, sobre [telefono].
Future<void> abrirSincronizacion(
  WidgetTester tester,
  TelefonoSync telefono, {
  Size tamano = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: telefono.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const SincronizacionPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final pagina = find.byKey(const Key('sincronizacion_pagina'));
final tarjetaTitulo = find.byKey(const Key('sincronizacion_titulo'));
final tarjetaDetalle = find.byKey(const Key('sincronizacion_detalle'));
final botonActualizar = find.byKey(const Key('sincronizacion_actualizar'));
final cargando = find.byKey(const Key('sincronizacion_cargando'));
final interruptorAhorro = find.byKey(const Key('sincronizacion_modo_ahorro'));
final avisoSinConexion = find.byKey(const Key('sincronizacion_aviso_sin_conexion'));
final avisoError = find.byKey(const Key('sincronizacion_aviso_error'));
final avisoAhorro = find.byKey(const Key('sincronizacion_aviso_ahorro'));
final avisoSinRespaldo = find.byKey(const Key('sincronizacion_aviso_sin_respaldo'));
final conectarDriveBoton = find.byKey(const Key('sincronizacion_conectar_drive'));
final toastListo = find.byKey(const Key('sincronizacion_listo'));
final hojaDatos = find.byKey(const Key('sincronizacion_hoja_datos'));
final hojaDetalle = find.byKey(const Key('sincronizacion_hoja_detalle'));

String textoDe(Finder finder) => (finder.evaluate().single.widget as Text).data ?? '';
