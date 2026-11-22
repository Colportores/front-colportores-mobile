// Seguimiento de la vista 18 (HU-AUTH-008, #383): la respuesta tardía de la consulta de la cuenta que
// la restringe (suspendida o pendiente) cuando la persona ya entró a su inicio con lo último que
// sabía («activa»). Decisión de Cristian (21/10), «Suspensión»: avisar y frenar sin perder nada.
//
// - Sin nada abierto: la app pasa directo a la pantalla de su cuenta.
// - Con algo abierto (un formulario, una hoja, Configuración): lo termina y lo guarda, se le avisa
//   por qué va a cambiar la pantalla, y al guardar o salir llega a la pantalla de su cuenta.
// - Si la respuesta habilita (activa): el inicio no cambia bajo los dedos.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_falsos.dart';
import '../helpers/alta_ubicacion_qa_arnes.dart';
import '../helpers/db_local_repository_en_memoria.dart';

final _principal = find.byKey(const Key('inicio_principal'));
final _titulo = find.byKey(const Key('espera_titulo'));
final _revisando = find.byKey(const Key('revisando_cuenta_pagina'));
final _configuracion = find.byKey(const Key('inicio_configuracion'));
final _atrasDeConfiguracion = find.byKey(const Key('configuracion_atras'));
final _aviso = find.byKey(const Key('cuenta_restringida_aviso'));
final _avisoModulo = find.byKey(const Key('modulo_bloqueado_aviso'));
final _login = find.byKey(const Key('login_enviar'));

/// Los 15 s del arranque (los mismos del GPS, #267).
const _tope = Duration(seconds: 15);

late EstadoCuentaEnMemoria _backend;
late EstadoCuentaLocalEnMemoria _recordado;
late ProviderContainer _container;
late RepoAltaFalso _repo;

Future<void> _montar(WidgetTester tester, {required EstadoCuenta contestara}) async {
  _backend = EstadoCuentaEnMemoria(estado: contestara);
  _recordado = EstadoCuentaLocalEnMemoria();
  _repo = RepoAltaFalso();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ahoraEsperaProvider.overrideWithValue(() => DateTime(2026, 10, 7, 14, 30)),
        asignacionCampaniaDataSourceProvider.overrideWithValue(AsignacionCampaniaEnMemoria()),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(_backend),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(_recordado),
        ...overridesAlta(repo: _repo),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  _container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> _entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.ensureVisible(_login);
  await tester.tap(_login);
  await tester.pump();
  await tester.pump();
}

