import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_baja.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatoBaja.monto', () {
    test('dado pesos justos, entonces lleva punto de miles y sin decimales', () {
      expect(FormatoBaja.monto(0), r'$U 0');
      expect(FormatoBaja.monto(9900), r'$U 99');
      expect(FormatoBaja.monto(100000), r'$U 1.000');
      expect(FormatoBaja.monto(145000), r'$U 1.450');
      expect(FormatoBaja.monto(123456700), r'$U 1.234.567');
    });

    test('dado centavos, entonces lleva coma decimal con dos cifras', () {
      expect(FormatoBaja.monto(145050), r'$U 1.450,50');
      expect(FormatoBaja.monto(145005), r'$U 1.450,05');
      expect(FormatoBaja.monto(5), r'$U 0,05');
    });

    test('dado un monto negativo, entonces el signo va delante', () {
      expect(FormatoBaja.monto(-145000), r'-$U 1.450');
    });
  });

  group('FormatoBaja.cuota y cobranza', () {
    test('dado un número de cuota, entonces lo escribe como el canvas', () {
      expect(FormatoBaja.cuota(2), '2.ª cuota');
      expect(FormatoBaja.cuota(12), '12.ª cuota');
    });

    test('dado una cobranza, entonces junta el monto y la cuota', () {
      expect(
        FormatoBaja.cobranza(const CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2)),
        r'$U 1.450 (2.ª cuota)',
      );
    });
  });

  group('FormatoBaja.fecha', () {
    test('dado un momento, entonces escribe día, mes y año con dos cifras', () {
      expect(FormatoBaja.fecha(DateTime(2026, 9, 12, 15)), '12/09/2026');
      expect(FormatoBaja.fecha(DateTime(2026, 1, 3, 9)), '03/01/2026');
    });
  });
}
