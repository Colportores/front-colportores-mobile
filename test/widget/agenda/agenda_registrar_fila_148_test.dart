// HU-VIS-002 (vista 23B) + HU-VIS-005 (vista 39): «Registrar» de una fila de la agenda cierra ESA
// agenda. Con dos entrevistas programadas en la misma casa, el flujo real de «Registrar visita»
// (`FlujoRegistrarVisita`) no toma «la más antigua de la casa» (lo que lee `agendaProgramadaDe`):
// toma la de la fila tocada. Los tests de la pestaña con un destino falso no podían verlo.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/campo_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../mapa/hoja_con_quien_arnes.dart';
import '../mapa/personas_arnes.dart' show asentar;
import '../mapa/registrar_visita_arnes.dart';

/// Miércoles 28/10/2026, 10:00 (hora local).
final _ahora = DateTime(2026, 10, 28, 10);

/// Dos entrevistas programadas en la misma casa y el mismo espacio: la de ayer (atrasada) y la de
/// hoy a las 9:00 (vencida).
ItemAgenda _deLaCasa(String id, DateTime cuando, String nombre) =>
    itemAgenda(id, cuando, nombre: nombre, espacioId: 'esp-1', ubicacionId: 'ub-1');

Future<AgendaRepositorioFalso> _montar(WidgetTester tester, List<ItemAgenda> items) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Lo que lee la hoja de la casa es «la programada más antigua»: la de ayer.
  final repo = AgendaRepositorioFalso()..programada = agendaDe('ayer');
  final navegador = GlobalKey<NavigatorState>();
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaFalsa(items)),
        relojAgendaProvider.overrideWithValue(() => _ahora),
        agendaRepositoryProvider.overrideWithValue(repo),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 28, 13)),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaGrecia())),
        saldosDePersonasProvider.overrideWithValue(SaldosFalsos(const {})),
        // El mismo enganche que `main.dart`: el flujo real de «Registrar visita».
        registrarVisitaDesdeLaCasaProvider.overrideWithValue(
          (datos) =>
              FlujoRegistrarVisita.abrir(navegador.currentContext!, datos, colportorId: 'col-1'),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navegador,
        theme: temaClaro(),
        home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return repo;
}

void main() {
  final ayer = _deLaCasa('ayer', DateTime(2026, 10, 27, 9), 'Lidia');
  final hoy = _deLaCasa('hoy', DateTime(2026, 10, 28, 9), 'Mario');

  testWidgets(
    'dado dos programadas en la casa, cuando se toca «Registrar» en la de hoy y «No contestó», '
    'se cierra la de hoy y no la más antigua',
    (tester) async {
      final repo = await _montar(tester, [ayer, hoy]);

      await tester.tap(find.byKey(const Key('agenda_registrar_hoy')));
      await asentar(tester);
      await elegir(tester, OpcionQuePaso.noContesto);

      expect(repo.recibidas, hasLength(1));
      expect(repo.recibidas.single.agendaId, 'hoy');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dado dos programadas en la casa, cuando se toca «Registrar» en la atrasada y «Rechazo», se '
    'cierra la atrasada',
    (tester) async {
      final repo = await _montar(tester, [ayer, hoy]);

      await tester.tap(find.byKey(const Key('agenda_registrar_ayer')));
      await asentar(tester);
      await elegir(tester, OpcionQuePaso.rechazo);

      expect(repo.recibidas.single.agendaId, 'ayer');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dado el registro de la de hoy cancelado en «¿Qué pasó?», cuando se registra la otra, no queda '
    'nada pegado de la anterior',
    (tester) async {
      final repo = await _montar(tester, [ayer, hoy]);

      await tester.tap(find.byKey(const Key('agenda_registrar_hoy')));
      await asentar(tester);
      await tester.tap(find.text('Cancelar'));
      await asentar(tester);
      expect(repo.recibidas, isEmpty);

      await tester.tap(find.byKey(const Key('agenda_registrar_ayer')));
      await asentar(tester);
      await elegir(tester, OpcionQuePaso.noContesto);

      expect(repo.recibidas.single.agendaId, 'ayer');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
