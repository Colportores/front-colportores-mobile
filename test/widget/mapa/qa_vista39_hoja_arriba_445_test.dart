// QA de la hoja de la casa arriba (vista 39, C·02 «Hoja arriba · Personas», HU-UBI-003, #445, PR #476):
// los estados que una persona puede alcanzar en la matriz de tamaños (360×640, 412×915) y escalas de
// texto (1,0 y 2,0), el texto literal de la HU y del canvas, los casos límite de cada flujo y el camino
// real por el mapa (subir la hoja) y por la Lista.
//
// Con fuentes reales (sin ellas `flutter_test` pinta cajas Ahem y las medidas mienten). Las guías de
// contraste van en `qa_vista39_hoja_arriba_445_guias_test.dart` (con la fuente de prueba).
// Capturas: `--dart-define=QA_CAPTURAS=true` → `.dart_tool/qa_capturas/445_*.png` (nunca se commitean).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_persona.dart'
    show ClavesAvisoPrivacidad;
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart';
import '../../helpers/qa_vista39_445_aviso_arnes.dart';
import 'personas_arnes.dart' show asentar;

/// Los tests con `skip` documentan un hallazgo: `--dart-define=QA_HALLAZGOS=true` los corre.
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _nbsp = ' ';

Finder get _agregar => find.byKey(ClavesHojaCasa.agregarPersona);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _pestanas => find.byKey(ClavesHojaCasa.pestanas);
Finder get _filas => find.byType(FilaPersonaDeLaCasa);

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

