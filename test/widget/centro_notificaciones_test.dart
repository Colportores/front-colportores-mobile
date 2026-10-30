// El centro de notificaciones (vista 24, grupo C, HU-NOT-005, #156): 24C·01 a 24C·07 y los casos
// límite de cada flujo. El historial es el repositorio en memoria de
// `historial_notificaciones_falsos.dart` (con puertas para detener cada operación a mitad).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/fila_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/textos_centro_notificaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';

/// Cinco avisos en cuatro días distintos, los tres de arriba sin leer.
List<dynamic> _cinco() => [
  aviso('a'),
  aviso('b', hace: const Duration(hours: 5), titulo: 'Entrevista a las 11:30', leida: true),
  aviso(
    'c',
    hace: const Duration(hours: 26),
    titulo: 'Cobranza a las 14:30',
    detalle: 'Grecia 3310',
  ),
  aviso('d', hace: const Duration(days: 3), titulo: 'Entrevista a las 10:00', detalle: null),
  aviso('e', hace: const Duration(days: 10), leida: true),
];

CentroArnes _arnesConCinco() => CentroArnes(avisos: _cinco().cast());

/// La pantalla de Hoy con un botón que abre el centro: para volver atrás y reentrar.
Future<void> _abrirDesdeHoy(WidgetTester tester, CentroArnes arnes) async {
  tester.view
    ..physicalSize = const Size(390, 844)
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

Future<void> _abrirMenu(WidgetTester tester) async {
  await tester.tap(centroMenu);
  await tester.pumpAndSettle();
}

Future<void> _abrirConfirmacion(WidgetTester tester) async {
  await _abrirMenu(tester);
  await tester.tap(menuBorrarTodas);
  await tester.pumpAndSettle();
}

double _arriba(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  group('24C·01 Centro con no leídas', () {
    testWidgets(
      'dado cinco avisos en varios días, cuando abro el centro, los veo de más nuevo a más '
      'viejo, con el rótulo de cada día',
      (tester) async {
        await abrirCentro(tester, _arnesConCinco());

        expect(centroPagina, findsOneWidget);
        expect(find.text(TextosCentroNotificaciones.rotulo), findsOneWidget);
        expect(find.text('Notificaciones'), findsOneWidget);
        expect(find.text('HOY'), findsOneWidget);
        expect(find.text('AYER'), findsOneWidget);
        expect(find.text('MARTES 20'), findsOneWidget);
        expect(find.text('13 DE OCTUBRE'), findsOneWidget);
        final orden = [
          for (final id in ['a', 'b', 'c', 'd', 'e']) _arriba(tester, filaDe(id)),
        ];
        expect(orden, orderedEquals([...orden]..sort()));
        expect(_arriba(tester, find.text('HOY')), lessThan(orden[0]));
        expect(_arriba(tester, find.text('AYER')), inInclusiveRange(orden[1], orden[2]));
      },
    );

    testWidgets('las que no leí tienen el indicador «Nueva»; las leídas, no', (tester) async {
      await abrirCentro(tester, _arnesConCinco());

      expect(find.text('Nueva'), findsNWidgets(3));
      for (final id in ['a', 'c', 'd']) {
        expect(find.descendant(of: filaDe(id), matching: find.text('Nueva')), findsOneWidget);
      }
      for (final id in ['b', 'e']) {
        expect(find.descendant(of: filaDe(id), matching: find.text('Nueva')), findsNothing);
      }
    });

    testWidgets('cada aviso muestra la hora, el título y la dirección; sin dirección, no inventa '
        'nada', (tester) async {
      await abrirCentro(tester, _arnesConCinco());

      expect(find.descendant(of: filaDe('a'), matching: find.text('15:30')), findsOneWidget);
      expect(
        find.descendant(of: filaDe('a'), matching: find.text('Cobranza a las 16:00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: filaDe('a'), matching: find.text('Av. Italia 2810')),
        findsOneWidget,
      );
      // Hora, título y «Nueva»: sin segunda línea no hay un hueco ni un texto inventado.
      expect(find.descendant(of: filaDe('d'), matching: find.byType(Text)), findsNWidgets(3));
    });

    testWidgets('para el lector de pantalla cada aviso es un botón que lo dice todo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrirCentro(tester, _arnesConCinco());

      final sinLeer = tester.getSemantics(filaDe('a'));
      expect(sinLeer.label, 'Nueva. 15:30. Cobranza a las 16:00. Av. Italia 2810');
      expect(sinLeer.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final leida = tester.getSemantics(filaDe('b'));
      expect(leida.label, '11:10. Entrevista a las 11:30. Av. Italia 2810');
      semantica.dispose();
    });

    testWidgets('el rótulo del día es un encabezado y el título de la pantalla también', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrirCentro(tester, _arnesConCinco());

      expect(
        tester.getSemantics(find.text('HOY')).getSemanticsData().flagsCollection.isHeader,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.text('Notificaciones'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      semantica.dispose();
    });

    testWidgets('un aviso que llega con el centro abierto aparece arriba sin recargar', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      arnes.historial.llegaUno(
        aviso('nuevo', hace: Duration.zero, titulo: 'Entrevista a las 17:00'),
      );
      await tester.pumpAndSettle();

      expect(_arriba(tester, filaDe('nuevo')), lessThan(_arriba(tester, filaDe('a'))));
    });
  });

  group('tocar un aviso (R-NO05)', () {
    testWidgets('lo marca como leído y abre el mismo destino que la notificación original', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();

      expect(arnes.historial.marcadas, ['a']);
      expect(arnes.abridor.abiertos, [const DestinoAgenda('agenda-a')]);
      expect(find.descendant(of: filaDe('a'), matching: find.text('Nueva')), findsNothing);
      expect(find.text('Nueva'), findsNWidgets(2));
    });

    testWidgets('uno que ya estaba leído se abre sin volver a marcarlo', (tester) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('b'));
      await tester.pumpAndSettle();

      expect(arnes.historial.marcadas, isEmpty);
      expect(arnes.abridor.abiertos, [const DestinoAgenda('agenda-b')]);
    });

    testWidgets('un doble toque abre una sola vez', (tester) async {
      final arnes = _arnesConCinco();
      arnes.abridor.puerta = Completer<void>();
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
      arnes.abridor.puerta!.complete();
      await tester.pumpAndSettle();

      expect(arnes.abridor.abiertos, hasLength(1));
      expect(arnes.historial.marcadas, ['a']);
    });

    testWidgets(
      'dos avisos tocados seguidos, antes de que termine el primero: se abre el primero y '
      'el segundo no se pierde ni se pisa',
      (tester) async {
        final arnes = _arnesConCinco();
        arnes.historial.puertaAlMarcar = Completer<void>();
        await abrirCentro(tester, arnes);

        await tester.tap(filaDe('a'));
        await tester.pump();
        await tester.tap(filaDe('c'));
        await tester.pump();
        arnes.historial.puertaAlMarcar!.complete();
        await tester.pumpAndSettle();

        expect(arnes.abridor.abiertos, [const DestinoAgenda('agenda-a')]);
        expect(arnes.historial.marcadas, ['a']);
        expect(find.descendant(of: filaDe('c'), matching: find.text('Nueva')), findsOneWidget);

        await tester.tap(filaDe('c'));
        await tester.pumpAndSettle();
        expect(arnes.abridor.abiertos.last, const DestinoAgenda('agenda-c'));
      },
    );

    testWidgets('un aviso sin destino se marca como leído y no abre nada ni avisa', (tester) async {
      final arnes = CentroArnes(avisos: [aviso('sin', conDestino: false)]);
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('sin'));
      await tester.pumpAndSettle();

      expect(arnes.historial.marcadas, ['sin']);
      expect(arnes.abridor.abiertos, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('si no se puede marcar como leído, igual se abre y sigue como «Nueva»', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      arnes.historial.fallaAlMarcar = true;
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();

      expect(arnes.abridor.abiertos, [const DestinoAgenda('agenda-a')]);
      expect(find.descendant(of: filaDe('a'), matching: find.text('Nueva')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('volver atrás y reentrar: lo leído sigue leído y no se duplica nada', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      await _abrirDesdeHoy(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('centro_atras')));
      await tester.pumpAndSettle();
      expect(centroPagina, findsNothing);
      await tester.tap(find.byKey(const Key('ir_al_centro')));
      await tester.pumpAndSettle();

      expect(centroPagina, findsOneWidget);
      expect(find.byType(FilaNotificacion), findsNWidgets(5));
      expect(find.text('Nueva'), findsNWidgets(2));
      expect(arnes.historial.marcadas, ['a']);
    });
  });

  group('24C·07 El detalle ya no existe', () {
    testWidgets('la lista queda abierta, el aviso se marca como leído y se explica', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      arnes.destinos.inexistentes.add(const DestinoAgenda('agenda-a'));
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();

      expect(find.text('Esa agenda ya no está: se canceló o se borró.'), findsOneWidget);
      expect(centroLista, findsOneWidget);
      expect(arnes.abridor.abiertos, isEmpty);
      expect(arnes.historial.marcadas, ['a']);
      expect(filaDe('a'), findsOneWidget);
    });

    testWidgets('el aviso no desaparece: se puede volver a tocar y vuelve a explicarlo', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      arnes.destinos.inexistentes.add(const DestinoAgenda('agenda-a'));
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();

      expect(find.text('Esa agenda ya no está: se canceló o se borró.'), findsOneWidget);
      expect(arnes.destinos.consultados, hasLength(2));
    });

    testWidgets('si no se puede saber si existe, lo dice con qué hacer y se puede reintentar', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      arnes.destinos.falla = true;
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos abrir ese aviso. Probá de nuevo.'), findsOneWidget);
      expect(arnes.abridor.abiertos, isEmpty);

      arnes.destinos.falla = false;
      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
      expect(arnes.abridor.abiertos, [const DestinoAgenda('agenda-a')]);
    });

    testWidgets('si el destino falla al abrirse, avisa y no deja el aviso trabado', (tester) async {
      final arnes = _arnesConCinco();
      arnes.abridor.falla = StateError('no abre');
      await abrirCentro(tester, arnes);

      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
      expect(find.text('No pudimos abrir ese aviso. Probá de nuevo.'), findsOneWidget);

      arnes.abridor.falla = null;
      await tester.tap(filaDe('c'));
      await tester.pumpAndSettle();
      expect(arnes.abridor.abiertos.last, const DestinoAgenda('agenda-c'));
    });
  });

  group('24C·02 Menú: marcar y borrar', () {
    testWidgets('el «⋯» abre el menú con las dos acciones y «Cerrar»', (tester) async {
      await abrirCentro(tester, _arnesConCinco());

      await _abrirMenu(tester);

      expect(find.text('Marcar todas como leídas'), findsOneWidget);
      expect(find.text('Borrar todas'), findsOneWidget);
      expect(menuCerrar, findsOneWidget);

      await tester.tap(menuCerrar);
      await tester.pumpAndSettle();
      expect(menuMarcarTodas, findsNothing);
      expect(centroPagina, findsOneWidget);
    });

    testWidgets('«Marcar todas como leídas» deja todas leídas y lo anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await _abrirMenu(tester);
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();

      expect(find.text('Nueva'), findsNothing);
      expect(arnes.historial.filas.every((n) => n.leida), isTrue);
      expect(tester.takeAnnouncements().map((a) => a.message), [
        'Todas las notificaciones quedaron como leídas.',
      ]);
      semantica.dispose();
    });

    testWidgets('un doble toque en «Marcar todas» marca una vez y no cierra la pantalla', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await _abrirMenu(tester);
      await tester.tap(menuMarcarTodas);
      await tester.tap(menuMarcarTodas, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(arnes.historial.llamadasMarcarTodas, 1);
      expect(centroPagina, findsOneWidget);
    });

    testWidgets('si falla, dice qué hacer, nada queda marcado y el menú se puede volver a usar', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      arnes.historial.fallaAlMarcarTodas = true;
      await abrirCentro(tester, arnes);

      await _abrirMenu(tester);
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();
      expect(
        find.text('No pudimos marcar las notificaciones como leídas. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Nueva'), findsNWidgets(3));

      arnes.historial.fallaAlMarcarTodas = false;
      await _abrirMenu(tester);
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();
      expect(find.text('Nueva'), findsNothing);
    });

    testWidgets('sin avisos sin leer, «Marcar todas» está apagada y dice por qué', (tester) async {
      final semantica = tester.ensureSemantics();
      final arnes = CentroArnes(avisos: [aviso('a', leida: true)]);
      await abrirCentro(tester, arnes);

      await _abrirMenu(tester);
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();

      expect(find.text('No hay notificaciones sin leer'), findsOneWidget);
      expect(arnes.historial.llamadasMarcarTodas, 0);
      expect(menuMarcarTodas, findsOneWidget, reason: 'el menú sigue abierto');
      expect(
        tester.getSemantics(menuMarcarTodas).label,
        contains('No hay notificaciones sin leer'),
      );
      semantica.dispose();
    });

    testWidgets('llegar un aviso con el menú abierto no rompe nada', (tester) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await _abrirMenu(tester);
      arnes.historial.llegaUno(aviso('nuevo', hace: Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();

      expect(find.text('Nueva'), findsNothing);
    });
  });

  group('24C·03 Confirmar borrar todas', () {
    testWidgets('pregunta con la cantidad y explica que lo avisado no cambia', (tester) async {
      await abrirCentro(tester, _arnesConCinco());

      await _abrirConfirmacion(tester);

      expect(find.text('¿Borrar las 5 notificaciones?'), findsOneWidget);
      expect(
        find.text(
          'Se borran de este teléfono. Lo que avisaban (agendas, pedidos, tickets) no cambia.',
        ),
        findsOneWidget,
      );
      expect(borrarConfirmar, findsOneWidget);
      expect(borrarCancelar, findsOneWidget);
    });

    testWidgets('con una sola, la pregunta va en singular', (tester) async {
      await abrirCentro(tester, CentroArnes(avisos: [aviso('a')]));

      await _abrirConfirmacion(tester);

      expect(find.text('¿Borrar la notificación?'), findsOneWidget);
    });

    testWidgets('«Cancelar» no borra nada', (tester) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await _abrirConfirmacion(tester);
      await tester.tap(borrarCancelar);
      await tester.pumpAndSettle();

      expect(borrarTitulo, findsNothing);
      expect(arnes.historial.filas, hasLength(5));
      expect(arnes.historial.borrados, isEmpty);
    });

    testWidgets('«Borrar todas» deja la tabla vacía y muestra el estado vacío, sin el «⋯»', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await _abrirConfirmacion(tester);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.filas, isEmpty);
      expect(centroVacio, findsOneWidget);
      expect(centroMenu, findsNothing);
      expect(tester.takeAnnouncements().map((a) => a.message), ['Se borraron las notificaciones.']);
      semantica.dispose();
    });

    testWidgets('un doble toque en «Borrar todas» borra una sola vez; mientras borra no se puede '
        'cancelar ni salir', (tester) async {
      final arnes = _arnesConCinco();
      arnes.historial.puertaAlBorrar = Completer<void>();
      await abrirCentro(tester, arnes);

      await _abrirConfirmacion(tester);
      await tester.tap(borrarConfirmar);
      await tester.tap(borrarConfirmar);
      await tester.pump();

      expect(arnes.historial.borrados, hasLength(1));
      expect(tester.widget<OutlinedButton>(borrarCancelar).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(borrarTitulo, findsOneWidget, reason: 'atrás del sistema no cierra mientras borra');

      arnes.historial.puertaAlBorrar!.complete();
      await tester.pumpAndSettle();
      expect(arnes.historial.borrados, hasLength(1));
      expect(centroVacio, findsOneWidget);
    });

    testWidgets('si falla, la hoja sigue abierta con qué hacer, y «Borrar todas» vuelve a estar '
        'disponible', (tester) async {
      final arnes = _arnesConCinco();
      arnes.historial.fallaAlBorrar = true;
      await abrirCentro(tester, arnes);

      await _abrirConfirmacion(tester);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(borrarError, findsOneWidget);
      expect(find.text('No pudimos borrar las notificaciones. Probá de nuevo.'), findsOneWidget);
      expect(arnes.historial.filas, hasLength(5));
      expect(tester.widget<FilledButton>(borrarConfirmar).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(borrarCancelar).onPressed, isNotNull);

      arnes.historial.fallaAlBorrar = false;
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();
      expect(borrarTitulo, findsNothing);
      expect(centroVacio, findsOneWidget);
    });

    testWidgets('lo que llega con la confirmación abierta no se borra: no estaba en la cuenta', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      await abrirCentro(tester, arnes);

      await _abrirConfirmacion(tester);
      arnes.historial.llegaUno(aviso('nuevo', hace: -const Duration(minutes: 1)));
      await tester.pump();
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.filas.map((n) => n.id), ['nuevo']);
      expect(arnes.historial.borrados, [ahoraDelCentro]);
      expect(filaDe('nuevo'), findsOneWidget);
      expect(centroVacio, findsNothing);
    });

    testWidgets('«Cancelar» dos veces seguidas no saca también la pantalla', (tester) async {
      await abrirCentro(tester, _arnesConCinco());

      await _abrirConfirmacion(tester);
      await tester.tap(borrarCancelar);
      await tester.tap(borrarCancelar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(centroPagina, findsOneWidget);
    });
  });

  group('24C·04, 24C·05 y 24C·06 Vacío, cargando y error', () {
    testWidgets('24C·04 sin avisos: dice qué se ve acá y no ofrece el «⋯»', (tester) async {
      await abrirCentro(tester, CentroArnes());

      expect(centroVacio, findsOneWidget);
      expect(find.text('No tenés notificaciones'), findsOneWidget);
      expect(find.text('Acá ves los avisos de los últimos 90 días.'), findsOneWidget);
      expect(centroMenu, findsNothing);
      expect(centroLista, findsNothing);
    });

    testWidgets('24C·05 cargando: bloques en lugar de la lista, sin el «⋯», y después la lista', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final arnes = _arnesConCinco();
      arnes.historial.puertaAlObservar = Completer<void>();
      await abrirCentro(tester, arnes, esperar: false);

      expect(centroCargando, findsOneWidget);
      expect(tester.getSemantics(centroCargando).label, 'Cargando tus notificaciones');
      expect(centroMenu, findsNothing);
      expect(centroVacio, findsNothing);

      arnes.historial.puertaAlObservar!.complete();
      await tester.pumpAndSettle();
      expect(centroCargando, findsNothing);
      expect(centroLista, findsOneWidget);
      semantica.dispose();
    });

    testWidgets(
      '24C·06 error al leer: lo dice con «Reintentar», sin el «⋯»; reintentar vuelve a leer',
      (tester) async {
        final arnes = _arnesConCinco();
        arnes.historial.errorAlObservar = StateError('no se puede leer');
        await abrirCentro(tester, arnes);

        expect(centroError, findsOneWidget);
        expect(find.text('No pudimos leer tus notificaciones.'), findsOneWidget);
        expect(centroMenu, findsNothing);

        arnes.historial.errorAlObservar = null;
        await tester.tap(centroReintentar);
        await tester.pumpAndSettle();

        expect(centroError, findsNothing);
        expect(centroLista, findsOneWidget);
        expect(find.byType(FilaNotificacion), findsNWidgets(5));
      },
    );

    testWidgets('si el reintento vuelve a fallar, sigue el aviso y se puede volver a intentar', (
      tester,
    ) async {
      final arnes = _arnesConCinco();
      arnes.historial.errorAlObservar = StateError('no se puede leer');
      await abrirCentro(tester, arnes);

      await tester.tap(centroReintentar);
      await tester.pumpAndSettle();
      expect(centroError, findsOneWidget);

      arnes.historial.errorAlObservar = null;
      await tester.tap(centroReintentar);
      await tester.pumpAndSettle();
      expect(centroLista, findsOneWidget);
    });

    testWidgets('sin la base abierta, el centro muestra el error y no se cae', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: temaClaro(), home: const CentroNotificacionesPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(centroError, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('datos límite', () {
    testWidgets('300 avisos: la lista se construye perezosa y se llega hasta el último', (
      tester,
    ) async {
      final avisos = [
        for (var i = 0; i < 300; i++) aviso('n-$i', hace: Duration(hours: i * 6 + 1)),
      ];
      await abrirCentro(tester, CentroArnes(avisos: avisos));

      expect(find.byType(FilaNotificacion).evaluate().length, lessThan(30));
      await tester.scrollUntilVisible(
        filaDe('n-299'),
        600,
        scrollable: find.descendant(of: centroLista, matching: find.byType(Scrollable)),
        maxScrolls: 200,
      );
      expect(filaDe('n-299'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el mismo instante en dos avisos: salen los dos, siempre en el mismo orden', (
      tester,
    ) async {
      final arnes = CentroArnes(
        avisos: [
          aviso('x', hace: const Duration(hours: 1)),
          aviso('y', hace: const Duration(hours: 1)),
        ],
      );
      await abrirCentro(tester, arnes);

      expect(_arriba(tester, filaDe('y')), lessThan(_arriba(tester, filaDe('x'))));
    });

    final tamanos = {'390x844': const Size(390, 844), '320x568': const Size(320, 568)};
    for (final MapEntry(key: nombre, value: tamano) in tamanos.entries) {
      for (final texto in [1.0, 2.0, 3.0]) {
        testWidgets(
          'textos largos a $nombre con el texto al $texto×: lista, menú y confirmación sin '
          'desbordes',
          (tester) async {
            final largo = 'Entrevista con una dirección larguísima ' * 3;
            final arnes = CentroArnes(
              avisos: [
                aviso(
                  'a',
                  titulo: largo,
                  detalle: 'Avenida Doctor Luis Alberto de Herrera 1234 apto 1001 ' * 3,
                ),
                aviso(
                  'b',
                  hace: const Duration(hours: 3),
                  titulo: 'Palabra${'Interminable' * 12}',
                  detalle: null,
                ),
                aviso('c', hace: const Duration(hours: 30), leida: true),
              ],
            );
            await abrirCentro(tester, arnes, tamano: tamano, texto: texto);
            expect(tester.takeException(), isNull);

            await tester.tap(centroMenu);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(menuBorrarTodas);
            await tester.tap(menuBorrarTodas);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(borrarConfirmar, findsOneWidget);
            await tester.ensureVisible(borrarConfirmar);
            final alto = tester.view.physicalSize.height;
            expect(tester.getBottomLeft(borrarConfirmar).dy, lessThanOrEqualTo(alto));
          },
        );
      }
    }
  });

  group('accesibilidad', () {
    testWidgets('los toques miden lo mínimo, tienen nombre y el texto contrasta', (tester) async {
      final semantica = tester.ensureSemantics();
      await abrirCentro(tester, _arnesConCinco());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('las hojas también cumplen las guías', (tester) async {
      final semantica = tester.ensureSemantics();
      await abrirCentro(tester, _arnesConCinco());

      await _abrirMenu(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(menuBorrarTodas);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });
  });

  group('rótulo del día', () {
    testWidgets('un aviso de las 23:50 de ayer es de ayer aunque hayan pasado 16 horas', (
      tester,
    ) async {
      final arnes = CentroArnes(
        avisos: [aviso('tarde', hace: const Duration(hours: 16, minutes: 20))],
      );
      await abrirCentro(tester, arnes);

      expect(find.text('AYER'), findsOneWidget);
      expect(find.text('HOY'), findsNothing);
    });

    testWidgets('un aviso de las 00:05 de hoy es de hoy aunque hayan pasado 16 horas', (
      tester,
    ) async {
      final arnes = CentroArnes(avisos: [aviso('madrugada', hace: const Duration(hours: 16))]);
      await abrirCentro(tester, arnes);

      expect(find.text('HOY'), findsOneWidget);
    });
  });
}
