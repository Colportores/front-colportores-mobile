// El filtro por tipo del centro de notificaciones (vista 24, grupo D, HU-NOT-005, #484): 24D·01 a
// 24D·04 y los casos límite de cada flujo (doble toque, falla a mitad, acciones seguidas, volver y
// reentrar, datos límite y texto al 200 %). El historial es el repositorio en memoria de
// `historial_notificaciones_falsos.dart`.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/fila_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/textos_filtro_tipo_notificacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';

final _fila = find.byKey(const Key('filtro_fila'));
final _cambiar = find.byKey(const Key('filtro_cambiar'));
final _quitar = find.byKey(const Key('filtro_quitar'));
final _hojaTitulo = find.byKey(const Key('filtro_hoja_titulo'));
final _listo = find.byKey(const Key('filtro_hoja_listo'));
final _vacioFiltro = find.byKey(const Key('filtro_vacio'));
final _verTodos = find.byKey(const Key('filtro_ver_todos'));

Finder _opcion(TipoNotificacion? tipo) =>
    find.byKey(Key('filtro_opcion_${tipo?.codigo ?? 'TODOS'}'));

/// Siete avisos de cuatro tipos: dos tickets validados, un pedido, tres recordatorios y una cuota.
List<Notificacion> _variados() => [
  aviso('r1', hace: const Duration(minutes: 20), titulo: 'Cobranza a las 16:30'),
  aviso(
    't1',
    tipo: TipoNotificacion.ticketValidado,
    hace: const Duration(hours: 2),
    titulo: 'Tu ticket fue validado',
    detalle: 'Depósito del 20/10 · \$ 4.800',
    conDestino: false,
  ),
  aviso(
    'p1',
    tipo: TipoNotificacion.pedidoAutorizado,
    hace: const Duration(hours: 3),
    titulo: 'Pedido autorizado',
    detalle: '12 libros · retiro en la oficina',
    leida: true,
    conDestino: false,
  ),
  aviso('r2', hace: const Duration(hours: 5), titulo: 'Cobranza a las 11:00', leida: true),
  aviso(
    't2',
    tipo: TipoNotificacion.ticketValidado,
    hace: const Duration(days: 3),
    titulo: 'Tu ticket fue validado',
    detalle: 'Depósito del 14/10 · \$ 6.200',
    leida: true,
    conDestino: false,
  ),
  aviso(
    'c1',
    tipo: TipoNotificacion.cuotaPendiente,
    hace: const Duration(days: 4),
    titulo: 'Cuota pendiente hace 3 días',
    detalle: 'Grecia 3310',
    conDestino: false,
  ),
  aviso('r3', hace: const Duration(days: 5), titulo: 'Cobranza a las 09:00', leida: true),
];

CentroArnes _arnes() => CentroArnes(avisos: _variados());

Future<void> _abrirHoja(WidgetTester tester) async {
  await tester.tap(_cambiar);
  await tester.pumpAndSettle();
}

/// Elige [tipo] en la hoja y confirma con «Listo».
Future<void> _filtrarPor(WidgetTester tester, TipoNotificacion? tipo) async {
  await _abrirHoja(tester);
  await tester.ensureVisible(_opcion(tipo));
  await tester.tap(_opcion(tipo));
  await tester.pump();
  await tester.ensureVisible(_listo);
  await tester.tap(_listo);
  await tester.pumpAndSettle();
}

/// Abre el centro en una pantalla alta, para que la lista construya todos los avisos (es perezosa).
Future<void> _abrir(WidgetTester tester, CentroArnes arnes) =>
    abrirCentro(tester, arnes, tamano: const Size(390, 1800));

