// «¿María no te pagó?» al cancelar «$ Cobrar» (decisión de Cristian, 03/11, «Sin cobro»; vista 39 C·08,
// #440): `FlujoCobrarDesdeLaCasa` con la hoja «¿Qué venta?» y el cobro reales, la pregunta, y la visita
// «Cobranza» sin cobro que queda solo con «Sí, anotar la visita». Casos límite: doble toque por la
// semántica (la ruta que se cierra ignora los toques de puntero), falla a mitad del guardado, atrás,
// nombre real y sin nombre, sin conexión, texto al 200 % y lector de pantalla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/textos_que_venta.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/dialogo_no_te_pago.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart' show Either, Right;
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

const _noPudimosGuardar = 'No pudimos guardar la visita. Probá de nuevo.';

Finder get _anotar => find.byKey(ClavesNoTePago.anotar);
Finder get _noMeEquivoque => find.byKey(ClavesNoTePago.noMeEquivoque);
Finder get _dialogo => find.byType(DialogoNoTePago);

/// Dos ventas con saldo, para que aparezca C·08 («Cancelar» solo existe ahí).
CobranzasQueLeen _dosVentas() => cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]);

/// Una casa con una cita de cobranza `PROGRAMADA`, para comprobar que la visita no la toca.
AgendaRepositorioFalso _agendaConCita() =>
    AgendaRepositorioFalso()..programada = agendaDe('cita-1', tipo: TipoAgenda.cobranza);

/// Monta el flujo, toca «Cancelar» en C·08 y deja la pregunta en pantalla.
Future<ArnesCobrarDesdeLaCasa> _hastaLaPregunta(
  WidgetTester tester, {
  CobranzasQueLeen? repo,
  AgendaRepository? agenda,
  List<PersonaDelEspacio>? personas,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool lector = false,
}) async {
  // Con la letra real (Inter): la de prueba mide 1 em por letra y desborda a 200 % por su ancho.
  await cargarFuentes408(tester);
  final a = await montarCobrarDesdeLaCasa(
    tester,
    repo: repo ?? _dosVentas(),
    agenda: agenda ?? _agendaConCita(),
    personas: personas,
    escala: escala,
    tamano: tamano,
    lector: lector,
  );
  await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));
  return a;
}

