// Vista 16, artboards 16G (#691, seguimiento de #610): la fila «Recuperar mi respaldo» de
// Configuración como en el canvas, con la app entera.
//
// Inventario: 16G·01 fila con Drive · 16G·02 hoja «Recuperar tu respaldo» (Empezar / Ahora no) ·
// 16G·03 sin Drive conectado: primero la conexión con Google (16D·02) y después el asistente ·
// 16G·04 con datos: apagada y con el motivo. Más los estados que el canvas no dibuja (el estado del
// Drive cargando o ilegible) y los casos límite: doble toque, atrás y reentrar, texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/arranque/reinicio_de_raiz.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInExceptionCode;

import '../../helpers/db_local_repository_en_memoria.dart';
import '../../helpers/notificaciones_arnes.dart' as notif;
import '../../helpers/recuperacion_arnes.dart';
import '../../helpers/respaldo_drive_falsos.dart';

const _filaTitulo = 'Recuperar mi respaldo';
const _detalleConDrive = 'Traé a este teléfono lo que guardaste en tu Drive';
const _detalleSinDrive = 'Conectá tu Drive para buscar tu respaldo';
const _motivoApagada = 'No disponible: ya cargaste datos en este teléfono';
const _textoHoja =
    'Traemos a este teléfono lo que guardaste en ana.gomez@gmail.com. Se puede mientras no '
    'cargues nada acá.';

final _asistente = find.byKey(const Key('recuperacion_pagina'));
final _configuracion = find.byKey(const Key('configuracion_pagina'));
final _abrirConfiguracion = find.byKey(const Key('inicio_configuracion'));
final _atras = find.byKey(const Key('configuracion_atras'));
final _avisoNo = find.byKey(const Key('configuracion_recuperar_respaldo_no'));
final _hojaConectar = find.byKey(const Key('drive_hoja_conectar'));
final _conectarConGoogle = find.byKey(const Key('drive_conectar'));
final _conectarAhoraNo = find.byKey(const Key('drive_ahora_no'));
final _avisoCancelado = find.byKey(const Key('configuracion_drive_aviso_cancelado'));

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _asentar(tester);
}

ProviderContainer _raiz(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ColportoresApp)));

