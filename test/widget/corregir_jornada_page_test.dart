// "¿A qué hora terminaste?" (HU-JOR-002, "jornada que quedó abierta", #109): corrige una jornada
// que quedó abierta de un día anterior, con la hora elegida a mano entre el inicio (excluido) y
// las 23:59 de ese día. Un test por escenario con el texto literal, estados (incluido el error al
// guardar), validación del rango y accesibilidad (tamaño de toque, etiquetas, contraste y texto
// al 200 %). El wiring con `JornadaPage` (a qué pantalla se llega y qué pasa al volver) se prueba
// en `jornada_page_test.dart`; acá la pantalla se abre igual que ella lo hace: empujada sobre otra
// ruta, para que `Navigator.pop` tenga a dónde volver.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
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

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

/// Martes 22/09/2026, 18:00 — la jornada que quedó abierta.
final _inicio = DateTime(2026, 9, 22, 18);

JornadaModel _jornadaAbierta() => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-previa',
    colportorId: _sesion.usuarioId,
    inicio: _inicio,
    auditoria: Auditoria(createdAt: _inicio, updatedAt: _inicio, createdBy: _sesion.usuarioId),
  ),
);

/// El almacenamiento en memoria de la app, con la perilla para el estado de guardar. La pantalla
/// no lee la jornada activa (no hay "cargando" acá), solo la cierra.
final class _DataSource implements JornadaLocalDataSource {
  _DataSource({Iterable<JornadaModel> iniciales = const []})
    : _real = JornadaLocalDataSourceEnMemoria(iniciales: iniciales);

  final JornadaLocalDataSourceEnMemoria _real;

  /// Si no es `null`, el cierre espera a que se complete (estado "cerrando").
  Completer<void>? demoraFinalizar;
  Object? errorAlFinalizar;

  List<JornadaModel> get jornadas => _real.jornadas;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) => _real.obtenerActiva(colportorId);

  @override
  Future<void> insertar(JornadaModel jornada) => _real.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) async {
    if (demoraFinalizar case final demora?) await demora.future;
    if (errorAlFinalizar case final error?) throw error;
    return _real.finalizar(jornada);
  }
}

/// El backup automático (HU-SYNC-005) no importa acá: solo evita que el pedido real anote nada.
final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// Lo que devolvió `Navigator.pop` al salir de `CorregirJornadaPage`.
final class _Resultado {
  Jornada? valor;
  bool recibido = false;
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// Escala de texto mutable: el `builder` de abajo la relee en cada rebuild (`MediaQuery` no
/// memoiza), así que cambiar [valor] y disparar un frame (`_pantalla`, un `tap`) alcanza para
/// subirla a mitad de test, sin perder el estado ya armado.
final class _Escala {
  _Escala(this.valor);
  double valor;
}

/// El `ProviderScope` va como argumento directo de `pumpWidget` (ver `jornada_page_test.dart`).
/// `home` es un `Scaffold` vacío: `CorregirJornadaPage` se empuja encima con [_abrirCorregir],
/// igual que hace `JornadaPage._finalizar` (#109), para que `Navigator.pop` tenga a dónde volver.
Future<void> _montar(
  WidgetTester tester,
  _DataSource dataSource, {
  ThemeData? tema,
  _Escala? escala,
}) {
  final escalaEfectiva = escala ?? _Escala(1);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(dataSource),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        theme: tema ?? temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(escalaEfectiva.valor),
            // Sin AM/PM: el selector de hora del sistema queda en 24 h, hora antes que minuto.
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        ),
        home: const Scaffold(),
      ),
    ),
  );
}

Future<_Resultado> _abrirCorregir(WidgetTester tester, {DateTime? inicio}) async {
  final resultado = _Resultado();
  unawaited(
    _navigatorKey.currentState!
        .push<Jornada>(
          MaterialPageRoute(
            builder: (_) => CorregirJornadaPage(sesion: _sesion, inicio: inicio ?? _inicio),
          ),
        )
        .then((valor) {
          resultado
            ..valor = valor
            ..recibido = true;
        }),
  );
  await tester.pumpAndSettle();
  return resultado;
}

void _pantalla(WidgetTester tester, Size tamanio) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Abre el selector de hora del sistema, lo pasa a modo texto (más estable en tests que arrastrar
/// el dial) y confirma [hora]:[minuto].
Future<void> _elegirHora(WidgetTester tester, int hora, int minuto) async {
  // A 360x740 con textScaler 2.0 el botón queda fuera del viewport por defecto (la pantalla es
  // un `ListView`, scrollea).
  await tester.ensureVisible(find.byKey(const Key('corregir_jornada_elegir_hora')));
  await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(0), '$hora');
  await tester.enterText(find.byType(TextFormField).at(1), '$minuto');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

FilledButton _botonCerrar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('corregir_jornada_cerrar')));

