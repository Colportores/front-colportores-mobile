import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/pendientes_ubicacion.dart';

/// Puerto: cuántas visitas pendientes, ventas con saldo y cobros sin cerrar tiene una ubicación
/// (HU-UBI-005). Visitas, ventas y cobros todavía no existen en la DB local: hasta que lleguen
/// (HU de visitas y cobranzas) no hay implementación de producción y los tests usan un fake.
abstract interface class ConsultorPendientesUbicacion {
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId);
}
