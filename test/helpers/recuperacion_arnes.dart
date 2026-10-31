// Arnés de los tests del asistente de recuperación (HU-SYNC-006, vista 34, #175): un servicio de
// recuperación que hace lo que el test le diga, el almacén de «ya resolvió», el lector de lo que hay
// en la base y la pantalla suelta sobre todo eso.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/recuperacion_resuelta_repository.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/lector_de_lo_recuperado.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:colportores_mobile/features/respaldo/presentation/pages/recuperacion_page.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'respaldo_drive_falsos.dart';

/// El respaldo del canvas: «Respaldo del 22/10 a las 03:10 · 15 partes · 38 MB». La fecha va en hora
/// del teléfono, así el texto no depende de la zona de la máquina de pruebas.
final respaldoDePrueba = RespaldoEnDrive(
  llave: 'llave-1',
  fecha: DateTime(2026, 10, 22, 3, 10),
  partes: 15,
  bytes: 38 * 1024 * 1024,
  completo: true,
  tieneLlave: true,
);

InformeRecuperacion informeDePrueba({
  bool parcial = false,
  int restauradas = 15,
  int totales = 15,
  DateTime? fecha,
}) => InformeRecuperacion(
  fechaDelRespaldo: fecha ?? DateTime(2026, 10, 22, 3, 10),
  parcial: parcial,
  partesRestauradas: restauradas,
  partesTotales: totales,
  trabajosReenviados: 0,
  filasTraidas: const {},
  ahora: DateTime(2026, 10, 25, 9),
);

/// [ServicioRecuperacion] que hace lo que el test le diga.
final class ServicioRecuperacionFalso implements ServicioRecuperacion {
  /// Lo que encuentra `buscar` (la próxima vez que se llame).
  BusquedaRespaldo busqueda = RespaldoEncontrado(respaldoDePrueba);

  /// Lo que devuelve `recuperar`.
  ResultadoRecuperacion resultado = RecuperacionHecha(informeDePrueba());

  /// Si no es `null`, `buscar` espera a que el test la complete (se ve «Buscando…»).
  Completer<void>? compuertaBuscar;

  /// Si no es `null`, `recuperar` espera a que el test la complete (se ve «Restaurando…»).
  Completer<void>? compuertaRecuperar;

  /// Hace que [recuperar] espere a una compuerta que se crea al llamarlo, dentro del reloj falso
  /// del test (un `Completer` creado en un `setUp` no avanza con `tester.pump`).
  bool frenarRecuperar = false;

  /// Lo que `recuperar` informa antes de esperar o terminar.
  List<ProgresoRecuperacion> progresos = const [];

  Object? errorAlBuscar;
  Object? errorAlRecuperar;

  /// Lo que la pantalla le dio para informar el avance: el test lo usa para avanzar a mitad de camino.
  void Function(ProgresoRecuperacion progreso)? alAvanzarActual;

  int busquedas = 0;
  int recuperaciones = 0;
  String? ultimaContrasena;
  CancelacionRecuperacion? ultimaCancelacion;
  RespaldoEnDrive? ultimoRespaldo;

  /// Si es `true`, `recuperar` termina con [RecuperacionCancelada] cuando la persona cancela (como
  /// el motor), en vez de devolver [resultado].
  bool respetaLaCancelacion = true;

  @override
  Future<BusquedaRespaldo> buscar() async {
    busquedas++;
    await compuertaBuscar?.future;
    if (errorAlBuscar case final e?) throw e;
    return busqueda;
  }

  @override
  Future<ResultadoRecuperacion> recuperar({
    required RespaldoEnDrive respaldo,
    required String password,
    void Function(ProgresoRecuperacion progreso)? alAvanzar,
    CancelacionRecuperacion? cancelar,
  }) async {
    recuperaciones++;
    ultimaContrasena = password;
    ultimaCancelacion = cancelar;
    ultimoRespaldo = respaldo;
    alAvanzarActual = alAvanzar;
    progresos.forEach(alAvanzar ?? (_) {});
    if (frenarRecuperar) compuertaRecuperar ??= Completer<void>();
    await compuertaRecuperar?.future;
    if (errorAlRecuperar case final e?) throw e;
    if (respetaLaCancelacion && (cancelar?.cancelada ?? false)) {
      return const RecuperacionCancelada();
    }
    return resultado;
  }
}

/// Lo que hay en la base según el test.
final class LectorFalso implements LectorDeLoRecuperado {
  bool sinDatos = true;
  Object? errorAlMirar;
  int miradas = 0;
  ResumenDeLoRecuperado resumenAlRecuperar = const ResumenDeLoRecuperado(
    ubicaciones: 214,
    personas: 96,
    ventas: 41,
    cobros: 63,
  );
  Object? errorAlResumir;

