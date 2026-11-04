// QA de «Aviso exacto» (#510, PR #617), vista 24: el aviso «Los recordatorios pueden llegar tarde…» y su
// «Abrir ajustes». Complementa `vista24_alarmas_exactas_510_test.dart` (el del implementador) con:
// la matriz de estados × 360x640/412x915 × texto 1,0/2,0 con fuentes reales (desborde, alcance del
// botón, guías de toque y de etiqueta), los cruces con los otros avisos de la vista (24A·03/06,
// 24B·02/05/06), las carreras (volver a la app con la primera lectura pendiente, salir con los ajustes
// abriéndose), la app entera desde el arranque y la privacidad.
//
// Los tests de los hallazgos van con `skip` y corren con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_alarmas_exactas.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';
import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias;
import '../helpers/qa_vista24_alarmas_510_arnes.dart';

const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Los estados en los que el aviso tiene que estar.
const _conAviso = {
  Estado617.avisoSolo,
  Estado617.avisoNoAbren,
  Estado617.avisoAbriendo,
  Estado617.avisoNotifSinPedir,
  Estado617.avisoNotifBloqueadas,
  Estado617.avisoErrorGuardar,
  Estado617.avisoErrorLeerPrefs,
  Estado617.avisoAnticipacionLarga,
};