void main() {
  group('HU-JOR-002 — "jornada que quedó abierta" (#109)', () {
    testWidgets('muestra el título, el mensaje literal de qué día quedó sin cerrar y el botón '
        '"Cerrar" deshabilitado hasta elegir una hora', (tester) async {
      await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]));
      await _abrirCorregir(tester);

      expect(find.text('JORNADA SIN CERRAR'), findsOneWidget);
      expect(find.text('¿A qué hora terminaste?'), findsOneWidget);
      expect(
        find.text(
          'Tenés una jornada del martes 22 sin cerrar. No la cerramos con la hora de hoy para no '
          'sumarle horas que no trabajaste: hay que indicar a qué hora terminaste ese día.',
        ),
        findsOneWidget,
      );
      expect(find.text('Elegir la hora'), findsOneWidget);
      expect(_botonCerrar(tester).onPressed, isNull);
    });

    testWidgets('al elegir una hora válida ese mismo día y cerrar, la jornada queda cerrada a esa '
        'hora y se vuelve con la jornada cerrada', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      final resultado = await _abrirCorregir(tester);

      await _elegirHora(tester, 20, 30);
      expect(find.text('Terminé a las 20:30'), findsOneWidget);
      expect(_botonCerrar(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      final esperado = DateTime(2026, 9, 22, 20, 30).toUtc();
      expect(dataSource.jornadas.single.fin, esperado);
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
      expect(resultado.recibido, isTrue);
      expect(resultado.valor?.fin, esperado);
      // Volvió al `Scaffold` vacío de `_montar`: la pantalla de corrección ya no está.
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets('hora fuera de rango — a la misma hora del inicio (no es estrictamente '
        'posterior): rechaza con el rango explícito y no cierra la jornada', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);

      // El inicio fue a las 18:00: elegir esa misma hora no vale (el rango excluye el inicio).
      await _elegirHora(tester, 18, 0);
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'La hora tiene que estar entre las 18:00 y las 23:59. Elegí otra hora y volvé a '
          'intentar.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });
  });

  group('Estados', () {
    testWidgets('mientras cierra, el botón se deshabilita (un segundo toque no cierra dos veces)', (
      tester,
    ) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..demoraFinalizar = Completer<void>();
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pump();
      expect(_botonCerrar(tester).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')), warnIfMissed: false);

      dataSource.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
      expect(dataSource.jornadas, hasLength(1));
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
    });

    testWidgets('error al guardar: dice qué pasó, la jornada sigue abierta y deja volver a '
        'intentar', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(find.text('Ocurrió un error inesperado'), findsOneWidget);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
      expect(_botonCerrar(tester).onPressed, isNotNull);

      dataSource.errorAlFinalizar = null;
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
      expect(find.byKey(const Key('corregir_jornada_error')), findsNothing);
    });

    testWidgets('"Volver" sale de la pantalla sin cerrar la jornada', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      final resultado = await _abrirCorregir(tester);

      await tester.tap(find.byKey(const Key('corregir_jornada_atras')));
      await tester.pumpAndSettle();

      expect(resultado.recibido, isTrue);
      expect(resultado.valor, isNull);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });
  });

  group('Accesibilidad', () {
    const estados = ['sin elegir hora', 'hora elegida', 'error de rango'];

    /// Deja la pantalla en [estado].
    Future<void> prepararEstado(WidgetTester tester, String estado) async {
      switch (estado) {
        case 'sin elegir hora':
          break;
        case 'hora elegida':
          await _elegirHora(tester, 20, 30);
        case 'error de rango':
          await _elegirHora(tester, 18, 0);
          await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
          await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
          await tester.pumpAndSettle();
      }
    }

    for (final estado in estados) {
      testWidgets('$estado: tamaño de toque, etiquetas y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        _pantalla(tester, const Size(390, 844));
        await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]));
        await _abrirCorregir(tester);
        await prepararEstado(tester, estado);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });

      testWidgets('$estado: sin overflow con el texto al 200 % en 360x740', (tester) async {
        // El estado se arma a tamaño normal: a 360x740 con el texto al 200 % el diálogo del
        // selector de hora del *sistema* puede desbordar (ajeno a esta pantalla) antes de que
        // termine de abrirse. Lo que audita este test es el layout de `CorregirJornadaPage` ya
        // con el estado puesto, no el picker de Flutter.
        final escala = _Escala(1);
        await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]), escala: escala);
        await _abrirCorregir(tester);
        await prepararEstado(tester, estado);

        escala.valor = 2;
        _pantalla(tester, const Size(360, 740));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
