// QA de la pestaña «Agenda» con un estado cerrado o «Todas» (vista 23B, HU-VIS-002, #508): la HU en
// sus palabras, «Ver más» (semántica, páginas, reinicio al cambiar de filtro, estado vivo), los casos
// límite que los tests del PR no miran (error tras datos, medianoche, vencida dentro de «Todas»,
// volumen, reentrada) y la matriz de estados × teléfonos × escala de texto con las fuentes reales.
//
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, nunca al repo).
// Los hallazgos con `skip` se ven fallar con `--dart-define=QA_HALLAZGOS=true`.
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/qa_agenda_campania_508_arnes.dart';

Finder get _verMas => find.byKey(const Key('agenda_ver_mas'));

void main() {
  group('HU-VIS-002 · «Estado cerrado o Todas», en sus palabras', () {
    probar('Dado «Cumplida» Cuando se carga la lista Entonces: campaña, más nueva a más vieja, '
        '«En esta campaña» y «Ver más»', (tester) async {
      await llegarA508(tester, Estado508.cumplidasConVerMas, tamano: telefonoGrande);

      expect(find.text('En esta campaña'), findsOneWidget);
      expect(find.text('Hoy y los próximos 7 días'), findsNothing);
      // La más nueva arriba (P000 es la de ayer a las 15:00) y la 51.ª no está todavía.
      expect(find.text('P000 Martínez'), findsOneWidget);
      expect(find.text('P049 Martínez'), findsNothing);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('P000 Martínez'), lessThan(y('P001 Martínez')));
      await irAlFinal(tester);
      expect(find.text('Ver más'), findsOneWidget);
    });

    probar('Dado «Todas» Entonces el subtítulo es «En esta campaña»; «Pendientes» lo devuelve', (
      tester,
    ) async {
      await llegarA508(tester, Estado508.todasMezcla, tamano: telefonoGrande);
      expect(find.text('En esta campaña'), findsOneWidget);

      await aplicar508(tester, 'Pendientes');
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      expect(find.text('En esta campaña'), findsNothing);
    });

    probar('Ninguna agenda cerrada: «Ninguna agenda con estos filtros» y «Limpiar filtros»', (
      tester,
    ) async {
      await llegarA508(tester, Estado508.sinResultados, tamano: telefonoGrande);
      expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('En esta campaña'), findsOneWidget);
    });
  });

  group('«Ver más»', () {
    probar('es un botón con nombre y acción para el lector, y a 48 dp', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA508(tester, Estado508.cumplidasConVerMas, tamano: telefonoChico, escala: 2);
      await irAlFinal(tester);

      expect(
        tester.getSemantics(_verMas),
        isSemantics(label: 'Ver más', isButton: true, isEnabled: true, hasTapAction: true),
      );
      final tam = tester.getSize(_verMas);
      expect(tam.height, greaterThanOrEqualTo(48));
      expect(tam.width, greaterThanOrEqualTo(48));
      semantica.dispose();
    });

    probar('suma 10 filas más (60 → todas), la anterior sigue y el botón desaparece', (
      tester,
    ) async {
      await llegarA508(tester, Estado508.cumplidasConVerMas, tamano: telefonoGrande);
      await irAlFinal(tester);
      expect(find.text('P049 Martínez'), findsOneWidget);

      await tester.tap(_verMas);
      await asentar(tester);
      await tester.scrollUntilVisible(
        find.text('P059 Martínez'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('P059 Martínez'), findsOneWidget);
      expect(_verMas, findsNothing);
      expect(find.text('Ver más'), findsNothing);
    });

    probar('cambiar el tipo (chip) vuelve a la primera página', (tester) async {
      final repo = ConsultaAgendaFalsa([
        for (var i = 0; i < 120; i++)
          cerrada(i, tipo: i.isEven ? TipoAgenda.entrevista : TipoAgenda.cobranza),
      ]);
      await montar(tester, repo, tamano: telefonoGrande);
      await aplicar508(tester, 'Todas');
      await irAlFinal(tester);
      await tester.tap(_verMas);
      await asentar(tester);
      await irAlFinal(tester);
      // Dos páginas (100 de 120): sigue habiendo «Ver más».
      expect(_verMas, findsOneWidget);

      await tester.drag(find.byKey(const Key('agenda_filas')), const Offset(0, 20000));
      await tester.pump();
      await tester.tap(find.text('Entrevistas'));
      await asentar(tester);
      await irAlFinal(tester);
      // 60 entrevistas: una página de 50 y «Ver más» (no las 60 de golpe).
      expect(_verMas, findsOneWidget);
      expect(find.text('P118 Martínez'), findsNothing);
    });

    probar('una agenda nueva mientras se miran dos páginas no reinicia la lista', (tester) async {
      final repo = ConsultaAgendaFalsa([for (var i = 0; i < 120; i++) cerrada(i)]);
      await montar(tester, repo, tamano: telefonoGrande);
      await aplicar508(tester, 'Cumplidas');
      await irAlFinal(tester);
      await tester.tap(_verMas);
      await asentar(tester);
      await irAlFinal(tester);
      expect(find.text('P099 Martínez'), findsOneWidget);

      repo.emitir([
        itemAgenda(
          'nueva',
          DateTime(2026, 10, 28, 9),
          estado: EstadoAgenda.cumplida,
          nombre: 'Nueva',
        ),
        ...repo.items,
      ]);
      await asentar(tester);
      await irAlFinal(tester);

      // Sigue en 100 filas: entró la nueva arriba y la última (P099) salió a la página siguiente.
      expect(find.text('P098 Martínez'), findsOneWidget);
      expect(find.text('P099 Martínez'), findsNothing);
      expect(_verMas, findsOneWidget);
    });

    probar('600 agendas: doce toques llegan a la más vieja y «Ver más» se va', (tester) async {
      final repo = ConsultaAgendaFalsa([for (var i = 0; i < 600; i++) cerrada(i)]);
      await montar(tester, repo, tamano: telefonoGrande);
      await aplicar508(tester, 'Cumplidas');
      var toques = 0;
      for (var vuelta = 0; vuelta < 20; vuelta++) {
        await irAlFinal(tester);
        if (_verMas.evaluate().isEmpty) break;
        await tester.tap(_verMas);
        toques++;
        await asentar(tester);
      }
      expect(toques, 11);
      expect(_verMas, findsNothing);
      expect(find.text('P599 Martínez'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Casos límite', () {
    probar('un error después de datos dice qué pasó, y «Reintentar» devuelve la lista', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final repo = await llegarA508(tester, Estado508.todasMezcla, tamano: telefonoGrande);
      repo.emitirError(StateError('se cayó'));
      await asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Futura Martínez'), findsNothing);
      // Se anuncia (región viva), con la acción a mano.
      expect(
        tester.getSemantics(find.text('No pudimos leer tu agenda.')),
        isSemantics(isLiveRegion: true),
      );
      repo.error = null;
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(find.text('Futura Martínez'), findsOneWidget);
      // El filtro elegido se conserva.
      expect(find.text('Todas ▾'), findsOneWidget);
      expect(find.text('En esta campaña'), findsOneWidget);
      semantica.dispose();
    });

    probar('Reintentar que falla otra vez deja el aviso con su botón (no se traba)', (
      tester,
    ) async {
      final repo = await llegarA508(tester, Estado508.error, tamano: telefonoGrande);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
      }
      repo.error = null;
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);
    });

    probar('pasa la medianoche con «Cumplidas»: relee con el día nuevo y no pierde filas', (
      tester,
    ) async {
      final reloj = Reloj(DateTime(2026, 10, 28, 23, 58));
      final repo = ConsultaAgendaFalsa([for (var i = 0; i < 6; i++) cerrada(i)]);
      await montar(tester, repo, reloj: reloj, tamano: telefonoGrande);
      await aplicar508(tester, 'Cumplidas');
      expect(repo.pedidosCampania.last.hoy, DateTime(2026, 10, 28));

      reloj.ahora = DateTime(2026, 10, 29, 0, 1);
      await tester.pump(const Duration(minutes: 2));
      await asentar(tester);

      expect(repo.pedidosCampania.last.hoy, DateTime(2026, 10, 29));
      expect(find.text('P000 Martínez'), findsOneWidget);
      expect(find.text('En esta campaña'), findsOneWidget);
    });

    probar('una vencida dentro de «Todas» sigue pidiendo «Registrar» y lo registra una vez', (
      tester,
    ) async {
      final destinos = Destinos();
      await llegarA508(tester, Estado508.todasMezcla, tamano: telefonoGrande, destinos: destinos);

      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await asentar(tester);
      expect(destinos.registrar, hasLength(1));
    });

    probar('salir de la pestaña y volver conserva el filtro y la lista', (tester) async {
      final repo = ConsultaAgendaFalsa([for (var i = 0; i < 60; i++) cerrada(i)]);
      final visible = await montar(tester, repo, tamano: telefonoGrande);
      await aplicar508(tester, 'Cumplidas');

      visible.value = false;
      await asentar(tester);
      visible.value = true;
      await asentar(tester);

      expect(find.text('En esta campaña'), findsOneWidget);
      expect(find.text('Cumplidas ▾'), findsOneWidget);
      expect(find.text('P000 Martínez'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    probar(
      'lo cargado en la campaña no se pisa con la ventana: Pendientes ↔ Cumplidas ida y vuelta',
      (tester) async {
        final repo = ConsultaAgendaFalsa([
          entrevista('hoy', DateTime(2026, 10, 28, 17), nombre: 'Hoy'),
          cerrada(0),
        ]);
        await montar(tester, repo, tamano: telefonoGrande);
        for (var i = 0; i < 4; i++) {
          await aplicar508(tester, 'Cumplidas');
          expect(find.text('P000 Martínez'), findsOneWidget);
          expect(find.text('Hoy Martínez'), findsNothing);
          await aplicar508(tester, 'Pendientes');
          expect(find.text('Hoy Martínez'), findsOneWidget);
          expect(find.text('P000 Martínez'), findsNothing);
        }
      },
    );
  });

  group('Hallazgos corregidos', () {
    // QA #508 — «+ Agendar» no queda junto al rótulo de un día pasado de «Cumplidas»/«Canceladas»
    // (el canvas 23B·05 no lo dibuja con un estado cerrado; decisión del 29/10, P1).
    probar('«+ Agendar» no se ofrece al lado del rótulo de un día pasado de una lista cerrada', (
      tester,
    ) async {
      await llegarA508(tester, Estado508.canceladas, tamano: telefonoGrande);
      expect(find.text('+ Agendar'), findsNothing);
    });
  });

  group(
    'Matriz: estados × 360x640 / 412x915 × 1,0 / 2,0 (sin overflow, textos dentro, captura)',
    () {
      for (final e in Estado508.values) {
        for (final tamano in tamanos) {
          for (final escala in escalas) {
            probar('${e.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ${escala}x', (
              tester,
            ) async {
              await llegarA508(tester, e, escala: escala, tamano: tamano);
              expect(tester.takeException(), isNull);
              expectSinTextoFueraDeLosCostados(tester, tamano);
              await capturar508(
                tester,
                '${e.name}_${tamano.width.toInt()}_${escala.toString().replaceAll('.', '')}',
              );
              if (e.conVerMas) {
                await irAlFinal(tester);
                expect(_verMas, findsOneWidget);
                expect(tester.takeException(), isNull);
                await capturar508(
                  tester,
                  '${e.name}_fin_${tamano.width.toInt()}_${escala.toString().replaceAll('.', '')}',
                );
              }
            });
          }
        }
      }
    },
  );
}
