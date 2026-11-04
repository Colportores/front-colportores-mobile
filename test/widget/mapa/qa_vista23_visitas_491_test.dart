// QA de #491 (vista 23, artboard 23B·10 «En el mapa: tocar la casa», HU-VIS-002): la hoja de la casa
// con «VISITAS AGENDADAS», «Registrar visita» y «+ Agendar». Matriz de estados × 360x640 / 412x915 ×
// texto 1,0 / 2,0 dentro del alto real que el mapa le da a la hoja (un tercio el resumen, la mitad
// arriba): sin overflow, textos dentro, todo alcanzable al desplazar, y los casos límite de cada flujo.
// Los hallazgos van con `skip` (`--dart-define=QA_HALLAZGOS=true` los corre).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/visitas_agendadas_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_491_arnes.dart';

Finder get _filas => find.byType(FilaVisitaAgendada);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _agendar => find.byKey(ClavesHojaCasa.agendar);
Finder get _aviso => find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeerAgendas);

/// Trae [f] a la vista de la hoja desplazándola.
Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
}

void main() {
  group('23B·10 · textos literales del canvas y orden', () {
    probar491('el rótulo, las filas, «Registrar visita» y «+ Agendar», en ese orden', (
      tester,
    ) async {
      await montar491(tester, Estado491.canvas, enElMapa: false, tamano: const Size(390, 844));

      expect(find.text('VISITAS AGENDADAS'), findsOneWidget);
      expect(find.text('JUE 08/10 · 14:30'), findsOneWidget);
      expect(find.text('SÁB 10/10 · 12:30'), findsOneWidget);
      expect(find.text('Entrevista'), findsOneWidget);
      expect(find.text('Cobranza'), findsOneWidget);
      expect(find.text('María Fernández'), findsNWidgets(2));
      expect(find.textContaining('Registrar visita'), findsOneWidget);
      expect(find.text('+ Agendar'), findsOneWidget);
      expect(find.text('›'), findsNWidgets(2));
      final ys = [
        tester.getTopLeft(find.text('VISITAS AGENDADAS')).dy,
        tester.getTopLeft(_filas.first).dy,
        tester.getTopLeft(_filas.last).dy,
        tester.getTopLeft(_registrar).dy,
        tester.getTopLeft(_agendar).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    probar491('el rótulo es un encabezado para el lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar491(tester, Estado491.canvas, enElMapa: false, tamano: const Size(390, 844));
      expect(
        tester.getSemantics(find.byKey(ClavesVisitasAgendadas.rotulo)),
        isSemantics(label: 'VISITAS AGENDADAS', isHeader: true),
      );
      semantica.dispose();
    });

    probar491('cada fila es un botón para el lector con cuándo, qué y con quién', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar491(tester, Estado491.vencida, enElMapa: false, tamano: const Size(390, 844));
      final vencida = tester.getSemantics(find.byKey(ClavesVisitasAgendadas.fila('vencida')));
      expect(vencida, isSemantics(isButton: true, hasTapAction: true));
      expect(vencida.label, contains('Pasó la hora'));
      expect(vencida.label, contains('Entrevista'));
      semantica.dispose();
    });
  });

  group('Matriz: 15 estados × 360x640 / 412x915 × 1,0 / 2,0 (en el alto real de la hoja)', () {
    for (final e in Estado491.values) {
      for (final tamano in tamanos) {
        for (final escala in escalas) {
          probar491('${e.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ${escala}x', (
            tester,
          ) async {
            await montar491(tester, e, escala: escala, tamano: tamano);
            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados(tester, tamano);
            await capturar491(tester, '${e.name}_${sufijo491(tamano, escala)}');

            // Todo lo que la hoja ofrece se alcanza desplazando.
            final conLista = !{
              Estado491.sinVisitas,
              Estado491.cargando,
              Estado491.error,
              Estado491.errorArriba,
              Estado491.baja,
            }.contains(e);
            if (e != Estado491.baja) {
              await _traer(tester, _registrar);
              expect(
                estaALaVista(tester, _registrar),
                isTrue,
                reason: '«Registrar visita» no se alcanza al desplazar',
              );
            }
            if (e != Estado491.sinDestinos && e != Estado491.baja) {
              await _traer(tester, _agendar);
              expect(
                estaALaVista(tester, _agendar),
                isTrue,
                reason: '«+ Agendar» no se alcanza al desplazar',
              );
            }
            if (conLista) {
              for (final fila in [_filas.first, _filas.last]) {
                await _traer(tester, fila);
                final r = tester.getRect(fila);
                final v = visibleDeLaHoja(tester);
                // Una fila más alta que lo que se ve (2,0× en un tercio de 640) se lee desplazando:
                // alcanza con que su borde de arriba quede a la vista.
                expect(
                  r.top >= v.top - 0.5 && (r.bottom <= v.bottom + 0.5 || r.height > v.height),
                  isTrue,
                  reason: 'una visita no se alcanza al desplazar',
                );
              }
            }
            await alFinal491(tester);
            await capturar491(tester, '${e.name}_${sufijo491(tamano, escala)}_fin');
            if (e == Estado491.error || e == Estado491.errorArriba) {
              await tester.ensureVisible(_aviso);
              await tester.pump();
              expect(estaALaVista(tester, _aviso), isTrue);
              expect(find.text('Reintentar'), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('Capturas de la hoja entera (sin recorte del mapa), 360 de ancho', () {
    for (final e in Estado491.values) {
      for (final escala in escalas) {
        probar491('${e.rotulo} · entera · ${escala}x', (tester) async {
          await montar491(
            tester,
            e,
            escala: escala,
            tamano: Size(360, escala > 1 ? 2000 : 1100),
            enElMapa: false,
          );
          expect(tester.takeException(), isNull);
          await capturar491(tester, '${e.name}_entera_${escala.toString().replaceAll('.', '')}');
        });
      }
    }
  });

  group('Estados sin visitas', () {
    probar491('sin visitas ni cargando ni baja ocupan lugar: los botones suben', (tester) async {
      for (final e in [Estado491.sinVisitas, Estado491.cargando, Estado491.baja]) {
        await montar491(tester, e, enElMapa: false, tamano: const Size(390, 844));
        expect(find.byKey(ClavesVisitasAgendadas.seccion), findsNothing, reason: e.name);
        expect(find.text('VISITAS AGENDADAS'), findsNothing, reason: e.name);
        expect(_aviso, findsNothing, reason: e.name);
      }
    });

    probar491('la casa de baja no ofrece «Registrar visita» ni «+ Agendar» ni lee la agenda', (
      tester,
    ) async {
      final m = await montar491(tester, Estado491.baja, enElMapa: false);
      expect(_registrar, findsNothing);
      expect(_agendar, findsNothing);
      expect(m.repo.pedidosDeLaCasa, isEmpty, reason: 'no hace falta leer la agenda oculta');
    });
  });

  group('Error de lectura (sin artboard propio): aviso con salida', () {
    probar491('«No pudimos leer tu agenda.» con «Reintentar»; la hoja sigue usable', (
      tester,
    ) async {
      final m = await montar491(tester, Estado491.error, enElMapa: false);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_registrar, findsOneWidget);
      expect(_agendar, findsOneWidget);
      // Reintentar vuelve a leer; mientras sigue fallando, el aviso sigue (no se pierde ni se duplica).
      final antes = m.repo.pedidosDeLaCasa.length;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(m.repo.pedidosDeLaCasa.length, greaterThan(antes));
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      // Ahora anda: la lista aparece y el aviso se va.
      m.repo
        ..error = null
        ..items = [entrevista491('ent', jueves)];
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(_filas, findsOneWidget);
    });

    probar491('«Reintentar» toca al menos 48 dp', (tester) async {
      await montar491(tester, Estado491.error, enElMapa: false);
      final r = tester.getSize(
        find.ancestor(of: find.text('Reintentar'), matching: find.byType(InkWell)).first,
      );
      expect(r.height, greaterThanOrEqualTo(44));
    });

    // QA #491 — con el resumen a un tercio de la pantalla el aviso «No pudimos leer tu agenda.» tiene
    // que verse sin desplazar: va arriba de la persona (decisión del 29/10, P1).
    for (final tamano in tamanos) {
      probar491(
        'el aviso de error de lectura se ve sin desplazar · resumen ${tamano.width.toInt()}x${tamano.height.toInt()}',
        (tester) async {
          await montar491(tester, Estado491.error, tamano: tamano);
          await alPrincipio(tester);
          expect(estaALaVista(tester, _aviso), isTrue);
        },
      );
    }
  });

  group('Doble toque, falla a mitad y acciones superpuestas', () {
    // skip: QA #491 — las filas (`_abriendo`) y los botones de la hoja (`_enCurso`) tienen guardas
    // separadas: con un detalle abriéndose, «+ Agendar» (o «Registrar visita») abre otro destino, y al revés.
    probar491('tocar una fila y «+ Agendar» a la vez abre un solo destino', (tester) async {
      final abierto = Completer<Object?>();
      final m = await montar491(
        tester,
        Estado491.canvas,
        enElMapa: false,
        tamano: const Size(390, 1200),
        detalle: (_) => abierto.future,
      );
      await tester.tap(_filas.first);
      await tester.pump();
      expect(m.detalles, hasLength(1));
      await tester.tap(_agendar);
      await tester.pump();
      expect(
        m.agendar,
        0,
        reason: 'un segundo destino se abrió mientras el primero seguía abierto',
      );
      abierto.complete(null);
      await tester.pump();
    }, skip: !verHallazgos);

    probar491('tocar «+ Agendar» y una fila a la vez abre un solo destino', (tester) async {
      final abierto = Completer<Object?>();
      final m = await montar491(
        tester,
        Estado491.canvas,
        enElMapa: false,
        tamano: const Size(390, 1200),
        agendar: () => abierto.future,
      );
      await tester.tap(_agendar);
      await tester.pump();
      expect(m.agendar, 1);
      await tester.tap(_filas.first);
      await tester.pump();
      expect(m.detalles, isEmpty);
      abierto.complete(null);
      await tester.pump();
      await tester.tap(_filas.first);
      await tester.pump();
      expect(m.detalles, hasLength(1), reason: 'al volver, las filas se pueden tocar otra vez');
    }, skip: !verHallazgos);

    probar491('si «+ Agendar» falla, avisa, el botón se rehabilita y se puede reintentar', (
      tester,
    ) async {
      var intentos = 0;
      final m = await montar491(
        tester,
        Estado491.canvas,
        enElMapa: false,
        tamano: const Size(390, 1200),
        agendar: () async {
          intentos++;
          if (intentos == 1) throw StateError('datos de María en el mensaje');
          return true;
        },
      );
      await tester.tap(_agendar);
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('María en el mensaje'),
        findsNothing,
        reason: 'no filtra el error',
      );
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);
      await tester.tap(_agendar);
      await tester.pump();
      expect(m.agendar, 2);
    });

    probar491('si el detalle falla, avisa y las dos filas siguen tocables', (tester) async {
      var intentos = 0;
      final m = await montar491(
        tester,
        Estado491.canvas,
        enElMapa: false,
        tamano: const Size(390, 1200),
        detalle: (_) async {
          intentos++;
          if (intentos == 1) throw StateError('boom');
          return null;
        },
      );
      await tester.tap(_filas.first);
      await tester.pump();
      await tester.pump();
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);
      await tester.tap(_filas.last);
      await tester.pump();
      expect(m.detalles, hasLength(2));
    });

    probar491('la lista cambia mientras el detalle está abierto: no se pierde nada al volver', (
      tester,
    ) async {
      final abierto = Completer<Object?>();
      final m = await montar491(
        tester,
        Estado491.canvas,
        enElMapa: false,
        tamano: const Size(390, 1200),
        detalle: (_) => abierto.future,
      );
      await tester.tap(_filas.first);
      await tester.pump();
      m.repo.emitir([cobranza491('cob', sabado)]);
      await tester.pump();
      expect(_filas, findsOneWidget);
      abierto.complete(null);
      await tester.pump();
      expect(_filas, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    probar491('el último deja de existir: la sección se va y «Registrar visita» sigue', (
      tester,
    ) async {
      final m = await montar491(tester, Estado491.canvas, enElMapa: false);
      m.repo.emitir([]);
      await tester.pump();
      expect(find.byKey(ClavesVisitasAgendadas.seccion), findsNothing);
      expect(_registrar, findsOneWidget);
      expect(_agendar, findsOneWidget);
    });

    probar491('error después de datos: el aviso reemplaza la lista y al reintentar vuelve', (
      tester,
    ) async {
      final m = await montar491(tester, Estado491.canvas, enElMapa: false);
      expect(_filas, findsNWidgets(2));
      m.repo.emitirError(StateError('se cortó'));
      await tester.pump();
      expect(_aviso, findsOneWidget);
      expect(_filas, findsNothing);
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(_aviso, findsNothing);
      expect(_filas, findsNWidgets(2));
    });
  });

  group('Datos límite', () {
    probar491('una sola visita, dos, doce y cuarenta: sin overflow y en orden', (tester) async {
      for (final n in [1, 2, 12, 40]) {
        final items = [
          for (var i = 0; i < n; i++)
            entrevista491(
              'e${i.toString().padLeft(2, '0')}',
              DateTime(2026, 10, 7, 8).add(Duration(hours: i * 5)),
            ),
        ];
        final m = await montar491(
          tester,
          Estado491.canvas,
          items: items,
          enElMapa: false,
          tamano: const Size(360, 640),
          escala: 2,
        );
        expect(tester.takeException(), isNull, reason: '$n visitas');
        await tester.ensureVisible(_filas.last);
        await tester.pump();
        expect(m.repo.pedidosDeLaCasa, isNotEmpty);
        expect(find.byType(FilaVisitaAgendada, skipOffstage: false), findsNWidgets(n));
      }
    });

    probar491('texto larguísimo y emoji: la fila crece y no se corta (2,0× a 360 dp)', (
      tester,
    ) async {
      await montar491(
        tester,
        Estado491.larga,
        escala: 2,
        tamano: const Size(360, 3000),
        enElMapa: false,
      );
      expect(tester.takeException(), isNull);
      for (final fila in _filas.evaluate()) {
        final r = tester.getRect(find.byElementPredicate((e) => e == fila));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      }
    });

    probar491('visita de otro año: la fecha lleva el año; la del año actual, no', (tester) async {
      await montar491(tester, Estado491.otroAnio, enElMapa: false, tamano: const Size(390, 1200));
      expect(find.text('MAR 05/01/2027 · 09:00'), findsOneWidget);
      expect(find.text('JUE 08/10 · 14:30'), findsOneWidget);
    });

    probar491('dos visitas a la misma hora: las dos aparecen', (tester) async {
      await montar491(
        tester,
        Estado491.canvas,
        enElMapa: false,
        tamano: const Size(390, 1200),
        items: [entrevista491('a', jueves), cobranza491('b', jueves)],
      );
      expect(_filas, findsNWidgets(2));
    });
  });

  group('Volver y reentrar', () {
    probar491('cerrar la hoja y abrirla de nuevo vuelve a leer y a mostrar la lista', (
      tester,
    ) async {
      final m = await montar491(tester, Estado491.canvas, enElMapa: false);
      expect(_filas, findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final repo = m.repo;
      await montar491(tester, Estado491.canvas, enElMapa: false, repo: repo);
      expect(_filas, findsNWidgets(2));
      expect(repo.pedidosDeLaCasa.length, greaterThanOrEqualTo(2));
    });
  });
}
