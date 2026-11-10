// Salir del cobro (vista 28) sin cobrar desde «$ Cobrar» de la vista 39 (decisión del 10/11, P2 de
// #440, por el precedente de Cristian «Sin cobro» del 03/11): con una sola venta con saldo C·08 se
// salta y el cobro solo tiene «✕»; «✕» o atrás sin haber cobrado son el «Cancelar» y preguntan
// «¿María no te pagó?» con los mismos textos y el mismo comportamiento que el «Cancelar» de C·08.
// «Volver» (la venta ya no está o ya no debe nada) no pregunta; con algo escrito, antes «¿Descartar?».
// Casos límite: doble toque, falla a mitad del cobro, atrás mientras se registra, cobro parcial,
// volver a entrar, sin conexión, texto al 200 % y 48 dp.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/textos_que_venta.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/dialogo_no_te_pago.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/campo_falsos.dart' show agendaDe;
import '../../helpers/cobrar_desde_la_casa_arnes.dart';
import '../../helpers/cobro_arnes.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista23_408_arnes.dart' show cargarFuentes408;

Finder get _dialogo => find.byType(DialogoNoTePago);
Finder get _anotar => find.byKey(ClavesNoTePago.anotar);
Finder get _noMeEquivoque => find.byKey(ClavesNoTePago.noMeEquivoque);
Finder get _descartar => find.text('Descartar');
Finder get _seguirEscribiendo => find.text('Seguir escribiendo');
Finder get _avisoDescartar => find.text('¿Descartar lo que escribiste?');

/// Una sola venta con saldo: C·08 se salta y se cae directo en el cobro.
CobranzasQueLeen _unaVenta() => cobranzasConVentas([ventaDelCanvas38()]);

/// Una casa con una cita de cobranza `PROGRAMADA`, para comprobar que la visita no la toca.
AgendaRepositorioFalso _agendaConCita() =>
    AgendaRepositorioFalso()..programada = agendaDe('cita-1', tipo: TipoAgenda.cobranza);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await asentarAgendar(tester);
}

Future<void> _atrasDelSistema(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await asentarAgendar(tester);
}

