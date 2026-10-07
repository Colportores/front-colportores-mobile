// QA de la vista 18 (PR #315, issue #278, HU-AUTH-008): el arranque «Revisando con el servidor…»
// con tope de 15 s y el aviso de los módulos bloqueados sin estado conocido. Complementa
// `esperando_asignacion_arranque_278_test.dart` con lo que ese archivo no cubre: respuestas que se
// cruzan con un reintento, salida mientras un reintento cuelga, y tamaños con las fuentes reales
// (Inter) en vez de Ahem. Un test con `skip` documenta un hallazgo del QA.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _revisando = find.byKey(const Key('revisando_cuenta_pagina'));
final _textoRevisando = find.text('Revisando con el servidor…');
final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _configuracion = find.byKey(const Key('espera_configuracion'));
final _principal = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));
final _sinConexion = find.byKey(const Key('espera_sin_conexion'));
final _error = find.byKey(const Key('espera_error'));
final _aviso = find.byKey(const Key('modulo_bloqueado_aviso'));

const _tope = Duration(seconds: 15);

/// Los cuatro módulos de campo de la barra.
const _modulos = ['mapa', 'lista', 'agenda', 'ventas'];

/// Un servidor que contesta cuando el test lo decide, pedido por pedido, y con la respuesta que
/// tenía cuando lo atendió (no la de cuando se completa el `Future`): así se reproduce que dos
/// respuestas lleguen en desorden.
final class _ServidorManual implements EstadoCuentaRemoteDataSource {
  final pedidos = <Completer<EstadoCuenta>>[];

  @override
  Future<EstadoCuenta> consultar() {
    final pedido = Completer<EstadoCuenta>();
    pedidos.add(pedido);
    return pedido.future;
  }
}

final class _SinDatosLocales implements DatosLocalesRepository {
  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async => const Right(
    ResumenDatosLocales(
      personas: 0,
      visitas: 0,
      operacionesSinSincronizar: 0,
      hayBackupEnDrive: false,
    ),
  );

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

late EstadoCuentaRemoteDataSource _backend;
late EstadoCuentaLocalEnMemoria _recordado;
late ProviderContainer _container;

EstadoCuentaEnMemoria get _enMemoria => _backend as EstadoCuentaEnMemoria;

/// Sin las fuentes del proyecto `flutter_test` pinta Ahem (cada letra es un cuadrado del tamaño de
/// la fuente, el doble de ancho que Inter): los tamaños se miden con las reales.
Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
  final raiz = Platform.environment['FLUTTER_ROOT'];
  final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (raiz != null && iconos.existsSync()) {
    final bytes = iconos.readAsBytesSync();
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
});

void _tamano(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _montar(
  WidgetTester tester, {
  EstadoCuentaRemoteDataSource? backend,
  EstadoCuenta estado = EstadoCuenta.pendienteAsignacion,
}) async {
  _backend = backend ?? EstadoCuentaEnMemoria(estado: estado);
  _recordado = EstadoCuentaLocalEnMemoria();
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
        datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
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

/// Entra con un servidor manual: la primera consulta queda en vuelo (`pedidos[0]`).
Future<_ServidorManual> _entrarConServidorManual(WidgetTester tester) async {
  final servidor = _ServidorManual();
  await _montar(tester, backend: servidor);
  await _entrar(tester);
  return servidor;
}

Future<void> _vencerElTope(WidgetTester tester) async {
  await tester.pump(_tope);
  await tester.pumpAndSettle();
}

/// Toca «Reintentar» y devuelve el lugar de su consulta en `servidor.pedidos`: un toque, un pedido.
Future<int> _tocarReintentar(WidgetTester tester, _ServidorManual servidor) async {
  final antes = servidor.pedidos.length;
  await tester.ensureVisible(_actualizar);
  await tester.tap(_actualizar);
  await tester.pump();
  expect(servidor.pedidos, hasLength(antes + 1), reason: 'un toque, una consulta');
  return antes;
}

Future<void> _tocarModulo(WidgetTester tester, String modulo) async {
  await tester.tap(find.byKey(Key('inicio_pestana_$modulo')));
  await tester.pumpAndSettle();
}

Future<void> _cerrarSesionDesdeConfiguracion(WidgetTester tester) async {
  await tester.tap(_configuracion);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
  await tester.pumpAndSettle();
}

/// Todos los textos del aviso del módulo bloqueado: el mensaje y, si la trae, la acción.
List<String> _textosDelAviso(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.descendant(of: _aviso, matching: find.byType(Text))))
    ?t.data,
];

