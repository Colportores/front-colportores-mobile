// QA de #516 (PR #736, HU-NOT-004, vista 24 grupo B, sección AVISOS): casos límite, tamaños, error visible,
// validación del selector de hora y privacidad. Con las fuentes reales (la medida del texto vale).
// Los hallazgos van con `skip: 'QA #516: …'` hasta que el implementador los arregle.
import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/avisos_del_servidor_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_vista24_avisos_516_arnes.dart';

/// El rectángulo de [f] cabe en la pantalla visible (sin tener que desplazar).
bool _enPantalla(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  final v = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= 0 && r.bottom <= v.height && r.left >= 0 && r.right <= v.width;
}

void main() {
  setUpAll(cargarFuentesReales);

  group('Tamaños: ningún estado desborda ni corta controles', () {
    for (final tam in [...tamanos736, tamanoChico736]) {
      for (final escala in escalas736) {
        for (final estado in Estado736.values) {
          testWidgets('${estado.id} · ${tam.nombre} · texto ${escala}x', (tester) async {
            await llevarAlEstado736(tester, estado, tamano: tam, escala: escala);
            expect(tester.takeException(), isNull, reason: 'al abrir');
            // Recorre la pantalla de punta a punta: cada control se alcanza y mide al menos 48 dp.
            for (final f in controles736()) {
              if (f.evaluate().isEmpty) continue;
              await tester.ensureVisible(f);
              await tester.pump();
              expect(tester.takeException(), isNull, reason: '$f');
              expect(tester.getSize(f).height, greaterThanOrEqualTo(48), reason: '$f');
            }
            for (final f in [errorGuardar736, errorLeer736, cargando736]) {
              if (f.evaluate().isEmpty) continue;
              await tester.ensureVisible(f);
              await tester.pump();
              expect(tester.takeException(), isNull, reason: '$f');
            }
          });
        }
      }
    }
  });

  group('El error de guardar se ve sin tener que buscarlo (24B·06)', () {
    // La decisión de fondo (dónde va el aviso) es del canvas: el 24B·06 dibuja el aviso ARRIBA de la lista.
    // Acá se mide lo que ve la persona en el teléfono: si el interruptor vuelve a como estaba y el aviso
    // queda fuera de la pantalla, no se entera de que su cambio no se guardó.
    for (final tam in tamanos736) {
      testWidgets(
        'toca «Asignaciones» al final de la pantalla (${tam.nombre}) y falla: el aviso aparece a la vista',
        (tester) async {
          final telefono = await llevarAlEstado736(tester, Estado736.preferencias, tamano: tam);
          telefono.avisos.fallaAlGuardar = const AvisosServidorException();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
          await tester.pumpAndSettle();
          await tester.tap(asignaciones736);
          await tester.pumpAndSettle();

          expect(find.text(textoError736), findsOneWidget);
          expect(
            _enPantalla(tester, errorGuardar736),
            isTrue,
            reason: 'el aviso quedó fuera de lo que se ve, sin desplazar',
          );
        },
      );
    }

    testWidgets(
      'cambia la hora de la agenda (arriba) y falla: el aviso (en AVISOS) queda a la vista a 360×640',
      (tester) async {
        final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
        telefono.avisos.fallaAlGuardar = const AvisosServidorException();
        await tocar736(tester, horaAgenda736);
        await tester.pumpAndSettle();
        await elegirHora736(tester, 21, 0);

        expect(find.text(textoErrorHoraAgenda736), findsOneWidget);
        expect(
          tester.widget<Text>(horaAgendaValor736).data,
          '20:00',
          reason: 'volvió a como estaba',
        );
        expect(
          _enPantalla(tester, errorGuardar736),
          isTrue,
          reason: 'el aviso está en AVISOS, debajo de la fila de la hora que se tocó: no se ve',
        );
      },
    );
  });

  group('Selector de hora: validación y tamaños', () {
    testWidgets(
      'hora 24, minuto 60, vacío o emoji: el selector no deja confirmar y no se guarda nada',
      (tester) async {
        final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
        await tocar736(tester, horaCuota736);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        final campos = find.byType(TextField);

        for (final (h, m) in [('24', '00'), ('09', '60'), ('', ''), ('ab', 'cd'), ('9🙂', '0🙂')]) {
          await tester.enterText(campos.at(0), h);
          await tester.enterText(campos.at(1), m);
          await tester.pump();
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(find.text('OK'), findsOneWidget, reason: 'sigue abierto con "$h:$m"');
          expect(telefono.avisos.guardados, isEmpty, reason: '"$h:$m"');
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('texto pegado muy largo en el campo de la hora no rompe el selector ni guarda', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), '1' * 500);
      await tester.enterText(campos.at(1), '5' * 500);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(telefono.avisos.guardados, isEmpty);
    });

    testWidgets('00:00 y 23:59 se guardan tal cual, con dos dígitos', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 0, 0);
      await tocar736(tester, horaAgenda736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 23, 59);

      expect(telefono.avisos.avisos.horaCuota.texto, '00:00');
      expect(telefono.avisos.avisos.horaAgenda.texto, '23:59');
      expect(telefono.avisos.guardados.last['hora_cuota'], '00:00');
      expect(telefono.avisos.guardados.last['hora_agenda'], '23:59');
    });

    for (final tam in [...tamanos736, tamanoChico736]) {
      testWidgets('el selector a texto 2.0 en ${tam.nombre} no desborda y se puede confirmar', (
        tester,
      ) async {
        final telefono = await llevarAlEstado736(
          tester,
          Estado736.preferencias,
          tamano: tam,
          escala: 2,
        );
        await tocar736(tester, horaCuota736);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'al abrir');
        expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'en modo texto');
        final campos = find.byType(TextField);
        await tester.enterText(campos.at(0), '8');
        await tester.enterText(campos.at(1), '15');
        await tester.pump();
        await tester.ensureVisible(find.text('OK'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(telefono.avisos.avisos.horaCuota.texto, '08:15');
      });
    }
  });

  group('Casos límite de los flujos', () {
    testWidgets('el primer guardado sale bien y el segundo (en cola) falla: lo primero queda y el '
        'error dice lo que volvió', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos.guardadoDemorado = demora;
      await tocar736(tester, pedidos736);
      await tester.pump();
      await tocar736(tester, tickets736);
      await tester.pump();
      // Termina el primero bien; el segundo falla.
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await tocar736(tester, asignaciones736);
      await tester.pumpAndSettle();

      expect(telefono.avisos.avisos.pedidos, isFalse, reason: 'se guardó');
      expect(telefono.avisos.avisos.tickets, isFalse, reason: 'se guardó');
      expect(prendido736(tester, pedidos736), isFalse);
      expect(prendido736(tester, tickets736), isFalse);
      expect(prendido736(tester, asignaciones736), isTrue, reason: 'volvió a como estaba');
      expect(find.text(textoError736), findsOneWidget);
    });

    testWidgets('«Reintentar» con el servidor todavía caído: sigue el aviso, nada queda trabado, '
        'y al volver el servidor se guarda', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorGuardar);
      for (var i = 0; i < 3; i++) {
        await tocar736(tester, reintentarGuardar736);
        await tester.pumpAndSettle();
        expect(find.text(textoError736), findsOneWidget, reason: 'reintento ${i + 1}');
        expect(prendido736(tester, pedidos736), isTrue);
      }
      expect(telefono.avisos.guardados.length, 4, reason: '1 original + 3 reintentos');
      telefono.avisos.fallaAlGuardar = null;
      await tocar736(tester, reintentarGuardar736);
      await tester.pumpAndSettle();
      expect(errorGuardar736, findsNothing);
      expect(telefono.avisos.avisos.pedidos, isFalse);
      expect(prendido736(tester, pedidos736), isFalse);
    });

    testWidgets('doble toque rápido en «Reintentar»: un solo guardado', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorGuardar);
      telefono.avisos.fallaAlGuardar = null;
      final antes = telefono.avisos.guardados.length;
      final demora = Completer<void>();
      telefono.avisos.guardadoDemorado = demora;
      await tester.ensureVisible(reintentarGuardar736);
      await tester.pump();
      final punto = tester.getCenter(reintentarGuardar736);
      await tester.tapAt(punto);
      await tester.pump();
      await tester.tapAt(punto);
      await tester.pump();
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();

      expect(telefono.avisos.guardados.length - antes, 1);
      expect(telefono.avisos.avisos.pedidos, isFalse);
    });

    testWidgets('error al leer y «Reintentar»: llegan los avisos y se pueden usar', (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorLeer);
      expect(find.text('No pudimos leer tus avisos.'), findsOneWidget);
      expect(pedidos736, findsNothing);
      telefono.avisos
        ..fallaAlLeer = null
        ..avisos = const AvisosDelServidor(tickets: false);
      await tocar736(tester, reintentarLeer736);
      await tester.pumpAndSettle();

      expect(errorLeer736, findsNothing);
      expect(prendido736(tester, tickets736), isFalse);
      await tocar736(tester, pedidos736);
      await tester.pumpAndSettle();
      expect(telefono.avisos.avisos.pedidos, isFalse);
      expect(telefono.avisos.avisos.tickets, isFalse, reason: 'lo leído se conserva al guardar');
    });

    testWidgets('mientras los avisos cargan, apagar «Recordatorios de agenda» igual llega al '
        'servidor cuando termina de leer', (tester) async {
      final telefono = activado736();
      final lectura = Completer<void>();
      telefono.avisos.lecturaDemorada = lectura;
      await abrir736(tester, telefono);
      expect(cargando736, findsOneWidget);

      await tocar736(tester, recordatorios736);
      await tester.pump();
      expect(prendido736(tester, recordatorios736), isFalse);
      lectura.complete();
      await tester.pumpAndSettle();

      expect(telefono.avisos.avisos.agenda, isFalse, reason: 'el teléfono manda: se alineó');
      expect(errorGuardar736, findsNothing);
    });

    testWidgets('cambiar un aviso, un error al guardar y volver a entrar: el servidor manda', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.errorGuardar);
      telefono.avisos.fallaAlGuardar = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await abrir736(tester, telefono);

      expect(errorGuardar736, findsNothing, reason: 'el aviso no sobrevive a la reentrada');
      expect(prendido736(tester, pedidos736), isTrue);
    });

    testWidgets('muchas pulsaciones seguidas sobre el mismo interruptor: termina en lo último', (
      tester,
    ) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos.guardadoDemorado = demora;
      for (var i = 0; i < 7; i++) {
        await tocar736(tester, tickets736);
        await tester.pump();
      }
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();

      expect(prendido736(tester, tickets736), isFalse, reason: '7 toques = apagado');
      expect(telefono.avisos.avisos.tickets, isFalse);
      expect(errorGuardar736, findsNothing);
    });

    testWidgets(
      'con los recordatorios apagados, tocar la hora de la agenda no abre nada (ni con el '
      'lector de pantalla)',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await llevarAlEstado736(tester, Estado736.recordatoriosApagados);
        await tester.ensureVisible(horaAgenda736);
        await tester.pump();
        await tester.tap(horaAgenda736, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
        final nodo = tester.getSemantics(horaAgenda736);
        expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        semantica.dispose();
      },
    );

    testWidgets('un valor del servidor con basura (hora 25:99, interruptor "no", clave nueva) se '
        'muestra con los de siempre y se conserva la clave nueva al guardar', (tester) async {
      final telefono = activado736();
      telefono.avisos.avisos = AvisosDelServidor.desdeJson(const {
        'hora_cuota': '25:99',
        'hora_agenda': 7,
        'tickets': 'no',
        'pedidos': false,
        'otra_version': {'a': 1},
      });
      await abrir736(tester, telefono);
      expect(tester.widget<Text>(horaCuotaValor736).data, '09:00');
      expect(tester.widget<Text>(horaAgendaValor736).data, '20:00');
      expect(prendido736(tester, tickets736), isTrue);
      expect(prendido736(tester, pedidos736), isFalse);

      await tocar736(tester, asignaciones736);
      await tester.pumpAndSettle();
      expect(telefono.avisos.guardados.last['otra_version'], {'a': 1});
    });

    testWidgets(
      'el botón atrás funciona en cada estado (cargando, error al leer, error al guardar)',
      (tester) async {
        for (final e in [Estado736.cargando, Estado736.errorLeer, Estado736.errorGuardar]) {
          final telefono = switch (e) {
            Estado736.cargando => activado736()..avisos.lecturaDemorada = Completer<void>(),
            Estado736.errorLeer =>
              activado736()..avisos.fallaAlLeer = const AvisosServidorException(),
            _ => activado736(),
          };
          fijarTamano(tester, tamano: const Size(360, 640));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_conRuta(telefono));
          await tester.pumpAndSettle();
          await tester.tap(find.text('abrir'));
          await tester.pumpAndSettle();
          expect(pagina736, findsOneWidget, reason: e.id);
          if (e == Estado736.errorGuardar) {
            telefono.avisos.fallaAlGuardar = const AvisosServidorException();
            await tocar736(tester, pedidos736);
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(atras736);
          await tester.pump();
          await tester.tap(atras736);
          await tester.pumpAndSettle();
          expect(pagina736, findsNothing, reason: e.id);
          expect(find.text('abrir'), findsOneWidget);
        }
      },
    );
  });

  // Hallazgos documentados: se sacan del `skip` cuando el implementador los arregla.
  group(
    'Hallazgos',
    () {
      testWidgets(
        'con el error de un aviso a la vista, tocar «Recordatorios de agenda» (otra sección, del teléfono) '
        'no borra el aviso ni su «Reintentar»',
        (tester) async {
          final telefono = await llevarAlEstado736(tester, Estado736.errorGuardar);
          expect(errorGuardar736, findsOneWidget);
          telefono.avisos.fallaAlGuardar = null;

          await tocar736(tester, recordatorios736);
          await tester.pumpAndSettle();

          expect(errorGuardar736, findsOneWidget, reason: 'el cambio de Pedidos sigue sin guardar');
          expect(reintentarGuardar736, findsOneWidget);
        },
      );
    },
    skip:
        'QA #516: tocar «Recordatorios de agenda» con el error de AVISOS a la vista sincroniza la copia '
        'del servidor, limpia el aviso y pierde el «Reintentar» del cambio que no se guardó',
  );

  group('Privacidad', () {
    test(
      'toString de lo que se guarda no deja ver más que las horas y el estado de los avisos',
      () {
        const avisos = AvisosDelServidor(otras: {'secreto': 'x'});
        expect(avisos.toString(), isNot(contains('secreto')), reason: 'stringify apagado');
        expect(const HoraDelAviso(9, 5).toString(), '09:05');
        expect(const AvisosSinConexionException().toString(), 'AvisosSinConexionException');
        expect(const AvisosServidorException(codigo: '23514').toString(), contains('23514'));
      },
    );

    test('el estado de los avisos no imprime lo guardado', () {
      const estado = EstadoAvisosDelServidor(avisos: AvisosDelServidor(otras: {'token': 'abc'}));
      expect(estado.toString(), isNot(contains('abc')));
    });
  });
}

/// La pantalla abierta desde un botón, para probar «volver atrás».
Widget _conRuta(Telefono telefono) => ProviderScope(
  key: UniqueKey(),
  overrides: telefono.overrides,
  child: MaterialApp(
    theme: temaClaro(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(NotificacionesPage.ruta()),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ),
);