void main() {
  group('Al tocar «Cancelar» se pregunta, y no se escribe nada hasta contestar', () {
    testWidgets('«Cancelar» en C·08 abre «¿Pedro no te pagó?» con «Sí, anotar la visita» primero y '
        '«No, me equivoqué» después', (tester) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      expect(_dialogo, findsOneWidget);
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      expect(find.text('Sí, anotar la visita'), findsOneWidget);
      expect(find.text('No, me equivoqué'), findsOneWidget);
      // El orden de lectura y de foco es el de la pantalla: «Sí» arriba, «No» abajo.
      expect(
        tester.getTopLeft(_anotar).dy,
        lessThan(tester.getTopLeft(_noMeEquivoque).dy),
        reason: 'los botones van en el orden de la decisión',
      );
      // Mientras se pregunta no se escribió nada ni se devolvió nada.
      expect(agenda.recibidas, isEmpty);
      expect(a.repo.base.recibidos, isEmpty);
      expect(a.resultados, isEmpty);
      expect(a.lanzados, isEmpty);
    });

    testWidgets('el nombre es el real de la persona, el de pila: «¿María no te pagó?»', (
      tester,
    ) async {
      await _hastaLaPregunta(
        tester,
        personas: [clienteDePersonas('p1', 'María', apellido: 'Fernández')],
      );

      expect(find.text('¿María no te pagó?'), findsOneWidget);
      expect(find.textContaining('Fernández'), findsNothing);
      expect(find.textContaining('Pedro'), findsNothing);
    });

    testWidgets('la persona ya no está en la casa: la pregunta no inventa un nombre', (
      tester,
    ) async {
      await _hastaLaPregunta(tester, personas: const []);

      expect(find.text('¿No te pagaron?'), findsOneWidget);
      expect(find.textContaining('Pedro'), findsNothing);
      expect(find.text('Sí, anotar la visita'), findsOneWidget);
      expect(find.text('No, me equivoqué'), findsOneWidget);
    });

    testWidgets('«Cancelar» también pregunta cuando C·08 estaba cargando', (tester) async {
      final repo = _dosVentas()..compuerta = Completer<void>();
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: _agendaConCita());
      expect(find.byKey(ClavesQueVenta.cargando), findsOneWidget);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));

      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      expect(a.resultados, isEmpty);
    });

    testWidgets('«Cancelar» también pregunta cuando no se pudieron leer las ventas', (
      tester,
    ) async {
      final repo = _dosVentas()..fallas.add(const FailureInesperado(causa: 'x'));
      await montarCobrarDesdeLaCasa(tester, repo: repo, agenda: _agendaConCita());
      expect(find.byKey(ClavesQueVenta.error), findsOneWidget);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));

      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
    });

    testWidgets('sin pregunta: atrás en C·08 y «Cerrar» cuando ya no debe nada solo salen', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(tester, repo: _dosVentas(), agenda: agenda);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(_dialogo, findsNothing);
      expect(a.resultados, [false]);
      expect(agenda.recibidas, isEmpty);

      // Pagó todo mientras tanto: el aviso «no tiene ventas con saldo» se cierra con «Cerrar».
      final sinSaldo = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas(const []),
        agenda: agenda,
      );
      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cerrar));
      expect(_dialogo, findsNothing);
      expect(sinSaldo.resultados, [false]);
      expect(agenda.recibidas, isEmpty);
    });
  });

  group('«Sí, anotar la visita»', () {
    testWidgets('queda la visita «Cobranza» sin cobro y la cita de cobranza sigue PROGRAMADA', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      await tocarQueVenta(tester, _anotar);

      final visita = agenda.recibidas.single;
      expect(visita.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(visita.visita.espacioId, 'esp-1');
      expect(visita.visita.espacioPersonaId, 'ep-p1');
      // Sin agenda: la visita no cumple ni cancela la cita.
      expect(visita.agendaId, isNull);
      expect(agenda.programada!.estado, EstadoAgenda.programada);
      expect(agenda.programada!.id, 'cita-1');
      expect(agenda.canceladas, isEmpty);
      expect(agenda.deshechas, isEmpty);
      // Y no hay cobro: ni se abrió la pantalla del cobro ni se registró nada.
      expect(pagina, findsNothing);
      expect(a.repo.base.recibidos, isEmpty);
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      expect(a.lanzados, isEmpty);
    });

    testWidgets('el flujo termina: ni pregunta ni hoja abierta, y un aviso dice qué quedó', (
      tester,
    ) async {
      final a = await _hastaLaPregunta(tester);

      await tocarQueVenta(tester, _anotar);

      expect(_dialogo, findsNothing);
      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
      expect(find.text(TextosQueVenta.visitaAnotada), findsOneWidget);
      expect(find.text('cobrar'), findsOneWidget, reason: 'se vuelve a donde estaba');
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
    });

    testWidgets('la persona ya no está en la casa: la visita se guarda sin persona', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      await _hastaLaPregunta(tester, agenda: agenda, personas: const []);

      await tocarQueVenta(tester, _anotar);

      expect(agenda.recibidas.single.visita.espacioPersonaId, isNull);
      expect(agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
    });

    testWidgets('sin conexión es igual: no hay red en el flujo', (tester) async {
      final agenda = _agendaConCita();
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: _dosVentas(),
        agenda: agenda,
        abrir: false,
      );
      a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await abrirCobrarDesdeLaCasa(tester);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));
      expect(find.text('¿Pedro no te pagó?'), findsOneWidget);
      await tocarQueVenta(tester, _anotar);

      expect(agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.cobranza);
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      expect(find.textContaining('conexión'), findsNothing);
    });

    testWidgets('doble toque en «Sí» (dos veces por la semántica): una sola visita', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final agenda = _agendaConCita()..compuerta = Completer<void>();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      final boton = find.semantics.byLabel('Sí, anotar la visita');
      tester.semantics.performAction(boton, SemanticsAction.tap);
      tester.semantics.performAction(boton, SemanticsAction.tap);
      await asentarAgendar(tester);

      // En curso: los dos botones esperan y el lector oye qué pasa.
      expect(agenda.recibidas, hasLength(1));
      expect(tester.widget<FilledButton>(_anotar).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_noMeEquivoque).onPressed, isNull);
      expect(find.text(TextosQueVenta.anotandoLaVisita), findsOneWidget);

      agenda.compuerta!.complete();
      await asentarAgendar(tester);

      expect(agenda.recibidas, hasLength(1));
      expect(a.resultados, hasLength(1));
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
      expect(find.text('cobrar'), findsOneWidget, reason: 'no se sacó la pantalla de abajo');
      semantica.dispose();
    });

    testWidgets('«No» tocado mientras se guarda no hace nada: gana el «Sí»', (tester) async {
      final semantica = tester.ensureSemantics();
      final agenda = _agendaConCita()..compuerta = Completer<void>();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      tester.semantics.performAction(
        find.semantics.byLabel('Sí, anotar la visita'),
        SemanticsAction.tap,
      );
      tester.semantics.performAction(
        find.semantics.byLabel('No, me equivoqué'),
        SemanticsAction.tap,
      );
      await asentarAgendar(tester);
      expect(_dialogo, findsOneWidget);

      agenda.compuerta!.complete();
      await asentarAgendar(tester);

      expect(agenda.recibidas, hasLength(1));
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
      semantica.dispose();
    });

    testWidgets('atrás mientras se guarda espera: el guardado termina y la visita queda una vez', (
      tester,
    ) async {
      final agenda = _agendaConCita()..compuerta = Completer<void>();
      final a = await _hastaLaPregunta(tester, agenda: agenda);
      await tester.tap(_anotar);
      await asentarAgendar(tester);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(_dialogo, findsOneWidget, reason: 'atrás no corta un guardado en curso');

      agenda.compuerta!.complete();
      await asentarAgendar(tester);

      expect(_dialogo, findsNothing);
      expect(agenda.recibidas, hasLength(1));
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
    });

    testWidgets('falla el guardado: lo dice, los botones vuelven y el reintento repite la misma '
        'visita (no guarda dos)', (tester) async {
      final agenda = _agendaConCita()..resultados.add(const FailureInesperado(causa: 'StateError'));
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      await tocarQueVenta(tester, _anotar);

      expect(find.text(_noPudimosGuardar), findsOneWidget);
      expect(_dialogo, findsOneWidget);
      expect(tester.widget<FilledButton>(_anotar).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(_noMeEquivoque).onPressed, isNotNull);
      expect(find.text(TextosQueVenta.anotandoLaVisita), findsNothing, reason: 'nada trabado');
      expect(a.resultados, isEmpty);

      await tocarQueVenta(tester, _anotar);

      expect(agenda.recibidas.map((r) => r.visita.id), ['visita-1', 'visita-1']);
      expect(_dialogo, findsNothing);
      expect(a.resultados.single, isA<CobranzaAnotadaSinCobro>());
    });

    testWidgets('falla el guardado y se toca «No, me equivoqué»: sale sin visita', (tester) async {
      final agenda = _agendaConCita()..resultados.add(const FailureInesperado(causa: 'StateError'));
      final a = await _hastaLaPregunta(tester, agenda: agenda);
      await tocarQueVenta(tester, _anotar);
      expect(find.text(_noPudimosGuardar), findsOneWidget);

      await tocarQueVenta(tester, _noMeEquivoque);

      expect(a.resultados, [false]);
      expect(_dialogo, findsNothing);
      expect(agenda.programada!.estado, EstadoAgenda.programada);
    });

    testWidgets('el guardado lanza en vez de devolver una falla: se dice y no queda trabado', (
      tester,
    ) async {
      final agenda = _AgendaQueLanza();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      await tocarQueVenta(tester, _anotar);

      expect(find.text(_noPudimosGuardar), findsOneWidget);
      expect(tester.widget<FilledButton>(_anotar).onPressed, isNotNull);
      expect(a.lanzados, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('«No, me equivoqué» y atrás', () {
    testWidgets('«No» no escribe nada y vuelve a donde estaba (false)', (tester) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      await tocarQueVenta(tester, _noMeEquivoque);

      expect(a.resultados, [false]);
      expect(_dialogo, findsNothing);
      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
      expect(find.text('cobrar'), findsOneWidget);
      expect(agenda.recibidas, isEmpty);
      expect(a.repo.base.recibidos, isEmpty);
      expect(agenda.programada!.estado, EstadoAgenda.programada);
      expect(find.text(TextosQueVenta.visitaAnotada), findsNothing);
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
    });

    testWidgets('atrás cierra la pregunta como «No»: nada escrito', (tester) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(_dialogo, findsNothing);
      expect(a.resultados, [false]);
      expect(agenda.recibidas, isEmpty);
      expect(find.text('cobrar'), findsOneWidget);
    });

    testWidgets('tocar afuera no cierra la pregunta (es una decisión con efecto)', (tester) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      await tester.tapAt(const Offset(4, 4));
      await asentarAgendar(tester);

      expect(_dialogo, findsOneWidget);
      expect(a.resultados, isEmpty);
      expect(agenda.recibidas, isEmpty);
    });

    testWidgets('doble toque en «No» (dos veces por la semántica): se cierra una vez y la '
        'pantalla de abajo sigue', (tester) async {
      final semantica = tester.ensureSemantics();
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);

      final boton = find.semantics.byLabel('No, me equivoqué');
      tester.semantics.performAction(boton, SemanticsAction.tap);
      tester.semantics.performAction(boton, SemanticsAction.tap);
      await asentarAgendar(tester);

      expect(a.resultados, [false]);
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
      expect(find.text('cobrar'), findsOneWidget, reason: 'el segundo toque no sacó la pantalla');
      expect(agenda.recibidas, isEmpty);
      semantica.dispose();
    });

    testWidgets('volver a entrar después de «No»: se puede cobrar y no quedó nada trabado', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);
      await tocarQueVenta(tester, _noMeEquivoque);

      await abrirCobrarDesdeLaCasa(tester);
      await tocarQueVenta(tester, _cobrarEnLaHoja);

      expect(pagina, findsOneWidget);
      expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
      expect(a.resultados, [false]);
      expect(agenda.recibidas, isEmpty);
    });

    testWidgets('volver a entrar después de «Sí»: se pregunta de nuevo y es otra visita', (
      tester,
    ) async {
      final agenda = _agendaConCita();
      final a = await _hastaLaPregunta(tester, agenda: agenda);
      await tocarQueVenta(tester, _anotar);

      await abrirCobrarDesdeLaCasa(tester);
      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));
      await tocarQueVenta(tester, _anotar);

      expect(agenda.recibidas.map((r) => r.visita.id).toSet(), hasLength(2));
      expect(a.resultados, everyElement(isA<CobranzaAnotadaSinCobro>()));
    });
  });

  group('Accesibilidad', () {
    testWidgets('los dos botones llegan a 48 dp y a 56 de alto, de borde a borde', (tester) async {
      await _hastaLaPregunta(tester);

      for (final boton in [_anotar, _noMeEquivoque]) {
        expect(tester.getSize(boton).height, greaterThanOrEqualTo(56));
        expect(tester.getSize(boton).width, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('el lector oye la pregunta al abrirse y los dos botones, en ese orden', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _hastaLaPregunta(tester, lector: true);

      expect(find.semantics.byLabel('¿Pedro no te pagó?'), findsWidgets);
      final si = find.semantics.byLabel('Sí, anotar la visita');
      final no = find.semantics.byLabel('No, me equivoqué');
      expect(si, findsOneWidget);
      expect(no, findsOneWidget);
      expect(
        tester.getSemantics(_anotar),
        isSemantics(label: 'Sí, anotar la visita', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(_noMeEquivoque),
        isSemantics(label: 'No, me equivoqué', isButton: true, hasTapAction: true),
      );
      // El título es un encabezado.
      expect(
        tester.getSemantics(find.text('¿Pedro no te pagó?')),
        isSemantics(label: '¿Pedro no te pagó?', isHeader: true),
      );
      // Foco: lo que está primero en pantalla es lo primero que recorre el lector.
      expect(tester.getRect(_anotar).top, lessThan(tester.getRect(_noMeEquivoque).top));
      semantica.dispose();
    });

    testWidgets('mientras guarda, el lector oye «Anotando la visita…» (región viva)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final agenda = _agendaConCita()..compuerta = Completer<void>();
      await _hastaLaPregunta(tester, agenda: agenda);

      tester.semantics.performAction(
        find.semantics.byLabel('Sí, anotar la visita'),
        SemanticsAction.tap,
      );
      await asentarAgendar(tester);

      expect(find.semantics.byLabel(TextosQueVenta.anotandoLaVisita), findsOneWidget);
      agenda.compuerta!.complete();
      await asentarAgendar(tester);
      semantica.dispose();
    });

    testWidgets('texto al 200 % en 320×568: la pregunta, los dos botones y el aviso de falla '
        'entran sin desborde', (tester) async {
      final agenda = _agendaConCita()..resultados.add(const FailureInesperado(causa: 'StateError'));
      await _hastaLaPregunta(
        tester,
        agenda: agenda,
        escala: 2,
        tamano: const Size(320, 568),
        personas: [clienteDePersonas('p1', 'María Guadalupe', apellido: 'Fernández')],
      );
      expect(find.text('¿María Guadalupe no te pagó?'), findsOneWidget);

      await tocarQueVenta(tester, _anotar);
      expect(find.text(_noPudimosGuardar), findsOneWidget);
      await tester.ensureVisible(_noMeEquivoque);
      await tester.pump();
      await tester.tap(_noMeEquivoque);
      await asentarAgendar(tester);

      expect(tester.takeException(), isNull);
      expect(_dialogo, findsNothing);
    });
  });
}

Finder get _cobrarEnLaHoja => find.byKey(ClavesQueVenta.cobrar);

/// Un repositorio de la agenda que lanza al guardar la visita (una falla que se escapa en vez de un
/// `Left`). Nada más se usa en estos tests.
final class _AgendaQueLanza implements AgendaRepository {
  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) => throw StateError('se cayó la base');

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) async => const Right(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
