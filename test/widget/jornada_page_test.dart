// Pantalla principal: iniciar jornada (HU-JOR-001, #71) y finalizarla (HU-JOR-002, #75). Un test
// por escenario de aceptación
// con el texto literal de la HU, los estados de la pantalla y la accesibilidad (tamaño de toque,
// etiquetas, contraste y texto al 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Miércoles 23/09/2026, 14:35:20 en la zona del dispositivo.
final _ahora = DateTime(2026, 9, 23, 14, 35, 20);

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

/// El almacenamiento en memoria de la app, con perillas para los estados de error y de carga.
final class _DataSource implements JornadaLocalDataSource {
  _DataSource({Iterable<JornadaModel> iniciales = const []})
    : _real = JornadaLocalDataSourceEnMemoria(iniciales: iniciales);

  final JornadaLocalDataSourceEnMemoria _real;

  /// Si no es `null`, la lectura espera a que se complete (estado "cargando").
  Completer<void>? demoraLectura;
  Object? errorAlLeer;

  /// Si no es `null`, la escritura espera a que se complete (estado "guardando").
  Completer<void>? demoraInsercion;
  Object? errorAlInsertar;

  /// Si no es `null`, el cierre espera a que se complete (estado "finalizando").
  Completer<void>? demoraFinalizar;
  Object? errorAlFinalizar;

  /// Cuántas lecturas más devuelven "sin jornada" aunque haya una abierta: simula otra jornada
  /// que se abrió mientras la pantalla mostraba "Sin jornada en curso".
  int lecturasSinVer = 0;

  List<JornadaModel> get jornadas => _real.jornadas;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    if (demoraLectura case final demora?) await demora.future;
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
  Future<void> finalizar(JornadaModel jornada) async {
    if (demoraFinalizar case final demora?) await demora.future;
    if (errorAlFinalizar case final error?) throw error;
    return _real.finalizar(jornada);
  }
}

/// Registra los pedidos de backup: el motor real (HU-SYNC-005) decide si hay Wi-Fi y batería.
final class _BackupFalso implements DisparadorBackup {
  final List<String> pedidos = [];

  @override
  Future<void> solicitar(String colportorId) async => pedidos.add(colportorId);
}

JornadaModel _jornadaAbiertaDesde(DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-previa',
    colportorId: _sesion.usuarioId,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: _sesion.usuarioId),
  ),
);

/// El `ProviderScope` va como argumento directo de `pumpWidget` (ver app_test.dart).
Future<void> _montar(
  WidgetTester tester,
  _DataSource dataSource, {
  ThemeData? tema,
  double escalaTexto = 1,
  DateTime Function()? reloj,
  _BackupFalso? backup,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      jornadaLocalDataSourceProvider.overrideWithValue(dataSource),
      disparadorBackupProvider.overrideWithValue(backup ?? _BackupFalso()),
      relojJornadaProvider.overrideWithValue(reloj ?? () => _ahora),
    ],
    child: MaterialApp(
      theme: tema ?? temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escalaTexto)),
        child: child!,
      ),
      home: JornadaPage(sesion: _sesion),
    ),
  ),
);

void _pantalla(WidgetTester tester, Size tamanio) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

FilledButton _botonIniciar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('jornada_iniciar')));

FilledButton _botonFinalizar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('jornada_finalizar')));

Future<void> _tocarFinalizar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
  await tester.tap(find.byKey(const Key('jornada_finalizar')));
  await tester.pumpAndSettle();
}

