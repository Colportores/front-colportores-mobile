// HU-AUTH-007 — Mantenimiento de sesión activa (sliding 30 días), de punta a punta con la app
// montada: qué ve el colportor cuando la sesión sigue, cuando vence y cuando el servidor la revoca.
import 'dart:async';
import 'dart:math' as math;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';
const _revocada = 'Tu sesión se cerró desde el servidor. Iniciá sesión nuevamente.';

final _aviso = find.byKey(const Key('login_aviso_sesion'));
final _login = find.byKey(const Key('login_enviar'));
final _principal = find.byKey(const Key('inicio_email'));

/// Una sesión guardada que el servidor renovó por última vez hace [sinUso].
SesionModel _sesionSinUsoDesde(Duration sinUso) => SesionModel(
  usuarioId: '01920000-0000-7000-8000-000000000001',
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.now().toUtc().subtract(sinUso).add(const Duration(days: 30)),
);

Future<AuthRemoteDataSourceEnMemoria> _montar(
  WidgetTester tester, {
  SesionModel? guardada,
  AuthRemoteDataSourceEnMemoria? remote,
  ThemeMode tema = ThemeMode.light,
  RelojSesionEnMemoria? reloj,
}) async {
  final remoto =
      remote ??
      AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});
  final local = AuthLocalDataSourceEnMemoria();
  if (guardada != null) await local.guardarSesion(guardada);
  tester.platformDispatcher.platformBrightnessTestValue = tema == ThemeMode.dark
      ? Brightness.dark
      : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(local),
        if (reloj != null) relojSesionProvider.overrideWithValue(reloj),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  return remoto;
}

Future<void> _entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.tap(_login);
  await tester.pumpAndSettle();
}

void main() {
  group('HU-AUTH-007 — criterios de aceptación', () {
    testWidgets('Escenario: Refresh transparente con uso regular — con la sesión dentro de los 30 '
        'días entra directo, y un refresh no cambia nada de lo que se ve', (tester) async {
      final remote = await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 5)));

      expect(_principal, findsOneWidget);
      expect(_login, findsNothing);

      final container = ProviderScope.containerOf(tester.element(_principal));
      final renovada = await container.read(renovarSesionUseCaseProvider)(const NoParams());
      await tester.pumpAndSettle();

      expect(renovada.isRight(), isTrue);
      expect(remote.llamadasRenovarSesion, 1);
      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('Escenario: Expiración por inactividad — al abrir la app con la sesión vencida '
        'muestra "$_inactividad"', (tester) async {
      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 31)));

      expect(_login, findsOneWidget);
      expect(find.text(_inactividad), findsOneWidget);
    });

    testWidgets('Escenario: Expiración por inactividad — también cuando el proveedor ya la '
        'descartó al arrancar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..vencidaPorInactividadAlArrancar = true;

      await _montar(tester, remote: remote);

      expect(find.text(_inactividad), findsOneWidget);
    });

    testWidgets('Escenario: Refresh offline con JWT vigente — sin red opera normalmente, sin '
        'avisos ni intentos de refresh', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..simularSinConexion = true;

      await _montar(tester, remote: remote, guardada: _sesionSinUsoDesde(const Duration(days: 29)));

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(remote.llamadasRenovarSesion, 0);
    });

    testWidgets('Escenario: Edge - backend revocó la sesión — con la app abierta y otra pantalla '
        'encima, vuelve al login con "$_revocada"', (tester) async {
      final remote = await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 1)));
      unawaited(
        Navigator.of(tester.element(_principal)).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('otra', key: Key('otra_pantalla'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      remote.simularExpiracion(MotivoExpiracion.revocada);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('otra_pantalla')), findsNothing);
      expect(_login, findsOneWidget);
      expect(find.text(_revocada), findsOneWidget);
    });
  });

  group('Al volver a la app (proceso vivo en segundo plano)', () {
    Future<void> volverALaApp(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('Escenario: Expiración por inactividad — si pasaron los 30 días con la app en '
        'segundo plano, al volver cierra la sesión con "$_inactividad"', (tester) async {
      var ahora = DateTime.now().toUtc();
      final reloj = RelojSesionEnMemoria(sistema: () => ahora);
      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 20)), reloj: reloj);
      expect(_principal, findsOneWidget);

      ahora = ahora.add(const Duration(days: 11));
      await volverALaApp(tester);

      expect(_login, findsOneWidget);
      expect(find.text(_inactividad), findsOneWidget);
    });

    testWidgets('dentro de la ventana, volver a la app no cambia nada', (tester) async {
      var ahora = DateTime.now().toUtc();
      final reloj = RelojSesionEnMemoria(sistema: () => ahora);
      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 20)), reloj: reloj);

      ahora = ahora.add(const Duration(days: 9));
      await volverALaApp(tester);

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('atrasar el reloj del equipo no estira la sesión', (tester) async {
      var ahora = DateTime.now().toUtc().add(const Duration(days: 11));
      final reloj = RelojSesionEnMemoria(sistema: () => ahora);
      await reloj.ahora();
      ahora = ahora.subtract(const Duration(days: 11));

      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 20)), reloj: reloj);

      expect(find.text(_inactividad), findsOneWidget);
    });
  });

  group('Estados del aviso en el login', () {
    testWidgets('sin sesión vencida (primer ingreso o logout), no hay aviso', (tester) async {
      await _montar(tester);

      expect(_login, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('al volver a entrar, el aviso desaparece', (tester) async {
      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 40)));
      expect(_aviso, findsOneWidget);

      await _entrar(tester);

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('si entrar falla, el aviso sigue y el error se muestra aparte', (tester) async {
      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 40)));

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'incorrecta1');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
    });

    testWidgets('el lector de pantalla lo anuncia al aparecer (región viva)', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 40)));

      expect(tester.getSemantics(_aviso), isSemantics(isLiveRegion: true));
      expect(tester.getSemantics(find.text(_inactividad)).label, contains(_inactividad));
      semantica.dispose();
    });
  });

  group('Accesibilidad del aviso', () {
    for (final tema in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('tema ${tema.name}: tamaño de toque, etiquetas y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 40)), tema: tema);
        expect(_aviso, findsOneWidget);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        // En el tema claro, dos rótulos de marca del login ("COLPORTAJE · URUGUAY" en oro y
        // "O CONTINUAR CON") no llegan a 4.5:1: es la paleta del diseño, anotado en #59. El
        // contraste del aviso se mide aparte, en los dos temas.
        if (tema == ThemeMode.dark) {
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        expect(_contrasteDelAviso(tester), greaterThanOrEqualTo(4.5));
        semantica.dispose();
      });
    }

    testWidgets('sin overflow con el texto al 200 % en 360x740', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 740)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _montar(tester, guardada: _sesionSinUsoDesde(const Duration(days: 40)));

      expect(_aviso, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Contraste WCAG entre el texto del aviso y el fondo de la pantalla.
double _contrasteDelAviso(WidgetTester tester) {
  final contexto = tester.element(find.text(_inactividad));
  final texto = DefaultTextStyle.of(
    contexto,
  ).style.merge(tester.widget<Text>(find.text(_inactividad)).style);
  final fondo = Theme.of(contexto).scaffoldBackgroundColor;
  final a = texto.color!.computeLuminance();
  final b = fondo.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}
