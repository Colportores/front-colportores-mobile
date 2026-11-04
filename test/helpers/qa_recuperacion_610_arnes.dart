// Arnés del QA de #610 (varios respaldos juntos, aviso de «Empezar sin recuperar» y la fila
// «Recuperar mi respaldo» de Configuración): lleva el asistente a cada estado nuevo, en cualquier
// tamaño y escala de texto. Sobre el arnés de #175.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_local_repository_en_memoria.dart';
import 'notificaciones_arnes.dart' as notif;
import 'qa_recuperacion_175_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408;

RespaldoEnDrive respaldo610(String llave, {int partes = 15, int mb = 38, int dia = 22}) =>
    RespaldoEnDrive(
      llave: llave,
      fecha: DateTime(2026, 10, dia, 3, 10),
      partes: partes,
      bytes: mb * 1024 * 1024,
      completo: true,
      tieneLlave: true,
    );

/// Los estados que #610 suma (el resto de la vista 34 ya lo cubre el QA de #175).
enum Estado610 {
  variosOferta('Varios: «Encontramos más de un respaldo»'),
  variosContrasena('Varios: «Abrí tus copias»'),
  variosContrasenaDistinta('Varios: la contraseña no abre las copias'),
  variosRestaurando('Varios: restaurando (partes sumadas)'),
  variosInterrumpida('Varios: se cortó la conexión'),
  hojaDesdeEncontrado('Hoja «¿Empezar sin recuperar?» desde 34·01'),
  hojaDesdeVarios('Hoja «¿Empezar sin recuperar?» desde varios'),
  hojaDesdeConectar('Hoja «¿Empezar sin recuperar?» desde 34·02');

  const Estado610(this.rotulo);
  final String rotulo;
}

Future<ArnesRecuperacion> llegarA610(
  WidgetTester tester,
  Estado610 estado, {
  Size tamano = chico175,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  final a = ArnesRecuperacion();
  final s = a.servicio;
  final dos = VariosRespaldosEnDrive([respaldo610('llave-1'), respaldo610('llave-2', partes: 9)]);
  switch (estado) {
    case Estado610.hojaDesdeConectar:
      s.busqueda = const DriveSinPermiso();
    case Estado610.hojaDesdeEncontrado:
      break;
    case Estado610.variosRestaurando:
      s.busqueda = dos;
      s.frenarRecuperar = true;
      s.progresos = const [ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 12, total: 24)];
    case Estado610.variosInterrumpida:
      s.busqueda = dos;
      s.resultado = const RecuperacionSinConexion(hechas: 12, total: 24);
    case Estado610.variosContrasenaDistinta:
      s.busqueda = dos;
      s.resultado = const ContrasenaNoAbreElRespaldo();
    case Estado610.variosOferta || Estado610.variosContrasena || Estado610.hojaDesdeVarios:
      s.busqueda = dos;
  }
  await abrirAsistente175(tester, a, tamano: tamano, escala: escala);
  switch (estado) {
    case Estado610.variosContrasena:
      await irAContrasena175(tester);
    case Estado610.variosContrasenaDistinta ||
        Estado610.variosRestaurando ||
        Estado610.variosInterrumpida:
      await abrirCopia175(tester);
      if (estado == Estado610.variosInterrumpida) await asentar175(tester);
    case Estado610.hojaDesdeEncontrado ||
        Estado610.hojaDesdeVarios ||
        Estado610.hojaDesdeConectar:
      await tocar175(tester, cta2);
    case Estado610.variosOferta:
      break;
  }
  await tester.pump(const Duration(milliseconds: 400));
  return a;
}

/// La app entera, con la sesión iniciada, «Empezar sin recuperar» hecho y Configuración abierta,
/// con la fila «Recuperar mi respaldo» a la vista.
Future<void> abrirAppHastaConfiguracion610(
  WidgetTester tester,
  ArnesRecuperacion arnes, {
  Size tamano = chico175,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  final telefono = notif.Telefono();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
        ...arnes.overridesDelAsistente,
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byKey(const Key('login_enviar')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
    await tester.ensureVisible(find.byKey(const Key('login_enviar')));
    await tester.tap(find.byKey(const Key('login_enviar')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await empezarSinRecuperar(tester, cta2);
  if (notif.pedidoAhoraNo.evaluate().isNotEmpty) {
    await tester.ensureVisible(notif.pedidoAhoraNo);
    await tester.tap(notif.pedidoAhoraNo);
    await tester.pumpAndSettle();
  }
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('configuracion_recuperar_respaldo')));
  await tester.pump(const Duration(milliseconds: 300));
}
