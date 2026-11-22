// «+ Registrar venta» de la pestaña Ventas (HU-VEN-001, #546): «¿A quién le vendés?».
//
// Sin diseño nuevo (Cristian eligió reusar las piezas aprobadas): la fila de cada persona es la de la
// vista 32 (32A·05) y la venta es la vista 27. Un test por estado (cargando, vacío, error, con
// personas, sin resultados) y por cada caso límite: doble toque, falla a mitad del guardado, dos
// personas seguidas, volver y reentrar, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart'
    show PestanaInicio;
import 'package:colportores_mobile/features/ventas/domain/entities/persona_para_vender.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/cuando_cobrar_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/elegir_persona_para_vender_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/nueva_venta_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_elegir_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/personas_para_vender_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

/// Todo lo que el test controla: la lista, la venta, la agenda y qué devolvió la pantalla.
final class _Mundo {
  _Mundo({List<PersonaParaVender>? personas})
    : lector = LectorDePersonasParaVenderFalso(personas ?? _tres());

  final LectorDePersonasParaVenderFalso lector;
  final entorno = EntornoDeVenta();
  final agendas = AgendaRepositorioQueAgenda();

  var cerrada = false;
  PestanaInicio? pestana;
}

List<PersonaParaVender> _tres() => [
  personaParaVender(
    '3',
    nombre: 'Carlos',
    apellido: 'Rey',
    calle: 'Rivadavia',
    numero: '55',
    depto: null,
  ),
  personaParaVender('1', nombre: 'Ana', apellido: 'Zapata'),
  personaParaVender(
    '2',
    nombre: 'Beatriz',
    apellido: 'Álvarez',
    calle: 'Av. Italia',
    numero: '1234',
    depto: '101',
  ),
];

