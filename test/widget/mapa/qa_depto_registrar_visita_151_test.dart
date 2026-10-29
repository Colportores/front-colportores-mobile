// QA de «Registrar visita» y el estado de la última visita en la ficha del depto (vista 11·04,
// HU-VIS-005, #151, PR #574): la matriz de estados × tamaños × escala de texto (sin desborde, el botón
// se alcanza, la píldora dice lo que debe), los casos límite que los tests del PR no cubren (el estado
// que falla a mitad de vida, una lectura que se recupera, toques superpuestos, privacidad) y las
// capturas (con `--dart-define=QA_CAPTURAS=true`, a `.dart_tool/qa_capturas/`, nunca se commitean).
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ultima_visita_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_depto_151_arnes.dart';
import 'personas_arnes.dart' show montarClientes;

const _noPudimos = 'No pudimos abrir «Registrar visita». Probá de nuevo.';

Future<void> _bajarHastaElFinal(WidgetTester tester) async {
  final lista = find.byType(ListView);
  for (var i = 0; i < 30; i++) {
    await tester.drag(lista, const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('matriz de estados', () {
    for (final tamano in const [telefonoChico151, telefonoGrande151]) {
      for (final escala in const [1.0, 2.0]) {
        for (final e in Estado151.values) {
          final donde = '${e.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} a $escala×';
          testWidgets('11·04 · $donde: sin desborde y con contenido', (tester) async {
            final destino = await llegar151(tester, e, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull, reason: 'overflow en $donde');

            // La píldora dice lo que la última visita fue; y sin lectura no afirma nada.
            final texto = textoDePildora151(e);
            if (texto == null) {
              expect(pildoraEstado151, findsNothing, reason: 'no se afirma lo que no se sabe');
            } else {
              expect(find.text(texto), findsOneWidget, reason: donde);
            }

            await capturar151(
              tester,
              '${e.name}_${tamano.width.toInt()}x${tamano.height.toInt()}_${escala}x',
            );
            // «Registrar visita»: solo con destino enganchado y el depto activo.
            final hayBoton = e != Estado151.sinDestino && e != Estado151.deptoDeBaja;
            expect(botonRegistrar151, hayBoton ? findsOneWidget : findsNothing, reason: donde);
            if (hayBoton) {
              await tester.ensureVisible(botonRegistrar151);
              await tester.pump();
              final r = tester.getRect(botonRegistrar151);
              expect(r.height, greaterThanOrEqualTo(48));
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(tamano.width + 0.6));
              await tester.scrollUntilVisible(
                botonRegistrar151,
                -200,
                scrollable: find.byType(Scrollable).first,
              );
            }
            if (e == Estado151.avisoDeFalla) {
              expect(find.text(_noPudimos), findsOneWidget);
              expect(destino.contextos, hasLength(1));
            }
            // La nota de privacidad (canvas 11·04) sigue al final de la lista.
            if (e != Estado151.errorDeLectura) {
              await _bajarHastaElFinal(tester);
              expect(
                find.textContaining('Los datos de los clientes quedan solo en tu celular'),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              await tester.drag(find.byType(ListView), const Offset(0, 100000));
              await tester.pump();
            }
          });
        }
      }
    }
  });

  group('casos límite del estado', () {
    testWidgets(
      'dado que la lectura falla DESPUÉS de haber dicho un estado, cuando llega el error, no queda '
      'afirmado un estado viejo como si fuera cierto, y si se recupera vuelve a decir el nuevo',
      (tester) async {
        await cargarFuentes151(tester);
        final lector = LectorControlable151();
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'Ana', minutos: 0)]),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(lector),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(Destino151().llamar),
          ],
        );
        lector.valor(visitaDel20deSeptiembre());
        await asentar(tester);
        expect(find.text('Entrevista hecha · 20/09'), findsOneWidget);

        lector.error(StateError('se cayó la lectura'));
        await asentar(tester);
        expect(tester.takeException(), isNull);
        // La pantalla sigue entera y el botón sigue.
        expect(botonRegistrar151, findsOneWidget);
        // Mientras la lectura está en error, la píldora no debería seguir afirmando «Entrevista hecha»:
        // la HU pide «Mientras se lee, o si la lectura falla, no se afirma ningún estado».
        expect(
          find.text('Entrevista hecha · 20/09'),
          findsNothing,
          reason: 'con la lectura caída se sigue afirmando el estado viejo',
        );

        lector.valor(visitaDel20deSeptiembre(TipoResultadoVisita.rechazo));
        await asentar(tester);
        expect(find.text('Rechazó · 20/09'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que llegan tres cambios de estado seguidos (registrar, deshacer, registrar), cuando se '
      'asienta, la píldora muestra solo el último',
      (tester) async {
        await cargarFuentes151(tester);
        final lector = LectorControlable151();
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(lector),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(Destino151().llamar),
          ],
        );
        lector.valor(null);
        await asentar(tester);
        expect(find.text('Sin visitas todavía'), findsOneWidget);
        lector
          ..valor(visitaDel20deSeptiembre(TipoResultadoVisita.noContesto))
          ..valor(null)
          ..valor(visitaDel20deSeptiembre(TipoResultadoVisita.venta));
        await asentar(tester);
        expect(find.text('Venta · 20/09'), findsOneWidget);
        expect(find.text('Sin visitas todavía'), findsNothing);
        expect(find.text('No contestó · 20/09'), findsNothing);
        expect(pildoraEstado151, findsOneWidget);
      },
    );

    testWidgets(
      'dado que se reentra a la pantalla, cuando el lector cambia entre una entrada y otra, la nueva '
      'entrada lee de cero y no arrastra el estado anterior',
      (tester) async {
        await cargarFuentes151(tester);
        final lector = LectorUltimaVisitaFalso(visitaDel20deSeptiembre());
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(lector),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(Destino151().llamar),
          ],
        );
        expect(find.text('Entrevista hecha · 20/09'), findsOneWidget);
        final lecturas = lector.lecturas;
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);
        lector.cambiarA(visitaDel20deSeptiembre(TipoResultadoVisita.rechazo));
        await tester.tap(find.text('abrir clientes'));
        await asentar(tester);
        expect(find.text('Rechazó · 20/09'), findsOneWidget);
        expect(find.text('Entrevista hecha · 20/09'), findsNothing);
        expect(lector.lecturas, greaterThan(lecturas));
      },
    );

    testWidgets(
      'dado que la fecha de la visita cae a las 02:30 UTC, cuando se muestra, el día es el de la hora '
      'local de quien la mira (no el UTC pelado)',
      (tester) async {
        await cargarFuentes151(tester);
        final cuando = DateTime.utc(2026, 9, 21, 2, 30);
        final local = cuando.toLocal();
        final esperado =
            '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(
              LectorUltimaVisitaFalso(
                UltimaVisitaDelEspacio(resultado: TipoResultadoVisita.entrevista, fecha: cuando),
              ),
            ),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(Destino151().llamar),
          ],
        );
        expect(find.text('Entrevista hecha · $esperado'), findsOneWidget);
      },
    );
  });

  group('casos límite del botón', () {
    testWidgets(
      'dado un toque, cuando el destino está abierto, el botón sigue legible (no queda apagado) y el '
      'segundo toque no abre otra hoja',
      (tester) async {
        await cargarFuentes151(tester);
        final destino = Destino151()..compuerta = Completer<Object?>();
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(LectorUltimaVisitaFalso()),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(destino.llamar),
          ],
        );
        await tester.tap(botonRegistrar151);
        await tester.pump();
        await tester.tap(botonRegistrar151);
        await tester.tap(botonRegistrar151);
        await tester.pump();
        expect(destino.contextos, hasLength(1));
        final boton = tester.widget<FilledButton>(botonRegistrar151);
        expect(boton.onPressed, isNotNull, reason: 'apagado sobre el azul no se lee');
        destino.compuerta!.complete(true);
        await asentar(tester);
        await tester.tap(botonRegistrar151);
        await tester.pump();
        expect(destino.contextos, hasLength(2));
      },
    );

    testWidgets(
      'dado que el destino falla dos veces seguidas, cuando se toca de nuevo, aparece un solo aviso '
      '(no se apilan) y el botón sigue andando',
      (tester) async {
        await cargarFuentes151(tester);
        final destino = Destino151()..lanza = StateError('boom');
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(LectorUltimaVisitaFalso()),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(destino.llamar),
          ],
        );
        for (var i = 0; i < 3; i++) {
          await tester.tap(botonRegistrar151);
          await asentar(tester);
        }
        expect(destino.contextos, hasLength(3));
        expect(find.text(_noPudimos), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado que el aviso de falla está a la vista, cuando se lee con lector de pantalla, el aviso se '
      'anuncia (región viva) y no muestra el detalle técnico del error',
      (tester) async {
        final h = tester.ensureSemantics();
        await cargarFuentes151(tester);
        final destino = Destino151()..lanza = StateError('detalle técnico secreto');
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(LectorUltimaVisitaFalso()),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(destino.llamar),
          ],
        );
        await tester.tap(botonRegistrar151);
        await asentar(tester);
        expect(find.textContaining('detalle técnico'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);
        expect(
          tester.getSemantics(find.text(_noPudimos)),
          isSemantics(label: _noPudimos, isLiveRegion: true),
        );
        h.dispose();
      },
    );

    testWidgets(
      'dado que se vuelve atrás con «¿Qué pasó?» pendiente y se reentra, cuando la vieja termina, la '
      'nueva pantalla no queda con el botón trabado',
      (tester) async {
        await cargarFuentes151(tester);
        final destino = Destino151()..compuerta = Completer<Object?>();
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso(),
          otrosOverrides: [
            lectorUltimaVisitaDelEspacioProvider.overrideWithValue(LectorUltimaVisitaFalso()),
            registrarVisitaDesdeLaCasaProvider.overrideWithValue(destino.llamar),
          ],
        );
        await tester.tap(botonRegistrar151);
        await tester.pump();
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);
        await tester.tap(find.text('abrir clientes'));
        await asentar(tester);
        // La pantalla nueva tiene su propia guarda: se puede tocar aunque la vieja siga pendiente.
        await tester.tap(botonRegistrar151);
        await tester.pump();
        expect(destino.contextos, hasLength(2));
        destino.compuerta!.complete(true);
        await asentar(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('hallazgos', () {
    testWidgets(
      'el texto de «Registrar visita» usa la letra de la app (Inter) como el resto de los botones',
      (tester) async {
        await llegar151(tester, Estado151.entrevista);
        final estilo = DefaultTextStyle.of(tester.element(find.text('Registrar visita'))).style;
        expect(
          estilo.fontFamily,
          'Inter',
          reason:
              'styleFrom(textStyle:) pisa el estilo del tema entero y deja al botón sin la fuente',
        );
      },
      // skip: QA #151 — «Registrar visita» pisa `textStyle` del tema y pierde `fontFamily: Inter`
      // (cae a la letra del sistema, como pasó con «Deshacer» en #473). `QA_HALLAZGOS=true` lo corre.
      skip: !const bool.fromEnvironment('QA_HALLAZGOS'),
    );
  });

  group('encabezado fijo', () {
    testWidgets(
      'dado un depto con 40 clientes a 412×915 y texto 1,0×, cuando se baja la lista, «Registrar '
      'visita» sigue a la vista (el canvas 11·04 deja el encabezado fijo y solo scrollea la lista)',
      (tester) async {
        await llegar151(tester, Estado151.muchosClientes, tamano: telefonoGrande151);
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pump(const Duration(milliseconds: 300));
        expect(botonRegistrar151.hitTestable(), findsOneWidget);
      },
      // skip: QA #151 — el título, el estado y «Registrar visita» (11·04 `flex:none`) van dentro de la
      // lista y salen de la vista al bajar; también «+ Agregar cliente», que antes de #574 era fijo.
      skip: !const bool.fromEnvironment('QA_HALLAZGOS'),
    );
  });

  group('privacidad', () {
    test('la última visita no lleva personas ni notas y su toString no muestra nada de eso', () {
      final u = visitaDel20deSeptiembre();
      final texto = u.toString();
      expect(texto, isNot(contains('persona')));
      expect(texto, isNot(contains('nota')));
      expect(texto, isNot(contains('telefono')));
    });
  });
}
