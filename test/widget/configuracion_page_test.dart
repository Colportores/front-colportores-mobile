// Configuración: cerrar sesión (HU-AUTH-006) y borrar datos locales (HU-AUTH-010). Un test por
// escenario de aceptación, con el texto literal de la HU, más estados y accesibilidad.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/borrar_datos_locales_page.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _resumenBase = ResumenDatosLocales(
  personas: 12,
  visitas: 34,
  operacionesSinSincronizar: 0,
  hayBackupEnDrive: true,
);

final class _DatosLocalesFake implements DatosLocalesRepository {
  Either<Failure, ResumenDatosLocales> respuestaResumen = const Right(_resumenBase);
  Either<Failure, ResultadoBorradoDatosLocales> respuestaBorrado = const Right(
    ResultadoBorradoDatosLocales.completo,
  );
  Completer<void>? demoraResumen;
  Completer<void>? demoraBorrado;
  final List<bool> borrados = [];

  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async {
    await demoraResumen?.future;
    return respuestaResumen;
  }

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
  }) async {
    await demoraBorrado?.future;
    borrados.add(incluirBackupDrive);
    return respuestaBorrado;
  }
}

/// Almacén que no puede borrar la sesión: el cierre de sesión falla del lado local.
final class _LocalQueNoBorra implements AuthLocalDataSource {
  SesionModel? _sesion;
  bool fallar = false;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async {
    _sesion = sesion;
  }

  @override
  Future<void> borrarSesion() async {
    if (fallar) throw Exception('keystore');
    _sesion = null;
  }
}

late AuthRemoteDataSourceEnMemoria _remote;
late _DatosLocalesFake _datos;

/// Monta la app con sesión iniciada y abre Configuración.
Future<ProviderContainer> _montar(WidgetTester tester, {AuthLocalDataSource? local}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_remote),
      authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
      datosLocalesRepositoryProvider.overrideWithValue(_datos),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'secreto123');

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  await tester.pumpAndSettle();
  return container;
}

/// Scrollea hasta [finder] (con texto grande puede quedar fuera de pantalla) y lo toca.
Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _abrirBorrado(WidgetTester tester) =>
    _tocar(tester, find.byKey(const Key('configuracion_borrar_datos')));

Future<void> _llegarAlDialogoFinal(WidgetTester tester) async {
  await _abrirBorrado(tester);
  await _tocar(tester, find.byKey(const Key('borrar_datos_checkbox')));
  await _tocar(tester, find.byKey(const Key('borrar_datos_continuar')));
}

Finder get _login => find.byKey(const Key('login_enviar'));

