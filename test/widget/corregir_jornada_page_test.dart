// "¿A qué hora terminaste?" (HU-JOR-002, "jornada que quedó abierta", #109): corrige una jornada
// que quedó abierta de un día anterior, con la hora elegida a mano entre el inicio (excluido) y
// 12 h después, sin pasar de ahora ni del inicio de la jornada siguiente: el fin puede caer al día
// siguiente (#250, #327). Un test por escenario con el texto literal, estados (incluido el error
// al guardar), validación del rango, casos límite y accesibilidad (tamaño de toque, etiquetas,
// contraste y texto al 200 %). El wiring con `JornadaPage` (a qué pantalla se llega y qué pasa al
// volver) se prueba en `jornada_page_test.dart`; acá la pantalla se abre igual que ella lo hace:
// empujada sobre otra ruta, para que `Navigator.pop` tenga a dónde volver.
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

/// Miércoles 23/09/2026, 08:00: el rango para `_inicio` va de las 18:01 a las 06:00 (12 h después
/// del inicio, que cruza la medianoche).
final _ahora = DateTime(2026, 9, 23, 8);

JornadaModel _jornadaAbierta({DateTime? inicio}) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-previa',
    colportorId: _sesion.usuarioId,
    inicio: inicio ?? _inicio,
    auditoria: Auditoria(
      createdAt: inicio ?? _inicio,
      updatedAt: inicio ?? _inicio,
      createdBy: _sesion.usuarioId,
    ),
  ),
);

/// Una jornada ya cerrada: la que sigue a la que quedó abierta (el tope de su fin, #327).
JornadaModel _jornadaCerrada({required DateTime inicio, required DateTime fin}) =>
    JornadaModel.fromEntity(
      Jornada(
        id: 'jor-siguiente',
        colportorId: _sesion.usuarioId,
        inicio: inicio,
        fin: fin,
        auditoria: Auditoria(createdAt: inicio, updatedAt: fin, createdBy: _sesion.usuarioId),
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

  /// Cuántos cierres llegaron al almacenamiento (un doble toque no debe sumar dos).
  int escrituras = 0;

  /// Cuántas lecturas más devuelven "sin jornada" aunque haya una abierta: simula que otro
  /// teléfono ya la cerró (sync) o un doble toque.
  int lecturasSinVer = 0;

  List<JornadaModel> get jornadas => _real.jornadas;

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) =>
      _real.siguienteA(colportorId: colportorId, inicio: inicio);

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    if (lecturasSinVer > 0) {
      lecturasSinVer--;
      return null;
    }
    return _real.obtenerActiva(colportorId);
  }

  @override
  Future<void> insertar(JornadaModel jornada) => _real.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) async {
    escrituras++;
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
  DateTime? ahora,
  DateTime Function()? reloj,
}) {
  final escalaEfectiva = escala ?? _Escala(1);
  final relojFijo = ahora ?? _ahora;
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(dataSource),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(reloj ?? () => relojFijo),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        theme: tema ?? temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escalaEfectiva.valor)),
          child: child!,
        ),
        home: const Scaffold(),
      ),
    ),
  );
}

