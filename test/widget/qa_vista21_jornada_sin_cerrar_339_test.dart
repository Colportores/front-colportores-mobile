// QA del PR #380 (#339, seguimiento de #327; vista 21A «Jornada sin cerrar», HU-JOR-002): lo que
// las pruebas del implementador no recorren. La jornada siguiente que llega con la pantalla abierta
// (la «foto vieja» de la pantalla contra lo que ya hay guardado), el aviso que aparece a mitad de
// camino (anuncio, salida, tamaños, toque), la falla y el doble toque en las dos vueltas de Hoy
// (hora de fin vieja que se suelta y se vuelve a pedir) y la hoja que sigue diciendo el rango viejo.
// Los textos son los de la HU-JOR-002 y los de las decisiones de #327 / #339.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/corregir_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/qa_jornada_sin_cerrar_250_arnes.dart';

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
/// (gitignored): nunca se commitean.
const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Lunes 21 18:00:30: la jornada siguiente empezó en el mismo minuto que `inicioQa` (18:00).
final _siguienteMismoMinuto = inicioQa.add(const Duration(seconds: 30));

/// Lunes 21 19:00: la jornada siguiente recorta el rango (18:01 a 19:00) pero deja horas.
final _siguienteALas19 = DateTime(2026, 9, 21, 19);

JornadaModel _cerradaQa(DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-siguiente',
    colportorId: sesionQa.usuarioId,
    inicio: inicio,
    fin: inicio.add(const Duration(hours: 1)),
    auditoria: Auditoria(
      createdAt: inicio,
      updatedAt: inicio.add(const Duration(hours: 1)),
      createdBy: sesionQa.usuarioId,
    ),
  ),
);

/// El almacenamiento de [DataSourceQa] con la lectura de «la jornada siguiente» a la mano: cuenta
/// las llamadas, puede fallar en las que se le diga y retener cada una hasta que se la libere.
final class _DataSourceSiguiente implements JornadaLocalDataSource {
  _DataSourceSiguiente(this._real);

  final DataSourceQa _real;

  /// Cuántas veces se leyó la jornada siguiente.
  int llamadas = 0;

  /// Números de llamada (desde 1) que fallan con «disco ilegible».
  final Set<int> fallan = {};

  /// Números de llamada que esperan a que se complete su `Completer`.
  final Map<int, Completer<void>> retienen = {};

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) async {
    final n = ++llamadas;
    if (retienen[n] case final espera?) await espera.future;
    if (fallan.contains(n)) throw StateError('disco ilegible');
    return _real.siguienteA(colportorId: colportorId, inicio: inicio);
  }

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) => _real.obtenerActiva(colportorId);

  @override
  Future<void> insertar(JornadaModel jornada) => _real.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) => _real.finalizar(jornada);
}

final _avisoSiguiente = find.byKey(const Key('corregir_jornada_sin_hora_siguiente'));
final _avisoError = find.byKey(const Key('corregir_jornada_error'));
final _botonElegir = find.byKey(const Key('corregir_jornada_elegir_hora'));
final _flecha = find.byKey(const Key('corregir_jornada_atras'));
final _botonCerrar = find.byKey(const Key('corregir_jornada_cerrar'));
final _finalizarHoy = find.byKey(const Key('jornada_finalizar'));

const _textoMismaHora18 =
    'Esta jornada y la siguiente empezaron a la misma hora (18:00), así que no hay una hora para '
    'cerrarla. Avisale a tu coordinador.';

Future<void> _tocarCerrar(WidgetTester tester) async {
  await tester.ensureVisible(_botonCerrar);
  await tester.tap(_botonCerrar);
  await tester.pumpAndSettle();
}

/// La pantalla «¿A qué hora terminaste?» abierta con la foto de antes de que llegara la jornada
/// siguiente (sin ella), con 20:00 ya elegida y con la siguiente en [siguiente] ya guardada en el
/// teléfono, como cuando el motor de sync la trae con la pantalla abierta. Toca «Terminé a las
/// 20:00» y devuelve lo que quedó.
Future<({DataSourceQa ds, ResultadoQa resultado})> _conSiguienteQueLlega(
  WidgetTester tester, {
  required DateTime siguiente,
  Size tamano = telefonoGrandeQa,
  double escala = 1,
}) async {
  fijarPantallaQa(tester, tamano);
  final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(), _cerradaQa(siguiente)]);
  await montarQa(tester, ds, escala: EscalaQa(escala));
  final resultado = await abrirCorregirQa(tester);
  await elegirHoraQa(tester, '20:00');
  await _tocarCerrar(tester);
  return (ds: ds, resultado: resultado);
}

