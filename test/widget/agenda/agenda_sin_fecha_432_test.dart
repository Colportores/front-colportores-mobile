// 42B·01G (vista 42, contradicción 11 del canvas; decisión del 10/11, P4 del PR #681): la Agenda
// termina con el grupo «Sin fecha», las ventas con saldo que no tienen ninguna cobranza agendada, cada
// una con «Poner fecha», que pregunta «¿Cuándo volvés a cobrar?» y la agenda. Casos límite: doble toque,
// falla al guardar, volver atrás sin elegir, lista larga y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cobranza_por_agendar.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/cobranzas_sin_fecha.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart'
    show HeroAgenda;
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/ventas/presentation/pages/cuando_cobrar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;

/// Miércoles 28/10/2026, 10:00 (hora local).
final _base = DateTime(2026, 10, 28, 10);

CobranzaPorAgendar _sinFecha(
  String ventaId, {
  int saldo = 120000,
  String nombre = 'Pedro',
  String apellido = 'Gómez',
}) => CobranzaPorAgendar(
  ventaId: ventaId,
  numeroTalonario: '0042',
  espacioId: 'esp-1',
  espacioPersonaId: 'ep-1',
  saldoCentavos: saldo,
  personaNombre: nombre,
  personaApellido: apellido,
  calle: 'Grecia',
  numero: '3307',
);