Future<void> _guiasDeAccesibilidad(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Las causas por las que no se conoce el estado y cómo se provocan.
final _causas = <String, void Function(EstadoCuentaEnMemoria)>{
  'sin conexión': (b) => b.simularSinConexion = true,
  'servidor caído (503)': (b) => b.falla = const ServidorException(status: 503),
  'servidor caído (500 con mensaje)': (b) =>
      b.falla = const ServidorException(status: 500, mensaje: 'internal'),
};

void main() {
  group('#278 — el aviso del módulo bloqueado sin estado nunca habla de asignación', () {
    for (final MapEntry(key: causa, value: provocar) in _causas.entries) {
      testWidgets('$causa: ningún módulo, desde la espera ni desde Configuración, afirma que la '
          'cuenta espera asignación', (tester) async {
        await _montar(tester);
        provocar(_enMemoria);
        await _entrar(tester);
        await tester.pumpAndSettle();

        for (final modulo in _modulos) {
          await _tocarModulo(tester, modulo);
          for (final texto in _textosDelAviso(tester)) {
            expect(texto, isNot(matches(RegExp('asign', caseSensitive: false))), reason: modulo);
          }
        }

        await tester.tap(_configuracion);
        await tester.pumpAndSettle();
        for (final modulo in _modulos) {
          await _tocarModulo(tester, modulo);
          for (final texto in _textosDelAviso(tester)) {
            expect(texto, isNot(matches(RegExp('asign', caseSensitive: false))), reason: modulo);
          }
          expect(_textosDelAviso(tester), isNot(contains(startsWith('Disponible cuando'))));
        }
        await tester.pumpAndSettle();
      });
    }

    testWidgets('después del tope del arranque también', (tester) async {
      final servidor = await _entrarConServidorManual(tester);
      await _vencerElTope(tester);
      for (final modulo in _modulos) {
        await _tocarModulo(tester, modulo);
        expect(
          find.descendant(of: _aviso, matching: find.textContaining('asign')),
          findsNothing,
          reason: modulo,
        );
      }
      servidor.pedidos.first.complete(EstadoCuenta.pendienteAsignacion);
      await tester.pumpAndSettle();
    });
  });

  group('18A·02 en la raíz — lo que el arranque tiene y no tiene', () {
    testWidgets('solo el texto del diseño y el indicador: sin título de cuenta, sin botones', (
      tester,
    ) async {
      final servidor = await _entrarConServidorManual(tester);

      expect(find.descendant(of: _revisando, matching: find.byType(Text)), findsOneWidget);
      expect(_textoRevisando, findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      // «Consultando…» es del botón de la pantalla de espera, no del arranque.
      expect(find.text('Consultando…'), findsNothing);
      // Nada que afirme un estado de la cuenta.
      expect(find.textContaining('CUENTA'), findsNothing);
      expect(find.textContaining('asign'), findsNothing);

      servidor.pedidos.first.complete(EstadoCuenta.activa);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);
    });

    testWidgets('el indicador no se anuncia solo: el lector dice el texto una vez', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        final servidor = await _entrarConServidorManual(tester);

        expect(find.bySemanticsLabel('Revisando con el servidor…'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Progress|Cargando|progress')), findsNothing);

        servidor.pedidos.first.complete(EstadoCuenta.activa);
        await tester.pumpAndSettle();
      } finally {
        semantica.dispose();
      }
    });

    testWidgets('al pasar al aviso del tope, el aviso se anuncia (liveRegion) y el título es '
        'encabezado', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        final servidor = await _entrarConServidorManual(tester);
        await _vencerElTope(tester);

        expect(tester.getSemantics(_sinConexion), isSemantics(isLiveRegion: true));
        expect(tester.getSemantics(_titulo), isSemantics(isHeader: true));

        servidor.pedidos.first.complete(EstadoCuenta.pendienteAsignacion);
        await tester.pumpAndSettle();
      } finally {
        semantica.dispose();
      }
    });
  });

  group('el tope de 15 s llega a la pantalla', () {
    testWidgets(
      'a los 16 s sin respuesta el aviso ya está en pantalla y se hizo una sola consulta al '
      'servidor',
      (tester) async {
        final servidor = await _entrarConServidorManual(tester);

        await tester.pump(_tope + const Duration(seconds: 1));
        await tester.pump();

        expect(_revisando, findsNothing);
        expect(_sinConexion, findsOneWidget);
        expect(servidor.pedidos, hasLength(1), reason: 'sin reintentos automáticos escondidos');
      },
    );

    testWidgets('a los 14 s todavía dice «Revisando con el servidor…» y el aviso no salió', (
      tester,
    ) async {
      final servidor = await _entrarConServidorManual(tester);

      await tester.pump(const Duration(seconds: 14));

      expect(_textoRevisando, findsOneWidget);
      expect(_sinConexion, findsNothing);
      expect(servidor.pedidos, hasLength(1));

      servidor.pedidos.first.complete(EstadoCuenta.activa);
      await tester.pumpAndSettle();
    });
  });

  group('acciones superpuestas — el tope y un reintento', () {
    testWidgets(
      'la respuesta vieja llega mientras el reintento sigue en vuelo: la pantalla termina '
      'con la respuesta del reintento',
      (tester) async {
        final servidor = await _entrarConServidorManual(tester);
        await _vencerElTope(tester);

        final reintento = await _tocarReintentar(tester, servidor);
        expect(find.text('Consultando…'), findsOneWidget);

        servidor.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
        await tester.pump();
        expect(tester.takeException(), isNull);

        servidor.pedidos[reintento].complete(EstadoCuenta.activa);
        await tester.pumpAndSettle();
        expect(_principal, findsOneWidget);
      },
    );

    testWidgets('el reintento sale bien y después llega la respuesta vieja: la pantalla no vuelve '
        'atrás', (tester) async {
      final servidor = await _entrarConServidorManual(tester);
      await _vencerElTope(tester);
      final reintento = await _tocarReintentar(tester, servidor);
      servidor.pedidos[reintento].complete(EstadoCuenta.activa);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);

      servidor.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
      expect(tester.takeException(), isNull);
    });

    // skip: QA #278 — una respuesta vieja que llega tarde pisa en el teléfono el estado más nuevo.
    testWidgets(
      'el reintento sale bien y después llega la respuesta vieja: lo que queda recordado para el '
      'próximo arranque sin red es lo más nuevo',
      (tester) async {
        final servidor = await _entrarConServidorManual(tester);
        await _vencerElTope(tester);
        final reintento = await _tocarReintentar(tester, servidor);
        servidor.pedidos[reintento].complete(EstadoCuenta.activa);
        await tester.pumpAndSettle();
        final usuarioId = _container.read(sesionProvider).value!.usuarioId;
        expect(await _recordado.leer(usuarioId), EstadoCuenta.activa);

        servidor.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
        await tester.pumpAndSettle();

        expect(await _recordado.leer(usuarioId), EstadoCuenta.activa);
      },
      skip: true,
    );

    // skip: QA #278 — decisión del 07/10 (pendientes/…-278-qa-261007-1835.md, P1): el reintento a mano
    // tiene el mismo tope de 15 s; hoy «Consultando…» queda colgado mientras el servidor no conteste.
    testWidgets(
      'el reintento a mano también vence a los 15 s: vuelve el aviso de la causa con «Reintentar» '
      'a mano',
      (tester) async {
        final servidor = await _entrarConServidorManual(tester);
        await _vencerElTope(tester);
        await _tocarReintentar(tester, servidor);
        expect(find.text('Consultando…'), findsOneWidget);

        await tester.pump(_tope + const Duration(seconds: 1));
        await tester.pump();

        expect(find.text('Consultando…'), findsNothing);
        expect(_sinConexion, findsOneWidget);
        expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
      },
      skip: true,
    );

    // skip: QA #278 — decisión del 07/10 (pendientes/…-278-qa-261007-1835.md, P2): una respuesta se
    // aplica solo si ninguna consulta pedida después ya contestó. Hoy la vieja «activa» pisa a la
    // «suspendida» más nueva y la persona entra con la cuenta suspendida.
    testWidgets(
      'el reintento dice suspendida y después llega la vieja con activa: la pantalla sigue '
      'bloqueada',
      (tester) async {
        final servidor = await _entrarConServidorManual(tester);
        await _vencerElTope(tester);
        final reintento = await _tocarReintentar(tester, servidor);
        servidor.pedidos[reintento].complete(EstadoCuenta.suspendida);
        await tester.pumpAndSettle();
        expect(find.text(TextosEsperaAsignacion.tituloSuspendida), findsOneWidget);

        servidor.pedidos[0].complete(EstadoCuenta.activa);
        await tester.pumpAndSettle();

        expect(_principal, findsNothing);
        expect(find.text(TextosEsperaAsignacion.tituloSuspendida), findsOneWidget);
      },
      skip: true,
    );

    testWidgets('el reintento cuelga: la persona se va por Configuración y cierra sesión sin '
        'esperarlo', (tester) async {
      final servidor = await _entrarConServidorManual(tester);
      await _vencerElTope(tester);
      final reintento = await _tocarReintentar(tester, servidor);
      expect(find.text('Consultando…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await _cerrarSesionDesdeConfiguracion(tester);
      expect(_login, findsOneWidget);

      servidor.pedidos[reintento].complete(EstadoCuenta.activa);
      servidor.pedidos[0].complete(EstadoCuenta.activa);
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget, reason: 'la respuesta tardía no resucita la sesión cerrada');
      expect(tester.takeException(), isNull);
    });

    testWidgets('deslizar para refrescar con el reintento en vuelo no dispara otra consulta', (
      tester,
    ) async {
      final servidor = await _entrarConServidorManual(tester);
      await _vencerElTope(tester);
      final reintento = await _tocarReintentar(tester, servidor);
      final consultas = servidor.pedidos.length;

      await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1500);
      await tester.pump(const Duration(milliseconds: 500));

      expect(servidor.pedidos, hasLength(consultas), reason: 'el gesto no suma otra consulta');
      servidor.pedidos[reintento].complete(EstadoCuenta.pendienteAsignacion);
      await tester.pumpAndSettle();
      servidor.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('dos fallas seguidas (tope y después servidor caído) dejan «Reintentar» activo y '
        'un solo aviso', (tester) async {
      final servidor = await _entrarConServidorManual(tester);
      await _vencerElTope(tester);
      final primero = await _tocarReintentar(tester, servidor);
      servidor.pedidos[primero].completeError(const ServidorException(status: 503));
      await tester.pumpAndSettle();

      expect(_error, findsOneWidget);
      expect(_sinConexion, findsNothing);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);

      final segundo = await _tocarReintentar(tester, servidor);
      servidor.pedidos[segundo].complete(EstadoCuenta.pendienteAsignacion);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
      servidor.pedidos[0].complete(EstadoCuenta.pendienteAsignacion);
      await tester.pumpAndSettle();
    });
  });

  group('tamaños con las fuentes reales (Inter)', () {
    for (final (tam, texto, nombre) in const [
      (Size(360, 640), 1.0, '360x640'),
      (Size(360, 640), 2.0, '360x640 con texto 2.0'),
      (Size(412, 915), 1.0, '412x915'),
      (Size(412, 915), 2.0, '412x915 con texto 2.0'),
    ]) {
      testWidgets('el arranque a $nombre: texto entero en pantalla y guías de accesibilidad', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        try {
          await _cargarFuentes(tester);
          _tamano(tester, tam, texto: texto);
          final servidor = await _entrarConServidorManual(tester);
          await tester.pump(const Duration(milliseconds: 500));

          expect(tester.takeException(), isNull);
          final caja = tester.getRect(_textoRevisando);
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(tam.width));
          expect(caja.top, greaterThanOrEqualTo(0));
          expect(caja.bottom, lessThanOrEqualTo(tam.height));
          await _guiasDeAccesibilidad(tester);

          servidor.pedidos.first.complete(EstadoCuenta.activa);
          await tester.pumpAndSettle();
        } finally {
          semantica.dispose();
        }
      });

      for (final MapEntry(key: causa, value: provocar) in _causas.entries) {
        testWidgets('$causa a $nombre: la pantalla y el aviso del módulo, enteros y sin overflow', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          try {
            await _cargarFuentes(tester);
            _tamano(tester, tam, texto: texto);
            await _montar(tester);
            provocar(_enMemoria);
            await _entrar(tester);
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            await tester.ensureVisible(_actualizar);
            await tester.pump();
            await _guiasDeAccesibilidad(tester);

            await _tocarModulo(tester, 'mapa');
            expect(tester.takeException(), isNull);
            final caja = tester.getRect(_aviso);
            expect(caja.left, greaterThanOrEqualTo(0));
            expect(caja.right, lessThanOrEqualTo(tam.width));
            expect(caja.top, greaterThanOrEqualTo(0));
            expect(caja.bottom, lessThanOrEqualTo(tam.height));
            await _guiasDeAccesibilidad(tester);
            await tester.pumpAndSettle();
          } finally {
            semantica.dispose();
          }
        });
      }

      testWidgets('con el aviso del módulo a la vista, «Reintentar» queda a la mano a $nombre', (
        tester,
      ) async {
        await _cargarFuentes(tester);
        _tamano(tester, tam, texto: texto);
        await _montar(tester);
        _enMemoria.simularSinConexion = true;
        await _entrar(tester);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
        await tester.pump(const Duration(milliseconds: 600));

        expect(_aviso, findsOneWidget);
        final tapado = tester.getRect(_actualizar).overlaps(tester.getRect(_aviso));
        if (tapado) {
          expect(
            find.descendant(of: _aviso, matching: find.text('Reintentar')),
            findsOneWidget,
            reason: 'el aviso tapa el botón: tiene que traer la acción',
          );
        }
        await tester.pumpAndSettle();
      });
    }
  });

  group('Configuración con el estado sin conocer', () {
    testWidgets(
      'la barra bloqueada avisa lo de la pantalla y «Volver» deja a «Reintentar» a mano',
      (tester) async {
        await _montar(tester);
        _enMemoria.simularSinConexion = true;
        await _entrar(tester);
        await tester.pumpAndSettle();
        await tester.tap(_configuracion);
        await tester.pumpAndSettle();

        await _tocarModulo(tester, 'agenda');
        expect(
          find.descendant(
            of: _aviso,
            matching: find.text(TextosEsperaAsignacion.sinConexionSinEstado),
          ),
          findsOneWidget,
        );
        // El aviso nombra «Reintentar»: desde acá no hay botón, así que la salida es la flecha.
        expect(find.text('Reintentar'), findsNothing);
        await tester.tap(find.byKey(const Key('configuracion_atras')));
        await tester.pumpAndSettle();
        expect(_actualizar, findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets('si el estado se conoce con Configuración abierta, la barra se desbloquea', (
      tester,
    ) async {
      await _montar(tester);
      _enMemoria.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();

      _enMemoria.simularSinConexion = false;
      _enMemoria.estado = EstadoCuenta.activa;
      await _container.read(estadoCuentaProvider.notifier).refrescar();
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');

      expect(find.byKey(const Key('configuracion_pagina')), findsNothing);
      expect(_principal, findsOneWidget);
    });
  });
}