double _arriba(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

Future<void> _abrirDesdeHoy(WidgetTester tester, CentroArnes arnes) async {
  tester.view
    ..physicalSize = const Size(390, 1800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: arnes.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('ir_al_centro'),
                onPressed: () => Navigator.of(context).push(CentroNotificacionesPage.ruta()),
                child: const Text('Ir al centro'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('ir_al_centro')));
  await tester.pumpAndSettle();
}

void main() {
  group('24D·01 Fila «Tipo de aviso» arriba de la lista', () {
    testWidgets('con avisos, la fila dice «Todos» y «Cambiar», arriba del primer aviso', (
      tester,
    ) async {
      await _abrir(tester, _arnes());

      expect(_fila, findsOneWidget);
      expect(find.text('TIPO DE AVISO'), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Todos')), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Cambiar')), findsOneWidget);
      expect(_quitar, findsNothing);
      expect(_arriba(tester, _fila), lessThan(_arriba(tester, find.text('HOY'))));
      expect(find.byType(FilaNotificacion), findsNWidgets(7));
    });

    testWidgets('para el lector de pantalla la fila es un botón que dice qué se ve y que cambia', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester, _arnes());

      final nodo = tester.getSemantics(_cambiar);
      expect(nodo.label, 'Tipo de aviso: Todos. Cambiar');
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });

    testWidgets('la fila mide al menos 48 dp de alto y de ancho', (tester) async {
      await _abrir(tester, _arnes());

      final caja = tester.getSize(_cambiar);
      expect(caja.height, greaterThanOrEqualTo(48));
      expect(caja.width, greaterThanOrEqualTo(48));
    });

    testWidgets('sin avisos (24C·04), cargando (24C·05) y con error (24C·06) no hay fila', (
      tester,
    ) async {
      final vacio = CentroArnes();
      await _abrir(tester, vacio);
      expect(centroVacio, findsOneWidget);
      expect(_fila, findsNothing);

      final cargando = CentroArnes(avisos: _variados());
      cargando.historial.puertaAlObservar = Completer<void>();
      await abrirCentro(tester, cargando, esperar: false);
      expect(centroCargando, findsOneWidget);
      expect(_fila, findsNothing);
      cargando.historial.puertaAlObservar!.complete();
      await tester.pumpAndSettle();
      expect(_fila, findsOneWidget);

      final error = CentroArnes(avisos: _variados());
      error.historial.errorAlObservar = StateError('no se pudo leer');
      await _abrir(tester, error);
      expect(centroError, findsOneWidget);
      expect(_fila, findsNothing);
    });
  });

  group('24D·02 Elegir el tipo', () {
    testWidgets('la hoja «Ver avisos de» ofrece «Todos» y los 7 tipos, en el orden del canvas', (
      tester,
    ) async {
      await _abrir(tester, _arnes());
      await _abrirHoja(tester);

      expect(_hojaTitulo, findsOneWidget);
      expect(find.text('Ver avisos de'), findsOneWidget);
      final textos = [
        'Todos',
        'Recordatorios de visita',
        'Visitas de mañana',
        'Pedido autorizado',
        'Ticket validado',
        'Ticket rechazado',
        'Asignaciones',
        'Cuota pendiente',
      ];
      final opciones = [null, ...TextosFiltroTipoNotificacion.orden];
      expect(opciones, hasLength(textos.length));
      expect(TipoNotificacion.values, hasLength(7));
      expect(TextosFiltroTipoNotificacion.orden.toSet(), TipoNotificacion.values.toSet());
      for (var i = 0; i < textos.length; i++) {
        expect(
          find.descendant(of: _opcion(opciones[i]), matching: find.text(textos[i])),
          findsOneWidget,
          reason: textos[i],
        );
      }
      expect(_listo, findsOneWidget);
    });

    testWidgets('elegir una opción solo la marca: la lista no cambia hasta tocar «Listo»', (
      tester,
    ) async {
      await _abrir(tester, _arnes());
      await _abrirHoja(tester);

      await tester.tap(_opcion(TipoNotificacion.ticketValidado));
      await tester.pump();

      expect(find.byType(FilaNotificacion), findsNWidgets(7));
      await tester.tap(_listo);
      await tester.pumpAndSettle();
      expect(_hojaTitulo, findsNothing);
      expect(find.byType(FilaNotificacion), findsNWidgets(2));
    });

    testWidgets('la opción vigente aparece marcada y las demás no, para el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.pedidoAutorizado);
      await _abrirHoja(tester);

      final marcada = tester.getSemantics(_opcion(TipoNotificacion.pedidoAutorizado));
      expect(marcada.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(marcada.label, 'Pedido autorizado');
      final otra = tester.getSemantics(_opcion(TipoNotificacion.ticketValidado));
      expect(otra.getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
      semantica.dispose();
    });

    testWidgets('cerrar la hoja sin «Listo» (tocando afuera) deja el filtro como estaba', (
      tester,
    ) async {
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);
      await _abrirHoja(tester);

      await tester.tap(_opcion(TipoNotificacion.cuotaPendiente));
      await tester.pump();
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(_hojaTitulo, findsNothing);
      expect(find.descendant(of: _fila, matching: find.text('Ticket validado')), findsOneWidget);
      expect(find.byType(FilaNotificacion), findsNWidgets(2));
    });

    testWidgets('«Todos» en la hoja saca el filtro', (tester) async {
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      await _filtrarPor(tester, null);

      expect(_quitar, findsNothing);
      expect(find.byType(FilaNotificacion), findsNWidgets(7));
    });
  });

  group('24D·03 Filtro activo', () {
    testWidgets('la lista muestra solo los avisos de ese tipo y la fila dice cuál es', (
      tester,
    ) async {
      await _abrir(tester, _arnes());

      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      expect(find.descendant(of: _fila, matching: find.text('Ticket validado')), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Quitar')), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Cambiar')), findsNothing);
      expect(filaDe('t1'), findsOneWidget);
      expect(filaDe('t2'), findsOneWidget);
      for (final id in ['r1', 'p1', 'r2', 'c1', 'r3']) {
        expect(filaDe(id), findsNothing, reason: id);
      }
      // Los rótulos de día son los de los avisos que se ven.
      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('AYER'), findsNothing);
      expect(_arriba(tester, _fila), lessThan(_arriba(tester, find.text('HOY'))));
    });

    testWidgets('«✕ Quitar» vuelve a «Todos» y a la lista entera', (tester) async {
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      await tester.tap(_quitar);
      await tester.pumpAndSettle();

      expect(find.descendant(of: _fila, matching: find.text('Todos')), findsOneWidget);
      expect(_quitar, findsNothing);
      expect(find.byType(FilaNotificacion), findsNWidgets(7));
    });

    testWidgets('tocar la fila con filtro activo abre la hoja con ese tipo marcado y se cambia', (
      tester,
    ) async {
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      await _filtrarPor(tester, TipoNotificacion.cuotaPendiente);

      expect(find.descendant(of: _fila, matching: find.text('Cuota pendiente')), findsOneWidget);
      expect(filaDe('c1'), findsOneWidget);
      expect(filaDe('t1'), findsNothing);
    });

    testWidgets('para el lector de pantalla hay dos botones: cambiar el tipo y quitarlo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      expect(tester.getSemantics(_cambiar).label, 'Tipo de aviso: Ticket validado. Cambiar');
      final quitar = tester.getSemantics(_quitar);
      expect(quitar.label, 'Quitar el filtro y ver todos los avisos');
      expect(quitar.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });

    testWidgets('un aviso del tipo filtrado se abre y se marca como leído como siempre', (
      tester,
    ) async {
      final arnes = _arnes();
      await _abrir(tester, arnes);
      await _filtrarPor(tester, TipoNotificacion.recordatorioVisita);

      await tester.tap(filaDe('r1'));
      await tester.pumpAndSettle();

      expect(arnes.historial.marcadas, ['r1']);
      expect(arnes.abridor.abiertos, [const DestinoAgenda('agenda-r1')]);
      expect(find.descendant(of: filaDe('r1'), matching: find.text('Nueva')), findsNothing);
      expect(filaDe('r1'), findsOneWidget);
    });
  });

  group('24D·04 Sin avisos de ese tipo', () {
    testWidgets('dice qué tipo está filtrado, qué lo trae y ofrece «Ver todos»', (tester) async {
      await _abrir(tester, _arnes());

      await _filtrarPor(tester, TipoNotificacion.ticketRechazado);

      expect(_vacioFiltro, findsOneWidget);
      expect(find.text('No tenés avisos de tickets rechazados'), findsOneWidget);
      expect(find.text('Cuando tu coordinador rechace un ticket, lo ves acá.'), findsOneWidget);
      expect(find.text('Ver todos'), findsOneWidget);
      // La fila sigue arriba para cambiar o quitar el filtro; el vacío general no aparece.
      expect(find.descendant(of: _fila, matching: find.text('Ticket rechazado')), findsOneWidget);
      expect(centroVacio, findsNothing);
      expect(find.byType(FilaNotificacion), findsNothing);
    });

    testWidgets('el texto del canvas de «Pedido autorizado» es el literal', (tester) async {
      final arnes = CentroArnes(avisos: [aviso('r1')]);
      await _abrir(tester, arnes);

      await _filtrarPor(tester, TipoNotificacion.pedidoAutorizado);

      expect(find.text('No tenés avisos de pedidos autorizados'), findsOneWidget);
      expect(find.text('Cuando tu coordinador autorice un pedido, lo ves acá.'), findsOneWidget);
    });

    testWidgets('«Ver todos» vuelve a la lista entera', (tester) async {
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketRechazado);

      await tester.tap(_verTodos);
      await tester.pumpAndSettle();

      expect(_vacioFiltro, findsNothing);
      expect(find.byType(FilaNotificacion), findsNWidgets(7));
      expect(find.descendant(of: _fila, matching: find.text('Todos')), findsOneWidget);
    });

    testWidgets('cada tipo tiene su vacío con título y texto propios, sin repetir', (tester) async {
      final titulos = {
        for (final t in TipoNotificacion.values) TextosFiltroTipoNotificacion.vacioTitulo(t),
      };
      final textos = {
        for (final t in TipoNotificacion.values) TextosFiltroTipoNotificacion.vacioTexto(t),
      };
      expect(titulos, hasLength(TipoNotificacion.values.length));
      expect(textos, hasLength(TipoNotificacion.values.length));
    });

    testWidgets('un aviso del tipo que llega con el vacío a la vista lo reemplaza sin recargar', (
      tester,
    ) async {
      final arnes = _arnes();
      await _abrir(tester, arnes);
      await _filtrarPor(tester, TipoNotificacion.ticketRechazado);
      expect(_vacioFiltro, findsOneWidget);

      arnes.historial.llegaUno(
        aviso(
          'x1',
          tipo: TipoNotificacion.ticketRechazado,
          hace: Duration.zero,
          titulo: 'Tu ticket fue rechazado',
          conDestino: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(_vacioFiltro, findsNothing);
      expect(filaDe('x1'), findsOneWidget);
    });

    testWidgets('borrar los avisos del filtro (24C·03) deja el vacío del filtro, no el general', (
      tester,
    ) async {
      final arnes = _arnes();
      await _abrir(tester, arnes);
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuBorrarTodas);
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar las 2 notificaciones?'), findsOneWidget);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.borrados, [
        {'t1', 't2'},
      ]);
      expect(
        arnes.historial.filas.map((f) => f.id),
        unorderedEquals(['r1', 'p1', 'r2', 'c1', 'r3']),
      );
      expect(_vacioFiltro, findsOneWidget);
      expect(centroVacio, findsNothing);
      // Sin avisos que marcar ni borrar con este filtro, el menú no se ofrece.
      expect(centroMenu, findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('un doble toque en la fila abre una sola hoja', (tester) async {
      await _abrir(tester, _arnes());

      await tester.tap(_cambiar);
      await tester.tap(_cambiar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_hojaTitulo, findsOneWidget);
      await tester.tap(_listo);
      await tester.pumpAndSettle();
      // Una sola hoja: al cerrarla no queda otra debajo ni se sale de la pantalla.
      expect(_hojaTitulo, findsNothing);
      expect(centroPagina, findsOneWidget);
    });

    testWidgets('un doble toque en «Listo» cierra la hoja una sola vez y no saca la pantalla', (
      tester,
    ) async {
      await _abrir(tester, _arnes());
      await _abrirHoja(tester);
      await tester.tap(_opcion(TipoNotificacion.ticketValidado));
      await tester.pump();

      await tester.tap(_listo);
      await tester.tap(_listo, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(centroPagina, findsOneWidget);
      expect(find.byType(FilaNotificacion), findsNWidgets(2));
    });

    testWidgets('un toque afuera de la hoja la cierra sin abrir el menú, y al revés', (
      tester,
    ) async {
      await _abrir(tester, _arnes());

      // La hoja abierta tapa el «⋯»: un toque ahí cae sobre la barrera y la cierra, sin abrir el menú.
      await _abrirHoja(tester);
      await tester.tap(centroMenu, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(TextosFiltroTipoNotificacion.hojaTitulo), findsNothing);
      expect(menuBorrarTodas, findsNothing);

      // Con el menú abierto, la hoja del filtro no se abre encima.
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      expect(menuBorrarTodas, findsOneWidget);
      await tester.tap(_cambiar, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_hojaTitulo, findsNothing);
    });

    testWidgets(
      'falla a mitad de «Borrar todas» con filtro: sigue abierta, el botón vuelve a estar '
      'disponible y el filtro y los avisos no se tocan',
      (tester) async {
        final arnes = _arnes();
        arnes.historial.fallaAlBorrar = true;
        await _abrir(tester, arnes);
        await _filtrarPor(tester, TipoNotificacion.ticketValidado);

        await tester.tap(centroMenu);
        await tester.pumpAndSettle();
        await tester.tap(menuBorrarTodas);
        await tester.pumpAndSettle();
        await tester.tap(borrarConfirmar);
        await tester.pumpAndSettle();

        expect(borrarError, findsOneWidget);
        expect(tester.widget<FilledButton>(borrarConfirmar).onPressed, isNotNull);
        await tester.tap(borrarCancelar);
        await tester.pumpAndSettle();
        expect(find.descendant(of: _fila, matching: find.text('Ticket validado')), findsOneWidget);
        expect(arnes.historial.filas, hasLength(7));
        expect(find.byType(FilaNotificacion), findsNWidgets(2));
      },
    );

    testWidgets(
      'dos filtros seguidos, uno tras otro: el segundo reemplaza al primero sin pisar la lista',
      (tester) async {
        await _abrir(tester, _arnes());

        await _filtrarPor(tester, TipoNotificacion.ticketValidado);
        await _filtrarPor(tester, TipoNotificacion.cuotaPendiente);
        await _filtrarPor(tester, TipoNotificacion.recordatorioVisita);

        expect(find.byType(FilaNotificacion), findsNWidgets(3));
        for (final id in ['r1', 'r2', 'r3']) {
          expect(filaDe(id), findsOneWidget, reason: id);
        }
        expect(
          find.descendant(of: _fila, matching: find.text('Recordatorios de visita')),
          findsOneWidget,
        );
      },
    );

    testWidgets('«Quitar» dos veces seguidas es inocuo', (tester) async {
      await _abrir(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      await tester.tap(_quitar);
      await tester.tap(_quitar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(FilaNotificacion), findsNWidgets(7));
      expect(tester.takeException(), isNull);
    });

    testWidgets('el filtro puesto sobrevive a que un aviso se marque como leído o llegue otro', (
      tester,
    ) async {
      final arnes = _arnes();
      await _abrir(tester, arnes);
      await _filtrarPor(tester, TipoNotificacion.recordatorioVisita);

      await tester.tap(filaDe('r1'));
      await tester.pumpAndSettle();
      arnes.historial.llegaUno(
        aviso(
          'otro',
          tipo: TipoNotificacion.cuotaPendiente,
          hace: Duration.zero,
          conDestino: false,
        ),
      );
      arnes.historial.llegaUno(aviso('r4', hace: Duration.zero, titulo: 'Cobranza a las 17:00'));
      await tester.pumpAndSettle();

      expect(filaDe('otro'), findsNothing);
      expect(filaDe('r4'), findsOneWidget);
      expect(find.byType(FilaNotificacion), findsNWidgets(4));
    });

    testWidgets('volver atrás y reentrar: el filtro arranca otra vez en «Todos»', (tester) async {
      await _abrirDesdeHoy(tester, _arnes());
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);
      expect(find.byType(FilaNotificacion), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('centro_atras')));
      await tester.pumpAndSettle();
      expect(centroPagina, findsNothing);
      await tester.tap(find.byKey(const Key('ir_al_centro')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: _fila, matching: find.text('Todos')), findsOneWidget);
      expect(find.byType(FilaNotificacion), findsNWidgets(7));
    });

    testWidgets('«Marcar todas como leídas» con filtro activo marca y la lista se actualiza', (
      tester,
    ) async {
      final arnes = _arnes();
      await _abrir(tester, arnes);
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();

      expect(arnes.historial.llamadasMarcarTodas, 1);
      expect(find.text('Nueva'), findsNothing);
      expect(find.byType(FilaNotificacion), findsNWidgets(2));
    });

    testWidgets('60 avisos de un tipo y 60 de otro: el filtro los separa y se llega al último', (
      tester,
    ) async {
      final avisos = [
        for (var i = 0; i < 60; i++) ...[
          aviso('r-$i', hace: Duration(hours: i * 6 + 1)),
          aviso(
            't-$i',
            tipo: TipoNotificacion.ticketValidado,
            hace: Duration(hours: i * 6 + 2),
            conDestino: false,
          ),
        ],
      ];
      await _abrir(tester, CentroArnes(avisos: avisos));
      await _filtrarPor(tester, TipoNotificacion.ticketValidado);

      expect(find.byType(FilaNotificacion).evaluate().length, lessThan(30));
      await tester.scrollUntilVisible(
        filaDe('t-59'),
        600,
        scrollable: find.descendant(of: centroLista, matching: find.byType(Scrollable)),
        maxScrolls: 100,
      );
      expect(filaDe('t-59'), findsOneWidget);
      expect(filaDe('r-59'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    final tamanos = {'390x844': const Size(390, 844), '320x568': const Size(320, 568)};
    for (final MapEntry(key: nombre, value: tamano) in tamanos.entries) {
      for (final texto in [1.0, 2.0, 3.0]) {
        testWidgets(
          'a $nombre con el texto al $texto×: fila, hoja y vacío del filtro sin desbordes y con '
          'los botones a la vista',
          (tester) async {
            await abrirCentro(tester, _arnes(), tamano: tamano, texto: texto);
            expect(tester.takeException(), isNull);
            final alto = tester.view.physicalSize.height;

            await tester.tap(_cambiar);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(_opcion(TipoNotificacion.cuotaPendiente));
            await tester.tap(_opcion(TipoNotificacion.cuotaPendiente));
            await tester.pump();
            await tester.ensureVisible(_listo);
            await tester.pump();
            expect(tester.getBottomLeft(_listo).dy, lessThanOrEqualTo(alto));
            await tester.tap(_listo);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(_quitar, findsOneWidget);
            expect(tester.getSize(_quitar).height, greaterThanOrEqualTo(48));

            await tester.ensureVisible(_quitar);
            await tester.tap(_quitar);
            await tester.pumpAndSettle();
            // La lista entera es larga con el texto grande: se vuelve arriba, donde está la fila.
            for (var i = 0; i < 4; i++) {
              await tester.drag(centroLista, const Offset(0, 3000));
              await tester.pumpAndSettle();
            }
            await _filtrarPor(tester, TipoNotificacion.ticketRechazado);
            expect(tester.takeException(), isNull);
            // Con el texto grande el vacío queda debajo de la fila: la lista es perezosa y se baja.
            await tester.scrollUntilVisible(
              _verTodos,
              200,
              scrollable: find.descendant(of: centroLista, matching: find.byType(Scrollable)),
            );
            await tester.pump();
            expect(_vacioFiltro, findsOneWidget);
            expect(tester.getBottomLeft(_verTodos).dy, lessThanOrEqualTo(alto));
          },
        );
      }
    }
  });
}
