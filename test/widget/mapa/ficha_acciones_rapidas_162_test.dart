// HU-VEN-005 (#162): las acciones rápidas de la ficha de la persona (vista 32B·01): «+ Agendar cobranza»
// y «Registrar entrega» bajo la cuenta, sin salir de la ficha. «Agendar cobranza» abre «Agendar visita»
// de cobranza con la casa y la persona puestas; «Registrar entrega» lleva al destino que enchufa
// `registrarEntregaDesdeLaFichaProvider` (sin destino no se dibuja).
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  final agendar = find.byKey(ClavesFicha.botonAgendarCobranza);
  final entrega = find.byKey(ClavesFicha.botonRegistrarEntrega);
  final acciones = find.byKey(ClavesFicha.acciones);

  /// El mundo del canvas 32B·01: María con cuenta ($ 4.500 comprado, 1 de 2 entregado, $ 3.300 pagado,
  /// saldo $ 1.200), notas, una venta y una visita, y María sembrada en el depto para la agenda.
  MundoFicha mundo({bool conEntrega = true}) {
    final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
      ..conRegistrarEntrega = conEntrega;
    m.cuentas.cuenta = cuentaConSaldo;
    m.personas.sembrar([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]);
    return m;
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await asentar(tester);
  }

  group('32B·01 · ficha con la cuenta y las acciones rápidas', () {
    testWidgets('bajo la cuenta están «+ Agendar cobranza» y «Registrar entrega», en ese orden', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

      expect(find.text('+ Agendar cobranza'), findsOneWidget);
      expect(find.text('Registrar entrega'), findsOneWidget);
      final cuenta = tester.getBottomLeft(find.byKey(ClavesFicha.cuenta)).dy;
      final notas = tester.getTopLeft(find.byKey(ClavesFicha.notas)).dy;
      final y = tester.getTopLeft(acciones).dy;
      expect(y, greaterThan(cuenta));
      expect(y, lessThan(notas));
      // En el mismo renglón de izquierda a derecha, o «+ Agendar cobranza» arriba: nunca al revés.
      final a = tester.getTopLeft(agendar);
      final e = tester.getTopLeft(entrega);
      expect(
        a.dy < e.dy || (a.dy == e.dy && a.dx < e.dx),
        isTrue,
        reason: 'el canvas pone primero «+ Agendar cobranza»',
      );
    });

    testWidgets('la cuenta muestra comprado, entregado, pagado y saldo con los totales', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

      final cuenta = find.byKey(ClavesFicha.cuenta);
      expect(find.descendant(of: cuenta, matching: find.text('Comprado')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.textContaining('4.500')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.text('Entregado')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.text('1 de 2')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.text('Pagado')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.textContaining('3.300')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.text('Saldo')), findsOneWidget);
      expect(find.descendant(of: cuenta, matching: find.textContaining('1.200')), findsOneWidget);
    });

    testWidgets('las dos acciones se anuncian como botones y miden al menos 48 dp de alto', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

      for (final f in [agendar, entrega]) {
        expect(tester.getSize(f).height, greaterThanOrEqualTo(40));
        final nodo = tester.getSemantics(f);
        expect(nodo.flagsCollection.isButton, isTrue);
      }
      semantica.dispose();
    });
  });

  group('32B·02 · teléfono a la vista y 32B·03 · filtro por estado', () {
    testWidgets('con el teléfono a la vista las acciones siguen y no se mueven de sitio', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

      await tester.tap(find.byKey(ClavesFicha.botonVer));
      await asentar(tester);

      expect(agendar, findsOneWidget);
      expect(entrega, findsOneWidget);
    });

    testWidgets('con el filtro «Con saldo» elegido las acciones conviven con MOSTRAR', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

      await tocar(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo)));

      expect(agendar, findsOneWidget);
      expect(entrega, findsOneWidget);
      expect(find.text(TextosFicha.mostrar), findsOneWidget);
    });
  });

  group('32B·04 y 32B·08 · solo lectura', () {
    testWidgets('con la persona de baja no hay acciones rápidas', (tester) async {
      final m =
          MundoFicha(
              persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
              historial: historialDelCanvas(),
              notasIniciales: notasDeLaFicha(),
              contexto: contextoBajaDesde22(),
            )
            ..conRegistrarEntrega = true
            ..cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(acciones, findsNothing);
      expect(agendar, findsNothing);
      expect(entrega, findsNothing);
    });

    testWidgets('con el depto de baja no hay acciones rápidas', (tester) async {
      final m =
          MundoFicha(
              historial: historialDelCanvas(),
              notasIniciales: notasDeLaFicha(),
              contexto: contextoDeptoDeBaja,
              lugarInicial: (
                espacio: espacioDePersonas(
                  numeroDepto: '3B',
                  deletedAt: DateTime.utc(2026, 10, 20),
                ),
                ubicacion: ubicacionDePersonas(),
              ),
            )
            ..conRegistrarEntrega = true
            ..cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(acciones, findsNothing);
    });
  });

  group('32B·05 · 32B·06 · 32B·07 · sin acciones donde no hay cuenta', () {
    testWidgets('sin historial (32B·05) no hay acciones', (tester) async {
      final m = MundoFicha(persona: mariaDePrueba(telefono: null))..conRegistrarEntrega = true;
      await montarFicha(tester, m);

      expect(find.text(TextosFicha.sinHistorialTitulo), findsOneWidget);
      expect(acciones, findsNothing);
    });

    testWidgets('cargando (32B·06) no hay acciones', (tester) async {
      await montarFicha(tester, MundoFicha(cargando: true)..conRegistrarEntrega = true);

      expect(find.byKey(ClavesFicha.cargando), findsOneWidget);
      expect(acciones, findsNothing);
    });

    testWidgets('con error al leer (32B·07) no hay acciones y al reintentar aparecen', (
      tester,
    ) async {
      final m = mundo();
      m.fichas.errorAlObservar = StateError('no se pudo leer');
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(acciones, findsNothing);

      m.fichas.errorAlObservar = null;
      await tester.tap(find.text(TextosFicha.reintentar));
      await asentar(tester);

      expect(acciones, findsOneWidget);
    });

    testWidgets('con historial pero sin ventas («Sin movimientos aún») no hay acciones', (
      tester,
    ) async {
      final m = MundoFicha(historial: [historialDelCanvas().last])..conRegistrarEntrega = true;
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      expect(find.byKey(ClavesFicha.sinMovimientos), findsOneWidget);
      expect(acciones, findsNothing);
    });
  });

  group('cada acción solo si hay algo que hacer (decisión del 30/10, regla R4)', () {
    // Pagó todo: comprado $ 4.500, pagado $ 4.500, 1 de 2 entregado.
    const sinSaldo = ResumenCuentaPersona(
      compradoCentavos: 450000,
      pagadoCentavos: 450000,
      saldoCentavos: 0,
      entregasHechas: 1,
      entregasTotales: 2,
    );
    // Debe $ 1.200 pero ya recibió todo: 2 de 2 entregado.
    const sinEntregas = ResumenCuentaPersona(
      compradoCentavos: 450000,
      pagadoCentavos: 330000,
      saldoCentavos: 120000,
      entregasHechas: 2,
      entregasTotales: 2,
    );
    // Pagó y recibió todo.
    const alDia = ResumenCuentaPersona(
      compradoCentavos: 450000,
      pagadoCentavos: 450000,
      saldoCentavos: 0,
      entregasHechas: 2,
      entregasTotales: 2,
    );

    Future<void> montarCon(
      WidgetTester tester,
      ResumenCuentaPersona cuenta, {
      bool conEntrega = true,
    }) async {
      final m = mundo(conEntrega: conEntrega)..cuentas.cuenta = cuenta;
      await montarFicha(tester, m, tamano: const Size(390, 1600));
    }

    testWidgets('con saldo y entregas pendientes están las dos', (tester) async {
      await montarCon(tester, cuentaConSaldo);

      expect(agendar, findsOneWidget);
      expect(entrega, findsOneWidget);
    });

    testWidgets('sin saldo no hay «+ Agendar cobranza» y «Registrar entrega» sigue', (
      tester,
    ) async {
      await montarCon(tester, sinSaldo);

      expect(agendar, findsNothing);
      expect(entrega, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin entregas pendientes no hay «Registrar entrega» y «+ Agendar cobranza» sigue', (
      tester,
    ) async {
      await montarCon(tester, sinEntregas);

      expect(entrega, findsNothing);
      expect(agendar, findsOneWidget);
    });

    testWidgets('al día en saldo y en entregas no hay bloque de acciones', (tester) async {
      await montarCon(tester, alDia);

      expect(acciones, findsNothing);
      expect(agendar, findsNothing);
      expect(entrega, findsNothing);
      // La cuenta sigue a la vista: lo que desaparece son las acciones, no la ficha.
      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con entregas pendientes pero sin destino y sin saldo no hay bloque', (
      tester,
    ) async {
      await montarCon(tester, sinSaldo, conEntrega: false);

      expect(acciones, findsNothing);
    });

    testWidgets('con una sola acción a letra doble se llega a ella y no desborda', (tester) async {
      final m = mundo()..cuentas.cuenta = sinSaldo;
      await montarFicha(tester, m, tamano: const Size(320, 568), escala: 2);

      await tester.ensureVisible(entrega);
      expect(entrega, findsOneWidget);
      expect(agendar, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('«+ Agendar cobranza»', () {
    testWidgets('abre «Agendar visita» de cobranza con la casa y la persona puestas', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

      await tocar(tester, agendar);

      final pagina = tester.widget<AgendarVisitaPage>(find.byType(AgendarVisitaPage));
      expect(pagina.tipoInicial, TipoAgenda.cobranza);
      expect(pagina.espacioId, 'esp-1');
      expect(pagina.espacioPersonaId, 'ep-per-1');
      expect(pagina.colportorId, 'col-1');
    });

    testWidgets('al agendar guarda la cobranza, vuelve a la ficha y avisa', (tester) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      await tocar(tester, agendar);
      await tester.tap(find.byKey(ClavesAgendarVisita.botonAgendar));
      await asentar(tester, 30);

      final guardada = m.agendas.recibidas.single.agenda;
      expect(guardada.tipo, TipoAgenda.cobranza);
      expect(guardada.espacioPersonaId, 'ep-per-1');
      expect(find.byType(AgendarVisitaPage), findsNothing);
      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(find.text('Agendada.'), findsOneWidget);
      // De vuelta en la ficha las acciones están otra vez tocables.
      expect(tester.widget<ActionChip>(agendar).onPressed, isNotNull);
    });

    testWidgets('un doble toque abre «Agendar visita» una sola vez', (tester) async {
      await montarFicha(tester, mundo(), tamano: const Size(390, 1600));
      await tester.ensureVisible(agendar);
      await tester.pump();

      await tester.tap(agendar);
      await tester.tap(agendar, warnIfMissed: false);
      await asentar(tester);

      expect(find.byType(AgendarVisitaPage), findsOneWidget);
    });

    testWidgets('si la persona ya no está en el depto avisa qué hacer y deja tocar de nuevo', (
      tester,
    ) async {
      final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
        ..conRegistrarEntrega = true;
      m.cuentas.cuenta = cuentaConSaldo;
      // Sin sembrar a la persona: el vínculo no se encuentra.
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      await tocar(tester, agendar);

      expect(find.byType(AgendarVisitaPage), findsNothing);
      expect(find.text(TextosFicha.noPudimosAbrir), findsOneWidget);
      expect(tester.widget<ActionChip>(agendar).onPressed, isNotNull);
    });

    testWidgets('volver atrás y reentrar a la ficha deja las acciones tocables', (tester) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: const Size(390, 1600));
      await tocar(tester, agendar);
      expect(find.byType(AgendarVisitaPage), findsOneWidget);

      await tester.tap(find.byKey(ClavesAgendarVisita.cerrar));
      await asentar(tester);
      expect(find.byType(AgendarVisitaPage), findsNothing);

      await volverAtras(tester);
      expect(find.byKey(ClavesFicha.cuenta), findsNothing);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(tester.widget<ActionChip>(agendar).onPressed, isNotNull);
      expect(m.agendas.recibidas, isEmpty);
    });
  });

  group('«Registrar entrega»', () {
    testWidgets('lleva al destino con la persona y el espacio de la ficha', (tester) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      await tocar(tester, entrega);

      expect(m.entregas, [(personaId: 'per-1', espacioId: 'esp-1')]);
    });

    testWidgets('sin destino no se dibuja y «+ Agendar cobranza» sigue', (tester) async {
      await montarFicha(tester, mundo(conEntrega: false), tamano: const Size(390, 1600));

      expect(entrega, findsNothing);
      expect(find.text('Registrar entrega'), findsNothing);
      expect(agendar, findsOneWidget);
    });

    testWidgets('un doble toque con el destino abierto lo abre una sola vez', (tester) async {
      final m = mundo()..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m, tamano: const Size(390, 1600));
      await tester.ensureVisible(entrega);
      await tester.pump();

      await tester.tap(entrega);
      await tester.tap(entrega, warnIfMissed: false);
      await tester.pump();

      expect(m.entregas, hasLength(1));

      m.compuertaEntrega!.complete();
      await asentar(tester);
      // Ya volvió: se puede abrir otra vez.
      await tester.tap(entrega);
      await asentar(tester);
      expect(m.entregas, hasLength(2));
    });

    testWidgets('si el destino falla a mitad avisa qué hacer y las acciones vuelven a andar', (
      tester,
    ) async {
      final m = mundo()..lanzarAlRegistrarEntrega = StateError('no abrió');
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      await tocar(tester, entrega);

      expect(find.text(TextosFicha.noPudimosAbrir), findsOneWidget);
      expect(tester.widget<ActionChip>(entrega).onPressed, isNotNull);
      expect(tester.widget<ActionChip>(agendar).onPressed, isNotNull);

      // Reintenta y esta vez abre.
      await tester.tap(entrega);
      await asentar(tester);
      expect(m.entregas, hasLength(2));
    });
  });

  group('dos acciones seguidas', () {
    testWidgets(
      'con «Registrar entrega» abriéndose, «+ Agendar cobranza» queda apagada y no se pierde nada',
      (tester) async {
        final m = mundo()..compuertaEntrega = Completer<void>();
        await montarFicha(tester, m, tamano: const Size(390, 1600));
        await tester.ensureVisible(entrega);
        await tester.pump();

        await tester.tap(entrega);
        await tester.pump();

        expect(tester.widget<ActionChip>(agendar).onPressed, isNull);
        expect(tester.widget<ActionChip>(entrega).onPressed, isNull);
        await tester.tap(agendar, warnIfMissed: false);
        await tester.pump();
        expect(find.byType(AgendarVisitaPage), findsNothing);
        expect(m.entregas, hasLength(1));

        m.compuertaEntrega!.complete();
        await asentar(tester);
        expect(tester.widget<ActionChip>(agendar).onPressed, isNotNull);

        // La segunda acción, ya sin la primera, anda.
        await tocar(tester, agendar);
        expect(find.byType(AgendarVisitaPage), findsOneWidget);
      },
    );
  });

  group('datos límite', () {
    testWidgets('con letra al doble en 320 × 568 las acciones no desbordan y se llega a las dos', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), escala: 2, tamano: const Size(320, 568));

      await tester.scrollUntilVisible(entrega, 200, scrollable: find.byType(Scrollable).first);
      expect(entrega, findsOneWidget);
      expect(agendar, findsOneWidget);
      expect(tester.takeException(), isNull);
      // Con la letra grande las dos caben en el ancho: pasan a otra línea y no se montan.
      expect(tester.getRect(agendar).overlaps(tester.getRect(entrega)), isFalse);
      expect(tester.getRect(agendar).right, lessThanOrEqualTo(320));
      expect(tester.getRect(entrega).right, lessThanOrEqualTo(320));
    });

    testWidgets('con un nombre larguísimo y mucho historial las acciones siguen bajo la cuenta', (
      tester,
    ) async {
      final historial = [
        for (var i = 0; i < 150; i++)
          VentaEnFicha(
            id: 'ven-$i',
            fecha: DateTime(2026, 10, 12).subtract(Duration(days: i)),
            numeroTalonario: '${1000 + i}',
            montoCentavos: 10000,
            lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
          ),
      ];
      final m = MundoFicha(
        persona: clienteDePersonas(
          'per-1',
          'María de los Ángeles',
          apellido: 'Fernández de la Rosa Pérez',
          telefono: '099123456',
        ).persona,
        historial: historial,
        notasIniciales: notasDeLaFicha(),
      )..conRegistrarEntrega = true;
      m.cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m, escala: 2, tamano: const Size(320, 568));

      await tester.scrollUntilVisible(agendar, 200, scrollable: find.byType(Scrollable).first);
      expect(agendar, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
