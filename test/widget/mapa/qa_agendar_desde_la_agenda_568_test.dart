// QA de #568 («+ Agendar» de la pestaña Agenda → elegir la casa en la lista de ubicaciones → «¿Con
// quién?» → «Agendar visita»; decisión de Cristian 04/11, «Agendar pest.»). Complementa los tests del
// implementador con lo que no cubren: la pantalla dentro del `IndexedStack` de `InicioPage` (con la
// pestaña Lista viva, que comparte el estado), acciones superpuestas, salir a mitad de la lectura,
// «+ Agendar» del rótulo de un día con visitas y la matriz de estados × tamaños × texto.
// Los tests con `skip` documentan un hallazgo: se corren con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/elegir_casa_para_agendar_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_agendar_desde_la_agenda_568_arnes.dart';

final _seleccion = find.byKey(ClavesElegirCasaParaAgendar.pantalla);
final _formulario = find.byType(AgendarVisitaPage);
final _guardar = find.byKey(ClavesAgendarVisita.botonAgendar);
final _agendarDeLaAgenda = find.text('+ Agendar');
final _atras = find.byType(BackButton);

Future<void> _tocarAgendar(WidgetTester tester) async {
  await tester.ensureVisible(_agendarDeLaAgenda.first);
  await tester.pump();
  await tester.tap(_agendarDeLaAgenda.first);
  await asentarAgendar(tester);
}

Future<void> _elegirCasa(WidgetTester tester, String direccion) async {
  await tester.tap(find.text(direccion));
  await asentarAgendar(tester);
}

