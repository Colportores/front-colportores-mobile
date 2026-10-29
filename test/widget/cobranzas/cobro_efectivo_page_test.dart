// «Cobro en efectivo» (vista 28, HU-COB-001, #439): un grupo por artboard (28·01 a 28·09) y los casos
// límite de cada flujo: doble toque, falla a mitad de la acción, dos cobros seguidos, volver atrás y
// reentrar, y datos límite (textos largos, montos grandes, textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/cobro_arnes.dart';
import '../../helpers/persona_falsos.dart';

String _texto(String clave) => (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

Future<void> _cobrar(WidgetTester tester, String monto) async {
  await escribirMonto(tester, monto);
  await tocarCobro(tester, botonRegistrar);
}

void main() {
  group('28·01 · Cobro en efectivo', () {
    testWidgets('dado el canvas, cuando se abre, entonces dibuja la venta, el monto y la fecha', (
      tester,
    ) async {
      await montarCobro(tester);

      expect(pagina, findsOneWidget);
      expect(find.text('COBRO EN EFECTIVO'), findsOneWidget);
      expect(find.text('Cobrar'), findsOneWidget);
      expect(find.text('María Fernández · Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(find.text('Venta 0042 · 12/10'), findsOneWidget);
      expect(_texto('cobro_total'), r'$ 4.500');
      expect(_texto('cobro_pagado'), r'$ 3.300');
      expect(_texto('cobro_saldo'), r'$ 1.200');
      expect(find.text('MONTO'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('MONTO')), findsOneWidget);
      expect(tester.widget<TextField>(campoMonto).decoration!.hintText, r'$ 0');
      expect(find.text(r'$ 0'), findsOneWidget);
      expect(find.text('FECHA'), findsOneWidget);
      expect(find.text('Hoy, 23/10'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Registrar cobro'), findsOneWidget);
      expect(find.byKey(const Key('cobro_error')), findsNothing);
    });

    testWidgets('el monto se escribe con el teclado numérico y arranca con el foco', (
      tester,
    ) async {
      await montarCobro(tester);

      final campo = tester.widget<TextField>(campoMonto);
      expect(campo.autofocus, isTrue);
      expect(campo.keyboardType, const TextInputType.numberWithOptions(decimal: true));
    });

    testWidgets('«Registrar cobro» guarda el cobro de UYU 500 y el saldo pasa a 700', (
      tester,
    ) async {
      final a = await montarCobro(tester);

      await _cobrar(tester, '500');

      final cobro = a.repo.recibidos.single;
      expect(cobro.id, 'cobro-1');
      expect(cobro.ventaId, 'v-42');
      expect(cobro.montoCentavos, 50000);
      expect(cobro.medio, MedioCobranza.efectivo);
      expect(cobro.fecha, hoyDelCobro);
      expect(cobro.auditoria.createdBy, 'col-1');
      expect(_texto('cobro_saldo'), r'$ 700');
    });

    for (final (escrito, centavos) in [
      ('600', 60000),
      (r'$ 600', 60000),
      ('1.200', 120000),
      ('600,50', 60050),
      (' 600 ', 60000),
    ]) {
      testWidgets('el monto «$escrito» vale $centavos centavos', (tester) async {
        final a = await montarCobro(tester);

        await _cobrar(tester, escrito);

        expect(a.repo.recibidos.single.montoCentavos, centavos);
      });
    }
  });

  group('28·02 · Monto vacío', () {
    testWidgets('el botón está apagado y dice por qué', (tester) async {
      final a = await montarCobro(tester);

      expect(elBoton(tester).onPressed, isNull);
      expect(find.text('Ingresá el monto que te pagaron.'), findsOneWidget);
      // Apagado pero legible: el rótulo es blanco, no la tinta al 38 % de Material.
      expect(contrasteDelBoton(tester, 'Registrar cobro'), greaterThanOrEqualTo(3));

      await tester.tap(botonRegistrar, warnIfMissed: false);
      await asentarAgendar(tester);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('al escribir el monto el botón se enciende y la nota se va', (tester) async {
      await montarCobro(tester);

      await escribirMonto(tester, '100');
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.text('Ingresá el monto que te pagaron.'), findsNothing);

      await escribirMonto(tester, '');
      expect(elBoton(tester).onPressed, isNull);
      expect(find.text('Ingresá el monto que te pagaron.'), findsOneWidget);
    });

    for (final texto in ['0', '0,00', 'abc', '12,345', '-5', '1.2.3', r'$']) {
      testWidgets('el monto «$texto» no es un monto: el campo lo marca y no se guarda', (
        tester,
      ) async {
        final a = await montarCobro(tester);

        await escribirMonto(tester, texto);

        expect(elBoton(tester).onPressed, isNull);
        expect(a.repo.recibidos, isEmpty);
        if (texto != r'$') {
          expect(find.text('Escribí un monto válido, por ejemplo 600.'), findsOneWidget);
        }
      });
    }
  });

  group('28·03 · Monto mayor al saldo', () {
    testWidgets('un monto mayor al saldo se marca con el saldo y el botón queda apagado', (
      tester,
    ) async {
      final a = await montarCobro(tester);

      await escribirMonto(tester, r'$ 1.500');

      expect(find.text(r'El saldo es $ 1.200. Ingresá hasta ese monto.'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('justo el saldo se puede; un centavo más, no', (tester) async {
      await montarCobro(tester);

      await escribirMonto(tester, '1200');
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.textContaining('El saldo es'), findsNothing);

      await escribirMonto(tester, '1200,01');
      expect(elBoton(tester).onPressed, isNull);
      expect(find.textContaining('El saldo es'), findsOneWidget);
    });

    testWidgets('al corregir el monto el error se va', (tester) async {
      await montarCobro(tester);

      await escribirMonto(tester, '1500');
      await escribirMonto(tester, '1000');

      expect(find.textContaining('El saldo es'), findsNothing);
      expect(elBoton(tester).onPressed, isNotNull);
    });

    testWidgets('si el saldo bajó mientras tanto, quien guarda lo rechaza y el campo lo dice', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await escribirMonto(tester, '1200');
      // Otro cobro entró por el costado (el sync, otra pantalla): ahora la venta debe $ 700.
      a.repo.cobros['otro'] = cobroDeEjemplo('otro', 50000);

      await tocarCobro(tester, botonRegistrar);

      expect(a.repo.cobros.containsKey('cobro-1'), isFalse);
      expect(find.text(r'El saldo es $ 700. Ingresá hasta ese monto.'), findsOneWidget);
      expect(_texto('cobro_saldo'), r'$ 700');
      expect(elBoton(tester).onPressed, isNull);
      expect(find.byKey(const Key('cobro_error')), findsNothing);
    });

    testWidgets('si otro cobro dejó la venta sin saldo, la pantalla lo dice en vez de cobrar', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await escribirMonto(tester, '1200');
      a.repo.cobros['otro'] = cobroDeEjemplo('otro', 120000);

      await tocarCobro(tester, botonRegistrar);

      expect(find.text('Venta pagada'), findsOneWidget);
      expect(
        find.text('Esta venta no tiene saldo: ya está pagada. No queda nada para cobrar.'),
        findsOneWidget,
      );
      expect(a.repo.cobros.containsKey('cobro-1'), isFalse);
    });
  });

  group('28·04 · Fecha de otro día', () {
    testWidgets('«Cambiar» abre la hoja con Hoy, Ayer, anteayer y «Otro día…»', (tester) async {
      await montarCobro(tester);

      await tocarCobro(tester, campoFecha);

      expect(find.text('¿Cuándo te pagó?'), findsOneWidget);
      expect(find.byKey(const Key('cobro_dia_0')), findsOneWidget);
      expect(find.byKey(const Key('cobro_dia_1')), findsOneWidget);
      expect(find.byKey(const Key('cobro_dia_2')), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
      expect(find.text('Mié 21'), findsOneWidget);
      expect(find.text('Otro día…'), findsOneWidget);
      expect(
        find.text('No puede ser antes de la venta (12/10) ni después de hoy.'),
        findsOneWidget,
      );
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('elegir Ayer y «Listo» cambia la fecha y el cobro se guarda con ese día', (
      tester,
    ) async {
      final a = await montarCobro(tester);

      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_1')));
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));

      expect(find.text('Ayer, 22/10'), findsOneWidget);
      await _cobrar(tester, '300');
      expect(a.repo.recibidos.single.fecha, DateTime.utc(2026, 10, 22, 15));
    });

    testWidgets('cerrar la hoja sin «Listo» no cambia nada', (tester) async {
      await montarCobro(tester);

      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_2')));
      await tester.tapAt(const Offset(195, 40));
      await asentarAgendar(tester);

      expect(find.text('¿Cuándo te pagó?'), findsNothing);
      expect(find.text('Hoy, 23/10'), findsOneWidget);
    });

    testWidgets('volver a elegir Hoy deja el cobro con la hora de ahora', (tester) async {
      final a = await montarCobro(tester);

      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_1')));
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));
      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_0')));
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));
      await _cobrar(tester, '300');

      expect(find.text('Hoy, 23/10'), findsNothing); // ya está en la pantalla de éxito
      expect(a.repo.recibidos.single.fecha, hoyDelCobro);
    });

    testWidgets('«Otro día…» abre el calendario entre la venta y hoy', (tester) async {
      final a = await montarCobro(tester);

      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_otro_dia')));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // El 11 es antes de la venta (12/10): el calendario no lo deja elegir.
      await tester.tap(find.text('15'));
      await asentarAgendar(tester, 4);
      await tester.tap(find.text('OK'));
      await asentarAgendar(tester);
      expect(find.byKey(const Key('cobro_dia_elegido')), findsOneWidget);
      expect(find.text('Jue 15/10'), findsOneWidget);
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));

      expect(find.text('Jue 15/10'), findsOneWidget);
      await _cobrar(tester, '300');
      expect(a.repo.recibidos.single.fecha, DateTime.utc(2026, 10, 15, 15));
    });

    testWidgets('si la venta fue hoy, solo se ofrece Hoy', (tester) async {
      await montarCobro(
        tester,
        repo: CobranzasEnMemoria(ventas: [ventaDelCobro(fecha: hoyDelCobro)], cobradoAntes: 0),
      );

      await tocarCobro(tester, campoFecha);

      expect(find.byKey(const Key('cobro_dia_0')), findsOneWidget);
      expect(find.byKey(const Key('cobro_dia_1')), findsNothing);
      expect(find.byKey(const Key('cobro_dia_2')), findsNothing);
      expect(find.byKey(const Key('cobro_otro_dia')), findsNothing);
      expect(
        find.text('No puede ser antes de la venta (23/10) ni después de hoy.'),
        findsOneWidget,
      );
    });

    testWidgets('si la venta fue ayer, se ofrece Hoy y Ayer pero no «Otro día…»', (tester) async {
      await montarCobro(
        tester,
        repo: CobranzasEnMemoria(
          ventas: [ventaDelCobro(fecha: DateTime.utc(2026, 10, 22, 15))],
          cobradoAntes: 0,
        ),
      );

      await tocarCobro(tester, campoFecha);

      expect(find.byKey(const Key('cobro_dia_1')), findsOneWidget);
      expect(find.byKey(const Key('cobro_dia_2')), findsNothing);
      expect(find.byKey(const Key('cobro_otro_dia')), findsNothing);
    });

    testWidgets('si quien guarda rechaza la fecha, el campo lo dice y se puede corregir', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroFechaInvalida());

      await _cobrar(tester, '300');

      expect(
        _texto('cobro_fecha_error'),
        'No puede ser antes de la venta (12/10) ni después de hoy.',
      );
      expect(find.byKey(const Key('cobro_error')), findsNothing);
      expect(elBoton(tester).onPressed, isNotNull);

      await tocarCobro(tester, botonRegistrar);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });
  });

  group('28·05 · Registrando', () {
    testWidgets('el botón dice «Registrando…», los campos se bloquean y no se puede salir', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();

      await escribirMonto(tester, '300');
      await tocarCobro(tester, botonRegistrar);

      expect(find.text('Registrando…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(tester.widget<TextField>(campoMonto).enabled, isFalse);
      expect(cerrarCobro, findsNothing);
      // El gesto de atrás no cierra la pantalla mientras guarda.
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(pagina, findsOneWidget);
      expect(a.resultados, isEmpty);

      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });

    testWidgets('«Registrando…» se lee: blanco sobre el azul lleno (contraste AA)', (tester) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();

      await escribirMonto(tester, '300');
      await tocarCobro(tester, botonRegistrar);

      expect(find.text('Registrando…'), findsOneWidget);
      expect(contrasteDelBoton(tester, 'Registrando…'), greaterThanOrEqualTo(4.5));

      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
    });

    testWidgets('el campo de fecha tampoco responde mientras guarda', (tester) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();

      await escribirMonto(tester, '300');
      await tocarCobro(tester, botonRegistrar);
      await tester.tap(campoFecha, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(find.text('¿Cuándo te pagó?'), findsNothing);
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
    });
  });

  group('28·06 · Cobro parcial (éxito)', () {
    testWidgets('dice cuánto quedó pagado y debido, y que el monto suma al dinero en mano', (
      tester,
    ) async {
      await montarCobro(tester);

      await _cobrar(tester, '600');

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.text('María Fernández · Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(_texto('cobro_pagado'), r'$ 3.900');
      expect(_texto('cobro_saldo'), r'$ 600');
      expect(
        find.text(r'Sumamos $ 600 a tu dinero en mano. Queda en mano hasta que lo deposites.'),
        findsOneWidget,
      );
      expect(find.text('Agendar la próxima cobranza'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Registrar cobro'), findsNothing);
      expect(cerrarCobro, findsNothing);
    });

    testWidgets('«Listo» cierra la pantalla y avisa que se cobró', (tester) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, '600');

      await tocarCobro(tester, find.byKey(const Key('cobro_listo')));

      expect(pagina, findsNothing);
      expect(a.resultados, [true]);
    });

    testWidgets('el gesto de atrás en la confirmación también cierra con «se cobró»', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, '600');

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(pagina, findsNothing);
      expect(a.resultados, [true]);
    });

    testWidgets(
      '«Agendar la próxima cobranza» abre «Agendar» como cobranza y, al agendar, cierra',
      (tester) async {
        final a = await montarCobro(tester);
        await _cobrar(tester, '600');

        await tocarCobro(tester, find.text('Agendar la próxima cobranza'));

        final agendar = tester.widget<AgendarVisitaPage>(find.byType(AgendarVisitaPage));
        expect(agendar.tipoInicial, TipoAgenda.cobranza);
        expect(agendar.espacioId, 'esp-1');
        expect(agendar.espacioPersonaId, 'ep-p1');
        expect(agendar.colportorId, 'col-1');

        await tocarCobro(tester, find.byKey(ClavesAgendarVisita.botonAgendar));
        expect(a.agendas.guardadas, hasLength(1));
        expect(a.agendas.guardadas.values.single.tipo, TipoAgenda.cobranza);
        expect(pagina, findsNothing);
        expect(a.resultados, [true]);
      },
    );

    testWidgets('si no agenda y vuelve, la confirmación sigue ahí', (tester) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, '600');

      await tocarCobro(tester, find.text('Agendar la próxima cobranza'));
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(a.resultados, isEmpty);
      expect(a.agendas.guardadas, isEmpty);
    });

    testWidgets('dos toques seguidos en «Agendar la próxima cobranza» abren una sola pantalla', (
      tester,
    ) async {
      await montarCobro(tester);
      await _cobrar(tester, '600');

      final boton = find.text('Agendar la próxima cobranza');
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(find.byType(AgendarVisitaPage), findsOneWidget);
    });
  });

  group('28·07 · Saldo en cero: venta completa', () {
    testWidgets('cobrar todo el saldo dice «Venta pagada» y ofrece volver al mapa', (tester) async {
      final a = await montarCobro(tester);

      await _cobrar(tester, '1200');

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.text('Venta pagada'), findsOneWidget);
      expect(
        find.text(
          'El saldo llegó a cero. Si ya entregaste todo, la casa queda como «Venta completa».',
        ),
        findsOneWidget,
      );
      expect(_texto('cobro_pagado'), r'$ 4.500');
      expect(_texto('cobro_saldo'), r'$ 0');
      expect(find.textContaining('Sumamos'), findsNothing);
      expect(find.text('Agendar la próxima cobranza'), findsNothing);

      await tocarCobro(tester, find.byKey(const Key('cobro_volver_al_mapa')));
      expect(pagina, findsNothing);
      expect(a.resultados, [true]);
    });

    testWidgets('«Volver al mapa» dos veces seguidas cierra una sola pantalla', (tester) async {
      final a = await montarCobro(tester);
      await _cobrar(tester, '1200');

      final boton = find.byKey(const Key('cobro_volver_al_mapa'));
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(a.resultados, [true]);
      expect(find.text('abrir cobro'), findsOneWidget);
    });
  });

  group('28·08 · Error al guardar', () {
    testWidgets(
      'el aviso dice que no se registró nada, conserva lo escrito y ofrece «Reintentar»',
      (tester) async {
        final a = await montarCobro(tester);
        a.repo.fallas.add(const FailureCobroNoGuardado());

        await _cobrar(tester, '600');

        expect(
          find.text('No pudimos guardar el cobro. No se registró nada: probá de nuevo.'),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(campoMonto).controller!.text, '600');
        expect(find.text('Reintentar'), findsOneWidget);
        expect(elBoton(tester).onPressed, isNotNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(a.repo.cobros.containsKey('cobro-1'), isFalse);
      },
    );

    testWidgets('«Reintentar» repite el mismo id y no cobra dos veces', (tester) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _cobrar(tester, '600');

      await tocarCobro(tester, botonRegistrar);

      expect(a.repo.recibidos.map((c) => c.id), ['cobro-1', 'cobro-1']);
      expect(a.idsGenerados, ['cobro-1']);
      expect(a.repo.cobros.keys.where((k) => !k.startsWith('previo')), ['cobro-1']);
      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.byKey(const Key('cobro_error')), findsNothing);
    });

    testWidgets('si cambia el monto después de la falla, es otro cobro con otro id', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _cobrar(tester, '600');

      await escribirMonto(tester, '500');
      await tocarCobro(tester, botonRegistrar);

      expect(a.repo.recibidos.map((c) => c.id), ['cobro-1', 'cobro-2']);
      expect(a.repo.recibidos.last.montoCentavos, 50000);
    });

    testWidgets('si la persona cambia solo el día, tampoco repite el id', (tester) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _cobrar(tester, '600');

      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_1')));
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));
      await tocarCobro(tester, botonRegistrar);

      expect(a.repo.recibidos.map((c) => c.id), ['cobro-1', 'cobro-2']);
    });

    testWidgets('una excepción al guardar también deja el aviso y el botón libre', (tester) async {
      final a = await montarCobro(tester);
      a.repo.lanzar = StateError('se cayó la base');

      await _cobrar(tester, '600');

      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      await tocarCobro(tester, botonRegistrar);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });

    testWidgets('la falla no deja el botón trabado en «Registrando…»', (tester) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();
      a.repo.fallas.add(const FailureCobroNoGuardado());

      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);
      expect(find.text('Registrando…'), findsOneWidget);
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(find.text('Registrando…'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(cerrarCobro, findsOneWidget);
    });

    testWidgets('una falla que no es de las conocidas muestra el mismo aviso', (tester) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureInesperado());

      await _cobrar(tester, '600');

      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
    });
  });

  group('28·09 · Sin conexión', () {
    testWidgets('el cobro funciona igual sin red: no hay otro estado ni otro texto', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await asentarAgendar(tester);

      expect(find.textContaining('conexión'), findsNothing);
      await _cobrar(tester, '600');

      expect(a.repo.recibidos, hasLength(1));
      expect(find.text('Cobro registrado'), findsOneWidget);
    });
  });

  group('La venta que se cobra', () {
    testWidgets('mientras se lee, muestra el esqueleto y «✕» para salir', (tester) async {
      final repo = CobranzasEnMemoria()..compuertaDeLectura = Completer<void>();
      await montarCobro(tester, repo: repo);

      expect(find.byKey(const Key('cobro_cargando')), findsOneWidget);
      expect(find.text('Registrar cobro'), findsNothing);
      expect(cerrarCobro, findsOneWidget);

      repo.compuertaDeLectura!.complete();
      await asentarAgendar(tester);
      expect(find.byKey(const Key('cobro_cargando')), findsNothing);
      expect(find.text('Registrar cobro'), findsOneWidget);
    });

    testWidgets('si la venta ya no está en el teléfono, lo dice y deja volver', (tester) async {
      final a = await montarCobro(tester, repo: CobranzasEnMemoria(ventas: []));

      expect(
        find.text('Esta venta ya no está en tu teléfono. Volvé atrás y elegí otra.'),
        findsOneWidget,
      );
      expect(find.text('Registrar cobro'), findsNothing);

      await tocarCobro(tester, find.text('Volver'));
      expect(pagina, findsNothing);
      expect(a.resultados, [false]);
    });

    testWidgets('si la venta desaparece justo al guardar, pasa al mismo aviso', (tester) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroSinVenta());

      await _cobrar(tester, '600');

      expect(find.byKey(const Key('cobro_sin_venta')), findsOneWidget);
      expect(find.text('Registrar cobro'), findsNothing);
    });

    testWidgets('si no se puede leer, ofrece «Reintentar» y al reintentar muestra el formulario', (
      tester,
    ) async {
      final repo = CobranzasEnMemoria()
        ..fallaDeLectura = const FailureInesperado()
        ..fallaDeLecturaUnaVez = true;
      await montarCobro(tester, repo: repo);

      expect(find.text('No pudimos leer la venta guardada en tu teléfono.'), findsOneWidget);
      expect(find.text('Registrar cobro'), findsNothing);

      await tocarCobro(tester, find.byKey(const Key('venta_aviso_accion')));
      expect(repo.lecturas, 2);
      expect(find.text('Registrar cobro'), findsOneWidget);
    });

    testWidgets('si ya no debe nada, dice que está pagada y no ofrece cobrar', (tester) async {
      final a = await montarCobro(tester, repo: CobranzasEnMemoria(cobradoAntes: 450000));

      expect(find.text('Venta pagada'), findsOneWidget);
      expect(
        find.text('Esta venta no tiene saldo: ya está pagada. No queda nada para cobrar.'),
        findsOneWidget,
      );
      expect(find.text('Registrar cobro'), findsNothing);
      expect(campoMonto, findsNothing);
      expect(_texto('cobro_saldo'), r'$ 0');

      await tocarCobro(tester, find.text('Volver'));
      expect(a.resultados, [false]);
    });

    testWidgets('sin persona (venta sin cliente) la cabecera dice solo dónde fue', (tester) async {
      await montarCobro(tester, espacioPersonaId: null);

      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
    });

    testWidgets('sin saber nada de la casa, la cabecera queda sin línea de abajo', (tester) async {
      await montarCobro(tester, sinCasa: true, espacioPersonaId: null);

      expect(find.textContaining('Mataojo'), findsNothing);
      expect(find.text('Registrar cobro'), findsOneWidget);
    });
  });

  group('Casos límite', () {
    testWidgets('doble toque en «Registrar cobro»: un solo cobro', (tester) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();
      await escribirMonto(tester, '600');

      await tester.tap(botonRegistrar);
      await tester.tap(botonRegistrar, warnIfMissed: false);
      await tester.pump();
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(a.repo.recibidos, hasLength(1));
      expect(a.idsGenerados, ['cobro-1']);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });

    testWidgets('dos cobros seguidos: el segundo ve el saldo que dejó el primero', (tester) async {
      final a = await montarCobro(tester);

      await _cobrar(tester, '500');
      await tocarCobro(tester, find.byKey(const Key('cobro_listo')));
      expect(a.resultados, [true]);

      await abrirCobro(tester);
      expect(_texto('cobro_pagado'), r'$ 3.800');
      expect(_texto('cobro_saldo'), r'$ 700');
      // El monto del primero ya no entra: debe $ 700.
      await escribirMonto(tester, '800');
      expect(find.text(r'El saldo es $ 700. Ingresá hasta ese monto.'), findsOneWidget);

      await _cobrar(tester, '700');
      expect(find.text('Venta pagada'), findsOneWidget);
      expect(a.repo.recibidos.map((c) => c.id), ['cobro-1', 'cobro-2']);
      expect(a.repo.recibidos.map((c) => c.montoCentavos), [50000, 70000]);
    });

    testWidgets('volver atrás con «✕» y reentrar empieza de cero, sin cobrar nada', (tester) async {
      final a = await montarCobro(tester);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, campoFecha);
      await tocarCobro(tester, find.byKey(const Key('cobro_dia_1')));
      await tocarCobro(tester, find.byKey(const Key('cobro_hoja_listo')));

      await tocarCobro(tester, cerrarCobro);
      expect(pagina, findsNothing);
      expect(a.resultados, [false]);
      expect(a.repo.recibidos, isEmpty);

      await abrirCobro(tester);
      expect(tester.widget<TextField>(campoMonto).controller!.text, isEmpty);
      expect(find.text('Hoy, 23/10'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(find.byKey(const Key('cobro_error')), findsNothing);
    });

    testWidgets('el gesto de atrás en el formulario cierra sin cobrar', (tester) async {
      final a = await montarCobro(tester);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(pagina, findsNothing);
      expect(a.resultados, [false]);
    });

    testWidgets('«✕» dos veces seguidas cierra una sola pantalla', (tester) async {
      final a = await montarCobro(tester);

      await tester.tap(cerrarCobro);
      await tester.tap(cerrarCobro, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(a.resultados, [false]);
      expect(find.text('abrir cobro'), findsOneWidget);
    });

    testWidgets('un monto enorme que no entra en el servidor se marca y no se guarda', (
      tester,
    ) async {
      final a = await montarCobro(tester);

      await escribirMonto(tester, '99999999');

      expect(find.text('Escribí un monto válido, por ejemplo 600.'), findsOneWidget);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('una venta grande: el saldo y el monto se leen completos', (tester) async {
      await montarCobro(
        tester,
        repo: CobranzasEnMemoria(ventas: [ventaDelCobro(total: 2147483000)], cobradoAntes: 0),
      );

      expect(_texto('cobro_saldo'), r'$ 21.474.830');
      await escribirMonto(tester, '21.474.830');
      expect(elBoton(tester).onPressed, isNotNull);
    });

    testWidgets('el campo no admite más de 14 caracteres', (tester) async {
      await montarCobro(tester);

      await escribirMonto(tester, '1' * 40);

      expect(tester.widget<TextField>(campoMonto).controller!.text.length, 14);
    });

    testWidgets('nombres y direcciones largos no rompen la cabecera', (tester) async {
      await montarCobro(
        tester,
        personas: [
          clienteDePersonas(
            'p1',
            'María de los Ángeles del Carmen',
            apellido: 'Fernández de la Peña y Rodríguez',
          ),
        ],
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('María de los Ángeles'), findsOneWidget);
    });
  });

  group('textScaler 2.0 en 320×568', () {
    Future<void> sinDesbordes(WidgetTester tester) async {
      expect(tester.takeException(), isNull);
    }

    Future<void> alAlcance(WidgetTester tester, Finder f) async {
      await traerAlAlcance(tester, f);
      final rect = tester.getRect(f.first);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(568));
    }

    testWidgets('el formulario se desplaza y el botón queda al alcance', (tester) async {
      await montarCobro(tester, escala: 2, tamano: const Size(320, 568));

      await sinDesbordes(tester);
      await alAlcance(tester, botonRegistrar);
      await alAlcance(tester, campoFecha);
    });

    testWidgets('con el error de monto y el aviso de falla', (tester) async {
      final a = await montarCobro(tester, escala: 2, tamano: const Size(320, 568));
      a.repo.fallas.add(const FailureCobroNoGuardado());

      await escribirMonto(tester, '1500');
      await sinDesbordes(tester);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);

      await sinDesbordes(tester);
      // La lista sube sola: el aviso queda a la vista aunque el botón se tocó con el formulario
      // desplazado hacia abajo.
      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('cobro_error'))).top, greaterThanOrEqualTo(0));
      await alAlcance(tester, botonRegistrar);
    });

    testWidgets('la hoja de la fecha', (tester) async {
      await montarCobro(tester, escala: 2, tamano: const Size(320, 568));

      await tocarCobro(tester, campoFecha);

      await sinDesbordes(tester);
      await alAlcance(tester, find.byKey(const Key('cobro_hoja_listo')));
    });

    testWidgets('el cobro parcial y el saldo en cero', (tester) async {
      await montarCobro(tester, escala: 2, tamano: const Size(320, 568));
      await _cobrar(tester, '600');

      await sinDesbordes(tester);
      await alAlcance(tester, find.byKey(const Key('cobro_listo')));
      await tocarCobro(tester, find.byKey(const Key('cobro_listo')));

      await abrirCobro(tester);
      await _cobrar(tester, '600');
      await sinDesbordes(tester);
      expect(find.text('Venta pagada'), findsOneWidget);
      await alAlcance(tester, find.byKey(const Key('cobro_volver_al_mapa')));
    });

    testWidgets('«Registrando…» no desborda', (tester) async {
      final a = await montarCobro(tester, escala: 2, tamano: const Size(320, 568));
      a.repo.compuerta = Completer<void>();

      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);

      await sinDesbordes(tester);
      expect(find.text('Registrando…'), findsOneWidget);
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
    });
  });

  group('Accesibilidad', () {
    testWidgets('los toques miden 48 y todo tiene nombre', (tester) async {
      await montarCobro(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('el campo de fecha se anuncia con el día y la acción', (tester) async {
      await montarCobro(tester);

      expect(find.bySemanticsLabel('FECHA: Hoy, 23/10. Cambiar'), findsOneWidget);
    });

    testWidgets('el error del monto se anuncia al aparecer (región viva)', (tester) async {
      await montarCobro(tester);
      await escribirMonto(tester, '1500');

      final error = find.text(r'El saldo es $ 1.200. Ingresá hasta ese monto.');
      final vivo = find.ancestor(
        of: error,
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(vivo, findsWidgets);
    });
  });
}
