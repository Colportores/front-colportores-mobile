import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/pendientes_ubicacion.dart';

/// Puerto: lo que una ubicación tiene y la baja toca o impide (HU-UBI-005): visitas pendientes
/// propias, cobranza pendiente, ventas y visitas de otro colportor. Visitas, ventas y cobros todavía
/// no existen en la DB local: hasta que lleguen (HU de visitas y cobranzas) la implementación de
/// producción es `PendientesUbicacionSinFuente` y los tests usan un fake.
abstract interface class ConsultorPendientesUbicacion {
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId);
}
