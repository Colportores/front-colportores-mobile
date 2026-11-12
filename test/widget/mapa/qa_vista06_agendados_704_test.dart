// QA de #704 · vista 06, 06C·03 «Hoja a 1/2 · Agendados» (HU-VIS-002): la hoja en el teléfono real
// (360x640 y 412x915, texto a 1,0 y a 2,0, con las fuentes reales), sus estados, las pestañas con el
// texto grande y los casos límite que los tests del implementador (pantalla de 390x2000) no miran.
//
// Los que documentan un hallazgo abierto (H4 y H5, menores) van con `skip` salvo con
// `--dart-define=QA_HALLAZGOS=true`. H1 a H3 quedaron resueltos por las decisiones del 11/11 (P1 y P2
// del QA de #704: «Agendados» sube la hoja a la mitad y los chips van en una fila que se desplaza de
// costado) y corren siempre:
//  · H1: con el texto a 2,0 «Reintentar» del error al leer está a la vista al abrir la hoja.
//  · H2: en el estado vacío «+ Agendar» está a la vista al abrir la hoja.
//  · H3: los chips van en una fila y a 360x640 se ve al menos una visita al abrir la hoja.
//  · H5: a 360x640 con el texto a 2,0 la columna de la fila queda en ~100 dp y parte «Cobranza»,
//    «Entrevista», «Comercio», «Michigan» y «Mataojo» a mitad de palabra.
//  · H4: con el texto a 3,0 «Agendados» se parte en dos renglones a mitad de palabra.
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_agendados.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista06_agendados_704_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// `skip` de los tests que documentan un hallazgo (`skip` es `bool?`: el motivo va en el nombre del
/// test y en este encabezado).
const _skipH = !_hallazgos;

