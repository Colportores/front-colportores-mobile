import 'package:dartz/dartz.dart';

import '../../../../core/dispositivo/seguridad_dispositivo.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../entities/estado_db_local.dart';
import 'vigencia_sesion.dart';

/// Primitivas de la DB local cifrada que orquestan los casos de uso de HU-AUTH-009 (ADR-006).
///
/// Cada operación hace **una sola cosa** y devuelve un [Failure] en vez de lanzar. La secuencia
/// —qué camino tomar según lo que hay en el dispositivo, qué limpiar cuando algo falla— es de los
/// casos de uso: acá no hay ninguna decisión de flujo.
///
/// Las que reciben una DEK ([ClaveDb]) no la destruyen, salvo [abrir], que se queda con ella.
abstract interface class DbLocalRepository {
  /// Marca de inicialización, archivo SQLCipher y envoltorio por contraseña. Un almacén seguro que
  /// no responde no es un `Left`: sale como [MarcaDbLocal.ilegible].
  Future<Either<Failure, EstadoDbLocal>> estado();

  /// Si el equipo tiene bloqueo de pantalla (ADR-006).
  Future<Either<Failure, bool>> tieneBloqueoPantalla();

  /// Si el Keystore del equipo es por hardware o por software (S10).
  Future<Either<Failure, NivelAlmacenSeguro>> nivelAlmacenSeguro();

  /// Registra que el usuario aceptó seguir con un Keystore por software (S10).
  Future<Either<Failure, Unit>> registrarConsentimientoAlmacenSoftware();

  /// DEK guardada en el almacén seguro, o `null` si no hay ninguna. `Left(FailureAlmacenSeguro)` si
  /// el almacén falla o lo guardado no es una DEK.
  Future<Either<Failure, ClaveDb?>> leerDek();

  /// Genera una DEK nueva de 256 bits con el CSPRNG del sistema y la guarda en el almacén seguro,
  /// reemplazando la que hubiera. Exige que el dispositivo no esté marcado como inicializado: antes,
  /// [descartar]. Si no se puede guardar, la DEK se destruye y no se devuelve.
  Future<Either<Failure, ClaveDb>> crearDek();

  /// Envuelve [dek] con Argon2id([password]) en el archivo del envoltorio, reemplazando el que
  /// hubiera. Tarda de 1 a 2 s.
  Future<Either<Failure, Unit>> envolverConPassword(ClaveDb dek, String password);

  /// Desenvuelve la DEK con Argon2id([password]). `Left(FailurePasswordNoAbreDatos)` si la
  /// contraseña no la abre, `Left(FailureAlmacenSeguroSinRecuperacion)` si no hay envoltorio o no
  /// se puede leer.
  Future<Either<Failure, ClaveDb>> desenvolverConPassword(String password);

  /// Limpia el almacén seguro y lo reescribe con [dek] y la marca (recuperación guiada de ADR-006).
  /// No toca el archivo de la DB ni el envoltorio.
  Future<Either<Failure, Unit>> reconstruirAlmacen(ClaveDb dek);

  /// Abre la DB con [dek] (creándola y aplicando el esquema inicial si el archivo no existe) y la
  /// publica para el resto de la app. Desde acá la DEK es de la DB: la destruye el cierre de
  /// sesión, y también un fallo de la apertura.
  ///
  /// **Toma la apertura en forma sincrónica**: desde que se llama hasta que la DB queda registrada
  /// como "en uso" no hay ningún `await`. Los casos de uso dependen de eso para que un cierre de
  /// sesión no se cuele entre su último chequeo de sesión y la apertura (ver [abrirSiSigueVigente]).
  Future<Either<Failure, Unit>> abrir(ClaveDb dek);

  /// Marca el dispositivo como inicializado. Va **al final**, con la DB ya creada y abierta.
  Future<Either<Failure, Unit>> marcarInicializada();

  /// Deja el dispositivo como nuevo: cierra la DB si estaba abierta, borra el archivo y olvida la
  /// marca, la DEK, el consentimiento de S10 y el envoltorio por contraseña. **Destructivo**: lo
  /// que hubiera en la DB local no se recupera.
  Future<Either<Failure, Unit>> descartar();
}

/// Apertura atada a la sesión con la que arrancó el flujo (revisión del PR #44).
extension AperturaConSesionVigente on DbLocalRepository {
  /// Abre la DB solo si [testigo] sigue vigente; si no, destruye [dek] y devuelve
  /// `FailureSesionCerrada`.
  ///
  /// Sin `async` a propósito: entre el chequeo del testigo y el pedido de apertura no hay ningún
  /// `await`, así que un cierre de sesión no puede quedar en el medio. O llegó antes (y acá se ve),
  /// o llega después, con la apertura ya registrada, y la cierra. Si abriera sin mirar, la DB
  /// quedaría abierta sin sesión: el cierre ya pasó y no tiene nada que cerrar.
  Future<Either<Failure, Unit>> abrirSiSigueVigente(ClaveDb dek, TestigoSesion testigo) {
    if (!testigo.sigueVigente) {
      dek.destruir();
      return Future.value(const Left(FailureSesionCerrada()));
    }
    return abrir(dek);
  }
}