/// La pestaña Hoy (21A·01) con los [overrides] dados y el texto a [escala].
Future<void> _montarHoy(WidgetTester tester, List<Override> overrides, {double escala = 1}) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => RepaintBoundary(
            key: raizCapturaQa,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
              child: child!,
            ),
          ),
          home: InicioPage(sesion: sesionQa),
        ),
      ),
    );

/// La jornada empezó el miércoles 23 a las 22:00 y a las 23:50 se eligió 23:45 como hora de fin;
/// la siguiente (si hay) empezó a las 23:30.
final _inicioNoche = DateTime(2026, 9, 23, 22);
final _antesDeMedianoche = DateTime(2026, 9, 23, 23, 50);
final _despuesDeMedianoche = DateTime(2026, 9, 24, 0, 35);

/// Monta Hoy a las 23:50 con 23:45 elegida y devuelve la función que mueve el reloj.
Future<void Function(DateTime)> _hoyConHoraVieja(
  WidgetTester tester,
  JornadaLocalDataSource ds, {
  Size tamano = telefonoGrandeQa,
  double escala = 1,
}) async {
  fijarPantallaQa(tester, tamano);
  var reloj = _antesDeMedianoche;
  final overrides = [
    jornadaLocalDataSourceProvider.overrideWithValue(ds),
    disparadorBackupProvider.overrideWithValue(BackupQa()),
    relojJornadaProvider.overrideWithValue(() => reloj),
    ...overridesPestanaMapa(),
  ];
  await _montarHoy(tester, overrides);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('jornada_ajustar_hora_fin')));
  await tester.tap(find.byKey(const Key('jornada_ajustar_hora_fin')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('hoja_hora_valor')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '');
  await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '23:45');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
  await tester.pumpAndSettle();
  // La hoja no se arma bien con el texto grande en una pantalla chica: se sube la escala recién
  // con el estado ya armado.
  if (escala != 1) {
    await _montarHoy(tester, overrides, escala: escala);
    await tester.pumpAndSettle();
  }
  return (DateTime nuevo) => reloj = nuevo;
}

Future<void> _tocarFinalizar(WidgetTester tester) async {
  await tester.ensureVisible(_finalizarHoy);
  await tester.tap(_finalizarHoy);
  await tester.pumpAndSettle();
}

