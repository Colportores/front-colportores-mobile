// El puerto de los saldos de «¿Con quién?» (vista 39 C·07): sin ventas locales todavía no se sabe de
// nadie, y «no se sabe» no es «debe cero».
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:test/test.dart';

void main() {
  test('dado que no hay de dónde sacar el saldo, cuando se pide, no se sabe de nadie', () async {
    const fuente = SaldosDePersonasSinFuente();

    expect(await fuente.saldosPendientes(['pedro', 'ana']), isEmpty);
    expect(await fuente.saldosPendientes(const []), isEmpty);
  });
}
