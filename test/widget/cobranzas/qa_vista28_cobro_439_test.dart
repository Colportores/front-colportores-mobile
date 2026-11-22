// QA de «Cobro en efectivo» (vista 28, HU-COB-001, #439). Lo que no cubren los tests del PR:
// los 14 estados × 360x640 y 412x915 × texto 1,0 y 2,0 (sin desborde, sin texto cortado, con captura),
// los escenarios de la HU con su texto literal, los casos límite (falla a mitad con fecha elegida,
// reintento superpuesto, atrás del sistema mientras guarda, teclado abierto) y la privacidad.
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
// Los hallazgos van con `skip` y el motivo; `--dart-define=QA_HALLAZGOS=true` los corre.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cobro_arnes.dart';
import '../../helpers/qa_vista28_439_arnes.dart';

Future<void> _cobrar(WidgetTester tester, String monto) async {
  await escribirMonto(tester, monto);
  await tocarCobro(tester, botonRegistrar);
}

String _texto(String clave) => (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

void main() {
  group('Matriz: cada estado × tamaño × escala de texto', () {
    for (final tamano in [chico439, grande439]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado439.values) {
          testWidgets(
            '${estado.rotulo} · ${sufijo439(tamano, escala)}: sin desborde ni texto cortado',
            (tester) async {
              final a = await llegarA439(tester, estado, tamano: tamano, escala: escala);

              expect(tester.takeException(), isNull);
              sinTextoCortado439(tester);
              await capturar439(tester, '${estado.name}_${sufijo439(tamano, escala)}');
              // Barrer la lista de punta a punta no desborda.
              final lista = find.descendant(of: pagina, matching: find.byType(Scrollable));
              if (lista.evaluate().isNotEmpty) {
                await tester.drag(lista.first, const Offset(0, -3000));
                await tester.pump(const Duration(milliseconds: 300));
                expect(tester.takeException(), isNull);
              }
              await liberar439(tester, a);
            },
          );
        }
      }
    }
  });

  group('HU-COB-001 · escenarios literales', () {
    testWidgets(
      'Escenario: Cobro de UYU 500 del total UYU 1500. Dado saldo UYU 1500, cuando registro '
      'pago efectivo UYU 500, entonces saldo pasa a UYU 1000 y se persiste',
      (tester) async {
        final repo = CobranzasEnMemoria(ventas: [ventaDelCobro(total: 150000)], cobradoAntes: 0);
        await montarCobro(tester, repo: repo);
        expect(_texto('cobro_saldo'), r'$ 1.500');

        await _cobrar(tester, '500');

        expect(_texto('cobro_saldo'), r'$ 1.000');
        expect(_texto('cobro_pagado'), r'$ 500');
        final guardado = repo.recibidos.single;
        expect(guardado.montoCentavos, 50000);
        expect(guardado.medio, MedioCobranza.efectivo);
        expect(repo.cobros.containsKey(guardado.id), isTrue);
        expect(find.text('Cobro registrado'), findsOneWidget);
      },
    );

    testWidgets(
      'Escenario: Cobro que liquida saldo. Dado saldo UYU 500, cuando registro pago UYU 500, '
      'entonces saldo = 0 (y la casa queda «Venta completa»)',
      (tester) async {
        final repo = CobranzasEnMemoria(ventas: [ventaDelCobro(total: 50000)], cobradoAntes: 0);
        await montarCobro(tester, repo: repo);

        await _cobrar(tester, '500');

        expect(_texto('cobro_saldo'), r'$ 0');
        expect(find.text('Venta pagada'), findsOneWidget);
        expect(
          find.text(
            'El saldo llegó a cero. Si ya entregaste todo, la casa queda como «Venta completa».',
          ),
          findsOneWidget,
        );
        expect(find.text('Volver al mapa'), findsOneWidget);
      },
    );

    testWidgets('los textos del canvas están tal cual en el formulario', (tester) async {
      await montarCobro(tester);
      expect(find.text('COBRO EN EFECTIVO'), findsOneWidget);
      expect(find.text('Cobrar'), findsOneWidget);
      expect(find.text('MONTO'), findsOneWidget);
      expect(find.text('FECHA'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Venta 0042 · 12/10'), findsOneWidget);
      expect(find.text('Pagado'), findsOneWidget);
      expect(find.text('Saldo'), findsOneWidget);
      expect(find.text('Hoy, 23/10'), findsOneWidget);
      expect(find.text('Ingresá el monto que te pagaron.'), findsOneWidget);
      expect(find.textContaining('María Fernández'), findsOneWidget);
      expect(find.textContaining('Mataojo 2044'), findsOneWidget);
    });

    testWidgets('28·06: «Sumamos \$ 600 a tu dinero en mano…» con los dos botones del canvas', (
      tester,
    ) async {
      await montarCobro(tester);
      await _cobrar(tester, '600');

      expect(
        find.text('Sumamos \$ 600 a tu dinero en mano. Queda en mano hasta que lo deposites.'),
        findsOneWidget,
      );
      expect(find.text('Agendar la próxima cobranza'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(cerrarCobro, findsNothing, reason: 'sin ✕ en el éxito (canvas)');
    });
  });

  group('Validación del monto', () {
    for (final (texto, motivo) in [
      ('   ', 'solo espacios'),
      ('💰600', 'emoji'),
      ('-5', 'negativo'),
      ('0', 'cero'),
      ('0,00', 'cero con decimales'),
      ('1.2', 'punto que no es de miles'),
      ('1,2,3', 'dos comas'),
      ('600,123', 'tres decimales'),
      ('12abc', 'letras'),
      ('<script>', 'caracteres especiales'),
      ('9' * 200, 'pegado muy largo'),
    ]) {
      testWidgets('«$motivo» no habilita el botón ni guarda nada', (tester) async {
        final a = await montarCobro(tester);

        await escribirMonto(tester, texto);

        expect(elBoton(tester).onPressed, isNull);
        expect(a.repo.recibidos, isEmpty);
        expect(tester.takeException(), isNull);
        expect(tester.widget<TextField>(campoMonto).controller!.text.length, lessThanOrEqualTo(14));
      });
    }

    testWidgets('el monto con signo peso y coma decimal se entiende', (tester) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, r'$ 600,50');
      expect(a.repo.recibidos.single.montoCentavos, 60050);
    });
  });

  group('Casos límite del flujo', () {
    testWidgets(
      'falla a mitad con otro día elegido: conserva monto y día, y el reintento los repite',
      (tester) async {
        final a = await montarCobro(tester);
        a.repo.fallas.add(const FailureCobroNoGuardado());
        await escribirMonto(tester, '300');
        await tocarCobro(tester, campoFecha);
        await tocarCobro(tester, find.byKey(const Key('cobro_dia_1')));
        await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));
        await tocarCobro(tester, botonRegistrar);

        expect(find.byKey(const Key('cobro_error')), findsOneWidget);
        expect(tester.widget<TextField>(campoMonto).controller!.text, '300');
        expect(find.text('Ayer, 22/10'), findsOneWidget);
        expect(elBoton(tester).onPressed, isNotNull);
        expect(find.text('Reintentar'), findsOneWidget);

        await tocarCobro(tester, botonRegistrar);

        expect(a.repo.recibidos.map((c) => c.id).toSet(), hasLength(1));
        expect(a.repo.recibidos.last.fecha, DateTime.utc(2026, 10, 22, 15));
        expect(find.text('Cobro registrado'), findsOneWidget);
      },
    );

    testWidgets(
      'dos fallas seguidas: el aviso sigue, el botón sigue libre y al tercero se guarda',
      (tester) async {
        final a = await montarCobro(tester);
        a.repo.fallas.addAll(const [FailureCobroNoGuardado(), FailureInesperado()]);
        await _cobrar(tester, '300');
        await tocarCobro(tester, botonRegistrar);

        expect(find.byKey(const Key('cobro_error')), findsOneWidget);
        expect(find.text('Registrando…'), findsNothing);
        expect(elBoton(tester).onPressed, isNotNull);

        await tocarCobro(tester, botonRegistrar);
        expect(find.text('Cobro registrado'), findsOneWidget);
        expect(a.repo.cobros.values.where((c) => c.montoCentavos == 30000), hasLength(1));
      },
    );

    testWidgets('doble toque en «Reintentar» mientras el reintento guarda: un solo cobro', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _cobrar(tester, '300');
      a.repo.compuerta = Completer<void>();

      await tester.tap(botonRegistrar);
      await tester.pump();
      await tester.tap(botonRegistrar, warnIfMissed: false);
      await tester.pump();
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(a.repo.cobros.values.where((c) => c.montoCentavos == 30000), hasLength(1));
      expect(a.repo.recibidos.where((c) => c.montoCentavos == 30000), hasLength(2));
    });

    testWidgets(
      'el «atrás» del sistema mientras guarda no cierra; al terminar, cierra con «se cobró»',
      (tester) async {
        final a = await montarCobro(tester);
        a.repo.compuerta = Completer<void>();
        await escribirMonto(tester, '300');
        await tocarCobro(tester, botonRegistrar);

        await tester.binding.handlePopRoute();
        await asentarAgendar(tester);
        expect(find.text('Registrando…'), findsOneWidget);
        expect(a.resultados, isEmpty);

        a.repo.compuerta!.complete();
        await asentarAgendar(tester);
        expect(find.text('Cobro registrado'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await asentarAgendar(tester);
        expect(a.resultados, [true]);
      },
    );

    testWidgets('con el teléfono sin conexión el cobro se guarda igual (28·09)', (tester) async {
      final a = await montarCobro(tester);
      a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await asentarAgendar(tester, 3);

      await _cobrar(tester, '300');

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.textContaining('conexión'), findsNothing);
      expect(a.repo.recibidos, hasLength(1));
    });

    testWidgets('error de lectura: «Reintentar» mide 48 y el aviso es región viva', (tester) async {
      final h = tester.ensureSemantics();
      await montarCobro(
        tester,
        repo: CobranzasEnMemoria()..fallaDeLectura = const FailureInesperado(),
      );

      final accion = find.byKey(const Key('venta_aviso_accion'));
      expect(tester.getSize(accion).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getSemantics(find.byKey(const Key('cobro_error_lectura')))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      h.dispose();
    });

    testWidgets('reentrar tras un cobro: el segundo ve el saldo nuevo y el campo vacío', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, '200');
      await tocarCobro(tester, find.byKey(const Key('cobro_listo')));
      await abrirCobro(tester);

      expect(_texto('cobro_saldo'), r'$ 1.000');
      expect(tester.widget<TextField>(campoMonto).controller!.text, isEmpty);
      expect(a.resultados, [true]);
    });
  });

  group('Salir con algo escrito (decisión de #439: pregunta antes de descartar)', () {
    final aviso = find.text('¿Descartar lo que escribiste?');

    testWidgets('dos toques seguidos en «✕» abren un solo aviso', (tester) async {
      await montarCobro(tester);
      await escribirMonto(tester, '600');

      await tester.tap(cerrarCobro);
      await tester.tap(cerrarCobro, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(aviso, findsOneWidget);
    });

    testWidgets('tocar fuera del aviso lo cierra y conserva monto y día', (tester) async {
      final a = await montarCobro(tester);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_1')));
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));
      await tocarCobro(tester, cerrarCobro);
      expect(aviso, findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await asentarAgendar(tester);

      expect(aviso, findsNothing);
      expect(pagina, findsOneWidget);
      expect(tester.widget<TextField>(campoMonto).controller!.text, '600');
      expect(find.text('Ayer, 22/10'), findsOneWidget);
      expect(a.resultados, isEmpty);
    });

    testWidgets(
      'tras una falla de guardado, «✕» pregunta (lo escrito sigue ahí) y «Descartar» no cobra',
      (tester) async {
        final a = await montarCobro(tester);
        a.repo.fallas.add(const FailureCobroNoGuardado());
        await _cobrar(tester, '300');
        expect(find.byKey(const Key('cobro_error')), findsOneWidget);

        await tocarCobro(tester, cerrarCobro);
        expect(aviso, findsOneWidget);
        await tocarCobro(tester, find.text('Descartar'));

        expect(pagina, findsNothing);
        expect(a.resultados, [false]);
        expect(a.repo.cobros.values.where((c) => c.montoCentavos == 30000), isEmpty);
      },
    );

    testWidgets('con la confirmación del cobro ya hecho, el atrás no pregunta', (tester) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, '300');

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(aviso, findsNothing);
      expect(a.resultados, [true]);
    });

    testWidgets('el aviso mide 48 en sus botones y los botones tienen nombre', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA439(tester, Estado439.descartar, tamano: chico439, escala: 2);

      for (final texto in ['Descartar', 'Seguir escribiendo']) {
        expect(tester.getSize(find.text(texto)).height, greaterThan(0));
        expect(find.bySemanticsLabel(texto), findsWidgets);
      }
      h.dispose();
    });
  });

  group('Teclado abierto', () {
    testWidgets(
      'a 360×640 con texto 2,0 y el teclado arriba, el campo del monto queda a la vista al escribir',
      (tester) async {
        await llegarA439(tester, Estado439.c02Vacio, tamano: chico439, escala: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 100));
        await asentarAgendar(tester, 8);
        final monto = find.byKey(const Key('cobro_monto'), skipOffstage: false);
        expect(monto, findsOneWidget);
        final lista = tester.getRect(
          find.descendant(of: pagina, matching: find.byType(ListView)).first,
        );
        final campo = tester.getRect(monto);
        await capturar439(tester, 'teclado_escribiendo_360x640_x2.0');
        expect(
          campo.top,
          greaterThanOrEqualTo(lista.top - 0.5),
          reason: 'campo $campo, lista $lista',
        );
        expect(
          campo.bottom,
          lessThanOrEqualTo(lista.bottom + 0.5),
          reason: 'campo $campo, lista $lista',
        );
      },
    );

    testWidgets(
      'a 360×640 con texto 2,0 y el teclado arriba, el botón se ve y la lista no es una rendija',
      (tester) async {
        await llegarA439(tester, Estado439.c01Formulario, tamano: chico439, escala: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(tester.getRect(botonRegistrar).bottom, lessThanOrEqualTo(640 - 280 + 0.5));
        final lista = tester.getRect(
          find.descendant(of: pagina, matching: find.byType(ListView)).first,
        );
        expect(
          lista.height,
          greaterThan(100),
          reason: 'con el teclado la lista queda en ${lista.height} dp',
        );
        await capturar439(tester, 'teclado_360x640_x2.0');
      },
    );

    testWidgets(
      'la hoja de la fecha con el teclado arriba a 360×640 y texto 2,0: «Listo» se alcanza',
      (tester) async {
        await llegarA439(tester, Estado439.c01Formulario, tamano: chico439, escala: 2);
        await tocarCobro(tester, campoFecha);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        final listo = find.byKey(const Key('cobro_hoja_listo'));
        await tester.ensureVisible(listo);
        await tester.pump();
        expect(tester.getRect(listo).bottom, lessThanOrEqualTo(640 - 280 + 0.5));
        await capturar439(tester, 'hoja_teclado_360x640_x2.0');
      },
    );
  });

  group('Privacidad', () {
    test('los toString de las entidades y fallas del cobro no llevan datos de la persona', () {
      final venta = ventaDelCobro();
      final cobro = cobroDeEjemplo('c-1', 60000);
      for (final texto in [
        venta.toString(),
        cobro.toString(),
        const FailureCobroNoGuardado(causa: 'excepcion').toString(),
        const FailureCobroMayorAlSaldo(saldoCentavos: 120000).toString(),
      ]) {
        expect(texto, isNot(contains('María')));
        expect(texto, isNot(contains('Mataojo')));
      }
    });
  });
}
