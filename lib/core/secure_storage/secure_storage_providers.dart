import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'almacen_seguro.dart';
import 'archivo_envoltorio_dek.dart';
import 'clave_db.dart';
import 'cripto_sodium.dart';
import 'custodia_clave_db.dart';

part 'secure_storage_providers.g.dart';

// Cableado de la custodia de la DEK (convenciones §1.2: el DI transversal vive en core/).
//
// [almacenSeguroProvider] y [archivoEnvoltorioDekProvider] no tienen implementación por defecto
// —igual que los data sources de auth—: `main.dart` los sobreescribe con el Keystore y el
// directorio reales, y los tests con fakes o un directorio temporal. Así ningún test toca el
// Keystore ni el disco del dispositivo sin decirlo.

@Riverpod(keepAlive: true)
AlmacenSeguro almacenSeguro(Ref ref) {
  throw UnimplementedError('almacenSeguroProvider se sobreescribe en main.dart');
}

@Riverpod(keepAlive: true)
ArchivoEnvoltorioDek archivoEnvoltorioDek(Ref ref) {
  throw UnimplementedError('archivoEnvoltorioDekProvider se sobreescribe en main.dart');
}

/// libsodium (ADR-006). Sí tiene implementación por defecto: no toca ninguna plataforma, solo la
/// biblioteca nativa que los build hooks empaquetan con la app (y compilan para los tests).
@Riverpod(keepAlive: true)
CriptoSodium criptoSodium(Ref ref) => CriptoSodium();

/// Argon2id de la clave que envuelve la DEK (ADR-006, S11).
@Riverpod(keepAlive: true)
ProveedorClaveDb proveedorClaveDb(Ref ref) => ref.watch(criptoSodiumProvider);

/// Cifrado autenticado de la DEK con esa clave.
@Riverpod(keepAlive: true)
SelladorDek selladorDek(Ref ref) => ref.watch(criptoSodiumProvider);

@Riverpod(keepAlive: true)
CustodiaClaveDb custodiaClaveDb(Ref ref) => CustodiaClaveDb(
  ref.watch(almacenSeguroProvider),
  ref.watch(archivoEnvoltorioDekProvider),
  ref.watch(proveedorClaveDbProvider),
  ref.watch(selladorDekProvider),
);