  @override
  Future<bool> baseSinDatos() async {
    miradas++;
    if (errorAlMirar case final e?) throw e;
    return sinDatos;
  }

  @override
  Future<ResumenDeLoRecuperado> resumen() async {
    if (errorAlResumir case final e?) throw e;
    return resumenAlRecuperar;
  }
}

/// Los usuarios que ya resolvieron el asistente, en memoria.
final class ResueltaEnMemoria implements RecuperacionResueltaRepository {
  final Set<String> usuarios = {};
  Object? errorAlLeer;
  int marcas = 0;

  /// Si no es `null`, `marcarResuelta` espera a que el test la complete.
  Completer<void>? compuertaMarcar;

  @override
  Future<bool> estaResuelta(String usuarioId) async {
    if (errorAlLeer case final e?) throw e;
    return usuarios.contains(usuarioId);
  }

  @override
  Future<void> marcarResuelta(String usuarioId) async {
    marcas++;
    await compuertaMarcar?.future;
    usuarios.add(usuarioId);
  }
}

/// Una sesión fija (la de [usuarioDePrueba]) o ninguna.
class SesionFijaParaRecuperacion extends SesionNotifier {
  SesionFijaParaRecuperacion(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

const usuarioDePrueba = 'u-1';

Sesion sesionDePrueba() => Sesion(
  usuarioId: usuarioDePrueba,
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2030),
);

/// La conexión del teléfono a mano.
final class ConexionControlable implements MonitorConectividad {
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

/// Todo lo del asistente junto, para armar los `overrides`.
final class ArnesRecuperacion {
  ArnesRecuperacion();

  final servicio = ServicioRecuperacionFalso();
  final lector = LectorFalso();
  final resuelta = ResueltaEnMemoria();
  final conexion = ConexionControlable();

  /// Perezoso a propósito: el repositorio arma una cola de `Future`s, y si se creara en un `setUp`
  /// (fuera del reloj falso de `testWidgets`) sus pasos no avanzarían con `tester.pump`.
  late final RespaldoDriveArmado drive = RespaldoDriveArmado();

  /// Lo del asistente solo: sirve para armar la app entera, que trae su propia sesión y conexión.
  List<Override> get overridesDelAsistente => [
    asistenteDeRecuperacionHabilitadoProvider.overrideWithValue(true),
    servicioRecuperacionProvider.overrideWithValue(servicio),
    lectorDeLoRecuperadoProvider.overrideWithValue(lector),
    recuperacionResueltaRepositoryProvider.overrideWithValue(resuelta),
    respaldoDriveRepositoryProvider.overrideWithValue(drive.repo),
  ];

  /// Lo del asistente más una sesión fija y la conexión a mano: para la pantalla suelta.
  List<Override> get overrides => [
    ...overridesDelAsistente,
    monitorConectividadProvider.overrideWithValue(conexion),
    sesionProvider.overrideWith(() => SesionFijaParaRecuperacion(sesionDePrueba())),
  ];
}

// Las partes de la pantalla.
final pagina = find.byKey(const Key('recuperacion_pagina'));
final titulo = find.byKey(const Key('recuperacion_titulo'));
final paso = find.byKey(const Key('recuperacion_paso'));
final cta = find.byKey(const Key('recuperacion_cta'));
final cta2 = find.byKey(const Key('recuperacion_cta2'));
final buscando = find.byKey(const Key('recuperacion_buscando'));
final tarjeta = find.byKey(const Key('recuperacion_tarjeta'));
final campoContrasena = find.byKey(const Key('recuperacion_contrasena'));
final errorContrasena = find.byKey(const Key('recuperacion_contrasena_error'));
final verContrasena = find.byKey(const Key('recuperacion_contrasena_ver'));
final progresoValor = find.byKey(const Key('recuperacion_progreso_valor'));
final progresoBarra = find.byKey(const Key('recuperacion_progreso_barra'));
final heroTexto = find.byKey(const Key('recuperacion_hero_texto'));

/// El texto del botón principal o del secundario.
String textoDe(Finder boton) => find
    .descendant(of: boton, matching: find.byType(Text))
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .join(' ');

void fijarTelefono(WidgetTester tester, {Size tamano = const Size(390, 844), double escala = 1}) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// El asistente suelto sobre el arnés.
Future<void> abrirAsistente(
  WidgetTester tester,
  ArnesRecuperacion arnes, {
  List<Override> extra = const [],
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  fijarTelefono(tester, tamano: tamano, escala: escala);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...arnes.overrides, ...extra],
      child: MaterialApp(theme: temaClaro(), home: const RecuperacionPage()),
    ),
  );
  await tester.pump();
  await tester.pump();
}
