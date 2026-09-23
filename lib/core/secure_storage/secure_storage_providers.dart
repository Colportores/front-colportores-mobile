import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'almacen_seguro.dart';
import 'clave_db.dart';
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

/// Derivación Argon2id de la clave de la DB local (ADR-003).
///
/// **Sin implementación todavía**: la librería de Argon2id y sus parámetros de costo son el
/// Supuesto S11, pendiente de decisión (#26). Mientras tanto nadie lo sobreescribe en `main.dart` y
/// leerlo falla, como los demás providers de infraestructura sin default, en lugar de derivar con
/// algo que no se aprobó. Los tests lo sobreescriben con un fake.
@Riverpod(keepAlive: true)
ProveedorClaveDb proveedorClaveDb(Ref ref) {
  throw UnimplementedError(
    'proveedorClaveDbProvider: falta la implementación de Argon2id (Supuesto S11, #26)',
  );
}
