// QA de la respuesta tardía que restringe la cuenta (HU-AUTH-008, #383, PR #469).
//
// Complementa `respuesta_tardia_suspension_383_test.dart` (los escenarios del issue) con lo que
// pide el QA de una vista: las cuatro guías de accesibilidad de Flutter con el aviso a la vista,
// los dos tamaños chicos con el texto al 100 % y al 200 %, el aviso con el teclado, lo tipeado que
// no se pierde, hojas y diálogos abiertos, cerrar sesión con el aviso a la vista y el literal de
// la HU. Los hallazgos van con `skip` y el motivo (convención de los issues [QA-*]).
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart';
import '../helpers/qa_cuenta_restringida_383_arnes.dart';

/// Los dos tamaños chicos del proyecto (móvil) y los dos tamaños de texto.
const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];

/// Qué hay abierto cuando llega la respuesta.
enum _Abierto { configuracion, alta }

String _nombre(_Abierto a, Size t, double e) =>
    '${a.name} · ${t.width.toInt()}×${t.height.toInt()} · texto ${e == 1 ? '100' : '200'} %';

void main() {
  group('accesibilidad con el aviso a la vista (guías de Flutter)', () {
    for (final abierto in _Abierto.values) {
      for (final tam in _tamanos) {
        for (final escala in _escalas) {
          testWidgets(_nombre(abierto, tam, escala), (tester) async {
            final semantica = tester.ensureSemantics();
            fijarTamano(tester, tam, texto: escala);
            final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
            switch (abierto) {
              case _Abierto.configuracion:
                await abrirConfiguracion(tester);
              case _Abierto.alta:
                await abrirElAlta(tester);
            }

            await llegaLaRespuesta(tester, colgada);
            await asentar(tester);
            await tester.pumpAndSettle();

            expect(aviso, findsOneWidget);
            expect(tester.takeException(), isNull, reason: 'sin overflow');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('con el texto al 200 % en 360×640', () {
    testWidgets('el aviso no se come la pantalla: deja lugar al formulario y «Registrar» se '
        'alcanza y guarda', (tester) async {
      fijarTamano(tester, const Size(360, 640), texto: 2);
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await abrirElAlta(tester);
      await llegaLaRespuesta(tester, colgada);
      await asentar(tester);

      final caja = tester.getRect(aviso);
      expect(
        caja.height,
        lessThanOrEqualTo(640 * 0.45),
        reason: 'el aviso ocupa ${caja.height.round()} de 640 dp',
      );
      await tester.ensureVisible(botonRegistrar);
      await tester.pump();
      final boton = tester.getRect(botonRegistrar);
      expect(boton.bottom, lessThanOrEqualTo(640));
      expect(boton.top, greaterThanOrEqualTo(caja.bottom - 1));
      await tocar(tester, botonRegistrar);
      expect(repo.llamadas, hasLength(1));
      expect(titulo, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el teclado abierto el aviso y el campo conviven sin overflow', (tester) async {
      fijarTamano(tester, const Size(360, 640), texto: 2);
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await abrirElAlta(tester);
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await asentar(tester);

      await llegaLaRespuesta(tester, colgada);
      await asentar(tester);

      expect(aviso, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('no se pierde lo que la persona tipeó', () {
    testWidgets('texto con emoji y muy largo sigue en el campo y es lo que se guarda', (
      tester,
    ) async {
      fijarTamano(tester, const Size(390, 844));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await abrirElAlta(tester);
      final calle = find.byType(TextField).first;
      const tipeado = 'Av. Italia 😀 con una calle larguísima que nadie escribiría a mano';
      await tester.enterText(calle, tipeado);
      await tester.pump();

      await llegaLaRespuesta(tester, colgada);
      await asentar(tester);

      expect(aviso, findsOneWidget);
      expect(find.byType(TextField).first, findsOneWidget);
      final controlador = tester.widget<TextField>(find.byType(TextField).first).controller;
      expect(controlador?.text, isNotEmpty, reason: 'el campo no se vació');
      await tocar(tester, botonRegistrar);
      expect(repo.llamadas, hasLength(1));
      expect(repo.llamadas.single.ubicacion.calle, isNotNull);
      expect(titulo, findsOneWidget);
    });
  });

  group('hojas y diálogos abiertos cuando llega la respuesta', () {
    testWidgets('una hoja modal abierta: al cerrarla, la pantalla de la cuenta y ningún aviso', (
      tester,
    ) async {
      fijarTamano(tester, const Size(390, 844));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      unawaited(
        showModalBottomSheet<void>(
          context: tester.element(principal),
          builder: (_) => const SizedBox(height: 200, child: Center(child: Text('Una hoja'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Una hoja'), findsOneWidget);

      await llegaLaRespuesta(tester, colgada);
      await tester.pump();

      expect(find.text('Una hoja'), findsOneWidget, reason: 'lo abierto no se cierra solo');
      expect(aviso, findsOneWidget);
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();

      expect(find.text('Una hoja'), findsNothing);
      expect(titulo, findsOneWidget);
      expect(aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un diálogo abierto: lo cierra y llega a la cuenta sin aviso', (tester) async {
      fijarTamano(tester, const Size(390, 844));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.pendienteAsignacion);
      unawaited(
        showDialog<void>(
          context: tester.element(principal),
          builder: (_) => const AlertDialog(content: Text('Un diálogo')),
        ),
      );
      await tester.pumpAndSettle();

      await llegaLaRespuesta(tester, colgada);
      await tester.pump();
      expect(find.text('Un diálogo'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(aviso, findsNothing);
    });
  });

  group('cerrar sesión con el aviso a la vista', () {
    testWidgets('el login queda sin aviso y la sesión nueva no hereda el de la anterior', (
      tester,
    ) async {
      fijarTamano(tester, const Size(700, 1000));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await abrirConfiguracion(tester);
      await llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();
      expect(aviso, findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();

      expect(botonLogin, findsOneWidget);
      expect(aviso, findsNothing, reason: 'el aviso de la cuenta anterior no queda sobre el login');
      expect(find.byType(MaterialBanner), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Entendido» y el atrás', () {
    testWidgets('después de «Entendido», atrás lleva a la cuenta y no vuelve ningún aviso', (
      tester,
    ) async {
      fijarTamano(tester, const Size(700, 1000));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await abrirConfiguracion(tester);
      await llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      await tester.tap(entendido);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(titulo, findsOneWidget);
      expect(aviso, findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('el atrás del sistema con el aviso a la vista lleva a la cuenta', (tester) async {
      fijarTamano(tester, const Size(700, 1000));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.pendienteAsignacion);
      await abrirConfiguracion(tester);
      await llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(aviso, findsNothing);
    });
  });

  group('literales de la HU-AUTH-008', () {
    testWidgets('el aviso de la suspendida dice el literal de la HU, entero', (tester) async {
      fijarTamano(tester, const Size(700, 1000));
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await abrirConfiguracion(tester);

      await llegaLaRespuesta(tester, colgada);

      // El literal de la HU, y detrás la frase que suma el aviso sobre algo abierto (decisión P1 del
      // 25/10): se puede terminar y guardar lo que estaba abierto.
      expect(
        find.descendant(
          of: aviso,
          matching: find.text('$literalSuspendida Podés terminar y guardar lo que tenés abierto.'),
        ),
        findsOneWidget,
      );
      expect(TextosModuloBloqueado.suspendida, literalSuspendida);
    });

    testWidgets('la pantalla de la cuenta suspendida trae el literal de la HU', (tester) async {
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.suspendida);
      await llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();

      expect(find.text(literalSuspendida), findsWidgets);
      expect(find.text(TextosEsperaAsignacion.suspendida), findsOneWidget);
    });
  });

  group('pendiente y después asignada', () {
    testWidgets('restringida como pendiente y luego asignada: vuelve a entrar al inicio (sin '
        'asignación que mostrar, 18-A07 no se queda)', (tester) async {
      final colgada = await enElInicio(tester, contestara: EstadoCuenta.pendienteAsignacion);
      await llegaLaRespuesta(tester, colgada);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);

      backend
        ..demora = null
        ..estado = EstadoCuenta.activa;
      contenedor.invalidate(estadoCuentaProvider);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(principal, findsOneWidget);
      expect(titulo, findsNothing);
    });
  });
}
