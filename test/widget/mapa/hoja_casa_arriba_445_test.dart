// Vista 39 (base), artboard C·02 «Hoja arriba · Personas» (HU-UBI-003, #445) y los estados que la
// acompañan (E·01 a E·05 con la hoja subida): un test por artboard, por texto literal del canvas y por
// caso límite (doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, datos límite y
// texto al 200 y 300 %).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart' show asentar, contextoActivo;

const _nbsp = ' ';

final _ana = clienteDePersonas('p-ana', 'Ana', apellido: 'Gómez');

/// El contexto del canvas C·02: Pedro Gómez debe $ 1.200 y Ana Gómez dio una entrevista el 05/10.
final _contextoC02 = ContextoDeLaCasa(
  espacioId: 'esp-1',
  personas: [pedroGomez, _ana],
  saldosCentavos: const {'p-pedro': 120000},
  ultimaEntrevistaDe: {'p-ana': DateTime(2026, 10, 5, 12)},
  nota: notaDelCanvas,
);

ContextoDeLaCasa _contextoCon(List<PersonaDelEspacio> filas, {bool nota = false}) =>
    ContextoDeLaCasa(espacioId: 'esp-1', personas: filas, nota: nota ? notaDelCanvas : null);

/// Lo que un test necesita después de montar la hoja.
final class _Montaje {
  final cierres = <int>[];
  final visitas = <ContextoDeVisita>[];
  final cobros = <ContextoDeCobro>[];
  final fichas = <ContextoDeFicha>[];
  final repo = PersonaRepositorioFalso();
  final lecturas = <ClaveDeLaCasa>[];
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  ContextoDeLaCasa? contexto,
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lectura,
  ItemListaUbicacion? item,
  bool arriba = true,
  String? colportorId = 'col-1',
  bool conFicha = true,
  FutureOr<void> Function(ContextoDeFicha, _Montaje)? ficha,
  FutureOr<void> Function(ContextoDeCobro, _Montaje)? cobrar,
  bool conHistorial = false,
  bool conNotas = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  _Montaje? montaje,
}) async {
  final m = montaje ?? _Montaje();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final casa = item ?? itemDeLaHoja();
  final overrides = <Override>[
    ...overridesHojaCasa(
      lectura: lectura ?? (_) => Stream.value(contexto ?? _contextoC02),
      lecturas: m.lecturas,
      registrarVisita: (c) => m.visitas.add(c),
      cobrar: (c) async {
        m.cobros.add(c);
        if (cobrar != null) await cobrar(c, m);
      },
    ),
    personaRepositoryProvider.overrideWithValue(m.repo),
    espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(contextoActivo())),
    fichaDePersonaDesdeLaCasaProvider.overrideWithValue(
      conFicha
          ? (c) async {
              m.fichas.add(c);
              if (ficha != null) await ficha(c, m);
              return null;
            }
          : null,
    ),
    pestanaHistorialDeLaCasaProvider.overrideWithValue(
      conHistorial
          ? (context, datos) => Text('Historial de ${datos.espacioId}', key: const Key('hist'))
          : null,
    ),
    pestanaNotasDeLaCasaProvider.overrideWithValue(
      conNotas ? (context, datos) => const Text('Notas del lugar', key: Key('notas_tab')) : null,
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: casa,
              ahora: ahoraLista,
              alCerrar: () => m.cierres.add(m.cierres.length),
              arriba: arriba,
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

Finder get _pestanas => find.byKey(ClavesHojaCasa.pestanas);
Finder _pestana(String id) => find.byKey(ClavesHojaCasa.pestana(id));
Finder get _filas => find.byType(FilaPersonaDeLaCasa);
Finder get _abrirPersona => find.byKey(ClavesHojaCasa.abrirPersona);
Finder get _cobrar => find.byKey(ClavesHojaCasa.cobrar);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _agregar => find.byKey(ClavesHojaCasa.agregarPersona);
Finder get _sinPersonas => find.byKey(ClavesHojaCasa.sinPersonas);
Finder get _guardada => find.byKey(ClavesHojaCasa.personaGuardada);
Finder get _nota => find.byKey(ClavesHojaCasa.nota);
Finder get _avisoLejos => find.byKey(ClavesEstadosHojaCasa.avisoLejos);
Finder get _avisoBaja => find.byKey(ClavesEstadosHojaCasa.avisoDadaDeBaja);
Finder get _avisoError => find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeer);
Finder get _cargando => find.byKey(ClavesEstadosHojaCasa.cargando);
Finder get _cerrarAlta => find.byTooltip('Cerrar');

bool _seleccionada(WidgetTester tester, String id) {
  // ignore: deprecated_member_use
  return tester.getSemantics(_pestana(id)).hasFlag(SemanticsFlag.isSelected);
}

Future<void> _escribirNombre(WidgetTester tester, String nombre) async {
  await tester.enterText(
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
    nombre,
  );
  await tester.pump();
}

Future<void> _guardarAlta(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
  await asentar(tester);
}

void main() {
  group('C·02 · Hoja arriba · Personas', () {
    testWidgets(
      'dado el canvas, muestra «Registrar visita», las tres pestañas con Personas elegida y '
      'las dos personas',
      (tester) async {
        await _montar(tester, conHistorial: true, conNotas: true);

        expect(find.text('Grecia 3310'), findsOneWidget);
        expect(_registrar, findsOneWidget);
        expect(find.text('✓  Registrar visita'), findsOneWidget);
        expect(find.text('Personas'), findsOneWidget);
        expect(find.text('Historial'), findsOneWidget);
        expect(find.text('Notas'), findsOneWidget);
        expect(_seleccionada(tester, 'personas'), isTrue);
        expect(_seleccionada(tester, 'historial'), isFalse);
        expect(_seleccionada(tester, 'notas'), isFalse);
        expect(_filas, findsNWidgets(2));
        expect(find.text('Pedro Gómez'), findsOneWidget);
        expect(find.text('Ana Gómez'), findsOneWidget);
        expect(find.text('+ Agregar persona'), findsOneWidget);
      },
    );

    testWidgets(
      'Pedro: «Debe \$${_nbsp}1.200» y «\$ Cobrar»; Ana: «Entrevista dada el 05/10» y «›»',
      (tester) async {
        await _montar(tester);

        expect(find.text('Debe \$${_nbsp}1.200'), findsOneWidget);
        expect(_cobrar, findsOneWidget);
        expect(find.text('Entrevista dada el 05/10'), findsOneWidget);
        expect(
          find.text('›'),
          findsOneWidget,
          reason: 'solo la fila sin «\$ Cobrar» lleva la flecha',
        );
        expect(_abrirPersona, findsNWidgets(2));
      },
    );

    testWidgets('una persona que no debe ni tuvo entrevista queda con el nombre solo, sin inventar '
        'nada', (tester) async {
      await _montar(tester, contexto: _contextoCon([_ana]));

      expect(find.text('Ana Gómez'), findsOneWidget);
      expect(find.textContaining('Entrevista'), findsNothing);
      expect(find.textContaining('Debe'), findsNothing);
    });

    testWidgets('sin pestañas de Historial y Notas enganchadas se ofrece solo Personas', (
      tester,
    ) async {
      await _montar(tester);

      expect(_pestana('personas'), findsOneWidget);
      expect(_pestana('historial'), findsNothing);
      expect(_pestana('notas'), findsNothing);
    });

    testWidgets('tocar una pestaña cambia el contenido y se puede volver a Personas', (
      tester,
    ) async {
      await _montar(tester, conHistorial: true, conNotas: true);

      await tester.tap(_pestana('historial'));
      await tester.pump();
      expect(find.byKey(const Key('hist')), findsOneWidget);
      expect(find.text('Historial de esp-1'), findsOneWidget);
      expect(_filas, findsNothing);
      expect(_seleccionada(tester, 'historial'), isTrue);

      await tester.tap(_pestana('notas'));
      await tester.pump();
      expect(find.byKey(const Key('notas_tab')), findsOneWidget);
      expect(find.byKey(const Key('hist')), findsNothing);

      await tester.tap(_pestana('personas'));
      await tester.pump();
      expect(_filas, findsNWidgets(2));
      expect(find.byKey(const Key('notas_tab')), findsNothing);
    });

    testWidgets('hasta que llegue la pestaña Notas, la nota del lugar sigue a la vista', (
      tester,
    ) async {
      await _montar(tester);
      expect(_nota, findsOneWidget);
      expect(find.text('Perro suelto: tocar timbre y esperar.'), findsOneWidget);
    });

    testWidgets('con la pestaña Notas enganchada la nota ya no se repite debajo', (tester) async {
      await _montar(tester, conNotas: true);
      expect(_nota, findsNothing);
    });

    testWidgets('con la hoja a la altura del resumen se ve el resumen y no las pestañas (C·01)', (
      tester,
    ) async {
      await _montar(tester, arriba: false);

      expect(_pestanas, findsNothing);
      expect(_agregar, findsNothing);
      expect(_filas, findsOneWidget, reason: 'el resumen muestra la persona destacada');
    });

    testWidgets('un edificio sin depto elegido no tiene espacio ni personas: sigue el resumen', (
      tester,
    ) async {
      await _montar(tester, contexto: const ContextoDeLaCasa(espacioId: null, personas: []));

      expect(_pestanas, findsNothing);
      expect(_agregar, findsNothing);
    });
  });

  group('C·02 · tocar una persona abre su ficha (vista 32 B)', () {
    testWidgets('al tocar a Ana se abre su ficha con su persona y el espacio', (tester) async {
      final m = await _montar(tester);

      await tester.tap(_abrirPersona.last);
      await tester.pump();
      await tester.pump();

      expect(m.fichas, [(personaId: 'p-ana', espacioId: 'esp-1')]);
    });

    testWidgets('mientras la ficha no esté enganchada la fila no se toca y no lleva «›»', (
      tester,
    ) async {
      await _montar(tester, conFicha: false);

      expect(_abrirPersona, findsNothing);
      expect(find.text('›'), findsNothing);
      expect(find.text('Ana Gómez'), findsOneWidget);
    });

    testWidgets('falla a mitad: avisa que no se pudo abrir y la fila se puede volver a tocar', (
      tester,
    ) async {
      var intentos = 0;
      final m = await _montar(
        tester,
        ficha: (_, _) {
          intentos++;
          if (intentos == 1) throw StateError('no abrió');
        },
      );

      await tester.tap(_abrirPersona.last);
      await tester.pump();
      await tester.pump();

      expect(find.text('No pudimos abrir la ficha. Probá de nuevo.'), findsOneWidget);

      await tester.tap(_abrirPersona.last);
      await tester.pump();
      await tester.pump();

      expect(m.fichas, hasLength(2));
      expect(find.text('No pudimos abrir la ficha. Probá de nuevo.'), findsNothing);
    });

    testWidgets('doble toque: mientras abre la ficha no se abre otra', (tester) async {
      final compuerta = Completer<void>();
      final m = await _montar(tester, ficha: (_, _) => compuerta.future);

      await tester.tap(_abrirPersona.last);
      await tester.pump();
      await tester.tap(_abrirPersona.last);
      await tester.pump();

      expect(m.fichas, hasLength(1));
      compuerta.complete();
      await tester.pump();
      await tester.pump();

      await tester.tap(_abrirPersona.last);
      await tester.pump();
      expect(m.fichas, hasLength(2), reason: 'al terminar, la fila vuelve a estar habilitada');
    });

    testWidgets('«\$ Cobrar» de Pedro sigue abriendo el cobro desde la pestaña', (tester) async {
      final m = await _montar(tester);

      await tester.tap(_cobrar);
      await tester.pump();
      await tester.pump();

      expect(m.cobros, hasLength(1));
      expect(m.cobros.single.personaId, 'p-pedro');
      expect(m.cobros.single.espacioId, 'esp-1');
    });
  });

  group('C·02 · «+ Agregar persona» abre el alta corta (vista 32 A)', () {
    testWidgets('abre el alta con el espacio puesto y, al guardar, la pestaña lo dice', (
      tester,
    ) async {
      final m = await _montar(tester);

      await tester.tap(_agregar);
      await asentar(tester);
      expect(find.byType(AltaPersonaPage), findsOneWidget);

      await _escribirNombre(tester, 'Jorge');
      await _guardarAlta(tester);

      expect(find.byType(AltaPersonaPage), findsNothing);
      expect(m.repo.recibidas, hasLength(1));
      expect(m.repo.recibidas.single.vinculo.espacioId, 'esp-1');
      expect(m.repo.recibidas.single.persona.nombre, 'Jorge');
      expect(_guardada, findsOneWidget);
      expect(find.text('Guardamos a Jorge en este teléfono.'), findsOneWidget);
    });

    testWidgets('volver del alta sin guardar no avisa nada y deja la hoja como estaba', (
      tester,
    ) async {
      final m = await _montar(tester);

      await tester.tap(_agregar);
      await asentar(tester);
      await tester.tap(_cerrarAlta);
      await asentar(tester);

      expect(find.byType(AltaPersonaPage), findsNothing);
      expect(m.repo.recibidas, isEmpty);
      expect(_guardada, findsNothing);
      expect(_filas, findsNWidgets(2));
      expect(tester.widget<InkWell>(_agregar).onTap, isNotNull, reason: 'nada quedó trabado');
    });

    testWidgets('doble toque: se abre una sola alta', (tester) async {
      await _montar(tester);

      await tester.tap(_agregar);
      await tester.tap(_agregar, warnIfMissed: false);
      await asentar(tester);

      expect(find.byType(AltaPersonaPage), findsOneWidget);

      await tester.tap(_cerrarAlta);
      await asentar(tester);
      expect(find.byType(AltaPersonaPage), findsNothing);
    });

    testWidgets('volver atrás y reentrar: la hoja nueva no hereda el aviso de la anterior', (
      tester,
    ) async {
      final m = await _montar(tester);
      await tester.tap(_agregar);
      await asentar(tester);
      await _escribirNombre(tester, 'Jorge');
      await _guardarAlta(tester);
      expect(_guardada, findsOneWidget);

      await _montar(tester, montaje: m);

      expect(_guardada, findsNothing);
      expect(_seleccionada(tester, 'personas'), isTrue);
    });

    testWidgets('cambiar de pestaña quita el aviso de la última alta', (tester) async {
      await _montar(tester, conHistorial: true);
      await tester.tap(_agregar);
      await asentar(tester);
      await _escribirNombre(tester, 'Jorge');
      await _guardarAlta(tester);
      expect(_guardada, findsOneWidget);

      await tester.tap(_pestana('historial'));
      await tester.pump();
      await tester.tap(_pestana('personas'));
      await tester.pump();

      expect(_guardada, findsNothing);
    });

    testWidgets('dos acciones seguidas: con un cobro en curso «+ Agregar persona» espera', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final m = await _montar(tester, cobrar: (_, _) => compuerta.future);

      await tester.tap(_cobrar);
      await tester.pump();
      await tester.tap(_agregar);
      await tester.pump();

      expect(m.cobros, hasLength(1));
      expect(find.byType(AltaPersonaPage), findsNothing, reason: 'una acción a la vez');
      expect(tester.widget<InkWell>(_agregar).onTap, isNull);

      compuerta.complete();
      await asentar(tester);

      await tester.tap(_agregar);
      await asentar(tester);
      expect(find.byType(AltaPersonaPage), findsOneWidget);
    });

    testWidgets('mientras abre el alta, «Registrar visita» y «\$ Cobrar» esperan', (tester) async {
      final m = await _montar(tester);

      await tester.tap(_agregar);
      await tester.pump();

      expect(tester.widget<FilledButton>(_registrar).onPressed, isNull);
      expect(m.visitas, isEmpty);
      await asentar(tester);
      await tester.tap(_cerrarAlta);
      await asentar(tester);
      expect(tester.widget<FilledButton>(_registrar).onPressed, isNotNull);
    });

    testWidgets('sin saber quién es el colportor no se ofrece agregar', (tester) async {
      await _montar(tester, colportorId: null);

      expect(_agregar, findsNothing);
      expect(_filas, findsNWidgets(2));
    });
  });

  group('C·02 · estados con la hoja arriba', () {
    testWidgets('sin personas: dice que no hay y deja agregar la primera', (tester) async {
      await _montar(tester, contexto: _contextoCon(const []));

      expect(_sinPersonas, findsOneWidget);
      expect(find.text('Todavía no hay personas acá.'), findsOneWidget);
      expect(_agregar, findsOneWidget);
      expect(_filas, findsNothing);
    });

    testWidgets('casa dada de baja (E·04): avisa, muestra las personas en solo lectura y no deja '
        'agregar ni registrar', (tester) async {
      await _montar(
        tester,
        item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 1), motivoBaja: 'Ya no vive nadie'),
      );

      expect(_avisoBaja, findsOneWidget);
      expect(_pestanas, findsOneWidget);
      expect(_filas, findsNWidgets(2));
      expect(_agregar, findsNothing);
      expect(_registrar, findsNothing);
      expect(_cobrar, findsNothing);
    });

    testWidgets('casa dada de baja: la ficha de una persona se puede abrir (es solo ver)', (
      tester,
    ) async {
      final m = await _montar(tester, item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 1)));

      await tester.tap(_abrirPersona.first);
      await tester.pump();
      await tester.pump();

      expect(m.fichas, hasLength(1));
    });

    testWidgets('lejos (E·05): avisa y el resto de la hoja sigue funcionando', (tester) async {
      await _montar(tester, item: itemDeLaHoja(metros: 900));

      expect(_avisoLejos, findsOneWidget);
      expect(_registrar, findsOneWidget);
      expect(_pestanas, findsOneWidget);
      expect(tester.widget<FilledButton>(_registrar).onPressed, isNotNull);
    });

    testWidgets('sin conexión (E·03) se ve igual: la hoja es solo local y no avisa nada', (
      tester,
    ) async {
      await _montar(tester);

      expect(find.textContaining('conexión'), findsNothing);
      expect(_filas, findsNWidgets(2));
    });

    testWidgets('cargando (E·01): esqueletos sin pestañas ni personas', (tester) async {
      await _montar(tester, lectura: (_) => const Stream.empty());

      expect(_cargando, findsOneWidget);
      expect(_pestanas, findsNothing);
      expect(_filas, findsNothing);
    });

    testWidgets('error al leer (E·02): avisa, y «Reintentar» vuelve a leer y muestra la hoja', (
      tester,
    ) async {
      var lecturas = 0;
      await _montar(
        tester,
        lectura: (_) {
          lecturas++;
          return lecturas == 1
              ? Stream.error(StateError('no se pudo leer'))
              : Stream.value(_contextoC02);
        },
      );
      expect(_avisoError, findsOneWidget);
      expect(_pestanas, findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(_avisoError, findsNothing);
      expect(_pestanas, findsOneWidget);
      expect(_filas, findsNWidgets(2));
    });

    testWidgets('al llegar una persona nueva a la lista, la pestaña la suma', (tester) async {
      final fuente = StreamController<ContextoDeLaCasa>();
      addTearDown(fuente.close);
      await _montar(tester, lectura: (_) => fuente.stream);
      fuente.add(_contextoCon([pedroGomez]));
      await tester.pump();
      await tester.pump();
      expect(_filas, findsOneWidget);

      fuente.add(_contextoCon([pedroGomez, _ana]));
      await tester.pump();
      await tester.pump();

      expect(_filas, findsNWidgets(2));
    });
  });

  group('C·02 · datos límite y accesibilidad', () {
    testWidgets('una lista larga (60 personas) se desplaza y la última se alcanza', (tester) async {
      final personas = [
        for (var i = 0; i < 60; i++) clienteDePersonas('p-$i', 'Persona', apellido: 'Número $i'),
      ];
      await _montar(tester, contexto: _contextoCon(personas));

      await tester.dragUntilVisible(
        find.text('Persona Número 59'),
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      expect(find.text('Persona Número 59'), findsOneWidget);
      await tester.dragUntilVisible(
        _agregar,
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      expect(_agregar, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nombres larguísimos no desbordan', (tester) async {
      final largo = clienteDePersonas(
        'p-largo',
        'Maximiliano Bartolomé de la Santísima Trinidad',
        apellido: 'Fernández de Castro y Ortiz de Zárate',
      );
      await _montar(tester, contexto: _contextoCon([largo]), tamano: const Size(360, 740));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Maximiliano'), findsOneWidget);
    });

    for (final escala in [2.0, 3.0]) {
      testWidgets('a 360 px y texto ×$escala no desborda, con las tres pestañas y las filas', (
        tester,
      ) async {
        await _montar(
          tester,
          conHistorial: true,
          conNotas: true,
          escala: escala,
          tamano: const Size(360, 740),
        );

        expect(tester.takeException(), isNull);
        expect(_pestanas, findsOneWidget);
        expect(tester.getRect(_pestanas).right, lessThanOrEqualTo(360));
        expect(_filas, findsNWidgets(2));
        for (final id in ['personas', 'historial', 'notas']) {
          expect(tester.getSize(_pestana(id)).height, greaterThanOrEqualTo(48));
        }
      });
    }

    testWidgets('objetivos táctiles de al menos 48 dp: filas, «+ Agregar persona» y «\$ Cobrar»', (
      tester,
    ) async {
      await _montar(tester);

      expect(tester.getSize(_agregar).height, greaterThanOrEqualTo(48));
      for (final fila in _abrirPersona.evaluate()) {
        expect(tester.getSize(find.byWidget(fila.widget)).height, greaterThanOrEqualTo(48));
      }
      expect(tester.getSize(_cobrar).height, greaterThanOrEqualTo(48));
    });

    testWidgets('el lector de pantalla oye la pestaña elegida como seleccionada y cada persona con '
        'su detalle', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, conHistorial: true);

      expect(_seleccionada(tester, 'personas'), isTrue);
      expect(find.bySemanticsLabel('Ana Gómez. Entrevista dada el 05/10'), findsOneWidget);
      expect(find.bySemanticsLabel('+ Agregar persona'), findsOneWidget);
      semantica.dispose();
    });
  });
}
