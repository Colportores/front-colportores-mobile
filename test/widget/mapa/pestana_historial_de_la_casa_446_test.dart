// La pestaña Historial de la hoja de la casa (vista 39, C·03 y C·04, #446): las filas con el símbolo del
// resultado, los filtros, el detalle de una visita o de una venta, el cobro que abre su detalle y los
// estados cargando, vacío, filtro sin resultados y error; con los casos límite de cada flujo (doble
// toque, falla a mitad, dos acciones seguidas, volver y reentrar, listas largas y letra al 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza;
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart'
    show FormatoBajaPersona;
import 'package:colportores_mobile/features/mapa/presentation/textos_historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// El «hoy» de los tests: domingo 25/10/2026 a las 16:00, hora local.
final ahora = DateTime(2026, 10, 25, 16);

DateTime local(int mes, int dia, [int hora = 12, int minuto = 0]) =>
    DateTime(2026, mes, dia, hora, minuto).toUtc();

const pedro = PersonaDelEvento(nombre: 'Pedro', apellido: 'Gómez');

final cobroHoy = CobroDeLaCasa(
  id: 'cob-1',
  fecha: local(10, 25, 14, 20),
  montoCentavos: 60000,
  medio: MedioCobranza.efectivo,
  ventaId: 'ven-1',
  numeroTalonario: '0038',
  persona: pedro,
);

final ventaDelDoce = VentaDeLaCasa(
  id: 'ven-1',
  fecha: local(10, 12, 14),
  numeroTalonario: '0038',
  montoCentavos: 480000,
  pagadoCentavos: 360000,
  lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
  persona: pedro,
  espacioPersonaId: 'ep-pedro',
  nota: 'quiere Nuestros Hijos',
);

final entrevistaDelCinco = VisitaDeLaCasa(
  id: 'vis-2',
  fecha: local(10, 5, 17),
  resultado: TipoResultadoVisita.entrevista,
  persona: pedro,
  nota: 'volver con la esposa',
  duracion: const Duration(minutes: 22),
);

final noContestoDelTres = VisitaDeLaCasa(
  id: 'vis-1',
  fecha: local(10, 3, 15),
  resultado: TipoResultadoVisita.noContesto,
);

/// Lo de C·03: cobro de hoy, venta del 12, entrevista del 5 y «No contestó» del 3.
final eventosC03 = <EventoDeLaCasa>[cobroHoy, ventaDelDoce, entrevistaDelCinco, noContestoDelTres];

class HistorialFalso implements HistorialDeLaCasa {
  HistorialFalso(this._lectura);

  HistorialFalso.de(List<EventoDeLaCasa> eventos) : this((_) => Stream.value(eventos));

  final Stream<List<EventoDeLaCasa>> Function(String espacioId) _lectura;
  final espaciosLeidos = <String>[];

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) {
    espaciosLeidos.add(espacioId);
    return _lectura(espacioId);
  }
}

/// Cuenta las hojas modales que se abren.
class _CuentaDeHojas extends NavigatorObserver {
  var abiertas = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) abiertas++;
  }
}

