// QA del PR #336 (#327, seguimiento de #326; vista 21A «Jornada sin cerrar»): lo que las pruebas del
// implementador (`corregir_jornada_page_test.dart`) no cubren. Matriz de tamaños (360x640 y 412x915,
// texto 1.0 y 2.0) en los estados nuevos —el aviso de «la siguiente empezó a la misma hora», el del
// reloj atrasado, la hoja con la nota del día siguiente y el botón «Finalizando…»—, accesibilidad
// (toque, etiquetas, contraste, `liveRegion`), el texto literal con la hora en la zona del
// dispositivo, el rango de un solo minuto y los cambios de estado con la pantalla abierta.
// Los textos son los de la decisión de #327 (https://github.com/Colportores/front-colportores-mobile/issues/327#issuecomment-6091556580)
// y los del canvas 21A·08 / 21A·04.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/jornada_sin_cerrar.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/corregir_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/qa_jornada_sin_cerrar_250_arnes.dart';

/// Los casos de borde de una jornada siguiente que llega con la pantalla abierta pasan al S7:
/// necesitan que el motor de sync (#175) traiga la jornada, y no pierden nada. El `skip` de
/// `testWidgets` no admite un texto: el motivo es el issue #339.
const _pasaAlS7 = true;

/// Lunes 21 18:00:30: la jornada siguiente empezó en el mismo minuto que `inicioQa` (18:00).
final _siguienteMismoMinuto = inicioQa.add(const Duration(seconds: 30));

/// Martes 22 03:00: la jornada siguiente topa el fin antes de las 12 h (las 06:00).
final _siguienteMadrugada = DateTime(2026, 9, 22, 3);

/// Lunes 21 23:30: la jornada siguiente topa el fin el mismo día del inicio.
final _siguienteNoche = DateTime(2026, 9, 21, 23, 30);

JornadaModel _cerradaQa(DateTime inicio, {Duration duracion = const Duration(hours: 1)}) =>
    JornadaModel.fromEntity(
      Jornada(
        id: 'jor-siguiente',
        colportorId: sesionQa.usuarioId,
        inicio: inicio,
        fin: inicio.add(duracion),
        auditoria: Auditoria(
          createdAt: inicio,
          updatedAt: inicio.add(duracion),
          createdBy: sesionQa.usuarioId,
        ),
      ),
    );

DataSourceQa _dataSourceConSiguiente(DateTime? siguiente, {DateTime? inicio}) => DataSourceQa(
  iniciales: [jornadaAbiertaQa(inicio), ?(siguiente == null ? null : _cerradaQa(siguiente))],
);

/// Los estados nuevos de #327 a los que se llega desde la pantalla.
enum _Estado {
  mismoMinuto('la siguiente empezó en el mismo minuto (21A·08, aviso nuevo)'),
  relojAtrasado('reloj atrasado (21A·08, aviso)'),
  conTopeDeLaSiguiente('hora elegida bajo el tope de la siguiente'),
  hojaConNota('hoja de ajuste con la nota del día siguiente (21A·02)'),
  hojaOtraFueraDelTope('hoja «Otra hora» fuera del tope de la siguiente (21A·03)'),
  cerrando('cerrando, «Finalizando…» (21A·04)');

  const _Estado(this.rotulo);
  final String rotulo;
}

/// Monta la pantalla y la deja en [estado]. Devuelve el almacenamiento para mirar lo guardado.
Future<DataSourceQa> _armar(
  WidgetTester tester,
  _Estado estado, {
  Size tamano = telefonoGrandeQa,
  double escala = 1,
}) async {
  fijarPantallaQa(tester, tamano);
  final siguiente = switch (estado) {
    _Estado.mismoMinuto => _siguienteMismoMinuto,
    _Estado.relojAtrasado => null,
    _Estado.conTopeDeLaSiguiente => _siguienteNoche,
    _Estado.hojaConNota || _Estado.hojaOtraFueraDelTope || _Estado.cerrando => _siguienteMadrugada,
  };
  final ds = _dataSourceConSiguiente(siguiente);
  await montarQa(
    tester,
    ds,
    escala: EscalaQa(escala),
    reloj: estado == _Estado.relojAtrasado ? () => DateTime(2026, 9, 21, 12) : null,
  );
  await abrirCorregirQa(tester, inicioSiguiente: siguiente);
  switch (estado) {
    case _Estado.mismoMinuto || _Estado.relojAtrasado:
      break;
    case _Estado.conTopeDeLaSiguiente:
      await elegirHoraQa(tester, '23:30');
    case _Estado.hojaConNota:
      // La hoja arranca en la hora más temprana; con una hora de la madrugada ya elegida, vuelve a
      // abrirse en ella y la nota del día siguiente aparece.
      await elegirHoraQa(tester, '02:00');
      await abrirHojaQa(tester);
    case _Estado.hojaOtraFueraDelTope:
      await abrirHojaQa(tester);
      await escribirEnHojaQa(tester, '03:01');
    case _Estado.cerrando:
      await elegirHoraQa(tester, '02:00');
      ds.demoraFinalizar = Completer<void>();
      await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      // El indicador de progreso anima sin parar: `pumpAndSettle` no termina.
      await tester.pump(const Duration(milliseconds: 100));
  }
  return ds;
}