void main() {
  group('HU-JOR-001 — criterios de aceptación', () {
    testWidgets('Escenario: Inicio de jornada — Dado que no tengo jornada activa, Cuando presiono '
        '"Iniciar jornada", Entonces se crea jornada con `hora_inicio = now()` Y la UI cambia a '
        '"Jornada activa"', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('Sin jornada en curso'), findsOneWidget);
      expect(find.text('Ahora · 14:35'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      final creada = dataSource.jornadas.single;
      expect(creada.inicio, _ahora.toUtc());
      expect(creada.fin, isNull);
      expect(creada.colportorId, 'u-1');
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Desde las 14:35'), findsOneWidget);
      expect(find.text('Sin jornada en curso'), findsNothing);
    });

    testWidgets('Escenario: Bloqueo - jornada ya activa — Dado que tengo jornada activa, Cuando '
        'intento iniciar otra, Entonces la UI bloquea "Tenés una jornada en curso. Cerrala antes '
        'de iniciar otra."', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Desde las 13:15'), findsOneWidget);
      expect(find.text('1 h 20 min'), findsOneWidget);

      await tester.tap(find.byKey(const Key('jornada_iniciar')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_botonIniciar(tester).onPressed, isNull);
      expect(
        find.text('Tenés una jornada en curso. Cerrala antes de iniciar otra.'),
        findsOneWidget,
      );
      expect(dataSource.jornadas, hasLength(1));
    });

    testWidgets('Escenario: Bloqueo - jornada ya activa — si otra jornada se abrió mientras la '
        'pantalla mostraba "Sin jornada en curso", al presionar "Iniciar jornada" la UI bloquea '
        '"Tenés una jornada en curso. Cerrala antes de iniciar otra." y pasa a "Jornada activa"', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 14))])
        ..lecturasSinVer = 1;
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('Sin jornada en curso'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Desde las 14:00'), findsOneWidget);
      expect(
        find.text('Tenés una jornada en curso. Cerrala antes de iniciar otra.'),
        findsOneWidget,
      );
      expect(dataSource.jornadas, hasLength(1));
    });
  });

  group('Hora de inicio (hasta 30 minutos hacia atrás)', () {
    testWidgets('el selector solo ofrece de 30 minutos atrás a ahora, y la jornada empieza a la '
        'hora elegida', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('jornada_ajustar_hora')));
      await tester.pumpAndSettle();
      final selector = tester.widget<Slider>(find.byKey(const Key('jornada_selector_hora')));
      expect(selector.min, -30);
      expect(selector.max, 0);
      expect(selector.divisions, 30);

      selector.onChanged!(-10);
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);

      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('jornada_selector_hora')), findsNothing);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(dataSource.jornadas.single.inicio, DateTime(2026, 9, 23, 14, 25).toUtc());
      expect(find.text('Desde las 14:25'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
    });

    testWidgets('si la hora quedó fuera de rango al tocar, se rechaza con el rango explícito y no '
        'se ajusta en silencio', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      // La pantalla lee 14:35:59.999 y el caso de uso, un instante después, 14:36:00.5: la hora
      // elegida (14:05) quedó justo afuera del rango.
      final horas = [_ahora];
      DateTime reloj() => horas.length > 1 ? horas.removeAt(0) : horas.first;
      await _montar(tester, dataSource, reloj: reloj);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jornada_ajustar_hora')));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byKey(const Key('jornada_selector_hora'))).onChanged!(-30);
      await tester.pumpAndSettle();

      horas
        ..clear()
        ..addAll([DateTime(2026, 9, 23, 14, 35, 59, 999), DateTime(2026, 9, 23, 14, 36, 0, 500)]);
      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'La hora tiene que estar entre las 14:06 y las 14:36. Elegí otra hora y volvé a '
          'intentar.',
        ),
        findsOneWidget,
      );
      expect(dataSource.jornadas, isEmpty);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });
  });

  group('Estados', () {
    testWidgets('cargando: muestra el indicador mientras lee la jornada guardada', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource()..demoraLectura = Completer<void>();
      await _montar(tester, dataSource);
      await tester.pump();

      expect(find.text('Cargando tu jornada…'), findsOneWidget);
      expect(find.byKey(const Key('jornada_iniciar')), findsNothing);

      dataSource.demoraLectura!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('error al leer: dice qué pasó y qué hacer, y "Reintentar" vuelve a leer', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource()..errorAlLeer = StateError('db ilegible');
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No pudimos leer tu jornada. Tocá "Reintentar"; si sigue pasando, cerrá y volvé a '
          'abrir la app.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('jornada_iniciar')), findsNothing);

      dataSource.errorAlLeer = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('error al guardar: dice qué pasó y qué hacer, y deja volver a intentar', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource()..errorAlInsertar = StateError('disco lleno');
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No pudimos guardar el inicio de tu jornada. Probá de nuevo; si sigue pasando, cerrá y '
          'volvé a abrir la app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sin jornada en curso'), findsOneWidget);
      expect(_botonIniciar(tester).onPressed, isNotNull);

      dataSource.errorAlInsertar = null;
      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.byKey(const Key('jornada_error')), findsNothing);
    });

    testWidgets('mientras guarda, el botón se deshabilita (un segundo toque no inicia otra)', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource()..demoraInsercion = Completer<void>();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pump();
      expect(find.text('Iniciando…'), findsOneWidget);
      expect(_botonIniciar(tester).onPressed, isNull);
      await tester.tap(find.byKey(const Key('jornada_iniciar')), warnIfMissed: false);

      dataSource.demoraInsercion!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(dataSource.jornadas, hasLength(1));
    });

    testWidgets('muestra la fecha de hoy y el correo de la sesión', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      expect(find.text('MIÉRCOLES 23 DE SEPTIEMBRE'), findsOneWidget);
      expect(find.text('lucia.silva@correo.com'), findsOneWidget);
      expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    });
  });

  group('HU-JOR-002 — criterios de aceptación', () {
    testWidgets('Escenario: Fin de jornada con backup — Dado que tengo jornada activa con Wi-Fi '
        'disponible, Cuando finalizo, Entonces `hora_fin = now()` Y se dispara backup nocturno Y '
        'se muestra resumen', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      final backup = _BackupFalso();
      await _montar(tester, dataSource, backup: backup);
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Finalizar jornada'), findsOneWidget);

      await _tocarFinalizar(tester);

      final cerrada = dataSource.jornadas.single;
      expect(cerrada.fin, _ahora.toUtc());
      expect(cerrada.estaAbierta, isFalse);
      // El backup se pide al motor (HU-SYNC-005), que es el que mira Wi-Fi y batería.
      expect(backup.pedidos, ['u-1']);
      expect(find.text('Jornada finalizada'), findsOneWidget);
      expect(find.text('De las 13:15 a las 14:35'), findsOneWidget);
      expect(find.text('1 h 20 min'), findsOneWidget);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
      expect(_botonIniciar(tester).onPressed, isNotNull);
    });
  });

  group('Hora de fin (hasta 30 minutos hacia atrás, no antes del inicio)', () {
    testWidgets('el selector ofrece de 30 minutos atrás a ahora, y la jornada termina a la hora '
        'elegida', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('Ahora · 14:35'), findsOneWidget);

      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();
      final selector = tester.widget<Slider>(find.byKey(const Key('jornada_selector_hora_fin')));
      expect(selector.min, -30);
      expect(selector.max, 0);
      expect(find.text('Podés marcar el fin hasta 30 minutos hacia atrás.'), findsOneWidget);

      selector.onChanged!(-10);
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);

      await _tocarFinalizar(tester);

      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 14, 25).toUtc());
      expect(find.text('De las 13:15 a las 14:25'), findsOneWidget);
      expect(find.text('1 h 10 min'), findsOneWidget);
    });

    testWidgets('si la jornada empezó hace menos de 30 minutos, el selector no pasa del inicio', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 14, 20))]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();

      expect(tester.widget<Slider>(find.byKey(const Key('jornada_selector_hora_fin'))).min, -15);
      expect(
        find.text(
          'Podés marcar el fin hasta 15 minutos hacia atrás: tu jornada empezó a las 14:20.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Estados al finalizar', () {
    testWidgets('mientras guarda, el botón se deshabilita (un segundo toque no vuelve a cerrar)', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      )..demoraFinalizar = Completer<void>();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
      await tester.tap(find.byKey(const Key('jornada_finalizar')));
      await tester.pump();
      expect(find.text('Finalizando…'), findsOneWidget);
      expect(_botonFinalizar(tester).onPressed, isNull);

      dataSource.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Jornada finalizada'), findsOneWidget);
      expect(dataSource.jornadas.single.fin, _ahora.toUtc());
    });

    testWidgets('error al guardar: dice qué pasó y qué hacer, la jornada sigue abierta y deja '
        'volver a intentar', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      )..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _tocarFinalizar(tester);

      expect(
        find.text(
          'No pudimos guardar el fin de tu jornada, que sigue abierta. Probá de nuevo; si sigue '
          'pasando, cerrá y volvé a abrir la app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
      expect(_botonFinalizar(tester).onPressed, isNotNull);

      dataSource.errorAlFinalizar = null;
      await _tocarFinalizar(tester);
      expect(find.text('Jornada finalizada'), findsOneWidget);
      expect(find.byKey(const Key('jornada_error_fin')), findsNothing);
    });

    testWidgets('después de finalizar se puede iniciar otra jornada, y el resumen se va', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      await _tocarFinalizar(tester);

      await tester.ensureVisible(find.byKey(const Key('jornada_iniciar')));
      await tester.tap(find.byKey(const Key('jornada_iniciar')));
      await tester.pumpAndSettle();

      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Jornada finalizada'), findsNothing);
      expect(dataSource.jornadas, hasLength(2));
    });
  });

  group('Accesibilidad', () {
    final temas = {'claro': temaClaro, 'oscuro': temaOscuro};
    const estados = ['sin jornada', 'jornada activa', 'jornada finalizada'];

    /// Deja la pantalla en [estado], con el selector de hora abierto cuando lo hay.
    Future<void> prepararEstado(WidgetTester tester, String estado) async {
      switch (estado) {
        case 'sin jornada':
          await tester.ensureVisible(find.byKey(const Key('jornada_ajustar_hora')));
          await tester.tap(find.byKey(const Key('jornada_ajustar_hora')));
        case 'jornada activa':
          await tester.ensureVisible(find.byKey(const Key('jornada_ajustar_hora_fin')));
          await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
        case 'jornada finalizada':
          await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
          await tester.tap(find.byKey(const Key('jornada_finalizar')));
      }
      await tester.pumpAndSettle();
    }

    _DataSource dataSourcePara(String estado) => _DataSource(
      iniciales: [if (estado != 'sin jornada') _jornadaAbiertaDesde(DateTime(2026, 9, 23, 13))],
    );

    for (final MapEntry(key: nombreTema, value: tema) in temas.entries) {
      for (final estado in estados) {
        testWidgets('tema $nombreTema, $estado: tamaño de toque, etiquetas y contraste', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          _pantalla(tester, const Size(390, 844));
          await _montar(tester, dataSourcePara(estado), tema: tema());
          await tester.pumpAndSettle();
          await prepararEstado(tester, estado);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });

        testWidgets('tema $nombreTema, $estado: sin overflow con el texto al 200 % en 360x740', (
          tester,
        ) async {
          _pantalla(tester, const Size(360, 740));
          await _montar(tester, dataSourcePara(estado), tema: tema(), escalaTexto: 2);
          await tester.pumpAndSettle();
          await prepararEstado(tester, estado);

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
