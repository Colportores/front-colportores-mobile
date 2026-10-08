// Pantalla principal: iniciar jornada (HU-JOR-001, #71) y finalizarla (HU-JOR-002, #75). Un test
// por escenario de aceptación
// con el texto literal de la HU, los estados de la pantalla y la accesibilidad (tamaño de toque,
// etiquetas, contraste y texto al 200 %).
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
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;

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
      ...overridesPestanaMapa(),
    ],
    child: MaterialApp(
      theme: tema ?? temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(escalaTexto),
          // Sin AM/PM: `CorregirJornadaPage` (#109) abre el selector de hora del sistema, y en
          // 24 h el orden de campos es siempre hora-minuto sin control de período.
          alwaysUse24HourFormat: true,
        ),
        child: child!,
      ),
      home: InicioPage(sesion: _sesion),
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

/// El `onPressed` del botón con esa key (o del botón que ella envuelve): `null` = deshabilitado.
VoidCallback? _boton(WidgetTester tester, String key) {
  final buscado = find.byKey(Key(key));
  if (tester.widget(buscado) case final ButtonStyleButton boton) return boton.onPressed;
  return tester
      .widget<ButtonStyleButton>(
        find.descendant(
          of: buscado,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      )
      .onPressed;
}

Future<void> _abrirHoja(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('jornada_ajustar_hora')));
  await tester.tap(find.byKey(const Key('jornada_ajustar_hora')));
  await tester.pumpAndSettle();
}

Future<void> _tocarVeces(WidgetTester tester, String key, int veces) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }
}

