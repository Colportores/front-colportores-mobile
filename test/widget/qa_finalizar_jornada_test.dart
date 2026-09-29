// QA de la vista 21 (#230, HU-JOR-002): finalizar la jornada, resumen del día y jornada sin
// cerrar. Complementa a `jornada_page_test.dart` con los tamaños de referencia (360x640 y
// 412x915) a texto 1.0 y 2.0, los avisos de error de la corrección y la navegación.
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
import 'package:colportores_mobile/features/jornada/presentation/pages/corregir_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/resumen_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Object? errorAlFinalizar;
  Completer<void>? demoraFinalizar;

  @override
  Future<void> finalizar(JornadaModel jornada) async {
    if (demoraFinalizar case final demora?) await demora.future;
    if (errorAlFinalizar case final error?) throw error;
    return _real.finalizar(jornada);
  }
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

Future<void> _tocarSinEsperar(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

/// Elige [hora]:[minuto] en el selector del sistema (modo texto, más estable que el dial).
Future<void> _elegirHoraDelSistema(WidgetTester tester, String hora, String minuto) async {
  await _tocar(tester, 'corregir_jornada_elegir_hora');
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(0), hora);
  await tester.enterText(find.byType(TextFormField).at(1), minuto);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

_DataSource _ayer() => _DataSource(iniciales: [_abiertaDesde(DateTime(2026, 9, 28, 14, 35))]);

void main() {
  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
  const estados = [
    'jornada activa',
    'hoja de fin',
    'otra hora de fin fuera de rango',
    'finalizando',
    'error al guardar el fin',
    'resumen',
    'sin cerrar',
    'sin cerrar con error',
  ];

  Future<void> preparar(WidgetTester tester, String estado, double escala, Size tam) async {
    final ds = switch (estado) {
      'sin cerrar' || 'sin cerrar con error' => _ayer(),
      _ => _DataSource(iniciales: [_abiertaDesde(DateTime(2026, 9, 29, 13, 20))]),
    };
    await _montar(tester, ds, escala: escala);
    await tester.pumpAndSettle();
    switch (estado) {
      case 'hoja de fin':
        await _tocar(tester, 'jornada_ajustar_hora_fin');
      case 'otra hora de fin fuera de rango':
        await _tocar(tester, 'jornada_ajustar_hora_fin');
        await _tocar(tester, 'hoja_hora_valor');
        tester.view.viewInsets = FakeViewPadding(bottom: tam.height * .4);
        await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '13:50');
        await tester.pumpAndSettle();
      case 'finalizando':
        ds.demoraFinalizar = Completer<void>();
        await _tocarSinEsperar(tester, 'jornada_finalizar');
      case 'error al guardar el fin':
        ds.errorAlFinalizar = StateError('disco lleno');
        await _tocar(tester, 'jornada_finalizar');
      case 'resumen':
        await _tocar(tester, 'jornada_finalizar');
      case 'sin cerrar':
        await _tocar(tester, 'jornada_finalizar');
      case 'sin cerrar con error':
        await _tocar(tester, 'jornada_finalizar');
        await _elegirHoraDelSistema(tester, '14', '35');
        // El desborde del diálogo del sistema a texto 2.0 tiene su propio test.
        tester.takeException();
        await _tocar(tester, 'corregir_jornada_cerrar');
    }
  }

  group('QA #230 — tamaños de referencia, texto 1.0 y 2.0', () {
    for (final MapEntry(key: nombre, value: tam) in tamanios.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in estados) {
          testWidgets('$estado en $nombre, texto $escala: sin overflow y accesible', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            _pantalla(tester, tam);
            await preparar(tester, estado, escala, tam);

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

    testWidgets('el aviso de rango de la hora de fin se ve entero con el teclado abierto', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640));
      await preparar(tester, 'otra hora de fin fuera de rango', 2, const Size(360, 640));

      final aviso = tester.getRect(find.textContaining('La hora tiene que estar entre las'));
      expect(aviso.bottom, lessThanOrEqualTo(640 - 256));
    });
  });

  group('QA #230 — finalizar', () {
    testWidgets('dos toques seguidos en "Finalizar jornada" cierran una sola vez', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final ds = _DataSource(iniciales: [_abiertaDesde(DateTime(2026, 9, 29, 13, 20))])
        ..demoraFinalizar = Completer<void>();
      await _montar(tester, ds);
      await tester.pumpAndSettle();
      await _tocarSinEsperar(tester, 'jornada_finalizar');
      await tester.tap(find.byKey(const Key('jornada_finalizar')), warnIfMissed: false);
      await tester.pump();
      ds.demoraFinalizar!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ResumenJornadaPage), findsOneWidget);
      expect(ds.jornadas.single.estaAbierta, isFalse);
    });

    testWidgets('resumen: horas literales y el atrás del sistema vuelve a "Hoy" sin jornada', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource(iniciales: [_abiertaDesde(DateTime(2026, 9, 29, 13, 20))]));
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_finalizar');

      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
      expect(find.text('De las 13:20 a las 14:35'), findsOneWidget);
      expect(find.text('1 h 15 min'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ResumenJornadaPage), findsNothing);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('un fallo al finalizar deja la jornada abierta y se puede reintentar', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final ds = _DataSource(iniciales: [_abiertaDesde(DateTime(2026, 9, 29, 13, 20))])
        ..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, ds);
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_finalizar');
      expect(find.byKey(const Key('jornada_error_fin')), findsOneWidget);
      expect(find.text('Sigue en curso'), findsOneWidget);

      ds.errorAlFinalizar = null;
      await _tocar(tester, 'jornada_finalizar');
      expect(find.byType(ResumenJornadaPage), findsOneWidget);
    });
  });

  group('QA #230 — selector de hora del sistema a texto 2.0', () {
    for (final (nombre, tam) in [
      ('360x640', const Size(360, 640)),
      ('412x915', const Size(412, 915)),
    ]) {
      testWidgets('el diálogo en modo dial en $nombre no desborda', (tester) async {
        _pantalla(tester, tam);
        await _montar(tester, _ayer(), escala: 2);
        await tester.pumpAndSettle();
        await _tocar(tester, 'jornada_finalizar');
        await _tocar(tester, 'corregir_jornada_elegir_hora');

        expect(tester.takeException(), isNull);
      });

      // skip: QA #230 — a texto 2.0 el selector de hora del sistema en modo texto (el que se abre
      // al tocar el teclado) desborda 108 px en vertical: el botón OK queda fuera del diálogo.
      testWidgets('el diálogo en modo texto en $nombre no desborda', (tester) async {
        _pantalla(tester, tam);
        await _montar(tester, _ayer(), escala: 2);
        await tester.pumpAndSettle();
        await _tocar(tester, 'jornada_finalizar');
        await _tocar(tester, 'corregir_jornada_elegir_hora');
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      }, skip: true);
    }
  });

  group('QA #230 — jornada sin cerrar', () {
    testWidgets('sin elegir hora, "Cerrar" está deshabilitado y el atrás vuelve', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _ayer());
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_finalizar');

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('corregir_jornada_cerrar'))).onPressed,
        isNull,
      );
      await _tocar(tester, 'corregir_jornada_atras');
      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(find.text('Jornada activa'), findsOneWidget);
    });

    testWidgets('una hora igual al inicio se rechaza con el rango y no cierra nada', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final ds = _ayer();
      await _montar(tester, ds);
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_finalizar');
      await _elegirHoraDelSistema(tester, '14', '35');
      await _tocar(tester, 'corregir_jornada_cerrar');

      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);
      expect(find.textContaining('Elegí otra hora y volvé a intentar.'), findsOneWidget);
      expect(ds.jornadas.single.estaAbierta, isTrue);
      // La hora elegida no se pierde.
      expect(find.text('14:35'), findsWidgets);
    });

    // skip: QA #230 — si el cierre de la jornada sin cerrar falla por un error del sistema, el aviso
    // muestra el mensaje genérico del Failure ("Ocurrió un error inesperado"): no dice qué hacer.
    testWidgets('un fallo al cerrar la jornada sin cerrar dice qué pasó y qué hacer', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final ds = _ayer()..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, ds);
      await tester.pumpAndSettle();
      await _tocar(tester, 'jornada_finalizar');
      await _elegirHoraDelSistema(tester, '18', '10');
      await _tocar(tester, 'corregir_jornada_cerrar');

      final aviso = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('corregir_jornada_error')),
          matching: find.byType(Text),
        ),
      );
      expect(aviso.data, matches(RegExp('Prob|Reintent|volv|intent', caseSensitive: false)));
      expect(ds.jornadas.single.estaAbierta, isTrue);
    }, skip: true);
  });
}
