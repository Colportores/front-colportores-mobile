import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../value_objects/punto_capturado.dart';

/// Puerto hacia el GPS del teléfono **mientras la colportora se mueve** (#670): una lectura cada
/// vez que cambia su posición, con el rumbo si se sabe.
///
/// Solo lo abre el GPS único del colportor (`ubicacionColportorProvider`), y solo mientras el mapa
/// la sigue y está a la vista. **No pide el permiso**: ese diálogo sale de «Activar GPS» y de la
/// apertura de la pestaña Mapa, no de un stream que se reabre solo.
abstract interface class SeguidorGps {
  /// Las lecturas del GPS, una por cada cambio de posición. El stream empieza al suscribirse y
  /// termina al cancelar. Nunca lanza: si no hay permiso, la ubicación está apagada o el plugin
  /// falla emite un `Left(FailureGpsNoDisponible)` con el motivo y termina.
  Stream<Either<Failure, LecturaGps>> seguir();
}
