import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../secure_storage/clave_db.dart';
import 'app_database.dart';
import 'database_helper.dart';

part 'database_providers.g.dart';

// Cableado de la DB local (convenciones §1.2: el DI transversal vive en core/).
//
// [databaseHelperProvider] no tiene implementación por defecto —igual que `almacenSeguroProvider`—:
// `main.dart` lo sobreescribe con los directorios reales de `path_provider` y los tests con un
// directorio temporal. Así ningún test toca el disco del dispositivo sin decirlo.

@Riverpod(keepAlive: true)
DatabaseHelper databaseHelper(Ref ref) {
  throw UnimplementedError('databaseHelperProvider se sobreescribe en main.dart');
}

/// La DB local abierta, o `null` mientras no hay sesión.
///
/// Es la única puerta de entrada al [AppDatabase] para el resto de la app: los providers de DAOs
/// y data sources hacen `ref.watch(dbLocalProvider)` y se reconstruyen solos cuando la DB se abre
/// o se cierra (un `AppDatabase` cerrado nunca queda cacheado en un consumidor). Misma forma que
/// `SesionNotifier`: el estado sigue a la sesión.
///
/// [abrir] lo llama el flujo de login de HU-AUTH-009 (#27) con la clave derivada; [cerrar] lo
/// llama `SesionNotifier.cerrarSesion`.
@Riverpod(keepAlive: true)
class DbLocalNotifier extends _$DbLocalNotifier {
  /// Si [abrir] llegó a pedirle algo al helper. Se marca **antes** del primer `await`: mirar
  /// `state` no sirve, porque recién se asigna cuando la apertura ya terminó, y un [cerrar] con una
  /// apertura en vuelo se iría sin cerrar nada (la DB quedaría abierta después del logout).
  bool _helperEnUso = false;

  @override
  AppDatabase? build() => null;

  /// Abre la DB con [clave] (ver `DatabaseHelper.abrir` para los errores) y la publica.
  Future<AppDatabase> abrir(ClaveDb clave) async {
    final helper = ref.read(databaseHelperProvider);
    _helperEnUso = true;
    final db = await helper.abrir(clave);
    state = db;
    return db;
  }

  /// Cierra la DB y destruye la clave. Si hay una apertura en vuelo, `DatabaseHelper.cerrar`
  /// espera a que termine y cierra lo que abrió.
  ///
  /// Mientras tanto la continuación de [abrir] puede publicar la DB recién abierta; el `finally`
  /// de acá la vuelve a `null` al final, así que el estado que queda es el del cierre.
  ///
  /// Si [abrir] nunca se llamó, no toca el helper: así el cierre de sesión funciona igual en
  /// entornos donde la DB no se cableó (tests de widgets, Sprint 2). Una vez usado, siempre se le
  /// delega: `DatabaseHelper.cerrar` ya es no-op sin DB abierta.
  Future<void> cerrar() async {
    if (!_helperEnUso) return;
    try {
      await ref.read(databaseHelperProvider).cerrar();
    } finally {
      state = null;
    }
  }
}
