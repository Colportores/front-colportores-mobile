// Cómo se escribe la fecha del cobro (vista 28, 28·01 y 28·04) y el enganche de «Cobrar ahora» de
// 27A·14 (#439).
import 'package:colportores_mobile/features/cobranzas/presentation/textos_cobro.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoy = DateTime(2026, 10, 23);

  group('FormatoCobro.dia', () {
    test('hoy y ayer llevan su nombre y la fecha', () {
      expect(FormatoCobro.dia(hoy, hoy), 'Hoy, 23/10');
      expect(FormatoCobro.dia(DateTime(2026, 10, 22), hoy), 'Ayer, 22/10');
    });

    test('un día anterior lleva el día de la semana y la fecha', () {
      expect(FormatoCobro.dia(DateTime(2026, 10, 21), hoy), 'Mié 21/10');
      expect(FormatoCobro.dia(DateTime(2026, 10, 12), hoy), 'Lun 12/10');
    });

    test('cruza el cambio de mes y de año', () {
      expect(FormatoCobro.dia(DateTime(2026, 9, 30), DateTime(2026, 10, 1)), 'Ayer, 30/09');
      expect(FormatoCobro.dia(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), 'Ayer, 31/12');
    });
  });

  group('FormatoCobro.diasAntes', () {
    test('retrocede días calendario, también entre meses', () {
      expect(FormatoCobro.diasAntes(DateTime(2026, 11, 1), 2), DateTime(2026, 10, 30));
      expect(FormatoCobro.diasAntes(hoy, 0), hoy);
    });
  });

  group('FormatoCobro.alMediodia', () {
    test('es el mediodía de Montevideo (UTC-3) del día', () {
      expect(FormatoCobro.alMediodia(DateTime(2026, 10, 22)), DateTime.utc(2026, 10, 22, 15));
    });
  });

  group('TextosCobro', () {
    test('los textos con monto son los del canvas', () {
      expect(
        TextosCobro.mayorAlSaldo(r'$ 1.200'),
        r'El saldo es $ 1.200. Ingresá hasta ese monto.',
      );
      expect(
        TextosCobro.sumamos(r'$ 600'),
        r'Sumamos $ 600 a tu dinero en mano. Queda en mano hasta que lo deposites.',
      );
      expect(
        TextosCobro.fechaFueraDeRango('12/10'),
        'No puede ser antes de la venta (12/10) ni después de hoy.',
      );
      expect(TextosCobro.ventaDel('0042', DateTime(2026, 10, 12)), 'Venta 0042 · 12/10');
    });
  });

  test('«Cobrar ahora» no está enganchado hasta que la app lo conecta', () {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    expect(contenedor.read(cobrarDespuesDeLaVentaProvider), isNull);
  });

  test('un test o la app puede enganchar «Cobrar ahora» con el contexto de la venta', () async {
    final vistos = <ContextoDeCobroDeLaVenta>[];
    final contenedor = ProviderContainer(
      overrides: [
        cobrarDespuesDeLaVentaProvider.overrideWith(
          (ref) => (c) async {
            vistos.add(c);
            return true;
          },
        ),
      ],
    );
    addTearDown(contenedor.dispose);

    final cobro = contenedor.read(cobrarDespuesDeLaVentaProvider)!;
    final cobrado = await cobro((
      ventaId: 'v-1',
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      colportorId: 'col-1',
    ));

    expect(cobrado, isTrue);
    expect(vistos.single.ventaId, 'v-1');
  });
}
