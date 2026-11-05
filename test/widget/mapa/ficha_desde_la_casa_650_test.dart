// Vista 39 C·02 «Hoja arriba · Personas» → vista 32 B «Ficha de la persona» (HU-UBI-009, #650): tocar a
// una persona de la hoja de la casa abre su ficha por el flujo real (`FlujoFichaDesdeLaCasa`, el mismo
// que enchufa `main.dart`), con la persona, el espacio y el nombre que la fila ya tiene; volver deja la
// hoja como estaba. Casos límite: doble toque, falla a mitad (sin sesión), volver y reentrar, y datos
// límite (muchas personas, nombre largo, texto al 200 %).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_ficha_desde_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import 'ficha_persona_arnes.dart';

/// Cuenta las pantallas que se empujan y se sacan del navegador.
final class _Observador extends NavigatorObserver {
  var empujadas = 0;
  var sacadas = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) empujadas++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) sacadas++;
  }
}

Finder get _filas => find.byKey(ClavesHojaCasa.abrirPersona);
Finder get _ficha => find.byType(FichaPersonaPage);
Finder get _hoja => find.byType(HojaCasa);

FichaPersonaPage _laFicha(WidgetTester tester) => tester.widget<FichaPersonaPage>(_ficha);

PersonaDelEspacio _maria({String nombre = 'María', String apellido = 'Pérez'}) =>
    clienteDePersonas('per-1', nombre, apellido: apellido);

/// Lo que un test necesita después de montar la hoja.
final class _Montaje {
  _Montaje(this.mundo);

  final MundoFicha mundo;
  final observador = _Observador();
}

