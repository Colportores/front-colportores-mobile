// Falsos de la baja y la reactivación de una ubicación (HU-UBI-005, vista 09): lo que el teléfono sabe
// de la casa antes de darla de baja, con las pausas y las fallas que piden los casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:dartz/dartz.dart';

/// El consultor de lo pendiente de una ubicación: devuelve [pendientes] (nada, por defecto), con la
/// posibilidad de hacerlo esperar, fallar o lanzar.
final class PendientesFalso implements ConsultorPendientesUbicacion {
  PendientesFalso([this.pendientes = PendientesUbicacion.ninguno]);

  /// Lo que se devuelve; el test lo cambia entre consulta y consulta.
  PendientesUbicacion pendientes;

  /// Si no es `null`, la consulta espera a que se complete.
  Completer<void>? espera;

  /// Si no es `null`, la consulta devuelve esta falla.
  Failure? falla;

  /// Si no es `null`, la consulta lanza esto (un puerto roto).
  Object? lanza;

  /// Los ids consultados, en orden.
  final consultadas = <String>[];

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async {
    consultadas.add(ubicacionId);
    final pausa = espera;
    if (pausa != null) await pausa.future;
    final roto = lanza;
    if (roto != null) throw roto;
    final f = falla;
    return f != null ? Left(f) : Right(pendientes);
  }
}