void main() {
  group(
    'matriz: cada estado en cada tamaño, sin desbordes y con la hoja dentro de la pantalla',
    () {
      for (final MapEntry(key: nombreTamano, value: tamano) in tamanos704.entries) {
        for (final escala in [1.0, 2.0]) {
          for (final MapEntry(key: nombre, value: armar) in escenas704.entries) {
            testWidgets('$nombre · $nombreTamano · texto $escala', (tester) async {
              await cargarFuentes704(tester);
              await armar(tester, tamano, escala);

              expect(tester.takeException(), isNull);
              final h = tester.getRect(hoja);
              expect(h.bottom, lessThanOrEqualTo(tamano.height + 0.5));
              expect(h.top, greaterThanOrEqualTo(0));
              await capturar704(tester, '$nombre $nombreTamano x$escala');
            });
          }
        }
      }
    },
  );

  group('las filas de 06C·03 en el teléfono', () {
    for (final MapEntry(key: nombreTamano, value: tamano) in tamanos704.entries) {
      for (final escala in [1.0, 2.0]) {
        if (nombreTamano == '360x640' && escala == 2.0) continue; // H5, abajo
        testWidgets('ninguna palabra de las filas se parte a mitad de palabra · $nombreTamano · '
            'texto $escala', (tester) async {
          await cargarFuentes704(tester);
          await montarAgendados(tester, tamano: tamano, escala: escala);
          await abrirAgendados(tester);

          final partidos = <String>[];
          for (final id in ['atr', 'cuota', 'entrevista', 'entrega', 'manana']) {
            await verFila(tester, id);
            await tester.pump();
            partidos.addAll(textosPartidos(tester, fila407(id)));
            await capturar704(tester, 'fila $id $nombreTamano x$escala');
          }
          expect(partidos, isEmpty, reason: 'palabras partidas: $partidos');
        });
      }
    }
  });

  group('las pestañas «Cercanía» y «Agendados» con el texto grande y el teléfono angosto', () {
    for (final ancho in [320.0, 360.0, 412.0]) {
      for (final escala in [1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.5]) {
        testWidgets('${ancho.toInt()} dp · texto $escala: textos enteros, sin desborde y dentro de '
            'la hoja minimizada', (tester) async {
          await cargarFuentes704(tester);
          await montarAgendados(tester, tamano: Size(ancho, 700), escala: escala);

          expect(tester.takeException(), isNull);
          final pantalla = Size(ancho, 700);
          for (final p in [pestanaAgendados, find.byKey(ClavesAgendados.pestana)]) {
            expect(enLaHoja(tester, p, pantalla), isTrue, reason: 'la pestaña queda en la hoja');
          }
          final textos = textosPartidos(tester, hoja);
          expect(textos, isEmpty, reason: 'texto partido: $textos');
          // Los dos nombres se leen enteros (sin «…»).
          for (final nombre in ['Cercanía', 'Agendados']) {
            final p = find.descendant(of: hoja, matching: find.text(nombre));
            final lineas = tester.getSize(p).height / (14.5 * escala);
            expect(lineas, lessThan(1.8), reason: '«$nombre» ocupa más de un renglón');
          }
        });
      }
    }
  });

  group('estados: la salida de cada aviso se alcanza y se toca en el teléfono', () {
    for (final MapEntry(key: nombreTamano, value: tamano) in tamanos704.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('error al leer: «Reintentar» se alcanza, se toca y vuelve a leer · '
            '$nombreTamano · texto $escala', (tester) async {
          await cargarFuentes704(tester);
          final m = await escenas704['Agendados error al leer al abrirla']!(tester, tamano, escala);

          final reintentar = find.text('Reintentar');
          expect(reintentar, findsOneWidget);
          await tester.ensureVisible(reintentar);
          await tester.pump();
          final pedidos = m.consulta.pedidos.length;
          m.consulta.error = null;
          await tester.tap(reintentar);
          await asentarLista(tester);
          expect(m.consulta.pedidos.length, greaterThan(pedidos));
          expect(find.byKey(ClavesAgendados.error), findsNothing);
        });

        testWidgets('vacía: «+ Agendar» se alcanza y se toca una sola vez · $nombreTamano · '
            'texto $escala', (tester) async {
          await cargarFuentes704(tester);
          final m = await escenas704['Agendados vacia al abrirla']!(tester, tamano, escala);

          expect(find.text('No tenés visitas en los próximos 7 días'), findsOneWidget);
          final agendar = find.text('+ Agendar');
          await tester.ensureVisible(agendar);
          await tester.pump();
          await tester.tap(agendar);
          await tester.tap(agendar, warnIfMissed: false);
          await asentarLista(tester);
          expect(m.agendados, 1);
        });

        testWidgets('filtro sin resultados: «Limpiar filtros» se alcanza y devuelve la lista · '
            '$nombreTamano · texto $escala', (tester) async {
          await cargarFuentes704(tester);
          final m = await montarAgendados(
            tester,
            tamano: tamano,
            escala: escala,
            items: [agendado('e1', dia407(10), ubicacionId: 'u-italia')],
          );
          await abrirAgendados(tester);
          await tester.ensureVisible(chip407(TipoAgenda.entrega));
          await tester.pump();
          await tocarChip(tester, TipoAgenda.entrega);
          await asentarLista(tester);

          final limpiar = find.text('Limpiar filtros');
          await tester.ensureVisible(limpiar);
          await tester.pump();
          await tester.tap(limpiar);
          await asentarLista(tester);
          expect(find.byKey(ClavesAgendados.sinResultados), findsNothing);
          expect(m.mapa.mapa.config!.puntos.where((p) => !p.atenuado), isNotEmpty);
        });
      }
    }

    // — Hallazgos: lo que la colportora ve sin desplazar la hoja a la altura a la que la deja la app. —
    for (final (nombreTamano, escala) in [('360x640', 2.0)]) {
      testWidgets(
        'H1 · error al leer: «Reintentar» está a la vista al abrir la hoja · $nombreTamano · '
        'texto $escala',
        (tester) async {
          await cargarFuentes704(tester);
          final tamano = tamanos704[nombreTamano]!;
          await escenas704['Agendados error al leer al abrirla']!(tester, tamano, escala);

          final reintentar = find.text('Reintentar');
          expect(
            enLaHoja(tester, reintentar, tamano),
            isTrue,
            reason: 'Reintentar en ${tester.getRect(reintentar)}, hoja en ${tester.getRect(hoja)}',
          );
        },
      );
    }

    testWidgets('H2 · vacía: «+ Agendar» está a la vista al abrir la hoja · 412x915 · texto 1,0', (
      tester,
    ) async {
      await cargarFuentes704(tester);
      final tamano = tamanos704['412x915']!;
      await escenas704['Agendados vacia al abrirla']!(tester, tamano, 1);

      final agendar = find.text('+ Agendar');
      expect(
        enLaHoja(tester, agendar, tamano),
        isTrue,
        reason: '+ Agendar en ${tester.getRect(agendar)}, hoja en ${tester.getRect(hoja)}',
      );
    });

    testWidgets('H3 · al abrir la hoja en el teléfono chico se ve al menos una visita · 360x640 · '
        'texto 1,0', (tester) async {
      await cargarFuentes704(tester);
      final tamano = tamanos704['360x640']!;
      await escenas704['06C·03 Agendados al abrirla']!(tester, tamano, 1);

      final h = tester.getRect(hoja);
      final filas = filasDeAgendados.evaluate().where((e) {
        final r = tester.getRect(find.byWidget(e.widget));
        return r.top >= h.top && r.bottom <= h.bottom + 0.5;
      });
      expect(filas, isNotEmpty, reason: 'solo se ven las pestañas y los chips');
    });

    testWidgets(
      'H5 · en las filas ninguna palabra se parte a mitad de palabra · 360x640 · texto 2,0',
      (tester) async {
        await cargarFuentes704(tester);
        await montarAgendados(tester, tamano: tamanos704['360x640']!, escala: 2);
        await abrirAgendados(tester);

        final partidos = <String>[];
        for (final id in ['atr', 'cuota', 'entrevista', 'entrega', 'manana']) {
          await verFila(tester, id);
          await tester.pump();
          partidos.addAll(textosPartidos(tester, fila407(id)));
          await capturar704(tester, 'H5 fila $id 360x640 x2.0');
        }
        expect(partidos, isEmpty, reason: 'palabras partidas: $partidos');
      },
      skip: _skipH,
    );

    testWidgets('H4 · con el texto a 3,0 «Agendados» no se parte · 360x640', (tester) async {
      await cargarFuentes704(tester);
      await montarAgendados(tester, tamano: tamanos704['360x640']!, escala: 3);

      expect(textosPartidos(tester, hoja), isEmpty);
    }, skip: _skipH);
  });

  group('casos límite del flujo', () {
    testWidgets('cinco cambios de pestaña seguidos sin esperar: queda la última, con su lista y '
        'sin estado trabado', (tester) async {
      await cargarFuentes704(tester);
      final m = await montarAgendados(tester, tamano: tamanos704['412x915']!);
      for (var i = 0; i < 5; i++) {
        await tester.tap(pestanaAgendados);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(find.byKey(ClavesMapaUbicaciones.pestanaCercania));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(pestanaAgendados);
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAgendados.lista), findsOne);
      expect(m.mapa.mapa.config!.puntos.where((p) => p.atenuado), isNotEmpty);
    });

    testWidgets('una visita sin casa ni dirección (la casa de baja) no revienta la hoja: dice la '
        'persona y no inventa distancia', (tester) async {
      await cargarFuentes704(tester);
      final sinCasa = agendado('sin-casa', dia407(12), ubicacionId: 'u-x', calle: '', numero: '');
      await montarAgendados(
        tester,
        tamano: tamanos704['412x915']!,
        items: [...agendaDelCanvas(), sinCasa],
      );
      await abrirAgendados(tester);

      expect(tester.takeException(), isNull);
      await verFila(tester, 'sin-casa');
      expect(fila407('sin-casa'), findsOne);
    });

    testWidgets('60 visitas en el teléfono chico: se llega a la última y se toca · 360x640 · '
        'texto 2,0', (tester) async {
      await cargarFuentes704(tester);
      final muchas = [
        for (var i = 0; i < 60; i++)
          agendado(
            'm$i',
            dia407(8 + i % 12, dias: i ~/ 12, minuto: i % 4 * 15),
            ubicacionId: 'u-italia',
            metros: 40.0 + i * 20,
          ),
      ];
      final m = await montarAgendados(
        tester,
        tamano: tamanos704['360x640']!,
        escala: 2,
        items: muchas,
      );
      await abrirAgendados(tester);
      await tester.pump();

      expect(find.byKey(ClavesAgendados.lista), findsOne);
      await tester.scrollUntilVisible(
        fila407('m59'),
        400,
        maxScrolls: 400,
        scrollable: listaDeAgendados,
      );
      await tester.pump();
      await tester.tap(fila407('m59'));
      await asentarLista(tester);
      expect(m.detalles, ['m59']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('las distancias lejanas se dicen en km y no rompen la fila', (tester) async {
      await cargarFuentes704(tester);
      await montarAgendados(
        tester,
        tamano: tamanos704['360x640']!,
        items: [
          agendado('lejos', dia407(9), ubicacionId: 'u-italia', metros: 12345),
          agendado('mas', dia407(10), ubicacionId: 'u-italia', metros: 999),
        ],
      );
      await abrirAgendados(tester);

      await verFila(tester, 'lejos');
      expect(find.descendant(of: fila407('lejos'), matching: find.textContaining('km')), findsOne);
      await verFila(tester, 'mas');
      expect(tester.takeException(), isNull);
    });

    testWidgets('el lector lee cada pestaña con su cuenta y dice cuál está elegida', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarAgendados(tester, tamano: tamanos704['412x915']!);
      await abrirAgendados(tester);

      expect(
        tester.getSemantics(pestanaAgendados),
        isSemantics(label: 'Agendados, 5 visitas', isSelected: true, hasTapAction: true),
      );
      semantica.dispose();
    });

    testWidgets('con los datos todavía cargando, la pestaña dice «Agendados» y no una cuenta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final consulta = ConsultaAgendaFalsa(agendaDelCanvas())..congelada = true;
      await montarAgendados(tester, tamano: tamanos704['412x915']!, consulta: consulta);

      expect(find.bySemanticsLabel('Agendados'), findsOne);
      expect(
        find.descendant(of: pestanaAgendados, matching: find.byType(CircularProgressIndicator)),
        findsOne,
      );
      semantica.dispose();
    });
  });
}
