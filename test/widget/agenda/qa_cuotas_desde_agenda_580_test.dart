// QA de #580 (HU-COB-004): abrir las cuotas (30A-06) desde la cobranza de la Agenda y desde su aviso
// (`00 Navegacion`: «Notificación o agenda de cobranza»). Sin artboard nuevo: lo que se prueba es el
// acceso «Ver las cuotas» del detalle (4 tamaños × 10 estados), los avisos con la app entera (recordatorio
// y centro de notificaciones) y los casos límite de cada entrada. Las capturas salen con
// `--dart-define=QA_CAPTURAS=true`; los hallazgos con skip, con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/cuotas_de_la_venta_page.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuotas_arnes.dart'
    show botonPrincipal, montarCuotas, paginaLista, tocarEnCuotas, volverDeCuotas;
import '../../helpers/cuotas_desde_agenda_arnes.dart';
import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';
import '../../helpers/qa_cuotas_desde_agenda_580_arnes.dart';

/// Los hallazgos viven con `skip`; `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

String _suf(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

void main() {
  group('Detalle de la agenda · «Ver las cuotas» en cada estado y tamaño', () {
    for (final tamano in [chico580, grande580]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado580.values) {
          testWidgets('${estado.rotulo} · ${_suf(tamano, escala)}', (tester) async {
            await llegarA580(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);

            if (estado == Estado580.cargando) {
              expect(find.byKey(ClavesDetalleAgenda.cargando), findsOneWidget);
            }
            if (estado == Estado580.errorAlLeer) {
              expect(find.byKey(ClavesDetalleAgenda.reintentar), findsOneWidget);
            }
            if (!estado.conAcceso) {
              expect(botonCuotas580, findsNothing);
              await capturar580(tester, 'detalle_${estado.name}_${_suf(tamano, escala)}');
              return;
            }

            // Está en el árbol, se alcanza con el scroll y entra entero en la pantalla.
            expect(botonCuotas580, findsOneWidget);
            await tester.ensureVisible(botonCuotas580);
            await tester.pump();
            final r = tester.getRect(botonCuotas580);
            expect(r.height, greaterThanOrEqualTo(48), reason: 'alto del toque');
            expect(r.width, greaterThanOrEqualTo(48), reason: 'ancho del toque');
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(tamano.width));
            expect(r.top, greaterThanOrEqualTo(0));
            expect(r.bottom, lessThanOrEqualTo(tamano.height));
            sinTextoCortado580(tester);
            await capturar580(tester, 'detalle_${estado.name}_${_suf(tamano, escala)}');

            // Se puede tocar de verdad y lleva a las cuotas de esa venta.
            await tester.tap(botonCuotas580);
            await asentarDetalle(tester);
            expect(paginaLista, findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('Detalle de la agenda · lector de pantalla', () {
    testWidgets(
      '«Ver las cuotas» se anuncia como botón con su nombre y se activa desde el lector',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA580(tester, Estado580.programada, tamano: grande580);
        await tester.ensureVisible(botonCuotas580);
        await tester.pump();

        final nodo = tester.getSemantics(botonCuotas580);
        expect(nodo.label, 'Ver las cuotas');
        final datos = nodo.getSemanticsData();
        expect(datos.hasAction(SemanticsAction.tap), isTrue);
        expect(datos.flagsCollection.isButton, isTrue);
        expect(datos.flagsCollection.isEnabled, Tristate.isTrue);

        // El lector lo activa sin tocar el vidrio.
        tester.semantics.tap(find.semantics.byLabel('Ver las cuotas'));
        await asentarDetalle(tester);
        expect(paginaLista, findsOneWidget);
        h.dispose();
      },
    );

    testWidgets('el orden de lectura pone el acceso después de la nota y antes de las acciones', (
      tester,
    ) async {
      await llegarA580(tester, Estado580.programada, tamano: grande580);
      final yNota = tester.getTopLeft(find.byKey(ClavesDetalleAgenda.nota)).dy;
      final yAcceso = tester.getTopLeft(botonCuotas580).dy;
      final yModificar = tester.getTopLeft(find.byKey(ClavesDetalleAgenda.modificar)).dy;
      expect(yAcceso, greaterThan(yNota));
      expect(yAcceso, lessThan(yModificar));
    });
  });

  group('Detalle de la agenda · casos límite del acceso', () {
    testWidgets('tres toques seguidos sin fotograma abren una sola pantalla de cuotas', (
      tester,
    ) async {
      await montarDetalleDeCuota(tester);
      await tester.tap(botonCuotas580);
      await tester.tap(botonCuotas580, warnIfMissed: false);
      await tester.tap(botonCuotas580, warnIfMissed: false);
      await asentarDetalle(tester);

      expect(pantallasDeCuotas580(tester), 1);
      await tester.tap(volverDeCuotas);
      await asentarDetalle(tester);
      expect(pantallasDeCuotas580(tester), 0);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
    });

    testWidgets('entrar y salir cinco veces: el acceso vuelve siempre y nunca queda trabado', (
      tester,
    ) async {
      final a = await montarDetalleDeCuota(tester);
      for (var i = 1; i <= 5; i++) {
        await tester.tap(botonCuotas580);
        await asentarDetalle(tester);
        expect(paginaLista, findsOneWidget, reason: 'vuelta $i');
        await tester.tap(volverDeCuotas);
        await asentarDetalle(tester);
        expect(botonCuotas580, findsOneWidget, reason: 'vuelta $i');
      }
      expect(a.detalle.repo.lecturas, 6);
    });

    testWidgets('el «atrás» del sistema desde las cuotas deja el detalle de la cuota a la vista', (
      tester,
    ) async {
      await montarDetalleDeCuota(tester);
      await tester.tap(botonCuotas580);
      await asentarDetalle(tester);
      expect(paginaLista, findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarDetalle(tester);
      expect(paginaLista, findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(botonCuotas580, findsOneWidget);
    });

    testWidgets(
      'si la lectura de las cuotas falla, «Reintentar» está en la misma pantalla y anda',
      (tester) async {
        final a = await montarDetalleDeCuota(tester);
        a.plan.fallaAlLeer = true;
        await tester.tap(botonCuotas580);
        await asentarDetalle(tester);
        expect(find.text('No pudimos leer las cuotas guardadas en tu teléfono.'), findsOneWidget);

        a.plan.fallaAlLeer = false;
        await tester.tap(find.text('Reintentar'));
        await asentarDetalle(tester);
        expect(find.text('PLAN · 3 CUOTAS SEMANALES'), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
      },
    );

    testWidgets(
      'si mientras se miran las cuotas la cita deja de estar, el detalle lo dice y deja salir',
      (tester) async {
        final a = await montarDetalleDeCuota(tester);
        await tester.tap(botonCuotas580);
        await asentarDetalle(tester);

        a.detalle.repo.detalle = null;
        await tester.tap(volverDeCuotas);
        await asentarDetalle(tester);

        expect(
          find.text('Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.'),
          findsOneWidget,
        );
        expect(botonCuotas580, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('si mientras se miran las cuotas la cita pasa a cumplida, el acceso sigue', (
      tester,
    ) async {
      final a = await montarDetalleDeCuota(tester);
      await tester.tap(botonCuotas580);
      await asentarDetalle(tester);

      a.detalle.repo.detalle = DetalleDeAgenda(
        agenda: agendaDeCuota(estado: EstadoAgenda.cumplida),
      );
      await tester.tap(volverDeCuotas);
      await asentarDetalle(tester);

      expect(botonCuotas580, findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
    });

    testWidgets(
      'una nota de 600 caracteres con emoji no tapa ni desplaza el acceso fuera de alcance',
      (tester) async {
        final detalle = DetalleDeAgenda(agenda: agendaDeCuota(), nota: '${'ñandú 🚀 ' * 75}fin');
        await montarDetalle(
          tester,
          detalle: detalle,
          extras: overridesDeLasCuotas(planDeLaVenta()),
          escala: 2,
          tamano: chico580,
        );
        await tester.ensureVisible(botonCuotas580);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(botonCuotas580);
        await asentarDetalle(tester);
        expect(paginaLista, findsOneWidget);
      },
    );
  });

  group('Avisos · con la app entera', () {
    testWidgets('el recordatorio de una cuota vencida abre las cuotas con el aviso de vencida', (
      tester,
    ) async {
      final app = await abrirApp580(tester, reloj: despuesDeLaCuota2);
      app.recordatorios.tocar('ag-1');
      await asentar580(tester);

      expect(paginaLista, findsOneWidget);
      expect(find.textContaining('venció el 02/11'), findsWidgets);
      await capturar580(tester, 'aviso_vencida_390x844_x1.0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('dos recordatorios de cuotas de la misma venta seguidos abren una sola pantalla', (
      tester,
    ) async {
      final app = await abrirApp580(tester);
      app.recordatorios
        ..tocar('ag-1')
        ..tocar('ag-2')
        ..tocar('ag-1');
      await asentar580(tester);

      expect(pantallasDeCuotas580(tester), 1);
      await tester.tap(volverDeCuotas);
      await asentar580(tester);
      expect(pantallasDeCuotas580(tester), 0);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('el aviso de otra venta mientras se miran las cuotas de una apila la suya', (
      tester,
    ) async {
      final app = await abrirApp580(tester);
      app.recordatorios.tocar('ag-1');
      await asentar580(tester);
      expect(pantallasDeCuotas580(tester), 1);

      app.repo.detalle = DetalleDeAgenda(agenda: cuotaDeLaVenta580('ag-9', 'v-2'));
      app.recordatorios.tocar('ag-9');
      await asentar580(tester);
      expect(pantallasDeCuotas580(tester), 2);

      // Atrás una vez: queda la primera; atrás otra: la app.
      await tester.tap(volverDeCuotas.last);
      await asentar580(tester);
      expect(pantallasDeCuotas580(tester), 1);
      await tester.tap(volverDeCuotas);
      await asentar580(tester);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('el mismo aviso, después de cerrar las cuotas, las vuelve a abrir', (tester) async {
      final app = await abrirApp580(tester);
      for (var i = 0; i < 3; i++) {
        app.recordatorios.tocar('ag-1');
        await asentar580(tester);
        expect(paginaLista, findsOneWidget, reason: 'vuelta $i');
        await tester.tap(volverDeCuotas);
        await asentar580(tester);
        expect(paginaLista, findsNothing, reason: 'vuelta $i');
      }
    });

    testWidgets('con la lectura de la agenda lenta, al llegar la respuesta se abren las cuotas', (
      tester,
    ) async {
      final app = await abrirApp580(tester);
      final repo = app.repo;
      final compuerta = Completer<void>();
      repo.compuertaDeLectura = compuerta;

      app.recordatorios.tocar('ag-1');
      await asentar580(tester);
      expect(paginaLista, findsNothing);

      compuerta.complete();
      repo.compuertaDeLectura = null;
      await asentar580(tester);
      expect(paginaLista, findsOneWidget);
    });

    testWidgets('si leer la agenda lanza una excepción, el aviso abre el detalle y no se pierde', (
      tester,
    ) async {
      final app = await abrirApp580(tester);
      final repo = app.repo;
      final compuerta = Completer<void>();
      repo.compuertaDeLectura = compuerta;

      app.recordatorios.tocar('ag-1');
      await tester.pump();
      compuerta.completeError(StateError('base cerrada'));
      repo.compuertaDeLectura = null;
      await asentar580(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(botonCuotas580, findsOneWidget);
    });

    testWidgets('el recordatorio de una cuota cancelada también abre las cuotas', (tester) async {
      final app = await abrirApp580(
        tester,
        repo: AgendaRepositorioDetalle(
          DetalleDeAgenda(agenda: agendaDeCuota(estado: EstadoAgenda.cancelada)),
        ),
      );
      app.recordatorios.tocar('ag-1');
      await asentar580(tester);
      expect(paginaLista, findsOneWidget);
    });

    testWidgets(
      'con el detalle de la misma cobranza abierto, el aviso apila las cuotas y al volver '
      'queda el detalle',
      (tester) async {
        final app = await abrirApp580(tester);
        final contexto = tester.element(find.byKey(const Key('inicio_principal')));
        unawaited(DetalleAgendaPage.abrir(contexto, agendaId: 'ag-1', colportorId: 'col-1'));
        await asentar580(tester);
        expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);

        app.recordatorios.tocar('ag-1');
        await asentar580(tester);
        expect(paginaLista, findsOneWidget);

        await tester.tap(volverDeCuotas);
        await asentar580(tester);
        expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
        expect(botonCuotas580, findsOneWidget);
      },
    );

    testWidgets('el aviso del centro de notificaciones tocado dos veces abre una sola pantalla', (
      tester,
    ) async {
      final app = await abrirApp580(tester);
      final contexto = tester.element(find.byKey(const Key('inicio_principal')));
      final abrir = app.contenedor.read(abridorDestinoNotificacionProvider);

      unawaited(abrir(contexto, const DestinoAgenda('ag-1')));
      unawaited(abrir(contexto, const DestinoAgenda('ag-1')));
      await asentar580(tester);

      expect(pantallasDeCuotas580(tester), 1);
      await tester.tap(volverDeCuotas);
      await asentar580(tester);
      expect(pantallasDeCuotas580(tester), 0);
    });

    testWidgets(
      'si la persona sale antes de que termine la lectura, el aviso no abre nada encima',
      (tester) async {
        final app = await abrirApp580(tester);
        final repo = app.repo;
        final contexto = tester.element(find.byKey(const Key('inicio_principal')));
        final compuerta = Completer<void>();
        repo.compuertaDeLectura = compuerta;

        // Un aviso del centro con el contexto de una pantalla que se cierra mientras lee.
        unawaited(
          showDialog<void>(
            context: contexto,
            builder: (_) => const AlertDialog(title: Text('Otra cosa')),
          ),
        );
        await asentar580(tester);
        final contextoDelDialogo = tester.element(find.text('Otra cosa'));
        unawaited(
          app.contenedor.read(abridorDestinoNotificacionProvider)(
            contextoDelDialogo,
            const DestinoAgenda('ag-1'),
          ),
        );
        await tester.pump();
        Navigator.of(contextoDelDialogo).pop();
        await asentar580(tester);
        compuerta.complete();
        repo.compuertaDeLectura = null;
        await asentar580(tester);

        expect(tester.takeException(), isNull);
        expect(paginaLista, findsNothing);
      },
    );

    testWidgets('360×640 con texto al 200 %: las cuotas del aviso se abren sin desbordar', (
      tester,
    ) async {
      final app = await abrirApp580(tester, tamano: chico580, escala: 2, reloj: despuesDeLaCuota2);
      app.recordatorios.tocar('ag-1');
      await asentar580(tester);
      expect(paginaLista, findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturar580(tester, 'aviso_vencida_360x640_x2.0');
    });

    testWidgets('un plan sin cuotas guardadas: el aviso abre la pantalla y se puede salir', (
      tester,
    ) async {
      final app = await abrirApp580(tester, plan: PlanDeCuotasEnMemoria());
      app.recordatorios.tocar('ag-1');
      await asentar580(tester);

      expect(tester.takeException(), isNull);
      await capturar580(tester, 'aviso_sin_plan_390x844_x1.0');
      expect(volverDeCuotas, findsOneWidget);
      await tester.tap(volverDeCuotas);
      await asentar580(tester);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('un plan con todo pagado: el aviso abre la pantalla y se puede salir', (
      tester,
    ) async {
      final plan = PlanDeCuotasEnMemoria(
        cobradoCentavos: 250000,
        cuotas: [
          cuotaDe(1, dia: 2, monto: 83300, cubierta: true),
          cuotaDe(2, dia: 9, monto: 83300, cubierta: true),
          cuotaDe(3, dia: 16, monto: 83400, cubierta: true),
        ],
      );
      final app = await abrirApp580(tester, plan: plan);
      app.recordatorios.tocar('ag-1');
      await asentar580(tester);

      expect(tester.takeException(), isNull);
      await capturar580(tester, 'aviso_todo_pagado_390x844_x1.0');
      expect(volverDeCuotas, findsOneWidget);
    });
  });

  group('Regresión y hallazgos', () {
    // Regresión: al volver de las cuotas (el detalle se relee) quien bajó hasta «Ver las cuotas» con
    // texto al 200 % en 360×640 no pierde el lugar.
    testWidgets('al volver de las cuotas el detalle conserva el lugar del scroll', (tester) async {
      await montarDetalleDeCuota(tester, escala: 2, tamano: chico580);
      await tester.ensureVisible(botonCuotas580);
      await tester.pump();
      final scroll = find.byType(Scrollable).first;
      final antes = tester.state<ScrollableState>(scroll).position.pixels;
      expect(antes, greaterThan(0), reason: 'hace falta bajar para llegar al acceso');

      await tester.tap(botonCuotas580);
      await asentarDetalle(tester);
      await tester.tap(volverDeCuotas);
      await asentarDetalle(tester);

      expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, antes);
    });

    // skip: issue #580 — la lista de cuotas que queda tras armar el plan se abre con `pushReplacement`
    // sin el nombre de ruta que usa `abrir` para no apilar otra igual: un aviso de esa venta la duplica.
    testWidgets(
      'con las cuotas recién armadas a la vista, abrirlas otra vez no apila otra pantalla',
      (tester) async {
        await montarCuotas(tester);
        await tocarEnCuotas(tester, botonPrincipal);
        expect(pantallasDeCuotas580(tester), 1);

        final contexto = tester.element(paginaLista);
        unawaited(
          CuotasDeLaVentaPage.abrir(
            contexto,
            ventaId: 'v-1',
            colportorId: 'col-1',
            espacioId: 'esp-1',
          ),
        );
        await asentar580(tester);

        expect(pantallasDeCuotas580(tester), 1);
      },
      skip: !_verHallazgos,
    );
  });
}
