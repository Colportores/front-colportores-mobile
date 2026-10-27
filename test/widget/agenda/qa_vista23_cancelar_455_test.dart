// QA de «Cancelar una agenda» (vista 23 C, 23C·04 y 23C·05, HU-VIS-004, #455), encima de la
// implementación: el flujo completo (lista real → detalle real → hoja → lista), los diez estados que
// una persona puede alcanzar en 360x640 y 412x915 con texto 1,0 y 2,0, los casos límite de cada flujo
// y lo que lee un lector de pantalla. Los hallazgos viven como tests con `skip` (se corren con
// `--dart-define=QA_HALLAZGOS=true`); las capturas, con `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/qa_vista23_455_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  group('Matriz de estados × tamaños × texto', () {
    for (final tamano in [chico455, grande455]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado455.values) {
          final sufijo = sufijo455(tamano, escala);

          testWidgets('${estado.rotulo} · $sufijo · sin desborde ni texto cortado', (tester) async {
            await llegarA455(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            sinTextoCortado455(tester);
            await capturar455(tester, '${estado.archivo}_$sufijo');
            await desmontar455(tester);
          });

          if (estado.conHoja) {
            testWidgets('${estado.rotulo} · $sufijo · la hoja cabe y sus dos botones se alcanzan', (
              tester,
            ) async {
              await llegarA455(tester, estado, tamano: tamano, escala: escala);
              final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
              final r = tester.getRect(hoja455);
              expect(r.top, greaterThanOrEqualTo(0));
              expect(r.bottom, lessThanOrEqualTo(pantalla.height));
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(pantalla.width));
              // Los botones están a la vista sin desplazar nada (están fuera de la zona que se mueve).
              if (confirmar455.evaluate().isNotEmpty) {
                expect(tester.getRect(confirmar455).bottom, lessThanOrEqualTo(pantalla.height));
              }
              expect(tester.getRect(volver455).bottom, lessThanOrEqualTo(pantalla.height));
              await desmontar455(tester);
            });
          }

          if (estado == Estado455.h07Error || estado == Estado455.h06YaNoSePuede) {
            // skip: QA #455 — el aviso rojo va dentro de la zona que se desplaza, debajo del cuerpo: a
            // 360x640 con texto 2,0 queda fuera de la vista y la persona no ve por qué no se canceló.
            testWidgets(
              '${estado.rotulo} · $sufijo · el aviso se ve sin desplazar',
              (tester) async {
                await llegarA455(tester, estado, tamano: tamano, escala: escala);
                final aviso = find.text(
                  estado == Estado455.h07Error ? errorAlGuardar455 : yaNoSePuede455,
                );
                expect(aviso, findsOneWidget);
                final visible = tester.getRect(zonaDeLaHoja455);
                final r = tester.getRect(aviso);
                expect(
                  r.top >= visible.top - 0.5 && r.bottom <= visible.bottom + 0.5,
                  isTrue,
                  reason:
                      'aviso en ${r.top}–${r.bottom}, zona visible ${visible.top}–${visible.bottom}',
                );
                await desmontar455(tester);
              },
              skip: tamano == chico455 && escala == 2.0 ? !_verHallazgos : false,
            );
          }
        }
      }
    }
  });

  group('Literales de la HU y del canvas', () {
    testWidgets('23C·04 entrevista: título y cuerpo del canvas, botón rojo y «Volver»', (
      tester,
    ) async {
      await llegarA455(tester, Estado455.h04Entrevista);
      expect(find.text(tituloEntrevista455), findsOneWidget);
      expect(find.text(cuerpoEntrevista455), findsOneWidget);
      expect(find.descendant(of: confirmar455, matching: find.text('Cancelar agenda')), findsOne);
      expect(find.descendant(of: volver455, matching: find.text('Volver')), findsOneWidget);
      await desmontar455(tester);
    });

    testWidgets('23C·04 cobranza: no promete que la casa vuelve a su estado (no la pinta)', (
      tester,
    ) async {
      await llegarA455(tester, Estado455.h04Cobranza);
      expect(find.text(tituloCobranza455), findsOneWidget);
      expect(find.text(cuerpoCobranza455), findsOneWidget);
      expect(find.textContaining('casa vuelve'), findsNothing);
      await desmontar455(tester);
    });

    testWidgets('23C·05: «Agenda cancelada.» exacto, sin punto de más ni "Deshacer"', (
      tester,
    ) async {
      await llegarA455(tester, Estado455.l05Cancelada);
      expect(find.text(canceladaOk455), findsOneWidget);
      expect(find.text('Deshacer'), findsNothing);
      await desmontar455(tester);
    });

    testWidgets('error: el aviso es el de 23C·07 y el botón dice «Reintentar»', (tester) async {
      await llegarA455(tester, Estado455.h07Error);
      expect(find.text(errorAlGuardar455), findsOneWidget);
      expect(find.descendant(of: confirmar455, matching: find.text('Reintentar')), findsOneWidget);
      expect(find.descendant(of: volver455, matching: find.text('Volver')), findsOneWidget);
      await desmontar455(tester);
    });

    testWidgets('«Cancelando…»: botón apagado, «Volver» apagado y spinner con contexto', (
      tester,
    ) async {
      await llegarA455(tester, Estado455.h04Cancelando);
      expect(find.text('Cancelando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirmar455).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(volver455).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await desmontar455(tester);
    });
  });

  group('Casos límite del flujo', () {
    testWidgets('dos fallas seguidas y después éxito: cada vez el botón vuelve a tocarse', (
      tester,
    ) async {
      final m = await montar455(tester);
      m.repo.fallasAlCancelar.addAll(const [FailureInesperado(), FailureInesperado()]);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      expect(find.text(errorAlGuardar455), findsOneWidget);
      expect(tester.widget<FilledButton>(confirmar455).onPressed, isNotNull);
      await confirmar455Tocar(tester);
      expect(find.text(errorAlGuardar455), findsOneWidget);
      expect(tester.widget<FilledButton>(confirmar455).onPressed, isNotNull);
      await confirmar455Tocar(tester);
      expect(m.repo.canceladas, ['ag-1', 'ag-1', 'ag-1']);
      expect(find.text(canceladaOk455), findsOneWidget);
      expect(detalle455, findsNothing);
      await desmontar455(tester);
    });

    testWidgets('falla, «Volver» y abrir otra vez: la hoja nueva dice «Cancelar agenda», no '
        '«Reintentar»', (tester) async {
      final m = await montar455(tester);
      m.repo.fallasAlCancelar.add(const FailureInesperado());
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      await tester.tap(volver455);
      await asentarDetalle(tester);

      await abrirHoja455(tester);

      expect(find.descendant(of: confirmar455, matching: find.text('Cancelar agenda')), findsOne);
      expect(find.text('Reintentar'), findsNothing);
      await desmontar455(tester);
    });

    testWidgets('la falla que lanza una excepción en el reintento tampoco deja «Cancelando…»', (
      tester,
    ) async {
      final m = await montar455(tester);
      m.repo.fallasAlCancelar.add(const FailureInesperado());
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      m.repo.lanzarAlCancelar = StateError('se cayó');

      await confirmar455Tocar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Cancelando…'), findsNothing);
      expect(find.text(errorAlGuardar455), findsOneWidget);
      expect(tester.widget<FilledButton>(confirmar455).onPressed, isNotNull);
      await desmontar455(tester);
    });

    testWidgets('cancelar una agenda y enseguida la siguiente: el aviso es uno solo y no se '
        'pisa ninguna cancelación', (tester) async {
      final ahora = ahoraDelDetalle();
      final m = await montar455(tester, entrar: false);
      final dos = [
        ...filas455(TipoAgenda.entrevista, EstadoAgenda.programada, ahora),
        ...filas455(
          TipoAgenda.entrevista,
          EstadoAgenda.programada,
          ahora,
          id: 'ag-2',
          nombre: 'Luis',
          apellido: 'Pérez',
        ),
      ];
      m.consulta.emitir(dos);
      var quedan = dos;
      m.repo.alCancelarAgenda = (c) {
        quedan = quedan.where((i) => i.agenda.id != c.id).toList();
        m.consulta.emitir(quedan);
      };
      await asentarDetalle(tester);

      await entrar455(tester);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      expect(find.text(canceladaOk455), findsOneWidget);

      // Segunda agenda: el repo devuelve el detalle de la que pide.
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(id: 'ag-2'));
      await tester.tap(find.text('Luis Pérez'));
      await asentarDetalle(tester);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);

      expect(m.repo.canceladas, ['ag-1', 'ag-2']);
      expect(find.text(canceladaOk455), findsOneWidget);
      expect(find.text('Luis Pérez'), findsNothing);
      expect(find.text('María Fernández'), findsNothing);
      await desmontar455(tester);
    });

    testWidgets('el aviso «Agenda cancelada.» se va solo a los 4 s y el del recordatorio '
        'que quedó, a los 8 s', (tester) async {
      await montar455(tester);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      expect(find.text(canceladaOk455), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(canceladaOk455), findsNothing);
      await desmontar455(tester);

      await montar455(tester, recordatorioSeQueda: true);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      expect(find.text(canceladaSinAviso455), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(canceladaSinAviso455), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(canceladaSinAviso455), findsNothing);
      await desmontar455(tester);
    });

    testWidgets('el detalle abierto como única ruta (desde un recordatorio en frío): al '
        'cancelar queda cancelado, con el aviso, sin salidas y sin errores', (tester) async {
      final m = await montar455(tester, detalleSolo: true);
      expect(detalle455, findsOneWidget);

      await abrirHoja455(tester);
      await confirmar455Tocar(tester);

      expect(tester.takeException(), isNull);
      expect(m.repo.canceladas, ['ag-1']);
      expect(detalle455, findsOneWidget);
      expect(hoja455, findsNothing);
      expect(find.text(canceladaOk455), findsOneWidget);
      expect(find.text('Esta agenda está cancelada: no se puede modificar.'), findsOneWidget);
      expect(find.text('Cancelar agenda'), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
      await desmontar455(tester);
    });

    testWidgets('volver con la flecha del detalle apenas termina de cancelar no rompe nada', (
      tester,
    ) async {
      final m = await montar455(tester);
      m.repo.compuertaAlCancelar = Completer<void>();
      await abrirHoja455(tester);
      await tester.tap(confirmar455);
      await tester.pump();

      m.repo.compuertaAlCancelar!.complete();
      await tester.pump();
      // La flecha del detalle (ya se está cerrando) puede tocarse en el mismo fotograma.
      await tester.tap(find.byKey(ClavesDetalleAgenda.volver), warnIfMissed: false);
      await asentarDetalle(tester);

      expect(tester.takeException(), isNull);
      expect(m.repo.canceladas, ['ag-1']);
      expect(detalle455, findsNothing);
      await desmontar455(tester);
    });

    testWidgets('el toque afuera de la hoja la cierra sin cancelar, pero no mientras se cancela', (
      tester,
    ) async {
      final m = await montar455(tester, tamano: grande455);
      await abrirHoja455(tester);
      await tester.tapAt(const Offset(200, 60));
      await asentarDetalle(tester);
      expect(hoja455, findsNothing);
      expect(m.repo.canceladas, isEmpty);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);

      m.repo.compuertaAlCancelar = Completer<void>();
      await abrirHoja455(tester);
      await tester.tap(confirmar455);
      await tester.pump();
      await tester.tapAt(const Offset(200, 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hoja455, findsOneWidget);
      expect(find.text('Cancelando…'), findsOneWidget);

      m.repo.compuertaAlCancelar!.complete();
      await asentarDetalle(tester);
      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(canceladaOk455), findsOneWidget);
      await desmontar455(tester);
    });

    testWidgets('el detalle sin franja ni nota también ofrece cancelar', (tester) async {
      final m = await montar455(tester, entrar: false);
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(slot: null));
      await entrar455(tester);
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      expect(m.repo.canceladas, ['ag-1']);
      await desmontar455(tester);
    });

    testWidgets('una agenda ya cancelada desde otra pantalla: la hoja lo dice y no reintenta', (
      tester,
    ) async {
      final m = await montar455(tester);
      await abrirHoja455(tester);
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.cancelada));
      m.repo.fallasAlCancelar.add(const FailureValidacion(campos: {'agenda': yaNoSePuede455}));
      await confirmar455Tocar(tester);

      expect(find.text(yaNoSePuede455), findsOneWidget);
      expect(confirmar455, findsNothing);
      await tester.tap(volver455);
      await asentarDetalle(tester);
      expect(find.text('Esta agenda está cancelada: no se puede modificar.'), findsOneWidget);
      await desmontar455(tester);
    });
  });

  group('Lector de pantalla', () {
    testWidgets('el aviso de error de la hoja es una región viva (se anuncia solo)', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA455(tester, Estado455.h07Error);
      final nodo = tester.getSemantics(find.text(errorAlGuardar455));
      var n = nodo;
      var viva = false;
      while (true) {
        if (n.flagsCollection.isLiveRegion) viva = true;
        final padre = n.parent;
        if (padre == null) break;
        n = padre;
      }
      expect(viva, isTrue);
      h.dispose();
      await desmontar455(tester);
    });

    testWidgets('el botón rojo y el de «Volver» tienen nombre y acción de toque', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA455(tester, Estado455.h04Entrevista);
      expect(
        tester.getSemantics(confirmar455),
        isSemantics(label: 'Cancelar agenda', isButton: true, hasTapAction: true, isEnabled: true),
      );
      expect(
        tester.getSemantics(volver455),
        isSemantics(label: 'Volver', isButton: true, hasTapAction: true, isEnabled: true),
      );
      h.dispose();
      await desmontar455(tester);
    });

    testWidgets('el título de la hoja es un encabezado', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA455(tester, Estado455.h04Entrevista);
      expect(
        tester.getSemantics(find.text(tituloEntrevista455)),
        matchesSemantics(label: tituloEntrevista455, isHeader: true, hasTapAction: false),
      );
      h.dispose();
      await desmontar455(tester);
    });

    // skip: QA #455 — mientras se cancela el botón cambia a «Cancelando…» pero no es una región viva:
    // con TalkBack/VoiceOver no se anuncia que algo está pasando.
    testWidgets('«Cancelando…» se anuncia (región viva)', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA455(tester, Estado455.h04Cancelando);
      var n = tester.getSemantics(find.text('Cancelando…'));
      var viva = false;
      while (true) {
        if (n.flagsCollection.isLiveRegion) viva = true;
        final padre = n.parent;
        if (padre == null) break;
        n = padre;
      }
      expect(viva, isTrue);
      h.dispose();
      await desmontar455(tester);
    }, skip: !_verHallazgos);
  });
}
