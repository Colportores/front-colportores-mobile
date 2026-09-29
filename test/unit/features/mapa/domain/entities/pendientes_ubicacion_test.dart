// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:test/test.dart';

void main() {
  group('PendientesUbicacion', () {
    test('dado ningún pendiente, cuando se pregunta, no hay pendientes ni resumen', () {
      expect(PendientesUbicacion.ninguno.hayPendientes, isFalse);
      expect(PendientesUbicacion.ninguno.resumen, isEmpty);
    });

    test(
      'dado uno de cada tipo, cuando arma el resumen, una frase por pendiente y en singular',
      () {
        const p = PendientesUbicacion(visitasPendientes: 1, ventasConSaldo: 1, cobranzasActivas: 1);

        expect(p.hayPendientes, isTrue);
        expect(p.resumen, hasLength(3));
        expect(p.resumen[0], startsWith('Esta ubicación tiene 1 cobranza activa. '));
        expect(p.resumen[1], startsWith('Esta ubicación tiene 1 venta con saldo pendiente. '));
        expect(p.resumen[2], startsWith('Esta ubicación tiene 1 visita pendiente. '));
      },
    );

    test('dado varios de cada tipo, cuando arma el resumen, va en plural', () {
      const p = PendientesUbicacion(visitasPendientes: 3, ventasConSaldo: 2, cobranzasActivas: 2);

      expect(p.resumen[0], contains('2 cobranzas activas'));
      expect(p.resumen[1], contains('2 ventas con saldo pendiente'));
      expect(p.resumen[2], contains('3 visitas pendientes'));
    });

    test('dado solo visitas pendientes, cuando arma el resumen, solo habla de visitas', () {
      const p = PendientesUbicacion(visitasPendientes: 2);

      expect(p.resumen, hasLength(1));
      expect(p.resumen.single, contains('nuevas visitas'));
    });
  });
}
