// Test de dominio: la vigencia de una descarga pendiente (HU-SYNC-010, #300): 7 días desde que se
// pidió, y un reloj del teléfono que estaba adelantado no la estira.
import 'package:colportores_mobile/features/tiles/domain/entities/descarga_pendiente.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  final paquete = paqueteDe(bytesDePrueba(10));
  final pedida = DateTime.utc(2026, 10, 7, 12);

  DescargaPendiente anotada(DateTime cuando) => DescargaPendiente(
    paquete: paquete,
    anotadaEn: cuando,
    permitirDatosMoviles: true,
    pausadaPorElColportor: true,
  );

  group('vencida', () {
    test('la vigencia es de 7 días', () {
      expect(DescargaPendiente.vigencia, const Duration(days: 7));
    });

    test('a los 7 días justos vence; un segundo antes todavía no', () {
      final descarga = anotada(pedida);

      expect(descarga.vencida(pedida.add(const Duration(days: 7))), isTrue);
      expect(descarga.vencida(pedida.add(const Duration(days: 7, seconds: -1))), isFalse);
      expect(descarga.vencida(pedida), isFalse);
    });

    test('con fecha futura (reloj adelantado que se corrigió) no vence', () {
      final descarga = anotada(pedida.add(const Duration(days: 30)));

      expect(descarga.vencida(pedida), isFalse);
      expect(descarga.vencida(pedida.add(const Duration(days: 8))), isFalse);
    });
  });

  group('sinFechaFutura', () {
    test('con fecha pasada devuelve la misma descarga', () {
      final descarga = anotada(pedida);

      expect(
        identical(descarga.sinFechaFutura(pedida.add(const Duration(days: 3))), descarga),
        isTrue,
      );
    });

    test('con la fecha de ahora devuelve la misma descarga', () {
      final descarga = anotada(pedida);

      expect(identical(descarga.sinFechaFutura(pedida), descarga), isTrue);
    });

    test('con fecha futura la lleva a ahora y conserva todo lo demás', () {
      final ahora = pedida;
      final descarga = anotada(pedida.add(const Duration(days: 30)));

      final corregida = descarga.sinFechaFutura(ahora);

      expect(corregida, anotada(ahora));
      expect(corregida.paquete, paquete);
      expect(corregida.permitirDatosMoviles, isTrue);
      expect(corregida.pausadaPorElColportor, isTrue);
    });

    test('desde la fecha corregida los 7 días cuentan desde ahora', () {
      final ahora = pedida;
      final corregida = anotada(pedida.add(const Duration(days: 30))).sinFechaFutura(ahora);

      expect(corregida.vencida(ahora.add(const Duration(days: 7))), isTrue);
      expect(corregida.vencida(ahora.add(const Duration(days: 7, seconds: -1))), isFalse);
    });
  });
}
