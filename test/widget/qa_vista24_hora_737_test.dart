// QA de #737 (PR #744, vista 24, grupo B): la hora de los avisos como control (`›`), el aviso que dice
// cuál hora falló y la copia de «Recordatorios de agenda» en el servidor. Se apoya en el arnés de #516.
// Las capturas solo corren con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;
import '../helpers/qa_vista24_avisos_516_arnes.dart';

final _flecha = find.byKey(const Key('hora_del_aviso_flecha'));

Finder _flechaDe(Finder fila) => find.descendant(of: fila, matching: _flecha);

Future<void> _verFila(WidgetTester tester, Finder fila) async {
  await tester.ensureVisible(fila);
  await tester.pump();
}

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa744_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  group('La hora se ve como un control (`›`)', () {
    setUpAll(cargarFuentesReales);

    for (final tam in [...tamanos736, tamanoChico736]) {
      for (final escala in escalas736) {
        for (final (nombre, fila, valor) in [
          ('Cuotas', horaCuota736, horaCuotaValor736),
          ('visitas de mañana', horaAgenda736, horaAgendaValor736),
        ]) {
          testWidgets(
            'hora de $nombre · ${tam.nombre} · texto ${escala}x: flecha a la derecha, pegada a la '
            'hora, sin cortarse ni salirse de la fila',
            (tester) async {
              await llevarAlEstado736(tester, Estado736.preferencias, tamano: tam, escala: escala);
              await _verFila(tester, fila);

              final rFila = tester.getRect(fila);
              final rFlecha = tester.getRect(_flechaDe(fila));
              final rHora = tester.getRect(valor);

              expect(rFlecha.right, lessThanOrEqualTo(rFila.right));
              expect(rFlecha.left, greaterThanOrEqualTo(rFila.left));
              expect(rHora.left, greaterThanOrEqualTo(rFila.left));
              // La flecha cierra el renglón por la derecha (el relleno de la fila es de 16).
              expect(rFila.right - rFlecha.right, closeTo(16, 6), reason: 'no está a la derecha');
              // La hora queda a la izquierda de la flecha y no la pisa.
              expect(rHora.right, lessThanOrEqualTo(rFlecha.left + 0.5));
              // La hora entera en un solo renglón.
              final fuente = tester.widget<Text>(valor).style?.fontSize ?? 14;
              expect(rHora.height, lessThan(fuente * escala * 1.8), reason: 'la hora se partió');
              // La fila entera sigue siendo un blanco de toque cómodo.
              expect(rFila.height, greaterThanOrEqualTo(56));
              expect(tester.takeException(), isNull);
            },
          );
        }

        testWidgets('las dos flechas quedan en la misma columna · ${tam.nombre} · ${escala}x', (
          tester,
        ) async {
          await llevarAlEstado736(tester, Estado736.preferencias, tamano: tam, escala: escala);
          await _verFila(tester, horaCuota736);
          final cuotas = tester.getRect(_flechaDe(horaCuota736)).right;
          await _verFila(tester, horaAgenda736);
          final agenda = tester.getRect(_flechaDe(horaAgenda736)).right;
          expect(cuotas, closeTo(agenda, 0.5));
        });
      }
    }

    testWidgets('tocar la flecha misma abre el selector de hora', (tester) async {
      await llevarAlEstado736(tester, Estado736.preferencias);
      await _verFila(tester, horaCuota736);
      await tester.tap(_flechaDe(horaCuota736));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
    });

    testWidgets('el lector de pantalla no lee la flecha: un solo botón por hora', (tester) async {
      final semantica = tester.ensureSemantics();
      await llevarAlEstado736(tester, Estado736.preferencias);
      await _verFila(tester, horaCuota736);
      final s = tester.getSemantics(horaCuota736);
      expect(s.label, isNot(contains('›')));
      expect(s.value, '09:00');
      expect(s.value, isNot(contains('›')));
      expect(find.bySemanticsLabel('›'), findsNothing);
      semantica.dispose();
    });

    testWidgets('con los recordatorios apagados la fila de la agenda no se toca y no abre nada', (
      tester,
    ) async {
      await llevarAlEstado736(tester, Estado736.recordatoriosApagados);
      await _verFila(tester, horaAgenda736);
      await tester.tap(horaAgenda736, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
    });

    test('contraste de la flecha (gris de la paleta sobre el crema): ≥ 3:1 (1.4.11)', () {
      // `ExcludeSemantics` la saca del árbol que mide `textContrastGuideline`: se mide a mano.
      const gris = Color(0xFF5B6B82);
      const fondoTarjeta = Colors.white;
      const fondoPagina = Color(0xFFF7F4EC);
      double lum(Color c) {
        double f(double v) =>
            v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
      }

      double ratio(Color a, Color b) {
        final la = lum(a);
        final lb = lum(b);
        return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
      }

      expect(ratio(gris, fondoTarjeta), greaterThanOrEqualTo(3.0));
      expect(ratio(gris, fondoPagina), greaterThanOrEqualTo(3.0));
    });
  });

  group('El aviso dice cuál hora falló', () {
    testWidgets('Cuotas: el texto literal del issue, «Reintentar» a mano y la hora vuelve', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorGuardarHora);
      expect(
        find.text('No pudimos guardar la hora del aviso de cuotas. Volvió a como estaba.'),
        findsOneWidget,
      );
      expect(reintentarGuardar736, findsOneWidget);
      expect(tester.widget<Text>(horaCuotaValor736).data, '09:00');
      expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(9, 0));
    });

    testWidgets('visitas de mañana: el texto literal del issue y la hora vuelve', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, horaAgenda736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 21, 15);
      expect(
        find.text(
          'No pudimos guardar la hora del aviso de las visitas de mañana. Volvió a como estaba.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(horaAgendaValor736).data, '20:00');
    });

    testWidgets('el texto viejo, sin decir cuál, ya no aparece en ningún caso', (tester) async {
      await llevarAlEstado736(tester, Estado736.errorGuardarHora);
      expect(find.text('No pudimos guardar la hora. Volvió a como estaba.'), findsNothing);
    });

    testWidgets('las dos horas fallan juntas: un solo aviso, el de «varios cambios»', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos
        ..guardadoDemorado = demora
        ..fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 7, 0);
      await tocar736(tester, horaAgenda736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 19, 0);
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();

      expect(find.text(textoErrorVarios736), findsOneWidget);
      expect(errorGuardar736, findsOneWidget);
      expect(tester.widget<Text>(horaCuotaValor736).data, '09:00');
      expect(tester.widget<Text>(horaAgendaValor736).data, '20:00');
    });

    testWidgets('una hora y un interruptor que fallan juntos: «varios cambios»', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos
        ..guardadoDemorado = demora
        ..fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, pedidos736);
      await tester.pump();
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 7, 0);
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();
      expect(find.text(textoErrorVarios736), findsOneWidget);
    });

    testWidgets('«Reintentar» con el servidor de vuelta: guarda la hora y el aviso se va', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorGuardarHora);
      telefono.avisos.fallaAlGuardar = null;
      await tocar736(tester, reintentarGuardar736);
      await tester.pumpAndSettle();
      expect(errorGuardar736, findsNothing);
      expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(7, 30));
      await _verFila(tester, horaCuota736);
      expect(tester.widget<Text>(horaCuotaValor736).data, '07:30');
    });

    testWidgets('«Reintentar» con el servidor todavía caído: el mismo aviso, nada trabado', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorGuardarHora);
      await tocar736(tester, reintentarGuardar736);
      await tester.pumpAndSettle();
      expect(
        find.text('No pudimos guardar la hora del aviso de cuotas. Volvió a como estaba.'),
        findsOneWidget,
      );
      // La hora se puede volver a elegir.
      telefono.avisos.fallaAlGuardar = null;
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 10, 0);
      expect(errorGuardar736, findsNothing);
      expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(10, 0));
    });

    testWidgets('el aviso de la hora se anuncia como región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llevarAlEstado736(tester, Estado736.errorGuardarHora);
      await tester.ensureVisible(errorGuardar736);
      await tester.pump();
      expect(
        tester.getSemantics(errorGuardar736),
        matchesSemantics(
          label: 'No pudimos guardar la hora del aviso de cuotas. Volvió a como estaba.',
          isLiveRegion: true,
        ),
      );
      semantica.dispose();
    });

    for (final tam in tamanos736) {
      for (final escala in escalas736) {
        testWidgets(
          'error de la hora de las visitas de mañana · ${tam.nombre} · ${escala}x: guías de '
          'toque y etiquetas',
          (tester) async {
            final semantica = tester.ensureSemantics();
            final telefono = await llevarAlEstado736(
              tester,
              Estado736.preferencias,
              tamano: tam,
              escala: escala,
            );
            telefono.avisos.fallaAlGuardar = const AvisosServidorException();
            await tocar736(tester, horaAgenda736);
            await tester.pumpAndSettle();
            await elegirHora736(tester, 21, 15);
            expect(errorGuardar736, findsOneWidget);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            expect(tester.takeException(), isNull);
            semantica.dispose();
          },
        );
      }
    }
  });

  group('«Recordatorios de agenda»: la copia del servidor', () {
    testWidgets('apagar y prender con el servidor lento: el servidor termina con lo último', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos.guardadoDemorado = demora;

      await tocar736(tester, recordatorios736);
      await tester.pump();
      await tocar736(tester, recordatorios736);
      await tester.pump();
      expect(prendido736(tester, recordatorios736), isTrue, reason: 'la pantalla no se traba');

      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();

      expect(telefono.preferencias.preferencias.activados, isTrue);
      expect(telefono.avisos.avisos.agenda, isTrue);
      expect(errorGuardar736, findsNothing);
    });

    testWidgets('el servidor cuelga: el interruptor igual cambia y el resto de la pantalla anda', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      telefono.avisos.guardadoDemorado = Completer<void>();

      await tocar736(tester, recordatorios736);
      await tester.pump();
      expect(prendido736(tester, recordatorios736), isFalse);
      expect(telefono.preferencias.preferencias.activados, isFalse);

      // Otro cambio mientras la copia espera: no se pierde ni se pisa.
      await tocar736(tester, tickets736);
      await tester.pump();
      expect(prendido736(tester, tickets736), isFalse);
      expect(errorGuardar736, findsNothing);
    });

    testWidgets('el servidor contesta con error (no es la red): en silencio, sin aviso nuevo', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, recordatorios736);
      await tester.pumpAndSettle();
      expect(telefono.preferencias.preferencias.activados, isFalse);
      expect(errorGuardar736, findsNothing);
      expect(find.textContaining('No pudimos guardar'), findsNothing);
    });

    testWidgets('los avisos no se pudieron leer: apagar en el teléfono y «Reintentar» alinea', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorLeer);
      expect(errorLeer736, findsOneWidget);
      await tocar736(tester, recordatorios736);
      await tester.pumpAndSettle();
      expect(telefono.preferencias.preferencias.activados, isFalse);

      telefono.avisos.fallaAlLeer = null;
      await tocar736(tester, reintentarLeer736);
      await tester.pumpAndSettle();
      expect(telefono.avisos.avisos.agenda, isFalse, reason: 'el teléfono manda');
    });

    testWidgets('mientras la copia viaja, la hora de Cuotas que falla sí avisa y dice cuál', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos
        ..guardadoDemorado = demora
        ..fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, recordatorios736);
      await tester.pump();
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 7, 30);
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();
      // El único cambio visible que no se guardó es la hora: el aviso habla de ella.
      expect(
        find.text('No pudimos guardar la hora del aviso de cuotas. Volvió a como estaba.'),
        findsOneWidget,
      );
    });
  });

  group('Capturas', () {
    setUpAll(cargarTipografias);

    for (final tam in tamanos736) {
      for (final escala in escalas736) {
        testWidgets('captura error hora agenda ${tam.nombre} t${escala.toInt()}', (tester) async {
          final telefono = await llevarAlEstado736(
            tester,
            Estado736.preferencias,
            tamano: tam,
            escala: escala,
          );
          telefono.avisos.fallaAlGuardar = const AvisosServidorException();
          await tocar736(tester, horaAgenda736);
          await tester.pumpAndSettle();
          await elegirHora736(tester, 21, 15);
          await tester.pump(const Duration(milliseconds: 400));
          await _foto(tester, 'errorHoraAgenda_${tam.nombre}_t${escala.toInt()}');
          expect(tester.takeException(), isNull);
        }, skip: !conCapturas);
      }
    }
  });
}
