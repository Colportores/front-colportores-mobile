import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_db_local.dart';
import '../entities/estado_intentos_borrado.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/intentos_borrado_repository.dart';

final class VerificarPasswordBorradoParams extends Equatable {
  const VerificarPasswordBorradoParams({required this.password});

  final String password;

  /// Lleva la contraseña en texto plano: sin esto, interpolar los params en un log la filtraría.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [password];
}

/// Qué pide la confirmación final y cómo va el límite de intentos, para armar la pantalla.
final class RequisitosBorrado extends Equatable {
  const RequisitosBorrado({required this.pidePassword, required this.estadoIntentos});

  /// `false` si no hay DEK envuelta con contraseña (Google sin backup): se pide solo la frase.
  final bool pidePassword;

  final EstadoIntentosBorrado estadoIntentos;

  @override
  List<Object?> get props => [pidePassword, estadoIntentos];
}

/// Confirma con la contraseña el borrado de datos locales (HU-AUTH-010, vista 19): intenta abrir la
/// DEK envuelta por contraseña (ADR-006) **en el teléfono, sin red**, y la destruye enseguida.
///
/// Hay [maxIntentos] intentos; al agotarlos, [espera] sin poder probar. La espera se guarda en
/// [IntentosBorradoRepository] para que cerrar la app no la reinicie. Pasada la espera, se empieza
/// de nuevo. Un intento bueno limpia el contador.
///
/// - `Left(FailureBorradoBloqueado)`: hay espera en curso (**no** se prueba la contraseña) o se
///   acaba de agotar el último intento.
/// - `Left(FailurePasswordBorradoIncorrecta)`: no abre; cuenta un intento.
/// - `Left(FailureIntentosBorradoIlegibles)`: el contador de intentos no se pudo leer o está mal
///   formado. Falla cerrado: no se prueba la contraseña.
/// - Cualquier otra falla (almacén ilegible, sin envoltorio) sale tal cual y **no** cuenta: no es
///   culpa de la contraseña.
///
/// El reloj [_ahora] tiene que ser monótono (`RelojMonotono`): con el del sistema, adelantar la
/// hora del teléfono destrabaría la espera.
final class VerificarPasswordBorradoUseCase
    implements UseCase<Unit, VerificarPasswordBorradoParams> {
  const VerificarPasswordBorradoUseCase(this._db, this._intentos, this._ahora);

  static const maxIntentos = 5;
  static const espera = Duration(minutes: 5);

  final DbLocalRepository _db;
  final IntentosBorradoRepository _intentos;
  final DateTime Function() _ahora;

  /// Si pide contraseña y cómo van los intentos. `Left` si el almacén no se puede leer: sin saberlo
  /// no se puede confirmar nada, y no se borra.
  Future<Either<Failure, RequisitosBorrado>> requisitos() async {
    final estado = await _db.estado();
    if (estado case Left(value: final falla)) return Left(falla);
    final e = (estado as Right<Failure, EstadoDbLocal>).value;
    final intentos = await _vigente();
    // Sin saber cuántos intentos van no se puede confirmar nada: falla cerrado.
    if (intentos.ilegible) return const Left(FailureIntentosBorradoIlegibles());
    return Right(RequisitosBorrado(pidePassword: e.envoltorioExiste, estadoIntentos: intentos));
  }

  /// El estado guardado, con la espera ya vencida dada de baja.
  Future<EstadoIntentosBorrado> _vigente() async {
    final guardado = await _intentos.leer();
    final hasta = guardado.bloqueadoHasta;
    if (hasta != null && !_ahora().isBefore(hasta)) {
      await _intentos.limpiar();
      return EstadoIntentosBorrado.limpio;
    }
    return guardado;
  }

  @override
  Future<Either<Failure, Unit>> call(VerificarPasswordBorradoParams params) async {
    if (params.password.isEmpty) {
      return const Left(FailureValidacion(campos: {'password': 'Ingresá tu contraseña'}));
    }

    final estado = await _vigente();
    if (estado.ilegible) return const Left(FailureIntentosBorradoIlegibles());
    final hasta = estado.bloqueadoHasta;
    if (hasta != null) return Left(FailureBorradoBloqueado(hasta: hasta));

    final abierta = await _db.desenvolverConPassword(params.password);
    if (abierta case Right(value: final ClaveDb dek)) {
      dek.destruir();
      await _intentos.limpiar();
      return const Right(unit);
    }
    final falla = (abierta as Left<Failure, ClaveDb>).value;
    if (falla is! FailurePasswordNoAbreDatos) return Left(falla);

    final fallidos = estado.fallidos + 1;
    if (fallidos >= maxIntentos) {
      final fin = _ahora().add(espera);
      await _intentos.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));
      return Left(FailureBorradoBloqueado(hasta: fin));
    }
    await _intentos.guardar(EstadoIntentosBorrado(fallidos: fallidos));
    return Left(FailurePasswordBorradoIncorrecta(intentosRestantes: maxIntentos - fallidos));
  }
}
