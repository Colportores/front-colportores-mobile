// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:test/test.dart';

void main() {
  group('PendientesUbicacion', () {
    test('dado ningún pendiente, cuando se pregunta, no hay bloqueo, ni pendientes ni resumen', () {
      expect(PendientesUbicacion.ninguno.bloqueo, isNull);
      expect(PendientesUbicacion.ninguno.hayPendientes, isFalse);
      expect(PendientesUbicacion.ninguno.resumen, isEmpty);
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

    test('dado solo una visita de otro, el bloqueo dice visitas y no ventas', () {
      const p = PendientesUbicacion(tieneVisitasDeOtros: true);

      expect(p.bloqueo, const BloqueoPorVentasOVisitasAjenas(ventas: false, visitasDeOtros: true));
    });

    test(
      'dado ventas y visitas de otro en un edificio, el bloqueo lleva las dos cosas y el tipo',
      () {
        const p = PendientesUbicacion(
          tipo: TipoUbicacion.edificio,
          tieneVentas: true,
          tieneVisitasDeOtros: true,
        );

        expect(
          p.bloqueo,
          const BloqueoPorVentasOVisitasAjenas(
            ventas: true,
            visitasDeOtros: true,
            tipo: TipoUbicacion.edificio,
          ),
        );
      },
    );

    test('dado una visita de otro colportor, cuando se pregunta el bloqueo, es el de ventas o '
        'visitas de otro', () {
      const p = PendientesUbicacion(tieneVisitasDeOtros: true);

      expect(p.bloqueo, isA<BloqueoPorVentasOVisitasAjenas>());
    });

    test('dado una cobranza pendiente y una visita de otro, cuando se pregunta el bloqueo, gana la '
        'cobranza (tiene su salida «Ir a la cobranza»)', () {
      const cobranza = CobranzaPendiente(montoCentavos: 50000, numeroCuota: 1);
      const p = PendientesUbicacion(cobranzaPendiente: cobranza, tieneVisitasDeOtros: true);

      expect(p.bloqueo, isA<BloqueoPorCobranza>());
    });

    test('dado entrevistas agendadas y un bloqueo, cuando se pregunta, ambos conviven (el '
        'caso de uso decide el orden)', () {
      const p = PendientesUbicacion(entrevistasAgendadas: ['ag-1'], tieneVentas: true);

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

    test('dado un edificio, el sujeto es «Este edificio» (decisión del 04/11, P2)', () {
      const uno = PendientesUbicacion(tipo: TipoUbicacion.edificio, entrevistasAgendadas: ['a']);
      const dos = PendientesUbicacion(
        tipo: TipoUbicacion.edificio,
        entrevistasAgendadas: ['a', 'b'],
      );

      expect(uno.resumen, [
        'Este edificio tiene 1 entrevista agendada. Si la das de baja, se cancela.',
      ]);
      expect(dos.resumen, [
        'Este edificio tiene 2 entrevistas agendadas. Si la das de baja, se cancelan.',
      ]);
    });

    test('dado un negocio, el sujeto es «Este negocio» (decisión del 04/11, P2)', () {
      const uno = PendientesUbicacion(tipo: TipoUbicacion.negocio, entrevistasAgendadas: ['a']);
      const dos = PendientesUbicacion(
        tipo: TipoUbicacion.negocio,
        entrevistasAgendadas: ['a', 'b'],
      );

      expect(uno.resumen, [
        'Este negocio tiene 1 entrevista agendada. Si la das de baja, se cancela.',
      ]);
      expect(dos.resumen, [
        'Este negocio tiene 2 entrevistas agendadas. Si la das de baja, se cancelan.',
      ]);
    });

    test('dado la misma lista en otro tipo, no son iguales', () {
      expect(
        const PendientesUbicacion(entrevistasAgendadas: ['ag-1']),
        isNot(
          const PendientesUbicacion(tipo: TipoUbicacion.negocio, entrevistasAgendadas: ['ag-1']),
        ),
      );
    });

    test('dado entrevistas distintas, no son iguales', () {
      expect(
        const PendientesUbicacion(entrevistasAgendadas: ['ag-1']),
        isNot(const PendientesUbicacion(entrevistasAgendadas: ['ag-2'])),
      );
    });
  });

  group('CobranzaPendiente: cuántas', () {
    test('dado una sola venta con saldo, la cantidad es 1', () {
      expect(const CobranzaPendiente(montoCentavos: 100).cantidad, 1);
    });

    test('dado otra cantidad, no son iguales', () {
      expect(
        const CobranzaPendiente(montoCentavos: 100, cantidad: 2),
        isNot(const CobranzaPendiente(montoCentavos: 100)),
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
