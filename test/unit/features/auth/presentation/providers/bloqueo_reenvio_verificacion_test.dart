import 'package:colportores_mobile/features/auth/presentation/providers/bloqueo_reenvio_verificacion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el bloqueo dura 60 minutos exactos desde el rechazo', () {
    expect(bloqueoReenvioVerificacion, const Duration(minutes: 60));
  });

  test('arranca sin bloqueo y bloquearDesde fija ahora + 60 minutos', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(bloqueoReenvioVerificacionProvider), isNull);

    final ahora = DateTime(2026, 9, 29, 10, 15);
    container.read(bloqueoReenvioVerificacionProvider.notifier).bloquearDesde(ahora);

    expect(container.read(bloqueoReenvioVerificacionProvider), DateTime(2026, 9, 29, 11, 15));
  });
}
