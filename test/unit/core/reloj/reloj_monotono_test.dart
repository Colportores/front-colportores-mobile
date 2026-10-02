import 'package:colportores_mobile/core/reloj/reloj_monotono.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arranca en la hora del sistema y avanza con el cronómetro', () {
    var corrido = Duration.zero;
    final reloj = RelojMonotono(
      sistema: () => DateTime.utc(2026, 9, 30, 12),
      transcurrido: () => corrido,
    );

    expect(reloj.ahora(), DateTime.utc(2026, 9, 30, 12));
    corrido = const Duration(minutes: 5);
    expect(reloj.ahora(), DateTime.utc(2026, 9, 30, 12, 5));
  });

  test('mover la hora del sistema, hacia adelante o atrás, no cambia lo que devuelve', () {
    var sistema = DateTime.utc(2026, 9, 30, 12);
    final reloj = RelojMonotono(sistema: () => sistema, transcurrido: () => Duration.zero);

    sistema = DateTime.utc(2030);
    expect(reloj.ahora(), DateTime.utc(2026, 9, 30, 12));
    sistema = DateTime.utc(2020);
    expect(reloj.ahora(), DateTime.utc(2026, 9, 30, 12));
  });

  test('sin inyectar nada, devuelve una hora cercana a la actual y en UTC', () {
    final reloj = RelojMonotono();

    expect(reloj.ahora().isUtc, isTrue);
    expect(
      reloj.ahora().difference(DateTime.now().toUtc()).abs(),
      lessThan(const Duration(seconds: 5)),
    );
  });
}
