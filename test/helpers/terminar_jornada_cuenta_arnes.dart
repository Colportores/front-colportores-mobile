// Arnés de «Terminar jornada» en la pantalla de la cuenta restringida (#472): la pantalla de espera
// montada sola, con la sesión fija, la jornada en memoria (con perillas para trabar o romper la
// lectura y el cierre) y la entrevista en curso de la vista 39.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrevista_falsos.dart';

final sesionDeLaCuenta = Sesion(
  usuarioId: 'col-1',
  email: 'marta@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

/// Jueves 23/10/2026, 14:41: el reloj de la entrevista y de la jornada.
final ahoraDeLaCuenta = ahoraEntrevista;

class SesionFijaDeLaCuenta extends SesionNotifier {
  @override
  Future<Sesion?> build() async => sesionDeLaCuenta;
}

/// La jornada en memoria, con perillas para trabar o romper la lectura y el cierre.
final class LocalDeJornada implements JornadaLocalDataSource {
  LocalDeJornada(Iterable<JornadaModel> iniciales)
    : _real = JornadaLocalDataSourceEnMemoria(iniciales: iniciales);

  final JornadaLocalDataSourceEnMemoria _real;
  Completer<void>? demoraLectura;
  Completer<void>? demoraFinalizar;
  Object? errorAlLeer;
  Object? errorAlFinalizar;
  int cierres = 0;

  List<JornadaModel> get jornadas => _real.jornadas;
  JornadaModel get unica => _real.jornadas.single;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    if (demoraLectura case final d?) await d.future;
    if (errorAlLeer case final e?) throw e;
    return _real.obtenerActiva(colportorId);
  }

  @override
  Future<void> insertar(JornadaModel jornada) => _real.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) async {
    cierres++;
    if (demoraFinalizar case final d?) await d.future;
    if (errorAlFinalizar case final e?) throw e;
    return _real.finalizar(jornada);
  }

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) =>
      _real.siguienteA(colportorId: colportorId, inicio: inicio);
}

final class BackupFalsoDeLaCuenta implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

JornadaModel jornadaAbiertaDesde(DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-1',
    colportorId: sesionDeLaCuenta.usuarioId,
    inicio: inicio,
    auditoria: Auditoria(
      createdAt: inicio,
      updatedAt: inicio,
      createdBy: sesionDeLaCuenta.usuarioId,
    ),
  ),
);

/// Monta la pantalla de espera de [estado] (`null` = sin estado conocido, sin conexión) con la
/// jornada de [local].
Future<void> montarCuentaConJornada(
  WidgetTester tester, {
  required LocalDeJornada local,
  required MontajeEntrevista montaje,
  EstadoCuenta? estado = EstadoCuenta.suspendida,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sesionProvider.overrideWith(SesionFijaDeLaCuenta.new),
        jornadaLocalDataSourceProvider.overrideWithValue(local),
        disparadorBackupProvider.overrideWithValue(BackupFalsoDeLaCuenta()),
        relojJornadaProvider.overrideWithValue(() => ahoraDeLaCuenta),
        ...montaje.overrides,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: estado == null
            ? const EsperandoAsignacionPage(falla: FailureSinConexion())
            : EsperandoAsignacionPage(estado: estado),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
