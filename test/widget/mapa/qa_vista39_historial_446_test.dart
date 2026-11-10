// QA del Historial de la hoja de la casa (vista 39, C·03 y C·04, #446, PR #677). Lleva la hoja real, con
// el enganche de `main.dart`, a cada estado que una persona puede ver (con datos, vacío, cargando, error,
// filtro sin resultados, detalle de una venta y de una visita, aviso de «No pudimos abrir la venta») en
// 360×640 y 412×915 con letra al 100 % y al 200 %, con las fuentes reales; y prueba los casos límite de
// cada flujo (falla a mitad, acciones superpuestas, reentrada, datos límite, volver atrás).
//
// Lo que documenta un hallazgo va con `skip` salvo que se corra con `--dart-define=QA_HALLAZGOS=true`.
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, nunca al repo).
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart'
    show FormatoBajaPersona;
import 'package:colportores_mobile/features/mapa/presentation/textos_historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_446_arnes.dart';

/// Los tests que documentan un hallazgo van con `skip` hasta que el implementador lo arregle; con
/// `--dart-define=QA_HALLAZGOS=true` se corren. Motivo del skip: el comentario de cada test.
const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  Finder fila(String id) => find.byKey(ClavesHistorialDeLaCasa.fila(id));
  Finder filas() => find.byWidgetPredicate((w) => w is FilaDelHistorialDeLaCasa);

  Future<void> conFuentes(WidgetTester tester) => cargarFuentes205(tester);

  group('cada estado × tamaño × letra: nada desborda y se puede llegar a todo', () {
    for (final tamano in const [t360x640, t412x915]) {
      for (final escala in const [1.0, 2.0]) {
        for (final estado in Estado446.values) {
          testWidgets(
            'dado ${estado.name} a ${tamano.width.toInt()}×${tamano.height.toInt()} con letra ×$escala, '
            'se ve sin desbordar y con su salida a mano',
            (tester) async {
              await conFuentes(tester);
              await llegarA446(tester, estado, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull);
              await capturar446(tester, '${estado.name}_${sufijo446(tamano, escala)}');

              switch (estado) {
                case Estado446.vacio:
                  expect(find.byKey(ClavesHistorialDeLaCasa.vacio), findsOneWidget);
                  expect(find.text(TextosHistorialDeLaCasa.vacioTitulo), findsOneWidget);
                case Estado446.cargando:
                  expect(find.byKey(ClavesHistorialDeLaCasa.cargando), findsOneWidget);
                case Estado446.error:
                  await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.reintentar));
                  expect(find.byKey(ClavesHistorialDeLaCasa.reintentar), findsOneWidget);
                  expect(find.text(TextosHistorialDeLaCasa.noPudimosLeer), findsOneWidget);
                case Estado446.filtroSinResultados:
                  expect(find.byKey(ClavesHistorialDeLaCasa.sinResultados), findsOneWidget);
                  expect(find.byKey(ClavesHistorialDeLaCasa.verTodo), findsOneWidget);
                case Estado446.detalleDeVenta ||
                    Estado446.detalleLargo ||
                    Estado446.avisoNoPudimosAbrirLaVenta:
                  if (estado == Estado446.avisoNoPudimosAbrirLaVenta) {
                    expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsOneWidget);
                  } else {
                    // «Ver la venta» y «Cerrar» se alcanzan (el detalle se desplaza si no entra).
                    await tester.ensureVisible(find.byKey(ClavesDetalleDeVisita.cerrar));
                    expect(find.byKey(ClavesDetalleDeVisita.cerrar), findsOneWidget);
                    await tester.ensureVisible(find.byKey(ClavesDetalleDeVisita.verLaVenta));
                    expect(find.byKey(ClavesDetalleDeVisita.verLaVenta), findsOneWidget);
                  }
                case Estado446.detalleDeEntrevista ||
                    Estado446.detalleDeVisitaSinNota ||
                    Estado446.detalleDeRechazo:
                  await tester.ensureVisible(find.byKey(ClavesDetalleDeVisita.cerrar));
                  expect(find.byKey(ClavesDetalleDeVisita.cerrar), findsOneWidget);
                  // Una visita no ofrece «Ver la venta».
                  expect(find.byKey(ClavesDetalleDeVisita.verLaVenta), findsNothing);
                case Estado446.c03SinVerLaVenta:
                  expect(filas(), findsNWidgets(4));
                case Estado446.listaLarga:
                  expect(filas(), findsNWidgets(PestanaHistorialDeLaCasa.pagina));
                  expect(find.byKey(ClavesHistorialDeLaCasa.verMas), findsOneWidget);
                case Estado446.c03 ||
                    Estado446.filtroEntrevistas ||
                    Estado446.textosLargos ||
                    Estado446.dadaDeBaja:
                  expect(filas(), findsWidgets);
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('el texto literal del canvas (C·03 y C·04)', () {
    testWidgets('dado el historial de C·03, cada fila trae su línea chica, su título y su nota', (
      tester,
    ) async {
      await conFuentes(tester);
      await montarHoja446(tester);

      for (final t in [
        'HOY 14:20 · COBRO',
        '${FormatoBajaPersona.monto(60000)} en efectivo · Pedro',
        '12/10 · VENTA 0038',
        'Salud y Hogar · Pedro',
        '05/10 · ENTREVISTA DADA',
        'Pedro Gómez',
        '✎ volver con la esposa',
        '03/10 · NO CONTESTÓ',
        'Nadie atendió',
      ]) {
        expect(find.textContaining(t), findsOneWidget, reason: t);
      }
      for (final f in ['Todo', 'Entrevistas', 'Ventas', 'Cobros']) {
        expect(find.text(f), findsOneWidget, reason: 'filtro $f');
      }
    });

    testWidgets(
      'dado el detalle de la venta 0038, dice «Venta 0038 · 12/10» y «Pedro Gómez · Grecia 3310»',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester);
        await tocarFila446(tester, 'ven-1');

        expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
        expect(find.text('Pedro Gómez · Grecia 3310'), findsOneWidget);
        expect(find.text('NOTA DE LA VISITA'), findsOneWidget);
        expect(find.text('quiere Nuestros Hijos'), findsOneWidget);
        expect(find.text('Pagado'), findsOneWidget);
        expect(find.text('Saldo'), findsOneWidget);
        expect(find.text('Ver la venta'), findsOneWidget);
        expect(find.text('Cerrar'), findsOneWidget);
      },
    );

    testWidgets(
      'dado el filtro «Entrevistas», solo quedan las entrevistas y se puede volver a «Todo»',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester);
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.entrevistas)));
        await asentar446(tester);

        expect(filas(), findsOneWidget);
        expect(fila('vis-2'), findsOneWidget);

        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.todo)));
        await asentar446(tester);
        expect(filas(), findsNWidgets(4));
      },
    );
  });

  group('texto cortado con letra al 200 %', () {
    for (final tamano in const [t360x640, t412x915]) {
      testWidgets('dado C·03 a ${tamano.width.toInt()}×${tamano.height.toInt()} con letra ×2, '
          'la línea chica y el título de cada fila se leen enteros', (tester) async {
        await conFuentes(tester);
        await montarHoja446(
          tester,
          eventos: [cobroHoy446, noContesto446],
          tamano: tamano,
          escala: 2,
        );

        final cortados = textosCortados446(tester);

        expect(cortados, isEmpty, reason: 'cortados con «…»: $cortados');
      });
    }

    // skip: QA #446: a 360×640 con letra ×2 la línea chica de la entrevista («· 22 MIN») y la nota de la
    // venta se cortan con «…» en la fila; el detalle las trae enteras (menor).
    testWidgets(
      'dado la entrevista con duración y la venta con nota de C·03 a 360×640 con letra ×2, '
      'la fila no corta la duración ni la nota',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester, tamano: t360x640, escala: 2);

        final cortados = textosCortados446(tester);

        expect(cortados, isEmpty, reason: 'cortados con «…»: $cortados');
      },
      skip: !_conHallazgos,
    );
  });

  group('falla a mitad de la acción', () {
    testWidgets('dado un error de lectura, «Reintentar» vuelve a leer y se ven las filas', (
      tester,
    ) async {
      await conFuentes(tester);
      final fuente = HistorialPorLectura446(
        (n) => n == 0 ? Stream.error(StateError('falla')) : Stream.value(eventosC03()),
      );
      await montarHoja446(tester, fuente: fuente);
      expect(find.byKey(ClavesHistorialDeLaCasa.error), findsOneWidget);
      expect(find.byKey(ClavesHistorialDeLaCasa.filtros), findsNothing);

      await tocarEnLaHoja446(tester, ClavesHistorialDeLaCasa.reintentar);

      expect(find.byKey(ClavesHistorialDeLaCasa.error), findsNothing);
      expect(filas(), findsNWidgets(4));
      expect(fuente.pedidas, 2);
    });

    testWidgets(
      'dado que el stream falla DESPUÉS de mostrar filas, sale el aviso con «Reintentar» y al reintentar vuelven',
      (tester) async {
        await conFuentes(tester);
        final fuente = HistorialControlado446();
        await montarHoja446(tester, fuente: fuente);
        fuente.ultima.add(eventosC03());
        await asentar446(tester);
        expect(filas(), findsNWidgets(4));

        fuente.ultima.addError(StateError('se cerró la base'));
        await asentar446(tester);
        await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.reintentar));

        expect(find.byKey(ClavesHistorialDeLaCasa.error), findsOneWidget);
        expect(find.byKey(ClavesHistorialDeLaCasa.reintentar), findsOneWidget);

        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.reintentar));
        await asentar446(tester);
        fuente.ultima.add(eventosC03());
        await asentar446(tester);

        expect(filas(), findsNWidgets(4));
        expect(find.byKey(ClavesHistorialDeLaCasa.error), findsNothing);
      },
    );

    testWidgets(
      'dado que abrir la venta falla, el aviso dice qué hacer, la fila vuelve a tocarse y el aviso se va al reintentar',
      (tester) async {
        await conFuentes(tester);
        var intentos = 0;
        await montarHoja446(
          tester,
          verVenta: (_) {
            intentos++;
            if (intentos == 1) throw StateError('sin sesión');
            return true;
          },
        );
        await tocarFila446(tester, 'ven-1');
        await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);
        expect(find.text(TextosHistorialDeLaCasa.noPudimosAbrirLaVenta), findsOneWidget);

        await tocarFila446(tester, 'ven-1');
        // El aviso se limpia al volver a abrir algo.
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
        await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);

        expect(intentos, 2);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado que abrir la venta falla de forma asíncrona (Future con error), pasa lo mismo',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester, verVenta: (_) => Future<Object?>.error(StateError('x')));
        await tocarFila446(tester, 'ven-1');
        await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);

        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsOneWidget);
        await tocarFila446(tester, 'vis-2');
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
      },
    );
  });

  group('el aviso de «No pudimos abrir la venta» se ve donde la persona está mirando', () {
    for (final tamano in const [t360x640, t412x915]) {
      for (final escala in const [1.0, 2.0]) {
        // skip: QA #446: a 360×640 con letra ×2 el aviso queda arriba de las filas, fuera de la parte
        // visible de la hoja que quedó desplazada hasta la fila tocada: «Ver la venta» no abre nada y
        // no se ve ningún aviso (bloqueante). Se corre con QA_HALLAZGOS=true.
        final falla = tamano == t360x640 && escala == 2.0;
        testWidgets(
          'dado que «Ver la venta» falla a ${tamano.width.toInt()}×${tamano.height.toInt()} con letra ×$escala, '
          'el aviso está a la vista sin tener que desplazar',
          (tester) async {
            await conFuentes(tester);
            await llegarA446(
              tester,
              Estado446.avisoNoPudimosAbrirLaVenta,
              tamano: tamano,
              escala: escala,
            );

            expect(find.byKey(ClavesHistorialDeLaCasa.aviso).hitTestable(), findsOneWidget);
          },
          skip: falla && !_conHallazgos,
        );
      }
    }
  });

  group('acciones superpuestas', () {
    testWidgets(
      'dado que «Ver la venta» tarda, tocar otra fila o la misma no abre otra cosa encima',
      (tester) async {
        await conFuentes(tester);
        final espera = Completer<Object?>();
        var abiertas = 0;
        await montarHoja446(
          tester,
          verVenta: (_) {
            abiertas++;
            return espera.future;
          },
        );
        await tocarFila446(tester, 'ven-1');
        await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);
        expect(abiertas, 1);

        // Mientras la venta «se abre», otra fila y la misma no abren nada.
        await tester.tap(fila('vis-2'), warnIfMissed: false);
        await tester.tap(fila('ven-1'), warnIfMissed: false);
        await asentar446(tester);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
        expect(abiertas, 1);

        espera.complete(true);
        await asentar446(tester);
        await tocarFila446(tester, 'vis-2');
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
      },
    );

    testWidgets('dado un doble toque en «Ver la venta», la venta se abre una sola vez', (
      tester,
    ) async {
      await conFuentes(tester);
      final m = await montarHoja446(tester);
      await tocarFila446(tester, 'ven-1');
      final boton = find.byKey(ClavesDetalleDeVisita.verLaVenta);
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await asentar446(tester);

      expect(m.ventasAbiertas, hasLength(1));
      expect(m.ventasAbiertas.single.ventaId, 'ven-1');
      expect(m.ventasAbiertas.single.espacioId, 'esp-1');
      expect(m.ventasAbiertas.single.espacioPersonaId, 'ep-pedro');
    });

    testWidgets(
      'dado que llega una visita nueva con el detalle abierto, no se pierde ni cierra: está al cerrar',
      (tester) async {
        await conFuentes(tester);
        final fuente = HistorialControlado446();
        await montarHoja446(tester, fuente: fuente);
        fuente.ultima.add(eventosC03());
        await asentar446(tester);
        await tocarFila446(tester, 'vis-2');
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);

        fuente.ultima.add([
          VisitaDeLaCasa(
            id: 'nueva',
            fecha: fecha446(10, 25, 15),
            resultado: TipoResultadoVisita.rechazo,
          ),
          ...eventosC03(),
        ]);
        await asentar446(tester);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);

        await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.cerrar);
        expect(fila('nueva'), findsOneWidget);
        expect(filas(), findsNWidgets(5));
      },
    );

    testWidgets(
      'dado que la fila que se tocó desaparece del historial mientras el detalle está abierto, el detalle sigue y se cierra',
      (tester) async {
        await conFuentes(tester);
        final fuente = HistorialControlado446();
        await montarHoja446(tester, fuente: fuente);
        fuente.ultima.add(eventosC03());
        await asentar446(tester);
        await tocarFila446(tester, 'ven-1');

        fuente.ultima.add([cobroHoy446, entrevista446]);
        await asentar446(tester);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
        await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.cerrar);

        expect(fila('ven-1'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('volver atrás y reentrar', () {
    testWidgets(
      'dado el detalle abierto, el botón atrás del sistema lo cierra y la fila vuelve a abrirse',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester);
        await tocarFila446(tester, 'ven-1');
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);

        await tester.binding.handlePopRoute();
        await asentar446(tester);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);

        await tocarFila446(tester, 'ven-1');
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
      },
    );

    testWidgets('dado el detalle abierto, tocar fuera lo cierra', (tester) async {
      await conFuentes(tester);
      await montarHoja446(tester);
      await tocarFila446(tester, 'vis-2');

      await tester.tapAt(const Offset(200, 20));
      await asentar446(tester);

      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
    });

    testWidgets(
      'dado que se cambia de pestaña y se vuelve al Historial, arranca en «Todo» sin guardias trabadas',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester);
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
        await asentar446(tester);
        expect(filas(), findsNWidgets(1));

        await tester.tap(find.byKey(ClavesHojaCasa.pestana('personas')));
        await asentar446(tester);
        await tester.ensureVisible(find.byKey(ClavesHojaCasa.pestana('historial')));
        await tester.tap(find.byKey(ClavesHojaCasa.pestana('historial')));
        await asentar446(tester);

        expect(filas(), findsNWidgets(4));
        await tocarFila446(tester, 'ven-1');
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
      },
    );

    testWidgets(
      'dado que se sale con el detalle abierto (se desmonta la hoja), no queda nada colgado',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester);
        await tocarFila446(tester, 'ven-1');

        await tester.pumpWidget(const SizedBox());
        await asentar446(tester);

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('datos límite', () {
    testWidgets('dado 75 filas, «Ver más» suma de a 30 y cambiar de filtro vuelve a 30', (
      tester,
    ) async {
      await conFuentes(tester);
      await montarHoja446(tester, eventos: setentaYCinco446());
      expect(filas(), findsNWidgets(30));
      expect(find.text('Ver más (45)'), findsOneWidget);

      await tocarEnLaHoja446(tester, ClavesHistorialDeLaCasa.verMas);
      expect(filas(), findsNWidgets(60));
      expect(find.text('Ver más (15)'), findsOneWidget);

      await tocarEnLaHoja446(tester, ClavesHistorialDeLaCasa.verMas);
      expect(filas(), findsNWidgets(75));
      expect(find.byKey(ClavesHistorialDeLaCasa.verMas), findsNothing);

      await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await asentar446(tester);
      expect(filas(), findsNWidgets(15));
    });

    testWidgets('dado un solo evento, se ve una fila sin «Ver más»', (tester) async {
      await conFuentes(tester);
      await montarHoja446(tester, eventos: [noContesto446]);

      expect(filas(), findsOneWidget);
      expect(find.byKey(ClavesHistorialDeLaCasa.verMas), findsNothing);
    });

    testWidgets(
      'dado nombres y notas larguísimos y emoji, las filas y el detalle no desbordan y el detalle trae la nota entera',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester, eventos: textosLargos446(), tamano: t360x640, escala: 2);
        await tocarFila446(tester, 'l2');

        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byKey(ClavesDetalleDeVisita.nota),
            matching: find.textContaining('FIN'),
          ),
          findsOneWidget,
        );
        expect(find.text('185 min'), findsOneWidget);
      },
    );

    testWidgets('dado un evento de otro año, la fecha lleva el año', (tester) async {
      await conFuentes(tester);
      await montarHoja446(
        tester,
        eventos: [
          VisitaDeLaCasa(
            id: 'v-viejo',
            fecha: fecha446(10, 12, 12, 0, 2025),
            resultado: TipoResultadoVisita.noContesto,
          ),
        ],
      );

      expect(find.text('12/10/2025 · NO CONTESTÓ'), findsOneWidget);
    });

    testWidgets(
      'dado una venta sin líneas, sin persona y sobrepagada, el detalle muestra saldo 0 y no falla',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(
          tester,
          eventos: [
            VentaDeLaCasa(
              id: 'v-raro',
              fecha: fecha446(10, 20, 10),
              numeroTalonario: '0001',
              montoCentavos: 0,
              pagadoCentavos: 5000,
              lineas: const [],
            ),
          ],
        );
        await tocarFila446(tester, 'v-raro');

        expect(find.text('Venta 0001 · 20/10'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(ClavesDetalleDeVisita.hoja),
            matching: find.text('Grecia 3310'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado un cobro (sin destino enganchado), la fila se ve sin «›» y tocarla no hace nada',
      (tester) async {
        await conFuentes(tester);
        await montarHoja446(tester);
        await tester.ensureVisible(fila('cob-1'));

        expect(
          find.descendant(of: fila('cob-1'), matching: find.byIcon(Icons.chevron_right)),
          findsNothing,
        );
        await tester.tap(fila('cob-1'));
        await asentar446(tester);
        expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsNothing);
      },
    );
  });

  group('lector de pantalla', () {
    testWidgets(
      'dado el historial, cada fila tocable es un botón con su texto entero y los cobros sin destino no lo son',
      (tester) async {
        await conFuentes(tester);
        final semantica = tester.ensureSemantics();
        await montarHoja446(tester);
        await tester.ensureVisible(fila('ven-1'));
        await tester.pump();

        final venta = tester.getSemantics(fila('ven-1'));
        expect(venta.label, contains('VENTA 0038'));
        expect(venta.label, contains('Salud y Hogar'));
        expect(venta.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(venta.flagsCollection.isButton, isTrue);
        await tester.ensureVisible(fila('cob-1'));
        await tester.pump();
        final cobro = tester.getSemantics(fila('cob-1'));
        expect(cobro.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        semantica.dispose();
      },
    );

    testWidgets(
      'dado el filtro elegido, el lector dice «Ventas, elegido» y los demás solo su nombre',
      (tester) async {
        await conFuentes(tester);
        final semantica = tester.ensureSemantics();
        await montarHoja446(tester);
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.ventas)));
        await asentar446(tester);

        expect(find.bySemanticsLabel('Ventas, elegido'), findsOneWidget);
        expect(find.bySemanticsLabel('Todo'), findsOneWidget);
        semantica.dispose();
      },
    );

    testWidgets('dado el error de lectura, se anuncia como región viva', (tester) async {
      await conFuentes(tester);
      final semantica = tester.ensureSemantics();
      await montarHoja446(
        tester,
        fuente: HistorialPorLectura446((_) => Stream.error(StateError('x'))),
      );
      await tester.ensureVisible(find.byKey(ClavesHistorialDeLaCasa.error));
      await tester.pump();

      final nodo = tester.getSemantics(find.text(TextosHistorialDeLaCasa.noPudimosLeer));
      expect(nodo.flagsCollection.isLiveRegion || _tieneRegionViva(tester), isTrue);
      semantica.dispose();
    });
  });

  group('privacidad', () {
    test('dado un evento con nombre y nota, su toString no los imprime', () {
      for (final e in [venta446, entrevista446, cobroHoy446, noContesto446]) {
        final texto = e.toString();
        expect(texto, isNot(contains('Pedro')));
        expect(texto, isNot(contains('esposa')));
        expect(texto, isNot(contains('Nuestros Hijos')));
      }
      expect(pedro446.toString(), isNot(contains('Pedro')));
    });
  });
}

bool _tieneRegionViva(WidgetTester tester) {
  var viva = false;
  void visitar(SemanticsNode n) {
    if (n.flagsCollection.isLiveRegion) viva = true;
    n.visitChildren((h) {
      visitar(h);
      return true;
    });
  }

  final raiz = tester.binding.renderViews.first.owner!.semanticsOwner?.rootSemanticsNode;
  if (raiz != null) visitar(raiz);
  return viva;
}
