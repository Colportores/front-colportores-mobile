// QA de #642 y #671: la deuda de hace 7 días (`cuenta_deuda_historial`, backend-supabase 0168, que baja con la
// sincronización desde la 0179) y la variación semanal con datos límite; privacidad de `toString`.
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/presentation/textos_deuda.dart';
import 'package:flutter_test/flutter_test.dart';

DeudaConLaCasa _de({int total = 1840000, int? haceUnaSemana}) => DeudaConLaCasa(
  deudaTotalCentavos: total,
  sumaDeSaldosCentavos: total,
  depositosValidadosCentavos: 0,
  pedidos: const [],
  deudaHace7DiasCentavos: haceUnaSemana,
);

void main() {
  group('deuda de hace 7 días del historial', () {
    test('dado que no hay fila de hace 7 días, no hay con qué comparar', () {
      final d = _de();
      expect(d.deudaHace7DiasCentavos, isNull);
      expect(d.variacionCentavos, isNull);
      expect(FormatoDeuda.lineaDeVariacion(d), 'Sin datos de la semana anterior');
    });

    test(
      'dado 0 (el servidor registró que no debía nada), es «igual» o «subió», no «sin datos»',
      () {
        final cero = _de(total: 0, haceUnaSemana: 0);
        expect(cero.variacionCentavos, 0);
        expect(FormatoDeuda.lineaDeVariacion(cero), 'Igual que la semana pasada');
        final subio = _de(haceUnaSemana: 0);
        expect(FormatoDeuda.lineaDeVariacion(subio), r'▲ $ 18.400 contra la semana pasada');
      },
    );

    test('dado un valor negativo (estaba a favor), la variación es contra ese negativo', () {
      final d = _de(haceUnaSemana: -50000);
      expect(d.variacionCentavos, 1840000 + 50000);
      expect(FormatoDeuda.lineaDeVariacion(d), r'▲ $ 18.900 contra la semana pasada');
    });

    test('dado un entero enorme, la cuenta no se desborda ni da negativo', () {
      final d = _de(total: 9000000000000000, haceUnaSemana: 1);
      expect(d.variacionCentavos, 9000000000000000 - 1);
    });
  });

  group('privacidad', () {
    test('toString de la deuda no vuelca montos ni pedidos', () {
      final d = _de(haceUnaSemana: 2050000);
      expect(d.toString(), isNot(contains('1840000')));
      expect(d.toString(), isNot(contains('2050000')));
    });
  });
}