void main() {
  group('la pestaña Lista sigue viva debajo (así monta InicioPage)', () {
    // Hallazgo de QA #568 resuelto: el selector tiene su estado propio (no hereda la búsqueda de la Lista).
    probar568(
      'el selector arranca con la lista completa aunque la pestaña Lista tenga una búsqueda',
      (tester) async {
        final m = await montar568(tester);
        // Lucía buscó «Rivera» en la pestaña Lista antes de pasar a la Agenda.
        m.contenedor.read(listaUbicacionesProvider('col-1').notifier).buscar('Rivera');
        await asentarAgendar(tester);

        await _tocarAgendar(tester);

        expect(_seleccion, findsOneWidget);
        // El selector es otra lista: tiene que mostrar las casas, no las de una búsqueda ajena. Y si
        // filtra, el campo tiene que decirlo.
        final campo = find.descendant(of: _seleccion, matching: find.byType(TextField));
        final texto = tester.widget<TextField>(campo.first).controller?.text ?? '';
        final filtra = find.text('Mataojo 2044').evaluate().isEmpty;
        expect(
          filtra && texto.isEmpty,
          isFalse,
          reason: 'la lista del selector está filtrada ("Rivera") y el buscador se ve vacío',
        );
      },
    );

    // Hallazgo de QA #568 resuelto: lo escrito en el selector no se pega a la pestaña Lista.
    probar568('una búsqueda hecha en el selector no queda en la pestaña Lista al volver', (
      tester,
    ) async {
      final m = await montar568(tester);
      await _tocarAgendar(tester);
      final campo = find.descendant(of: _seleccion, matching: find.byType(TextField));
      await tester.enterText(campo.first, 'Rivera');
      await asentarAgendar(tester);
      expect(find.text('Mataojo 2044'), findsNothing);

      await tester.tap(_atras);
      await asentarAgendar(tester);

      final estado = m.contenedor.read(listaUbicacionesProvider('col-1'));
      expect(estado.filtros.busqueda, isEmpty, reason: 'el selector dejó su búsqueda en la Lista');
    });

    probar568('con la Lista viva el flujo completo agenda en la casa elegida', (tester) async {
      final m = await montar568(tester);
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Rivera 77');

      expect(_formulario, findsOneWidget);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);
      expect(m.agendas.recibidas.single.agenda.espacioId, 'esp-2');
      expect(tester.takeException(), isNull);
    });
  });

  group('acciones superpuestas y salidas a mitad de camino', () {
    probar568('tocar la casa A y enseguida la B, antes de que termine la lectura, abre solo la A', (
      tester,
    ) async {
      final m = await montar568(tester);
      m.espacios.compuerta = Completer<void>();
      await _tocarAgendar(tester);

      await tester.tap(find.text('Mataojo 2044'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Rivera 77'));
      await tester.pump(const Duration(milliseconds: 60));
      m.espacios.compuerta!.complete();
      await asentarAgendar(tester);

      expect(m.espacios.listados, 1);
      expect(_formulario, findsOneWidget);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);
      expect(m.agendas.recibidas, hasLength(1));
      expect(m.agendas.recibidas.single.agenda.espacioId, 'esp-1');
    });

    probar568('volver atrás mientras se lee la casa: no abre el formulario ni se traba', (
      tester,
    ) async {
      final m = await montar568(tester);
      m.espacios.compuerta = Completer<void>();
      await _tocarAgendar(tester);
      await tester.tap(find.text('Mataojo 2044'));
      await tester.pump(const Duration(milliseconds: 60));

      await tester.tap(_atras);
      await asentarAgendar(tester);
      m.espacios.compuerta!.complete();
      await asentarAgendar(tester);

      expect(_seleccion, findsNothing);
      expect(_formulario, findsNothing);
      expect(m.agendas.recibidas, isEmpty);
      expect(tester.takeException(), isNull);
      // Reentrada: el botón sirve y la lista abre.
      m.espacios.compuerta = null;
      await _tocarAgendar(tester);
      expect(_seleccion, findsOneWidget);
      await _elegirCasa(tester, 'Rivera 77');
      expect(_formulario, findsOneWidget);
    });

    probar568('el gesto de volver del sistema, en cada paso, cancela sin agendar', (tester) async {
      final m = await montar568(
        tester,
        personas: [
          mariaFernandez,
          clienteDePersonas('p2', 'Pedro', apellido: 'Gómez'),
        ],
      );
      await _tocarAgendar(tester);
      expect(_seleccion, findsOneWidget);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(_seleccion, findsNothing);

      await _tocarAgendar(tester);
      await _elegirCasa(tester, 'Mataojo 2044');
      expect(find.text('Todavía no sé con quién'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(find.text('Todavía no sé con quién'), findsNothing);
      expect(_formulario, findsNothing);

      await _tocarAgendar(tester);
      await _elegirCasa(tester, 'Mataojo 2044');
      await tester.tap(find.text('Todavía no sé con quién'));
      await asentarAgendar(tester);
      expect(_formulario, findsOneWidget);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(_formulario, findsNothing);
      expect(_agendarDeLaAgenda, findsOneWidget);
      expect(m.agendas.recibidas, isEmpty);
    });

    probar568('«+ Agendar» del rótulo de un día con visitas lleva al mismo flujo', (tester) async {
      final m = await montar568(
        tester,
        items: [itemAgenda('a-1', DateTime(2026, 10, 23, 16, 0), ubicacionId: 'u-1')],
      );
      expect(_agendarDeLaAgenda, findsOneWidget);

      await _tocarAgendar(tester);

      expect(_seleccion, findsOneWidget);
      await _elegirCasa(tester, 'Mataojo 2044');
      expect(_formulario, findsOneWidget);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);
      expect(m.agendas.recibidas.single.agenda.espacioId, 'esp-1');
    });

    probar568('una casa sin espacio y después un edificio: ambos avisan y la lista sigue usable', (
      tester,
    ) async {
      final m = await montar568(
        tester,
        filas: [
          filaLista('u-1', calle: 'Mataojo', numero: '2044'),
          filaLista('u-3', tipo: TipoUbicacion.edificio, calle: 'Av. Italia', numero: '1240'),
          filaLista('u-5', calle: 'Bulevar', numero: '9'),
        ],
      );
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Bulevar 9');
      expect(find.text(TextosElegirCasaParaAgendar.sinLugar), findsOneWidget);
      await _elegirCasa(tester, 'Av. Italia 1240');
      expect(find.text(TextosRegistrarVisita.edificioSinDeptoParaAgendar), findsOneWidget);
      expect(_seleccion, findsOneWidget);
      await _elegirCasa(tester, 'Mataojo 2044');
      expect(_formulario, findsOneWidget);
      expect(m.espacios.listados, 2);
    });

    // Hallazgo de QA #568 resuelto (decisión del mapa §2): el aviso del edificio habla de agendar.
    probar568('el aviso del edificio dice qué hacer en vez de hablar de «registrar visitas»', (
      tester,
    ) async {
      await montar568(
        tester,
        filas: [
          filaLista('u-3', tipo: TipoUbicacion.edificio, calle: 'Av. Italia', numero: '1240'),
        ],
      );
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Av. Italia 1240');

      // El usuario quería AGENDAR y el aviso habla de REGISTRAR; no dice cómo llegar al depto.
      expect(find.textContaining('agendar'), findsWidgets);
    });
  });

  group('texto grande', () {
    for (final tam in tamanos) {
      // skip: QA #568 — el título «Elegí la casa de la visita» de la barra se corta con puntos
      // suspensivos a ×2 («Elegí la casa de l…»).
      probar568(
        'el título del selector se lee entero a ${tam.width.toInt()} dp con texto ×2',
        (tester) async {
          await montar568(tester, tamano: tam, escala: 2);
          await _tocarAgendar(tester);

          final titulo = find.text(TextosElegirCasaParaAgendar.titulo);
          expect(titulo, findsOneWidget);
          final render = tester.renderObject<RenderParagraph>(
            find.descendant(of: titulo, matching: find.byType(RichText)).first,
          );
          expect(render.didExceedMaxLines, isFalse, reason: 'el título quedó cortado con «…»');
        },
        skip: !verHallazgos,
      );
    }
  });

  group('sin tamaño ni escala que rompan el flujo', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        probar568(
          'flujo completo a ${tam.width.toInt()}×${tam.height.toInt()} con texto ×$escala',
          (tester) async {
            final m = await montar568(
              tester,
              tamano: tam,
              escala: escala,
              personas: [
                mariaFernandez,
                clienteDePersonas('p2', 'Pedro', apellido: 'Gómez'),
              ],
            );
            await _tocarAgendar(tester);
            await _elegirCasa(tester, 'Mataojo 2044');
            await tester.scrollUntilVisible(
              find.text('Todavía no sé con quién'),
              80,
              scrollable: find
                  .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
                  .first,
            );
            await tester.tap(find.text('Todavía no sé con quién'));
            await asentarAgendar(tester);
            await tester.ensureVisible(_guardar);
            await tester.tap(_guardar);
            await asentarAgendar(tester);

            expect(m.agendas.recibidas, hasLength(1));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
