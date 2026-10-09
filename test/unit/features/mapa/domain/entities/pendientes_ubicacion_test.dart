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
}
