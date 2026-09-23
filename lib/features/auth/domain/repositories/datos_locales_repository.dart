import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/resumen_datos_locales.dart';

/// Los datos de negocio que este teléfono guarda (DB cifrada, sus claves y cachés), vistos como un
/// todo: para contarlos antes de cerrar sesión (HU-AUTH-006) y para borrarlos (HU-AUTH-010).
abstract interface class DatosLocalesRepository {
  /// Cantidades de lo guardado en el teléfono. Si lo pendiente no se puede contar, llega como
  /// `null` en [ResumenDatosLocales.operacionesSinSincronizar] (no es un `Left`: igual se puede
  /// borrar). `Left` solo ante una falla inesperada.
  Future<Either<Failure, ResumenDatosLocales>> resumen();

  /// Borra la DB local (sobrescritura con ceros + borrado), la sal y la marca de inicialización
  /// del almacén seguro, las cachés y, si [incluirBackupDrive], el backup en Drive.
  ///
  /// Borra aunque haya operaciones sin sincronizar (decisión de Cristian en #66: es el objetivo de
  /// la HU; la pantalla ya lo avisó y pidió confirmarlo). Es idempotente: si falla a mitad,
  /// reintentar termina el trabajo sin restos. Una falla de Drive no revierte lo local.
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({required bool incluirBackupDrive});
}
