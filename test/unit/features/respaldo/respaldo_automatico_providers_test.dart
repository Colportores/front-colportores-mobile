// El cableado del respaldo: cuándo se avisa «llevás N días sin backup» y el primer respaldo al
// conectar Drive (HU-SYNC-005, HU-SYNC-004).
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime.utc(2026, 11, 10, 12);

final class _Servicio implements ServicioRespaldo {
  _Servicio(this.resultado);

  final ResultadoRespaldo resultado;
  final List<OrigenRespaldo> pedidos = [];

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    pedidos.add(origen);
    return resultado;
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async =>
      const VerificacionOmitida(MotivoOmision.sinWifi);
}

void main() {
  group('diasSinRespaldo (aviso por más de 7 días)', () {
    test('sin un respaldo anterior no hay desde cuándo contar: no avisa', () {
      expect(diasSinRespaldo(ultimo: null, ahora: _ahora), isNull);
    });

    test('hasta 7 días justos no avisa; pasados, sí', () {
      expect(
        diasSinRespaldo(ultimo: _ahora.subtract(const Duration(days: 7)), ahora: _ahora),
        isNull,
      );
      expect(
        diasSinRespaldo(
          ultimo: _ahora.subtract(const Duration(days: 7, minutes: 1)),
          ahora: _ahora,
        ),
        8,
      );
    });

    test('cuenta el día en curso: 7 días y 3 horas son «8 días» (ejemplo de la HU)', () {
      expect(
        diasSinRespaldo(ultimo: _ahora.subtract(const Duration(days: 7, hours: 3)), ahora: _ahora),
        8,
      );
      expect(
        diasSinRespaldo(ultimo: _ahora.subtract(const Duration(days: 9, hours: 5)), ahora: _ahora),
        10,
      );
      // Días justos: no se suma uno de más.
      expect(diasSinRespaldo(ultimo: _ahora.subtract(const Duration(days: 8)), ahora: _ahora), 8);
      expect(diasSinRespaldo(ultimo: _ahora.subtract(const Duration(days: 45)), ahora: _ahora), 45);
    });

    test('un respaldo «del futuro» (reloj atrasado) no avisa', () {
      expect(diasSinRespaldo(ultimo: _ahora.add(const Duration(days: 3)), ahora: _ahora), isNull);
    });
  });

  group('PrimerRespaldoConServicio', () {
    test('pide un respaldo como acción de la persona: sin esperar Wi-Fi ni batería', () async {
      final servicio = _Servicio(RespaldoHecho(fecha: _ahora, esBase: true));

      final hecho = await PrimerRespaldoConServicio(() => servicio).hacer();

      expect(hecho, isTrue);
      expect(servicio.pedidos, [OrigenRespaldo.pedidoPorLaPersona]);
    });

    test('si no se hizo (omitido o fallido) lo dice, y la conexión igual queda', () async {
      for (final resultado in <ResultadoRespaldo>[
        const RespaldoOmitido(MotivoOmision.sinConexion),
        const RespaldoFallido(CausaFalloRespaldo.otra),
      ]) {
        expect(await PrimerRespaldoConServicio(() => _Servicio(resultado)).hacer(), isFalse);
      }
    });

    test('el servicio se pide al hacer el respaldo, no al armarse', () async {
      var armado = false;
      final primero = PrimerRespaldoConServicio(() {
        armado = true;
        return _Servicio(RespaldoHecho(fecha: _ahora, esBase: true));
      });

      expect(armado, isFalse);
      await primero.hacer();
      expect(armado, isTrue);
    });
  });
}