void main() {
  group('Una sola venta: «✕» o atrás sin cobrar son el «Cancelar»', () {
    testWidgets('dado una venta, cuando toco «✕» sin escribir nada, entonces el cobro se cierra y '
        'pregunta «¿Pedro no te pagó?» sin haber escrito nada todavía', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      expect(find.byKey(ClavesQueVenta.lista), findsNothing, reason: 'C·08 se salta');
      expect(pagina, findsOneWidget);

      await tocarCobro(tester, cerrarCobro);

      expect(pagina, findsNothing);
      expect(_dialogo, findsOneWidget);
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      expect(find.text('Sí, anotar la visita'), findsOneWidget);
      expect(find.text('No, me equivoqué'), findsOneWidget);
      expect(agenda.recibidas, isEmpty);
      expect(a.repo.base.recibidos, isEmpty);
      expect(a.resultados, isEmpty);
    });

    testWidgets('«Sí, anotar la visita»: UNA visita «Cobranza» sin cobro y sin agenda, la cita sigue '
        'PROGRAMADA y el flujo devuelve CobranzaAnotadaSinCobro', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);

      await tocarCobro(tester, cerrarCobro);
      await _tocar(tester, _anotar);

      final visita = agenda.recibidas.single;
      expect(visita.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(visita.visita.espacioId, 'esp-1');
      expect(visita.visita.espacioPersonaId, 'ep-p1');
      expect(visita.agendaId, isNull);
      expect(agenda.programada!.estado, EstadoAgenda.programada);
      expect(agenda.canceladas, isEmpty);
      expect(a.repo.base.recibidos, isEmpty, reason: 'no hay cobro');
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      expect(_dialogo, findsNothing);
      expect(find.text(TextosQueVenta.visitaAnotada), findsOneWidget);
      expect(a.rutas.aperturas - 1, a.rutas.cierres, reason: 'no queda ninguna ruta colgada');
    });

    testWidgets('atrás del sistema en el cobro también pregunta; «No, me equivoqué» no escribe nada '
        'y vuelve a donde estaba (false)', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);

      await _atrasDelSistema(tester);
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);

      await _tocar(tester, _noMeEquivoque);

      expect(a.resultados, [false]);
      expect(_dialogo, findsNothing);
      expect(pagina, findsNothing);
      expect(find.text('cobrar'), findsOneWidget);
      expect(agenda.recibidas, isEmpty);
      expect(agenda.programada!.estado, EstadoAgenda.programada);
      expect(find.text(TextosQueVenta.visitaAnotada), findsNothing);
    });

    testWidgets('atrás en la pregunta es «No»: nada escrito', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await tocarCobro(tester, cerrarCobro);

      await _atrasDelSistema(tester);

      expect(_dialogo, findsNothing);
      expect(a.resultados, [false]);
      expect(agenda.recibidas, isEmpty);
    });

    testWidgets('la persona ya no está en la casa: «¿No te pagaron?» y la visita sin persona', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      await montarCobrarDesdeLaCasa(
        tester,
        repo: _unaVenta(),
        agenda: agenda,
        personas: const [],
      );

      await tocarCobro(tester, cerrarCobro);
      expect(find.text('¿No te pagaron?'), findsOneWidget);
      expect(find.textContaining('Pedro'), findsNothing);
      await _tocar(tester, _anotar);

      expect(agenda.recibidas.single.visita.espacioPersonaId, isNull);
      expect(agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
    });

    testWidgets('el nombre es el de pila de la persona real: «¿María no te pagó?»', (tester) async {
      await montarCobrarDesdeLaCasa(
        tester,
        repo: _unaVenta(),
        agenda: _agendaConCita(),
        personas: [clienteDePersonas('p1', 'María', apellido: 'Fernández')],
      );

      await tocarCobro(tester, cerrarCobro);

      expect(find.text('¿María no te pagó?'), findsOneWidget);
      expect(find.textContaining('Fernández'), findsNothing);
    });

    testWidgets('sin poder leer la venta en el cobro, «✕» también pregunta (no se cobró)', (
      tester,
    ) async {
      final repo = _unaVenta();
      repo.base.fallaDeLectura = const FailureInesperado(causa: 'x');
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: _agendaConCita());
      expect(find.byKey(const Key('cobro_error_lectura')), findsOneWidget);

      await tocarCobro(tester, cerrarCobro);

      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      expect(a.resultados, isEmpty);
    });
  });

  group('«Volver» no pregunta: no había nada que cobrar', () {
    testWidgets('la venta ya no está: «Volver» sale sin preguntar y sin escribir nada (false)', (
      tester,
    ) async {
      // C·08 la lista (lectura previa) pero el cobro ya no la encuentra.
      final repo = cobranzasConVentas(const [])..fija = [ventaDelCanvas38()];
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: agenda);
      expect(find.byKey(const Key('cobro_sin_venta')), findsOneWidget);

      await tocarCobro(tester, botonRegistrar);

      expect(_dialogo, findsNothing);
      expect(a.resultados, [false]);
      expect(agenda.recibidas, isEmpty);
      expect(pagina, findsNothing);
    });

    testWidgets('la venta ya no está: «✕» y atrás tampoco preguntan', (tester) async {
      final repo = cobranzasConVentas(const [])..fija = [ventaDelCanvas38()];
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: agenda);

      await tocarCobro(tester, cerrarCobro);
      expect(_dialogo, findsNothing);
      expect(a.resultados, [false]);

      await abrirCobrarDesdeLaCasa(tester);
      await _atrasDelSistema(tester);
      expect(_dialogo, findsNothing);
      expect(a.resultados, [false, false]);
      expect(agenda.recibidas, isEmpty);
    });

    testWidgets('la venta ya quedó saldada: «Volver» y «✕» salen sin preguntar (false)', (
      tester,
    ) async {
      // C·08 todavía la veía con saldo, pero se pagó entera desde otro lado.
      final repo = _unaVenta()..fija = [ventaDelCanvas38()];
      repo.base.cobros['otro'] = cobroDeEjemplo('otro', 120000, venta: 'v-38');
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: agenda);
      expect(find.text('Venta pagada'), findsOneWidget);

      await tocarCobro(tester, botonRegistrar);
      expect(_dialogo, findsNothing);
      expect(a.resultados, [false]);

      await abrirCobrarDesdeLaCasa(tester);
      await tocarCobro(tester, cerrarCobro);
      expect(_dialogo, findsNothing);
      expect(a.resultados, [false, false]);
      expect(agenda.recibidas, isEmpty);
    });
  });

  group('Con algo escrito, primero «¿Descartar lo que escribiste?»', () {
    testWidgets('«Seguir escribiendo» se queda en el cobro con el monto y no pregunta nada más', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: _agendaConCita());
      await escribirMonto(tester, '600');

      await tocarCobro(tester, cerrarCobro);
      expect(_avisoDescartar, findsOneWidget);
      expect(_dialogo, findsNothing, reason: 'la pregunta del pago va después');

      await _tocar(tester, _seguirEscribiendo);

      expect(pagina, findsOneWidget);
      expect(_dialogo, findsNothing);
      expect(find.text('600'), findsOneWidget);
      expect(a.resultados, isEmpty);
    });

    testWidgets('«Descartar» cierra el cobro y recién ahí pregunta; «Sí» anota sin cobro', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await escribirMonto(tester, '600');

      await tocarCobro(tester, cerrarCobro);
      await _tocar(tester, _descartar);

      expect(_avisoDescartar, findsNothing);
      expect(pagina, findsNothing);
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      await _tocar(tester, _anotar);

      expect(a.repo.base.recibidos, isEmpty, reason: 'lo escrito se descartó: no hay cobro');
      expect(agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
    });
  });

  group('Mientras se registra y después de cobrar', () {
    testWidgets('atrás mientras se registra el cobro espera: ni «✕», ni descartar, ni pregunta', (
      tester,
    ) async {
      final repo = _unaVenta();
      repo.base.compuerta = Completer<void>();
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: _agendaConCita());
      await escribirMonto(tester, '600');
      await tester.tap(botonRegistrar);
      await asentarAgendar(tester);

      expect(cerrarCobro, findsNothing, reason: 'la «✕» no se ofrece mientras se registra');
      await _atrasDelSistema(tester);
      expect(pagina, findsOneWidget);
      expect(_avisoDescartar, findsNothing);
      expect(_dialogo, findsNothing);

      repo.base.compuerta!.complete();
      await asentarAgendar(tester);

      // Quedó el cobro parcial; atrás ya cobró: devuelve true, sin pregunta.
      await _atrasDelSistema(tester);
      expect(_dialogo, findsNothing);
      expect(a.resultados, [true]);
      expect(repo.base.recibidos, hasLength(1));
    });

    testWidgets('falla a mitad del cobro: el botón vuelve, y salir después pregunta (tras '
        'descartar el monto)', (tester) async {
      final repo = _unaVenta();
      repo.base.fallas.add(const FailureCobroNoGuardado(causa: 'x'));
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: agenda);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);

      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull, reason: 'nada trabado');
      expect(cerrarCobro, findsOneWidget);

      await tocarCobro(tester, cerrarCobro);
      await _tocar(tester, _descartar);
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      await _tocar(tester, _noMeEquivoque);

      expect(a.resultados, [false]);
      expect(agenda.recibidas, isEmpty);
    });

    testWidgets('cobro parcial y «Listo»: true y sin pregunta (la visita la guarda quien abrió)', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);

      await tocarCobro(tester, find.text('Listo'));

      expect(_dialogo, findsNothing);
      expect(a.resultados, [true]);
      expect(agenda.recibidas, isEmpty, reason: 'este flujo no escribe la visita de un cobro');
    });

    testWidgets('cobro parcial y atrás del sistema: true y sin pregunta', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);

      await _atrasDelSistema(tester);

      expect(_dialogo, findsNothing);
      expect(a.resultados, [true]);
      expect(agenda.recibidas, isEmpty);
    });
  });

  group('Doble toque y dos acciones seguidas', () {
    testWidgets('doble toque en «✕» (dos veces por la semántica): una sola pregunta y la pantalla '
        'de abajo sigue', (tester) async {
      final semantica = tester.ensureSemantics();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: _agendaConCita());

      // La «✕» lleva «Volver» como tooltip del IconButton.
      final cerrar = find.semantics.byPredicate(
        (n) => n.label == 'Volver' || n.tooltip == 'Volver',
      );
      tester.semantics.performAction(cerrar, SemanticsAction.tap);
      tester.semantics.performAction(cerrar, SemanticsAction.tap);
      await asentarAgendar(tester);

      expect(_dialogo, findsOneWidget);
      expect(pagina, findsNothing);
      expect(find.text('cobrar'), findsOneWidget, reason: 'el segundo toque no sacó otra pantalla');

      await _tocar(tester, _noMeEquivoque);
      expect(a.resultados, [false]);
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
      semantica.dispose();
    });

    testWidgets('doble toque en «✕» con algo escrito: un solo «¿Descartar?»', (tester) async {
      await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: _agendaConCita());
      await escribirMonto(tester, '600');

      final x = tester.widget<IconButton>(cerrarCobro).onPressed!;
      x();
      x();
      await asentarAgendar(tester);

      expect(_avisoDescartar, findsOneWidget);
      expect(_dialogo, findsNothing);
    });

    testWidgets('doble toque en «Sí» por la semántica: una sola visita', (tester) async {
      final semantica = tester.ensureSemantics();
      final agenda = _agendaConCita()..compuerta = Completer<void>();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await tocarCobro(tester, cerrarCobro);

      final si = find.semantics.byLabel('Sí, anotar la visita');
      tester.semantics.performAction(si, SemanticsAction.tap);
      tester.semantics.performAction(si, SemanticsAction.tap);
      await asentarAgendar(tester);
      agenda.compuerta!.complete();
      await asentarAgendar(tester);

      expect(agenda.recibidas, hasLength(1));
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      semantica.dispose();
    });
  });

  group('Volver a entrar y sin conexión', () {
    testWidgets('después de «No» se vuelve a entrar y se puede cobrar: nada quedó trabado', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await tocarCobro(tester, cerrarCobro);
      await _tocar(tester, _noMeEquivoque);

      await abrirCobrarDesdeLaCasa(tester);
      expect(pagina, findsOneWidget);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, botonRegistrar);
      await tocarCobro(tester, find.text('Listo'));

      expect(a.resultados, [false, true]);
      expect(a.repo.base.recibidos, hasLength(1));
      expect(agenda.recibidas, isEmpty);
    });

    testWidgets('después de «Sí» se vuelve a entrar, se sale otra vez y es otra visita', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: agenda);
      await tocarCobro(tester, cerrarCobro);
      await _tocar(tester, _anotar);

      await abrirCobrarDesdeLaCasa(tester);
      await tocarCobro(tester, cerrarCobro);
      await _tocar(tester, _anotar);

      expect(agenda.recibidas.map((r) => r.visita.id).toSet(), hasLength(2));
      expect(a.resultados, everyElement(isA<CobranzaAnotadaSinCobro>()));
    });

    testWidgets('sin conexión es igual: no hay red en el flujo', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: _unaVenta(),
        agenda: agenda,
        abrir: false,
      );
      a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await abrirCobrarDesdeLaCasa(tester);

      await tocarCobro(tester, cerrarCobro);
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      await _tocar(tester, _anotar);

      expect(agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      expect(find.textContaining('conexión'), findsNothing);
    });
  });

  group('Accesibilidad', () {
    testWidgets('la «✕» del cobro mide al menos 48 × 48 dp y el lector la oye como botón', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarCobrarDesdeLaCasa(tester, repo: _unaVenta(), agenda: _agendaConCita());

      final tam = tester.getSize(cerrarCobro);
      expect(tam.width, greaterThanOrEqualTo(48));
      expect(tam.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(cerrarCobro),
        anyOf(
          isSemantics(label: 'Volver', isButton: true, hasTapAction: true),
          isSemantics(tooltip: 'Volver', isButton: true, hasTapAction: true),
        ),
      );
      semantica.dispose();
    });

    testWidgets('texto al 200 % en 320×568: «✕» a 48 dp, la pregunta y sus botones entran sin '
        'desborde y «Sí» anota', (tester) async {
      // Con la letra real (Inter): la de prueba mide 1 em por letra y desborda a 200 % por su ancho.
      await cargarFuentes408(tester);
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: _unaVenta(),
        agenda: agenda,
        escala: 2,
        tamano: const Size(320, 568),
        personas: [clienteDePersonas('p1', 'María Guadalupe', apellido: 'Fernández')],
      );
      await traerAlAlcance(tester, cerrarCobro);
      expect(tester.getSize(cerrarCobro).height, greaterThanOrEqualTo(48));

      await tocarCobro(tester, cerrarCobro);
      expect(find.text('¿María Guadalupe no te pagó?'), findsOneWidget);
      for (final boton in [_anotar, _noMeEquivoque]) {
        await tester.ensureVisible(boton);
        await tester.pump();
        expect(tester.getSize(boton).height, greaterThanOrEqualTo(48));
      }
      await _tocar(tester, _anotar);

      expect(tester.takeException(), isNull);
      expect(agenda.recibidas, hasLength(1));
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
    });
  });
}
