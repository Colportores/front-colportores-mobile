import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/persona_repository.dart';
import '../services/validador_persona.dart';

/// Parámetros de [ModificarPersonaUseCase]: lo que el colportor dejó en el formulario, tal cual.
final class ModificarPersonaParams extends Equatable {
  const ModificarPersonaParams({
    required this.personaId,
    required this.nombre,
    this.apellido = '',
    this.telefono = '',
  });

  final String personaId;
  final String nombre;
  final String apellido;
  final String telefono;

  /// Lleva datos personales: ver `Persona.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [personaId, nombre, apellido, telefono];
}

/// HU-UBI-010 — Modificar el nombre, el apellido y el teléfono de una persona, solo en el teléfono.
///
/// 1. Valida con las mismas reglas del alta (`ValidadorPersona`): nombre con al menos 2 caracteres
///    (vaciado: «El nombre no puede quedar vacío.», canvas 32C·02) y teléfono con formato. Devuelve
///    `Left(FailureValidacion)` con el detalle por campo (`nombre`, `telefono`) y no toca la DB.
/// 2. Le pasa al repositorio los textos sin espacios de más (`apellido` vacío si no hay, teléfono
///    `null` si se lo vació) y la hora; el repositorio escribe todo o nada, deja el evento
///    `persona_modificada` en el `audit_log` local y no encola nada.
///
/// Si lo que se pidió ya era lo que estaba, no se escribe nada (`huboCambios: false`).
final class ModificarPersonaUseCase
    implements UseCase<ResultadoModificarPersona, ModificarPersonaParams> {
  /// [_ahora] se pasa como `ahora:` (parámetro nombrado privado, Dart ≥ 3.10).
  ModificarPersonaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PersonaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoModificarPersona>> call(ModificarPersonaParams params) {
    final personaId = params.personaId.trim();
    final problemaNombre = ValidadorPersona.problemaNombre(params.nombre);
    final problemaTelefono = ValidadorPersona.problemaTelefono(params.telefono);

    final campos = <String, String>{
      if (personaId.isEmpty) 'persona': 'Falta la persona que se quiere modificar',
      if (problemaNombre != null) 'nombre': ValidadorPersona.mensajeNombreEdicion(problemaNombre),
      if (problemaTelefono != null) 'telefono': ValidadorPersona.mensajeTelefono(problemaTelefono),
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));

    return _repository.modificar(
      personaId: personaId,
      nombre: ValidadorPersona.limpiar(params.nombre),
      apellido: ValidadorPersona.limpiar(params.apellido),
      telefono: ValidadorPersona.telefonoLimpio(params.telefono),
      ahora: _ahora(),
    );
  }
}
