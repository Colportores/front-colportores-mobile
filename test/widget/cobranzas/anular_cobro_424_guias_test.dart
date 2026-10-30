// Guías de accesibilidad de Flutter sobre cada estado de «Detalle del cobro» y «Anular cobro» (vista 30 B,
// #424), en 360x640 y 412x915, con texto 1,0 y 2,0. Con las cajas de Ahem la guía de contraste lee el
// color de verdad.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/anular_cobro_arnes.dart';

enum _Estado {
  detalle('30B-01 detalle'),
  motivo('30B-02 motivo'),
  otro('30B-03 otro'),
  confirmar('30B-04 confirmar'),
  anulado('30B-05 anulado'),
  fueraDePlazo('30B-06 fuera de plazo'),
  ticketValidado('30B-07 ticket validado'),
  error('30B-08 error');

  const _Estado(this.rotulo);
  final String rotulo;
}

Future<void> _llegarA(WidgetTester tester, _Estado estado, Size tamano, double escala) async {
  final fueraDePlazo = estado == _Estado.fueraDePlazo;
  final repo = AnulacionesEnMemoria(
    cobros: [
      detalleDeEjemplo(
        medio: estado == _Estado.ticketValidado ? MedioCobranza.tarjeta : MedioCobranza.efectivo,
      ),
    ],
  );
  if (estado == _Estado.error) repo.fallas.add(const FailureCobroNoAnulado());
  await montarDetalleDelCobro(
    tester,
    repo: repo,
    ahora: fueraDePlazo ? DateTime.utc(2026, 10, 27) : null,
    ticketValidado: estado == _Estado.ticketValidado,
    escala: escala,
    tamano: tamano,
  );
  switch (estado) {
    case _Estado.detalle || _Estado.fueraDePlazo || _Estado.ticketValidado:
      break;
    case _Estado.motivo:
      await irAAnular(tester);
    case _Estado.otro:
      await irAAnular(
        tester,
        m: MotivoDeAnulacion.otro,
        texto: 'El cliente pagó con transferencia',
      );
    case _Estado.confirmar:
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
    case _Estado.anulado:
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
    case _Estado.error:
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
  }
  await asentarAgendar(tester, 3);
}

void main() {
  for (final tamano in const [Size(360, 640), Size(412, 915)]) {
    for (final escala in const [1.0, 2.0]) {
      for (final estado in _Estado.values) {
        group('${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · $escala', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            await _llegarA(tester, estado, tamano, escala);
            await expectLater(tester, meetsGuideline(guia));
            expect(tester.takeException(), isNull);
            h.dispose();
          }

          testWidgets(
            'tamaño de toque Android (48 dp)',
            (t) => verificar(t, androidTapTargetGuideline),
          );
          testWidgets('tamaño de toque iOS (44 pt)', (t) => verificar(t, iOSTapTargetGuideline));
          testWidgets(
            'todo lo tocable tiene nombre',
            (t) => verificar(t, labeledTapTargetGuideline),
          );
          testWidgets('contraste del texto', (t) => verificar(t, textContrastGuideline));
        });
      }
    }
  }
}