Future<_Mundo> _montar(
  WidgetTester tester, {
  _Mundo? mundo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final m = mundo ?? _Mundo();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...m.entorno.overrides,
        lectorDePersonasParaVenderProvider.overrideWithValue(m.lector),
        agendaRepositoryProvider.overrideWithValue(m.agendas),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => DateTime(2026, 10, 28, 14, 35)),
        ...Telefono().overrides,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_elegir'),
                onPressed: () async {
                  m.cerrada = false;
                  m.pestana = await Navigator.of(
                    context,
                  ).push(ElegirPersonaParaVenderPage.ruta(colportorId: 'col-1'));
                  m.cerrada = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await _abrir(tester);
  return m;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_elegir')));
  await asentar(tester);
}

Finder _fila(String id) => find.byKey(Key('persona_para_vender_ep-$id'));

/// 27A·14 «Terminar sin entregar ni cobrar» y, si el hilo pide la fecha de la entrega (27C·01, #435),
/// se vuelve sin elegirla.
Future<void> _terminarSinNada(WidgetTester tester) async {
  await tocar(tester, find.byKey(const Key('venta_terminar')));
  await tester.pumpAndSettle();
  if (find.byKey(const Key('otro_dia_pagina')).evaluate().isNotEmpty) {
    await tocar(tester, find.byKey(const Key('venta_atras')));
    await tester.pumpAndSettle();
  }
}

/// «¿Cuándo volvés a cobrar?» → «Sin fecha» → «Guardar», y «Listo» en «Así quedó la venta».
Future<void> _sinFechaYListo(WidgetTester tester) async {
  await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
  await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
  await tester.pumpAndSettle();
  await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
  await tester.pumpAndSettle();
}

Finder get _busqueda => find.byKey(const Key('personas_busqueda'));

Finder get _campoTalonario =>
    find.descendant(of: find.byKey(const Key('venta_talonario')), matching: find.byType(TextField));

/// Los nombres de las filas visibles, de arriba abajo.
List<String> _ordenVisible(WidgetTester tester, List<String> ids) {
  final conPosicion = [
    for (final id in ids)
      if (_fila(id).evaluate().isNotEmpty) (id, tester.getTopLeft(_fila(id)).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (id, _) in conPosicion) id];
}

/// 27A·01 → 27A·05: una colección de 2 libros con Salud y Hogar y Nuestros Hijos.
Future<void> _armarVenta(WidgetTester tester) async {
  await tocar(tester, find.text('Colección de 2 libros'));
  await tocar(tester, find.text(TextosVenta.armarLaColeccion));
  for (final (i, nombre) in ['Salud y Hogar', 'Nuestros Hijos'].indexed) {
    await tocar(tester, find.byKey(Key('armar_libro_${i + 1}')));
    await tocar(tester, find.text(nombre).last);
    await tocar(tester, find.text(TextosVenta.listo));
  }
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
}

void main() {
  group('estados', () {
    testWidgets('cargando: tres filas grises anunciadas, y después la lista', (tester) async {
      final semantica = tester.ensureSemantics();
      final mundo = _Mundo()..lector.compuerta = Completer<void>();
      await _montar(tester, mundo: mundo);

      expect(find.byKey(const Key('personas_cargando')), findsOneWidget);
      expect(find.bySemanticsLabel(TextosElegirPersona.cargando), findsOneWidget);
      expect(_busqueda, findsNothing);

      mundo.lector.compuerta!.complete();
      await asentar(tester);

      expect(find.byKey(const Key('personas_cargando')), findsNothing);
      expect(_fila('1'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('con personas: el título, la cuenta y cada una con su dirección, de la A a la Z', (
      tester,
    ) async {
      await _montar(tester);

      expect(find.text('NUEVA VENTA'), findsOneWidget);
      expect(find.text('¿A quién le vendés?'), findsOneWidget);
      expect(find.text('PERSONAS · 3'), findsOneWidget);
      expect(find.text('Ana Zapata'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(find.text('Beatriz Álvarez'), findsOneWidget);
      expect(find.text('Av. Italia 1234 · Depto 101'), findsOneWidget);
      expect(find.text('Carlos Rey'), findsOneWidget);
      expect(find.text('Rivadavia 55'), findsOneWidget);
      expect(_ordenVisible(tester, ['1', '2', '3']), ['1', '2', '3']);
    });

    testWidgets('sin personas: dice qué pasa y qué hacer, con «Ir al mapa» a mano', (tester) async {
      final mundo = _Mundo(personas: const []);
      await _montar(tester, mundo: mundo);

      expect(find.text(TextosElegirPersona.sinPersonas), findsOneWidget);
      expect(find.text(TextosElegirPersona.sinPersonasAyuda), findsOneWidget);
      expect(find.text(TextosElegirPersona.irAlMapa), findsOneWidget);
      expect(_busqueda, findsNothing);

      await tester.tap(find.text(TextosElegirPersona.irAlMapa));
      await asentar(tester);

      expect(mundo.cerrada, isTrue);
      expect(mundo.pestana, PestanaInicio.mapa);
    });

    testWidgets('error al leer: avisa que no se perdió nada y «Reintentar» vuelve a leer', (
      tester,
    ) async {
      final mundo = _Mundo()..lector.error = StateError('falla');
      await _montar(tester, mundo: mundo);

      expect(find.text(TextosElegirPersona.errorLectura), findsOneWidget);
      expect(_fila('1'), findsNothing);

      await tester.tap(find.text(TextosElegirPersona.reintentar));
      await asentar(tester);

      expect(mundo.lector.suscripciones, 2);
      expect(find.text(TextosElegirPersona.errorLectura), findsNothing);
      expect(_fila('1'), findsOneWidget);
    });

    testWidgets('si la lista queda vacía mientras está abierta, pasa al aviso y no queda muda', (
      tester,
    ) async {
      final mundo = await _montar(tester);

      mundo.lector.emitir(const []);
      await asentar(tester);

      expect(find.text(TextosElegirPersona.sinPersonas), findsOneWidget);
      expect(_fila('1'), findsNothing);
    });

    testWidgets('una persona dada de baja con la lista abierta deja de estar', (tester) async {
      final mundo = await _montar(tester);

      mundo.lector.emitir([
        for (final p in _tres())
          if (p.espacioPersonaId != 'ep-1') p,
      ]);
      await asentar(tester);

      expect(_fila('1'), findsNothing);
      expect(_fila('2'), findsOneWidget);
      expect(find.text('PERSONAS · 2'), findsOneWidget);
    });

    testWidgets('«volver» cierra sin elegir pestaña', (tester) async {
      final mundo = await _montar(tester);

      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);

      expect(mundo.cerrada, isTrue);
      expect(mundo.pestana, isNull);
    });
  });

  group('búsqueda', () {
    testWidgets('por nombre: queda quien tiene lo escrito y la cuenta se actualiza', (
      tester,
    ) async {
      await _montar(tester);

      await tester.enterText(_busqueda, 'bea');
      await asentar(tester);

      expect(_fila('2'), findsOneWidget);
      expect(_fila('1'), findsNothing);
      expect(_fila('3'), findsNothing);
      expect(find.text('PERSONAS · 1'), findsOneWidget);
    });

    testWidgets('por dirección, sin tildes ni mayúsculas', (tester) async {
      await _montar(tester);

      await tester.enterText(_busqueda, 'ITALIA 12');
      await asentar(tester);

      expect(_ordenVisible(tester, ['1', '2', '3']), ['2']);

      await tester.enterText(_busqueda, 'alvarez');
      await asentar(tester);

      expect(_ordenVisible(tester, ['1', '2', '3']), ['2']);
    });

    testWidgets('primero lo que empieza con lo escrito y después A-Z', (tester) async {
      final mundo = _Mundo(
        personas: [
          personaParaVender('a', nombre: 'Zoe', apellido: 'Gómez', calle: 'Mataojo'),
          personaParaVender('b', nombre: 'Ana', apellido: 'Sosa', calle: 'Hnos. Matos'),
          personaParaVender('c', nombre: 'Mateo', apellido: 'Pérez', calle: 'Rivera'),
        ],
      );
      await _montar(tester, mundo: mundo);

      await tester.enterText(_busqueda, 'mat');
      await asentar(tester);

      // «Mateo» (nombre) y «Zoe» (calle Mataojo) empiezan con «mat»; «Ana» (Hnos. Matos) solo lo contiene.
      expect(_ordenVisible(tester, ['a', 'b', 'c']), ['c', 'a', 'b']);
    });

    testWidgets('sin resultados: dice que no hay nadie y «Borrar búsqueda» vuelve a todos', (
      tester,
    ) async {
      await _montar(tester);

      await tester.enterText(_busqueda, 'xyz');
      await asentar(tester);

      expect(find.text(TextosElegirPersona.sinResultados), findsOneWidget);
      expect(find.text(TextosElegirPersona.sinResultadosAyuda), findsOneWidget);
      expect(_fila('1'), findsNothing);

      await tester.tap(find.text(TextosElegirPersona.borrarBusqueda));
      await asentar(tester);

      expect(find.text(TextosElegirPersona.sinResultados), findsNothing);
      expect(_fila('1'), findsOneWidget);
      expect(tester.widget<TextField>(_busqueda).controller!.text, isEmpty);
    });

    testWidgets('la ✕ de la caja borra lo escrito y devuelve la lista entera', (tester) async {
      await _montar(tester);
      await tester.enterText(_busqueda, 'ana');
      await asentar(tester);
      expect(find.text('PERSONAS · 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('personas_borrar_busqueda')));
      await asentar(tester);

      expect(find.text('PERSONAS · 3'), findsOneWidget);
    });
  });

  group('vender', () {
    testWidgets('tocar a alguien abre la vista 27 con esa persona y su dirección puestas', (
      tester,
    ) async {
      await _montar(tester);

      await tester.tap(_fila('2'));
      await asentar(tester);

      expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
      expect(find.text('Beatriz Álvarez'), findsOneWidget);
      expect(find.text('Av. Italia 1234 · Depto 101'), findsOneWidget);
    });

    testWidgets('una persona sin nombre se vende como «Sin nombre»', (tester) async {
      final mundo = _Mundo(
        personas: [personaParaVender('1', nombre: ' ', apellido: '')],
      );
      await _montar(tester, mundo: mundo);

      await tester.tap(_fila('1'));
      await asentar(tester);

      expect(find.text(TextosElegirPersona.sinNombre), findsOneWidget);
    });

    testWidgets('registrar la venta la guarda con esa persona, sigue «¿Cuándo volvés a cobrar?» y '
        'vuelve a la pestaña con el aviso', (tester) async {
      final mundo = await _montar(tester);

      await tester.tap(_fila('2'));
      await asentar(tester);
      await _armarVenta(tester);
      await escribir(tester, _campoTalonario, '0042');
      await tocar(tester, find.byKey(const Key('venta_cta')));

      // 27A·14 «Venta registrada: ¿y ahora?» (sin cobro enganchado: solo la confirmación).
      expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
      expect(find.text('Beatriz Álvarez · \$ 8.900'), findsOneWidget);
      await _terminarSinNada(tester);

      expect(find.text('¿Cuándo volvés a cobrar?'), findsOneWidget);
      await _sinFechaYListo(tester);

      final recibida = mundo.entorno.ventas.recibidas.single;
      expect(recibida.venta.espacioPersonaId, 'ep-2');
      expect(recibida.venta.colportorId, 'col-1');
      expect(recibida.venta.numeroTalonario, '0042');
      expect(mundo.cerrada, isTrue);
      expect(mundo.pestana, isNull);
      expect(find.text('Venta 0042 guardada. Cobranza sin fecha.'), findsOneWidget);
      expect(mundo.agendas.recibidas, isEmpty);
    });

    testWidgets('«Mañana» agenda la cobranza de esa persona en su casa', (tester) async {
      final mundo = await _montar(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);
      await _armarVenta(tester);
      await escribir(tester, _campoTalonario, '0043');
      await tocar(tester, find.byKey(const Key('venta_cta')));
      await _terminarSinNada(tester);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.manana)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agendar_hoja_listo')));
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
      await tester.pumpAndSettle();

      final cita = mundo.agendas.recibidas.single.agenda;
      expect(cita.espacioId, 'esp-1');
      expect(cita.espacioPersonaId, 'ep-1');
      expect(mundo.cerrada, isTrue);
    });

    testWidgets('salir de la venta sin registrar deja la lista donde estaba, con la búsqueda', (
      tester,
    ) async {
      final mundo = await _montar(tester);
      await tester.enterText(_busqueda, 'ana');
      await asentar(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);
      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);

      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
      expect(find.byKey(const Key('elegir_persona_pagina')), findsOneWidget);
      expect(tester.widget<TextField>(_busqueda).controller!.text, 'ana');
      expect(_fila('1'), findsOneWidget);
      expect(mundo.cerrada, isFalse);
      expect(mundo.entorno.ventas.recibidas, isEmpty);
    });

    testWidgets('volver atrás y elegir a otra persona abre la venta de la otra', (tester) async {
      await _montar(tester);

      await tester.tap(_fila('1'));
      await asentar(tester);
      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);
      await tester.tap(_fila('3'));
      await asentar(tester);

      expect(find.byType(NuevaVentaPage), findsOneWidget);
      expect(find.text('Carlos Rey'), findsOneWidget);
      expect(find.text('Rivadavia 55'), findsOneWidget);
    });

    testWidgets('cerrar la lista y reentrar empieza de cero', (tester) async {
      final mundo = await _montar(tester);
      await tester.enterText(_busqueda, 'ana');
      await asentar(tester);
      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);
      expect(mundo.cerrada, isTrue);

      await _abrir(tester);

      expect(tester.widget<TextField>(_busqueda).controller!.text, isEmpty);
      expect(find.text('PERSONAS · 3'), findsOneWidget);
      // La lista leyó otra vez (autoDispose): una suscripción por apertura.
      expect(mundo.lector.suscripciones, 2);
    });

    testWidgets('doble toque en la misma persona: se abre una sola venta', (tester) async {
      await _montar(tester);

      await tester.tap(_fila('1'));
      await tester.tap(_fila('1'), warnIfMissed: false);
      await asentar(tester);

      expect(find.byType(NuevaVentaPage), findsOneWidget);
      // Volver deja una sola capa: no hay otra venta abajo.
      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);
      expect(find.byType(NuevaVentaPage), findsNothing);
      expect(find.byKey(const Key('elegir_persona_pagina')), findsOneWidget);
    });

    testWidgets(
      'dos personas seguidas antes de que abra la primera: gana la primera y no se pisa',
      (tester) async {
        await _montar(tester);

        await tester.tap(_fila('1'));
        await tester.tap(_fila('2'), warnIfMissed: false);
        await asentar(tester);

        expect(find.byType(NuevaVentaPage), findsOneWidget);
        expect(find.text('Ana Zapata'), findsOneWidget);
        expect(find.text('Beatriz Álvarez'), findsNothing);
      },
    );

    testWidgets('falla a mitad del guardado: la venta sigue con todo lo cargado, el botón se '
        'rehabilita y después se puede elegir a otra persona', (tester) async {
      final mundo = await _montar(tester);
      mundo.entorno.ventas.respuesta = const FailureInesperado();

      await tester.tap(_fila('1'));
      await asentar(tester);
      await _armarVenta(tester);
      await escribir(tester, _campoTalonario, '0044');
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.byKey(const Key('venta_error')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('venta_cta'))).onPressed, isNotNull);
      expect(mundo.cerrada, isFalse);

      // Reintenta y esta vez guarda.
      mundo.entorno.ventas.respuesta = null;
      await tocar(tester, find.byKey(const Key('venta_cta')));
      expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
      await _terminarSinNada(tester);
      await _sinFechaYListo(tester);

      expect(mundo.entorno.ventas.recibidas, hasLength(2));
      expect(mundo.cerrada, isTrue);

      // La pantalla no quedó trabada: se vuelve a abrir y se vende a otra persona.
      await _abrir(tester);
      await tester.tap(_fila('3'));
      await asentar(tester);
      expect(find.byType(NuevaVentaPage), findsOneWidget);
    });

    testWidgets(
      'si la persona se da de baja mientras se carga la venta, la lista ya no la tiene al '
      'volver',
      (tester) async {
        final mundo = await _montar(tester);

        await tester.tap(_fila('1'));
        await asentar(tester);
        mundo.lector.emitir([
          for (final p in _tres())
            if (p.espacioPersonaId != 'ep-1') p,
        ]);
        await asentar(tester);
        await tester.tap(find.byKey(const Key('venta_atras')));
        await asentar(tester);

        expect(_fila('1'), findsNothing);
        expect(find.text('PERSONAS · 2'), findsOneWidget);
      },
    );
  });

  group('datos límite', () {
    testWidgets('300 personas: la lista es perezosa, llega hasta la última y la cuenta es exacta', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 300; i++)
          personaParaVender(
            i.toString().padLeft(3, '0'),
            nombre: 'Persona ${i.toString().padLeft(3, '0')}',
            apellido: 'Prueba',
          ),
      ];
      await _montar(tester, mundo: _Mundo(personas: muchas));

      expect(find.text('PERSONAS · 300'), findsOneWidget);
      expect(_fila('299'), findsNothing);
      await tester.dragUntilVisible(
        _fila('299'),
        find.byKey(const Key('elegir_persona_scroll')),
        const Offset(0, -1000),
      );
      expect(_fila('299'), findsOneWidget);
    });

    testWidgets('la misma persona en dos deptos aparece dos veces, cada una con el suyo', (
      tester,
    ) async {
      final mundo = _Mundo(
        personas: [
          personaParaVender('1', nombre: 'Ana', apellido: 'Zapata', depto: '3B'),
          personaParaVender('1b', nombre: 'Ana', apellido: 'Zapata', depto: '4C'),
        ],
      );
      await _montar(tester, mundo: mundo);

      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 4C'), findsOneWidget);
      expect(_ordenVisible(tester, ['1', '1b']), ['1', '1b']);
    });

    for (final tamano in [const Size(320, 568), const Size(412, 915)]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'con nombres y direcciones larguísimos a ${tamano.width.toInt()}×${tamano.height.toInt()} y '
          'letra $escala no desborda y se llega a todas las filas',
          (tester) async {
            final largas = [
              for (var i = 0; i < 4; i++)
                personaParaVender(
                  'l$i',
                  nombre: 'María de los Ángeles $i',
                  apellido: 'Fernández de la Cruz y Sotomayor Echeverría',
                  calle: 'Avenida Doctor Luis Alberto de Herrera y Presidente Gestido',
                  numero: '12345',
                  depto: 'Torre 2 Piso 15 Apartamento 1503',
                ),
            ];
            await _montar(
              tester,
              mundo: _Mundo(personas: largas),
              escala: escala,
              tamano: tamano,
            );

            expect(tester.takeException(), isNull);
            for (var i = 0; i < 4; i++) {
              await tester.scrollUntilVisible(
                _fila('l$i'),
                200,
                scrollable: find.byType(Scrollable).first,
              );
              expect(_fila('l$i'), findsOneWidget);
              expect(tester.getSize(_fila('l$i')).height, greaterThanOrEqualTo(48));
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets('accesible a letra $escala: objetivos de 48 dp, etiquetas y contraste', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await _montar(tester, escala: escala, tamano: const Size(390, 844));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }

    testWidgets('la fila se lee como botón con el nombre y la dirección', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);

      expect(find.bySemanticsLabel('Ana Zapata. Mataojo 2044 · Depto 3B'), findsOneWidget);
      semantica.dispose();
    });
  });
}
