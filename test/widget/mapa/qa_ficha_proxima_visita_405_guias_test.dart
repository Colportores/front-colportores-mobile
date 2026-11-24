// QA de «PRÓXIMA VISITA» en la ficha de la persona (vista 23, 23A·05, y vista 32B, #405, PR #592): las
// guías de accesibilidad de Flutter (tamaño de toque de Android e iOS, etiqueta en lo tocable y
// contraste del texto) en cada estado de la sección, a 360×640 y 412×915, con el texto al 100 % y al
// 200 %. Archivo aparte con la letra de prueba (Ahem): con las fuentes reales el
// `textContrastGuideline` da falsos negativos.
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import 'ficha_persona_arnes.dart';

enum _Estado {
  conVisita('con visita y aviso'),
  vencida('visita que ya pasó de hora'),
  varias('varias visitas'),
  sinVisita('sin visita: «+ Agendar»'),
  errorAlLeer('error al leer la agenda'),
  soloLecturaConVisita('persona de baja con visita'),
  fichaVaciaConVisita('ficha vacía con visita');

  const _Estado(this.rotulo);
  final String rotulo;
}

ItemAgenda _visita(String id, DateTime cuando) => itemAgenda(
  id,
  cuando,
  slotCodigo: 'early_afternoon',
  espacioPersonaId: 'ep-per-1',
  nombre: 'María',
  apellido: 'Pérez',
);

MundoFicha _mundo(_Estado e) {
  final m = MundoFicha(
    persona: e == _Estado.soloLecturaConVisita ? mariaDePrueba(baja: DateTime(2026, 10, 22)) : null,
    historial: e == _Estado.fichaVaciaConVisita ? const [] : historialDelCanvas(),
    notasIniciales: e == _Estado.fichaVaciaConVisita ? const [] : notasDeLaFicha(),
    contexto: e == _Estado.soloLecturaConVisita ? contextoBajaDesde22() : null,
  )..conDetalleDeAgenda = true;
  if (e != _Estado.fichaVaciaConVisita) {
    m.cuentas.cuenta = cuentaConSaldo;
    m.conRegistrarEntrega = true;
  }
  m.personas.sembrar([
    if (e == _Estado.soloLecturaConVisita)
      clienteDeBajaDePersonas('per-1', 'María', apellido: 'Pérez')
    else
      clienteDePersonas('per-1', 'María', apellido: 'Pérez'),
  ]);
  m.consultaAgendas.items = switch (e) {
    _Estado.sinVisita || _Estado.errorAlLeer => const [],
    _Estado.vencida => [_visita('a1', DateTime(2026, 10, 21, 10))],
    _Estado.varias => [
      _visita('a1', DateTime(2026, 10, 30, 11)),
      _visita('a2', DateTime(2026, 10, 21, 10)),
      _visita('a3', DateTime(2026, 10, 24, 14, 30)),
    ],
    _ => [_visita('a1', DateTime(2026, 10, 24, 14, 30))],
  };
  if (e == _Estado.errorAlLeer) m.consultaAgendas.error = StateError('sin base');
  return m;
}

void main() {
  for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in _Estado.values) {
        final donde =
            '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} al '
            '${(escala * 100).toInt()} %';

        testWidgets('guías de toque, nombre y contraste con la sección a la vista: $donde', (
          tester,
        ) async {
          final h = tester.ensureSemantics();
          await montarFicha(tester, _mundo(estado), tamano: tamano, escala: escala);
          // La sección entra en pantalla (en 360×640 al 200 % queda más abajo).
          await tester.scrollUntilVisible(
            find.byKey(ClavesFicha.proximaVisita),
            80,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: 'sin overflow');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      }
    }
  }
}
