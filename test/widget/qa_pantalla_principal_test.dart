// QA de la vista 20 (#229, HU-JOR-001): pantalla principal con la barra inferior e "Iniciar
// jornada". Complementa a `jornada_page_test.dart` con lo que ese archivo no cubre: los dos
// tamaños de referencia (360x640 y 412x915) a texto 1.0 y 2.0 con el teclado abierto, las entradas
// raras del campo "Otra hora", el doble toque, la navegación hacia atrás y la privacidad.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;

final _ahora = DateTime(2026, 9, 29, 14, 35, 20);

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _DataSource implements JornadaLocalDataSource {
  _DataSource({Iterable<JornadaModel> iniciales = const []})
    : _real = JornadaLocalDataSourceEnMemoria(iniciales: iniciales);

  final JornadaLocalDataSourceEnMemoria _real;
  Completer<void>? demoraInsercion;
  Object? errorAlInsertar;
  Object? errorAlLeer;
  int lecturasSinVer = 0;

  List<JornadaModel> get jornadas => _real.jornadas;

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) =>
      _real.siguienteA(colportorId: colportorId, inicio: inicio);

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    if (errorAlLeer case final error?) throw error;
    if (lecturasSinVer > 0) {
      lecturasSinVer--;
      return null;
    }
    return _real.obtenerActiva(colportorId);
  }

  @override
  Future<void> insertar(JornadaModel jornada) async {
    if (demoraInsercion case final demora?) await demora.future;
    if (errorAlInsertar case final error?) throw error;
    return _real.insertar(jornada);
  }

  @override
  Future<void> finalizar(JornadaModel jornada) => _real.finalizar(jornada);
}

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

JornadaModel _abiertaDesde(DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-previa',
    colportorId: _sesion.usuarioId,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: _sesion.usuarioId),
  ),
);

Future<void> _montar(WidgetTester tester, _DataSource dataSource, {double escala = 1}) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          jornadaLocalDataSourceProvider.overrideWithValue(dataSource),
          disparadorBackupProvider.overrideWithValue(_BackupFalso()),
          relojJornadaProvider.overrideWithValue(() => _ahora),
          ...overridesPestanaMapa(),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: InicioPage(sesion: _sesion),
        ),
      ),
    );

void _pantalla(WidgetTester tester, Size tamanio, {double teclado = 0}) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: teclado);
  addTearDown(tester.view.reset);
}

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Abre "Otra hora"; con [teclado] > 0 simula el teclado, que aparece recién al enfocar el campo.
Future<void> _abrirOtraHora(WidgetTester tester, {double teclado = 0}) async {
  await _tocar(tester, 'jornada_ajustar_hora');
  await _tocar(tester, 'hoja_hora_valor');
  if (teclado > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: teclado);
    await tester.pumpAndSettle();
  }
}

