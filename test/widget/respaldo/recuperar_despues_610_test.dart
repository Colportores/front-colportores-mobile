// HU-SYNC-006 (#610, decisión de Cristian del 03/11, «Recup. luego») — La app entera: después de
// «Empezar sin recuperar», Configuración ofrece «Recuperar mi respaldo» mientras el teléfono no
// tenga nada cargado, y vuelve a abrir el asistente.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/arranque/reinicio_de_raiz.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/db_local_repository_en_memoria.dart';
import '../../helpers/notificaciones_arnes.dart' as notif;
import '../../helpers/recuperacion_arnes.dart';

final _asistente = find.byKey(const Key('recuperacion_pagina'));
final _configuracion = find.byKey(const Key('configuracion_pagina'));
final _filaRecuperar = find.byKey(const Key('configuracion_recuperar_respaldo'));
final _avisoNo = find.byKey(const Key('configuracion_recuperar_respaldo_no'));
final _abrirConfiguracion = find.byKey(const Key('inicio_configuracion'));
final _atras = find.byKey(const Key('configuracion_atras'));

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

Future<void> _abrirApp(
  WidgetTester tester,
  notif.Telefono telefono,
  ArnesRecuperacion arnes, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // La base del teléfono es la misma antes y después del reinicio (es un archivo).
  final dbDelTelefono = dbLocalYaPreparada();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    // «Recuperar mi respaldo» reinicia la raíz, como en `main.dart`.
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
}

/// «Empezar sin recuperar» (con su aviso) y el permiso de notificaciones «Ahora no»: llega a Hoy.
Future<void> _empezarSinRecuperar(WidgetTester tester) async {
  await empezarSinRecuperar(tester, cta2);
  if (notif.pedidoAhoraNo.evaluate().isNotEmpty) await _tocar(tester, notif.pedidoAhoraNo);
  await tester.pumpAndSettle();
  expect(notif.principal, findsOneWidget);
}

Future<void> _irAConfiguracion(WidgetTester tester) async {
  // Con el Drive conectado la fila pasa por la hoja «Recuperar tu respaldo» (16G·02, #691); sin
  // Drive, por la conexión con Google (16G·03, en `recuperar_respaldo_16g_691_test.dart`).
  await conectarDriveDeLaApp(tester);
  await tester.tap(_abrirConfiguracion);
  await tester.pumpAndSettle();
  expect(_configuracion, findsOneWidget);
}