/// Deja pasar el tope del arranque y dibuja lo que sigue.
Future<void> _vencerElTope(WidgetTester tester) async {
  await tester.pump(_tope);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

void _tamano(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Entra con lo último que sabía («activa») mientras la consulta del estado queda colgada: pasados
/// los 15 s la persona está en su inicio. Devuelve la respuesta que se está haciendo esperar;
/// [contestara] es lo que dirá el backend cuando llegue.
Future<Completer<void>> _enElInicioConLaConsultaColgada(
  WidgetTester tester, {
  required EstadoCuenta contestara,
}) async {
  await _montar(tester, contestara: contestara);
  final colgada = _backend.demora = Completer<void>();
  await _entrar(tester);
  final usuarioId = _container.read(sesionProvider).value!.usuarioId;
  await _recordado.guardar(usuarioId, EstadoCuenta.activa);
  await _vencerElTope(tester);
  expect(_principal, findsOneWidget, reason: 'entró con lo último que sabía');
  return colgada;
}

/// La respuesta llega tarde, pasado el tope.
Future<void> _llegaLaRespuesta(WidgetTester tester, Completer<void> colgada) async {
  colgada.complete();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Abre el alta de ubicación encima del inicio, como lo hace «Registrar» de la lista, y elige el tipo
/// para que se pueda registrar.
Future<void> _abrirElAlta(WidgetTester tester) async {
  final usuarioId = _container.read(sesionProvider).value!.usuarioId;
  unawaited(AltaUbicacionPage.abrir(tester.element(_principal), colportorId: usuarioId));
  await asentar(tester);
  await tocar(tester, find.text('Casa'));
  expect(botonRegistrar, findsOneWidget);
}

bool _registrarHabilitado(WidgetTester tester) =>
    tester.widget<FilledButton>(botonRegistrar).onPressed != null;

/// Los avisos de la cuenta que se restringió con algo abierto: el de esa cuenta y que lo abierto se
/// puede terminar y guardar.
final _suspendidaConLoAbierto = TextosModuloBloqueado.conLoAbierto(EstadoCuenta.suspendida);
final _pendienteConLoAbierto = TextosModuloBloqueado.conLoAbierto(EstadoCuenta.pendienteAsignacion);

/// El texto del aviso de la cuenta restringida.
Finder _textoDelAviso(String texto) => find.descendant(of: _aviso, matching: find.text(texto));

void main() {
  group('sin nada abierto: la respuesta tardía pasa directo a la pantalla de la cuenta', () {
    testWidgets('«suspendida»: Cuenta suspendida, sin aviso encima, y queda recordada', (
      tester,
    ) async {
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );

      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(_principal, findsNothing);
      expect(_titulo, findsOneWidget);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(find.text(TextosEsperaAsignacion.suspendida), findsOneWidget);
      expect(_aviso, findsNothing, reason: 'la pantalla de la cuenta ya es el aviso');
      expect(tester.takeException(), isNull);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      expect(await _recordado.leer(usuarioId), EstadoCuenta.suspendida);
    });

    testWidgets('«pendiente»: Esperando asignación', (tester) async {
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.pendienteAsignacion,
      );

      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(_principal, findsNothing);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«activa»: el inicio no cambia bajo los dedos ni avisa nada', (tester) async {
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.activa,
      );

      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
      expect(_aviso, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      expect(await _recordado.leer(usuarioId), EstadoCuenta.activa);
    });

    testWidgets('después de restringirse no se vuelve al inicio: la barra de la cuenta bloquea los '
        'módulos', (tester) async {
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inicio_pestana_ventas')));
      await tester.pumpAndSettle();

      expect(_principal, findsNothing);
      expect(
        find.descendant(of: _avisoModulo, matching: find.text(TextosModuloBloqueado.suspendida)),
        findsOneWidget,
      );
    });
  });

  group('con Configuración abierta', () {
    testWidgets('«suspendida»: el aviso con el texto de la cuenta; al volver, la pantalla de la '
        'cuenta y sin aviso', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      expect(_atrasDeConfiguracion, findsOneWidget);

      await _llegaLaRespuesta(tester, colgada);

      expect(_atrasDeConfiguracion, findsOneWidget, reason: 'lo abierto sigue abierto');
      expect(_textoDelAviso(_suspendidaConLoAbierto), findsOneWidget);
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(_atrasDeConfiguracion);
      await tester.pumpAndSettle();

      expect(_titulo, findsOneWidget);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(_aviso, findsNothing, reason: 'la pantalla de la cuenta ya lo dice');
      expect(tester.takeException(), isNull);
    });

    testWidgets('«pendiente»: el aviso de la cuenta que espera asignación', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.pendienteAsignacion,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();

      await _llegaLaRespuesta(tester, colgada);

      expect(_textoDelAviso(_pendienteConLoAbierto), findsOneWidget);
      await tester.tap(_atrasDeConfiguracion);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('«activa»: Configuración y el inicio quedan como estaban, sin aviso', (
      tester,
    ) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.activa,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();

      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(_atrasDeConfiguracion);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });
  });

  group('con el alta de una ubicación abierta (no se pierde lo que estaba cargando)', () {
    testWidgets('lo abierto se puede terminar y guardar; al guardar, la pantalla de la cuenta', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _abrirElAlta(tester);

      await _llegaLaRespuesta(tester, colgada);
      await asentar(tester);

      // El formulario sigue, con lo que ya había elegido, y el aviso le dice por qué.
      expect(botonRegistrar, findsOneWidget);
      expect(_registrarHabilitado(tester), isTrue);
      expect(_textoDelAviso(_suspendidaConLoAbierto), findsOneWidget);
      expect(_repo.llamadas, isEmpty);

      await tocar(tester, botonRegistrar);

      expect(_repo.llamadas, hasLength(1), reason: 'se guardó lo que tenía abierto');
      expect(botonRegistrar, findsNothing);
      expect(_titulo, findsOneWidget);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(_principal, findsNothing);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cuenta «pendiente»: mismo recorrido, con su aviso', (tester) async {
      _tamano(tester, const Size(390, 844));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.pendienteAsignacion,
      );
      await _abrirElAlta(tester);

      await _llegaLaRespuesta(tester, colgada);
      await asentar(tester);
      expect(_textoDelAviso(_pendienteConLoAbierto), findsOneWidget);

      await tocar(tester, botonRegistrar);

      expect(_repo.llamadas, hasLength(1));
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'salir sin guardar: la pantalla de la cuenta, sin perder nada y sin forma de volver '
      'al inicio',
      (tester) async {
        _tamano(tester, const Size(390, 844));
        final colgada = await _enElInicioConLaConsultaColgada(
          tester,
          contestara: EstadoCuenta.suspendida,
        );
        await _abrirElAlta(tester);
        await _llegaLaRespuesta(tester, colgada);
        await asentar(tester);

        await tester.binding.handlePopRoute();
        await asentar(tester);
        await tester.pumpAndSettle();

        expect(_repo.llamadas, isEmpty);
        expect(_titulo, findsOneWidget);
        expect(_principal, findsNothing);
        expect(_aviso, findsNothing);
        expect(tester.takeException(), isNull);
        // Reentrar a un módulo: bloqueado, con el texto de su cuenta.
        await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
        await tester.pumpAndSettle();
        expect(_principal, findsNothing);
        expect(
          find.descendant(of: _avisoModulo, matching: find.text(TextosModuloBloqueado.suspendida)),
          findsOneWidget,
        );
      },
    );

    testWidgets('el guardado falla a mitad: el formulario sigue, el botón se vuelve a habilitar y '
        'el reintento guarda y lleva a la cuenta', (tester) async {
      _tamano(tester, const Size(390, 844));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _abrirElAlta(tester);
      await _llegaLaRespuesta(tester, colgada);
      await asentar(tester);
      var falla = true;
      _repo.comportamiento = (ubicacion) async =>
          falla ? const Left(FailureInesperado()) : Right(AltaRegistrada(ubicacion: ubicacion));

      await tocar(tester, botonRegistrar);

      expect(_repo.llamadas, hasLength(1));
      expect(botonRegistrar, findsOneWidget, reason: 'no se cierra con el guardado fallido');
      expect(_registrarHabilitado(tester), isTrue, reason: 'ningún ocupado trabado');
      expect(_titulo, findsNothing, reason: 'sin guardar no se lo saca del formulario');

      falla = false;
      await tocar(tester, botonRegistrar);

      expect(_repo.llamadas, hasLength(2));
      expect(botonRegistrar, findsNothing);
      expect(_titulo, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('doble toque en Registrar con la cuenta ya restringida: se guarda una sola vez', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _abrirElAlta(tester);
      await _llegaLaRespuesta(tester, colgada);
      await asentar(tester);
      final guardando = _repo.bloqueo = Completer<void>();

      await tester.ensureVisible(botonRegistrar);
      final lugar = tester.getCenter(botonRegistrar);
      await tester.tapAt(lugar);
      await tester.pump();
      await tester.tapAt(lugar);
      await asentar(tester);
      guardando.complete();
      await asentar(tester);
      await tester.pumpAndSettle();

      expect(_repo.llamadas, hasLength(1));
      expect(_titulo, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la respuesta llega con el guardado en vuelo: termina, guarda y va a la cuenta', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _abrirElAlta(tester);
      final guardando = _repo.bloqueo = Completer<void>();
      await tester.ensureVisible(botonRegistrar);
      await tester.tap(botonRegistrar);
      await asentar(tester);
      expect(_repo.llamadas, hasLength(1));

      await _llegaLaRespuesta(tester, colgada);
      expect(_textoDelAviso(_suspendidaConLoAbierto), findsOneWidget);
      guardando.complete();
      await asentar(tester);
      await tester.pumpAndSettle();

      expect(_repo.llamadas, hasLength(1));
      expect(botonRegistrar, findsNothing);
      expect(_titulo, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«activa»: el formulario y el inicio siguen igual; al guardar vuelve al inicio', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.activa,
      );
      await _abrirElAlta(tester);

      await _llegaLaRespuesta(tester, colgada);
      await asentar(tester);
      expect(find.byType(SnackBar), findsNothing);
      await tocar(tester, botonRegistrar);
      await tester.pumpAndSettle();

      expect(_repo.llamadas, hasLength(1));
      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });
  });

  group('el aviso', () {
    testWidgets('se cierra con «Entendido» y no vuelve', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      await tester.tap(find.byKey(const Key('cuenta_restringida_entendido')));
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(_atrasDeConfiguracion, findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(_aviso, findsNothing);
    });

    testWidgets('queda a la vista hasta que la persona lo cierra: no se va solo', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _llegaLaRespuesta(tester, colgada);

      await tester.pump(const Duration(minutes: 2));

      expect(_aviso, findsOneWidget);
    });

    testWidgets('no tapa el botón con el que se termina lo que está abierto', (tester) async {
      _tamano(tester, const Size(360, 640));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _abrirElAlta(tester);

      await _llegaLaRespuesta(tester, colgada);
      await asentar(tester);

      expect(_aviso, findsOneWidget);
      await tester.ensureVisible(botonRegistrar);
      await tester.pump();
      final aviso = tester.getRect(_aviso);
      final boton = tester.getRect(botonRegistrar);
      expect(aviso.overlaps(boton), isFalse, reason: 'el aviso no queda sobre «Registrar»');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no cierra un aviso que ya estaba a la vista (un error del formulario)', (
      tester,
    ) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(_atrasDeConfiguracion),
      ).showSnackBar(const SnackBar(content: Text('Otro aviso del formulario')));
      await tester.pump();

      await _llegaLaRespuesta(tester, colgada);

      expect(find.text('Otro aviso del formulario'), findsOneWidget);
      expect(_textoDelAviso(_suspendidaConLoAbierto), findsOneWidget);
    });

    testWidgets('a 360×640 y con el texto al 200 %: se lee entero y no desborda', (tester) async {
      _tamano(tester, const Size(360, 640), texto: 2);
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();

      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(_textoDelAviso(_suspendidaConLoAbierto), findsOneWidget);
      final caja = tester.getRect(_aviso);
      expect(caja.left, greaterThanOrEqualTo(0));
      expect(caja.right, lessThanOrEqualTo(360));
      expect(caja.bottom, lessThanOrEqualTo(640));
      expect(find.byKey(const Key('cuenta_restringida_entendido')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('se anuncia a los lectores de pantalla (región viva) y «Entendido» tiene el '
        'tamaño de un botón', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final semantica = tester.ensureSemantics();
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(_textoDelAviso(_suspendidaConLoAbierto), findsOneWidget);
      expect(
        find.ancestor(
          of: _textoDelAviso(_suspendidaConLoAbierto),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
        reason: 'se anuncia apenas aparece',
      );
      final entendido = tester.getSize(find.byKey(const Key('cuenta_restringida_entendido')));
      expect(entendido.height, greaterThanOrEqualTo(48));
      semantica.dispose();
    });
  });

  group('casos límite de la respuesta', () {
    testWidgets('la de un arranque anterior (sesión cerrada y otra entrada) no restringe la '
        'sesión nueva', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final vieja = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      // Cierra la sesión desde Configuración y vuelve a entrar con la consulta colgada otra vez.
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
      _backend.demora = Completer<void>();
      await _entrar(tester);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      await _recordado.guardar(usuarioId, EstadoCuenta.activa);
      await _vencerElTope(tester);
      expect(_principal, findsOneWidget);

      await _llegaLaRespuesta(tester, vieja);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una respuesta con error después del tope no restringe nada', (tester) async {
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      _backend.falla = const ServidorException(status: 503);

      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(_revisando, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si después la reactivan, al volver a consultar entra otra vez', (tester) async {
      final colgada = await _enElInicioConLaConsultaColgada(
        tester,
        contestara: EstadoCuenta.suspendida,
      );
      await _llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();
      expect(find.text('Cuenta suspendida'), findsOneWidget);

      // El administrador la reactivó: la próxima consulta (o «Actualizar») la trae.
      _backend
        ..demora = null
        ..estado = EstadoCuenta.activa;
      _container.invalidate(estadoCuentaProvider);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });
  });
}
