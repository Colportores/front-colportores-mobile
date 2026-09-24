import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/dispositivo/dispositivo_providers.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../data/repositories/db_local_repository_impl.dart';
import '../../domain/repositories/db_local_repository.dart';
import '../../domain/repositories/vigencia_sesion.dart';
import '../../domain/services/turno_db_local.dart';
import '../../domain/usecases/empezar_de_nuevo_db_local_use_case.dart';
import '../../domain/usecases/inicializar_db_local_use_case.dart';
import '../../domain/usecases/recuperar_db_local_con_password_use_case.dart';
import 'sesion_notifier.dart';

part 'db_local_providers.g.dart';

// Cableado de la DB local cifrada (HU-AUTH-009, ADR-006). Vive aparte de `auth_providers.dart` a
// propósito: no toca el login. Lo usa quien dispare la inicialización después de un login o al
// restaurar la sesión (la pantalla de progreso, #27).

@Riverpod(keepAlive: true)
DbLocalRepository dbLocalRepository(Ref ref) => DbLocalRepositoryImpl(
  custodia: ref.watch(custodiaClaveDbProvider),
  seguridad: ref.watch(seguridadDispositivoProvider),
  helper: ref.watch(databaseHelperProvider),
  dbLocal: ref.watch(dbLocalProvider.notifier),
);

/// `keepAlive` porque el testigo usa `ref` después de construirse: si el provider se descartara
/// mientras se envuelve la DEK, el chequeo posterior no podría leer la sesión.
@Riverpod(keepAlive: true)
VigenciaSesion vigenciaSesion(Ref ref) => _VigenciaSesionRiverpod(ref);

/// Un solo turno para toda la app, compartido por los tres flujos de la DB local (revisión del PR
/// #81): `keepAlive`, o cada caso de uso tendría el suyo y no serviría de nada.
@Riverpod(keepAlive: true)
TurnoDbLocal turnoDbLocal(Ref ref) => TurnoDbLocal();

@riverpod
InicializarDbLocalUseCase inicializarDbLocalUseCase(Ref ref) => InicializarDbLocalUseCase(
  ref.watch(dbLocalRepositoryProvider),
  ref.watch(vigenciaSesionProvider),
  ref.watch(turnoDbLocalProvider),
);

@riverpod
RecuperarDbLocalConPasswordUseCase recuperarDbLocalConPasswordUseCase(Ref ref) =>
    RecuperarDbLocalConPasswordUseCase(
      ref.watch(dbLocalRepositoryProvider),
      ref.watch(vigenciaSesionProvider),
      ref.watch(turnoDbLocalProvider),
    );

@riverpod
EmpezarDeNuevoDbLocalUseCase empezarDeNuevoDbLocalUseCase(Ref ref) => EmpezarDeNuevoDbLocalUseCase(
  ref.watch(dbLocalRepositoryProvider),
  ref.watch(turnoDbLocalProvider),
);

/// La sesión vigente es la de `sesionProvider`, y el cierre de sesión se detecta por
/// `cierresDbLocalProvider`.
///
/// Mirar solo `sesionProvider` no alcanza: `SesionNotifier.cerrarSesion` pasa la sesión a `null`
/// recién al final, **después** de pedirle a la DB que cierre, y entre las dos cosas hay un `await`.
/// Un chequeo que cayera justo ahí vería la sesión viva con el cierre ya hecho. El contador se
/// incrementa en la primera línea de `DbLocalNotifier.cerrar()`, así que no tiene esa ventana.
final class _VigenciaSesionRiverpod implements VigenciaSesion {
  _VigenciaSesionRiverpod(this._ref);

  final Ref _ref;

  @override
  TestigoSesion? tomarTestigo() {
    final sesion = _ref.read(sesionProvider).value;
    if (sesion == null) return null;
    final cierres = _ref.read(cierresDbLocalProvider);
    return _Testigo(_ref, sesion.usuarioId, cierres, cierres.pedidos);
  }
}

final class _Testigo implements TestigoSesion {
  _Testigo(this._ref, this._usuarioId, this._cierres, this._pedidosAlTomar);

  final Ref _ref;
  final String _usuarioId;
  final CierresDbLocal _cierres;
  final int _pedidosAlTomar;

  @override
  bool get sigueVigente {
    final cierres = _ref.read(cierresDbLocalProvider);
    // Otro contador (el provider se reconstruyó) cuenta desde cero: falla cerrado.
    if (!identical(cierres, _cierres) || cierres.pedidos != _pedidosAlTomar) return false;
    return _ref.read(sesionProvider).value?.usuarioId == _usuarioId;
  }
}
