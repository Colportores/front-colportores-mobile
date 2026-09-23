import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/resumen_datos_locales.dart';

/// Los datos de negocio que este teléfono guarda (DB cifrada, sus claves y cachés), vistos como un
/// todo: para contarlos antes de cerrar sesión (HU-AUTH-006) y para borrarlos (HU-AUTH-010).
abstract interface class DatosLocalesRepository {
  /// Cantidades de lo guardado en el teléfono. `Left` si no se pudo saber — en ese caso quien
  /// borra **no** borra: sin el conteo no hay forma de saber si se pierde trabajo sin subir.
  Future<Either<Failure, ResumenDatosLocales>> resumen();

  /// Borra la DB local (sobrescritura con ceros + borrado), la sal y la marca de inicialización
  /// del almacén seguro, las cachés y, si [incluirBackupDrive], el backup en Drive.
  ///
  /// Se niega (`Left(FailureDatosSinSincronizar)`) si hay operaciones sin sincronizar o si no se
  /// puede saber: perder el trabajo de un colportor no se revierte. Es idempotente: si falla a
  /// mitad, reintentar no deja restos. Una falla de Drive no revierte lo local (HU-AUTH-010).
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({required bool incluirBackupDrive});
}
