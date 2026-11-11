// QA de #679, «Mostrar bajas» (32D·04) y «Reactivar» (32D·05): guías de accesibilidad con las bajas
// a la vista, en la hoja de la casa y en la ficha del depto, a 360×640 y 412×915. Sin fuentes reales
// (con letra real `textContrastGuideline` da falsos negativos).
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/bajas_de_personas.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart';
import 'hoja_con_quien_arnes.dart' show SaldosFalsos;
import 'hoja_espacios_arnes.dart';

final _mostrar = find.byKey(ClavesBajasDePersonas.mostrar);
final _reactivarMaria = find.byKey(ClavesBajasDePersonas.reactivar('p2'));

List<PersonaDelEspacio> _filas() => [
  clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
  clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
];

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final tamano in [t360x640, t412x915]) {
    group('guías a ${tamano.width.toInt()}×${tamano.height.toInt()}', () {
      testWidgets('hoja de la casa con «Mostrar bajas» apagado y prendido', (tester) async {
        final handle = tester.ensureSemantics();
        final m = Montaje445();
        m.repo.sembrar(_filas());
        await montarHoja445(
          tester,
          montaje: m,
          tamano: tamano,
          otros: [
            saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
          ],
        );
        await asentar445(tester);
        await tester.ensureVisible(_mostrar);
        await tester.pump();
        await _guias(tester);

        await tester.tap(_mostrar);
        await asentar445(tester);
        await tester.ensureVisible(_reactivarMaria);
        await tester.pump();
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('ficha del depto con las bajas a la vista', (tester) async {
        final handle = tester.ensureSemantics();
        await montarHoja(
          tester,
          espacios: [espacioDe('esp-1', '101', piso: '1')],
          tamano: tamano,
          extras: [
            personaRepositoryProvider.overrideWithValue(
              PersonaRepositorioFalso()..sembrar(_filas()),
            ),
            relojPersonaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 25, 9, 30)),
            saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
          ],
        );
        await abrirFichaDepto(tester, 'esp-1');
        await tester.ensureVisible(_mostrar);
        await tester.tap(_mostrar);
        await asentarHoja(tester);
        await tester.ensureVisible(_reactivarMaria);
        await tester.pump();

        await _guias(tester);
        handle.dispose();
      });
    });
  }
}