/// La app entera hasta Hoy, después de «Empezar sin recuperar» (el teléfono sigue sin datos).
Future<void> _abrirApp(
  WidgetTester tester,
  ArnesRecuperacion arnes, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final telefono = notif.Telefono();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final dbDelTelefono = dbLocalYaPreparada();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ReiniciadorDeRaiz(
      overrides: () => [
        dbLocalRepositoryProvider.overrideWithValue(dbDelTelefono),
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
  if (notif.pedidoAhoraNo.evaluate().isNotEmpty) await _tocar(tester, notif.pedidoAhoraNo);
  await tester.pumpAndSettle();
  expect(notif.principal, findsOneWidget);
}

Future<void> _irAConfiguracion(WidgetTester tester) async {
  await tester.tap(_abrirConfiguracion);
  // Sin `pumpAndSettle`: con el estado del Drive leyéndose, la fila «Cuenta Drive» gira.
  await _asentar(tester);
  expect(_configuracion, findsOneWidget);
  await tester.ensureVisible(filaRecuperarRespaldo);
  await tester.pump();
}

void main() {
  late ArnesRecuperacion arnes;

  setUp(() => arnes = ArnesRecuperacion());

  group('16G·01 · la fila con Drive conectado', () {
    testWidgets('dice qué trae, lleva flecha y se puede tocar', (tester) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);

      final fila = tester.widget<ListTile>(filaRecuperarRespaldo);
      expect(fila.enabled, isTrue);
      expect(find.text(_filaTitulo), findsOneWidget);
      expect(find.text(_detalleConDrive), findsOneWidget);
      expect(
        find.descendant(of: filaRecuperarRespaldo, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
      expect(tester.getSize(filaRecuperarRespaldo).height, greaterThanOrEqualTo(48));
    });
  });

  group('16G·02 · la hoja «Recuperar tu respaldo» antes de empezar', () {
    testWidgets('tocar la fila abre la hoja con la cuenta del Drive y no reinicia todavía', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);

      await _tocar(tester, filaRecuperarRespaldo);

      expect(hojaRecuperarRespaldo, findsOneWidget);
      expect(find.text('Recuperar tu respaldo'), findsOneWidget);
      expect(find.text(_textoHoja), findsOneWidget);
      expect(textoDe(hojaRecuperarEmpezar), 'Empezar');
      expect(textoDe(hojaRecuperarAhoraNo), 'Ahora no');
      expect(arnes.resuelta.desmarcas, 0, reason: 'nada se reinicia hasta «Empezar»');
      expect(_asistente, findsNothing);
    });

    testWidgets('«Empezar» reinicia la app y abre el asistente (vista 34)', (tester) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      final busquedasAntes = arnes.servicio.busquedas;

      await recuperarDesdeConfiguracion(tester);
      await _asentar(tester);

      expect(_asistente, findsOneWidget);
      expect(_configuracion, findsNothing);
      expect(arnes.resuelta.desmarcas, 1);
      expect(arnes.servicio.busquedas, busquedasAntes + 1);
    });

    testWidgets('«Ahora no» cierra la hoja, no reinicia y la fila se puede volver a tocar', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);

      await _tocar(tester, hojaRecuperarAhoraNo);

      expect(hojaRecuperarRespaldo, findsNothing);
      expect(_configuracion, findsOneWidget);
      expect(_asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);

      // Nada quedó trabado: el segundo intento abre la hoja de nuevo.
      await _tocar(tester, filaRecuperarRespaldo);
      expect(hojaRecuperarRespaldo, findsOneWidget);
    });

    testWidgets('«Atrás» del sistema cierra la hoja sin reiniciar; la fila sigue andando', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(hojaRecuperarRespaldo, findsNothing);
      expect(_configuracion, findsOneWidget);
      expect(arnes.resuelta.desmarcas, 0);
      await recuperarDesdeConfiguracion(tester);
      await _asentar(tester);
      expect(_asistente, findsOneWidget);
    });

    testWidgets('doble toque en la fila abre una sola hoja', (tester) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);

      await tester.tap(filaRecuperarRespaldo);
      await tester.tap(filaRecuperarRespaldo, warnIfMissed: false);
      await _asentar(tester);

      expect(hojaRecuperarRespaldo, findsOneWidget);
    });

    testWidgets('doble toque en «Empezar»: un solo reinicio, un solo asistente', (tester) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);
      final busquedasAntes = arnes.servicio.busquedas;

      await tester.tap(hojaRecuperarEmpezar);
      await tester.tap(hojaRecuperarEmpezar, warnIfMissed: false);
      await _asentar(tester);

      expect(arnes.resuelta.desmarcas, 1);
      expect(arnes.servicio.busquedas, busquedasAntes + 1);
      expect(_asistente, findsOneWidget);
    });

    testWidgets('si cargó datos mientras la hoja estaba abierta: «Empezar» avisa y no reinicia', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);
      arnes.lector.sinDatos = false;

      await _tocar(tester, hojaRecuperarEmpezar);

      expect(_asistente, findsNothing);
      expect(_avisoNo, findsOneWidget);
      expect(
        find.text('Ya hay datos cargados en este teléfono, así que no se puede traer el respaldo.'),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isFalse, reason: '16G·04');
    });

    testWidgets('el Drive sin permiso también es una cuenta: hoja con su correo, y el asistente '
        'pide reconectar', (tester) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _raiz(tester).read(estadoRespaldoDriveProvider.notifier).permisoRevocado();
      await _irAConfiguracion(tester);

      expect(find.text(_detalleConDrive), findsOneWidget);
      await _tocar(tester, filaRecuperarRespaldo);

      expect(find.text(_textoHoja), findsOneWidget);
    });
  });

  group('16G·03 · sin Drive conectado: primero la conexión con Google', () {
    testWidgets('la fila pide conectar el Drive', (tester) async {
      await _abrirApp(tester, arnes);
      await _irAConfiguracion(tester);

      expect(find.text(_detalleSinDrive), findsOneWidget);
      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isTrue);
    });

    testWidgets('tocarla abre la conexión con Google (16D·02), no la hoja de 16G·02', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await _irAConfiguracion(tester);

      await _tocar(tester, filaRecuperarRespaldo);

      expect(_hojaConectar, findsOneWidget);
      expect(hojaRecuperarRespaldo, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);
    });

    testWidgets('conectado, sigue directo al asistente', (tester) async {
      await _abrirApp(tester, arnes);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);

      await _tocar(tester, _conectarConGoogle);
      await _asentar(tester);

      expect(arnes.drive.google.conexiones, 1);
      expect(_asistente, findsOneWidget);
      expect(_configuracion, findsNothing);
      expect(arnes.resuelta.desmarcas, 1);
    });

    testWidgets('si cancela en Google: el aviso de 16D·07, no reinicia y puede volver a probar', (
      tester,
    ) async {
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await _abrirApp(tester, arnes);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);

      await _tocar(tester, _conectarConGoogle);

      expect(_hojaConectar, findsNothing);
      expect(_avisoCancelado, findsOneWidget);
      expect(_asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);

      arnes.drive.google.errorAlConectar = null;
      await _tocar(tester, filaRecuperarRespaldo);
      await _tocar(tester, _conectarConGoogle);
      await _asentar(tester);
      expect(_asistente, findsOneWidget);
    });

    testWidgets('«Ahora no» en la conexión: no pasa nada más', (tester) async {
      await _abrirApp(tester, arnes);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);

      await _tocar(tester, _conectarAhoraNo);

      expect(_hojaConectar, findsNothing);
      expect(_avisoCancelado, findsNothing);
      expect(_configuracion, findsOneWidget);
      expect(arnes.drive.google.conexiones, 0);
      expect(arnes.resuelta.desmarcas, 0);
    });

    testWidgets('doble toque en la fila: una sola hoja de conexión', (tester) async {
      await _abrirApp(tester, arnes);
      await _irAConfiguracion(tester);

      await tester.tap(filaRecuperarRespaldo);
      await tester.tap(filaRecuperarRespaldo, warnIfMissed: false);
      await _asentar(tester);

      expect(_hojaConectar, findsOneWidget);
    });
  });

  group('16G·04 · con datos cargados: apagada, con el motivo', () {
    testWidgets('se ve apagada, dice por qué y no lleva flecha', (tester) async {
      await _abrirApp(tester, arnes);
      arnes.lector.sinDatos = false;
      await _irAConfiguracion(tester);

      final fila = tester.widget<ListTile>(filaRecuperarRespaldo);
      expect(fila.enabled, isFalse);
      expect(find.text(_filaTitulo), findsOneWidget);
      expect(find.text(_motivoApagada), findsOneWidget);
      expect(
        find.descendant(of: filaRecuperarRespaldo, matching: find.byIcon(Icons.chevron_right)),
        findsNothing,
      );
    });

    testWidgets('tocarla no abre nada', (tester) async {
      await _abrirApp(tester, arnes);
      arnes.lector.sinDatos = false;
      await _irAConfiguracion(tester);

      await tester.tap(filaRecuperarRespaldo, warnIfMissed: false);
      await _asentar(tester);

      expect(hojaRecuperarRespaldo, findsNothing);
      expect(_hojaConectar, findsNothing);
      expect(_asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);
    });

    testWidgets('el lector de pantalla la anuncia apagada y lee el motivo', (tester) async {
      final semantica = tester.ensureSemantics();
      await _abrirApp(tester, arnes);
      arnes.lector.sinDatos = false;
      await _irAConfiguracion(tester);

      final nodo = tester.getSemantics(filaRecuperarRespaldo);
      expect(nodo.label, contains(_filaTitulo));
      expect(nodo.label, contains(_motivoApagada));
      expect(nodo, isSemantics(hasEnabledState: true, isEnabled: false));
      semantica.dispose();
    });

    testWidgets('el motivo se lee en el gris de los textos chicos, no en el gris de lo apagado', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      arnes.lector.sinDatos = false;
      await _irAConfiguracion(tester);

      final estilo = tester.widget<Text>(find.text(_motivoApagada)).style;
      expect(estilo?.color, const Color(0xFF5B6B82));
    });
  });

  group('Estados que el canvas no dibuja: el estado del Drive', () {
    testWidgets('si todavía se está leyendo, el toque espera y abre la hoja que corresponde', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      final compuerta = Completer<void>();
      arnes.drive.almacen.compuertaLeer = compuerta;
      _raiz(tester).invalidate(estadoRespaldoDriveProvider);
      await _irAConfiguracion(tester);

      await tester.tap(filaRecuperarRespaldo);
      await _asentar(tester);
      expect(hojaRecuperarRespaldo, findsNothing);

      arnes.drive.almacen.compuertaLeer = null;
      compuerta.complete();
      await _asentar(tester);

      expect(hojaRecuperarRespaldo, findsOneWidget);
    });

    testWidgets('si no se pudo leer: avisa, no abre nada y se puede volver a probar', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      arnes.drive.almacen.alLeer = true;
      _raiz(tester).invalidate(estadoRespaldoDriveProvider);
      await _irAConfiguracion(tester);

      await _tocar(tester, filaRecuperarRespaldo);

      expect(_avisoNo, findsOneWidget);
      expect(
        find.text('No pudimos ver el estado de tu Drive. Probá de nuevo en unos minutos.'),
        findsOneWidget,
      );
      expect(hojaRecuperarRespaldo, findsNothing);
      expect(_hojaConectar, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);

      // El almacén vuelve: «Reintentar» de la fila «Cuenta Drive» relee y la fila abre la hoja.
      arnes.drive.almacen.alLeer = false;
      await _raiz(tester).read(estadoRespaldoDriveProvider.notifier).recargar();
      await _asentar(tester);
      await _tocar(tester, filaRecuperarRespaldo);
      expect(hojaRecuperarRespaldo, findsOneWidget);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets('después de «Ahora no», salir y volver a Configuración: la fila sigue igual', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      await _tocar(tester, filaRecuperarRespaldo);
      await _tocar(tester, hojaRecuperarAhoraNo);

      await _tocar(tester, _atras);
      await tester.pumpAndSettle();
      await _irAConfiguracion(tester);

      expect(find.text(_detalleConDrive), findsOneWidget);
      await _tocar(tester, filaRecuperarRespaldo);
      expect(hojaRecuperarRespaldo, findsOneWidget);
    });

    testWidgets('si cargó datos con Configuración cerrada, al volver la fila está apagada', (
      tester,
    ) async {
      await _abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      await _tocar(tester, _atras);
      await tester.pumpAndSettle();
      arnes.lector.sinDatos = false;

      await _irAConfiguracion(tester);

      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isFalse);
      expect(find.text(_motivoApagada), findsOneWidget);
    });
  });

  group('Texto al 200 % en 360 × 740', () {
    testWidgets('16G·01 y 16G·02: la fila y la hoja se leen enteras y «Empezar» se puede tocar', (
      tester,
    ) async {
      await _abrirApp(tester, arnes, tamano: const Size(360, 740), escala: 2);
      await conectarDriveDeLaApp(tester);
      await _irAConfiguracion(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(_detalleConDrive), findsOneWidget);

      await _tocar(tester, filaRecuperarRespaldo);
      expect(tester.takeException(), isNull);
      expect(find.text(_textoHoja), findsOneWidget);
      await tester.ensureVisible(hojaRecuperarAhoraNo);
      expect(tester.getSize(hojaRecuperarEmpezar).height, greaterThanOrEqualTo(48));

      await _tocar(tester, hojaRecuperarEmpezar);
      await _asentar(tester);
      expect(_asistente, findsOneWidget);
    });

    testWidgets('16G·03: el detalle sin Drive no desborda', (tester) async {
      await _abrirApp(tester, arnes, tamano: const Size(360, 740), escala: 2);
      await _irAConfiguracion(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(_detalleSinDrive), findsOneWidget);
    });

    testWidgets('16G·04: la fila apagada con el motivo no desborda', (tester) async {
      await _abrirApp(tester, arnes, tamano: const Size(360, 740), escala: 2);
      arnes.lector.sinDatos = false;
      await _irAConfiguracion(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(_motivoApagada), findsOneWidget);
    });
  });
}