bool _habilitado(WidgetTester tester, String key) =>
    tester.widget<FilledButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
  const estados = [
    'sin jornada',
    'hoja de ajuste',
    'otra hora fuera de rango',
    'error al guardar',
    'error de carga',
    'ya en curso',
    'jornada activa',
  ];

  Future<void> preparar(WidgetTester tester, String estado) async {
    switch (estado) {
      case 'hoja de ajuste':
        await _tocar(tester, 'jornada_ajustar_hora');
      case 'otra hora fuera de rango':
        await _abrirOtraHora(tester, teclado: tester.view.physicalSize.height * .4);
        await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '13:50');
        await tester.pumpAndSettle();
      case 'error al guardar' || 'ya en curso':
        await _tocar(tester, 'jornada_iniciar');
    }
  }

  _DataSource dataSourcePara(String estado) => switch (estado) {
    'jornada activa' => _DataSource(iniciales: [_abiertaDesde(DateTime(2026, 9, 29, 13))]),
    'ya en curso' => _DataSource(
      iniciales: [_abiertaDesde(DateTime(2026, 9, 29, 8, 10))],
    )..lecturasSinVer = 1,
    'error de carga' => _DataSource()..errorAlLeer = StateError('db ilegible'),
    'error al guardar' => _DataSource()..errorAlInsertar = StateError('disco lleno'),
    _ => _DataSource(),
  };

  group('QA #229 — tamaños de referencia, texto 1.0 y 2.0', () {
    for (final MapEntry(key: nombre, value: tamanio) in tamanios.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in estados) {
          testWidgets('$estado en $nombre, texto $escala: sin overflow y accesible', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            _pantalla(tester, tamanio);
            await _montar(tester, dataSourcePara(estado), escala: escala);
            await tester.pumpAndSettle();
            await preparar(tester, estado);

            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }

    testWidgets('con el teclado abierto a texto 2.0 en 360x640, "Usar esta hora" se alcanza', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640));
      await _montar(tester, _DataSource(), escala: 2);
      await tester.pumpAndSettle();
      await _abrirOtraHora(tester, teclado: 256);
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '14:20');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_otra')), findsNothing);
      expect(find.textContaining('14:20'), findsWidgets);
    });

    testWidgets('con el teclado abierto a texto 2.0 en 360x640, el aviso de rango se ve entero '
        'sin scrollear la hoja', (tester) async {
      _pantalla(tester, const Size(360, 640));
      await _montar(tester, _DataSource(), escala: 2);
      await tester.pumpAndSettle();
      await _abrirOtraHora(tester, teclado: 256);
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '13:50');
      await tester.pumpAndSettle();

      final aviso = tester.getRect(
        find.text('La hora tiene que estar entre las 14:05 y las 14:35.'),
      );
      // El teclado ocupa los últimos 256 dp: el aviso tiene que terminar arriba de él.
      expect(aviso.bottom, lessThanOrEqualTo(640 - 256));
    });
  });

  group('QA #229 — entradas del campo "Otra hora"', () {
    Future<void> escribir(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), texto);
      await tester.pumpAndSettle();
    }

    for (final entrada in [
      '   ',
      '😀😀',
      'abc',
      '14:2😀',
      'catorce',
      '1234567890123456789012345678901234567890',
    ]) {
      testWidgets('"$entrada": no habilita "Usar esta hora"', (tester) async {
        _pantalla(tester, const Size(390, 844));
        await _montar(tester, _DataSource());
        await tester.pumpAndSettle();
        await _abrirOtraHora(tester);
        await escribir(tester, entrada);

        expect(_habilitado(tester, 'hoja_hora_usar_escrita'), isFalse);
        final campo = tester.widget<TextField>(find.byKey(const Key('hoja_hora_campo')));
        expect(campo.controller!.text.length, lessThanOrEqualTo(5));
        expect(campo.controller!.text, matches(RegExp(r'^[0-9:]*$')));
        expect(tester.takeException(), isNull);
      });
    }

    for (final entrada in ['24:00', '12:60', '99:99', '::::', '1:2', '14::2']) {
      testWidgets('"$entrada": dice qué pasó y qué hacer, y no deja usarla', (tester) async {
        _pantalla(tester, const Size(390, 844));
        await _montar(tester, _DataSource());
        await tester.pumpAndSettle();
        await _abrirOtraHora(tester);
        await escribir(tester, entrada);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(_habilitado(tester, 'hoja_hora_usar_escrita'), isFalse);
        expect(
          find.textContaining('No entendimos esa hora. Escribila en formato 24 h'),
          findsOneWidget,
        );
      });
    }

    testWidgets('los límites del rango: 14:05 se usa y 14:04 se rechaza con el rango literal', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _abrirOtraHora(tester);

      await escribir(tester, '14:04');
      expect(find.text('La hora tiene que estar entre las 14:05 y las 14:35.'), findsOneWidget);
      expect(_habilitado(tester, 'hoja_hora_usar_escrita'), isFalse);

      await escribir(tester, '14:05');
      expect(_habilitado(tester, 'hoja_hora_usar_escrita'), isTrue);
      await escribir(tester, '14:35');
      expect(_habilitado(tester, 'hoja_hora_usar_escrita'), isTrue);
      await escribir(tester, '14:36');
      expect(find.text('La hora tiene que estar entre las 14:05 y las 14:35.'), findsOneWidget);
    });

    testWidgets('"Volver" y volver a entrar no pierde la hora que se estaba ajustando', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_ajustar_hora');
      await _tocar(tester, 'hoja_hora_menos');
      await _tocar(tester, 'hoja_hora_menos');
      await _tocar(tester, 'hoja_hora_valor');
      await _tocar(tester, 'hoja_hora_volver');

      expect(find.byKey(const Key('hoja_hora_usar')), findsOneWidget);
      expect(find.text('Usar 14:25'), findsOneWidget);
    });
  });

  group('QA #229 — iniciar y navegación', () {
    testWidgets('dos toques seguidos en "Iniciar jornada" crean una sola jornada', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource()..demoraInsercion = Completer<void>();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('jornada_iniciar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('jornada_iniciar')), warnIfMissed: false);
      await tester.pump();
      dataSource.demoraInsercion!.complete();
      await tester.pumpAndSettle();

      expect(dataSource.jornadas, hasLength(1));
      expect(find.text('Jornada activa'), findsOneWidget);
    });

    testWidgets('después de un error al guardar, la hora elegida sigue ahí', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource()..errorAlInsertar = StateError('disco lleno');
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_ajustar_hora');
      await _tocar(tester, 'hoja_hora_menos');
      await _tocar(tester, 'hoja_hora_usar');
      await _tocar(tester, 'jornada_iniciar');

      expect(find.byKey(const Key('jornada_error')), findsOneWidget);
      expect(find.textContaining('14:30'), findsWidgets);
      expect(_habilitado(tester, 'jornada_iniciar'), isTrue);
    });

    testWidgets('el botón atrás del sistema cierra la hoja sin cambiar la hora', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_ajustar_hora');
      await _tocar(tester, 'hoja_hora_menos');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(find.text('Ahora · 14:35'), findsOneWidget);
    });

    testWidgets('Configuración: se abre con el engranaje y atrás vuelve a la pantalla principal', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _tocar(tester, 'inicio_configuracion');
      expect(find.byKey(const Key('inicio_principal')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('el atrás del sistema desde Mapa, Lista, Agenda o Ventas vuelve a Hoy', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      for (final pestana in ['mapa', 'lista', 'agenda', 'ventas']) {
        await _tocar(tester, 'inicio_pestana_$pestana');
        expect(find.byKey(Key('pestana_$pestana')), findsOneWidget);
        expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, isNot(0));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
        expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      }
    });

    testWidgets('el atrás del sistema desde Hoy cierra la app (no queda en la pantalla)', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      final llamadas = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        llamadas.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(llamadas, contains('SystemNavigator.pop'), reason: 'en Hoy el atrás sale de la app');
    });

    testWidgets('las pestañas sin contenido muestran el ícono y «Esta sección llega pronto.»', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      // «Mapa» (HU-UBI-003) y «Lista» (HU-UBI-002) ya tienen contenido: lo cubren sus propios tests.
      for (final pestana
          in PestanaInicio.values
              .skip(1)
              .where((p) => p != PestanaInicio.mapa && p != PestanaInicio.lista)) {
        await _tocar(tester, 'inicio_pestana_${pestana.name}');
        final seccion = find.byKey(Key('pestana_${pestana.name}'));
        expect(
          find.descendant(of: seccion, matching: find.text('Esta sección llega pronto.')),
          findsOneWidget,
        );
        expect(find.descendant(of: seccion, matching: find.byIcon(pestana.icono)), findsOneWidget);
      }
    });

    testWidgets('la pestaña elegida se anuncia como seleccionada', (tester) async {
      final semantica = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inicio_pestana_agenda')));
      await tester.pumpAndSettle();

      final nodo = tester.getSemantics(find.byKey(const Key('inicio_pestana_agenda')));
      // ignore: deprecated_member_use
      expect(nodo.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(nodo.label, contains('Agenda'));
      semantica.dispose();
    });
  });

  group('QA #229 — privacidad', () {
    test('la sesión y la jornada no muestran el email ni el token en toString()', () {
      final texto = '$_sesion ${_abiertaDesde(_ahora).toEntity()}';
      expect(texto, isNot(contains('lucia.silva@correo.com')));
      expect(texto, isNot(contains('token-secreto')));
    });
  });
}
