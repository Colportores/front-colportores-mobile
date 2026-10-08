// QA del PR #326 (#250, vista 21 «A08» + la pantalla «¿A qué hora terminaste?»): lo que la prueba
// del implementador (`corregir_jornada_page_test.dart`) no cubre. Matriz de tamaños (360x640 y
// 412x915, texto 1.0 y 2.0), accesibilidad en los estados que faltaban (error al guardar, cerrando),
// validación exhaustiva de «Otra hora», el recorrido de −5/+5 y el cruce de la medianoche, la
// navegación con la hoja abierta, acciones superpuestas y bordes de calendario (fin de mes y de año).
// Los textos literales son los de la HU-JOR-002 y la decisión de Cristian del 30/09; el día del fin va
// entero («martes 22», decisión del 08/10 sobre #250, P2).
import 'dart:async';

import 'package:colportores_mobile/features/jornada/presentation/pages/corregir_jornada_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_jornada_sin_cerrar_250_arnes.dart';

/// Los estados de la pantalla a los que se llega (21A·08 y su hoja de hora, 21A·02, 21A·03, 21A·04
/// y 21A·05 del diseño).
enum _Estado {
  sinHora('sin elegir hora (21A·08)'),
  hojaAjuste('hoja de ajuste ±5 (21A·02)'),
  hojaOtraConAviso('hoja «Otra hora» con aviso de rango (21A·03)'),
  hojaOtraDiaSiguiente('hoja «Otra hora» con un fin del día siguiente'),
  finDiaSiguiente('fin elegido al día siguiente'),
  errorAlGuardar('error al guardar (21A·05)'),
  cerrando('cerrando (21A·04)');

  const _Estado(this.rotulo);
  final String rotulo;
}

/// Si el botón −5 / +5 de la hoja (el `OutlinedButton` dentro de [clave]) está habilitado.
bool _pasoHabilitado(WidgetTester tester, String clave) =>
    tester
        .widget<OutlinedButton>(
          find.descendant(of: find.byKey(Key(clave)), matching: find.byType(OutlinedButton)),
        )
        .onPressed !=
    null;

Future<void> _tocar(WidgetTester tester, String clave) async {
  final buscador = find.byKey(Key(clave));
  await tester.ensureVisible(buscador);
  await tester.tap(buscador);
  await tester.pumpAndSettle();
}