FilledButton _botonFinalizar(WidgetTester tester) => tester.widget<FilledButton>(_finalizarHoy);

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCapturaQa));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/339_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  const matriz = <(String, Size, double)>[
    ('360x640 texto 1.0', telefonoChicoQa, 1),
    ('360x640 texto 2.0', telefonoChicoQa, 2),
    ('412x915 texto 1.0', telefonoGrandeQa, 1),
    ('412x915 texto 2.0', telefonoGrandeQa, 2),
  ];

  group(
    '21A·08 con la jornada siguiente que llega con la pantalla abierta (criterios de #339)',
    () {
      testWidgets(
        'dado que elegí una hora y llegó una siguiente en el mismo minuto, cuando cierro, '
        'entonces veo el aviso literal, sin rango al revés, y puedo volver sin escribir nada',
        (tester) async {
          final r = await _conSiguienteQueLlega(tester, siguiente: _siguienteMismoMinuto);

          expect(
            find.descendant(of: _avisoSiguiente, matching: find.text(_textoMismaHora18)),
            findsOne,
          );
          expect(find.textContaining('entre las'), findsNothing);
          expect(find.textContaining('18:01'), findsNothing);
          expect(_avisoError, findsNothing);
          expect(find.text('Finalizando…'), findsNothing);
          expect(find.text('--:--'), findsOneWidget);
          expect(r.ds.escrituras, 0);

          await tester.tap(_flecha);
          await tester.pumpAndSettle();
          expect(r.resultado.recibido, isTrue);
          expect(r.resultado.valor, isNull);
          expect(r.ds.escrituras, 0, reason: 'la jornada sigue abierta, sin un fin inventado');
          expect(r.ds.jornadas.where((j) => j.estaAbierta), hasLength(1));
        },
      );

      testWidgets('el aviso que aparece a mitad de camino se anuncia (liveRegion) con el texto '
          'literal, y la flecha y «Elegir la hora» se leen bien', (tester) async {
        final semantica = tester.ensureSemantics();
        await _conSiguienteQueLlega(tester, siguiente: _siguienteMismoMinuto);

        final aviso = tester.getSemantics(_avisoSiguiente);
        expect(aviso, isSemantics(isLiveRegion: true));
        expect(aviso.label, contains(_textoMismaHora18));
        final flecha = tester.getSemantics(_flecha);
        expect(flecha.tooltip, 'Volver');
        expect(flecha.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(
          tester.getSemantics(_botonElegir).getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'sin horas que ofrecer, «Elegir la hora» no se anuncia como un botón activo',
        );
        semantica.dispose();
      });

      testWidgets(
        'el botón de cerrar vuelve a estar quieto: sin «Finalizando…» y sin la hora que ya '
        'no sirve (el atrás del sistema también sale)',
        (tester) async {
          final r = await _conSiguienteQueLlega(tester, siguiente: _siguienteMismoMinuto);

          expect(tester.widget<FilledButton>(_botonCerrar).onPressed, isNull);
          expect(find.text('Cerrar'), findsOneWidget);
          expect(find.textContaining('Terminé a las'), findsNothing);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(r.resultado.recibido, isTrue);
          expect(r.ds.escrituras, 0);
        },
      );

      testWidgets('reentrada: al volver a abrir la pantalla con la foto vieja y tocar otra vez, el '
          'aviso sale de nuevo y nada queda trabado', (tester) async {
        final r = await _conSiguienteQueLlega(tester, siguiente: _siguienteMismoMinuto);
        await tester.tap(_flecha);
        await tester.pumpAndSettle();
        expect(r.resultado.recibido, isTrue);

        final segunda = await abrirCorregirQa(tester);
        expect(_avisoSiguiente, findsNothing, reason: 'la pantalla nueva arranca con su foto');
        await elegirHoraQa(tester, '19:00');
        await _tocarCerrar(tester);

        expect(_avisoSiguiente, findsOneWidget);
        expect(_flecha, findsOneWidget);
        expect(r.ds.escrituras, 0);
        await tester.tap(_flecha);
        await tester.pumpAndSettle();
        expect(segunda.recibido, isTrue);
      });

      testWidgets('un doble toque en «Terminé a las 20:00» no deja nada trabado ni escribe', (
        tester,
      ) async {
        fijarPantallaQa(tester, telefonoGrandeQa);
        final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(), _cerradaQa(_siguienteMismoMinuto)]);
        await montarQa(tester, ds);
        await abrirCorregirQa(tester);
        await elegirHoraQa(tester, '20:00');

        await tester.ensureVisible(_botonCerrar);
        await tester.tap(_botonCerrar);
        await tester.tap(_botonCerrar, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_avisoSiguiente, findsOneWidget);
        expect(ds.escrituras, 0);
        expect(find.text('Finalizando…'), findsNothing);
      });

      for (final (nombre, tamano, escala) in matriz) {
        testWidgets(
          '$nombre: el aviso que aparece a mitad de camino entra en la pantalla, la flecha '
          'mide 48 dp y no hay overflow',
          (tester) async {
            await _conSiguienteQueLlega(
              tester,
              siguiente: _siguienteMismoMinuto,
              tamano: tamano,
              escala: escala,
            );
            await tester.pump(const Duration(milliseconds: 100));

            expect(tester.takeException(), isNull);
            await tester.ensureVisible(_avisoSiguiente);
            await tester.pump();
            final caja = tester.getRect(_avisoSiguiente);
            expect(caja.left, greaterThanOrEqualTo(0));
            expect(caja.right, lessThanOrEqualTo(tamano.width));
            final flecha = tester.getSize(_flecha);
            expect(flecha.width, greaterThanOrEqualTo(48));
            expect(flecha.height, greaterThanOrEqualTo(48));
          },
        );
      }

      for (final tamano in [const Size(390, 844), telefonoChicoQa, telefonoGrandeQa]) {
        testWidgets(
          '${tamano.width.toInt()}x${tamano.height.toInt()} · aviso que aparece a mitad de '
          'camino: tamaño de toque, etiquetas y contraste',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await _conSiguienteQueLlega(tester, siguiente: _siguienteMismoMinuto, tamano: tamano);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            expect(tester.takeException(), isNull);
            semantica.dispose();
          },
        );
      }
    },
  );

  group('21A·03 con una siguiente que llega y deja horas (rango recortado, no vacío)', () {
    testWidgets('dado que elegí 20:00 y llegó una siguiente a las 19:00, cuando cierro, entonces '
        'veo el rango real, la hora se conserva y con una hora dentro del rango se cierra', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final r = await _conSiguienteQueLlega(tester, siguiente: _siguienteALas19);

      expect(
        find.descendant(
          of: _avisoError,
          matching: find.text(
            'La hora tiene que estar entre las 18:01 y las 19:00. Elegí otra hora y volvé a '
            'intentar.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.getSemantics(_avisoError), isSemantics(isLiveRegion: true));
      expect(_avisoSiguiente, findsNothing);
      expect(find.text('Finalizando…'), findsNothing);
      // Lo tipeado no se pierde y el botón sigue disponible para el reintento.
      expect(find.text('Terminé a las 20:00'), findsOneWidget);
      expect(tester.widget<FilledButton>(_botonCerrar).onPressed, isNotNull);
      expect(r.ds.escrituras, 0);

      await elegirHoraQa(tester, '18:30');
      expect(_avisoError, findsNothing, reason: 'al elegir otra hora el aviso viejo se va');
      await _tocarCerrar(tester);

      expect(r.resultado.recibido, isTrue);
      expect(r.resultado.valor!.fin, DateTime(2026, 9, 21, 18, 30).toUtc());
      expect(r.ds.escrituras, 1);
      semantica.dispose();
    });

    testWidgets('con la siguiente a las 19:00, una hora fuera de rango repetida da el mismo aviso '
        'una y otra vez sin trabar el botón', (tester) async {
      final r = await _conSiguienteQueLlega(tester, siguiente: _siguienteALas19);
      for (var i = 0; i < 3; i++) {
        await _tocarCerrar(tester);
        expect(find.textContaining('entre las 18:01 y las 19:00'), findsOneWidget);
        expect(find.text('Finalizando…'), findsNothing);
        expect(tester.widget<FilledButton>(_botonCerrar).onPressed, isNotNull);
      }
      expect(r.ds.escrituras, 0);
    });

    testWidgets('con la siguiente a las 19:00, al volver a abrir «Elegir la hora» la hoja ofrece '
        'el rango real (18:01 a 19:00) y no el viejo', (tester) async {
      final r = await _conSiguienteQueLlega(tester, siguiente: _siguienteALas19);
      await abrirHojaQa(tester);

      expect(find.text('Entre las 18:01 y las 19:00.'), findsOneWidget);
      expect(r.ds.escrituras, 0);
    }, skip: true); // skip: QA #339 — la hoja sigue diciendo «Entre las 18:01 y las 06:00.»
  });

  group('21A·01/05 Hoy con la hora de fin vieja y la jornada siguiente (dos vueltas)', () {
    final siguienteDeLaNoche = _cerradaQa(DateTime(2026, 9, 23, 23, 30));

    _DataSourceSiguiente armar({Iterable<JornadaModel> extra = const []}) =>
        _DataSourceSiguiente(DataSourceQa(iniciales: [jornadaAbiertaQa(_inicioNoche), ...extra]));

    testWidgets('falla a mitad: si la segunda vuelta no puede leer la jornada siguiente, Hoy dice '
        'qué hacer, el botón vuelve y el próximo toque lleva a la corrección', (tester) async {
      final ds = armar(extra: [siguienteDeLaNoche])..fallan.add(2);
      final moverReloj = await _hoyConHoraVieja(tester, ds);
      expect(find.text('23:45 · hace 5 min'), findsOneWidget);
      moverReloj(_despuesDeMedianoche);

      await _tocarFinalizar(tester);

      expect(ds.llamadas, 2, reason: 'una vuelta con la hora vieja y otra sin ella');
      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('jornada_error_fin')),
          matching: find.textContaining('No pudimos guardar el fin de tu jornada'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Probá de nuevo'), findsOneWidget);
      expect(_botonFinalizar(tester).onPressed, isNotNull);
      expect(find.text('Finalizando…'), findsNothing);
      expect(find.textContaining('23:45'), findsNothing, reason: 'la hora vieja ya se soltó');
      expect(ds._real.escrituras, 0);
      expect(ds._real.jornadas.where((j) => j.estaAbierta), hasLength(1));

      // Reintento (la lectura anda): una sola vuelta, directo a la corrección con el tope.
      await _tocarFinalizar(tester);
      expect(ds.llamadas, 3);
      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      await tester.tap(_botonElegir);
      await tester.pumpAndSettle();
      expect(find.text('Entre las 22:01 y las 23:30.'), findsOneWidget);
    });

    testWidgets('falla en la primera vuelta: se conserva la hora elegida y el reintento anda', (
      tester,
    ) async {
      final ds = armar(extra: [siguienteDeLaNoche])..fallan.add(1);
      final moverReloj = await _hoyConHoraVieja(tester, ds);
      moverReloj(_despuesDeMedianoche);

      await _tocarFinalizar(tester);

      expect(ds.llamadas, 1);
      expect(find.byKey(const Key('jornada_error_fin')), findsOneWidget);
      expect(_botonFinalizar(tester).onPressed, isNotNull);
      expect(find.text('Finalizando…'), findsNothing);
      expect(find.byType(CorregirJornadaPage), findsNothing);

      await _tocarFinalizar(tester);
      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(ds._real.escrituras, 0);
    });

    testWidgets('acciones superpuestas: mientras corren las dos vueltas, «Finalizar jornada» queda '
        'apagado en «Finalizando…» y un toque más no lee ni escribe de nuevo', (tester) async {
      final ds = armar(extra: [siguienteDeLaNoche]);
      final primera = ds.retienen[1] = Completer<void>();
      final segunda = ds.retienen[2] = Completer<void>();
      final moverReloj = await _hoyConHoraVieja(tester, ds);
      moverReloj(_despuesDeMedianoche);

      await tester.ensureVisible(_finalizarHoy);
      await tester.tap(_finalizarHoy);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Finalizando…'), findsOneWidget);
      expect(_botonFinalizar(tester).onPressed, isNull);
      await tester.tap(_finalizarHoy, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ds.llamadas, 1);

      // Pasa a la segunda vuelta (sin la hora vieja) y sigue apagado.
      primera.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(ds.llamadas, 2);
      expect(find.text('Finalizando…'), findsOneWidget);
      expect(_botonFinalizar(tester).onPressed, isNull);
      await tester.tap(_finalizarHoy, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ds.llamadas, 2);

      segunda.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CorregirJornadaPage), findsOneWidget, reason: 'una sola corrección');
      expect(ds._real.escrituras, 0);
      expect(find.text('--:--'), findsOneWidget, reason: 'la hora vieja no pasó a la corrección');
    });

    for (final (nombre, tamano, escala) in matriz) {
      testWidgets('$nombre: el aviso de la falla de la segunda vuelta entra en pantalla y no hay '
          'overflow', (tester) async {
        final ds = armar(extra: [siguienteDeLaNoche])..fallan.add(2);
        final moverReloj = await _hoyConHoraVieja(tester, ds, tamano: tamano, escala: escala);
        moverReloj(_despuesDeMedianoche);
        await _tocarFinalizar(tester);

        expect(tester.takeException(), isNull);
        final aviso = find.byKey(const Key('jornada_error_fin'));
        await tester.ensureVisible(aviso);
        await tester.pump();
        expect(tester.getRect(aviso).right, lessThanOrEqualTo(tamano.width));
        await tester.ensureVisible(_finalizarHoy);
        await tester.pump();
        expect(tester.getSize(_finalizarHoy).height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('con la jornada siguiente en el mismo minuto y la hora vieja, el cierre normal '
        'sigue sin escribir y los toques repetidos no apilan pantallas', (tester) async {
      final ds = armar(extra: [_cerradaQa(_inicioNoche.add(const Duration(seconds: 30)))]);
      final moverReloj = await _hoyConHoraVieja(tester, ds);
      moverReloj(_despuesDeMedianoche);

      for (var i = 0; i < 3; i++) {
        await _tocarFinalizar(tester);
        expect(find.byType(CorregirJornadaPage), findsOneWidget);
        expect(find.byKey(const Key('corregir_jornada_sin_hora_siguiente')), findsOneWidget);
        await tester.tap(_flecha);
        await tester.pumpAndSettle();
        expect(find.byType(CorregirJornadaPage), findsNothing);
        expect(_botonFinalizar(tester).onPressed, isNotNull);
      }
      expect(ds._real.escrituras, 0);
    });
  });

  group('21A·01 Hoy con la jornada de ayer abierta: «Cambiar ›» sin acción', () {
    Future<DataSourceQa> montarConJornadaDeAyer(WidgetTester tester) async {
      fijarPantallaQa(tester, telefonoGrandeQa);
      final ds = DataSourceQa();
      await _montarHoy(tester, [
        jornadaLocalDataSourceProvider.overrideWithValue(ds),
        disparadorBackupProvider.overrideWithValue(BackupQa()),
        relojJornadaProvider.overrideWithValue(() => ahoraQa),
        ...overridesPestanaMapa(),
      ]);
      await tester.pumpAndSettle();
      return ds;
    }

    testWidgets('la fila de la hora de fin no responde (la jornada quedó abierta: no hay hora a '
        'mano en Hoy, la corrección es otra pantalla)', (tester) async {
      await montarConJornadaDeAyer(tester);

      await tester.ensureVisible(find.text('Cambiar ›'));
      await tester.tap(find.text('Cambiar ›'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_valor')), findsNothing);
      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(_botonFinalizar(tester).onPressed, isNotNull);
    });

    testWidgets('«Cambiar ›» sin acción se ve apagado, como «Elegir la hora» de la corrección '
        '(regla de la decisión de #336, P1)', (tester) async {
      await montarConJornadaDeAyer(tester);

      final cambiar = tester.widget<Text>(find.text('Cambiar ›'));
      final primario = Theme.of(tester.element(find.text('Cambiar ›'))).colorScheme.primary;
      expect(cambiar.style!.color, isNot(primario));
    }, skip: true); // skip: QA #339 — «Cambiar ›» sin acción se pinta con el color primario
  });

  if (_conCapturas) {
    group('Capturas (QA_CAPTURAS)', () {
      for (final (nombre, tamano, escala) in matriz) {
        final etiqueta = nombre.replaceAll(' ', '_');
        testWidgets('captura 21A·08 aviso a mitad de camino · $nombre', (tester) async {
          await cargarFuentesQa(tester);
          await _conSiguienteQueLlega(
            tester,
            siguiente: _siguienteMismoMinuto,
            tamano: tamano,
            escala: escala,
          );
          await _capturar(tester, 'a08_aviso_$etiqueta');
        });
        testWidgets('captura 21A·03 rango recortado · $nombre', (tester) async {
          await cargarFuentesQa(tester);
          await _conSiguienteQueLlega(
            tester,
            siguiente: _siguienteALas19,
            tamano: tamano,
            escala: escala,
          );
          await _capturar(tester, 'a03_recortado_$etiqueta');
        });
        testWidgets('captura Hoy falla segunda vuelta · $nombre', (tester) async {
          await cargarFuentesQa(tester);
          final ds = _DataSourceSiguiente(
            DataSourceQa(
              iniciales: [
                jornadaAbiertaQa(_inicioNoche),
                _cerradaQa(DateTime(2026, 9, 23, 23, 30)),
              ],
            ),
          )..fallan.add(2);
          final moverReloj = await _hoyConHoraVieja(tester, ds, tamano: tamano, escala: escala);
          moverReloj(_despuesDeMedianoche);
          await _tocarFinalizar(tester);
          await tester.ensureVisible(find.byKey(const Key('jornada_error_fin')));
          await tester.pump();
          await _capturar(tester, 'hoy_falla_$etiqueta');
        });
      }
      testWidgets('captura 21A·08 reloj dentro del minuto del inicio · 360x640', (tester) async {
        await cargarFuentesQa(tester);
        fijarPantallaQa(tester, telefonoChicoQa);
        await montarQa(
          tester,
          DataSourceQa(),
          reloj: () => inicioQa.add(const Duration(seconds: 30)),
        );
        await abrirCorregirQa(tester);
        await _capturar(tester, 'a08_reloj_en_minuto_360x640');
      });
      testWidgets('captura hoja con el rango viejo · 412x915', (tester) async {
        await cargarFuentesQa(tester);
        await _conSiguienteQueLlega(tester, siguiente: _siguienteALas19);
        await abrirHojaQa(tester);
        await _capturar(tester, 'a02_hoja_rango_viejo_412x915');
      });
    });
  }
}