/// "Volver al inicio" del resumen a pantalla completa.
Future<void> _volverAlInicio(WidgetTester tester) async {
  await tester.tap(find.text('Volver al inicio'));
  await tester.pumpAndSettle();
}

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

    testWidgets('Escenario: Bloqueo - jornada ya activa — Dado que tengo jornada activa, la '
        'pantalla es "Jornada activa" y no ofrece iniciar otra', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Desde las 13:15'), findsOneWidget);
      expect(find.text('1 h 20 min'), findsOneWidget);
      // Vista 20 A08: «Iniciar jornada» deshabilitado con el bloqueo de la HU.
      expect(
        find.text('Tenés una jornada en curso. Cerrala antes de iniciar otra.'),
        findsOneWidget,
      );
      expect(find.text('Iniciar jornada'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('jornada_iniciar'))).onPressed,
        isNull,
      );
      expect(dataSource.jornadas, hasLength(1));
    });

    testWidgets('Escenario: Bloqueo - jornada ya activa — Dado que tengo jornada activa (abierta '
        'mientras la pantalla mostraba "Sin jornada en curso"), Cuando intento iniciar otra, '
        'Entonces la UI bloquea "Tenés una jornada en curso. Cerrala antes de iniciar otra."', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 8, 10))],
      )..lecturasSinVer = 1;
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('Sin jornada en curso'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(
        find.text('Tenés una jornada en curso. Cerrala antes de iniciar otra.'),
        findsOneWidget,
      );
      expect(find.text('Ver jornada en curso · desde 08:10'), findsOneWidget);
      expect(_botonIniciar(tester).onPressed, isNull);
      expect(find.text('Jornada activa'), findsNothing);
      expect(dataSource.jornadas, hasLength(1));

      await tester.tap(find.text('Ver jornada en curso · desde 08:10'));
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Desde las 08:10'), findsOneWidget);
      // Vista 20 A08: con la jornada activa, «Iniciar jornada» sigue deshabilitado con el bloqueo.
      expect(
        find.text('Tenés una jornada en curso. Cerrala antes de iniciar otra.'),
        findsOneWidget,
      );
    });
  });

  group('Hora de inicio (hasta 30 minutos hacia atrás)', () {
    testWidgets('la hoja ofrece de a 5 minutos entre 30 minutos atrás y ahora, y la jornada '
        'empieza a la hora elegida', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      expect(find.text('¿A qué hora empezaste?'), findsOneWidget);
      expect(find.text('Entre las 14:05 y las 14:35.'), findsOneWidget);
      expect(find.text('Ahora'), findsWidgets);
      expect(_boton(tester, 'hoja_hora_mas'), isNull, reason: '+5 no pasa de ahora');

      await _tocarVeces(tester, 'hoja_hora_menos', 2);
      expect(find.text('14:25'), findsOneWidget);
      expect(find.text('Hace 10 min'), findsOneWidget);
      expect(find.text('Usar 14:25'), findsOneWidget);

      await tester.tap(find.text('Usar 14:25'));
      await tester.pumpAndSettle();
      expect(find.text('¿A qué hora empezaste?'), findsNothing);
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(dataSource.jornadas.single.inicio, DateTime(2026, 9, 23, 14, 25).toUtc());
      expect(find.text('Desde las 14:25'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
    });

    testWidgets('−5 se detiene a los 30 minutos y +5 vuelve hasta ahora', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      await _tocarVeces(tester, 'hoja_hora_menos', 6);
      expect(find.text('14:05'), findsOneWidget);
      expect(find.text('Hace 30 min'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_menos'), isNull);

      await _tocarVeces(tester, 'hoja_hora_mas', 1);
      expect(find.text('14:10'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_menos'), isNotNull);
    });

    testWidgets('Cancelar deja la hora como estaba', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      await _tocarVeces(tester, 'hoja_hora_menos', 3);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Ahora · 14:35'), findsOneWidget);
    });

    testWidgets('"Otra hora": una hora dentro del rango se usa tal cual', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      expect(find.text('Otra hora'), findsOneWidget);
      expect(find.text('Escribila en formato 24 h.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '14:20');
      await tester.pumpAndSettle();
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNotNull);
      await tester.tap(find.text('Usar esta hora'));
      await tester.pumpAndSettle();
      expect(find.text('14:20 · hace 15 min'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();
      expect(dataSource.jornadas.single.inicio, DateTime(2026, 9, 23, 14, 20).toUtc());
    });

    testWidgets('"Otra hora": fuera de rango se rechaza con el rango explícito, sin ajustar en '
        'silencio', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '13:50');
      await tester.pumpAndSettle();

      expect(find.text('La hora tiene que estar entre las 14:05 y las 14:35.'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);

      // Una hora futura tampoco vale.
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '14:40');
      await tester.pumpAndSettle();
      expect(find.text('La hora tiene que estar entre las 14:05 y las 14:35.'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);

      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('¿A qué hora empezaste?'), findsOneWidget);
      expect(find.text('Ahora'), findsWidgets);
    });

    testWidgets('"Otra hora": lo que no es una hora de 24 h dice qué pasó y qué hacer', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '99:99');
      await tester.pumpAndSettle();

      expect(
        find.text('No entendimos esa hora. Escribila en formato 24 h, por ejemplo 14:20.'),
        findsOneWidget,
      );
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);

      // Mientras todavía está escribiendo no se le marca error.
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '14');
      await tester.pumpAndSettle();
      expect(find.textContaining('No entendimos'), findsNothing);
    });

    testWidgets('"Otra hora": una hora a medio escribir no se acepta ni marca error hasta '
        'confirmar; "143" no es 01:43 y "1430" sí', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _abrirHoja(tester);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      final campo = find.byKey(const Key('hoja_hora_campo'));

      await tester.enterText(campo, '14:3');
      await tester.pumpAndSettle();
      expect(find.textContaining('No entendimos'), findsNothing);
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);

      // Al confirmar con "listo" del teclado, ahí sí se le dice qué falta.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('No entendimos esa hora. Escribila en formato 24 h, por ejemplo 14:20.'),
        findsOneWidget,
      );

      await tester.enterText(campo, '143');
      await tester.pumpAndSettle();
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);

      await tester.enterText(campo, '1430');
      await tester.pumpAndSettle();
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNotNull);
      expect(find.textContaining('No entendimos'), findsNothing);
    });

    testWidgets('"Otra hora": con el campo vacío dice qué escribir', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _abrirHoja(tester);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '');
      await tester.pumpAndSettle();

      expect(find.text('Escribí la hora, por ejemplo 14:20.'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);
    });

    testWidgets('un doble toque en "Usar" no cierra también la pantalla principal', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _abrirHoja(tester);

      await tester.tap(find.text('Usar 14:35'));
      await tester.tap(find.text('Usar 14:35'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('si cambia el minuto con la hoja abierta, se guarda la hora que el colportor vio '
        'y confirmó, no una corrida', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      var reloj = _ahora;
      await _montar(tester, dataSource, reloj: () => reloj);
      await tester.pumpAndSettle();
      await _abrirHoja(tester);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '14:20');
      await tester.pumpAndSettle();

      // Pasa el minuto con la hoja abierta.
      reloj = DateTime(2026, 9, 23, 14, 36, 5);
      await tester.tap(find.text('Usar esta hora'));
      await tester.pumpAndSettle();
      expect(find.text('14:20 · hace 16 min'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();
      expect(dataSource.jornadas.single.inicio, DateTime(2026, 9, 23, 14, 20).toUtc());
    });

    testWidgets('"Otra hora": cruzando la medianoche, 23:50 es 20 minutos antes de las 00:10', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      await _montar(tester, dataSource, reloj: () => DateTime(2026, 9, 24, 0, 10, 20));
      await tester.pumpAndSettle();

      await _abrirHoja(tester);
      expect(find.text('Entre las 23:40 y las 00:10.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '23:50');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar esta hora'));
      await tester.pumpAndSettle();
      expect(find.text('23:50 · hace 20 min'), findsOneWidget);

      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();
      expect(dataSource.jornadas.single.inicio, DateTime(2026, 9, 23, 23, 50).toUtc());
    });

    testWidgets('si la hora quedó fuera de rango al tocar, se rechaza con el rango explícito y no '
        'se ajusta en silencio', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      // La pantalla muestra 14:05 (30 min antes de las 14:35:20) y el caso de uso lee la hora al
      // tocar, 14:36:00.5: la hora mostrada (14:05) quedó justo afuera del rango.
      var reloj = _ahora;
      await _montar(tester, dataSource, reloj: () => reloj);
      await tester.pumpAndSettle();
      await _abrirHoja(tester);
      await _tocarVeces(tester, 'hoja_hora_menos', 6);
      await tester.tap(find.text('Usar 14:05'));
      await tester.pumpAndSettle();
      expect(find.text('14:05 · hace 30 min'), findsOneWidget);

      reloj = DateTime(2026, 9, 23, 14, 36, 0, 500);
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

    testWidgets('guarda la hora que mostraba la etiqueta, aunque el minuto cambie antes del toque '
        '(#102)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource();
      var reloj = _ahora;
      await _montar(tester, dataSource, reloj: () => reloj);
      await tester.pumpAndSettle();
      await _abrirHoja(tester);
      await _tocarVeces(tester, 'hoja_hora_menos', 2);
      await tester.tap(find.text('Usar 14:25'));
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);

      // Pasa el minuto sin que la pantalla se vuelva a dibujar, y recién ahí el toque.
      reloj = DateTime(2026, 9, 23, 14, 36, 5);
      await tester.tap(find.text('Iniciar jornada'));
      await tester.pumpAndSettle();

      expect(dataSource.jornadas.single.inicio, DateTime(2026, 9, 23, 14, 25).toUtc());
      expect(find.text('Desde las 14:25'), findsOneWidget);
    });
  });

  group('Estructura de la app (barra inferior)', () {
    testWidgets('la barra tiene Hoy · Mapa · Lista · Agenda · Ventas, con "Hoy" primero y '
        'Configuración en el engranaje', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      final barra = find.byKey(const Key('inicio_barra'));
      for (final etiqueta in ['Hoy', 'Mapa', 'Lista', 'Agenda', 'Ventas']) {
        expect(find.descendant(of: barra, matching: find.text(etiqueta)), findsOneWidget);
      }
      expect(tester.widget<NavigationBar>(barra).selectedIndex, 0, reason: 'arranca en "Hoy"');
      expect(find.byTooltip('Configuración'), findsOneWidget);
    });

    testWidgets('cada pestaña sin HU todavía queda vacía y no pierde lo elegido en "Hoy"', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();
      await _abrirHoja(tester);
      await _tocarVeces(tester, 'hoja_hora_menos', 2);
      await tester.tap(find.text('Usar 14:25'));
      await tester.pumpAndSettle();

      for (final pestana in ['mapa', 'lista', 'agenda', 'ventas']) {
        await tester.tap(find.byKey(Key('inicio_pestana_$pestana')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('pestana_$pestana')), findsOneWidget);
        expect(find.text('Sin jornada en curso').hitTestable(), findsNothing);
      }

      await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);
    });

    testWidgets('"Abrir el mapa" lleva a la pestaña Mapa', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 14, 35))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir el mapa'));
      await tester.pumpAndSettle();

      expect(tester.widget<NavigationBar>(find.byKey(const Key('inicio_barra'))).selectedIndex, 1);
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
          'Tocá “Reintentar” para volver a cargarla. Tus datos siguen guardados en este teléfono.',
        ),
        findsOneWidget,
      );
      expect(find.text('No pudimos leer tu jornada.'), findsOneWidget);
      expect(find.byKey(const Key('jornada_iniciar')), findsNothing);

      dataSource.errorAlLeer = null;
      // La pestaña «Lista» también vive en el `IndexedStack` y tiene su propio «Reintentar».
      await tester.tap(find.text('Reintentar').hitTestable());
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
          'No pudimos guardar el inicio de tu jornada. Probá de nuevo; si sigue pasando, avisale a '
          'tu coordinador.',
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

    testWidgets('sin jornada: fecha de hoy, estado "Sin jornada", la hora como fila y el botón al '
        'pie', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _DataSource());
      await tester.pumpAndSettle();

      expect(find.text('MIÉRCOLES 23 DE SEPTIEMBRE'), findsOneWidget);
      expect(find.text('Sin jornada'), findsOneWidget);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
      expect(find.text('Marcá el inicio cuando salgas a trabajar.'), findsOneWidget);
      expect(find.text('HORA DE INICIO'), findsOneWidget);
      expect(find.text('Cambiar ›'), findsOneWidget);
      expect(find.text('Podés marcar el inicio hasta 30 minutos hacia atrás.'), findsOneWidget);
      // El botón queda al pie, arriba de la barra inferior.
      final boton = tester.getBottomLeft(find.byKey(const Key('jornada_iniciar'))).dy;
      final barra = tester.getTopLeft(find.byKey(const Key('inicio_barra'))).dy;
      expect(boton, lessThanOrEqualTo(barra));
      expect(barra - boton, lessThan(40));
      // Cerrar sesión vive en Configuración (HU-AUTH-006).
      expect(find.byTooltip('Configuración'), findsOneWidget);
    });

    testWidgets('jornada activa: estado "En curso", desde qué hora y cuánto lleva', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('LLEVÁS'), findsOneWidget);
      expect(find.text('Abrir el mapa'), findsOneWidget);
      expect(find.text('Finalizar jornada'), findsOneWidget);
    });

    testWidgets(
      'la jornada activa sobrevive a un reinicio de la app',
      // skip: issue #72 — bloqueado por #27. Hoy nadie abre la DB local (el login todavía no
      // deriva la clave, HU-AUTH-009), así que `jornadaLocalDataSourceProvider` cae al fallback
      // en memoria (`JornadaLocalDataSourceEnMemoria`, ver el comentario TODO(#27) en
      // `jornada_providers.dart`) y la jornada se pierde al cerrar la app — por diseño, no es un
      // bug. Cuando el login abra la DB este provider pasa solo a `JornadaLocalDataSourceDrift`,
      // que persiste; ahí este criterio se puede probar de verdad (con un `AppDatabase` real
      // entre dos "sesiones" de la app, no con el fake en memoria de este archivo).
      skip: true,
      (tester) async {},
    );
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
      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
      expect(find.text('Buen trabajo'), findsOneWidget);
      expect(find.text('TRABAJASTE'), findsOneWidget);
      expect(find.text('De las 13:15 a las 14:35'), findsOneWidget);
      expect(find.text('1 h 20 min'), findsOneWidget);

      await _volverAlInicio(tester);
      expect(find.text('JORNADA FINALIZADA'), findsNothing);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
      expect(_botonIniciar(tester).onPressed, isNotNull);
    });

    testWidgets('un doble toque en "Volver al inicio" no saca también la pantalla principal', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      await _tocarFinalizar(tester);

      await tester.tap(find.text('Volver al inicio'));
      await tester.tap(find.text('Volver al inicio'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });
  });

  group('Hora de fin (hasta 30 minutos hacia atrás, no antes del inicio)', () {
    testWidgets('la hoja ofrece de a 5 minutos entre 30 minutos atrás y ahora, y la jornada '
        'termina a la hora elegida', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('HORA DE FIN'), findsOneWidget);
      expect(find.text('Ahora · 14:35'), findsOneWidget);
      expect(find.textContaining('Podés marcar el fin'), findsNothing);

      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();
      expect(find.text('¿A qué hora terminaste?'), findsOneWidget);
      expect(find.text('Entre las 14:05 y las 14:35.'), findsOneWidget);
      await _tocarVeces(tester, 'hoja_hora_menos', 2);
      expect(find.text('Usar 14:25'), findsOneWidget);
      await tester.tap(find.text('Usar 14:25'));
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);

      await _tocarFinalizar(tester);

      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 14, 25).toUtc());
      expect(find.text('De las 13:15 a las 14:25'), findsOneWidget);
      expect(find.text('1 h 10 min'), findsOneWidget);
    });

    testWidgets('"Otra hora" de fin: fuera de rango se rechaza con el rango explícito', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '13:50');
      await tester.pumpAndSettle();

      expect(find.text('La hora tiene que estar entre las 14:05 y las 14:35.'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_usar_escrita'), isNull);
    });

    testWidgets('si la jornada empezó hace menos de 30 minutos, la hoja no pasa del inicio', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 14, 20))]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Podés marcar el fin'), findsNothing);

      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();

      expect(find.text('Entre las 14:20 y las 14:35.'), findsOneWidget);
      await _tocarVeces(tester, 'hoja_hora_menos', 4);
      expect(find.text('14:20'), findsOneWidget);
      expect(_boton(tester, 'hoja_hora_menos'), isNull);
    });

    testWidgets('si la jornada es de un día anterior, el selector no se ofrece (ninguna hora de '
        'hoy le corresponde): "Cambiar" queda deshabilitado y "Finalizar" navega directo a la '
        'corrección (bug #118, repro del revisor)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 22, 18))]);
      // Repro exacta del revisor: inicio 22/09 18:00, ahora 23/09 10:00.
      await _montar(tester, dataSource, reloj: () => DateTime(2026, 9, 23, 10));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('jornada_ajustar_hora_fin')));
      expect(
        tester.widget<InkWell>(find.byKey(const Key('jornada_ajustar_hora_fin'))).onTap,
        isNull,
        reason:
            'antes del fix, esto se podía tocar y ofrecía una hora de hoy (p. ej. "hace 15 '
            'min") que el caso de uso rechazaba con un rango de AYER, sin navegar a la corrección',
      );

      await _tocarFinalizar(tester);

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.textContaining('Tenés una jornada del martes 22 sin cerrar.'), findsOneWidget);
      expect(find.byKey(const Key('jornada_error_fin')), findsNothing);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });

    testWidgets(
      'cruzando la medianoche (#250): con la jornada iniciada a las 23:50, a las 00:10 el '
      'selector ofrece hasta las 00:10 y la jornada termina a las 00:05 del día siguiente',
      (tester) async {
        _pantalla(tester, const Size(390, 844));
        final dataSource = _DataSource(
          iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 23, 50))],
        );
        await _montar(tester, dataSource, reloj: () => DateTime(2026, 9, 24, 0, 10, 20));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
        await tester.pumpAndSettle();
        expect(find.text('Entre las 23:50 y las 00:10.'), findsOneWidget);
        await tester.tap(find.byKey(const Key('hoja_hora_valor')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '00:05');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Usar esta hora'));
        await tester.pumpAndSettle();
        expect(find.text('00:05 · hace 5 min'), findsOneWidget);

        await _tocarFinalizar(tester);

        expect(find.byType(CorregirJornadaPage), findsNothing);
        expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 24, 0, 5).toUtc());
        expect(find.text('De las 23:50 a las 00:05'), findsOneWidget);
        expect(find.text('15 min'), findsOneWidget);
      },
    );
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
      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
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
          'pasando, avisale a tu coordinador.',
        ),
        findsOneWidget,
      );
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Sigue en curso'), findsOneWidget);
      expect(find.text('LLEVÁS'), findsNothing);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
      expect(_botonFinalizar(tester).onPressed, isNotNull);

      dataSource.errorAlFinalizar = null;
      await _tocarFinalizar(tester);
      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
      expect(find.byKey(const Key('jornada_error_fin')), findsNothing);
    });

    testWidgets('finalizar sin jornada activa (doble toque desde dos dispositivos): si ya se '
        'cerró en otro lado mientras la pantalla seguía en "Jornada activa", relee el estado sin '
        'mostrar error (#76)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final abierta = _jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15));
      final dataSource = _DataSource(iniciales: [abierta]);
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);

      // Otro dispositivo (o una pestaña duplicada) ya la cerró por su cuenta: el almacenamiento
      // real ya no tiene una jornada abierta, pero esta pantalla todavía no se enteró — el mismo
      // caso de uso que el "doble toque" pero disparado desde afuera en vez de un segundo tap acá
      // (ese lo bloquea el botón deshabilitado, ver el test de arriba).
      await dataSource.finalizar(
        JornadaModel.fromEntity(
          abierta.finalizada(
            fin: DateTime(2026, 9, 23, 14),
            actualizadaEn: DateTime(2026, 9, 23, 14),
          ),
        ),
      );

      await _tocarFinalizar(tester);

      expect(find.byKey(const Key('jornada_error_fin')), findsNothing);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
    });

    testWidgets('si la jornada la cerró otro teléfono, la hora de fin elegida no pasa a la próxima '
        'jornada', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final abierta = _jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15));
      final dataSource = _DataSource(iniciales: [abierta]);
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();
      await _tocarVeces(tester, 'hoja_hora_menos', 2);
      await tester.tap(find.text('Usar 14:25'));
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);

      // Otro teléfono la cierra; al tocar "Finalizar" esta pantalla se entera.
      await dataSource.finalizar(
        JornadaModel.fromEntity(
          abierta.finalizada(
            fin: DateTime(2026, 9, 23, 14),
            actualizadaEn: DateTime(2026, 9, 23, 14),
          ),
        ),
      );
      await _tocarFinalizar(tester);
      expect(find.text('Sin jornada en curso'), findsOneWidget);

      // La próxima jornada arranca sin la hora de fin vieja.
      await tester.ensureVisible(find.byKey(const Key('jornada_iniciar')));
      await tester.tap(find.byKey(const Key('jornada_iniciar')));
      await tester.pumpAndSettle();
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('Ahora · 14:35'), findsOneWidget);
      expect(find.text('14:25 · hace 10 min'), findsNothing);
    });

    testWidgets(
      'el backup solo se dispara con Wi-Fi disponible y batería ≥ 30 %',
      // skip: issue #76 — bloqueado por #74. `DisparadorBackupPendiente` (el stub de
      // HU-SYNC-005 que usa hoy `disparadorBackupProvider`) no mira Wi-Fi ni batería: siempre
      // "dispara" (en los hechos, solo loguea que se pidió). La condición real llega con el
      // motor de sync (carril aparte); hasta entonces este criterio de la HU no se puede
      // verificar ni cumplir.
      skip: true,
      (tester) async {},
    );

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
      await _volverAlInicio(tester);

      await tester.ensureVisible(find.byKey(const Key('jornada_iniciar')));
      await tester.tap(find.byKey(const Key('jornada_iniciar')));
      await tester.pumpAndSettle();

      expect(find.text('Jornada activa'), findsOneWidget);
      expect(find.text('JORNADA FINALIZADA'), findsNothing);
      expect(dataSource.jornadas, hasLength(2));
    });

    testWidgets('reloj atrasado: si la hora del teléfono quedó antes del inicio, dice qué pasó y '
        'qué hacer, y la jornada sigue abierta (#102)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      // La jornada empezó a las 15:35 y el teléfono dice 14:35: alguien atrasó el reloj.
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 15, 35))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _tocarFinalizar(tester);

      expect(
        find.text(
          'La hora del teléfono es anterior al inicio de tu jornada. Revisá la fecha y hora del '
          'teléfono y volvé a intentar.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('jornada_error_fin')), findsOneWidget);
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });

    testWidgets('jornada de un día anterior: no la cierra con la hora de hoy y navega a "¿A qué '
        'hora terminaste?" con el mensaje de qué día es (#102, wiring en #109)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 22, 18))]);
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _tocarFinalizar(tester);

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.text('¿A qué hora terminaste?'), findsOneWidget);
      expect(find.text('Martes 22 · después de las 18:00'), findsOneWidget);
      expect(find.textContaining('Tenés una jornada del martes 22 sin cerrar.'), findsOneWidget);
      // Se navegó: la pantalla de jornada (con su bloqueo "Jornada activa") ya no está en pantalla.
      expect(find.text('Jornada activa'), findsNothing);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });

    testWidgets('al corregir la hora de esa jornada y cerrar, vuelve y lo trata como un cierre '
        'exitoso normal, con el resumen (#109)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 22, 18))]);
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _tocarFinalizar(tester);
      expect(find.byType(CorregirJornadaPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '20:30');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 22, 20, 30).toUtc());
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
      expect(find.text('De las 18:00 a las 20:30'), findsOneWidget);
      await _volverAlInicio(tester);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('jornada iniciada a las 23:59 de ayer (#250): "Finalizar" lleva a la corrección, '
        'una hora de la madrugada la cierra y el resumen la cuenta de punta a punta', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 22, 23, 59))],
      );
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _tocarFinalizar(tester);
      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      // Antes de #250 no había ninguna hora posible y la única salida era volver.
      expect(find.byKey(const Key('corregir_jornada_atras')), findsNothing);

      await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
      await tester.pumpAndSettle();
      expect(find.text('Entre las 00:00 y las 11:59.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_hora_valor')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '00:30');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 0, 30).toUtc());
      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
      expect(find.text('De las 23:59 a las 00:30'), findsOneWidget);
      expect(find.text('31 min'), findsOneWidget);
      await _volverAlInicio(tester);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('la corrección no tiene salida sin elegir una hora: ni flecha ni atrás del '
        'sistema, y la jornada sigue abierta (#230)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 22, 18))]);
      await _montar(tester, dataSource);
      await tester.pumpAndSettle();

      await _tocarFinalizar(tester);
      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.byKey(const Key('corregir_jornada_atras')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });

    testWidgets(
      'desde la corrección, si la jornada ya estaba cerrada, sale y Hoy relee lo guardado '
      '(no queda trabada, #230)',
      (tester) async {
        _pantalla(tester, const Size(390, 844));
        final dataSource = _DataSource(
          iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 22, 18))],
        );
        await _montar(tester, dataSource);
        await tester.pumpAndSettle();
        await _tocarFinalizar(tester);
        expect(find.byType(CorregirJornadaPage), findsOneWidget);

        await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('hoja_hora_valor')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '20:30');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
        await tester.pumpAndSettle();

        dataSource.lecturasSinVer = 1;
        await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
        await tester.pumpAndSettle();

        expect(find.byType(CorregirJornadaPage), findsNothing);
        expect(find.text('JORNADA FINALIZADA'), findsNothing);
        // Hoy volvió a leer lo guardado y se puede seguir usando.
        expect(find.text('Jornada activa'), findsOneWidget);
        expect(_botonFinalizar(tester).onPressed, isNotNull);
      },
    );

    testWidgets('guarda la hora de fin que mostraba la etiqueta, aunque el minuto cambie antes '
        'del toque (#102)', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final dataSource = _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13, 15))],
      );
      var reloj = _ahora;
      await _montar(tester, dataSource, reloj: () => reloj);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
      await tester.pumpAndSettle();
      await _tocarVeces(tester, 'hoja_hora_menos', 2);
      await tester.tap(find.text('Usar 14:25'));
      await tester.pumpAndSettle();
      expect(find.text('14:25 · hace 10 min'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
      await tester.pumpAndSettle();

      reloj = DateTime(2026, 9, 23, 14, 36, 5);
      await tester.tap(find.byKey(const Key('jornada_finalizar')));
      await tester.pumpAndSettle();

      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 14, 25).toUtc());
    });
  });

  group('Accesibilidad', () {
    const estados = [
      'sin jornada',
      'hoja de ajuste',
      'otra hora fuera de rango',
      'iniciando',
      'error al guardar',
      'error de carga',
      'ya en curso',
      'jornada activa',
      'finalizando',
      'error al guardar el fin',
      'hoja de fin',
      'jornada finalizada',
    ];

    /// Deja la pantalla en [estado], con el selector de hora abierto cuando lo hay.
    Future<void> prepararEstado(WidgetTester tester, String estado, _DataSource dataSource) async {
      switch (estado) {
        case 'hoja de ajuste':
          await _abrirHoja(tester);
          await _tocarVeces(tester, 'hoja_hora_menos', 2);
        case 'otra hora fuera de rango':
          await _abrirHoja(tester);
          await tester.tap(find.byKey(const Key('hoja_hora_valor')));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '13:50');
        case 'iniciando':
          dataSource.demoraInsercion = Completer<void>();
          await tester.ensureVisible(find.byKey(const Key('jornada_iniciar')));
          await tester.tap(find.byKey(const Key('jornada_iniciar')));
          await tester.pump();
        case 'error al guardar':
          dataSource.errorAlInsertar = StateError('disco lleno');
          await tester.ensureVisible(find.byKey(const Key('jornada_iniciar')));
          await tester.tap(find.byKey(const Key('jornada_iniciar')));
        case 'ya en curso':
          await tester.ensureVisible(find.byKey(const Key('jornada_iniciar')));
          await tester.tap(find.byKey(const Key('jornada_iniciar')));
        case 'jornada activa':
          break;
        case 'hoja de fin':
          await tester.ensureVisible(find.byKey(const Key('jornada_ajustar_hora_fin')));
          await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
        case 'finalizando' || 'error al guardar el fin':
          await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
          await tester.tap(find.byKey(const Key('jornada_finalizar')));
          if (estado == 'finalizando') await tester.pump();
        case 'jornada finalizada':
          await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
          await tester.tap(find.byKey(const Key('jornada_finalizar')));
      }
      if (estado == 'iniciando' || estado == 'finalizando') return;
      await tester.pumpAndSettle();
    }

    _DataSource dataSourcePara(String estado) => switch (estado) {
      'jornada activa' || 'hoja de fin' || 'jornada finalizada' => _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13))],
      ),
      'finalizando' => _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13))],
      )..demoraFinalizar = Completer<void>(),
      'error al guardar el fin' => _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 13))],
      )..errorAlFinalizar = StateError('disco lleno'),
      'ya en curso' => _DataSource(
        iniciales: [_jornadaAbiertaDesde(DateTime(2026, 9, 23, 8, 10))],
      )..lecturasSinVer = 1,
      'error de carga' => _DataSource()..errorAlLeer = StateError('db ilegible'),
      _ => _DataSource(),
    };

    for (final estado in estados) {
      testWidgets('$estado: tamaño de toque, etiquetas y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        _pantalla(tester, const Size(390, 844));
        final dataSource = dataSourcePara(estado);
        await _montar(tester, dataSource);
        await tester.pumpAndSettle();
        await prepararEstado(tester, estado, dataSource);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });

      testWidgets('$estado: sin overflow con el texto al 200 % en 360x740', (tester) async {
        _pantalla(tester, const Size(360, 740));
        final dataSource = dataSourcePara(estado);
        await _montar(tester, dataSource, escalaTexto: 2);
        await tester.pumpAndSettle();
        await prepararEstado(tester, estado, dataSource);

        expect(tester.takeException(), isNull);
      });
    }
  });
}