Future<_Resultado> _abrirCorregir(
  WidgetTester tester, {
  DateTime? inicio,
  DateTime? inicioSiguiente,
}) async {
  final resultado = _Resultado();
  unawaited(
    _navigatorKey.currentState!
        .push<Jornada>(
          MaterialPageRoute(
            builder: (_) => CorregirJornadaPage(
              sesion: _sesion,
              inicio: inicio ?? _inicio,
              inicioSiguiente: inicioSiguiente,
            ),
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

/// Abre la hoja de hora, escribe [hora]:[minuto] en "Otra hora" y, si [confirmar], la usa.
Future<void> _elegirHora(WidgetTester tester, int hora, int minuto, {bool confirmar = true}) async {
  // A 360x740 con textScaler 2.0 el botón queda fuera del viewport por defecto (la pantalla
  // scrollea).
  await tester.ensureVisible(find.byKey(const Key('corregir_jornada_elegir_hora')));
  await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('hoja_hora_valor')));
  await tester.tap(find.byKey(const Key('hoja_hora_valor')));
  await tester.pumpAndSettle();
  final texto = '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
  await tester.enterText(find.byKey(const Key('hoja_hora_campo')), texto);
  await tester.pumpAndSettle();
  if (!confirmar) return;
  await tester.ensureVisible(find.byKey(const Key('hoja_hora_usar_escrita')));
  await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
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
          'Tu jornada del martes 22 empezó a las 18:00 y quedó abierta. Cerrala para empezar la '
          'de hoy.',
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
        'posterior): la hoja rechaza con el rango explícito y no deja elegirla', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);

      // El inicio fue a las 18:00: elegir esa misma hora no vale (el rango excluye el inicio).
      await _elegirHora(tester, 18, 0, confirmar: false);

      expect(find.text('La hora tiene que estar entre las 18:01 y las 06:00.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('hoja_hora_usar_escrita'))).onPressed,
        isNull,
      );
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
      // 21A·04 (#327): el círculo no va solo, dice qué está pasando, como "Finalizando…" en Hoy.
      expect(
        find.descendant(
          of: find.byKey(const Key('corregir_jornada_cerrar')),
          matching: find.text('Finalizando…'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')), warnIfMissed: false);

      dataSource.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
      expect(dataSource.escrituras, 1);
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

      expect(
        find.text(
          'No pudimos guardar el fin de tu jornada, que sigue abierta. Probá de nuevo; si sigue '
          'pasando, avisale a tu coordinador.',
        ),
        findsOneWidget,
      );
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
      expect(_botonCerrar(tester).onPressed, isNotNull);

      dataSource.errorAlFinalizar = null;
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
      expect(find.byKey(const Key('corregir_jornada_error')), findsNothing);
    });

    testWidgets('sin flecha de volver: el atrás del sistema no sale y no cierra la jornada', (
      tester,
    ) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      final resultado = await _abrirCorregir(tester);

      expect(find.byKey(const Key('corregir_jornada_atras')), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(resultado.recibido, isFalse);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });
  });

  group('Ningún error deja la pantalla sin salida (revisión de #237)', () {
    testWidgets('si la jornada ya estaba cerrada (otro teléfono), sale sin jornada en vez de '
        'quedarse trabada', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      final resultado = await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);

      // Dos lecturas: la del estado (que la pantalla no había armado) y la del caso de uso.
      dataSource.lecturasSinVer = 2;
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(resultado.recibido, isTrue);
      expect(resultado.valor, isNull);
    });

    testWidgets('un fallo al guardar no bloquea: deja reintentar en la misma pantalla', (
      tester,
    ) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);

      dataSource.errorAlFinalizar = null;
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(dataSource.jornadas.single.estaAbierta, isFalse);
    });

    testWidgets('jornada iniciada a las 23:59 (#250): ya hay horas válidas del día siguiente, así '
        'que no queda trabada ni hace falta volver', (tester) async {
      final inicio = DateTime(2026, 9, 22, 23, 59);
      final dataSource = _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]);
      await _montar(tester, dataSource);
      final resultado = await _abrirCorregir(tester, inicio: inicio);

      expect(find.byKey(const Key('corregir_jornada_atras')), findsNothing);
      await _elegirHora(tester, 0, 30);
      expect(find.text('Terminé a las 00:30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 0, 30).toUtc());
      expect(resultado.valor?.fin, DateTime(2026, 9, 23, 0, 30).toUtc());
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets('si no queda ningún minuto válido (el reloj del teléfono quedó antes del inicio), '
        'deja volver para no ser una trampa', (tester) async {
      final inicio = DateTime(2026, 9, 22, 23, 59);
      final dataSource = _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]);
      await _montar(tester, dataSource, ahora: DateTime(2026, 9, 22, 23, 30));
      final resultado = await _abrirCorregir(tester, inicio: inicio);

      expect(find.byKey(const Key('corregir_jornada_atras')), findsOneWidget);

      await tester.tap(find.byKey(const Key('corregir_jornada_atras')));
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(resultado.recibido, isTrue);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });

    testWidgets('con horas válidas sigue sin flecha (el atrás solo sale sin minuto válido)', (
      tester,
    ) async {
      await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]));
      await _abrirCorregir(tester);

      expect(find.byKey(const Key('corregir_jornada_atras')), findsNothing);
    });
  });

  group('El fin puede cruzar la medianoche (#250, A08)', () {
    testWidgets('la hoja ofrece el rango completo, de las 18:01 a las 06:00 del día siguiente, y '
        'arranca en el primer minuto válido', (tester) async {
      await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]));
      await _abrirCorregir(tester);

      await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
      await tester.pumpAndSettle();

      expect(find.text('Entre las 18:01 y las 06:00.'), findsOneWidget);
      expect(find.text('18:01'), findsOneWidget);
      expect(find.byKey(const Key('hoja_hora_nota')), findsNothing);
    });

    testWidgets('una hora del día siguiente lo dice en la hoja y en la pantalla, y la jornada '
        'queda cerrada a esa hora', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      final resultado = await _abrirCorregir(tester);

      await _elegirHora(tester, 0, 30, confirmar: false);
      expect(find.text('Termina el miércoles 23, al día siguiente.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pumpAndSettle();

      expect(find.text('00:30'), findsOneWidget);
      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsOneWidget);
      expect(find.text('Termina el miércoles 23, al día siguiente.'), findsOneWidget);
      expect(find.text('Terminé a las 00:30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      final esperado = DateTime(2026, 9, 23, 0, 30).toUtc();
      expect(dataSource.jornadas.single.fin, esperado);
      expect(resultado.valor?.fin, esperado);
      expect(resultado.valor?.duracion, const Duration(hours: 6, minutes: 30));
    });

    testWidgets('una hora del mismo día no lleva aclaración, y cambiarla por una del día '
        'siguiente (y al revés) actualiza la aclaración', (tester) async {
      await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]));
      await _abrirCorregir(tester);

      await _elegirHora(tester, 20, 30);
      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsNothing);

      await _elegirHora(tester, 1, 15);
      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsOneWidget);
      expect(find.text('Terminé a las 01:15'), findsOneWidget);

      await _elegirHora(tester, 23, 10);
      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsNothing);
      expect(find.text('Terminé a las 23:10'), findsOneWidget);
    });

    testWidgets('el tope son 12 h después del inicio: las 06:00 valen, las 06:01 no y lo dice con '
        'el rango', (tester) async {
      await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]));
      await _abrirCorregir(tester);

      await _elegirHora(tester, 6, 1, confirmar: false);
      expect(find.text('La hora tiene que estar entre las 18:01 y las 06:00.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('hoja_hora_usar_escrita'))).onPressed,
        isNull,
      );

      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '06:00');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('hoja_hora_usar_escrita'))).onPressed,
        isNotNull,
      );
    });

    testWidgets('sin horas futuras: con el tope en ahora (menos de 12 h desde el inicio), una hora '
        'posterior se rechaza con el rango', (tester) async {
      final inicio = DateTime(2026, 9, 22, 22);
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]),
        ahora: DateTime(2026, 9, 23, 1),
      );
      await _abrirCorregir(tester, inicio: inicio);

      await _elegirHora(tester, 1, 30, confirmar: false);

      expect(find.text('La hora tiene que estar entre las 22:01 y las 01:00.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('hoja_hora_usar_escrita'))).onPressed,
        isNull,
      );
    });

    testWidgets('volver y reentrar: la hoja arranca en la hora que ya se había elegido, y al '
        'reentrar a la pantalla empieza sin hora', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 0, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_hora_usar')), findsOneWidget);
      expect(find.text('Usar 00:30'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_hora_cancelar')));
      await tester.pumpAndSettle();
      expect(find.text('Terminé a las 00:30'), findsOneWidget);

      // Cierra la pantalla (sin elegir otra cosa) y la vuelve a abrir: no arrastra la hora.
      _navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await _abrirCorregir(tester);
      expect(find.text('--:--'), findsOneWidget);
      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsNothing);
      expect(_botonCerrar(tester).onPressed, isNull);
    });

    testWidgets('dos toques seguidos en "Cerrar" con un fin del día siguiente cierran una sola '
        'vez', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..demoraFinalizar = Completer<void>();
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 0, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')), warnIfMissed: false);
      await tester.pump();
      expect(_botonCerrar(tester).onPressed, isNull);

      dataSource.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
      // Una sola escritura llegó al almacenamiento: `jornadas` tiene una fila aunque se cerrara
      // dos veces, así que lo que prueba el doble toque es el conteo de escrituras.
      expect(dataSource.escrituras, 1);
      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 0, 30).toUtc());
    });

    testWidgets('si falla a mitad con un fin del día siguiente, el botón vuelve a habilitarse y el '
        'reintento cierra a la misma hora', (tester) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 0, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);
      expect(_botonCerrar(tester).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Terminé a las 00:30'), findsOneWidget);

      dataSource.errorAlFinalizar = null;
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(dataSource.jornadas.single.fin, DateTime(2026, 9, 23, 0, 30).toUtc());
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets(
      'si el rango cambió entre la hoja y el toque (el reloj se atrasó), la hora fuera de '
      'rango se rechaza con el rango real y la jornada sigue abierta',
      (tester) async {
        final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
        var ahora = DateTime(2026, 9, 23, 8);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              jornadaLocalDataSourceProvider.overrideWithValue(dataSource),
              disparadorBackupProvider.overrideWithValue(_BackupFalso()),
              relojJornadaProvider.overrideWithValue(() => ahora),
            ],
            child: MaterialApp(
              navigatorKey: _navigatorKey,
              theme: temaClaro(),
              home: const Scaffold(),
            ),
          ),
        );
        await _abrirCorregir(tester);
        await _elegirHora(tester, 5, 30);

        // El reloj retrocede: ahora son las 03:00, y las 05:30 ya serían futuras.
        ahora = DateTime(2026, 9, 23, 3);
        await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('La hora tiene que estar entre las 18:01 y las 03:00.'),
          findsOneWidget,
        );
        expect(find.textContaining('Elegí otra hora y volvé a intentar.'), findsOneWidget);
        expect(dataSource.jornadas.single.estaAbierta, isTrue);
        expect(_botonCerrar(tester).onPressed, isNotNull);
      },
    );
  });

  group('Jornada siguiente, reloj atrasado y hoja de ajuste (#327)', () {
    // Martes 22 a las 22:00: sus 12 h terminarían el miércoles a las 10:00.
    final inicio = DateTime(2026, 9, 22, 22);
    // La jornada siguiente empezó el miércoles a las 08:00 y se cerró a las 10:00.
    final siguiente = DateTime(2026, 9, 23, 8);
    final ahoraTarde = DateTime(2026, 9, 23, 12);

    _DataSource conSiguiente() => _DataSource(
      iniciales: [
        _jornadaAbierta(inicio: inicio),
        _jornadaCerrada(inicio: siguiente, fin: DateTime(2026, 9, 23, 10)),
      ],
    );

    final botonElegir = find.byKey(const Key('corregir_jornada_elegir_hora'));
    final avisoReloj = find.byKey(const Key('corregir_jornada_reloj_atrasado'));

    testWidgets('con la jornada siguiente a las 08:00, la hoja ofrece hasta las 08:00 y no hasta '
        'las 10:00 que darían las 12 h; la jornada cierra a las 08:00', (tester) async {
      final dataSource = conSiguiente();
      await _montar(tester, dataSource, ahora: ahoraTarde);
      final resultado = await _abrirCorregir(tester, inicio: inicio, inicioSiguiente: siguiente);

      await tester.tap(botonElegir);
      await tester.pumpAndSettle();
      expect(find.text('Entre las 22:01 y las 08:00.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_hora_cancelar')));
      await tester.pumpAndSettle();

      // 08:01 pisaría a la jornada siguiente: la hoja lo rechaza con el rango y no deja usarlo.
      await _elegirHora(tester, 8, 1, confirmar: false);
      expect(find.text('La hora tiene que estar entre las 22:01 y las 08:00.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('hoja_hora_usar_escrita'))).onPressed,
        isNull,
      );

      // 08:00 queda a ras de la siguiente, sin superponerse: vale.
      await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '08:00');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pumpAndSettle();
      expect(find.text('Terminé a las 08:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      final esperado = DateTime(2026, 9, 23, 8).toUtc();
      expect(resultado.valor?.fin, esperado);
      expect(dataSource.jornadas.firstWhere((j) => j.id == 'jor-previa').fin, esperado);
      // La siguiente no se tocó.
      expect(
        dataSource.jornadas.firstWhere((j) => j.id == 'jor-siguiente').fin,
        DateTime(2026, 9, 23, 10).toUtc(),
      );
    });

    testWidgets('sin jornada siguiente, el tope siguen siendo las 12 h: hasta las 10:00', (
      tester,
    ) async {
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]),
        ahora: ahoraTarde,
      );
      await _abrirCorregir(tester, inicio: inicio);

      await tester.tap(botonElegir);
      await tester.pumpAndSettle();

      expect(find.text('Entre las 22:01 y las 10:00.'), findsOneWidget);
    });

    testWidgets('con ahora a las 07:00, antes de la jornada siguiente, el tope es ahora (gana el '
        'menor de los tres)', (tester) async {
      await _montar(tester, conSiguiente(), ahora: DateTime(2026, 9, 23, 7));
      await _abrirCorregir(tester, inicio: inicio, inicioSiguiente: siguiente);

      await tester.tap(botonElegir);
      await tester.pumpAndSettle();

      expect(find.text('Entre las 22:01 y las 07:00.'), findsOneWidget);
    });

    testWidgets('si la pantalla no conocía la siguiente, el caso de uso igual rechaza la hora que '
        'la pisa, con el rango real, y la jornada sigue abierta', (tester) async {
      final dataSource = conSiguiente();
      await _montar(tester, dataSource, ahora: ahoraTarde);
      await _abrirCorregir(tester, inicio: inicio);

      await _elegirHora(tester, 9, 0);
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('La hora tiene que estar entre las 22:01 y las 08:00.'),
        findsOneWidget,
      );
      expect(find.textContaining('Elegí otra hora y volvé a intentar.'), findsOneWidget);
      expect(dataSource.jornadas.firstWhere((j) => j.id == 'jor-previa').estaAbierta, isTrue);
      expect(_botonCerrar(tester).onPressed, isNotNull);

      // Con otra hora dentro del rango, cierra.
      await _elegirHora(tester, 7, 30);
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(
        dataSource.jornadas.firstWhere((j) => j.id == 'jor-previa').fin,
        DateTime(2026, 9, 23, 7, 30).toUtc(),
      );
    });

    testWidgets('reloj atrasado con la pantalla abierta: «Elegir la hora» no queda muda, dice qué '
        'pasó y qué hacer, se anuncia, deshabilita el botón y deja volver', (tester) async {
      final semantica = tester.ensureSemantics();
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      // El reloj del teléfono quedó el lunes a las 12:00, antes del inicio (martes 18:00).
      await _montar(tester, dataSource, ahora: DateTime(2026, 9, 21, 12));
      final resultado = await _abrirCorregir(tester);

      expect(avisoReloj, findsOneWidget);
      expect(
        find.descendant(
          of: avisoReloj,
          matching: find.text(
            'La hora del teléfono es anterior al inicio de tu jornada. Revisá la fecha y hora del '
            'teléfono y volvé a intentar.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.getSemantics(avisoReloj), isSemantics(isLiveRegion: true));
      expect(_botonCerrar(tester).onPressed, isNull);

      tester.takeAnnouncements();
      await tester.tap(botonElegir);
      await tester.pumpAndSettle();

      // No abre la hoja, no se desvanece el aviso y el toque se anuncia otra vez.
      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(avisoReloj, findsOneWidget);
      expect(tester.takeAnnouncements().map((a) => a.message), [
        'La hora del teléfono es anterior al inicio de tu jornada. Revisá la fecha y hora del '
            'teléfono y volvé a intentar.',
      ]);

      // Con la flecha de volver, no queda atrapado; la jornada sigue abierta.
      await tester.tap(find.byKey(const Key('corregir_jornada_atras')));
      await tester.pumpAndSettle();
      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(resultado.recibido, isTrue);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
      expect(dataSource.escrituras, 0);
      semantica.dispose();
    });

    testWidgets('reloj atrasado: el atrás del sistema también sale (no es una trampa)', (
      tester,
    ) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource, ahora: DateTime(2026, 9, 21, 12));
      final resultado = await _abrirCorregir(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(resultado.recibido, isTrue);
      expect(dataSource.jornadas.single.estaAbierta, isTrue);
    });

    testWidgets('el reloj se atrasa con una hora ya elegida: el aviso aparece sin cerrar nada, y '
        'al corregirlo la pantalla vuelve a ofrecer horas', (tester) async {
      var ahora = _ahora;
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()]);
      await _montar(tester, dataSource, reloj: () => ahora);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);
      expect(avisoReloj, findsNothing);
      expect(_botonCerrar(tester).onPressed, isNotNull);

      ahora = DateTime(2026, 9, 21, 12);
      await tester.tap(botonElegir);
      await tester.pumpAndSettle();

      expect(avisoReloj, findsOneWidget);
      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(_botonCerrar(tester).onPressed, isNull);
      expect(find.byKey(const Key('corregir_jornada_atras')), findsOneWidget);
      expect(dataSource.escrituras, 0);

      ahora = _ahora;
      await tester.tap(botonElegir);
      await tester.pumpAndSettle();
      expect(avisoReloj, findsNothing);
      expect(find.byKey(const Key('hoja_hora_ajuste')), findsOneWidget);
    });

    testWidgets('reloj atrasado y un error viejo: el aviso del reloj es el único que se muestra', (
      tester,
    ) async {
      var ahora = _ahora;
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..errorAlFinalizar = StateError('disco lleno');
      await _montar(tester, dataSource, reloj: () => ahora);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);

      ahora = DateTime(2026, 9, 21, 12);
      await tester.tap(botonElegir);
      await tester.pumpAndSettle();

      expect(avisoReloj, findsOneWidget);
      expect(find.byKey(const Key('corregir_jornada_error')), findsNothing);
    });

    testWidgets('mientras cierra no se puede abrir la hoja: la acción en curso no se pisa', (
      tester,
    ) async {
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..demoraFinalizar = Completer<void>();
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pump();
      await tester.tap(botonElegir, warnIfMissed: false);
      await tester.pump();

      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(find.text('Finalizando…'), findsOneWidget);

      dataSource.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
      expect(dataSource.escrituras, 1);
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets('mientras cierra, el botón conserva su nombre para el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final dataSource = _DataSource(iniciales: [_jornadaAbierta()])
        ..demoraFinalizar = Completer<void>();
      await _montar(tester, dataSource);
      await _abrirCorregir(tester);
      await _elegirHora(tester, 20, 30);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pump();

      expect(
        tester.getSemantics(find.byKey(const Key('corregir_jornada_cerrar'))).label,
        contains('Finalizando…'),
      );

      dataSource.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
      semantica.dispose();
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('hoja de ajuste (21A·02) a 360x640 con texto ${escala}x: −5 y +5 quedan a la '
          'altura de la hora y la nota del día siguiente va debajo de la fila, sin moverlos', (
        tester,
      ) async {
        final esc = _Escala(escala);
        _pantalla(tester, const Size(360, 640));
        await _montar(tester, _DataSource(iniciales: [_jornadaAbierta()]), escala: esc);
        await _abrirCorregir(tester);

        Future<({Rect menos, Rect mas, Rect valor, Rect? nota})> medir() async {
          await tester.ensureVisible(botonElegir);
          await tester.tap(botonElegir);
          await tester.pumpAndSettle();
          final medidas = (
            menos: tester.getRect(find.byKey(const Key('hoja_hora_menos'))),
            mas: tester.getRect(find.byKey(const Key('hoja_hora_mas'))),
            valor: tester.getRect(find.byKey(const Key('hoja_hora_valor'))),
            nota: find.byKey(const Key('hoja_hora_nota')).evaluate().isEmpty
                ? null
                : tester.getRect(find.byKey(const Key('hoja_hora_nota'))),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const Key('hoja_hora_cancelar')));
          await tester.tap(find.byKey(const Key('hoja_hora_cancelar')));
          await tester.pumpAndSettle();
          return medidas;
        }

        await _elegirHora(tester, 21, 10);
        final sinNota = await medir();
        await _elegirHora(tester, 0, 30);
        final conNota = await medir();

        expect(sinNota.nota, isNull);
        expect(conNota.nota, isNotNull);
        for (final m in [sinNota, conNota]) {
          // Los dos botones y la columna de la hora comparten el centro vertical.
          expect(m.menos.center.dy, closeTo(m.valor.center.dy, 0.5));
          expect(m.mas.center.dy, closeTo(m.valor.center.dy, 0.5));
          // Y los botones no se salen de la hoja por los costados.
          expect(m.menos.left, greaterThanOrEqualTo(0));
          expect(m.mas.right, lessThanOrEqualTo(360));
        }
        // La nota no agranda la columna de la hora: la altura es la misma con y sin nota, así
        // que los botones no se corren al aparecer.
        expect(conNota.valor.height, closeTo(sinNota.valor.height, 0.5));
        // Y queda debajo de la fila (no dentro de la columna de la hora).
        expect(conNota.nota!.top, greaterThanOrEqualTo(conNota.valor.bottom));
        expect(conNota.nota!.top, greaterThanOrEqualTo(conNota.menos.bottom));
        expect(conNota.nota!.top, greaterThanOrEqualTo(conNota.mas.bottom));
      });
    }

    testWidgets('cuando la siguiente empieza en el mismo minuto que el inicio no queda ninguna '
        'hora válida: avisa qué pasa y qué hacer, apaga «Elegir la hora» y deja volver', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final dataSource = _DataSource(
        iniciales: [
          _jornadaAbierta(inicio: inicio),
          _jornadaCerrada(
            inicio: inicio.add(const Duration(seconds: 30)),
            fin: inicio.add(const Duration(hours: 2)),
          ),
        ],
      );
      await _montar(tester, dataSource, ahora: ahoraTarde);
      final resultado = await _abrirCorregir(
        tester,
        inicio: inicio,
        inicioSiguiente: inicio.add(const Duration(seconds: 30)),
      );

      final aviso = find.byKey(const Key('corregir_jornada_sin_hora_siguiente'));
      expect(aviso, findsOneWidget);
      expect(
        find.descendant(
          of: aviso,
          matching: find.text(
            'Esta jornada y la siguiente empezaron a la misma hora (22:00), así que no hay una '
            'hora para cerrarla. Avisale a tu coordinador.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.getSemantics(aviso), isSemantics(isLiveRegion: true));
      // No es el aviso del reloj (el reloj está en hora) y «Elegir la hora» está apagado.
      expect(avisoReloj, findsNothing);
      expect(tester.widget<InkWell>(botonElegir).onTap, isNull);
      expect(_botonCerrar(tester).onPressed, isNull);
      await tester.tap(botonElegir, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(find.byKey(const Key('corregir_jornada_atras')), findsOneWidget);

      await tester.tap(find.byKey(const Key('corregir_jornada_atras')));
      await tester.pumpAndSettle();
      expect(resultado.recibido, isTrue);
      expect(dataSource.escrituras, 0);
      semantica.dispose();
    });

    testWidgets('el aviso de la siguiente en el mismo minuto se lee entero con el texto al 200 %', (
      tester,
    ) async {
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]),
        ahora: ahoraTarde,
        escala: _Escala(2),
      );
      await _abrirCorregir(
        tester,
        inicio: inicio,
        inicioSiguiente: inicio.add(const Duration(seconds: 30)),
      );

      expect(find.byKey(const Key('corregir_jornada_sin_hora_siguiente')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('con el reloj atrasado y la siguiente en el mismo minuto, manda el aviso del '
        'reloj y no el de la siguiente', (tester) async {
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]),
        ahora: DateTime(2026, 9, 21, 12),
      );
      await _abrirCorregir(
        tester,
        inicio: inicio,
        inicioSiguiente: inicio.add(const Duration(seconds: 30)),
      );

      expect(avisoReloj, findsOneWidget);
      expect(find.byKey(const Key('corregir_jornada_sin_hora_siguiente')), findsNothing);
      expect(find.byKey(const Key('corregir_jornada_atras')), findsOneWidget);
    });

    testWidgets('sin jornada siguiente, con el reloj dentro del minuto del inicio no se culpa a '
        'una siguiente que no existe: solo deja volver', (tester) async {
      await _montar(
        tester,
        _DataSource(iniciales: [_jornadaAbierta(inicio: inicio)]),
        ahora: inicio.add(const Duration(seconds: 20)),
      );
      await _abrirCorregir(tester, inicio: inicio);

      expect(find.byKey(const Key('corregir_jornada_sin_hora_siguiente')), findsNothing);
      expect(avisoReloj, findsNothing);
      expect(find.byKey(const Key('corregir_jornada_atras')), findsOneWidget);
      expect(_botonCerrar(tester).onPressed, isNull);
    });

    testWidgets('con una siguiente que deja horas libres no aparece el aviso del mismo minuto', (
      tester,
    ) async {
      await _montar(tester, conSiguiente(), ahora: ahoraTarde);
      await _abrirCorregir(tester, inicio: inicio, inicioSiguiente: siguiente);

      expect(find.byKey(const Key('corregir_jornada_sin_hora_siguiente')), findsNothing);
      expect(tester.widget<InkWell>(botonElegir).onTap, isNotNull);
    });
  });

  group('Accesibilidad', () {
    const estados = [
      'sin elegir hora',
      'hora elegida',
      'error de rango',
      'fin al día siguiente',
      'hoja con el día siguiente',
    ];

    /// Deja la pantalla en [estado].
    Future<void> prepararEstado(WidgetTester tester, String estado) async {
      switch (estado) {
        case 'sin elegir hora':
          break;
        case 'hora elegida':
          await _elegirHora(tester, 20, 30);
        case 'error de rango':
          await _elegirHora(tester, 18, 0, confirmar: false);
        case 'fin al día siguiente':
          await _elegirHora(tester, 0, 30);
        case 'hoja con el día siguiente':
          await _elegirHora(tester, 0, 30, confirmar: false);
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
        // El estado se arma a tamaño normal y después se sube el texto al 200 %.
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
