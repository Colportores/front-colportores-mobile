// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:test/test.dart';

void main() {
  group('PendientesUbicacion', () {
    test('dado ningún pendiente, cuando se pregunta, no hay bloqueo, ni pendientes ni resumen', () {
      expect(PendientesUbicacion.ninguno.bloqueo, isNull);
      expect(PendientesUbicacion.ninguno.hayPendientes, isFalse);
      expect(PendientesUbicacion.ninguno.resumen, isEmpty);
    });

    test('dado una visita pendiente propia, cuando arma el resumen, va en singular y es el literal '
        'de la HU', () {
      const p = PendientesUbicacion(visitasPropiasPendientes: 1);

      expect(p.hayPendientes, isTrue);
      expect(p.bloqueo, isNull);
      expect(p.resumen, [
        'Esta ubicación tiene 1 visita pendiente. Si la das de baja, no podrás registrar nuevas '
            'visitas, pero el historial se conserva.',
      ]);
    });

    test('dado varias visitas pendientes propias, cuando arma el resumen, va en plural', () {
      const p = PendientesUbicacion(visitasPropiasPendientes: 2);

      expect(p.resumen, hasLength(1));
      expect(
        p.resumen.single,
        'Esta ubicación tiene 2 visitas pendientes. Si la das de baja, no podrás registrar nuevas '
        'visitas, pero el historial se conserva.',
      );
    });

    test('dado una cobranza pendiente, cuando se pregunta el bloqueo, es el de la cobranza con su '
        'monto y su cuota', () {
      const cobranza = CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2);
      const p = PendientesUbicacion(cobranzaPendiente: cobranza, tieneVentas: true);

      expect(p.bloqueo, const BloqueoPorCobranza(cobranza));
    });

    test(
      'dado cualquier venta, cuando se pregunta el bloqueo, es el de ventas o visitas de otro',
      () {
        const p = PendientesUbicacion(tieneVentas: true);

        expect(p.bloqueo, const BloqueoPorVentasOVisitasAjenas());
      },
    );

    test('dado una visita de otro colportor, cuando se pregunta el bloqueo, es el de ventas o '
        'visitas de otro', () {
      const p = PendientesUbicacion(tieneVisitasDeOtros: true);

      expect(p.bloqueo, const BloqueoPorVentasOVisitasAjenas());
    });

    test('dado una cobranza pendiente y una visita de otro, cuando se pregunta el bloqueo, gana la '
        'cobranza (tiene su salida «Ir a la cobranza»)', () {
      const cobranza = CobranzaPendiente(montoCentavos: 50000, numeroCuota: 1);
      const p = PendientesUbicacion(cobranzaPendiente: cobranza, tieneVisitasDeOtros: true);

      expect(p.bloqueo, isA<BloqueoPorCobranza>());
    });

    test('dado visitas propias pendientes y un bloqueo, cuando se pregunta, ambos conviven (el '
        'caso de uso decide el orden)', () {
      const p = PendientesUbicacion(visitasPropiasPendientes: 1, tieneVentas: true);

      expect(p.hayPendientes, isTrue);
      expect(p.bloqueo, isNotNull);
    });
  });

  group('PendientesUbicacion: entrevistas agendadas (Cristian, 21/10)', () {
    test('dado una entrevista agendada, cuando se pregunta, hay que confirmar pero no bloquea', () {
      const p = PendientesUbicacion(entrevistasAgendadas: ['ag-1']);

      expect(p.hayPendientes, isTrue);
      expect(p.bloqueo, isNull);
      expect(p.resumen, ['Esta casa tiene 1 entrevista agendada. Si la das de baja, se cancela.']);
    });

    test('dado varias, el aviso va en plural', () {
      const p = PendientesUbicacion(entrevistasAgendadas: ['ag-1', 'ag-2', 'ag-3']);

      expect(p.resumen, [
        'Esta casa tiene 3 entrevistas agendadas. Si la das de baja, se cancelan.',
      ]);
    });

    test('dado entrevistas y visitas pendientes, el resumen lleva las dos frases', () {
      const p = PendientesUbicacion(entrevistasAgendadas: ['ag-1'], visitasPropiasPendientes: 2);

      expect(p.resumen, hasLength(2));
      expect(p.resumen.first, startsWith('Esta casa tiene 1 entrevista agendada.'));
      expect(p.resumen.last, startsWith('Esta ubicación tiene 2 visitas pendientes.'));
    });

    test('dado entrevistas distintas, no son iguales', () {
      expect(
        const PendientesUbicacion(entrevistasAgendadas: ['ag-1']),
        isNot(const PendientesUbicacion(entrevistasAgendadas: ['ag-2'])),
      );
    });
  });

  group('CobranzaPendiente: destino', () {
    test('dado la venta y la casa, cuando se pregunta, tiene destino', () {
      const c = CobranzaPendiente(montoCentavos: 100, ventaId: 'v-1', espacioId: 'esp-1');

      expect(c.tieneDestino, isTrue);
    });

    test('dado que falta la venta o la casa, no tiene destino', () {
      expect(const CobranzaPendiente(montoCentavos: 100).tieneDestino, isFalse);
      expect(const CobranzaPendiente(montoCentavos: 100, ventaId: 'v-1').tieneDestino, isFalse);
      expect(const CobranzaPendiente(montoCentavos: 100, espacioId: 'e').tieneDestino, isFalse);
    });
  });
}