/// Monta la pantalla y la deja en [estado]. Devuelve el almacenamiento para mirar lo guardado.
Future<DataSourceQa> _armar(
  WidgetTester tester,
  _Estado estado, {
  Size tamano = telefonoGrandeQa,
  double escala = 1,
}) async {
  fijarPantallaQa(tester, tamano);
  final ds = DataSourceQa();
  await montarQa(tester, ds, escala: EscalaQa(escala));
  await abrirCorregirQa(tester);
  switch (estado) {
    case _Estado.sinHora:
      break;
    case _Estado.hojaAjuste:
      await abrirHojaQa(tester);
    case _Estado.hojaOtraConAviso:
      await abrirHojaQa(tester);
      await escribirEnHojaQa(tester, '06:01');
    case _Estado.hojaOtraDiaSiguiente:
      await abrirHojaQa(tester);
      await escribirEnHojaQa(tester, '00:30');
    case _Estado.finDiaSiguiente:
      await elegirHoraQa(tester, '00:30');
    case _Estado.errorAlGuardar:
      await elegirHoraQa(tester, '00:30');
      ds.errorAlFinalizar = StateError('disco lleno');
      await _tocar(tester, 'corregir_jornada_cerrar');
    case _Estado.cerrando:
      await elegirHoraQa(tester, '00:30');
      ds.demoraFinalizar = Completer<void>();
      await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
      // El indicador de progreso anima sin parar: `pumpAndSettle` no termina.
      await tester.pump(const Duration(milliseconds: 100));
  }
  return ds;
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
        testWidgets('$nombre · ${estado.rotulo}: sin overflow ni excepciones', (tester) async {
          final ds = await _armar(tester, estado, tamano: tamano, escala: escala);
          await tester.pump(const Duration(milliseconds: 100));

          expect(tester.takeException(), isNull);
          if (estado == _Estado.cerrando) ds.demoraFinalizar!.complete();
        });
      }
    }
  });

  group('Accesibilidad (checklist 6): los estados que la prueba del implementador no recorre', () {
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

            if (estado == _Estado.cerrando) ds.demoraFinalizar!.complete();
            semantica.dispose();
          },
        );
      }
    }

    testWidgets('el aviso de error al guardar se anuncia (liveRegion) y está a la vista', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _armar(tester, _Estado.errorAlGuardar);

      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Semantics && (w.properties.liveRegion ?? false)),
        findsOneWidget,
      );
      expect(
        find.textContaining('No pudimos guardar el fin de tu jornada, que sigue abierta.'),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets('los botones −5 y +5 de la hoja tienen etiqueta para el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _armar(tester, _Estado.hojaAjuste);

      expect(find.bySemanticsLabel('5 minutos antes'), findsOneWidget);
      expect(find.bySemanticsLabel('5 minutos después'), findsOneWidget);
      semantica.dispose();
    });

    // skip: QA #250 — mientras cierra, el botón queda con un spinner de 18 dp y sin texto: el lector de
    // pantalla lo lee como «botón» sin nombre y a la vista es un spinner sin contexto (§8.3). En Hoy
    // el mismo momento dice «Finalizando…» (21A·04).
    testWidgets('mientras cierra, el botón conserva un texto que dice qué está pasando', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final ds = await _armar(tester, _Estado.cerrando);

      final boton = find.byKey(const Key('corregir_jornada_cerrar'));
      expect(find.descendant(of: boton, matching: find.byType(Text)), findsWidgets);
      expect(tester.getSemantics(boton).label, isNotEmpty);

      ds.demoraFinalizar!.complete();
      semantica.dispose();
    }, skip: true);
  });

  group('Validación de «Otra hora» (checklist 4): cada entrada, con el botón y el aviso', () {
    // Rango de la hoja: de las 18:01 del lunes 21 a las 06:00 del martes 22.
    const sinAviso = <String, bool>{
      // texto escrito: ¿habilita «Usar esta hora»?
      '18:01': true,
      '18:30': true,
      '1830': true,
      '21:00': true,
      '23:59': true,
      '0:30': true,
      '00:00': true,
      '05:59': true,
      '06:00': true,
      // El teclado deja pegar de más: lo que sobra se corta a 5 caracteres y lo que no es dígito
      // ni «:» no entra.
      '18:30:15': true,
      '18:30abc': true,
      '18:30😀': true,
    };
    sinAviso.forEach((texto, valido) {
      testWidgets('«$texto» se acepta', (tester) async {
        await _armar(tester, _Estado.hojaOtraConAviso);
        await escribirEnHojaQa(tester, texto);

        expect(botonUsarEscritaQa(tester).onPressed, valido ? isNotNull : isNull);
        expect(find.textContaining('La hora tiene que estar'), findsNothing);
        expect(find.textContaining('No entendimos'), findsNothing);
      });
    });

    const fueraDeRango = <String>['18:00', '06:01', '12:00', '17:59', '09:30', '9:30', '07:00'];
    for (final texto in fueraDeRango) {
      testWidgets('«$texto» está fuera del rango: avisa el rango y no deja usarla', (tester) async {
        await _armar(tester, _Estado.hojaOtraConAviso);
        await escribirEnHojaQa(tester, texto);

        expect(find.text('La hora tiene que estar entre las 18:01 y las 06:00.'), findsOneWidget);
        expect(botonUsarEscritaQa(tester).onPressed, isNull);
      });
    }

    const noEntendida = <String>[
      '25:00',
      '12:60',
      '24:00',
      '99:99',
      '0000000000',
      '12345',
      ':::::',
    ];
    for (final texto in noEntendida) {
      testWidgets('«$texto» no es una hora: lo dice y no deja usarla', (tester) async {
        await _armar(tester, _Estado.hojaOtraConAviso);
        await escribirEnHojaQa(tester, texto);

        expect(find.textContaining('No entendimos esa hora.'), findsOneWidget);
        expect(botonUsarEscritaQa(tester).onPressed, isNull);
      });
    }

    const vacias = <String>['', '   ', 'abc', '😀', '\n', 'a b c'];
    for (final texto in vacias) {
      testWidgets('«${texto.replaceAll('\n', r'\n')}» queda vacío: pide la hora con un ejemplo', (
        tester,
      ) async {
        await _armar(tester, _Estado.hojaOtraConAviso);
        await escribirEnHojaQa(tester, texto);

        expect(find.textContaining('Escribí la hora, por ejemplo'), findsOneWidget);
        expect(botonUsarEscritaQa(tester).onPressed, isNull);
      });
    }

    testWidgets('a medio escribir («1», «18:3») no regaña todavía, pero no habilita el botón', (
      tester,
    ) async {
      await _armar(tester, _Estado.hojaOtraConAviso);
      for (final texto in ['1', '18', '18:', '18:3']) {
        await escribirEnHojaQa(tester, texto);
        expect(find.textContaining('No entendimos'), findsNothing, reason: texto);
        expect(botonUsarEscritaQa(tester).onPressed, isNull, reason: texto);
      }
    });

    testWidgets('«Listo» del teclado con una hora a medio escribir marca lo que falta', (
      tester,
    ) async {
      await _armar(tester, _Estado.hojaOtraConAviso);
      await escribirEnHojaQa(tester, '18:3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('No entendimos esa hora.'), findsOneWidget);
      expect(find.byKey(const Key('hoja_hora_otra')), findsOneWidget);
    });

    testWidgets('«Listo» del teclado con una hora válida la usa y cierra la hoja', (tester) async {
      await _armar(tester, _Estado.hojaOtraConAviso);
      await escribirEnHojaQa(tester, '20:15');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_otra')), findsNothing);
      expect(find.text('20:15'), findsOneWidget);
      expect(find.text('Terminé a las 20:15'), findsOneWidget);
    });

    testWidgets('tras un aviso de rango, lo tipeado no se pierde y corregirlo lo habilita', (
      tester,
    ) async {
      await _armar(tester, _Estado.hojaOtraConAviso);

      final campo = tester.widget<TextField>(find.byKey(const Key('hoja_hora_campo')));
      expect(campo.controller!.text, '06:01');

      await escribirEnHojaQa(tester, '06:00');
      expect(find.textContaining('La hora tiene que estar'), findsNothing);
      expect(botonUsarEscritaQa(tester).onPressed, isNotNull);
    });
  });

  group('Hoja de ajuste ±5 y el cruce de la medianoche (checklist 1, 5b)', () {
    testWidgets('arranca en el primer minuto válido: −5 no se puede, +5 sube de a cinco', (
      tester,
    ) async {
      await _armar(tester, _Estado.hojaAjuste);

      expect(find.text('18:01'), findsOneWidget);
      expect(_pasoHabilitado(tester, 'hoja_hora_menos'), isFalse);

      await tester.tap(find.byKey(const Key('hoja_hora_mas')));
      await tester.pumpAndSettle();
      expect(find.text('18:06'), findsOneWidget);
      expect(find.text('Usar 18:06'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pumpAndSettle();
      expect(find.text('18:01'), findsOneWidget);
    });

    testWidgets('al pasar de las 23:56 a las 00:01 aparece la aclaración del día siguiente', (
      tester,
    ) async {
      await _armar(tester, _Estado.sinHora);
      await elegirHoraQa(tester, '23:56');
      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsNothing);

      await abrirHojaQa(tester);
      expect(find.text('23:56'), findsWidgets);
      expect(find.byKey(const Key('hoja_hora_nota')), findsNothing);

      await tester.tap(find.byKey(const Key('hoja_hora_mas')));
      await tester.pumpAndSettle();
      expect(find.text('00:01'), findsOneWidget);
      expect(find.text('Termina el martes 22, al día siguiente.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pumpAndSettle();
      // «23:56» también se ve detrás de la hoja, en la pantalla: se mira solo la de la hoja.
      expect(
        find.descendant(
          of: find.byKey(const Key('hoja_hora_ajuste')),
          matching: find.text('23:56'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('hoja_hora_nota')), findsNothing);
    });

    testWidgets('en el último minuto válido (06:00) +5 no se puede y −5 baja a las 05:55', (
      tester,
    ) async {
      await _armar(tester, _Estado.sinHora);
      await elegirHoraQa(tester, '06:00');
      await abrirHojaQa(tester);

      expect(_pasoHabilitado(tester, 'hoja_hora_mas'), isFalse);
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pumpAndSettle();
      expect(find.text('05:55'), findsOneWidget);
    });

    testWidgets('la aclaración dice el día entero, en la hoja de ajuste, en «Otra hora» y en la '
        'pantalla (decisión del 08/10, P2)', (tester) async {
      await _armar(tester, _Estado.sinHora);
      await abrirHojaQa(tester);
      await escribirEnHojaQa(tester, '00:30');
      // «Otra hora»: el texto de ayuda del campo.
      expect(find.text('Termina el martes 22, al día siguiente.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
      await tester.pumpAndSettle();
      // La pantalla.
      expect(
        tester.widget<Text>(find.byKey(const Key('corregir_jornada_dia_fin'))).data,
        'Termina el martes 22, al día siguiente.',
      );

      // La hoja de ajuste, ahora arrancando en las 00:30.
      await abrirHojaQa(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('hoja_hora_nota'))).data,
        'Termina el martes 22, al día siguiente.',
      );
    });

    testWidgets('una hora del mismo día no lleva aclaración ni en la hoja ni en la pantalla', (
      tester,
    ) async {
      await _armar(tester, _Estado.sinHora);
      await elegirHoraQa(tester, '21:10');

      expect(find.byKey(const Key('corregir_jornada_dia_fin')), findsNothing);
      await abrirHojaQa(tester);
      expect(find.byKey(const Key('hoja_hora_nota')), findsNothing);
    });

    testWidgets('el fin de año: una jornada del jueves 31/12 que termina el viernes 1/1', (
      tester,
    ) async {
      fijarPantallaQa(tester, telefonoGrandeQa);
      final inicio = DateTime(2026, 12, 31, 18);
      final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(inicio)]);
      await montarQa(tester, ds, reloj: () => DateTime(2027, 1, 1, 8));
      final resultado = await abrirCorregirQa(tester, inicio: inicio);

      expect(find.textContaining('Tenés una jornada del jueves 31 sin cerrar.'), findsOneWidget);
      expect(find.text('Jueves 31 · después de las 18:00'), findsOneWidget);

      await elegirHoraQa(tester, '00:30');
      expect(find.text('Termina el viernes 1, al día siguiente.'), findsOneWidget);

      await _tocar(tester, 'corregir_jornada_cerrar');
      expect(ds.jornadas.single.fin, DateTime(2027, 1, 1, 0, 30).toUtc());
      expect(resultado.valor?.fin, DateTime(2027, 1, 1, 0, 30).toUtc());
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets('un inicio con segundos (18:00:30): las 18:00 no valen y las 18:01 sí', (
      tester,
    ) async {
      fijarPantallaQa(tester, telefonoGrandeQa);
      final inicio = DateTime(2026, 9, 21, 18, 0, 30);
      final ds = DataSourceQa(iniciales: [jornadaAbiertaQa(inicio)]);
      await montarQa(tester, ds);
      await abrirCorregirQa(tester, inicio: inicio);

      await elegirHoraQa(tester, '18:00', confirmar: false);
      expect(find.text('La hora tiene que estar entre las 18:01 y las 06:00.'), findsOneWidget);
      expect(botonUsarEscritaQa(tester).onPressed, isNull);

      await escribirEnHojaQa(tester, '18:01');
      expect(botonUsarEscritaQa(tester).onPressed, isNotNull);
    });
  });

  group('Navegación y acciones superpuestas (checklist 5 y 5b)', () {
    testWidgets('el atrás del sistema con la hoja abierta cierra solo la hoja: la pantalla sigue '
        'y no cambia la hora', (tester) async {
      await _armar(tester, _Estado.sinHora);
      await abrirHojaQa(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
      expect(botonCerrarQa(tester).onPressed, isNull);
    });

    testWidgets('tocar fuera de la hoja la cierra y conserva la hora ya elegida', (tester) async {
      await _armar(tester, _Estado.finDiaSiguiente);
      await abrirHojaQa(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);
      expect(find.text('00:30'), findsOneWidget);
      expect(find.text('Terminé a las 00:30'), findsOneWidget);
    });

    testWidgets(
      '«Cancelar» con una hora ya elegida no la toca, y «Volver» de «Otra hora» tampoco',
      (tester) async {
        await _armar(tester, _Estado.sinHora);
        await elegirHoraQa(tester, '20:30');

        await abrirHojaQa(tester);
        await tester.tap(find.byKey(const Key('hoja_hora_valor')));
        await tester.pumpAndSettle();
        await escribirEnHojaQa(tester, '19:00');
        await tester.tap(find.byKey(const Key('hoja_hora_volver')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('hoja_hora_cancelar')));
        await tester.pumpAndSettle();

        expect(find.text('20:30'), findsOneWidget);
        expect(find.text('Terminé a las 20:30'), findsOneWidget);
      },
    );

    testWidgets('doble toque en «Cancelar» de la hoja (con una pausa corta entre medio) no saca '
        'la pantalla de corrección', (tester) async {
      await _armar(tester, _Estado.sinHora);
      await abrirHojaQa(tester);

      await tester.tap(find.byKey(const Key('hoja_hora_cancelar')));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(const Key('hoja_hora_cancelar')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
    });

    testWidgets('doble toque en «Usar 18:01» elige una sola vez y la pantalla sigue', (
      tester,
    ) async {
      await _armar(tester, _Estado.sinHora);
      await abrirHojaQa(tester);

      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.tap(find.byKey(const Key('hoja_hora_usar')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(CorregirJornadaPage), findsOneWidget);
      expect(find.text('Terminé a las 18:01'), findsOneWidget);
    });

    testWidgets(
      'doble toque en «Usar esta hora» (Otra hora) elige una sola vez y la pantalla sigue',
      (tester) async {
        await _armar(tester, _Estado.sinHora);
        await abrirHojaQa(tester);
        await escribirEnHojaQa(tester, '00:30');

        await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
        await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(CorregirJornadaPage), findsOneWidget);
        expect(find.text('Terminé a las 00:30'), findsOneWidget);
      },
    );

    testWidgets('mientras cierra no se puede volver a abrir la hoja, y al terminar sale con el fin '
        'elegido (una sola escritura)', (tester) async {
      final ds = await _armar(tester, _Estado.cerrando);

      await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('hoja_hora_ajuste')), findsNothing);

      await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ds.escrituras, 1);

      ds.demoraFinalizar!.complete();
      await tester.pumpAndSettle();

      expect(ds.escrituras, 1);
      expect(ds.jornadas.single.fin, DateTime(2026, 9, 22, 0, 30).toUtc());
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets('tras un error al guardar, elegir otra hora saca el aviso y el reintento cierra '
        'con la nueva (dos escrituras: una falló, una guardó)', (tester) async {
      final ds = await _armar(tester, _Estado.errorAlGuardar);
      expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);
      expect(find.text('Terminé a las 00:30'), findsOneWidget);

      ds.errorAlFinalizar = null;
      await elegirHoraQa(tester, '23:50');
      expect(find.byKey(const Key('corregir_jornada_error')), findsNothing);
      expect(find.text('Terminé a las 23:50'), findsOneWidget);

      await _tocar(tester, 'corregir_jornada_cerrar');

      expect(ds.escrituras, 2);
      expect(ds.jornadas.single.fin, DateTime(2026, 9, 21, 23, 50).toUtc());
      expect(find.byType(CorregirJornadaPage), findsNothing);
    });

    testWidgets(
      'el error al guardar no se pierde con un giro de pantalla ni al subir el texto a 2.0',
      (tester) async {
        fijarPantallaQa(tester, telefonoGrandeQa);
        final escala = EscalaQa();
        final ds = DataSourceQa()..errorAlFinalizar = StateError('disco lleno');
        await montarQa(tester, ds, escala: escala);
        await abrirCorregirQa(tester);
        await elegirHoraQa(tester, '00:30');
        await _tocar(tester, 'corregir_jornada_cerrar');
        expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);

        escala.valor = 2;
        fijarPantallaQa(tester, const Size(915, 412));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('corregir_jornada_error')), findsOneWidget);
        expect(find.text('00:30'), findsOneWidget);
      },
    );
  });
}