void main() {
  setUp(() {
    _remote = AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});
    _datos = _DatosLocalesFake();
  });

  group('HU-AUTH-006 — Cerrar sesión', () {
    testWidgets('Escenario: Logout exitoso con sync_queue vacía y con red', (tester) async {
      final container = await _montar(tester);
      expect(find.text('ana@example.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      expect(find.text(TextosConfiguracion.confirmarCierre), findsOneWidget);
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();

      expect(_remote.llamadasCerrarSesion, 1, reason: 'revoca el JWT en Supabase');
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget, reason: 'la UI navega a la pantalla de login');
      expect(find.byType(ConfiguracionPage), findsNothing);
    });

    testWidgets('Escenario: Logout con sync_queue pendiente -advertencia', (tester) async {
      _datos.respuestaResumen = const Right(
        ResumenDatosLocales(
          personas: 0,
          visitas: 0,
          operacionesSinSincronizar: 3,
          hayBackupEnDrive: false,
        ),
      );
      final container = await _montar(tester);

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Tenés 3 operaciones sin sincronizar. Si cerrás sesión ahora, se subirán cuando vuelvas '
          'a iniciar sesión.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Cerrar sesión igual'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(container.read(sesionProvider).value, isNotNull, reason: 'cancelar no cierra nada');
      expect(find.byType(ConfiguracionPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar sesión igual'));
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    testWidgets('Escenario: Logout sin conexión', (tester) async {
      final container = await _montar(tester);
      _remote.simularSinConexion = true;

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cerraste sesión en este teléfono. Se va a cerrar por completo cuando haya conexión.',
        ),
        findsOneWidget,
      );
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget, reason: 'la UI navega al login');

      // La revocación quedó pendiente y se reintenta sola al volver a entrar con red.
      _remote.simularSinConexion = false;
      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
      await tester.pumpAndSettle();
      expect(_remote.revocaciones, hasLength(1));
    });

    testWidgets('error: si la sesión no se puede borrar, avisa y deja reintentar', (tester) async {
      final local = _LocalQueNoBorra();
      final container = await _montar(tester, local: local);
      local.fallar = true;

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cerrar la sesión. Probá de nuevo.'), findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(find.byType(ConfiguracionPage), findsOneWidget);

      local.fallar = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    testWidgets('cargando: mientras revisa lo pendiente, muestra progreso y no acepta otro toque', (
      tester,
    ) async {
      _datos.demoraResumen = Completer<void>();
      await _montar(tester);

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pump();
      expect(find.byKey(const Key('configuracion_cerrando')), findsOneWidget);
      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pump();

      _datos.demoraResumen!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_dialogo_cierre')), findsOneWidget);
    });

    testWidgets('volver sale de Configuración sin tocar la sesión', (tester) async {
      final container = await _montar(tester);

      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_email')), findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
    });
  });

  group('HU-AUTH-010 — Borrar datos locales', () {
    testWidgets('Escenario: Borrado exitoso (sin tocar backup en Drive)', (tester) async {
      final container = await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text(TextosBorrado.explicacion), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_personas')), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('34'), findsOneWidget);
      expect(find.text('Sí, vas a elegir si se borra'), findsOneWidget);
      expect(find.text(TextosBorrado.datosDelSistema), findsOneWidget);
      expect(
        find.text(TextosBorrado.limiteBorrado),
        findsOneWidget,
        reason: 'HU-AUTH-010, caso borde: documenta el límite del overwrite en memoria flash',
      );

      final continuar = find.byKey(const Key('borrar_datos_continuar'));
      expect(tester.widget<FilledButton>(continuar).onPressed, isNull, reason: 'sin checkbox');
      await _tocar(tester, find.byKey(const Key('borrar_datos_checkbox')));
      await _tocar(tester, continuar);

      await tester.tap(find.text('No, conservar mi backup en Drive'));
      await tester.pump();
      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(_datos.borrados, [false]);
      expect(_remote.llamadasCerrarSesion, 1, reason: 'revoca el JWT en Supabase');
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget, reason: 'la UI navega al login');
    });

    testWidgets('Escenario: Borrado exitoso (incluyendo backup en Drive)', (tester) async {
      await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text('Sí, borrar también mi backup en Drive'));
      await tester.pump();
      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(_datos.borrados, [true]);
      expect(_login, findsOneWidget);
    });

    testWidgets('Escenario: Borrado exitoso (incluyendo backup en Drive) — Drive falla por red', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Right(
        ResultadoBorradoDatosLocales.backupDriveNoBorradoSinConexion,
      );
      await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text('Sí, borrar también mi backup en Drive'));
      await tester.pump();
      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos borrar el backup remoto; intentalo más tarde desde Drive.'),
        findsOneWidget,
      );
      expect(_login, findsOneWidget);
    });

    testWidgets('Escenario: Error -borrado de Drive falla y se exigió incluirlo', (tester) async {
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text('Sí, borrar también mi backup en Drive'));
      await tester.pump();
      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Tus datos locales se eliminaron. No pudimos borrar el backup en Drive; eliminalo '
          'manualmente desde drive.google.com o reintentá.',
        ),
        findsOneWidget,
      );
      expect(_datos.borrados, [true], reason: 'los datos locales sí se borran (no se revierte)');
      expect(_login, findsOneWidget);
    });

    testWidgets('Escenario: Edge -usuario cancela en el diálogo final', (tester) async {
      final container = await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.byKey(const Key('borrar_datos_cancelar')));
      await tester.pumpAndSettle();

      expect(_datos.borrados, isEmpty, reason: 'no se borra absolutamente nada');
      expect(container.read(sesionProvider).value, isNotNull);
      expect(find.byType(ConfiguracionPage), findsOneWidget, reason: 'vuelvo a Configuración');
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);
    });

    testWidgets('Escenario: Edge -sin sesión válida (caso raro)', (tester) async {
      final container = await _montar(tester);
      _remote.simularSinConexion = true; // la revocación no puede llegar al servidor
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(_datos.borrados, [false], reason: 'el borrado local procede igual');
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget);
    });

    testWidgets('pendientes: avisa cuántas se pierden y pide confirmarlo aparte (#66)', (
      tester,
    ) async {
      _datos.respuestaResumen = const Right(
        ResumenDatosLocales(
          personas: 2,
          visitas: 5,
          operacionesSinSincronizar: 7,
          hayBackupEnDrive: false,
        ),
      );
      final container = await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text(TextosBorrado.pendientes(7)), findsOneWidget);
      await _tocar(tester, find.byKey(const Key('borrar_datos_checkbox')));
      final continuar = find.byKey(const Key('borrar_datos_continuar'));
      expect(
        tester.widget<FilledButton>(continuar).onPressed,
        isNull,
        reason: 'falta confirmar que se pierden las pendientes',
      );

      await _tocar(tester, find.byKey(const Key('borrar_datos_checkbox_pendientes')));
      await _tocar(tester, continuar);
      expect(find.byKey(const Key('borrar_datos_dialogo_pendientes')), findsOneWidget);
      await tester.tap(find.text(TextosBorrado.confirmarFinal));
      await tester.pumpAndSettle();

      expect(_datos.borrados, [false], reason: 'el borrado se hace igual');
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget);
    });

    testWidgets('pendientes desconocidos: avisa que no se pudieron contar y deja borrar', (
      tester,
    ) async {
      _datos.respuestaResumen = const Right(
        ResumenDatosLocales(
          personas: 0,
          visitas: 0,
          operacionesSinSincronizar: null,
          hayBackupEnDrive: false,
        ),
      );
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text('No se pudieron contar'), findsOneWidget);
      expect(find.text(TextosBorrado.pendientesDesconocidos), findsOneWidget);
      await _tocar(tester, find.byKey(const Key('borrar_datos_checkbox')));
      await _tocar(tester, find.byKey(const Key('borrar_datos_checkbox_pendientes')));
      await _tocar(tester, find.byKey(const Key('borrar_datos_continuar')));
      await tester.tap(find.text(TextosBorrado.confirmarFinal));
      await tester.pumpAndSettle();

      expect(_datos.borrados, [false]);
      expect(_login, findsOneWidget);
    });

    testWidgets('error: si el borrado falla, avisa y la sesión sigue abierta', (tester) async {
      _datos.respuestaBorrado = const Left(FailureInesperado());
      final container = await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(find.text(TextosBorrado.errorBorrado), findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(find.byType(BorrarDatosLocalesPage), findsOneWidget);

      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.completo);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(_datos.borrados, [false, false]);
      expect(_login, findsOneWidget);
    });

    testWidgets('error: si borra pero no puede cerrar la sesión, no muestra el login', (
      tester,
    ) async {
      final local = _LocalQueNoBorra();
      final container = await _montar(tester, local: local);
      local.fallar = true;
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text('Sí, borrar datos locales'));
      await tester.pumpAndSettle();

      expect(find.text(TextosBorrado.errorBorrado), findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(_login, findsNothing);

      local.fallar = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    testWidgets('error: si no puede revisar los datos, no ofrece borrar y deja reintentar', (
      tester,
    ) async {
      _datos.respuestaResumen = const Left(FailureDatosLocalesIlegibles());
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text(const FailureDatosLocalesIlegibles().mensaje), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_continuar')), findsNothing);
      expect(_datos.borrados, isEmpty);

      _datos.respuestaResumen = const Right(_resumenBase);
      await _tocar(tester, find.byKey(const Key('borrar_datos_reintentar')));
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('cargando: mientras cuenta, lo dice', (tester) async {
      await _montar(tester);
      _datos.demoraResumen = Completer<void>();

      await tester.tap(find.byKey(const Key('configuracion_borrar_datos')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Revisando los datos de este teléfono…'), findsOneWidget);
      _datos.demoraResumen!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('sin backup en Drive, el diálogo final no pregunta por Drive', (tester) async {
      _datos.respuestaResumen = const Right(
        ResumenDatosLocales(
          personas: 0,
          visitas: 0,
          operacionesSinSincronizar: 0,
          hayBackupEnDrive: false,
        ),
      );
      await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      expect(find.text(TextosBorrado.conservarDrive), findsNothing);
      expect(find.text(TextosBorrado.borrarDrive), findsNothing);
    });

    testWidgets('mientras borra, el PopScope bloquea el back y "atrás" queda deshabilitado', (
      tester,
    ) async {
      _datos.demoraBorrado = Completer<void>();
      await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await tester.tap(find.text(TextosBorrado.confirmarFinal));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('borrar_datos_borrando')), findsOneWidget);
      // El ListView quedó scrolleado hacia abajo por los toques anteriores (checkbox, continuar):
      // "atrás" (arriba del todo) queda fuera del viewport actual y flutter_test lo trata como
      // offstage por default. No hace falta tocarlo, solo inspeccionar su estado: skipOffstage:
      // false alcanza, sin necesidad de scrollear de vuelta.
      final atras = find.byKey(const Key('borrar_datos_atras'), skipOffstage: false);
      expect(
        tester.widget<IconButton>(atras).onPressed,
        isNull,
        reason: '"atrás" no puede sacar de la pantalla mientras borra',
      );
      final popScope = tester.widget<PopScope>(
        find.descendant(
          of: find.byType(BorrarDatosLocalesPage),
          matching: find.byType(PopScope),
          skipOffstage: false,
        ),
      );
      expect(
        popScope.canPop,
        isFalse,
        reason: 'el gesto/botón de sistema tampoco puede sacar de la pantalla mientras borra',
      );

      _datos.demoraBorrado!.complete();
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    // skip: QA #68 — HU-AUTH-010 (casos borde) pide esperar o cancelar limpiamente una operación
    // en curso (sync o backup activo) antes de borrar. No hay motor de sync ni jobs de backup en
    // el código todavía — nada que testear hasta que existan.
    testWidgets(
      'caso borde: borrado con una operación en curso (sync o backup activo) espera o cancela '
      'limpiamente',
      (tester) async {
        fail('no hay nada que probar: no existe motor de sync ni job de backup en el código');
      },
      skip: true,
    );
  });

  group('Accesibilidad', () {
    for (final tema in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('Configuración cumple las guías (${tema.name})', (tester) async {
        final handle = tester.ensureSemantics();
        tester.platformDispatcher.platformBrightnessTestValue = tema == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _montar(tester);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await _abrirBorrado(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('con textScaler 2.0 no hay overflow en Configuración ni en el borrado', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _montar(tester);
      expect(tester.takeException(), isNull);

      await _llegarAlDialogoFinal(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(TextosBorrado.borrarDrive), findsOneWidget);
    });

    testWidgets('el resumen de borrado con operaciones pendientes cumple las guías', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _datos.respuestaResumen = const Right(
        ResumenDatosLocales(
          personas: 2,
          visitas: 5,
          operacionesSinSincronizar: 7,
          hayBackupEnDrive: true,
        ),
      );
      await _montar(tester);
      await _abrirBorrado(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('el diálogo final (con la opción de backup en Drive) cumple las guías', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _montar(tester);
      await _llegarAlDialogoFinal(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