void main() {
  late notif.Telefono telefono;
  late ArnesRecuperacion arnes;

  setUp(() {
    telefono = notif.Telefono();
    arnes = ArnesRecuperacion();
  });

  testWidgets('dado un teléfono sin datos que empezó sin recuperar, cuando abro Configuración, '
      'entonces veo «Recuperar mi respaldo»', (tester) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);

    await tester.ensureVisible(_filaRecuperar);
    expect(find.text('Recuperar mi respaldo'), findsOneWidget);
    expect(find.text('Traé a este teléfono lo que guardaste en tu Drive'), findsOneWidget);
  });

  testWidgets('al tocarla vuelve el asistente, con la búsqueda y las mismas opciones', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    final busquedasAntes = arnes.servicio.busquedas;

    await recuperarDesdeConfiguracion(tester);

    expect(_asistente, findsOneWidget);
    expect(_configuracion, findsNothing, reason: 'Configuración sale de la pila');
    expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
    expect(arnes.servicio.busquedas, busquedasAntes + 1);
    expect(textoDe(cta), 'Recuperar mis datos');
    expect(textoDe(cta2), 'Empezar sin recuperar');
  });

  testWidgets('al tocarla la app se reinicia por dentro: raíz nueva, directo en el asistente, sin '
      'Inicio ni Configuración de por medio', (tester) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    final raizAntes = ProviderScope.containerOf(tester.element(find.byType(ColportoresApp)));
    await tester.ensureVisible(_filaRecuperar);
    await tester.tap(_filaRecuperar);
    await _asentar(tester);
    await tester.tap(hojaRecuperarEmpezar);
    // El primer cuadro tira la raíz vieja entera: ya no hay nada de ella andando.
    await tester.pump();
    await tester.pump();
    expect(find.byType(ColportoresApp), findsOneWidget);
    final raizDespues = ProviderScope.containerOf(tester.element(find.byType(ColportoresApp)));
    expect(
      raizDespues,
      isNot(same(raizAntes)),
      reason: 'un ProviderScope nuevo, como en main.dart',
    );
    expect(notif.principal, findsNothing, reason: 'no pasa por Hoy');

    await _asentar(tester);
    expect(_asistente, findsOneWidget);
    expect(_configuracion, findsNothing);
  });

  testWidgets('después del reinicio, «Atrás» no devuelve a Configuración: la pila es nueva', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await recuperarDesdeConfiguracion(tester);

    final navegador = tester.state<NavigatorState>(find.byType(Navigator).first);

    expect(navegador.canPop(), isFalse);
  });

  testWidgets('recuperar desde Configuración termina en «Ir a mi inicio» y la app sigue', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await recuperarDesdeConfiguracion(tester);

    await _tocar(tester, cta);
    await tester.enterText(campoContrasena, 'la-de-antes');
    await _asentar(tester);
    await _tocar(tester, cta);
    expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
    expect(arnes.servicio.recuperaciones, 1);
    await _tocar(tester, cta);

    expect(_asistente, findsNothing);
    expect(notif.principal, findsOneWidget);
  });

  testWidgets('«Empezar sin recuperar» del asistente reabierto vuelve a la app y la fila sigue', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await recuperarDesdeConfiguracion(tester);

    await empezarSinRecuperar(tester, cta2);
    await tester.pumpAndSettle();

    expect(_asistente, findsNothing);
    expect(notif.principal, findsOneWidget);
    await _irAConfiguracion(tester);
    await tester.ensureVisible(_filaRecuperar);
    expect(_filaRecuperar, findsOneWidget, reason: 'sigue sin nada cargado: se puede recuperar');
  });

  testWidgets('volver atrás y reentrar a Configuración: la fila sigue ahí', (tester) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await tester.tap(_atras);
    await tester.pumpAndSettle();
    expect(_configuracion, findsNothing);

    await _irAConfiguracion(tester);

    await tester.ensureVisible(_filaRecuperar);
    expect(_filaRecuperar, findsOneWidget);
  });

  testWidgets('con datos cargados la fila queda apagada y dice por qué (16G·04)', (tester) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    arnes.lector.sinDatos = false;

    await _irAConfiguracion(tester);

    await tester.ensureVisible(_filaRecuperar);
    expect(tester.widget<ListTile>(_filaRecuperar).enabled, isFalse);
    expect(find.text('No disponible: ya cargaste datos en este teléfono'), findsOneWidget);
  });

  testWidgets('si cargó datos con Configuración abierta: avisa por qué no y la fila se apaga', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await tester.ensureVisible(_filaRecuperar);
    arnes.lector.sinDatos = false;

    await recuperarDesdeConfiguracion(tester);

    expect(_asistente, findsNothing);
    expect(_configuracion, findsOneWidget);
    expect(_avisoNo, findsOneWidget);
    expect(
      find.text('Ya hay datos cargados en este teléfono, así que no se puede traer el respaldo.'),
      findsOneWidget,
    );
    expect(tester.widget<ListTile>(_filaRecuperar).enabled, isFalse, reason: '16G·04');
    expect(find.text('No disponible: ya cargaste datos en este teléfono'), findsOneWidget);
  });

  testWidgets('si no se puede mirar la base: avisa, no abre y al reentrar se puede volver a '
      'probar', (tester) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await tester.ensureVisible(_filaRecuperar);
    arnes.lector.errorAlMirar = StateError('base cerrada');

    await recuperarDesdeConfiguracion(tester);

    expect(_asistente, findsNothing);
    expect(
      find.text('No pudimos revisar si este teléfono tiene datos. Probá de nuevo en unos minutos.'),
      findsOneWidget,
    );

    // Nada quedó trabado: con la base de vuelta, reentrando a Configuración la fila abre.
    arnes.lector.errorAlMirar = null;
    await tester.ensureVisible(_atras);
    await tester.tap(_atras);
    await tester.pumpAndSettle();
    await _irAConfiguracion(tester);
    await recuperarDesdeConfiguracion(tester);
    expect(_asistente, findsOneWidget);
  });

  testWidgets('si no se puede quitar la marca: avisa, no reinicia y se puede volver a probar', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await tester.ensureVisible(_filaRecuperar);
    arnes.resuelta.errorAlDesmarcar = StateError('almacén cerrado');

    await recuperarDesdeConfiguracion(tester);

    expect(_asistente, findsNothing);
    expect(_configuracion, findsOneWidget, reason: 'la app no se reinició');
    expect(_avisoNo, findsOneWidget);

    arnes.resuelta.errorAlDesmarcar = null;
    await recuperarDesdeConfiguracion(tester);
    expect(_asistente, findsOneWidget);
  });

  testWidgets('doble toque en la fila: reinicia una sola vez y abre un solo asistente', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);
    await tester.ensureVisible(_filaRecuperar);
    final miradasAntes = arnes.lector.miradas;
    final busquedasAntes = arnes.servicio.busquedas;

    await tester.tap(_filaRecuperar);
    await tester.tap(_filaRecuperar, warnIfMissed: false);
    await _asentar(tester);
    expect(hojaRecuperarRespaldo, findsOneWidget, reason: 'una sola hoja');
    await tester.tap(hojaRecuperarEmpezar);
    await tester.tap(hojaRecuperarEmpezar, warnIfMissed: false);
    await _asentar(tester);

    // Se decide una sola vez: la marca se quita una vez y el asistente que abre es uno.
    expect(arnes.lector.miradas, greaterThan(miradasAntes));
    expect(arnes.resuelta.desmarcas, 1, reason: 'el segundo toque no vuelve a pedir el reinicio');
    expect(arnes.servicio.busquedas, busquedasAntes + 1);
    expect(_asistente, findsOneWidget);
  });

  testWidgets('con el asistente apagado la fila no está', (tester) async {
    arnes.habilitado = false;
    await _abrirApp(tester, telefono, arnes);
    await tester.pumpAndSettle();
    if (notif.pedidoAhoraNo.evaluate().isNotEmpty) await _tocar(tester, notif.pedidoAhoraNo);
    await tester.pumpAndSettle();
    expect(notif.principal, findsOneWidget);
    await _irAConfiguracion(tester);

    expect(_filaRecuperar, findsNothing);
  });

  testWidgets('a 360 dp con el texto al 200 % la fila se lee y se puede tocar', (tester) async {
    await _abrirApp(tester, telefono, arnes, tamano: const Size(360, 740), escala: 2);
    await _empezarSinRecuperar(tester);
    await _irAConfiguracion(tester);

    await tester.ensureVisible(_filaRecuperar);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Recuperar mi respaldo'), findsOneWidget);
    await recuperarDesdeConfiguracion(tester);
    expect(_asistente, findsOneWidget);
  });

  testWidgets('el servicio encuentra varios respaldos al reabrir: se ofrecen todos juntos', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _empezarSinRecuperar(tester);
    arnes.servicio.busqueda = VariosRespaldosEnDrive([respaldoDePrueba, respaldoDePrueba]);
    await _irAConfiguracion(tester);

    await recuperarDesdeConfiguracion(tester);

    expect(tester.widget<Text>(titulo).data, 'Encontramos más de un respaldo');
    expect(textoDe(cta), 'Recuperar todos mis datos');
  });
}