void main() {
  late AgendaRepositorioQueAgenda agendas;
  late StreamController<List<CobranzaPorAgendar>> sinFecha;

  setUp(() {
    agendas = AgendaRepositorioQueAgenda();
    sinFecha = StreamController<List<CobranzaPorAgendar>>.broadcast();
  });
  tearDown(() => sinFecha.close());

  Future<void> montar(
    WidgetTester tester, {
    List<CobranzaPorAgendar> cobranzas = const [],
    ConsultaAgendaFalsa? repo,
    double escala = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var n = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consultaAgendaRepositoryProvider.overrideWithValue(
            repo ??
                ConsultaAgendaFalsa([
                  itemAgenda('e1', DateTime(2026, 10, 28, 14, 30), nombre: 'Ana'),
                ]),
          ),
          relojAgendaProvider.overrideWithValue(() => _base),
          cobranzasSinFechaProvider.overrideWith((ref, colportorId) async* {
            yield cobranzas;
            yield* sinFecha.stream;
          }),
          agendaRepositoryProvider.overrideWithValue(agendas),
          generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
          relojVisitaProvider.overrideWithValue(() => _base),
          ...Telefono().overrides,
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> desmontar(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> elegirMananaYGuardar(WidgetTester tester) async {
    await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
    await tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
    await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
  }

  bool ponerFechaPrendido(WidgetTester tester, String ventaId) =>
      tester.widget<TextButton>(find.byKey(ClavesSinFecha.ponerFecha(ventaId))).onPressed != null;

  group('el grupo', () {
    testWidgets('sale al final, después de los días, con la persona, el saldo y «Poner fecha»', (
      tester,
    ) async {
      await montar(
        tester,
        cobranzas: [
          _sinFecha('v-1'),
          _sinFecha('v-2', nombre: 'Luis', saldo: 50000),
        ],
      );

      final grupo = find.byKey(ClavesSinFecha.grupo);
      await tester.ensureVisible(grupo);
      expect(find.text('SIN FECHA (2)'), findsOneWidget);
      expect(find.text('Cobranza · Pedro Gómez'), findsOneWidget);
      expect(find.text(r'Saldo $ 1.200 · Grecia 3307'), findsOneWidget);
      expect(find.text('Cobranza · Luis Gómez'), findsOneWidget);
      expect(find.text(r'Saldo $ 500 · Grecia 3307'), findsOneWidget);
      expect(find.byKey(ClavesSinFecha.ponerFecha('v-1')), findsOneWidget);
      // Después del día de hoy.
      expect(
        tester.getTopLeft(grupo).dy,
        greaterThan(tester.getTopLeft(find.textContaining('HOY ·').first).dy),
      );
      await desmontar(tester);
    });

    testWidgets('sin cobranzas sin fecha no hay grupo', (tester) async {
      await montar(tester);

      expect(find.byKey(ClavesSinFecha.grupo), findsNothing);
      await desmontar(tester);
    });

    testWidgets('con el filtro «Entrevistas» no sale; con «Cobranzas» sí', (tester) async {
      await montar(tester, cobranzas: [_sinFecha('v-1')]);

      await tester.tap(find.text('Entrevistas'));
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesSinFecha.grupo), findsNothing);

      await tester.tap(find.text('Cobranzas'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ClavesSinFecha.grupo));
      expect(find.byKey(ClavesSinFecha.grupo), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('sin citas pero con cobranzas sin fecha: el grupo, sin «Todavía no agendaste»', (
      tester,
    ) async {
      await montar(tester, repo: ConsultaAgendaFalsa(), cobranzas: [_sinFecha('v-1')]);

      expect(find.byKey(ClavesSinFecha.grupo), findsOneWidget);
      expect(find.byType(HeroAgenda), findsNothing);
      await desmontar(tester);
    });

    testWidgets('es reactivo: cuando la lectura cambia, la fila sale sola', (tester) async {
      await montar(tester, cobranzas: [_sinFecha('v-1'), _sinFecha('v-2')]);
      await tester.ensureVisible(find.byKey(ClavesSinFecha.grupo));
      expect(find.text('SIN FECHA (2)'), findsOneWidget);

      sinFecha.add([_sinFecha('v-2')]);
      await tester.pumpAndSettle();
      expect(find.text('SIN FECHA (1)'), findsOneWidget);
      expect(find.byKey(ClavesSinFecha.fila('v-1')), findsNothing);

      sinFecha.add(const []);
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesSinFecha.grupo), findsNothing);
      await desmontar(tester);
    });

    testWidgets('una lista larga (40) se puede recorrer hasta la última', (tester) async {
      await montar(
        tester,
        cobranzas: [for (var i = 0; i < 40; i++) _sinFecha('v-$i', nombre: 'Persona $i')],
      );

      await tester.scrollUntilVisible(
        find.byKey(ClavesSinFecha.ponerFecha('v-39')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cobranza · Persona 39 Gómez'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('texto al 200 % y nombres largos: sin desbordes y «Poner fecha» de 48 dp', (
      tester,
    ) async {
      await montar(
        tester,
        escala: 2,
        cobranzas: [
          _sinFecha(
            'v-1',
            nombre: 'María de los Ángeles',
            apellido: 'Rodríguez Fernández de la Torre',
          ),
        ],
      );

      await tester.scrollUntilVisible(
        find.byKey(ClavesSinFecha.ponerFecha('v-1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      final boton = tester.getSize(find.byKey(ClavesSinFecha.ponerFecha('v-1')));
      expect(boton.height, greaterThanOrEqualTo(48));
      expect(boton.width, greaterThanOrEqualTo(48));
      await desmontar(tester);
    });
  });

  group('«Poner fecha»', () {
    testWidgets('pregunta «¿Cuándo volvés a cobrar?» con la venta y agenda la cobranza', (
      tester,
    ) async {
      await montar(tester, cobranzas: [_sinFecha('v-1')]);

      await tocar(tester, find.byKey(ClavesSinFecha.ponerFecha('v-1')));
      expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.text(r'Pedro Gómez · saldo $ 1.200'), findsOneWidget);

      await elegirMananaYGuardar(tester);

      expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
      expect(agendas.guardadas, hasLength(1));
      final cita = agendas.guardadas.values.single;
      expect(cita.tipo, TipoAgenda.cobranza);
      expect(cita.espacioId, 'esp-1');
      expect(cita.espacioPersonaId, 'ep-1');
      expect(cita.colportorId, 'col-1');
      expect(cita.fechaProgramada.toLocal(), DateTime(2026, 10, 29, 10));
      expect(ponerFechaPrendido(tester, 'v-1'), isTrue, reason: 'nada queda trabado');
      await desmontar(tester);
    });

    testWidgets('doble toque: una sola pregunta y una sola cita', (tester) async {
      await montar(tester, cobranzas: [_sinFecha('v-1'), _sinFecha('v-2')]);

      final boton = find.byKey(ClavesSinFecha.ponerFecha('v-1'));
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await tester.tap(find.byKey(ClavesSinFecha.ponerFecha('v-2')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
      await elegirMananaYGuardar(tester);
      expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
      expect(agendas.recibidas, hasLength(1));
      await desmontar(tester);
    });

    testWidgets('volver atrás sin elegir no agenda nada y se puede volver a entrar', (
      tester,
    ) async {
      await montar(tester, cobranzas: [_sinFecha('v-1')]);

      await tocar(tester, find.byKey(ClavesSinFecha.ponerFecha('v-1')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
      expect(agendas.recibidas, isEmpty);
      expect(ponerFechaPrendido(tester, 'v-1'), isTrue);

      await tocar(tester, find.byKey(ClavesSinFecha.ponerFecha('v-1')));
      expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
      await elegirMananaYGuardar(tester);
      expect(agendas.guardadas, hasLength(1));
      await desmontar(tester);
    });

    testWidgets('si la cita no se guarda: lo dice, la fila sigue y el botón vuelve', (
      tester,
    ) async {
      agendas.lanzar = StateError('sin base');
      await montar(tester, cobranzas: [_sinFecha('v-1')]);

      await tocar(tester, find.byKey(ClavesSinFecha.ponerFecha('v-1')));
      await elegirMananaYGuardar(tester);

      expect(find.text(TextosSinFecha.noSePudoAgendar), findsOneWidget);
      expect(find.byKey(ClavesSinFecha.fila('v-1')), findsOneWidget);
      expect(ponerFechaPrendido(tester, 'v-1'), isTrue);
      expect(tester.takeException(), isNull);

      // El reintento sí agenda.
      await tocar(tester, find.byKey(ClavesSinFecha.ponerFecha('v-1')));
      await elegirMananaYGuardar(tester);
      expect(agendas.guardadas, hasLength(1));
      await desmontar(tester);
    });
  });
}
