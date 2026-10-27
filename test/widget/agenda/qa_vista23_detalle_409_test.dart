// QA de #409 (vista 23 C, HU-VIS-003): el detalle de una agenda y «Modificar agenda», 23C·01, 23C·02,
// 23C·03, 23C·06 y 23C·07. Complementa los tests de la implementación con:
//  1. la matriz de estados (23) × 360x640 / 412x915 × texto 1,0 / 2,0, sin overflow ni texto cortado,
//     con capturas (`--dart-define=QA_CAPTURAS=true`) y las fuentes reales del proyecto;
//  2. el escenario literal de la HU (14:00 → 15:00, el aviso pasa de 13:30 a 14:30);
//  3. los casos límite de entradas (nota larga pegada, solo espacios, emoji), de navegación y de
//     acciones que se superponen;
//  4. lo que dice el lector de pantalla y la privacidad.
// Los tests con `skip` documentan un hallazgo de QA (corren con `--dart-define=QA_HALLAZGOS=true`).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_detalle_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/modificar_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/qa_vista23_409_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

String _suf(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

String _textoDe(Key k) => (find.byKey(k).evaluate().single.widget as Text).data!;

String _fila(Key k) => [
  for (final w in find.descendant(of: find.byKey(k), matching: find.byType(Text)).evaluate())
    (w.widget as Text).data ?? '',
].join('|');

void main() {
  group('Matriz · cada estado × 360x640 / 412x915 × texto 1,0 / 2,0', () {
    for (final tamano in [chico409, grande409]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado409.values) {
          testWidgets('${estado.rotulo} · ${_suf(tamano, escala)}', (tester) async {
            await llegarA409(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull, reason: 'overflow o error al pintar');
            sinTextoCortado409(tester);
            await capturar409(tester, '${estado.archivo}_${_suf(tamano, escala)}');
          });
        }
      }
    }
  });

  group('23C·01 · Criterios de la HU (literal)', () {
    testWidgets(
      'Dado que tengo agenda a las 14:00 con recordatorio a 13:30, cuando cambio a 15:00, '
      'entonces el recordatorio se reprograma a 14:30',
      (tester) async {
        final arnes = await montarDetalle(
          tester,
          detalle: DetalleDeAgenda(agenda: agendaDelDetalle(cuando: DateTime(2026, 10, 24, 14))),
        );
        expect(_fila(ClavesDetalleAgenda.recordatorio), 'Recordatorio|13:30');

        await tocar409(tester, modificar409);
        await subirHora409(tester, 12);
        expect(find.text('Mañana · 15:00'), findsOneWidget);
        expect(
          _textoDe(ClavesModificarAgenda.textoRecordatorio),
          'Reprogramamos el recordatorio para las 14:30.',
        );
        await tocar409(tester, guardar409);

        expect(find.text('Guardado. El recordatorio pasó a las 14:30.'), findsOneWidget);
        expect(_fila(ClavesDetalleAgenda.recordatorio), 'Recordatorio|14:30');
        expect(
          arnes.recordatorios.programados['ag-1']!.fechaProgramada.toLocal(),
          DateTime(2026, 10, 24, 15),
        );
      },
    );

    for (final e in [Estado409.d06Cumplida, Estado409.d06NoCumplida, Estado409.d06Cancelada]) {
      testWidgets(
        'Regla: solo es editable si está PROGRAMADA (${e.rotulo} no ofrece «Modificar»)',
        (tester) async {
          await llegarA409(tester, e);
          expect(modificar409, findsNothing);
          expect(find.byKey(ClavesDetalleAgenda.avisoCerrada), findsOneWidget);
        },
      );
    }

    testWidgets(
      'Regla: cambiar de entrevista a cobranza lo manda tal cual a guardar (el repositorio '
      'recalcula el color de la casa)',
      (tester) async {
        final arnes = await montarDetalle(tester);
        await tocar409(tester, modificar409);
        await tocar409(tester, find.text('Cobranza'));
        await tocar409(tester, guardar409);
        expect(arnes.repo.recibidos.single.tipo, TipoAgenda.cobranza);
      },
    );
  });

  group('Entradas del formulario «Modificar»', () {
    testWidgets('texto pegado de 600 caracteres: el campo se queda en 500 y se guarda', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      await tocar409(tester, modificar409);
      await tester.enterText(find.byType(TextField), 'x' * 600);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text.length, 500);
      await tocar409(tester, guardar409);
      expect(arnes.repo.recibidos.single.nota!.length, 500);
    });

    testWidgets('nota con emoji y caracteres especiales llega entera y se ve en el detalle', (
      tester,
    ) async {
      const nota = 'Volver 🙏 mañana · "después" <b>&</b> ñ';
      final arnes = await montarDetalle(tester);
      await tocar409(tester, modificar409);
      await tester.enterText(find.byType(TextField), nota);
      await tocar409(tester, guardar409);
      expect(arnes.repo.recibidos.single.nota, nota);
      expect(find.text(nota), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nota de solo espacios: se manda en blanco (borra la nota) y el detalle dice '
        '«Sin nota»', (tester) async {
      final arnes = await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Algo'),
      );
      await tocar409(tester, modificar409);
      await tester.enterText(find.byType(TextField), '     ');
      await tocar409(tester, guardar409);
      expect(arnes.repo.recibidos.single.nota!.trim(), isEmpty);
      expect(_fila(ClavesDetalleAgenda.nota), 'Nota|Sin nota');
    });

    testWidgets('la nota tipeada no se pierde si falla el guardado ni al reintentar', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.fallas.add(const FailureInesperado());
      await tocar409(tester, modificar409);
      await tester.enterText(find.byType(TextField), 'No perder esto 🙏');
      await tocar409(tester, guardar409);
      expect(find.text('No perder esto 🙏'), findsOneWidget);
      await tocar409(tester, guardar409);
      expect(arnes.repo.recibidos.last.nota, 'No perder esto 🙏');
    });
  });

  group('Navegación', () {
    testWidgets('la flecha del detalle vuelve a la pantalla anterior', (tester) async {
      await montarDetalle(tester);
      await tocar409(tester, find.byKey(ClavesDetalleAgenda.volver));
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsNothing);
      expect(find.text('abrir detalle'), findsOneWidget);
    });

    testWidgets('el botón atrás del sistema en «Modificar» vuelve al detalle sin guardar', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      await tocar409(tester, modificar409);
      await tocar409(tester, find.text('Cobranza'));
      await tester.binding.handlePopRoute();
      await asentarDetalle(tester);
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(_textoDe(ClavesDetalleAgenda.titulo), 'Entrevista');
      expect(arnes.repo.recibidos, isEmpty);
    });

    testWidgets(
      'cerrar la hoja «Esa hora ya pasó» con el atrás del sistema deja el botón sirviendo '
      'y no guarda',
      (tester) async {
        final arnes = await montarDetalle(tester);
        await tocar409(tester, modificar409);
        await hoyAMediaTarde409(tester);
        await tocar409(tester, guardar409);
        expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsOneWidget);

        await tester.binding.handlePopRoute();
        await asentarDetalle(tester);
        expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsNothing);
        expect(find.text('Guardando…'), findsNothing);
        expect(arnes.repo.recibidos, isEmpty);

        await tocar409(tester, guardar409);
        expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsOneWidget);
      },
    );
  });

  group('Casos límite de acciones superpuestas', () {
    testWidgets('la falla del guardado deja todo editable otra vez: tipo, hora, franja y nota', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.fallas.add(const FailureInesperado());
      await tocar409(tester, modificar409);
      await tocar409(tester, find.text('Cobranza'));
      await tocar409(tester, guardar409);
      expect(find.byKey(ClavesModificarAgenda.avisoFalla), findsOneWidget);
      // Todo vuelve a responder.
      await tocar409(tester, find.text('Entrevista'));
      await subirHora409(tester, 12);
      await tocar409(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.finDeTarde)));
      await tester.enterText(find.byType(TextField), 'otra');
      await tocar409(tester, guardar409);
      final c = arnes.repo.recibidos.last;
      expect(c.tipo, TipoAgenda.entrevista);
      expect(c.nota, 'otra');
      expect(c.slotCodigo, FranjaHoraria.finDeTarde.codigo);
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
    });

    testWidgets('mientras guarda, el tipo, la hora, las franjas y la nota no responden', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.compuerta = Completer<void>();
      await tocar409(tester, modificar409);
      await tester.tap(guardar409);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Cobranza'), warnIfMissed: false);
      await tester.tap(campoHora409, warnIfMissed: false);
      await asentarDetalle(tester);
      expect(find.byKey(ClavesAgendarVisita.hojaListo), findsNothing);
      expect(arnes.repo.recibidos.single.tipo, TipoAgenda.entrevista);
      arnes.repo.compuerta!.complete();
      await asentarDetalle(tester);
    });

    testWidgets('«Reintentar» después de «Guardar igual» no vuelve a preguntar por la hora', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      await tocar409(tester, modificar409);
      await hoyAMediaTarde409(tester);
      arnes.repo.fallas.add(const FailureInesperado());
      await tocar409(tester, guardar409);
      await tocar409(tester, find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual));
      expect(find.byKey(ClavesModificarAgenda.avisoFalla), findsOneWidget);
      await tocar409(tester, guardar409);
      expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsNothing);
      expect(arnes.repo.recibidos, hasLength(2));
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
    });

    testWidgets('«Registrar resultado» y «Modificar» a la vez abren una sola pantalla', (
      tester,
    ) async {
      final espera = Completer<void>();
      final arnes = await montarDetalle(tester, conRegistrar: true, registrarDemorado: espera);
      await tester.tap(find.byKey(ClavesDetalleAgenda.registrar));
      await tester.pump();
      await tester.tap(modificar409);
      await asentarDetalle(tester);
      expect(arnes.registros, hasLength(1));
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
      espera.complete();
      await asentarDetalle(tester);
    });
  });

  group('Lector de pantalla', () {
    testWidgets('el error al guardar se anuncia como región viva', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA409(tester, Estado409.m07Error);
      var vivo = false;
      void buscar(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isLiveRegion) vivo = true;
        n.visitChildren((c) {
          buscar(c);
          return true;
        });
      }

      buscar(tester.getSemantics(find.byKey(ClavesModificarAgenda.avisoFalla)));
      expect(vivo, isTrue, reason: 'el aviso de error no es una región viva');
      h.dispose();
    });

    testWidgets('el detalle anuncia el título como encabezado y cada renglón como una frase', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await montarDetalle(tester);
      expect(
        tester.getSemantics(find.byKey(ClavesDetalleAgenda.titulo)).flagsCollection.isHeader,
        isTrue,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Estado\s*[:\n]?\s*Programada')), findsOneWidget);
      h.dispose();
    });
  });

  group('Teclado en «Modificar»', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('con el teclado abierto a 360x640 (x$escala) el campo de la nota queda a la '
          'vista y no desborda', (tester) async {
        await llegarA409(tester, Estado409.m02Modificar, escala: escala);
        await tester.ensureVisible(find.byType(TextField));
        await tester.tap(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await asentarDetalle(tester);
        expect(tester.takeException(), isNull);
        final campo = tester.getRect(find.byType(TextField));
        final alto = tester.view.physicalSize.height - 280;
        expect(campo.bottom, lessThanOrEqualTo(alto + 1), reason: 'el campo quedó bajo el teclado');
        await capturar409(tester, 'teclado_x$escala');
      });
    }
  });

  group('Privacidad', () {
    test('ni los cambios ni el detalle ni los parámetros muestran la nota en un toString', () {
      const nota = 'NOTA-SECRETA-DE-LA-PERSONA';
      final detalle = DetalleDeAgenda(agenda: agendaDelDetalle(), nota: nota);
      final cambios = CambiosDeAgenda(
        agendaId: 'ag-1',
        tipo: TipoAgenda.entrevista,
        fechaProgramada: DateTime(2026, 10, 24, 14),
        nota: nota,
        idNota: 'n1',
      );
      expect(detalle.toString(), isNot(contains(nota)));
      expect(cambios.toString(), isNot(contains(nota)));
    });
  });

  group('Hallazgos de QA', () {
    // skip: QA #409 — tocar el aviso de la agenda que ya está abierta apila otro detalle igual encima
    // (hay que volver dos veces).
    testWidgets(
      'tocar el recordatorio de la agenda que ya está en pantalla no abre un segundo detalle',
      (tester) async {
        await montarDetalle(tester);
        final contexto = tester.element(find.byType(DetalleAgendaPage));
        unawaited(FlujoDetalleAgenda.abrir(contexto, agendaId: 'ag-1', colportorId: 'col-1'));
        await asentarDetalle(tester);
        expect(find.byType(DetalleAgendaPage, skipOffstage: false), findsOneWidget);
      },
      skip: !_hallazgos,
    );

    // skip: QA #409 — el aviso rojo de 23C·07 va arriba del formulario: con el formulario más alto que
    // la pantalla (360x640) y la persona abajo, al fallar solo cambia el botón a «Reintentar» y el
    // aviso queda fuera de vista (no hay scroll hacia él).
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'al fallar el guardado con el formulario scrolleado abajo, el aviso de error queda a la vista '
        '(360x640, x$escala)',
        (tester) async {
          final arnes = await montarDetalle(tester, escala: escala, tamano: chico409);
          arnes.repo.fallas.add(const FailureInesperado());
          await tocar409(tester, modificar409);
          final scroll = find.byType(SingleChildScrollView);
          await tester.drag(scroll, const Offset(0, -3000));
          await asentarDetalle(tester);
          await tester.tap(guardar409);
          await asentarDetalle(tester);
          final visible = tester.getRect(scroll);
          final aviso = tester.getRect(find.byKey(ClavesModificarAgenda.avisoFalla));
          expect(
            aviso.overlaps(visible) &&
                aviso.top >= visible.top - 1 &&
                aviso.bottom <= visible.bottom + 1,
            isTrue,
            reason: 'aviso en $aviso, zona visible $visible',
          );
        },
        // A 1,0× el aviso entra en la zona visible: queda como regresión; a 2,0× es el hallazgo.
        skip: escala > 1 && !_hallazgos,
      );
    }

    // skip: QA #409 — el hint «Esperá a que carguemos la casa para guardar.» queda en un nodo padre sin
    // etiqueta ni acción: el lector lee «Guardar cambios, deshabilitado» sin decir por qué.
    testWidgets(
      '«Guardar cambios» deshabilitado porque la casa no carga: el lector dice por qué en el mismo '
      'nodo del botón',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA409(tester, Estado409.mCasaError);
        expect(tester.getSemantics(guardar409).hint, contains('Esperá a que carguemos la casa'));
        h.dispose();
      },
      skip: !_hallazgos,
    );

    // skip: QA #409 — con la casa sin leer, «Registrar resultado» queda apagado sin aviso ni
    // «Reintentar» (la persona no sabe por qué ni cómo arreglarlo desde el detalle).
    testWidgets(
      'si la casa no se puede leer, «Registrar resultado» no queda apagado sin decir por qué',
      (tester) async {
        final h = tester.ensureSemantics();
        await montarDetalle(tester, conRegistrar: true, fallaDeCasa: const FailureInesperado());
        final boton = tester.widget<FilledButton>(find.byKey(ClavesDetalleAgenda.registrar));
        final habilitado = boton.onPressed != null;
        final dice =
            find.textContaining('casa').evaluate().isNotEmpty ||
            find.byKey(ClavesDetalleAgenda.reintentar).evaluate().isNotEmpty;
        expect(
          habilitado || dice,
          isTrue,
          reason: 'botón principal apagado, sin aviso ni «Reintentar»',
        );
        h.dispose();
      },
      skip: !_hallazgos,
    );

    // skip: QA #409 — «Modificar» arranca con la franja en automático: cambiar la hora pisa en
    // silencio la franja que la persona había elegido a mano al agendar.
    testWidgets(
      'modificar la hora no pisa la franja que la persona había elegido a mano al agendar',
      (tester) async {
        // 14:30 con «Fin de tarde» (la sugerida para esa hora sería otra): la franja es de la
        // persona.
        final arnes = await montarDetalle(
          tester,
          detalle: DetalleDeAgenda(agenda: agendaDelDetalle(slot: FranjaHoraria.finDeTarde.codigo)),
        );
        await tocar409(tester, modificar409);
        await subirHora409(tester, 1);
        await tocar409(tester, guardar409);
        expect(arnes.repo.recibidos.single.slotCodigo, FranjaHoraria.finDeTarde.codigo);
      },
      skip: !_hallazgos,
    );
  });
}
