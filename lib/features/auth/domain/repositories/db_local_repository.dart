import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../entities/estado_db_local.dart';

/// Primitivas de la DB local cifrada que orquesta `InicializarDbLocalUseCase` (HU-AUTH-009).
///
/// Cada operación hace **una sola cosa** y devuelve un [Failure] en vez de lanzar. La secuencia
/// —qué camino tomar según lo que hay en el dispositivo, qué limpiar cuando algo falla— es del caso
/// de uso: acá no hay ninguna decisión de flujo.
abstract interface class DbLocalRepository {
  /// Marca de inicialización del almacén seguro y existencia del archivo SQLCipher.
  Future<Either<Failure, EstadoDbLocal>> estado();

  /// Sal guardada en el almacén seguro, o `null` si no hay ninguna.
  Future<Either<Failure, Uint8List?>> leerSal();

  /// Genera una sal nueva de 256 bits desde el CSPRNG del sistema y la persiste, reemplazando la
  /// que hubiera. Exige que el dispositivo no esté marcado como inicializado: antes, [descartar].
  Future<Either<Failure, Uint8List>> generarSal();

  /// Deriva la clave de la DB desde [password] y [sal] (Argon2id — ADR-003). La clave vive solo en
  /// memoria: quien la recibe es responsable de destruirla o de pasársela a [abrir].
  Future<Either<Failure, ClaveDb>> derivarClave({required String password, required Uint8List sal});

  /// Abre la DB con [clave] (creándola y aplicando el esquema inicial si el archivo no existe) y la
  /// publica para el resto de la app. Desde acá la clave es de la DB: la destruye el cierre de
  /// sesión, y también un fallo de la apertura.
  ///
  /// **Toma la apertura en forma sincrónica**: desde que se llama hasta que la DB queda registrada
  /// como "en uso" no hay ningún `await`. El caso de uso depende de eso para que un cierre de sesión
  /// no se cuele entre su último chequeo de sesión y la apertura.
  Future<Either<Failure, Unit>> abrir(ClaveDb clave);

  /// Marca el dispositivo como inicializado. Va **al final**, con la DB ya creada y abierta.
  Future<Either<Failure, Unit>> marcarInicializada();

  /// Deja el dispositivo como nuevo: cierra la DB si estaba abierta, borra el archivo y olvida la
  /// sal y la marca. **Destructivo**: lo que hubiera en la DB local no se recupera.
  Future<Either<Failure, Unit>> descartar();
}
