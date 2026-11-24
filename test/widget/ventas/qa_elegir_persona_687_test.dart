// QA de «¿A quién le vendés?» (#546, PR #687): la caja de búsqueda con lo que una persona puede pegar
// o escribir (solo espacios, emoji, caracteres especiales, un texto larguísimo): no se rompe, no se
// pierde la lista y siempre hay una salida a mano («Borrar búsqueda»).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/elegir_persona_para_vender_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_elegir_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/personas_para_vender_falsos.dart';
import '../../helpers/qa_vista27_entrega_435_arnes.dart' show capturar435, cargarFuentes408;
import '../../helpers/venta_ui_falsos.dart';

Future<void> _montar(WidgetTester tester, {double escala = 1}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final entorno = EntornoDeVenta();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...entorno.overrides,
        lectorDePersonasParaVenderProvider.overrideWithValue(
          LectorDePersonasParaVenderFalso([
            personaParaVender('1', nombre: 'Ana', apellido: 'Zapata'),
            personaParaVender('2', nombre: 'Beatriz', apellido: 'Álvarez'),
          ]),
        ),
        agendaRepositoryProvider.overrideWithValue(AgendaRepositorioQueAgenda()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const ElegirPersonaParaVenderPage(colportorId: 'col-1'),
      ),
    ),
  );
  await asentar(tester);
}

void main() {
  testWidgets(
    'sin resultados a 360×640 con letra al 200 %: «Borrar búsqueda» del cuerpo está a la vista o a un '
    'scroll',
    (tester) async {
      await cargarFuentes408(tester);
      await _montar(tester, escala: 2);
      await tester.enterText(find.byKey(const Key('personas_busqueda')), 'zzzz');
      await asentar(tester);
      await capturar435(tester, '687_sinResultados_360_2x');

      final boton = find.text(TextosElegirPersona.borrarBusqueda);
      expect(boton, findsOneWidget);
      var abajo = tester.getRect(boton).bottom;
      if (abajo > 640) {
        await tester.drag(find.text(TextosElegirPersona.sinResultados), const Offset(0, -600));
        await asentar(tester);
        abajo = tester.getRect(boton).bottom;
      }
      expect(
        abajo,
        lessThanOrEqualTo(640),
        reason: 'el botón del aviso quedó fuera de la pantalla',
      );
    },
  );

  group('búsqueda de «¿A quién le vendés?»', () {
    final entradas = <String, String>{
      'solo espacios': '     ',
      'emoji': '😀🙏🏽',
      'caracteres especiales': '%_\'"; DROP TABLE personas;--',
      'texto pegado de 5000 letras': 'ñ' * 5000,
    };
    for (final MapEntry(key: nombre, value: texto) in entradas.entries) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets('$nombre · ${escala}x: no se rompe y se puede volver a la lista', (
          tester,
        ) async {
          await _montar(tester, escala: escala);
          await tester.enterText(find.byKey(const Key('personas_busqueda')), texto);
          await asentar(tester);

          expect(tester.takeException(), isNull);
          final sinResultados = find.text(TextosElegirPersona.sinResultados);
          if (texto.trim().isNotEmpty) {
            expect(sinResultados, findsOneWidget);
            // La salida es «Borrar búsqueda» (cuerpo) o la ✕ de la caja, que siempre está a mano.
            await tester.tap(find.byTooltip(TextosElegirPersona.borrarBusqueda));
            await asentar(tester);
          }
          expect(find.text(TextosElegirPersona.sinResultados), findsNothing);
        });
      }
    }
  });
}
