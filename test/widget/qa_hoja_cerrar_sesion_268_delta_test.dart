// QA de la vista 16 «Configuración» (#225, PR #268), segunda pasada sobre la punta 11cb65f: lo que
// cambió desde el QA del 02/10 (la fila «Mapas offline» ya está en la pantalla, el merge de develop
// con las hojas sobre la barra de Android) y los casos que faltaban: fuentes reales y overflow a
// 2,0 en los dos tamaños, volver a abrir la hoja con el conteo distinto, y los dos menores que ya
// había anotado la revisión (con `skip`). Capturas PNG con `--dart-define=QA_CAPTURAS=true`, en
// `.dart_tool/qa_capturas/` (gitignored).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/nombre_cuenta_provider.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// (nombre, ancho, alto, escala de texto).
const _matriz = <(String, double, double, double)>[
  ('360x640_1x', 360, 640, 1),
  ('360x640_2x', 360, 640, 2),
  ('412x915_1x', 412, 915, 1),
  ('412x915_2x', 412, 915, 2),
];

Finder _k(String clave) => find.byKey(Key(clave));

bool _fuentesCargadas = false;

/// Carga las fuentes de `assets/fonts/` y los íconos: sin esto `flutter_test` pinta cajas y los
/// anchos de las palabras son falsos.
Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final candidato = raiz != null
          ? File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          : File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (candidato.existsSync()) {
        final bytes = candidato.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/268_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void _pantalla(WidgetTester tester, double ancho, double alto, double escala) {
  tester.view
    ..physicalSize = Size(ancho, alto)
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Un cuadro corto: con un indicador girando `pumpAndSettle` no termina nunca.
Future<void> _cuadro(WidgetTester tester) => tester.pump(const Duration(milliseconds: 150));

/// La hoja sola, abierta desde un botón.
Future<void> _abrirHoja(
  WidgetTester tester, {
  required int? pendientes,
  Future<bool> Function()? cerrar,
  Future<int?> Function()? contar,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('abrir_hoja'),
              onPressed: () => unawaited(
                mostrarHojaCerrarSesion(
                  context,
                  pendientes: pendientes,
                  cerrar: cerrar ?? () async => true,
                  contar: contar,
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_k('abrir_hoja'));
  await tester.pumpAndSettle();
}

/// Cada estado de la hoja (16A·02 a 16A·06 y el conteo que falla, decisión del 02/10).
final _estados = <String, Future<void> Function(WidgetTester)>{
  'a02_sin_pendientes': (t) => _abrirHoja(t, pendientes: 0),
  'a03_con_1': (t) => _abrirHoja(t, pendientes: 1),
  'a03_con_3': (t) => _abrirHoja(t, pendientes: 3),
  'a03_con_100': (t) => _abrirHoja(t, pendientes: 100),
  'sin_revisar': (t) => _abrirHoja(t, pendientes: null, contar: () async => null),
  'revisando': (t) async {
    await _abrirHoja(t, pendientes: null, contar: () => Completer<int?>().future);
    await t.tap(_k('configuracion_reintentar_conteo'));
    await _cuadro(t);
  },
  'a04_cerrando': (t) async {
    await _abrirHoja(t, pendientes: 0, cerrar: () => Completer<bool>().future);
    await t.tap(_k('configuracion_dialogo_confirmar'));
    await _cuadro(t);
  },
  'a04_cerrando_sin_revisar': (t) async {
    await _abrirHoja(
      t,
      pendientes: null,
      contar: () async => null,
      cerrar: () => Completer<bool>().future,
    );
    await t.tap(_k('configuracion_dialogo_confirmar'));
    await _cuadro(t);
  },
  'a06_error': (t) async {
    await _abrirHoja(t, pendientes: 0, cerrar: () async => false);
    await t.tap(_k('configuracion_dialogo_confirmar'));
    await t.pumpAndSettle();
  },
};

/// Un repositorio que contesta el conteo con lo que se le dé, en orden (el último se repite).
final class _ConteosEnOrden implements DatosLocalesRepository {
  _ConteosEnOrden(this._respuestas);

  final List<int?> _respuestas;
  int llamadas = 0;

  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async {
    final n = _respuestas[llamadas < _respuestas.length ? llamadas : _respuestas.length - 1];
    llamadas++;
    if (n == null) return const Left(FailureValidacion(campos: {}));
    return Right(
      ResumenDatosLocales(
        personas: 0,
        visitas: 0,
        operacionesSinSincronizar: n,
        hayBackupEnDrive: false,
      ),
    );
  }

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

/// La app entera con sesión iniciada y Configuración abierta.
Future<ProviderContainer> _abrirConfiguracion(
  WidgetTester tester, {
  required DatosLocalesRepository datos,
  String? nombre = 'Lucía Silva',
}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'Secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      datosLocalesRepositoryProvider.overrideWithValue(datos),
      nombreCuentaProvider.overrideWithValue(nombre),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'Secreto123');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(_k('inicio_configuracion'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('La hoja «¿Cerrar sesión?» con las fuentes reales, sin overflow y con capturas', () {
    for (final (nombreTamano, ancho, alto, escala) in _matriz) {
      for (final MapEntry(key: estado, value: abrir) in _estados.entries) {
        testWidgets('$estado a $nombreTamano', (tester) async {
          await _cargarFuentes(tester);
          _pantalla(tester, ancho, alto, escala);
          await abrir(tester);

          expect(tester.takeException(), isNull);
          // Las acciones del estado siguen alcanzables desplazando la hoja (a 2,0 la hoja ocupa
          // toda la pantalla).
          final cancelar = _k('configuracion_dialogo_cancelar');
          await tester.ensureVisible(cancelar);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(cancelar, findsOneWidget);
          await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, 2000));
          await _cuadro(tester);
          await _capturar(tester, '${estado}_$nombreTamano');
        });
      }
    }
  });

  group('Configuración (16A·01) con «Mapas offline», fuentes reales y capturas', () {
    for (final (nombreTamano, ancho, alto, escala) in _matriz) {
      testWidgets('fila «Mapas offline» y «Cerrar sesión» alcanzables a $nombreTamano', (
        tester,
      ) async {
        await _cargarFuentes(tester);
        _pantalla(tester, ancho, alto, escala);
        await _abrirConfiguracion(tester, datos: _ConteosEnOrden([0]));

        expect(tester.takeException(), isNull);
        await _capturar(tester, 'a01_arriba_$nombreTamano');
        await tester.ensureVisible(_k('configuracion_mapas_offline'));
        await tester.pump();
        expect(_k('configuracion_mapas_offline'), findsOneWidget);
        await tester.ensureVisible(_k('configuracion_cerrar_sesion'));
        await tester.pump();
        await _capturar(tester, 'a01_abajo_$nombreTamano');
        await tester.tap(_k('configuracion_cerrar_sesion'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_k('configuracion_dialogo_cierre'), findsOneWidget);
        expect(find.text('Todo sincronizado'), findsOneWidget);
      });
    }

    testWidgets('«Mapas offline» abre su pantalla y volver deja a Configuración como estaba', (
      tester,
    ) async {
      _pantalla(tester, 360, 640, 1);
      await _abrirConfiguracion(tester, datos: _ConteosEnOrden([0]));
      await tester.ensureVisible(_k('configuracion_mapas_offline'));
      await tester.tap(_k('configuracion_mapas_offline'));
      await tester.pumpAndSettle();
      expect(_k('configuracion_pagina'), findsNothing);

      await tester.tap(_k('mapas_offline_atras'));
      await tester.pumpAndSettle();
      expect(_k('configuracion_pagina'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Volver a abrir la hoja desde Configuración', () {
    testWidgets('cada apertura vuelve a contar: sin poder contar, cancelar y luego 2 pendientes', (
      tester,
    ) async {
      _pantalla(tester, 360, 640, 1);
      final datos = _ConteosEnOrden([null, 2]);
      await _abrirConfiguracion(tester, datos: datos);

      await tester.ensureVisible(_k('configuracion_cerrar_sesion'));
      await tester.tap(_k('configuracion_cerrar_sesion'));
      await tester.pumpAndSettle();
      expect(_k('configuracion_aviso_sin_revisar'), findsOneWidget);
      expect(find.text('Todo sincronizado'), findsNothing);

      await tester.tap(_k('configuracion_dialogo_cancelar'));
      await tester.pumpAndSettle();
      expect(_k('configuracion_dialogo_cierre'), findsNothing);
      // «Cerrar sesión» vuelve a estar habilitado (el conteo no quedó trabado en «revisando»).
      final fila = tester.widget<OutlinedButton>(_k('configuracion_cerrar_sesion'));
      expect(fila.onPressed, isNotNull);

      await tester.tap(_k('configuracion_cerrar_sesion'));
      await tester.pumpAndSettle();
      expect(_k('configuracion_aviso_sin_revisar'), findsNothing);
      expect(
        find.text(TextosCerrarSesion.advertenciaPendientes(2)),
        findsOneWidget,
        reason: 'la segunda apertura cuenta de nuevo y muestra los 2 pendientes',
      );
      expect(datos.llamadas, 2);
    });

    testWidgets('sin poder contar, «Reintentar» con éxito y «Cerrar sesión» cierra una sola vez', (
      tester,
    ) async {
      _pantalla(tester, 412, 915, 1);
      final datos = _ConteosEnOrden([null, 0]);
      final container = await _abrirConfiguracion(tester, datos: datos);

      await tester.ensureVisible(_k('configuracion_cerrar_sesion'));
      await tester.tap(_k('configuracion_cerrar_sesion'));
      await tester.pumpAndSettle();
      await tester.tap(_k('configuracion_reintentar_conteo'));
      await tester.pumpAndSettle();
      expect(find.text('Todo sincronizado'), findsOneWidget);
      expect(_k('configuracion_reintentar_conteo'), findsNothing);

      await tester.tap(_k('configuracion_dialogo_confirmar'));
      await tester.pumpAndSettle();
      expect(container.read(sesionProvider).value, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('Menores que ya anotó la revisión (con skip hasta que se arreglen)', () {
    // skip: QA #225 — sin poder contar, mientras cierra, la hoja sigue mostrando un «Reintentar»
    // apagado arriba de «Cerrando sesión» (`sinRevisar` no mira la fase): ruido que contradice 16A·04.
    testWidgets('cerrando sin haber podido contar no muestra el «Reintentar» del conteo', (
      tester,
    ) async {
      _pantalla(tester, 360, 640, 1);
      await _estados['a04_cerrando_sin_revisar']!(tester);

      expect(_k('configuracion_reintentar_conteo'), findsNothing);
      expect(find.text('Cerrando sesión'), findsOneWidget);
    }, skip: true);

    // skip: QA #225 — tras un «Reintentar» exitoso la hoja pasa a «Todo sincronizado» y el botón
    // enfocado desaparece, pero `_TodoSincronizado` no es región viva: TalkBack no anuncia el cambio.
    testWidgets('el paso a «Todo sincronizado» tras reintentar se anuncia (liveRegion)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      _pantalla(tester, 360, 640, 1);
      await _abrirHoja(tester, pendientes: null, contar: () async => 0);
      await tester.tap(_k('configuracion_reintentar_conteo'));
      await tester.pumpAndSettle();

      final nodo = tester.getSemantics(find.text('Todo sincronizado'));
      // ignore: deprecated_member_use
      expect(nodo.hasFlag(ui.SemanticsFlag.isLiveRegion), isTrue);
      semantica.dispose();
    }, skip: true);
  });
}
