// Cableado de la custodia de la DEK: el almacén y el archivo del envoltorio no traen implementación
// por defecto; libsodium sí. La custodia se arma con lo que se inyecte.
import 'dart:io';

import 'package:colportores_mobile/core/dispositivo/dispositivo_providers.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/secure_storage/secure_storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

Matcher get _sinImplementacion => throwsA(
  isA<ProviderException>().having((e) => e.exception, 'exception', isA<UnimplementedError>()),
);

void main() {
  group('secure_storage providers', () {
    test('dado que nadie los inyectó, el almacén, el archivo del envoltorio y la seguridad del '
        'equipo fallan en vez de inventar uno', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(almacenSeguroProvider), _sinImplementacion);
      expect(() => container.read(archivoEnvoltorioDekProvider), _sinImplementacion);
      expect(() => container.read(seguridadDispositivoProvider), _sinImplementacion);
    });

    test('dado que nadie la inyectó, la derivación y el sellado son libsodium', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(proveedorClaveDbProvider), isA<CriptoSodium>());
      expect(container.read(selladorDekProvider), same(container.read(proveedorClaveDbProvider)));
    });

    test('dado un almacén y un archivo inyectados, custodiaClaveDbProvider los usa', () async {
      final dir = await Directory.systemTemp.createTemp('providers_');
      addTearDown(() => dir.delete(recursive: true));
      final almacen = AlmacenSeguroEnMemoria();
      final container = ProviderContainer(
        overrides: [
          almacenSeguroProvider.overrideWithValue(almacen),
          archivoEnvoltorioDekProvider.overrideWithValue(
            ArchivoEnvoltorioDek(directorio: () async => dir),
          ),
        ],
      );
      addTearDown(container.dispose);

      final custodia = container.read(custodiaClaveDbProvider);
      await custodia.guardarDek(custodia.generarDek());

      expect(custodia, isA<CustodiaClaveDb>());
      expect(almacen.contenido, isNotEmpty, reason: 'escribe en el almacén inyectado');
    });
  });
}
