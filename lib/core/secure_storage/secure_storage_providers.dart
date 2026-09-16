import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'almacen_seguro.dart';
import 'custodia_clave_db.dart';

part 'secure_storage_providers.g.dart';

// Cableado del almacén seguro (convenciones §1.2: el DI transversal vive en core/).
//
// [almacenSeguroProvider] no tiene implementación por defecto —igual que los data sources de
// auth—: `main.dart` lo sobreescribe con el adaptador real y los tests con el fake en memoria.
// Así ninguna capa puede quedarse sin inyectar y, sobre todo, ningún test toca el Keystore.

@Riverpod(keepAlive: true)
AlmacenSeguro almacenSeguro(Ref ref) {
  throw UnimplementedError('almacenSeguroProvider se sobreescribe en main.dart');
}

@Riverpod(keepAlive: true)
CustodiaClaveDb custodiaClaveDb(Ref ref) => CustodiaClaveDb(ref.watch(almacenSeguroProvider));
