// Cableado del almacén seguro: el provider no trae implementación por defecto y la custodia se
// arma con la que se inyecte.
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/secure_storage/secure_storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secure_storage providers', () {
    test('dado que nadie lo inyectó, almacenSeguroProvider falla en vez de inventar uno', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(almacenSeguroProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });

    test('dado un almacén inyectado, custodiaClaveDbProvider lo usa', () async {
      final almacen = AlmacenSeguroEnMemoria();
      final container = ProviderContainer(
        overrides: [almacenSeguroProvider.overrideWithValue(almacen)],
      );
      addTearDown(container.dispose);

      final custodia = container.read(custodiaClaveDbProvider);
      await custodia.generarSal();

      expect(custodia, isA<CustodiaClaveDb>());
      expect(almacen.contenido, isNotEmpty, reason: 'escribe en el almacén inyectado');
    });
  });
}
