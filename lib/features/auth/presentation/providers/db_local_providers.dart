import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../data/repositories/db_local_repository_impl.dart';
import '../../domain/repositories/db_local_repository.dart';
import '../../domain/repositories/vigencia_sesion.dart';
import '../../domain/usecases/inicializar_db_local_use_case.dart';
import 'sesion_notifier.dart';

part 'db_local_providers.g.dart';

// Cableado de la inicialización de la DB local cifrada (HU-AUTH-009). Vive aparte de
// `auth_providers.dart` a propósito: no toca el login, lo usa quien lo dispare después de un login
// con contraseña (la pantalla de progreso, #27).
//
// `dbLocalRepositoryProvider` depende de `proveedorClaveDbProvider`, que todavía no tiene
// implementación (Argon2id, Supuesto S11): hasta que la tenga, leer el caso de uso falla con
// `UnimplementedError`.

@Riverpod(keepAlive: true)
DbLocalRepository dbLocalRepository(Ref ref) => DbLocalRepositoryImpl(
  custodia: ref.watch(custodiaClaveDbProvider),
  proveedorClave: ref.watch(proveedorClaveDbProvider),
  helper: ref.watch(databaseHelperProvider),
  dbLocal: ref.watch(dbLocalProvider.notifier),
);

/// `keepAlive` porque el testigo usa `ref` después de construirse: si el provider se descartara
/// mientras la clave se deriva, el chequeo posterior no podría leer la sesión.
@Riverpod(keepAlive: true)
VigenciaSesion vigenciaSesion(Ref ref) => _VigenciaSesionRiverpod(ref);

@riverpod
InicializarDbLocalUseCase inicializarDbLocalUseCase(Ref ref) => InicializarDbLocalUseCase(
  ref.watch(dbLocalRepositoryProvider),
  ref.watch(vigenciaSesionProvider),
);

/// La sesión vigente es la de `sesionProvider`, y el cierre de sesión se detecta por
/// `DbLocalNotifier.cierresPedidos`.
///
/// Mirar solo `sesionProvider` no alcanza: `SesionNotifier.cerrarSesion` pasa la sesión a `null`
/// recién al final, **después** de pedirle a la DB que cierre, y entre las dos cosas hay un `await`.
/// Un chequeo que cayera justo ahí vería la sesión viva con el cierre ya hecho. El contador del
/// notifier se incrementa en la primera línea de `cerrar()`, así que no tiene esa ventana.
final class _VigenciaSesionRiverpod implements VigenciaSesion {
  _VigenciaSesionRiverpod(this._ref);

  final Ref _ref;

  @override
  TestigoSesion? tomarTestigo() {
    final sesion = _ref.read(sesionProvider).value;
    if (sesion == null) return null;
    final dbLocal = _ref.read(dbLocalProvider.notifier);
    return _Testigo(_ref, sesion.usuarioId, dbLocal, dbLocal.cierresPedidos);
  }
}

final class _Testigo implements TestigoSesion {
  _Testigo(this._ref, this._usuarioId, this._dbLocal, this._cierres);

  final Ref _ref;
  final String _usuarioId;
  final DbLocalNotifier _dbLocal;
  final int _cierres;

  @override
  bool get sigueVigente {
    final dbLocal = _ref.read(dbLocalProvider.notifier);
    // Otro notifier (el provider se reconstruyó) cuenta desde cero: falla cerrado.
    if (!identical(dbLocal, _dbLocal) || dbLocal.cierresPedidos != _cierres) return false;
    return _ref.read(sesionProvider).value?.usuarioId == _usuarioId;
  }
}