void main() {
  group('Matriz de estados × tamaños × escalas (sin overflow, contenido alcanzable)', () {
    for (final estado in Estado445.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets('${estado.name} · ${sufijo445(tamano, escala)}', (tester) async {
            await cargarFuentes205(tester);
            await llegarA445(tester, estado, tamano: tamano, escala: escala);
            await asentar(tester);

            expect(
              tester.takeException(),
              isNull,
              reason: 'overflow o excepción en ${estado.name}',
            );
            expect(find.text('Grecia 3310'), findsOneWidget);

            switch (estado) {
              case Estado445.c02Produccion:
              case Estado445.c02Pestanas:
                expect(_registrar, findsOneWidget);
                expect(_pestanas, findsOneWidget);
                expect(find.text('Pedro Gómez'), findsOneWidget);
                expect(find.text('Ana Gómez'), findsOneWidget);
                expect(find.text('Debe \$${_nbsp}1.200'), findsOneWidget);
                expect(find.text('Entrevista dada el 05/10'), findsOneWidget);
                await tester.ensureVisible(_agregar);
                await tester.pump();
                expect(_agregar, findsOneWidget);
              case Estado445.sinPersonas:
                expect(find.text('Todavía no hay personas acá.'), findsOneWidget);
                await tester.ensureVisible(_agregar);
                expect(_agregar, findsOneWidget);
              case Estado445.sesentaPersonas:
                expect(_filas, findsNWidgets(60));
                await tester.ensureVisible(_agregar);
                await tester.pump();
                expect(_agregar, findsOneWidget);
              case Estado445.nombresLargos:
                expect(find.textContaining('Maximiliano Alejandro'), findsOneWidget);
                await tester.ensureVisible(_agregar);
                expect(_agregar, findsOneWidget);
              case Estado445.cargando:
                expect(find.byKey(ClavesEstadosHojaCasa.cargando), findsOneWidget);
                expect(_agregar, findsNothing);
              case Estado445.errorAlLeer:
                expect(find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeer), findsOneWidget);
                expect(find.text('Reintentar'), findsOneWidget);
              case Estado445.dadaDeBaja:
                expect(find.byKey(ClavesEstadosHojaCasa.avisoDadaDeBaja), findsOneWidget);
                expect(_agregar, findsNothing);
                expect(_registrar, findsNothing);
                expect(find.text('Pedro Gómez'), findsOneWidget, reason: 'solo lectura: se ve');
              case Estado445.lejos:
                expect(find.byKey(ClavesEstadosHojaCasa.avisoLejos), findsOneWidget);
                expect(_registrar, findsOneWidget, reason: 'lejos avisa y no frena');
                await tester.ensureVisible(_agregar);
                expect(_agregar, findsOneWidget);
              case Estado445.fallaAlAbrirFicha:
                expect(find.text('No pudimos abrir la ficha. Probá de nuevo.'), findsOneWidget);
            }
            await capturar445(tester, '${estado.name}_${sufijo445(tamano, escala)}');
          });
        }
      }
    }
  });

  group('Texto literal de la HU-UBI-003 / canvas C·02', () {
    testWidgets('dado el canvas, los rótulos son los del diseño', (tester) async {
      await cargarFuentes205(tester);
      await llegarA445(tester, Estado445.c02Pestanas);
      for (final t in [
        'Grecia 3310',
        '✓  Registrar visita',
        'Personas',
        'Historial',
        'Notas',
        'Pedro Gómez',
        'Debe \$${_nbsp}1.200',
        '\$ Cobrar',
        'Ana Gómez',
        'Entrevista dada el 05/10',
        '+ Agregar persona',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(
        find.text(TextosHojaCasa.notaDelLugar),
        findsNothing,
        reason: 'con Notas la nota va en su pestaña',
      );
    });

    testWidgets('el subtítulo dice tipo · estado · distancia como el canvas', (tester) async {
      await cargarFuentes205(tester);
      await llegarA445(tester, Estado445.c02Produccion);
      final texto = tester
          .widget<Text>(find.byKey(ClavesHojaCasa.subtitulo))
          .data!
          .replaceAll(' ', ' ');
      expect(texto, 'Casa · Cobranza pendiente · a 20 m de vos');
      expect(FormatoHojaCasa, isNotNull);
    });
  });

  group('Casos límite adicionales', () {
    testWidgets('nombre con emoji y espacios sobrantes: iniciales y nombre sin romper', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      await montarHoja445(
        tester,
        contexto: contextoCon([
          clienteDePersonas('e1', '😀 Ana', apellido: '   '),
          clienteDePersonas('e2', '   ', apellido: 'Solo apellido'),
          clienteDePersonas('e3', 'Zoë', apellido: 'Ñandú'),
        ]),
      );
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(_filas, findsNWidgets(3));
      expect(find.text('😀 Ana'), findsOneWidget);
      expect(
        find.text('😀'),
        findsOneWidget,
        reason: 'la inicial es el emoji entero, no media pareja',
      );
      expect(find.text('S'), findsOneWidget);
      expect(find.text('ZÑ'), findsOneWidget);
    });

    testWidgets('el contexto cambia mientras la hoja está abierta: la lista sigue al dato', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      final c = StreamController<ContextoDeLaCasa>();
      addTearDown(c.close);
      await montarHoja445(tester, lectura: c.stream);
      c.add(contextoCon([pedroGomez]));
      await asentar(tester);
      expect(_filas, findsNWidgets(1));
      c.add(contextoC02);
      await asentar(tester);
      expect(_filas, findsNWidgets(2));
      c.add(contextoCon(const []));
      await asentar(tester);
      expect(_filas, findsNothing);
      expect(find.text('Todavía no hay personas acá.'), findsOneWidget);
      expect(_agregar, findsOneWidget, reason: 'sin personas igual se puede agregar la primera');
    });

    testWidgets('error al leer: Reintentar vuelve a leer y muestra la hoja', (tester) async {
      await cargarFuentes205(tester);
      var intento = 0;
      await montarHoja445(
        tester,
        lecturaFn: () => ++intento == 1
            ? Stream<ContextoDeLaCasa>.error(StateError('x'))
            : Stream.value(contextoC02),
      );
      await asentar(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Reintentar'), findsNothing);
      expect(_filas, findsNWidgets(2), reason: 'después de reintentar se ve la hoja');
    });

    testWidgets('mensaje de error sin PII: la falla al abrir la ficha no repite el nombre', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      await montarHoja445(tester, ficha: (_) => throw StateError('Pedro Gómez 099123456'));
      await tester.tap(find.byKey(ClavesHojaCasa.abrirPersona).first);
      await asentar(tester);
      expect(find.textContaining('099123456'), findsNothing);
      expect(find.text('No pudimos abrir la ficha. Probá de nuevo.'), findsOneWidget);
    });

    testWidgets('el aviso de una falla es una región viva y la persona sigue pudiendo reintentar', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      final semantica = tester.ensureSemantics();
      var fallar = true;
      final m = await montarHoja445(
        tester,
        ficha: (_) {
          if (fallar) throw StateError('x');
        },
      );
      await tester.tap(find.byKey(ClavesHojaCasa.abrirPersona).first);
      await asentar(tester);
      final aviso = find.text('No pudimos abrir la ficha. Probá de nuevo.');
      expect(aviso, findsOneWidget);
      var vivo = false;
      for (final nodo in [tester.getSemantics(aviso)]) {
        SemanticsNode? n = nodo;
        while (n != null) {
          // ignore: deprecated_member_use
          if (n.hasFlag(SemanticsFlag.isLiveRegion)) vivo = true;
          n = n.parent;
        }
      }
      expect(vivo, isTrue, reason: 'el aviso se tiene que anunciar al lector de pantalla');
      fallar = false;
      await tester.tap(find.byKey(ClavesHojaCasa.abrirPersona).first);
      await asentar(tester);
      expect(m.fichas, hasLength(2), reason: 'después de la falla se puede volver a tocar');
      expect(aviso, findsNothing);
      semantica.dispose();
    });

    testWidgets('la hoja sin colportorId no ofrece «+ Agregar persona» (ante la duda, bloquea)', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      await montarHoja445(tester, colportorId: null);
      expect(_agregar, findsNothing);
      expect(_filas, findsNWidgets(2));
    });
  });
  group('Éxito del alta: «+ Agregar persona» → guardar → «Guardamos a X en este teléfono.»', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets(sufijo445(tamano, escala), (tester) async {
          await cargarFuentes205(tester);
          final m = await montarHoja445(tester, tamano: tamano, escala: escala);
          await tester.ensureVisible(_agregar);
          await tester.pump();
          await tester.tap(_agregar);
          await asentar(tester);
          expect(find.text('Nueva persona'), findsOneWidget);
          await tester.enterText(
            find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.hintText == 'Obligatorio',
            ),
            'Jorge Ñandú',
          );
          await tester.pump();
          await tester.ensureVisible(find.widgetWithText(FilledButton, 'Guardar persona'));
          await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
          await asentar(tester);

          expect(tester.takeException(), isNull);
          expect(m.repo.recibidas, hasLength(1));
          expect(find.text('Guardamos a Jorge Ñandú en este teléfono.'), findsOneWidget);
          expect(find.text('Nueva persona'), findsNothing, reason: 'vuelve a la hoja de la casa');
          await capturar445(tester, 'alta_exitosa_${sufijo445(tamano, escala)}');
        });
      }
    }
  });

  group('Privacidad', () {
    test(
      'ContextoDeLaCasa no filtra nombres, teléfonos ni notas por toString (stringify en true)',
      () {
        final original = EquatableConfig.stringify;
        EquatableConfig.stringify = true;
        addTearDown(() => EquatableConfig.stringify = original);

        final texto = '$contextoC02 ${contextoC02.personas.first} ${contextoC02.nota}';

        expect(texto, isNot(contains('Pedro')));
        expect(texto, isNot(contains('Gómez')));
        expect(texto, isNot(contains('Perro suelto')));
      },
    );
  });

  group('Producción hoy: sin ficha ni cobro enganchados (solo «Registrar visita»)', () {
    testWidgets('las filas son solo texto, sin «›» ni «\$ Cobrar», y «+ Agregar persona» sigue', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      await montarHoja445(tester, conFicha: false);
      await asentar(tester);
      expect(find.text('›'), findsNothing);
      expect(find.byKey(ClavesHojaCasa.abrirPersona), findsNothing);
      expect(_agregar, findsOneWidget);
      expect(_pestanas, findsOneWidget);
      expect(find.text('Historial'), findsNothing);
      await capturar445(tester, 'produccion_sin_ficha');
    });
  });

  group('Hallazgos (skip: QA #445)', () {
    // skip: QA #445 — las iniciales del avatar de 34 dp se parten en dos renglones y se cortan con el
    // texto al 200 % («P» arriba, «G» tapada abajo): FilaPersonaDeLaCasa fija 34×34 y el texto escala.
    testWidgets('a texto 2,0 las iniciales del avatar caben en el círculo sin partirse', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      await montarHoja445(tester, escala: 2, tamano: t412x915);
      await asentar(tester);
      final parrafo = tester.renderObject<RenderParagraph>(find.text('PG'));
      final alto = parrafo.getMaxIntrinsicHeight(34);
      expect(
        alto,
        lessThanOrEqualTo(34),
        reason: 'las iniciales «PG» miden $alto dp de alto en 34 dp de ancho',
      );
      expect(parrafo.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(34));
    }, skip: !_verHallazgos);

    // skip: QA #445 — con «No volver a mostrar» fallando, a 360×640 y texto 2,0 el aviso rojo queda debajo
    // de la pantalla (fuera de la vista) y la persona no ve nada pasar: a diferencia de HojaCasa, el alta no
    // lleva el aviso a la vista (`Scrollable.ensureVisible`).
    testWidgets(
      'si «No volver a mostrar» no se pudo guardar, el aviso de la falla queda a la vista a 360×640 y 2,0×',
      (tester) async {
        await cargarFuentes205(tester);
        await llegarAlAviso445(tester, EstadoAviso445.falla, tamano: t360x640, escala: 2);
        final r = tester.getRect(find.byKey(ClavesAvisoPrivacidad.falla));
        expect(
          r.bottom,
          lessThanOrEqualTo(640 - 72),
          reason: 'el aviso está en ${r.top}..${r.bottom}',
        );
      },
      skip: !_verHallazgos,
    );
  });
}