/// La pestaña Hoy de la app (21A·01 / 21A·04), con la jornada de [ds] y el reloj de [reloj].
Future<void> _montarHoy(
  WidgetTester tester,
  DataSourceQa ds, {
  DateTime? reloj,
  double escala = 1,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      jornadaLocalDataSourceProvider.overrideWithValue(ds),
      disparadorBackupProvider.overrideWithValue(BackupQa()),
      relojJornadaProvider.overrideWithValue(() => reloj ?? ahoraQa),
      ...overridesPestanaMapa(),
    ],
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

Future<void> _tocarFinalizarHoy(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
  await tester.tap(find.byKey(const Key('jornada_finalizar')));
  await tester.pumpAndSettle();
}

/// El almacenamiento de [DataSourceQa] con la lectura de «la jornada siguiente» que puede fallar.
final class _DataSourceSiguienteFalla implements JornadaLocalDataSource {
  _DataSourceSiguienteFalla(this._real);

  final DataSourceQa _real;
  bool falla = true;

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) {
    if (falla) throw StateError('disco ilegible');
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
final _avisoReloj = find.byKey(const Key('corregir_jornada_reloj_atrasado'));
final _botonElegir = find.byKey(const Key('corregir_jornada_elegir_hora'));
final _flecha = find.byKey(const Key('corregir_jornada_atras'));

String _dosDigitos(int n) => n.toString().padLeft(2, '0');

String _hhmmLocal(DateTime instante) {
  final local = instante.toLocal();
  return '${_dosDigitos(local.hour)}:${_dosDigitos(local.minute)}';
}

/// Contraste WCAG entre dos colores opacos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Contraste real (WCAG) de la etiqueta de un botón, con los colores que ya resolvió el árbol:
/// el del texto (con su opacidad) sobre el relleno del botón, y éste sobre el fondo de la pantalla.
double _contrasteDeLaEtiqueta(WidgetTester tester, Finder etiqueta) {
  final colorTexto = tester.renderObject<RenderParagraph>(etiqueta).text.style!.color!;
  final boton = find.ancestor(of: etiqueta, matching: find.byType(FilledButton)).first;
  final material = tester.widget<Material>(
    find.descendant(of: boton, matching: find.byType(Material)).first,
  );
  final pantalla = Theme.of(tester.element(etiqueta)).scaffoldBackgroundColor;
  final fondo = Color.alphaBlend(material.color ?? const Color(0x00000000), pantalla);
  return _contraste(Color.alphaBlend(colorTexto, fondo), fondo);
}

void main() {
  group('Matriz de tamaños: 360x640 y 412x915, con el texto al 1.0 y al 2.0 (checklist 7)', () {
    const matriz = <(String, Size, double)>[
      ('360x640 texto 1.0', telefonoChicoQa, 1),
      ('360x640 texto 2.0', telefonoChicoQa, 2),
      ('412x915 texto 1.0', telefonoGrandeQa, 1),
      ('412x915 texto 2.0', telefonoGrandeQa, 2),
    ];
    for (final (nombre, tamano, escala) in matriz) {
      for (final estado in _Estado.values) {
        testWidgets(
          '$nombre · ${estado.rotulo}: sin overflow y los avisos y el botón se alcanzan',
          (tester) async {
            final ds = await _armar(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 100));

            expect(tester.takeException(), isNull);
            // El aviso nuevo y el del reloj se leen enteros: con el desplazamiento, el aviso queda
            // dentro de la pantalla (ni cortado a los costados ni más ancho que ella).
            for (final aviso in [
              if (estado == _Estado.mismoMinuto) _avisoSiguiente,
              if (estado == _Estado.relojAtrasado) _avisoReloj,
            ]) {
              expect(aviso, findsOneWidget);
              await tester.ensureVisible(aviso);
              await tester.pump();
              final caja = tester.getRect(aviso);
              expect(caja.left, greaterThanOrEqualTo(0));
              expect(caja.right, lessThanOrEqualTo(tamano.width));
            }
            if (estado == _Estado.cerrando) ds.demoraFinalizar!.complete();
          },
        );
      }
    }
  });

  group('Accesibilidad (checklist 6) en los estados nuevos', () {
    for (final tamano in [telefonoChicoQa, telefonoGrandeQa]) {
      for (final estado in _Estado.values) {
        testWidgets(
          '${tamano.width.toInt()}x${tamano.height.toInt()} · ${estado.rotulo}: tamaño de toque, '
          'etiquetas y contraste',
          (tester) async {
            final semantica = tester.ensureSemantics();
            final ds = await _armar(tester, estado, tamano: tamano);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            expect(tester.takeException(), isNull);
            if (estado == _Estado.cerrando) ds.demoraFinalizar!.complete();
            semantica.dispose();
          },
        );
      }
    }

    testWidgets('los dos avisos se anuncian (liveRegion) con el texto literal en la semántica', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _armar(tester, _Estado.mismoMinuto);
      final siguiente = tester.getSemantics(_avisoSiguiente);
      expect(siguiente, isSemantics(isLiveRegion: true));
      expect(
        siguiente.label,
        contains(
          'Esta jornada y la siguiente empezaron a la misma hora (18:00), así que no hay una hora '
          'para cerrarla. Avisale a tu coordinador.',
        ),
      );

      await _armar(tester, _Estado.relojAtrasado);
      final reloj = tester.getSemantics(_avisoReloj);
      expect(reloj, isSemantics(isLiveRegion: true));
      expect(reloj.label, contains(JornadaSinCerrar.avisoRelojAtrasado));
      semantica.dispose();
    });

    testWidgets('con el aviso de la siguiente en el mismo minuto, «Elegir la hora» no se ofrece '
        'como botón activo (sin acción de toque) y la flecha sí', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armar(tester, _Estado.mismoMinuto);

      final elegir = tester.getSemantics(_botonElegir);
      expect(elegir.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      final flecha = tester.getSemantics(_flecha);
      expect(flecha.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(flecha.tooltip, 'Volver');
      semantica.dispose();
    });
  });

  group('Texto literal y husos horarios (checklist 1 y 3)', () {
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

    // Cada fila es un instante local distinto: el día entero en minúscula, la hora con ceros a la
    // izquierda y el cambio de día de la medianoche (HU-JOR-002 / canvas 21A·08).
    final casos = <(DateTime, String)>[
      (DateTime(2026, 9, 21, 0, 0), 'lunes 21 empezó a las 00:00'),
      (DateTime(2026, 9, 22, 8, 5), 'martes 22 empezó a las 08:05'),
      (DateTime(2026, 9, 23, 23, 59), 'miércoles 23 empezó a las 23:59'),
      (DateTime(2026, 9, 26, 12, 30), 'sábado 26 empezó a las 12:30'),
      (DateTime(2026, 9, 27, 14, 35), 'domingo 27 empezó a las 14:35'),
      (DateTime(2026, 12, 31, 23, 30), 'jueves 31 empezó a las 23:30'),
    ];
    for (final (inicio, esperado) in casos) {
      test('el aviso del día anterior dice «Tu jornada del $esperado y quedó abierta. Cerrala para '
          'empezar la de hoy.»', () {
        // Se pasa el instante en UTC, como lo guarda la base: el texto sale en la zona del
        // dispositivo (no en la de UTC).
        final mensaje = FailureJornadaDeDiaAnterior(inicio: inicio.toUtc()).mensaje;

        expect(
          mensaje,
          'Tu jornada del $esperado y quedó abierta. Cerrala para empezar la de hoy.',
        );
      });
    }

    test('un instante en UTC se dice con el día y la hora del dispositivo, no los de UTC', () {
      // 2026-09-29 02:30 UTC: en Montevideo (UTC-3) todavía es el lunes 28 a las 23:30.
      final inicio = DateTime.utc(2026, 9, 29, 2, 30);
      final local = inicio.toLocal();
      final esperado =
          'Tu jornada del ${dias[local.weekday - 1]} ${local.day} empezó a las ${_hhmmLocal(inicio)} '
          'y quedó abierta. Cerrala para empezar la de hoy.';

      expect(FailureJornadaDeDiaAnterior(inicio: inicio).mensaje, esperado);
      expect(
        JornadaSinCerrar.avisoSinHoraPorJornadaSiguiente(inicio),
        'Esta jornada y la siguiente empezaron a la misma hora (${_hhmmLocal(inicio)}), así que '
        'no hay una hora para cerrarla. Avisale a tu coordinador.',
      );
      if (inicio.toLocal().timeZoneOffset != Duration.zero) {
        // Con un huso distinto de UTC, la hora de UTC (02:30) no puede aparecer.
        expect(
          JornadaSinCerrar.avisoSinHoraPorJornadaSiguiente(inicio),
          isNot(contains('(02:30)')),
        );
      }
    });

    test('el aviso de la siguiente en el mismo minuto lleva la hora con dos dígitos y no cambia '
        'con los segundos del inicio', () {
      final a = DateTime(2026, 9, 21, 0, 5, 3);
      final b = DateTime(2026, 9, 21, 0, 5, 58);

      expect(
        JornadaSinCerrar.avisoSinHoraPorJornadaSiguiente(a),
        'Esta jornada y la siguiente empezaron a la misma hora (00:05), así que no hay una hora '
        'para cerrarla. Avisale a tu coordinador.',
      );
      expect(
        JornadaSinCerrar.avisoSinHoraPorJornadaSiguiente(a),
        JornadaSinCerrar.avisoSinHoraPorJornadaSiguiente(b),
      );
    });

    testWidgets('el aviso de la pantalla dice la hora del inicio de la jornada (zona del '
        'dispositivo), aunque llegue en UTC como de la base', (tester) async {
      fijarPantallaQa(tester, telefonoGrandeQa);
      final inicio = DateTime.utc(2026, 9, 22, 2, 30);
      final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(inicio)]);
      await montarQa(tester, ds, reloj: () => DateTime.utc(2026, 9, 22, 14));
      await abrirCorregirQa(
        tester,
        inicio: inicio,
        inicioSiguiente: inicio.add(const Duration(seconds: 20)),
      );

      expect(_avisoSiguiente, findsOneWidget);
      expect(
        find.textContaining('empezaron a la misma hora (${_hhmmLocal(inicio)})'),
        findsOneWidget,
      );
      expect(find.textContaining('después de las ${_hhmmLocal(inicio)}'), findsOneWidget);
    });
  });

  group('Rango de un solo minuto y bordes de la jornada siguiente (checklist 5b)', () {
    testWidgets('si la siguiente empieza justo un minuto después, queda una sola hora válida: la '
        'hoja la ofrece, −5 y +5 no se mueven y la jornada se cierra a ras de la siguiente', (
      tester,
    ) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      // Inicio 18:00, siguiente 18:01:00 exacto: el único minuto posible es el 18:01.
      final siguiente = DateTime(2026, 9, 21, 18, 1);
      final ds = _dataSourceConSiguiente(siguiente);
      await montarQa(tester, ds);
      final resultado = await abrirCorregirQa(tester, inicioSiguiente: siguiente);

      // Hay hora válida: no es el caso del aviso, la flecha no aparece y «Elegir la hora» sirve.
      expect(_avisoSiguiente, findsNothing);
      expect(_flecha, findsNothing);
      expect(tester.widget<InkWell>(_botonElegir).onTap, isNotNull);

      await abrirHojaQa(tester);
      expect(find.text('Entre las 18:01 y las 18:01.'), findsOneWidget);
      expect(find.text('Usar 18:01'), findsOneWidget);
      for (final clave in ['hoja_hora_menos', 'hoja_hora_mas']) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.descendant(of: find.byKey(Key(clave)), matching: find.byType(OutlinedButton)),
              )
              .onPressed,
          isNull,
          reason: '$clave: con un solo minuto no hay hacia dónde moverse',
        );
      }
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();
      expect(find.text('Terminé a las 18:01'), findsOneWidget);
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(resultado.recibido, isTrue);
      expect(ds.escrituras, 1);
      final cerrada = ds.jornadas.firstWhere((j) => j.id == 'jor-previa');
      expect(cerrada.fin!.toLocal(), DateTime(2026, 9, 21, 18, 1));
    });

    testWidgets('la siguiente empieza 59 segundos después en el mismo minuto: aviso, no una hora '
        'inventada ni una hoja vacía', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      final inicio = DateTime(2026, 9, 21, 18, 0, 0, 500);
      final siguiente = DateTime(2026, 9, 21, 18, 0, 59, 900);
      final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(inicio), _cerradaQa(siguiente)]);
      await montarQa(tester, ds);
      await abrirCorregirQa(tester, inicio: inicio, inicioSiguiente: siguiente);

      expect(_avisoSiguiente, findsOneWidget);
      await tester.tap(_botonElegir, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(ds.escrituras, 0);
    });

    testWidgets('el reloj se arregla con la pantalla abierta y la siguiente está en el mismo '
        'minuto: el aviso del reloj da paso al de la siguiente al volver a tocar «Elegir la '
        'hora»', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      var ahora = DateTime(2026, 9, 21, 12);
      final ds = _dataSourceConSiguiente(_siguienteMismoMinuto);
      await montarQa(tester, ds, reloj: () => ahora);
      await abrirCorregirQa(tester, inicioSiguiente: _siguienteMismoMinuto);

      expect(_avisoReloj, findsOneWidget);
      expect(_avisoSiguiente, findsNothing);

      ahora = DateTime(2026, 9, 22, 8);
      await tester.tap(_botonElegir);
      await tester.pumpAndSettle();

      expect(_avisoReloj, findsNothing);
      expect(_avisoSiguiente, findsOneWidget);
      expect(tester.widget<InkWell>(_botonElegir).onTap, isNull);
      expect(_flecha, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el reloj sale del atraso y la siguiente deja horas libres: el aviso desaparece, '
        '«Elegir la hora» abre la hoja y se cierra con una hora válida', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      var ahora = DateTime(2026, 9, 21, 12);
      final ds = _dataSourceConSiguiente(_siguienteNoche);
      await montarQa(tester, ds, reloj: () => ahora);
      final resultado = await abrirCorregirQa(tester, inicioSiguiente: _siguienteNoche);
      expect(_avisoReloj, findsOneWidget);
      expect(_flecha, findsOneWidget);

      ahora = DateTime(2026, 9, 22, 8);
      await tester.tap(_botonElegir);
      await tester.pumpAndSettle();

      expect(_avisoReloj, findsNothing);
      expect(_flecha, findsNothing);
      expect(find.text('Entre las 18:01 y las 23:30.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(resultado.recibido, isTrue);
      expect(ds.escrituras, 1);
    });

    testWidgets('con la siguiente en el mismo minuto, el atrás del sistema sale de la pantalla y '
        'no escribe nada', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      final ds = _dataSourceConSiguiente(_siguienteMismoMinuto);
      await montarQa(tester, ds);
      final resultado = await abrirCorregirQa(tester, inicioSiguiente: _siguienteMismoMinuto);

      await navegadorQa.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(resultado.recibido, isTrue);
      expect(resultado.valor, isNull);
      expect(ds.escrituras, 0);
      expect(ds.jornadas.firstWhere((j) => j.id == 'jor-previa').estaAbierta, isTrue);
    });
  });

  group('Botón «Finalizando…» (21A·04): alineación y legibilidad del spinner', () {
    for (final (nombre, tamano, escala) in const [
      ('360x640 texto 1.0', telefonoChicoQa, 1.0),
      ('360x640 texto 2.0', telefonoChicoQa, 2.0),
      ('412x915 texto 1.0', telefonoGrandeQa, 1.0),
    ]) {
      testWidgets('$nombre: el spinner y el texto van en la misma línea y el conjunto queda '
          'centrado en el botón', (tester) async {
        await _armar(tester, _Estado.cerrando, tamano: tamano, escala: escala);

        final boton = find.byKey(const Key('corregir_jornada_cerrar'));
        final spinner = find.descendant(
          of: boton,
          matching: find.byType(CircularProgressIndicator),
        );
        final texto = find.descendant(of: boton, matching: find.text('Finalizando…'));
        expect(spinner, findsOneWidget);
        expect(texto, findsOneWidget);

        final cajaBoton = tester.getRect(boton);
        final cajaSpinner = tester.getRect(spinner);
        final cajaTexto = tester.getRect(texto);
        expect(
          (cajaSpinner.center.dy - cajaTexto.center.dy).abs(),
          lessThanOrEqualTo(1.5),
          reason: 'el spinner y el texto comparten el centro vertical',
        );
        expect(cajaSpinner.right, lessThanOrEqualTo(cajaTexto.left));
        final margenIzquierdo = cajaSpinner.left - cajaBoton.left;
        final margenDerecho = cajaBoton.right - cajaTexto.right;
        expect(
          (margenIzquierdo - margenDerecho).abs(),
          lessThanOrEqualTo(1.5),
          reason: 'spinner + texto centrados horizontalmente en el botón',
        );
        expect(cajaSpinner.top, greaterThanOrEqualTo(cajaBoton.top));
        expect(cajaSpinner.bottom, lessThanOrEqualTo(cajaBoton.bottom));
        expect(cajaBoton.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el spinner (onPrimary, como la etiqueta) sobre el fondo del botón mientras '
        'trabaja supera 3:1 (WCAG 1.4.11, componentes de interfaz)', (tester) async {
      await _armar(tester, _Estado.cerrando);
      // Con la transición del botón apagado ya terminada.
      await tester.pump(const Duration(seconds: 1));

      final boton = find.byKey(const Key('corregir_jornada_cerrar'));
      final tema = Theme.of(tester.element(boton));
      // El fondo real del botón (primary al 85 %, ver `ConEspera.estiloDelBoton`) sobre la pantalla.
      final material = tester.widget<Material>(
        find.descendant(of: boton, matching: find.byType(Material)).first,
      );
      final fondo = Color.alphaBlend(
        material.color ?? const Color(0x00000000),
        tema.scaffoldBackgroundColor,
      );
      final indicador = tester.widget<CircularProgressIndicator>(
        find.descendant(of: boton, matching: find.byType(CircularProgressIndicator)),
      );
      final colorSpinner =
          indicador.color ?? tema.progressIndicatorTheme.color ?? tema.colorScheme.primary;

      expect(colorSpinner, tema.colorScheme.onPrimary);
      expect(_contraste(colorSpinner, fondo), greaterThanOrEqualTo(3));
    });

    testWidgets('mientras cierra, el botón conserva su nombre «Finalizando…» para el lector y el '
        'aviso del error anterior no se ve', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armar(tester, _Estado.cerrando);

      final boton = tester.getSemantics(find.byKey(const Key('corregir_jornada_cerrar')));
      expect(boton.label, contains('Finalizando…'));
      expect(find.byKey(const Key('corregir_jornada_error')), findsNothing);
      semantica.dispose();
    });
  });

  group('Hoja de ajuste con la nota (21A·02): alineación de −5 / +5 con la hora', () {
    for (final (nombre, tamano, escala) in const [
      ('360x640 texto 1.0', telefonoChicoQa, 1.0),
      ('360x640 texto 2.0', telefonoChicoQa, 2.0),
      ('412x915 texto 1.0', telefonoGrandeQa, 1.0),
      ('412x915 texto 2.0', telefonoGrandeQa, 2.0),
    ]) {
      testWidgets('$nombre: −5 y +5 se centran con la hora y la nota queda debajo de la fila', (
        tester,
      ) async {
        await _armar(tester, _Estado.hojaConNota, tamano: tamano, escala: escala);

        final nota = find.byKey(const Key('hoja_hora_nota'));
        expect(nota, findsOneWidget);
        expect(tester.widget<Text>(nota).data, 'Termina el martes 22, al día siguiente.');
        final valor = tester.getRect(find.byKey(const Key('hoja_hora_valor')));
        final menos = tester.getRect(find.byKey(const Key('hoja_hora_menos')));
        final mas = tester.getRect(find.byKey(const Key('hoja_hora_mas')));
        final cajaNota = tester.getRect(nota);

        expect((menos.center.dy - valor.center.dy).abs(), lessThanOrEqualTo(1.5));
        expect((mas.center.dy - valor.center.dy).abs(), lessThanOrEqualTo(1.5));
        expect(cajaNota.top, greaterThanOrEqualTo(valor.bottom));
        expect(cajaNota.top, greaterThanOrEqualTo(menos.bottom));
        expect(cajaNota.top, greaterThanOrEqualTo(mas.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('al pasar de una hora del día siguiente a una del mismo día, la nota se va y −5 y '
        '+5 no se corren', (tester) async {
      await _armar(tester, _Estado.hojaConNota, tamano: telefonoChicoQa, escala: 2);
      final antes = tester.getRect(find.byKey(const Key('hoja_hora_menos')));

      // De las 02:00 del martes a las 23:55 del lunes son 25 toques de −5: la nota (martes)
      // desaparece al cruzar la medianoche.
      for (var i = 0; i < 25; i++) {
        await tester.tap(find.byKey(const Key('hoja_hora_menos')));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_nota')), findsNothing);
      final despues = tester.getRect(find.byKey(const Key('hoja_hora_menos')));
      expect(
        despues.top,
        antes.top,
        reason: 'sin la nota la fila de la hora no se mueve de arriba',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('teclado abierto en «Otra hora» (280 dp) a 360x640 con texto 2.0: sin overflow y '
        'el campo y el aviso del rango siguen alcanzables', (tester) async {
      await _armar(tester, _Estado.hojaOtraFueraDelTope, tamano: telefonoChicoQa, escala: 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('La hora tiene que estar entre las 18:01 y las 03:00.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Desde Hoy hasta el cierre, con la jornada siguiente (checklist 1, 5 y 5b)', () {
    testWidgets('con una siguiente a las 03:00, Finalizar lleva a la corrección con el rango de '
        'las 18:01 a las 03:00 y cerrar a las 02:30 vuelve a Hoy con la jornada cerrada', (
      tester,
    ) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      final ds = _dataSourceConSiguiente(_siguienteMadrugada);
      await _montarHoy(tester, ds);
      await tester.pumpAndSettle();

      await _tocarFinalizarHoy(tester);

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(_avisoSiguiente, findsNothing);
      expect(
        find.text(
          'Tu jornada del lunes 21 empezó a las 18:00 y quedó abierta. Cerrala para '
          'empezar la de hoy.',
        ),
        findsOneWidget,
      );
      await elegirHoraQa(tester, '02:30');
      expect(find.text('Terminé a las 02:30'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(ds.escrituras, 1);
      final cerrada = ds.jornadas.firstWhere((j) => j.id == 'jor-previa');
      expect(cerrada.fin!.toLocal(), DateTime(2026, 9, 22, 2, 30));
      expect(find.text('JORNADA FINALIZADA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la siguiente en el mismo minuto, Finalizar muestra el aviso nuevo, la flecha '
        'vuelve a Hoy con la jornada abierta y se puede volver a entrar sin trabarse', (
      tester,
    ) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      final ds = _dataSourceConSiguiente(_siguienteMismoMinuto);
      await _montarHoy(tester, ds);
      await tester.pumpAndSettle();

      for (var vuelta = 0; vuelta < 2; vuelta++) {
        await _tocarFinalizarHoy(tester);
        expect(find.byType(CorregirJornadaPage), findsOneWidget, reason: 'entrada ${vuelta + 1}');
        expect(_avisoSiguiente, findsOneWidget);
        expect(botonCerrarQa(tester).onPressed, isNull);

        await tester.tap(_flecha);
        await tester.pumpAndSettle();

        expect(find.byType(CorregirJornadaPage), findsNothing);
        expect(find.byKey(const Key('jornada_finalizar')), findsOneWidget);
        expect(find.text('JORNADA FINALIZADA'), findsNothing);
      }
      expect(ds.escrituras, 0);
      expect(ds.jornadas.firstWhere((j) => j.id == 'jor-previa').estaAbierta, isTrue);
    });

    testWidgets('«Finalizando…» en Hoy (21A·04): el botón dice qué pasa, está apagado y el mismo '
        'conjunto spinner + texto queda centrado', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(DateTime(2026, 9, 22, 7, 30))])
        ..demoraFinalizar = Completer<void>();
      await _montarHoy(tester, ds);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
      await tester.tap(find.byKey(const Key('jornada_finalizar')));
      await tester.pump(const Duration(milliseconds: 100));

      final boton = find.byKey(const Key('jornada_finalizar'));
      expect(find.text('Finalizando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(boton).onPressed, isNull);
      final spinner = find.descendant(of: boton, matching: find.byType(CircularProgressIndicator));
      final texto = find.descendant(of: boton, matching: find.text('Finalizando…'));
      expect(
        (tester.getRect(spinner).center.dy - tester.getRect(texto).center.dy).abs(),
        lessThan(1.5),
      );
      final cajaBoton = tester.getRect(boton);
      expect(
        ((tester.getRect(spinner).left - cajaBoton.left) -
                (cajaBoton.right - tester.getRect(texto).right))
            .abs(),
        lessThan(1.5),
      );
      expect(tester.takeException(), isNull);
      ds.demoraFinalizar!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('Falla a mitad del flujo con la jornada siguiente (checklist 5b)', () {
    testWidgets('si falla la lectura de la jornada siguiente, Hoy dice qué hacer, no se traba y '
        'al reintentar entra a la corrección', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      final real = _dataSourceConSiguiente(_siguienteMadrugada);
      final ds = _DataSourceSiguienteFalla(real);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jornadaLocalDataSourceProvider.overrideWithValue(ds),
            disparadorBackupProvider.overrideWithValue(BackupQa()),
            relojJornadaProvider.overrideWithValue(() => ahoraQa),
            ...overridesPestanaMapa(),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: InicioPage(sesion: sesionQa),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tocarFinalizarHoy(tester);

      expect(find.byType(CorregirJornadaPage), findsNothing);
      expect(find.textContaining('No pudimos guardar el fin de tu jornada'), findsOneWidget);
      expect(find.textContaining('Probá de nuevo'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('jornada_finalizar'))).onPressed,
        isNotNull,
        reason: 'el botón vuelve a habilitarse',
      );
      expect(find.text('Finalizando…'), findsNothing);
      expect(real.escrituras, 0);

      ds.falla = false;
      await _tocarFinalizarHoy(tester);

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.textContaining('No pudimos guardar el fin de tu jornada'), findsNothing);
    });
  });

  group('Hallazgos de QA (el primero arreglado; los otros dos pasan al S7)', () {
    // QA #327 (PR #336), arreglado en la ronda única: la etiqueta «Finalizando…» salía a ~1.9:1 al
    // terminar la transición del botón apagado (gris al 38 % de Material sobre azul al 50 %). El
    // canvas 21A·04 la pinta en blanco sobre el azul al 85 %, y así queda ahora (`ConEspera`).
    testWidgets('«Finalizando…» de la corrección se lee: contraste de texto (WCAG 1.4.3)', (
      tester,
    ) async {
      final ds = await _armar(tester, _Estado.cerrando, tamano: telefonoGrandeQa);
      // Con la transición del botón ya terminada: es lo que ve la persona los segundos que dura.
      await tester.pump(const Duration(seconds: 1));

      expect(
        _contrasteDeLaEtiqueta(
          tester,
          find.descendant(
            of: find.byKey(const Key('corregir_jornada_cerrar')),
            matching: find.text('Finalizando…'),
          ),
        ),
        greaterThanOrEqualTo(4.5),
      );
      ds.demoraFinalizar!.complete();
    });

    // Ídem en Hoy (21A·04), que comparte `ConEspera` y el estilo del botón mientras trabaja.
    testWidgets('«Finalizando…» de Hoy se lee: contraste de texto (WCAG 1.4.3)', (tester) async {
      fijarPantallaQa(tester, telefonoGrandeQa);
      final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(DateTime(2026, 9, 22, 7, 30))])
        ..demoraFinalizar = Completer<void>();
      await _montarHoy(tester, ds);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
      await tester.tap(find.byKey(const Key('jornada_finalizar')));
      await tester.pump(const Duration(milliseconds: 100));
      // Con la transición del botón ya terminada.
      await tester.pump(const Duration(seconds: 1));

      expect(
        _contrasteDeLaEtiqueta(
          tester,
          find.descendant(
            of: find.byKey(const Key('jornada_finalizar')),
            matching: find.text('Finalizando…'),
          ),
        ),
        greaterThanOrEqualTo(4.5),
      );
      ds.demoraFinalizar!.complete();
    });

    // skip, pasa al S7 (#339) — si cuando se cierra ya hay una jornada siguiente en el mismo
    // minuto del inicio y la pantalla se abrió sin ella (foto vieja), el aviso dice «entre las
    // 18:01 y las 18:00»: un rango al revés que no le sirve a nadie (el caso de uso no lo cuida).
    testWidgets('una siguiente que llega con la pantalla abierta no deja un rango invertido en el '
        'aviso', (tester) async {
      fijarPantallaQa(tester, telefonoChicoQa);
      // La pantalla se abrió con la foto «sin siguiente»; al cerrar, la base ya tiene una que
      // empezó a las 18:00:30 (la trajo el motor de sync mientras tanto).
      final ds = DataSourceQa(
        iniciales: [jornadaAbiertaQa(), _cerradaQa(DateTime(2026, 9, 21, 18, 0, 30))],
      );
      await montarQa(tester, ds);
      await abrirCorregirQa(tester);
      await elegirHoraQa(tester, '20:00');

      await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.pumpAndSettle();

      expect(find.textContaining('entre las 18:01 y las 18:00'), findsNothing);
    }, skip: _pasaAlS7);

    // skip, pasa al S7 (#339) — en ese mismo caso la pantalla no ofrece salida: sin flecha (la foto
    // vieja dice que hay hora válida) y con el atrás del sistema bloqueado por el PopScope.
    testWidgets(
      'una siguiente que llega con la pantalla abierta no deja la pantalla sin salida',
      (tester) async {
        fijarPantallaQa(tester, telefonoChicoQa);
        final ds = DataSourceQa(
          iniciales: [jornadaAbiertaQa(), _cerradaQa(DateTime(2026, 9, 21, 18, 0, 30))],
        );
        await montarQa(tester, ds);
        final resultado = await abrirCorregirQa(tester);
        await elegirHoraQa(tester, '20:00');
        await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
        await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
        await tester.pumpAndSettle();

        final hayFlecha = _flecha.evaluate().isNotEmpty;
        await navegadorQa.currentState!.maybePop();
        await tester.pumpAndSettle();

        expect(hayFlecha || resultado.recibido, isTrue, reason: 'tiene que haber una salida');
      },
      skip: _pasaAlS7,
    );
  });
}