/// La hoja de la casa con el flujo REAL de la ficha enganchado (como en `main.dart`) y la ficha con sus
/// dobles de `ficha_persona_arnes.dart`.
Future<_Montaje> _montar(
  WidgetTester tester, {
  List<PersonaDelEspacio>? personas,
  MundoFicha? mundo,
  bool conFicha = true,
  String? colportorId = 'col-1',
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final m = _Montaje(mundo ?? MundoFicha());
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navegador = GlobalKey<NavigatorState>();
  var contador = 0;
  final overrides = <Override>[
    ...overridesHojaCasa(
      lectura: (_) =>
          Stream.value(ContextoDeLaCasa(espacioId: 'esp-1', personas: personas ?? [_maria()])),
    ),
    fichaDePersonaDesdeLaCasaProvider.overrideWithValue(
      conFicha
          ? (datos) => FlujoFichaDesdeLaCasa.abrir(
              navegador.currentContext!,
              datos,
              colportorId: colportorId,
            )
          : null,
    ),
    fichaPersonaRepositoryProvider.overrideWithValue(m.mundo.fichas),
    notaPersonaRepositoryProvider.overrideWithValue(m.mundo.notas),
    espacioRepositoryProvider.overrideWithValue(m.mundo.espacios),
    cuentasDePersonasProvider.overrideWithValue(m.mundo.cuentas),
    movimientosDeCuentaProvider.overrideWithValue(m.mundo.movimientos),
    marcadorDeTelefonoProvider.overrideWithValue(m.mundo.marcador),
    personaRepositoryProvider.overrideWithValue(m.mundo.personas),
    relojPersonaProvider.overrideWithValue(() => ahoraFicha),
    generadorIdPersonaProvider.overrideWithValue(() => 'nota-nueva-${++contador}'),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        navigatorKey: navegador,
        navigatorObservers: [m.observador],
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: colportorId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return m;
}

void main() {
  group('C·02 → 32B · tocar una persona abre su ficha', () {
    testWidgets('la fila de María lleva «›» y al tocarla se abre SU ficha con su espacio', (
      tester,
    ) async {
      final m = await _montar(tester);
      expect(_filas, findsOneWidget);
      expect(find.text('›'), findsOneWidget);
      expect(_ficha, findsNothing);

      await tester.tap(_filas);
      await asentar(tester);

      expect(_ficha, findsOneWidget);
      final pagina = _laFicha(tester);
      expect(pagina.personaId, 'per-1');
      expect(pagina.espacioId, 'esp-1');
      expect(pagina.colportorId, 'col-1');
      expect(pagina.nombre, 'María');
      // Se lee del teléfono: la ficha muestra a la persona.
      expect(find.text('María Pérez'), findsWidgets);
      expect(m.observador.empujadas, greaterThanOrEqualTo(2));
    });

    testWidgets('mientras la ficha no esté enganchada la fila no se toca y no lleva «›»', (
      tester,
    ) async {
      await _montar(tester, conFicha: false);

      expect(_filas, findsNothing);
      expect(find.text('›'), findsNothing);
      expect(find.text('María Pérez'), findsOneWidget);
    });

    testWidgets('al volver con «Volver» la hoja sigue abierta en la pestaña Personas', (
      tester,
    ) async {
      await _montar(tester);
      await tester.tap(_filas);
      await asentar(tester);
      expect(_ficha, findsOneWidget);

      await volverAtras(tester);

      expect(_ficha, findsNothing);
      expect(_hoja, findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.listaDePersonas), findsOneWidget);
      expect(_filas, findsOneWidget);
    });

    testWidgets('«atrás» del sistema también vuelve a la hoja', (tester) async {
      await _montar(tester);
      await tester.tap(_filas);
      await asentar(tester);

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(_ficha, findsNothing);
      expect(find.byKey(ClavesHojaCasa.listaDePersonas), findsOneWidget);
    });

    testWidgets('volver y reentrar: la misma fila abre la ficha otra vez', (tester) async {
      final m = await _montar(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(_filas);
        await asentar(tester);
        expect(_ficha, findsOneWidget, reason: 'vuelta ${i + 1}');
        await volverAtras(tester);
        expect(_ficha, findsNothing);
      }

      expect(m.observador.sacadas, 3);
    });

    testWidgets('doble toque: mientras la ficha está abierta no se apila otra', (tester) async {
      final semantica = tester.ensureSemantics();
      final m = await _montar(tester);
      final antes = m.observador.empujadas;

      final fila = find.semantics.byLabel(RegExp('María Pérez'));
      tester.semantics.performAction(fila, SemanticsAction.tap);
      tester.semantics.performAction(fila, SemanticsAction.tap);
      await asentar(tester);

      expect(find.byType(FichaPersonaPage), findsOneWidget);
      expect(m.observador.empujadas - antes, 1);
      semantica.dispose();
    });

    testWidgets('sin sesión: avisa que no pudo abrir y la fila vuelve a poder tocarse', (
      tester,
    ) async {
      await _montar(tester, colportorId: null);

      await tester.tap(_filas);
      await asentar(tester);

      expect(_ficha, findsNothing);
      expect(find.text('No pudimos abrir la ficha. Probá de nuevo.'), findsOneWidget);

      await tester.tap(_filas);
      await asentar(tester);
      expect(_ficha, findsNothing);
      expect(find.text('No pudimos abrir la ficha. Probá de nuevo.'), findsOneWidget);
    });
  });

  group('32B · lo que dice la ficha con el nombre que la fila pasó', () {
    testWidgets('32B·07 error al leer: «No pudimos leer los datos de María en tu teléfono.»', (
      tester,
    ) async {
      final mundo = MundoFicha();
      mundo.fichas.errorAlObservar = StateError('no se pudo leer');
      await _montar(tester, mundo: mundo);

      await tester.tap(_filas);
      await asentar(tester);

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(
        find.text('No pudimos leer los datos de María en tu teléfono.'),
        findsOneWidget,
        reason: 'el texto del canvas lleva el nombre de la fila',
      );
    });

    testWidgets('32B·06 cargando: «Cargando la ficha de María»', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, mundo: MundoFicha(cargando: true));

      await tester.tap(_filas);
      await asentar(tester);

      expect(find.byKey(ClavesFicha.cargando), findsOneWidget);
      expect(find.bySemanticsLabel(TextosFicha.cargando('María')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('una persona sin nombre de pila abre la ficha y el error dice «la persona»', (
      tester,
    ) async {
      final mundo = MundoFicha();
      mundo.fichas.errorAlObservar = StateError('no se pudo leer');
      await _montar(
        tester,
        mundo: mundo,
        personas: [_maria(nombre: '  ', apellido: 'Pérez')],
      );

      await tester.tap(_filas);
      await asentar(tester);

      expect(_laFicha(tester).nombre, isNull);
      expect(find.text(TextosFicha.noPudimosLeer(null)), findsOneWidget);
    });
  });

  group('Datos límite', () {
    testWidgets(
      'veinte personas: tocar la última abre SU ficha y al volver el desplazamiento sigue',
      (tester) async {
        final personas = [
          for (var i = 1; i <= 20; i++)
            clienteDePersonas(i == 20 ? 'per-1' : 'p-$i', i == 20 ? 'María' : 'Persona $i'),
        ];
        await _montar(tester, personas: personas, tamano: const Size(390, 700));
        final ultima = find.byKey(const ValueKey('fila_persona_per-1'));
        await tester.scrollUntilVisible(ultima, 200, scrollable: find.byType(Scrollable).first);
        final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
        final antes = scrollable.position.pixels;
        expect(antes, greaterThan(0));

        await tester.tap(find.descendant(of: ultima, matching: _filas));
        await asentar(tester);
        expect(_laFicha(tester).personaId, 'per-1');
        await volverAtras(tester);

        final despues = tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(despues.position.pixels, antes, reason: 'la hoja queda donde estaba');
        expect(ultima, findsOneWidget);
      },
    );

    testWidgets('nombre largo con el texto al 200 %: la ficha se abre sin desbordar', (
      tester,
    ) async {
      final mundo = MundoFicha(cargando: true);
      await _montar(
        tester,
        mundo: mundo,
        escala: 2,
        tamano: const Size(320, 640),
        personas: [_maria(nombre: 'María de los Ángeles del Carmen', apellido: 'Fernández Ortiz')],
      );

      await tester.ensureVisible(_filas);
      await tester.tap(_filas);
      await asentar(tester);

      expect(_ficha, findsOneWidget);
      expect(find.byKey(ClavesFicha.cargando), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