void main() {
  setUpAll(cargarTipografias);

  group('matriz: estados × tamaño × texto', () {
    for (final estado in Estado617.values) {
      for (final tam in tamanos) {
        for (final escala in escalas) {
          testWidgets('${estado.rotulo} · ${tam.nombre} · texto ${escala.toStringAsFixed(1)}', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await llevarAlEstado617(tester, estado, tamano: tam, escala: escala);

            // Sin desborde, en ningún estado.
            expect(tester.takeException(), isNull);

            if (_conAviso.contains(estado)) {
              expect(avisoAlarmas, findsOneWidget);
              expect(find.text(textoAvisoAlarmas), findsOneWidget);
              await tester.ensureVisible(abrirAlarmas);
              await tester.pump();
              // El botón se alcanza: queda dentro de la pantalla y se puede tocar.
              final caja = tester.getRect(abrirAlarmas);
              expect(caja.left, greaterThanOrEqualTo(0));
              expect(caja.right, lessThanOrEqualTo(tam.ancho));
              expect(abrirAlarmas.hitTestable(), findsOneWidget);
              // El texto del aviso no se sale del ancho.
              final texto = tester.getRect(find.text(textoAvisoAlarmas));
              expect(texto.left, greaterThanOrEqualTo(0));
              expect(texto.right, lessThanOrEqualTo(tam.ancho));
              expect(
                tester.widget<TextButton>(abrirAlarmas).onPressed,
                estado == Estado617.avisoAbriendo ? isNull : isNotNull,
              );
            } else {
              expect(avisoAlarmas, findsNothing);
              expect(abrirAlarmas, findsNothing);
              expect(noAbrenAlarmas, findsNothing);
            }
            if (estado == Estado617.avisoNoAbren) {
              expect(find.text(textoNoAbrenAlarmas), findsOneWidget);
            } else {
              expect(noAbrenAlarmas, findsNothing);
            }

            // Guías de toque y de etiqueta con el aviso a la vista (subido el scroll).
            final desplazable = find.byType(SingleChildScrollView);
            if (desplazable.evaluate().isNotEmpty) {
              await tester.drag(desplazable.first, const Offset(0, 5000));
              await tester.pump();
            }
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            expect(tester.takeException(), isNull);
            semantica.dispose();
          });
        }
      }
    }
  });

  group('cruces con los otros avisos de la vista', () {
    testWidgets(
      'con las notificaciones bloqueadas hay dos «Abrir ajustes» y cada uno abre el suyo',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final t = telefono617();
        t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
        t.recuerdo.pedido = PedidoNotificaciones.sistema;
        await montar617(tester, t);

        final deNotificaciones = find.byKey(const Key('notificaciones_abrir_ajustes'));
        expect(deNotificaciones, findsOneWidget);
        expect(abrirAlarmas, findsOneWidget);
        // Rótulos distintos: el lector no los confunde.
        expect(tester.getSemantics(deNotificaciones).label, 'Abrir ajustes del teléfono');
        expect(tester.getSemantics(abrirAlarmas).label, 'Abrir ajustes');

        await tester.tap(abrirAlarmas);
        await tester.pumpAndSettle();
        expect(t.alarmas.ajustesAbiertos, 1);
        expect(t.sistema.ajustesAbiertos, 0);

        await tester.tap(deNotificaciones);
        await tester.pumpAndSettle();
        expect(t.sistema.ajustesAbiertos, 1);
        expect(t.alarmas.ajustesAbiertos, 1);
        semantica.dispose();
      },
    );

    testWidgets(
      'el aviso de las alarmas va entre el del permiso y las preferencias, en ese orden',
      (tester) async {
        final t = telefono617();
        t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
        await montar617(tester, t);

        final permiso = tester.getTopLeft(find.byKey(const Key('notificaciones_apagadas'))).dy;
        final alarmas = tester.getTopLeft(avisoAlarmas).dy;
        final interruptor = tester.getTopLeft(interruptorRecordatorios).dy;
        expect(permiso, lessThan(alarmas));
        expect(alarmas, lessThan(interruptor));
      },
    );

    testWidgets('con error al guardar el aviso sigue y «Reintentar» funciona sin tocarlo', (
      tester,
    ) async {
      final t = telefono617();
      await montar617(tester, t);
      t.preferencias.fallaAlGuardar = true;
      await tester.tap(interruptorRecordatorios);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pref_error_guardar')), findsOneWidget);
      expect(avisoAlarmas, findsOneWidget);

      t.preferencias.fallaAlGuardar = false;
      await tester.ensureVisible(find.byKey(const Key('pref_error_reintentar')));
      await tester.tap(find.byKey(const Key('pref_error_reintentar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pref_error_guardar')), findsNothing);
      // Quedaron apagados: el aviso se va (decidido el 03/11) y no hay ningún error suelto.
      expect(avisoAlarmas, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'con error al leer las preferencias el aviso convive con «Reintentar» y, al leer, se '
      'acomoda',
      (tester) async {
        final t = telefono617();
        t.preferencias.fallaAlLeer = true;
        await montar617(tester, t);

        expect(find.byKey(const Key('pref_error_leer')), findsOneWidget);
        expect(avisoAlarmas, findsOneWidget);

        t.preferencias.fallaAlLeer = false;
        t.preferencias.preferencias = t.preferencias.preferencias.copyWith(activados: false);
        await tester.tap(find.byKey(const Key('pref_reintentar_leer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pref_error_leer')), findsNothing);
        expect(avisoAlarmas, findsNothing, reason: 'las preferencias dicen apagado');
      },
    );

    testWidgets('«Activar» las notificaciones desde el aviso de arriba no mueve ni apaga el aviso '
        'de las alarmas', (tester) async {
      final t = telefono617();
      t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
      await montar617(tester, t);
      expect(find.byKey(const Key('notificaciones_activar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notificaciones_activar')));
      await tester.pumpAndSettle();
      expect(avisoAlarmas, findsOneWidget);
      expect(abrirAlarmas, findsOneWidget);
    });
  });

  group('carreras y reentradas', () {
    testWidgets(
      'volver a la app con la primera lectura todavía pendiente: no se pisa ni se cuelga',
      (tester) async {
        final t = telefono617();
        final demora = t.alarmas.lecturaDemorada = Completer<void>();
        await montar617(tester, t, esperar: false);
        await tester.pump();

        volverALaApp(tester);
        volverALaApp(tester);
        await tester.pump();
        expect(avisoAlarmas, findsNothing, reason: 'todavía no se sabe');

        demora.complete();
        await tester.pumpAndSettle();
        expect(avisoAlarmas, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('salir de la vista mientras se abren los ajustes: al terminar no lanza nada', (
      tester,
    ) async {
      final t = telefono617();
      final demora = t.alarmas.ajustesDemorados = Completer<void>();
      await montar617(tester, t);

      await tester.tap(abrirAlarmas);
      await tester.pump();
      await tester.tap(atrasNotificaciones);
      await tester.pumpAndSettle();
      demora.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'volver del ajuste con el permiso prendido mientras «abriendo»: el aviso se va y el '
      'fin de la demora no lo trae de vuelta',
      (tester) async {
        final t = telefono617();
        final demora = t.alarmas.ajustesDemorados = Completer<void>();
        await montar617(tester, t);

        await tester.tap(abrirAlarmas);
        await tester.pump();
        t.alarmas.estado = EstadoAlarmasExactas.permitidas;
        volverALaApp(tester);
        await tester.pumpAndSettle();
        expect(avisoAlarmas, findsNothing);

        demora.complete();
        await tester.pumpAndSettle();
        expect(avisoAlarmas, findsNothing);
        expect(noAbrenAlarmas, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('el permiso va y viene cinco veces: el aviso siempre acompaña al estado', (
      tester,
    ) async {
      final t = telefono617();
      await montar617(tester, t);
      for (var i = 0; i < 5; i++) {
        t.alarmas.estado = EstadoAlarmasExactas.permitidas;
        volverALaApp(tester);
        await tester.pumpAndSettle();
        expect(avisoAlarmas, findsNothing, reason: 'vuelta $i prendido');
        t.alarmas.estado = EstadoAlarmasExactas.apagadas;
        volverALaApp(tester);
        await tester.pumpAndSettle();
        expect(avisoAlarmas, findsOneWidget, reason: 'vuelta $i apagado');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('«No pudimos abrir» se anuncia al lector y desaparece al reintentar con éxito', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final t = telefono617();
      t.alarmas.puedeAbrirAjustes = false;
      await montar617(tester, t);
      await tester.tap(abrirAlarmas);
      await tester.pumpAndSettle();

      final nodo = tester.getSemantics(noAbrenAlarmas);
      expect(nodo.label, contains('No pudimos abrir los ajustes'));
      expect(
        tester.getSemantics(noAbrenAlarmas).getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
      );
      semantica.dispose();
    });
  });

  // skip: QA #510 (PR #617) — el aviso de «No pudimos abrir los ajustes» de un intento viejo
  // (`_alarmasNoAbren` en `NotificacionesPage`) queda en el estado de la página y reaparece cuando el
  // aviso vuelve (permiso prendido y quitado, o «Recordatorios de agenda» apagados y prendidos), sin
  // que la persona haya tocado «Abrir ajustes» de nuevo.
  group('hallazgos', () {
    testWidgets('el «No pudimos abrir los ajustes» de antes no reaparece cuando el aviso vuelve '
        '(permiso prendido y quitado)', (tester) async {
      final t = telefono617();
      t.alarmas.puedeAbrirAjustes = false;
      await montar617(tester, t);
      await tester.tap(abrirAlarmas);
      await tester.pumpAndSettle();
      expect(noAbrenAlarmas, findsOneWidget);

      // La persona lo prendió a mano y volvió: el aviso se fue.
      t.alarmas.estado = EstadoAlarmasExactas.permitidas;
      volverALaApp(tester);
      await tester.pumpAndSettle();
      expect(avisoAlarmas, findsNothing);

      // Más tarde lo quitó: el aviso vuelve, sin el texto de un intento viejo.
      t.alarmas.estado = EstadoAlarmasExactas.apagadas;
      volverALaApp(tester);
      await tester.pumpAndSettle();
      expect(avisoAlarmas, findsOneWidget);
      expect(noAbrenAlarmas, findsNothing);
    }, skip: !_conHallazgos);

    testWidgets('el «No pudimos abrir los ajustes» de antes no reaparece al apagar y prender '
        '«Recordatorios de agenda»', (tester) async {
      final t = telefono617();
      t.alarmas.puedeAbrirAjustes = false;
      await montar617(tester, t);
      await tester.tap(abrirAlarmas);
      await tester.pumpAndSettle();
      expect(noAbrenAlarmas, findsOneWidget);

      await tester.tap(interruptorRecordatorios);
      await tester.pumpAndSettle();
      expect(avisoAlarmas, findsNothing);
      await tester.tap(interruptorRecordatorios);
      await tester.pumpAndSettle();
      expect(avisoAlarmas, findsOneWidget);
      expect(noAbrenAlarmas, findsNothing);
    }, skip: !_conHallazgos);
  });

  group('la app entera', () {
    testWidgets('desde el arranque con el permiso apagado: se reprograman los avisos y '
        'Configuración → Notificaciones muestra el aviso; al volver con el permiso, se va', (
      tester,
    ) async {
      final t = telefono617();
      await abrirApp(tester, t);
      expect(principal, findsOneWidget);
      expect(t.alarmas.lecturas, greaterThanOrEqualTo(1));
      expect(t.recordatorios.llamadas, contains('programar:ag-1'));

      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('configuracion_notificaciones')));
      await tester.tap(find.byKey(const Key('configuracion_notificaciones')));
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsOneWidget);
      expect(avisoAlarmas, findsOneWidget);

      final antes = t.recordatorios.llamadas.where((l) => l == 'programar:ag-1').length;
      t.alarmas.estado = EstadoAlarmasExactas.permitidas;
      volverALaApp(tester);
      await tester.pumpAndSettle();
      expect(avisoAlarmas, findsNothing);
      expect(
        t.recordatorios.llamadas.where((l) => l == 'programar:ag-1').length,
        greaterThan(antes),
        reason: 'con el permiso prendido los avisos se reprograman exactos',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('el permiso se quita con la app abierta y en otra pantalla: al volver se '
        'reprograma igual (no hace falta abrir la vista 24)', (tester) async {
      final t = telefono617(alarmas: EstadoAlarmasExactas.permitidas);
      await abrirApp(tester, t);
      expect(principal, findsOneWidget);
      final antes = t.recordatorios.llamadas.where((l) => l == 'programar:ag-1').length;

      t.alarmas.estado = EstadoAlarmasExactas.apagadas;
      volverALaApp(tester);
      await tester.pumpAndSettle();
      expect(
        t.recordatorios.llamadas.where((l) => l == 'programar:ag-1').length,
        greaterThan(antes),
        reason: 'Android cancela las alarmas exactas al quitar el permiso',
      );
    });

    testWidgets('en iOS (sin concepto) no hay aviso ni reprogramación por este permiso', (
      tester,
    ) async {
      final t = telefono617(alarmas: EstadoAlarmasExactas.noAplica);
      await abrirApp(tester, t);
      final antes = t.recordatorios.llamadas.length;
      volverALaApp(tester);
      await tester.pumpAndSettle();
      expect(t.recordatorios.llamadas.length, antes);
      expect(avisoAlarmas, findsNothing);
    });
  });

  group('privacidad', () {
    test('la excepción del permiso no deja la causa en el texto', () {
      const e = PermisoAlarmasExactasException(
        operacion: 'estado',
        causa: 'ana@example.com en Av. Italia 1234',
      );
      expect(e.toString(), 'PermisoAlarmasExactasException(estado)');
      expect(e.toString(), isNot(contains('ana@example.com')));
    });
  });
}
