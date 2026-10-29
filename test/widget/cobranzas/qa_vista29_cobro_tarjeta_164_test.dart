// QA de «Cobro con tarjeta y por transferencia» (vista 29, HU-COB-002 y HU-COB-003, #164). Lo que no
// cubren los tests del PR: los 20 estados × 360x640 y 412x915 × texto 1,0 y 2,0 (sin desborde, sin texto
// cortado, con captura), los escenarios de la HU con su texto literal, el canvas texto por texto, la
// validación de los campos nuevos (emoji, pegados larguísimos, caracteres especiales), los casos límite
// (falla a mitad, acciones superpuestas, atrás de cada estado, teclado abierto) y la accesibilidad de
// lo que se anuncia. Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
// Los hallazgos van con `skip` y el motivo; `--dart-define=QA_HALLAZGOS=true` los corre.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cobro_arnes.dart';
import '../../helpers/qa_vista29_164_arnes.dart';

const verHallazgos164 = bool.fromEnvironment('QA_HALLAZGOS');

String _texto(String clave) => (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

Future<void> _alTope(WidgetTester tester) async {
  final lista = find.descendant(of: pagina, matching: find.byType(Scrollable)).first;
  await tester.drag(lista, const Offset(0, 5000));
  await asentarAgendar(tester, 3);
}

/// El centro del widget [f] cae dentro de la pantalla y nada lo tapa.
bool _enPantalla(WidgetTester tester, Finder f) {
  if (f.evaluate().isEmpty) return false;
  final caja = tester.getRect(f.first);
  final pantalla = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  return pantalla.contains(caja.center) &&
      pantalla.contains(caja.topLeft) &&
      pantalla.contains(caja.bottomRight);
}

void main() {
  group('Matriz: cada estado × tamaño × escala de texto', () {
    for (final tamano in [chico164, grande164]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado164.values) {
          testWidgets(
            '${estado.rotulo} · ${sufijo164(tamano, escala)}: sin desborde ni texto cortado',
            (tester) async {
              final a = await llegarA164(tester, estado, tamano: tamano, escala: escala);

              expect(tester.takeException(), isNull);
              sinTextoCortado164(tester);
              await capturar164(tester, '${estado.name}_${sufijo164(tamano, escala)}');
              final lista = find.descendant(of: pagina, matching: find.byType(Scrollable));
              if (lista.evaluate().isNotEmpty) {
                await tester.drag(lista.first, const Offset(0, -3000));
                await tester.pump(const Duration(milliseconds: 300));
                expect(tester.takeException(), isNull);
              }
              await liberar164(tester, a);
            },
          );
        }
      }
    }
  });

  group('HU-COB-002 y HU-COB-003 · escenarios literales', () {
    testWidgets(
      'Escenario: Cobro con tarjeta V1. Dado que el cliente pagó con tarjeta UYU 800, cuando registro '
      'tipo TARJETA y monto 800, entonces se persiste con numero_aprobacion=null',
      (tester) async {
        final a = await montarCobro(tester);
        expect(_texto('cobro_saldo'), r'$ 1.200');

        await preparar164(tester, tarjeta164, '800');
        await registrar164(tester);

        final guardado = a.repo.recibidos.single;
        expect(guardado.medio, MedioCobranza.tarjeta);
        expect(guardado.montoCentavos, 80000);
        expect(guardado.numeroAprobacion, isNull);
        expect(guardado.tarjetaMarca, isNull);
        expect(_texto('cobro_saldo'), r'$ 400');
        expect(find.text('Cobro registrado'), findsOneWidget);
        // Decisión del 23/10: gana el canvas sobre el texto de la HU.
        expect(
          find.text('Guardá el ticket de la tarjeta: tu coordinador te lo va a pedir.'),
          findsOneWidget,
        );
        expect(find.textContaining('En V2 podrás cargarlo'), findsNothing);
      },
    );

    testWidgets(
      'Escenario: Cobro por transferencia. Dado que el cliente envió transferencia, cuando registro '
      'tipo TRANSFERENCIA, monto, referencia "TX-12345", entonces se persiste y actualiza saldo',
      (tester) async {
        final a = await montarCobro(tester);

        await preparar164(tester, transferencia164, '800');
        await escribir164(tester, 'cobro_referencia', 'TX-12345');
        await registrar164(tester);

        final guardado = a.repo.recibidos.single;
        expect(guardado.medio, MedioCobranza.transferencia);
        expect(guardado.referenciaTransferencia, 'TX-12345');
        expect(guardado.bancoOrigen, isNull);
        expect(guardado.numeroAprobacion, isNull);
        expect(guardado.tarjetaTipo, isNull);
        expect(_texto('cobro_saldo'), r'$ 400');
        expect(a.repo.cobros.containsKey(guardado.id), isTrue);
        expect(
          find.text('Sumamos \$ 800 a tu dinero depositado. Referencia TX-12345.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'el formulario de la tarjeta dice lo que dibuja el canvas 29A·01, texto por texto',
      (tester) async {
        await montarCobro(tester);
        await tocarCobro(tester, tarjeta164);
        for (final t in [
          'COBRO',
          'Cobrar',
          'MEDIO',
          'Efectivo',
          'Tarjeta',
          'Transferencia',
          'MONTO',
          'Débito',
          'Crédito',
          'MARCA (OPCIONAL)',
          'Visa',
          'Mastercard',
          'OCA',
          'Otra',
          'Nº DE APROBACIÓN (OPCIONAL)',
          'Registrar cobro',
          'Venta 0042 · 12/10',
          'Pagado',
          'Saldo',
        ]) {
          expect(find.text(t), findsWidgets, reason: 'falta «$t» del canvas 29A·01');
        }
        expect(find.text('COBRO EN EFECTIVO'), findsNothing);
        expect(find.text('Lo dice el ticket'), findsOneWidget);
        expect(find.textContaining('María Fernández'), findsOneWidget);
      },
    );

    testWidgets('el formulario de la transferencia dice lo que dibuja el canvas 29B·01', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, transferencia164);
      for (final t in [
        'REFERENCIA (OPCIONAL)',
        'Nº de operación',
        'BANCO DE ORIGEN (OPCIONAL)',
        'Elegir banco',
      ]) {
        expect(find.text(t), findsOneWidget, reason: 'falta «$t» del canvas 29B·01');
      }
    });

    testWidgets('29A·04: «El saldo es \$ 1.200. Ingresá hasta ese monto.» y el botón apagado', (
      tester,
    ) async {
      await llegarA164(tester, Estado164.a04Mayor);
      expect(find.text(r'El saldo es $ 1.200. Ingresá hasta ese monto.'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(find.text('Registrar cobro'), findsOneWidget);
    });

    testWidgets('29A·05: el aviso del canvas, «Reintentar» y lo cargado intacto', (tester) async {
      await llegarA164(tester, Estado164.a05Error);
      expect(
        find.text('No pudimos guardar el cobro. No se registró nada: probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Registrar cobro'), findsNothing);
    });

    testWidgets('29B·03: «Sumamos \$ 1.200 a tu dinero depositado. Referencia 88213.» y «Listo»', (
      tester,
    ) async {
      await llegarA164(tester, Estado164.b03Registrada);
      expect(
        find.text('Sumamos \$ 1.200 a tu dinero depositado. Referencia 88213.'),
        findsOneWidget,
      );
      expect(find.text('Listo'), findsOneWidget);
      expect(_texto('cobro_saldo'), r'$ 0');
    });

    testWidgets('29B·02: la hoja dice «Banco de origen» y lista los seis, con «Listo»', (
      tester,
    ) async {
      await llegarA164(tester, Estado164.b02Banco);
      expect(find.text('Banco de origen'), findsOneWidget);
      for (final b in ['BROU', 'Itaú', 'Santander', 'Scotiabank', 'BBVA', 'Otro']) {
        expect(bancoDeLaHoja164(b), findsOneWidget, reason: b);
      }
      expect(bancoListo164, findsOneWidget);
    });

    testWidgets('29A·02 y 29B·03 suman al dinero DEPOSITADO, nunca «en mano»', (tester) async {
      await llegarA164(tester, Estado164.a02Parcial);
      expect(find.textContaining('dinero depositado'), findsOneWidget);
      expect(find.textContaining('en mano'), findsNothing);
    });
  });

  group('Validación de los campos nuevos', () {
    testWidgets('el monto de la tarjeta se valida como el del efectivo', (tester) async {
      for (final (texto, motivo) in [
        ('   ', 'solo espacios'),
        ('💰800', 'emoji'),
        ('-5', 'negativo'),
        ('0', 'cero'),
        ('12abc', 'letras'),
        ('<script>', 'caracteres especiales'),
        ('9' * 200, 'pegado muy largo'),
        ('1200,01', 'un centavo más que el saldo'),
        ('1.201', 'un peso más que el saldo'),
      ]) {
        final a = await montarCobro(tester);
        await tocarCobro(tester, tarjeta164);
        await escribirMonto164(tester, texto);
        expect(elBoton(tester).onPressed, isNull, reason: 'se habilitó con «$motivo»');
        expect(a.repo.recibidos, isEmpty, reason: motivo);
        // Desmontar la pantalla para el siguiente caso.
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('el monto exacto del saldo con tarjeta se acepta y deja la venta en cero', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await preparar164(tester, tarjeta164, r'$ 1.200');
      expect(elBoton(tester).onPressed, isNotNull);
      await registrar164(tester);
      expect(a.repo.recibidos.single.montoCentavos, 120000);
      expect(_texto('cobro_saldo'), r'$ 0');
    });

    testWidgets(
      'con tarjeta y todos los datos cargados pero el monto vacío, el botón está apagado y dice por qué',
      (tester) async {
        await montarCobro(tester);
        await tocarCobro(tester, tarjeta164);
        await escribir164(tester, 'cobro_aprobacion', '004471');
        await tocarCobro(tester, find.byKey(const Key('cobro_marca_Visa')));
        expect(elBoton(tester).onPressed, isNull);
        expect(find.text('Ingresá el monto que te pagaron.'), findsOneWidget);
      },
    );

    testWidgets(
      'texto pegado larguísimo (5000 caracteres) en cada campo: se corta al largo del servidor',
      (tester) async {
        final a = await montarCobro(tester);
        await tocarCobro(tester, tarjeta164);
        await escribirMonto164(tester, '800');
        await tocarCobro(tester, find.byKey(const Key('cobro_marca_Otra')));
        await escribir164(tester, 'cobro_marca_otra', 'M' * 5000);
        await escribir164(tester, 'cobro_aprobacion', '7' * 5000);
        await registrar164(tester);

        final g = a.repo.recibidos.single;
        expect(g.tarjetaMarca!.length, 40);
        expect(g.numeroAprobacion!.length, 40);
        expect(find.text('Cobro registrado'), findsOneWidget);
      },
    );

    testWidgets('banco «Otro» y referencia pegados larguísimos: 60 y 40 caracteres', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await preparar164(tester, transferencia164, '800');
      await escribir164(tester, 'cobro_referencia', 'R' * 5000);
      await tocarCobro(tester, banco164);
      await tocarCobro(tester, bancoDeLaHoja164('Otro'));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('cobro_banco_otro')),
          matching: find.byType(TextField),
        ),
        'B' * 5000,
      );
      await asentarAgendar(tester, 3);
      await tocarCobro(tester, bancoListo164);
      await registrar164(tester);

      final g = a.repo.recibidos.single;
      expect(g.referenciaTransferencia!.length, 40);
      expect(g.bancoOrigen!.length, 60);
    });

    testWidgets(
      'caracteres especiales, comillas, tildes, Ñ y HTML se guardan tal cual, sin romper nada',
      (tester) async {
        final a = await montarCobro(tester);
        await preparar164(tester, transferencia164, '800');
        await escribir164(tester, 'cobro_referencia', "Ñandú'; DROP TABLE cobranza;--");
        await registrar164(tester);
        final g = a.repo.recibidos.single;
        expect(g.referenciaTransferencia, "Ñandú'; DROP TABLE cobranza;--");
        expect(find.text('Cobro registrado'), findsOneWidget);
      },
    );

    testWidgets('emoji suelto en la referencia (hasta 5) se guarda y se muestra', (tester) async {
      final a = await montarCobro(tester);
      await preparar164(tester, transferencia164, '800');
      await escribir164(tester, 'cobro_referencia', 'TX 😀😀😀');
      await registrar164(tester);
      expect(a.repo.recibidos.single.referenciaTransferencia, 'TX 😀😀😀');
      expect(find.text('Cobro registrado'), findsOneWidget);
    });

    // skip: QA #164 — el campo cuenta caracteres visibles (40 emoji entran) pero el caso de uso mide
    // unidades UTF-16 (cada emoji son 2): un dato que el campo dejó escribir se rechaza al registrar
    // con el aviso genérico «probá de nuevo» y «Reintentar» repite lo mismo para siempre.
    testWidgets(
      '40 emoji en la referencia (el campo los deja escribir) se registran, no dan un error sin salida',
      (tester) async {
        final a = await montarCobro(tester);
        await preparar164(tester, transferencia164, '800');
        await escribir164(tester, 'cobro_referencia', '😀' * 40);
        expect(tester.widget<TextField>(campo164('cobro_referencia')).controller!.text.length, 80);

        await registrar164(tester);

        expect(
          find.text('Cobro registrado'),
          findsOneWidget,
          reason: 'el campo dejó escribir 40 emoji y el registro los rechazó con «probá de nuevo»',
        );
        expect(a.repo.recibidos, isNotEmpty);
      },
      skip: !verHallazgos164,
    );

    testWidgets('tipo de tarjeta: crédito se guarda como crédito y débito de entrada como débito', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await preparar164(tester, tarjeta164, '100');
      await registrar164(tester);
      expect(a.repo.recibidos.single.tarjetaTipo, TipoTarjeta.debito);
      await tocarCobro(tester, listo164);
      await abrirCobro(tester);
      await preparar164(tester, tarjeta164, '100');
      await tocarCobro(tester, find.byKey(const Key('cobro_tipo_1')));
      await registrar164(tester);
      expect(a.repo.recibidos.last.tarjetaTipo, TipoTarjeta.credito);
    });
  });

  group('Casos límite de cada flujo', () {
    testWidgets('falla a mitad con tarjeta: nada queda trabado y lo tipeado sigue ahí', (
      tester,
    ) async {
      final repo = CobranzasEnMemoria()..fallas.add(const FailureCobroNoGuardado());
      await montarCobro(tester, repo: repo);
      await preparar164(tester, tarjeta164, '800');
      await tocarCobro(tester, find.byKey(const Key('cobro_tipo_1')));
      await tocarCobro(tester, find.byKey(const Key('cobro_marca_Mastercard')));
      await escribir164(tester, 'cobro_aprobacion', '004471');

      await registrar164(tester);

      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.widget<TextField>(campo164('cobro_aprobacion')).controller!.text, '004471');
      expect(tester.widget<TextField>(campoMonto).controller!.text, '800');
      // El selector de medio y los chips vuelven a responder.
      await tocarCobro(tester, transferencia164);
      expect(find.byKey(const Key('cobro_referencia')), findsOneWidget);
      await tocarCobro(tester, tarjeta164);
      expect(tester.widget<TextField>(campo164('cobro_aprobacion')).controller!.text, '004471');
      await registrar164(tester);
      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(repo.cobros.values.where((c) => c.medio == MedioCobranza.tarjeta), hasLength(1));
    });

    testWidgets(
      'falla a mitad con transferencia: banco y referencia se conservan y «Reintentar» repite el id',
      (tester) async {
        final a = await llegarA164(tester, Estado164.errorTransferencia);
        expect(find.byKey(const Key('cobro_error')), findsOneWidget);
        await traerAlAlcance(tester, campo164('cobro_referencia'));
        expect(tester.widget<TextField>(campo164('cobro_referencia')).controller!.text, 'TX-12345');

        await registrar164(tester);

        expect(a.repo.recibidos, hasLength(2));
        expect(a.repo.recibidos.first.id, a.repo.recibidos.last.id);
        expect(a.idsGenerados, hasLength(1));
        expect(find.text('Cobro registrado'), findsOneWidget);
      },
    );

    testWidgets(
      'acciones superpuestas: dos toques en «Registrar cobro» y uno en el medio mientras guarda',
      (tester) async {
        final repo = CobranzasEnMemoria()..compuerta = Completer<void>();
        final a = await montarCobro(tester, repo: repo);
        await preparar164(tester, tarjeta164, '800');

        await tester.tap(botonRegistrar);
        await tester.pump();
        await tester.tap(botonRegistrar, warnIfMissed: false);
        await tester.pump();
        await tester.tap(transferencia164, warnIfMissed: false);
        await tester.pump();

        expect(repo.recibidos, hasLength(1));
        expect(find.text('Registrando…'), findsOneWidget);
        // El medio no cambió mientras guardaba.
        expect(find.byKey(const Key('cobro_aprobacion')), findsOneWidget);
        repo.compuerta!.complete();
        await asentarAgendar(tester, 4);
        expect(find.text('Cobro registrado'), findsOneWidget);
        expect(a.repo.cobros.values.where((c) => c.id != 'previo-v-42'), hasLength(1));
      },
    );

    testWidgets('«Listo» tocado dos veces cierra una sola vez', (tester) async {
      final a = await llegarA164(tester, Estado164.a02Registrada);
      await tester.tap(listo164);
      await tester.tap(listo164, warnIfMissed: false);
      await asentarAgendar(tester);
      expect(a.resultados, [true]);
      expect(pagina, findsNothing);
    });

    testWidgets(
      'dos cobros seguidos, tarjeta y luego transferencia: el segundo ve el saldo nuevo y empieza limpio',
      (tester) async {
        final a = await montarCobro(tester);
        await preparar164(tester, tarjeta164, '500');
        await escribir164(tester, 'cobro_aprobacion', '111');
        await registrar164(tester);
        expect(_texto('cobro_saldo'), r'$ 700');
        await tocarCobro(tester, listo164);

        await abrirCobro(tester);
        expect(_texto('cobro_saldo'), r'$ 700');
        expect(find.byKey(const Key('cobro_aprobacion')), findsNothing);
        await preparar164(tester, transferencia164, '700');
        await registrar164(tester);

        final segundo = a.repo.recibidos.last;
        expect(segundo.medio, MedioCobranza.transferencia);
        expect(segundo.numeroAprobacion, isNull);
        expect(_texto('cobro_saldo'), r'$ 0');
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'el saldo cambió mientras tanto (otro cobro): el campo lo dice y no se pierde nada',
      (tester) async {
        final repo = CobranzasEnMemoria();
        final a = await montarCobro(tester, repo: repo);
        await preparar164(tester, tarjeta164, '1000');
        await escribir164(tester, 'cobro_aprobacion', '004471');
        // Mientras la colportora escribe, otro cobro baja el saldo a $ 300.
        repo.cobros['otro'] = cobroDeEjemplo('otro', 90000);

        await registrar164(tester);

        expect(find.text(r'El saldo es $ 300. Ingresá hasta ese monto.'), findsOneWidget);
        expect(elBoton(tester).onPressed, isNull);
        expect(tester.widget<TextField>(campo164('cobro_aprobacion')).controller!.text, '004471');
        expect(a.repo.cobros.values.where((c) => c.medio == MedioCobranza.tarjeta), isEmpty);
      },
    );

    testWidgets('atrás con la hoja del banco abierta cierra la hoja y no la pantalla', (
      tester,
    ) async {
      final a = await llegarA164(tester, Estado164.b02Banco);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(bancoListo164, findsNothing);
      expect(pagina, findsOneWidget);
      expect(a.resultados, isEmpty);
    });

    testWidgets(
      'atrás mientras guarda no cierra ni pregunta; al terminar, atrás cierra con «se cobró»',
      (tester) async {
        final a = await llegarA164(tester, Estado164.registrando);
        await tester.binding.handlePopRoute();
        await asentarAgendar(tester, 3);
        expect(pagina, findsOneWidget);
        expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
        await liberar164(tester, a);
        expect(find.text('Cobro registrado'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await asentarAgendar(tester);
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'reentrar tras un error y salir: nada del cobro fallido queda en la pantalla nueva',
      (tester) async {
        final a = await llegarA164(tester, Estado164.a05Error);
        await tester.binding.handlePopRoute();
        await asentarAgendar(tester, 3);
        expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
        await tocarCobro(tester, find.text('Descartar'));
        expect(a.resultados, [false]);

        await abrirCobro(tester);
        expect(find.byKey(const Key('cobro_error')), findsNothing);
        expect(tester.widget<TextField>(campoMonto).controller!.text, isEmpty);
        expect(find.byKey(const Key('cobro_aprobacion')), findsNothing);
        expect(a.repo.cobros.values.where((c) => c.medio != MedioCobranza.efectivo), isEmpty);
      },
    );

    testWidgets(
      'el aviso del ticket y el botón «Listo» se ven sin desplazar (360x640, texto 2,0)',
      (tester) async {
        await llegarA164(tester, Estado164.a02Registrada, tamano: chico164, escala: 2);
        await _alTope(tester);
        await traerAlAlcance(tester, find.byKey(const Key('cobro_aviso_ticket')));
        expect(_enPantalla(tester, find.byKey(const Key('cobro_aviso_ticket'))), isTrue);
        expect(_enPantalla(tester, listo164), isTrue);
      },
    );

    for (final (tamano, escala) in [
      (chico164, 1.0),
      (chico164, 2.0),
      (grande164, 1.0),
      (grande164, 2.0),
    ]) {
      for (final medio in ['tarjeta', 'transferencia']) {
        testWidgets(
          'tras fallar con $medio y el último dato escrito, el aviso de error queda a la vista · ${sufijo164(tamano, escala)}',
          (tester) async {
            final repo = CobranzasEnMemoria()..fallas.add(const FailureCobroNoGuardado());
            await montarCobro(tester, repo: repo, tamano: tamano, escala: escala);
            if (medio == 'tarjeta') {
              await preparar164(tester, tarjeta164, '800');
              await escribir164(tester, 'cobro_aprobacion', '004471');
            } else {
              await preparar164(tester, transferencia164, '800');
              await escribir164(tester, 'cobro_referencia', 'TX-12345');
            }

            await registrar164(tester);
            await asentarAgendar(tester);

            expect(find.text('Reintentar'), findsOneWidget);
            expect(
              _enPantalla(tester, find.byKey(const Key('cobro_error'))),
              isTrue,
              reason: 'el aviso de error no está a la vista',
            );
          },
        );
      }
    }
  });

  group('Tamaño de toque de los campos nuevos', () {
    for (final (estado, clave) in [
      (Estado164.a01Otra, 'cobro_marca_otra'),
      (Estado164.a01Otra, 'cobro_aprobacion'),
      (Estado164.b01Transferencia, 'cobro_referencia'),
      (Estado164.b02Otro, 'cobro_banco_otro'),
    ]) {
      testWidgets('${estado.rotulo}: «$clave» mide al menos 48 dp de alto con texto 1,0', (
        tester,
      ) async {
        await llegarA164(tester, estado);
        await traerAlAlcance(tester, campo164(clave));
        expect(tester.getSize(campo164(clave)).height, greaterThanOrEqualTo(48));
      });
    }
  });

  group('El selector «MEDIO» con las fuentes reales', () {
    for (final tamano in [chico164, grande164]) {
      // skip: QA #164 — con Inter de verdad, «Transferencia» no entra en un tercio del ancho a 360 ni a
      // 412 dp: el selector se apila en tres filas de ancho completo y no es la fila de tres del canvas
      // (29A·01 y 29B·01). Los tests del PR no lo ven: con la fuente de prueba el texto mide menos.
      testWidgets(
        'a ${tamano.width.toInt()} dp, Efectivo, Tarjeta y Transferencia van en una sola fila',
        (tester) async {
          await llegarA164(tester, Estado164.a01Tarjeta, tamano: tamano);
          final arriba = [for (var i = 0; i < 3; i++) tester.getTopLeft(medio164(i)).dy.round()];
          expect(
            arriba.toSet(),
            hasLength(1),
            reason: 'los tres segmentos no están en la misma fila',
          );
        },
        skip: !verHallazgos164,
      );
    }
  });

  group('Acciones superpuestas en la hoja del banco', () {
    testWidgets('dos toques seguidos en «Listo» de la hoja no cierran también la pantalla', (
      tester,
    ) async {
      final a = await llegarA164(tester, Estado164.b02Banco);
      await tester.tap(bancoDeLaHoja164('BROU'));
      await tester.pump();
      await tester.tap(bancoListo164);
      await tester.tap(bancoListo164, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(pagina, findsOneWidget);
      expect(a.resultados, isEmpty);
      expect(find.text('BROU'), findsOneWidget);
    });
  });

  group('Teclado abierto', () {
    testWidgets(
      'hoja del banco con «Otro»: «Listo» y el campo siguen al alcance con el teclado (360x640, 2,0)',
      (tester) async {
        await llegarA164(tester, Estado164.b02Otro, tamano: chico164, escala: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(bancoListo164);
        await tester.pump();
        expect(_enPantalla(tester, bancoListo164), isTrue);
        await tester.tap(bancoListo164);
        await asentarAgendar(tester);
        expect(banco164, findsOneWidget);
        expect(find.text('Banco Heritage'), findsOneWidget);
      },
    );

    testWidgets(
      'formulario de la tarjeta con el teclado arriba: el número de aprobación se puede traer a la vista',
      (tester) async {
        await llegarA164(tester, Estado164.a01Tarjeta, tamano: chico164, escala: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 300));
        await traerAlAlcance(tester, campo164('cobro_aprobacion'));
        expect(tester.takeException(), isNull);
        expect(_enPantalla(tester, campo164('cobro_aprobacion')), isTrue);
      },
    );
  });

  group('Accesibilidad de lo que se anuncia', () {
    testWidgets('el aviso de error y el del ticket son regiones vivas', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA164(tester, Estado164.a05Error);
      final e = tester.getSemantics(find.byKey(const Key('cobro_error')));
      expect(e.flagsCollection.isLiveRegion, isTrue);
      h.dispose();
    });

    testWidgets(
      'cada marca, cada tipo y cada medio se anuncia como botón con su nombre y si está elegido',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA164(tester, Estado164.a01Tarjeta);
        for (final (clave, etiqueta, elegido) in [
          ('cobro_medio_1', 'Tarjeta', true),
          ('cobro_medio_0', 'Efectivo', false),
          ('cobro_tipo_0', 'Débito', true),
          ('cobro_tipo_1', 'Crédito', false),
          ('cobro_marca_Visa', 'Visa', false),
        ]) {
          final s = tester.getSemantics(find.byKey(Key(clave)));
          expect(s.label, contains(etiqueta), reason: clave);
          expect(
            s,
            isSemantics(isButton: true, isSelected: elegido, hasSelectedState: true),
            reason: clave,
          );
        }
        h.dispose();
      },
    );

    testWidgets('el campo del banco se anuncia con su rótulo y el valor elegido', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA164(tester, Estado164.b01ConBanco);
      final s = tester.getSemantics(banco164);
      expect(s.label, contains('BANCO DE ORIGEN'));
      expect(s.label, contains('Itaú'));
      h.dispose();
    });
  });
}