void main() {
  late _CuentaDeHojas hojas;

  Future<void> asentar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<HistorialFalso> montar(
    WidgetTester tester, {
    List<EventoDeLaCasa>? eventos,
    HistorialFalso? fuente,
    FutureOr<Object?> Function(String)? verCobro,
    FutureOr<Object?> Function(ContextoDeVentaDeLaCasa)? verVenta,
    double escala = 1,
    Size tamano = const Size(412, 915),
    String espacio = 'esp-1',
    Key? clave,
  }) async {
    final historial = fuente ?? HistorialFalso.de(eventos ?? eventosC03);
    hojas = _CuentaDeHojas();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = <Override>[
      historialDeLaCasaFuenteProvider.overrideWithValue(historial),
      relojPersonaProvider.overrideWithValue(() => ahora),
      verCobroDesdeLaCasaProvider.overrideWithValue(verCobro),
      verVentaDesdeLaCasaProvider.overrideWithValue(verVenta),
    ];
    await tester.pumpWidget(
      ProviderScope(
        key: clave ?? UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: temaClaro(),
          navigatorObservers: [hojas],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PestanaHistorialDeLaCasa(espacioId: espacio, direccion: 'Grecia 3310'),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
    return historial;
  }

  String monto(int centavos) => FormatoBajaPersona.monto(centavos);

  Finder fila(String id) => find.byKey(ClavesHistorialDeLaCasa.fila(id));
  Finder filas() => find.byWidgetPredicate((w) => w is FilaDelHistorialDeLaCasa);

  group('las filas (C·03)', () {
    testWidgets(
      'dado el historial de C·03, cada fila trae su línea chica, su título y su línea de abajo',
      (tester) async {
        final f = await montar(tester);

        expect(f.espaciosLeidos, ['esp-1']);
        expect(filas(), findsNWidgets(4));
        // Cobro de hoy.
        expect(find.text('HOY 14:20 · COBRO'), findsOneWidget);
        expect(find.text('${monto(60000)} en efectivo · Pedro'), findsOneWidget);
        expect(find.text('Venta 0038'), findsOneWidget);
        // Venta con la nota de su visita.
        expect(find.text('12/10 · VENTA 0038'), findsOneWidget);
        expect(find.text('Salud y Hogar · Pedro'), findsOneWidget);
        expect(find.text('${monto(480000)} · ✎ quiere Nuestros Hijos'), findsOneWidget);
        // Entrevista dada con su duración.
        expect(find.text('05/10 · ENTREVISTA DADA · 22 MIN'), findsOneWidget);
        expect(find.text('Pedro Gómez'), findsOneWidget);
        expect(find.text('✎ volver con la esposa'), findsOneWidget);
        // No contestó, sin persona ni nota.
        expect(find.text('03/10 · NO CONTESTÓ'), findsOneWidget);
        expect(find.text('Nadie atendió'), findsOneWidget);
      },
    );

    testWidgets('dado el orden, las filas siguen el de la lista: lo más nuevo arriba', (
      tester,
    ) async {
      await montar(tester);

      final ys = [
        for (final id in ['cob-1', 'ven-1', 'vis-2', 'vis-1']) tester.getTopLeft(fila(id)).dy,
      ];

      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('dado cada resultado, el símbolo es el del mapa', (tester) async {
      await montar(
        tester,
        eventos: [
          VisitaDeLaCasa(id: 'a', fecha: local(10, 4), resultado: TipoResultadoVisita.rechazo),
          VisitaDeLaCasa(
            id: 'b',
            fecha: local(10, 3),
            resultado: TipoResultadoVisita.cobranza,
            persona: pedro,
          ),
          cobroHoy,
        ],
      );

      expect(find.text('04/10 · RECHAZO'), findsOneWidget);
      expect(find.text('✕'), findsOneWidget);
      expect(find.text(TextosHistorialDeLaCasa.rechazo), findsOneWidget);
      expect(find.text('03/10 · COBRANZA'), findsOneWidget);
      expect(find.text('${TextosHistorialDeLaCasa.pasadaACobrar} · Pedro'), findsOneWidget);
      expect(find.text(r'$'), findsNWidgets(2));
    });

    testWidgets(
      'dado una entrevista sin persona ni duración, dice «Sin nombre» y no inventa minutos',
      (tester) async {
        await montar(
          tester,
          eventos: [
            VisitaDeLaCasa(
              id: 'a',
              fecha: local(10, 4, 9, 5),
              resultado: TipoResultadoVisita.entrevista,
            ),
          ],
        );

        expect(find.text('04/10 · ENTREVISTA DADA'), findsOneWidget);
        expect(find.text(TextosHistorialDeLaCasa.sinNombre), findsOneWidget);
        expect(find.textContaining('MIN'), findsNothing);
      },
    );

    testWidgets('dado un cobro con tarjeta o transferencia, el título dice el medio', (
      tester,
    ) async {
      await montar(
        tester,
        eventos: [
          CobroDeLaCasa(
            id: 'a',
            fecha: local(10, 24),
            montoCentavos: 10000,
            medio: MedioCobranza.tarjeta,
            ventaId: 'v',
          ),
          CobroDeLaCasa(
            id: 'b',
            fecha: local(10, 23),
            montoCentavos: 20000,
            medio: MedioCobranza.transferencia,
            ventaId: 'v',
            persona: pedro,
          ),
        ],
      );

      expect(find.text('${monto(10000)} con tarjeta'), findsOneWidget);
      expect(find.text('${monto(20000)} por transferencia · Pedro'), findsOneWidget);
    });

    testWidgets(
      'dado una nota larga con saltos de línea, la fila la muestra en una línea cortada',
      (tester) async {
        final larga = 'Primera línea\nsegunda línea ${'muy larga ' * 40}';
        await montar(
          tester,
          eventos: [
            VisitaDeLaCasa(
              id: 'a',
              fecha: local(10, 4),
              resultado: TipoResultadoVisita.entrevista,
              nota: larga,
            ),
          ],
        );

        final texto = tester.widget<Text>(find.textContaining('✎ Primera línea segunda línea'));
        expect(texto.maxLines, 2);
        expect(texto.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('los filtros', () {
    testWidgets(
      'dado el historial, aparecen Todo, Entrevistas, Ventas y Cobros con «Todo» elegido',
      (tester) async {
        await montar(tester);

        for (final f in FiltroDeLaCasa.values) {
          expect(find.byKey(ClavesHistorialDeLaCasa.filtro(f)), findsOneWidget);
        }
        for (final r in ['Todo', 'Entrevistas', 'Ventas', 'Cobros']) {
          expect(find.text(r), findsOneWidget);
        }
        final handle = tester.ensureSemantics();
        expect(find.semantics.byLabel('Todo, elegido'), findsOneWidget);
        expect(find.semantics.byLabel('Ventas'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('dado que elijo cada filtro, quedan solo sus filas y «Todo» las devuelve', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.entrevistas)));
      await tester.pump();
      expect(filas(), findsOneWidget);
      expect(fila('vis-2'), findsOneWidget);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
      await tester.pump();
      expect(filas(), findsOneWidget);
      expect(fila('ven-1'), findsOneWidget);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await tester.pump();
      expect(filas(), findsOneWidget);
      expect(fila('cob-1'), findsOneWidget);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.todo)));
      await tester.pump();
      expect(filas(), findsNWidgets(4));
    });

    testWidgets(
      'dado el filtro Cobros, la visita de cobranza entra y la de venta sin su venta va en Ventas',
      (tester) async {
        await montar(
          tester,
          eventos: [
            VisitaDeLaCasa(id: 'c', fecha: local(10, 4), resultado: TipoResultadoVisita.cobranza),
            VisitaDeLaCasa(id: 'v', fecha: local(10, 3), resultado: TipoResultadoVisita.venta),
            noContestoDelTres,
          ],
        );

        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
        await tester.pump();
        expect(filas(), findsOneWidget);
        expect(fila('c'), findsOneWidget);

        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
        await tester.pump();
        expect(filas(), findsOneWidget);
        expect(fila('v'), findsOneWidget);
      },
    );

    testWidgets('dado un filtro sin resultados, lo dice y «Ver todo» vuelve a mostrar todo', (
      tester,
    ) async {
      await montar(tester, eventos: [noContestoDelTres]);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.entrevistas)));
      await tester.pump();

      expect(find.byKey(ClavesHistorialDeLaCasa.sinResultados), findsOneWidget);
      expect(find.text('No hay entrevistas en esta casa.'), findsOneWidget);
      expect(filas(), findsNothing);
      expect(find.byKey(ClavesHistorialDeLaCasa.filtros), findsOneWidget);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.verTodo));
      await tester.pump();

      expect(find.byKey(ClavesHistorialDeLaCasa.sinResultados), findsNothing);
      expect(filas(), findsOneWidget);
    });

    testWidgets('dado cada filtro vacío, el texto nombra lo que falta', (tester) async {
      await montar(tester, eventos: [noContestoDelTres]);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
      await tester.pump();
      expect(find.text('No hay ventas en esta casa.'), findsOneWidget);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await tester.pump();
      expect(find.text('No hay cobros en esta casa.'), findsOneWidget);
    });

    testWidgets('dado que toco el mismo filtro dos veces seguidas, no pasa nada raro', (
      tester,
    ) async {
      await montar(tester);
      final ventas = find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas));

      await tester.tap(ventas);
      await tester.tap(ventas);
      await tester.pump();

      expect(filas(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('estados', () {
    testWidgets(
      'dado que el historial todavía no llegó, muestra «Cargando el historial» y después las filas',
      (tester) async {
        final controlador = StreamController<List<EventoDeLaCasa>>();
        addTearDown(controlador.close);
        await montar(tester, fuente: HistorialFalso((_) => controlador.stream));

        expect(find.byKey(ClavesHistorialDeLaCasa.cargando), findsOneWidget);
        expect(find.byKey(ClavesHistorialDeLaCasa.filtros), findsNothing);
        final handle = tester.ensureSemantics();
        expect(find.semantics.byLabel(TextosHistorialDeLaCasa.cargando), findsOneWidget);
        handle.dispose();

        controlador.add(eventosC03);
        await asentar(tester);

        expect(find.byKey(ClavesHistorialDeLaCasa.cargando), findsNothing);
        expect(filas(), findsNWidgets(4));
      },
    );

    testWidgets('dado una casa sin nada, explica qué pasa y no ofrece filtros', (tester) async {
      await montar(tester, eventos: const []);

      expect(find.byKey(ClavesHistorialDeLaCasa.vacio), findsOneWidget);
      expect(find.text(TextosHistorialDeLaCasa.vacioTitulo), findsOneWidget);
      expect(find.text(TextosHistorialDeLaCasa.vacioAyuda), findsOneWidget);
      expect(find.byKey(ClavesHistorialDeLaCasa.filtros), findsNothing);
    });

    testWidgets('dado que la lectura falla, dice qué pasó y «Reintentar» lee de nuevo', (
      tester,
    ) async {
      var intento = 0;
      final f = await montar(
        tester,
        fuente: HistorialFalso((_) {
          intento++;
          return intento == 1 ? Stream.error(StateError('sin base')) : Stream.value(eventosC03);
        }),
      );

      expect(find.byKey(ClavesHistorialDeLaCasa.error), findsOneWidget);
      expect(find.text(TextosHistorialDeLaCasa.noPudimosLeer), findsOneWidget);
      expect(find.textContaining('sin base'), findsNothing);

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.reintentar));
      await asentar(tester);

      expect(f.espaciosLeidos, hasLength(2));
      expect(find.byKey(ClavesHistorialDeLaCasa.error), findsNothing);
      expect(filas(), findsNWidgets(4));
    });

    testWidgets(
      'dado que reintento y vuelve a fallar, el aviso sigue y se puede reintentar otra vez',
      (tester) async {
        final f = await montar(
          tester,
          fuente: HistorialFalso((_) => Stream.error(StateError('x'))),
        );

        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.reintentar));
        await asentar(tester);
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.reintentar));
        await asentar(tester);

        expect(f.espaciosLeidos, hasLength(3));
        expect(find.byKey(ClavesHistorialDeLaCasa.error), findsOneWidget);
      },
    );

    testWidgets(
      'dado que llega una visita nueva con la pestaña abierta, aparece arriba sin recargar',
      (tester) async {
        final controlador = StreamController<List<EventoDeLaCasa>>();
        addTearDown(controlador.close);
        await montar(tester, fuente: HistorialFalso((_) => controlador.stream));
        controlador.add([noContestoDelTres]);
        await asentar(tester);
        expect(filas(), findsOneWidget);

        controlador.add([cobroHoy, noContestoDelTres]);
        await asentar(tester);

        expect(filas(), findsNWidgets(2));
        expect(tester.getTopLeft(fila('cob-1')).dy, lessThan(tester.getTopLeft(fila('vis-1')).dy));
      },
    );

    testWidgets('dado que la lectura pide el espacio de la hoja, lee ESE espacio', (tester) async {
      final f = await montar(tester, espacio: 'esp-77');

      expect(f.espaciosLeidos, ['esp-77']);
    });
  });

  group('el detalle (C·04)', () {
    testWidgets(
      'dado que toco la venta, abre su detalle con lo vendido, lo pagado, el saldo y la nota',
      (tester) async {
        await montar(tester);

        await tester.tap(fila('ven-1'));
        await asentar(tester);

        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
        expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
        expect(find.text('Pedro Gómez · Grecia 3310'), findsOneWidget);
        // C·04: «Colección de 1 libro · $ 4.800» y «Libro · Salud y Hogar» (decisión del 10/11).
        expect(find.text('Colección de 1 libro'), findsOneWidget);
        expect(find.text(monto(480000)), findsOneWidget);
        expect(find.text(TextosHistorialDeLaCasa.libro), findsOneWidget);
        expect(find.text('Salud y Hogar'), findsWidgets);
        expect(find.text('Total'), findsNothing);
        expect(find.text('× 1'), findsNothing);
        expect(find.text(TextosHistorialDeLaCasa.pagado), findsOneWidget);
        expect(find.text(monto(360000)), findsOneWidget);
        expect(find.text(TextosHistorialDeLaCasa.saldo), findsOneWidget);
        expect(find.text(monto(120000)), findsOneWidget);
        expect(find.text(TextosHistorialDeLaCasa.notaDeLaVisita), findsOneWidget);
        expect(find.text('quiere Nuestros Hijos'), findsOneWidget);
        expect(find.byKey(ClavesDetalleDeVisita.cerrar), findsOneWidget);
        // Sin pantalla donde ver una venta, «Ver la venta» no se ofrece.
        expect(find.byKey(ClavesDetalleDeVisita.verLaVenta), findsNothing);
      },
    );

    testWidgets('dado que toco la entrevista, el detalle dice la duración y la nota entera', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(fila('vis-2'));
      await asentar(tester);

      expect(find.text('Entrevista dada · 05/10'), findsOneWidget);
      expect(find.text('Pedro Gómez · Grecia 3310'), findsOneWidget);
      expect(find.text(TextosHistorialDeLaCasa.duracion), findsOneWidget);
      expect(find.text('22 min'), findsOneWidget);
      expect(find.text('volver con la esposa'), findsOneWidget);
      expect(find.byKey(ClavesDetalleDeVisita.verLaVenta), findsNothing);
    });

    testWidgets(
      'dado que toco un «No contestó» sin nota, el detalle solo trae el título y «Cerrar»',
      (tester) async {
        await montar(tester);

        await tester.tap(fila('vis-1'));
        await asentar(tester);

        expect(find.text('No contestó · 03/10'), findsOneWidget);
        expect(find.text('Grecia 3310'), findsOneWidget);
        expect(find.byKey(ClavesDetalleDeVisita.nota), findsNothing);
        expect(find.byKey(ClavesDetalleDeVisita.datos), findsNothing);
        expect(find.byKey(ClavesDetalleDeVisita.cerrar), findsOneWidget);
      },
    );

    testWidgets('dado que toco «Cerrar», vuelve al historial como estaba', (tester) async {
      await montar(tester);
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
      await tester.pump();

      await tester.tap(fila('ven-1'));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesDetalleDeVisita.cerrar));
      await asentar(tester);

      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
      expect(filas(), findsOneWidget);
    });

    testWidgets('dado una venta sin renglones ni nota, el detalle muestra solo los montos', (
      tester,
    ) async {
      await montar(
        tester,
        eventos: [
          VentaDeLaCasa(
            id: 'ven-9',
            fecha: local(10, 1),
            numeroTalonario: '0009',
            montoCentavos: 0,
            pagadoCentavos: 0,
            lineas: const [],
          ),
        ],
      );

      await tester.tap(fila('ven-9'));
      await asentar(tester);

      expect(find.text('Venta 0009 · 01/10'), findsOneWidget);
      expect(find.text('Grecia 3310'), findsOneWidget);
      expect(find.byKey(ClavesDetalleDeVisita.nota), findsNothing);
      expect(
        find.descendant(of: find.byKey(ClavesDetalleDeVisita.datos), matching: find.text(monto(0))),
        findsNWidgets(3),
      );
    });

    testWidgets('dado una venta pagada de más, el saldo es cero', (tester) async {
      await montar(
        tester,
        eventos: [
          VentaDeLaCasa(
            id: 'ven-9',
            fecha: local(10, 1),
            numeroTalonario: '0009',
            montoCentavos: 100000,
            pagadoCentavos: 150000,
            lineas: const [],
          ),
        ],
      );

      await tester.tap(fila('ven-9'));
      await asentar(tester);

      expect(find.text(monto(150000)), findsOneWidget);
      expect(find.text(monto(0)), findsOneWidget);
    });
  });

  group('«Ver la venta»', () {
    testWidgets(
      'dado que hay a dónde llevar, el detalle de la venta la ofrece y la abre con su id, el espacio '
      'de la hoja y su cliente',
      (tester) async {
        final abiertas = <ContextoDeVentaDeLaCasa>[];
        await montar(
          tester,
          espacio: 'esp-9',
          verVenta: (venta) {
            abiertas.add(venta);
            return true;
          },
        );

        await tester.tap(fila('ven-1'));
        await asentar(tester);
        await tester.tap(find.byKey(ClavesDetalleDeVisita.verLaVenta));
        await asentar(tester);

        expect(abiertas, [(ventaId: 'ven-1', espacioId: 'esp-9', espacioPersonaId: 'ep-pedro')]);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
      },
    );

    testWidgets(
      'dado dos ventas con saldo en la casa, «Ver la venta» abre la que se tocó y no la otra',
      (tester) async {
        final ana = VentaDeLaCasa(
          id: 'ven-2',
          fecha: local(10, 20, 11),
          numeroTalonario: '0041',
          montoCentavos: 200000,
          pagadoCentavos: 50000,
          lineas: const [LineaDeFicha(nombre: 'El Deseado', cantidad: 1)],
          persona: const PersonaDelEvento(nombre: 'Ana'),
          espacioPersonaId: 'ep-ana',
        );
        final abiertas = <ContextoDeVentaDeLaCasa>[];
        await montar(
          tester,
          eventos: [ana, ventaDelDoce],
          verVenta: (venta) {
            abiertas.add(venta);
            return true;
          },
        );

        await tester.tap(fila('ven-2'));
        await asentar(tester);
        await tester.tap(find.byKey(ClavesDetalleDeVisita.verLaVenta));
        await asentar(tester);
        await tester.tap(fila('ven-1'));
        await asentar(tester);
        await tester.tap(find.byKey(ClavesDetalleDeVisita.verLaVenta));
        await asentar(tester);

        expect(abiertas, [
          (ventaId: 'ven-2', espacioId: 'esp-1', espacioPersonaId: 'ep-ana'),
          (ventaId: 'ven-1', espacioId: 'esp-1', espacioPersonaId: 'ep-pedro'),
        ]);
      },
    );

    testWidgets('dado que cierro el detalle con «Cerrar», no se abre la venta', (tester) async {
      final abiertas = <ContextoDeVentaDeLaCasa>[];
      await montar(
        tester,
        verVenta: (venta) {
          abiertas.add(venta);
          return true;
        },
      );

      await tester.tap(fila('ven-1'));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesDetalleDeVisita.cerrar));
      await asentar(tester);

      expect(abiertas, isEmpty);
    });

    testWidgets('dado que hay a dónde llevar, el detalle de una entrevista no lo ofrece', (
      tester,
    ) async {
      await montar(tester, verVenta: (_) => true);

      await tester.tap(fila('vis-2'));
      await asentar(tester);

      expect(find.byKey(ClavesDetalleDeVisita.verLaVenta), findsNothing);
    });

    testWidgets('dado un doble toque en «Ver la venta», se abre una sola vez', (tester) async {
      final abiertas = <String>[];
      final lenta = Completer<Object?>();
      await montar(
        tester,
        verVenta: (venta) {
          abiertas.add(venta.ventaId);
          return lenta.future;
        },
      );
      await tester.tap(fila('ven-1'));
      await asentar(tester);

      final handle = tester.ensureSemantics();
      final boton = find.semantics.byLabel(TextosHistorialDeLaCasa.verLaVenta);
      tester.semantics.performAction(boton, SemanticsAction.tap);
      tester.semantics.performAction(boton, SemanticsAction.tap);
      await asentar(tester);

      expect(abiertas, ['ven-1']);
      handle.dispose();
      lenta.complete(true);
      await asentar(tester);
    });

    testWidgets(
      'dado que abrir la venta falla, el aviso dice qué pasó y la fila se puede tocar de nuevo',
      (tester) async {
        var intentos = 0;
        await montar(
          tester,
          verVenta: (_) {
            intentos++;
            if (intentos == 1) throw StateError('sin sesión');
            return true;
          },
        );

        await tester.tap(fila('ven-1'));
        await asentar(tester);
        await tester.tap(find.byKey(ClavesDetalleDeVisita.verLaVenta));
        await asentar(tester);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsOneWidget);
        expect(find.text(TextosHistorialDeLaCasa.noPudimosAbrirLaVenta), findsOneWidget);
        expect(find.text(TextosHistorialDeLaCasa.noPudimosAbrirElCobro), findsNothing);
        expect(find.textContaining('sin sesión'), findsNothing);

        await tester.tap(fila('ven-1'));
        await asentar(tester);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
        await tester.tap(find.byKey(ClavesDetalleDeVisita.verLaVenta));
        await asentar(tester);

        expect(intentos, 2);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
      },
    );
  });

  group('un cobro abre su detalle (casilla de #168, decisión de Cristian 30/10)', () {
    testWidgets(
      'dado que hay detalle del cobro, tocar la fila lo abre con el id del cobro y no abre la hoja de visita',
      (tester) async {
        final abiertos = <String>[];
        await montar(
          tester,
          verCobro: (id) {
            abiertos.add(id);
            return true;
          },
        );

        await tester.tap(fila('cob-1'));
        await asentar(tester);

        expect(abiertos, ['cob-1']);
        expect(hojas.abiertas, 0);
        expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
      },
    );

    testWidgets('dado que todavía no hay detalle del cobro, la fila no se toca ni lleva «›»', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(fila('cob-1'));
      await asentar(tester);

      expect(hojas.abiertas, 0);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(fila('cob-1')).getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('dado un doble toque en el cobro, el detalle se abre una sola vez', (tester) async {
      final abiertos = <String>[];
      final lento = Completer<Object?>();
      await montar(
        tester,
        verCobro: (id) {
          abiertos.add(id);
          return lento.future;
        },
      );

      final handle = tester.ensureSemantics();
      final etiqueta = FormatoHistorialDeLaCasa.paraLector(cobroHoy, ahora);
      tester.semantics.performAction(find.semantics.byLabel(etiqueta), SemanticsAction.tap);
      tester.semantics.performAction(find.semantics.byLabel(etiqueta), SemanticsAction.tap);
      await asentar(tester);

      expect(abiertos, ['cob-1']);
      handle.dispose();
      lento.complete(true);
      await asentar(tester);
    });

    testWidgets(
      'dado un segundo toque en otra fila mientras el cobro se abre, no se abre nada más; al volver, sí',
      (tester) async {
        final lento = Completer<Object?>();
        await montar(tester, verCobro: (_) => lento.future);
        final handle = tester.ensureSemantics();
        final cobro = FormatoHistorialDeLaCasa.paraLector(cobroHoy, ahora);
        final venta = FormatoHistorialDeLaCasa.paraLector(ventaDelDoce, ahora);

        tester.semantics.performAction(find.semantics.byLabel(cobro), SemanticsAction.tap);
        await tester.pump();
        tester.semantics.performAction(find.semantics.byLabel(venta), SemanticsAction.tap);
        await asentar(tester);
        expect(hojas.abiertas, 0);

        lento.complete(true);
        await asentar(tester);
        tester.semantics.performAction(find.semantics.byLabel(venta), SemanticsAction.tap);
        await asentar(tester);

        expect(hojas.abiertas, 1);
        handle.dispose();
      },
    );

    testWidgets('dado que abrir el cobro falla, avisa qué pasó y la fila no queda trabada', (
      tester,
    ) async {
      var intentos = 0;
      await montar(
        tester,
        verCobro: (_) {
          intentos++;
          if (intentos == 1) throw StateError('x');
          return true;
        },
      );

      await tester.tap(fila('cob-1'));
      await asentar(tester);
      expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsOneWidget);
      expect(find.text(TextosHistorialDeLaCasa.noPudimosAbrirElCobro), findsOneWidget);

      await tester.tap(fila('cob-1'));
      await asentar(tester);

      expect(intentos, 2);
      expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
    });

    testWidgets(
      'dado que el detalle del cobro devuelve false (sin contexto), no hay aviso ni se traba',
      (tester) async {
        var intentos = 0;
        await montar(
          tester,
          verCobro: (_) {
            intentos++;
            return false;
          },
        );

        await tester.tap(fila('cob-1'));
        await asentar(tester);
        await tester.tap(fila('cob-1'));
        await asentar(tester);

        expect(intentos, 2);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
      },
    );
  });

  group('doble toque y acciones seguidas en una visita', () {
    testWidgets('dado un doble toque en la fila, se abre un solo detalle', (tester) async {
      await montar(tester);
      final handle = tester.ensureSemantics();
      final etiqueta = FormatoHistorialDeLaCasa.paraLector(ventaDelDoce, ahora);

      tester.semantics.performAction(find.semantics.byLabel(etiqueta), SemanticsAction.tap);
      tester.semantics.performAction(find.semantics.byLabel(etiqueta), SemanticsAction.tap);
      await asentar(tester);

      expect(hojas.abiertas, 1);
      handle.dispose();
    });

    testWidgets('dado dos filas tocadas seguidas, se abre solo la primera', (tester) async {
      await montar(tester);
      final handle = tester.ensureSemantics();
      final venta = FormatoHistorialDeLaCasa.paraLector(ventaDelDoce, ahora);
      final entrevista = FormatoHistorialDeLaCasa.paraLector(entrevistaDelCinco, ahora);

      tester.semantics.performAction(find.semantics.byLabel(venta), SemanticsAction.tap);
      tester.semantics.performAction(find.semantics.byLabel(entrevista), SemanticsAction.tap);
      await asentar(tester);

      expect(hojas.abiertas, 1);
      expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
      expect(find.text('Entrevista dada · 05/10'), findsNothing);
      handle.dispose();
    });

    testWidgets('dado que abro, cierro y abro otra fila, cada detalle trae sus datos', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(fila('ven-1'));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesDetalleDeVisita.cerrar));
      await asentar(tester);
      await tester.tap(fila('vis-2'));
      await asentar(tester);

      expect(hojas.abiertas, 2);
      expect(find.text('Entrevista dada · 05/10'), findsOneWidget);
      expect(find.text('Venta 0038 · 12/10'), findsNothing);
    });

    testWidgets(
      'dado un doble toque en «Cerrar», el detalle se cierra una vez y la pestaña sigue',
      (tester) async {
        await montar(tester);
        await tester.tap(fila('ven-1'));
        await asentar(tester);
        final handle = tester.ensureSemantics();
        final cerrar = find.semantics.byLabel(TextosHistorialDeLaCasa.cerrar);

        tester.semantics.performAction(cerrar, SemanticsAction.tap);
        tester.semantics.performAction(cerrar, SemanticsAction.tap);
        await asentar(tester);

        expect(find.byKey(ClavesHistorialDeLaCasa.pestana), findsOneWidget);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );

    testWidgets(
      'dado que el evento desaparece de la lista con el detalle abierto, el detalle sigue sin romperse',
      (tester) async {
        final controlador = StreamController<List<EventoDeLaCasa>>();
        addTearDown(controlador.close);
        await montar(tester, fuente: HistorialFalso((_) => controlador.stream));
        controlador.add(eventosC03);
        await asentar(tester);
        await tester.tap(fila('ven-1'));
        await asentar(tester);

        controlador.add([noContestoDelTres]);
        await asentar(tester);

        expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ClavesDetalleDeVisita.cerrar));
        await asentar(tester);
        expect(filas(), findsOneWidget);
      },
    );
  });

  group('volver atrás y reentrar', () {
    testWidgets('dado que salgo de la pestaña y vuelvo, arranca en «Todo» con todo el historial', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
      await tester.pump();
      expect(filas(), findsOneWidget);

      // Reentrar: la hoja arma la pestaña de nuevo (otra pestaña de por medio).
      await tester.pumpWidget(const SizedBox());
      await montar(tester);

      expect(filas(), findsNWidgets(4));
    });

    testWidgets('dado que reentro con el detalle ya cerrado, el guardia no queda activo', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(fila('ven-1'));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesDetalleDeVisita.cerrar));
      await asentar(tester);

      await tester.tap(fila('ven-1'));
      await asentar(tester);

      expect(hojas.abiertas, 2);
    });
  });

  group('datos límite', () {
    List<EventoDeLaCasa> muchos(int n) => [
      for (var i = 0; i < n; i++)
        VisitaDeLaCasa(
          id: 'v-${i.toString().padLeft(3, '0')}',
          fecha: DateTime(2026, 9, 1).add(Duration(hours: n - i)).toUtc(),
          resultado: i.isEven ? TipoResultadoVisita.noContesto : TipoResultadoVisita.rechazo,
        ),
    ];

    testWidgets('dado una lista larga, dibuja una página y «Ver más» suma otra hasta el final', (
      tester,
    ) async {
      await montar(tester, eventos: muchos(75), tamano: const Size(412, 4000));
      expect(filas(), findsNWidgets(PestanaHistorialDeLaCasa.pagina));
      expect(find.text('Ver más (45)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.verMas));
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.verMas));
      await tester.pump();
      expect(filas(), findsNWidgets(60));
      expect(find.text('Ver más (15)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.verMas));
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.verMas));
      await tester.pump();
      expect(filas(), findsNWidgets(75));
      expect(find.byKey(ClavesHistorialDeLaCasa.verMas), findsNothing);
    });

    testWidgets('dado que cambio de filtro después de «Ver más», vuelve a la primera página', (
      tester,
    ) async {
      await montar(tester, eventos: muchos(75), tamano: const Size(412, 4000));
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.verMas));
      await tester.pump();
      expect(filas(), findsNWidgets(60));

      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.todo)));
      await tester.pump();
      expect(filas(), findsNWidgets(60));
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await tester.pump();
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.todo)));
      await tester.pump();

      expect(filas(), findsNWidgets(PestanaHistorialDeLaCasa.pagina));
    });

    testWidgets('dado exactamente una página, no ofrece «Ver más»', (tester) async {
      await montar(
        tester,
        eventos: muchos(PestanaHistorialDeLaCasa.pagina),
        tamano: const Size(412, 4000),
      );

      expect(filas(), findsNWidgets(PestanaHistorialDeLaCasa.pagina));
      expect(find.byKey(ClavesHistorialDeLaCasa.verMas), findsNothing);
    });

    testWidgets(
      'dado nombres y notas larguísimos con letra al 200 % en 320 × 568, no desborda ni corta el detalle',
      (tester) async {
        final nombre = 'Maximiliano ${'Fernández ' * 6}';
        final nota = 'Pidió que volvamos ${'después de las dieciocho horas ' * 12}';
        final largo = PersonaDelEvento(nombre: nombre, apellido: 'de la Rosa y Márquez');
        await montar(
          tester,
          escala: 2,
          tamano: const Size(320, 568),
          eventos: [
            VisitaDeLaCasa(
              id: 'a',
              fecha: local(10, 4),
              resultado: TipoResultadoVisita.entrevista,
              persona: largo,
              nota: nota,
              duracion: const Duration(hours: 11, minutes: 59),
            ),
            VentaDeLaCasa(
              id: 'b',
              fecha: local(10, 3),
              numeroTalonario: '0123',
              montoCentavos: 123456789,
              pagadoCentavos: 1,
              lineas: [
                for (var i = 0; i < 6; i++)
                  LineaDeFicha(nombre: 'Colección de libros número ${i + 1} del año', cantidad: 3),
              ],
              persona: largo,
              nota: nota,
            ),
            cobroHoy,
          ],
        );

        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(fila('b'));
        await tester.tap(fila('b'));
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(ClavesDetalleDeVisita.cerrar),
          200,
          scrollable: find.descendant(
            of: find.byKey(ClavesDetalleDeVisita.hoja),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.byKey(ClavesDetalleDeVisita.cerrar), findsOneWidget);
        expect(find.text(nota), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado la letra al 200 %, los cuatro filtros se reparten en renglones y cada uno se puede tocar',
      (tester) async {
        await montar(tester, escala: 2, tamano: const Size(320, 568));

        for (final f in FiltroDeLaCasa.values) {
          final opcion = find.byKey(ClavesHistorialDeLaCasa.filtro(f));
          expect(tester.getSize(opcion).height, greaterThanOrEqualTo(40));
          await tester.ensureVisible(opcion);
          await tester.tap(opcion);
          await tester.pump();
        }
        await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.todo)));
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.todo)));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(filas(), findsNWidgets(4));
      },
    );

    testWidgets('dado el texto al 130 % y al 200 % en un teléfono chico, ninguna fila desborda', (
      tester,
    ) async {
      for (final escala in [1.3, 2.0]) {
        await montar(tester, escala: escala, tamano: const Size(320, 568), clave: ValueKey(escala));
        expect(tester.takeException(), isNull, reason: 'escala $escala');
      }
    });
  });

  group('accesibilidad', () {
    testWidgets(
      'dado cada fila, el lector dice la línea chica, el título y la de abajo, y se anuncia como botón',
      (tester) async {
        await montar(tester);
        final handle = tester.ensureSemantics();

        final etiqueta = FormatoHistorialDeLaCasa.paraLector(ventaDelDoce, ahora);

        expect(etiqueta, contains('12/10 · VENTA 0038'));
        expect(etiqueta, contains('Salud y Hogar · Pedro'));
        expect(etiqueta, contains('✎ quiere Nuestros Hijos'));
        final nodo = tester.getSemantics(fila('ven-1')).getSemanticsData();
        expect(nodo.label, etiqueta);
        expect(nodo.hasAction(SemanticsAction.tap), isTrue);
        handle.dispose();
      },
    );

    testWidgets('dado cada fila tocable, mide al menos 48 dp de alto para el dedo', (tester) async {
      await montar(tester);

      for (final id in ['ven-1', 'vis-2', 'vis-1']) {
        expect(tester.getSize(fila(id)).height, greaterThanOrEqualTo(48));
      }
    });
  });
}
