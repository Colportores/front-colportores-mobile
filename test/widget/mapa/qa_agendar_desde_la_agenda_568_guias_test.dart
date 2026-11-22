// QA de #568, matriz de estados × 360×640 / 412×915 × texto 1,0 / 2,0 con las guías de accesibilidad
// (tamaño de toque Android e iOS, nombre en todo lo tocable) y sin desbordes. El contraste va en
// `qa_agendar_desde_la_agenda_568_contraste_test.dart` (con la letra de prueba: con la real da falsos
// negativos). Con `--dart-define=QA_CAPTURAS=true` deja una captura por celda en
// `.dart_tool/qa_capturas/`.
import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/elegir_casa_para_agendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_agendar_desde_la_agenda_568_arnes.dart';

enum Estado568 {
  agendaVacia('23B·07 pestaña vacía con «+ Agendar»'),
  agendaConVisitas('23B·01 «+ Agendar» junto al día'),
  selector('elegir la casa (vista 05 en selección)'),
  selectorSinUbicaciones('elegir la casa sin ubicaciones'),
  avisoEdificio('elegir la casa: aviso del edificio'),
  avisoSinLugar('elegir la casa: aviso de casa sin lugar'),
  conQuien('¿Con quién? con varias personas'),
  formulario('23A·01 Agendar visita con la casa elegida'),
  exito('23A·05 de vuelta en la Agenda con el aviso de éxito');

  const Estado568(this.rotulo);
  final String rotulo;
}

/// Toca una fila de la lista del selector (perezosa: a 2× la de abajo todavía no se construyó).
Future<void> _tocarFila(WidgetTester tester, String direccion) async {
  await tester.scrollUntilVisible(
    find.text(direccion),
    80,
    scrollable: find
        .descendant(of: find.byKey(const Key('lista_filas')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.tap(find.text(direccion), warnIfMissed: false);
  await asentarAgendar(tester);
}

Future<void> llegarA(WidgetTester tester, Estado568 estado, Size tam, double escala) async {
  final filas = switch (estado) {
    Estado568.selectorSinUbicaciones => <UbicacionConResumen>[],
    Estado568.avisoEdificio || Estado568.avisoSinLugar => [
      filaLista('u-1', calle: 'Mataojo', numero: '2044'),
      filaLista('u-3', tipo: TipoUbicacion.edificio, calle: 'Av. Italia', numero: '1240'),
      filaLista('u-5', calle: 'Bulevar', numero: '9'),
    ],
    _ => null,
  };
  await montar568(
    tester,
    tamano: tam,
    escala: escala,
    filas: filas,
    items: estado == Estado568.agendaConVisitas
        ? [itemAgenda('a-1', DateTime(2026, 10, 23, 16, 0), ubicacionId: 'u-1')]
        : const [],
    personas: estado == Estado568.conQuien
        ? [mariaFernandez, clienteDePersonas('p2', 'Pedro', apellido: 'Gómez')]
        : null,
  );
  if (estado == Estado568.agendaVacia || estado == Estado568.agendaConVisitas) return;
  final agendar = find.text('+ Agendar').first;
  await tester.ensureVisible(agendar);
  await tester.pump();
  await tester.tap(agendar);
  await asentarAgendar(tester);
  switch (estado) {
    case Estado568.selector || Estado568.selectorSinUbicaciones:
      return;
    case Estado568.avisoEdificio:
      await _tocarFila(tester, 'Av. Italia 1240');
    case Estado568.avisoSinLugar:
      await _tocarFila(tester, 'Bulevar 9');
    case Estado568.conQuien:
      await _tocarFila(tester, 'Mataojo 2044');
    case Estado568.formulario || Estado568.exito:
      await _tocarFila(tester, 'Mataojo 2044');
      if (estado == Estado568.exito) {
        final guardar = find.byKey(ClavesAgendarVisita.botonAgendar);
        await tester.ensureVisible(guardar);
        await tester.tap(guardar);
        await asentarAgendar(tester);
      }
    case Estado568.agendaVacia || Estado568.agendaConVisitas:
      break;
  }
}

void main() {
  for (final estado in Estado568.values) {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        final celda = '${estado.rotulo} · ${tam.width.toInt()}×${tam.height.toInt()} · ×$escala';
        testWidgets('$celda: sin desborde y con las guías de toque y de nombre', (tester) async {
          await llegarA(tester, estado, tam, escala);

          expect(tester.takeException(), isNull, reason: 'desborde u otra excepción');
          if (estado == Estado568.selector) {
            expect(find.byKey(ClavesElegirCasaParaAgendar.pantalla), findsOneWidget);
          }
          if (estado == Estado568.formulario) {
            expect(find.byType(AgendarVisitaPage), findsOneWidget);
          }
          await capturar568(
            tester,
            '${estado.name}_${tam.width.toInt()}_${escala.toString().replaceAll('.', '_')}',
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          expectSinTextoFueraDeLosCostados(tester, tam);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
