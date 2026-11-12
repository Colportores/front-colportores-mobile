import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio_persona.dart';
import '../entities/nota_persona.dart';
import '../entities/persona.dart';
import '../repositories/persona_repository.dart';
import '../services/validador_persona.dart';

/// Los tres ids (UUID v7) de un alta: la persona, su vínculo y su primera nota. La pantalla los genera
/// **una vez por formulario** y los repite en cada intento, así que un doble toque o un reintento tras
/// una falla no crea dos personas.
final class IdsAltaPersona extends Equatable {
  const IdsAltaPersona({required this.persona, required this.vinculo, required this.nota});

  final String persona;
  final String vinculo;
  final String nota;

  @override
  List<Object?> get props => [persona, vinculo, nota];
}

/// Parámetros de [RegistrarPersonaUseCase].
final class RegistrarPersonaParams extends Equatable {
  const RegistrarPersonaParams({
    required this.ids,
    required this.espacioId,
    required this.colportorId,
    required this.nombre,
    this.apellido = '',
    this.telefono = '',
    this.nota = '',
  });

  final IdsAltaPersona ids;
  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  final String nombre;
  final String apellido;
  final String telefono;

  /// La primera nota, opcional: en blanco no crea ninguna.
  final String nota;

  /// Lleva datos personales: ver `Persona.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [ids, espacioId, colportorId, nombre, apellido, telefono, nota];
}

/// HU-UBI-008 — Alta de una persona en un espacio, solo en el teléfono.
///
/// 1. Valida: nombre (al menos 2 caracteres) y teléfono (`ValidadorPersona`). Sin ids, espacio o
///    colportor: también. Devuelve `Left(FailureValidacion)` con el detalle por campo (`nombre`,
///    `telefono`) y no toca la DB.
/// 2. Arma la persona (UUID v7 del alta, textos sin espacios de más, `apellido` vacío si no hay), su
///    vínculo con el espacio y, si la hay, su primera nota, y se los pasa al repositorio, que los guarda
///    en una sola transacción.
///
/// Todo es local: sin red el alta se completa. No se encola la persona ni la nota; el vínculo sube solo
/// con ids (ADR-017).
final class RegistrarPersonaUseCase implements UseCase<Persona, RegistrarPersonaParams> {
  /// [_generarId] se pasa como `generarId:` (parámetro nombrado privado, Dart ≥ 3.10).
  RegistrarPersonaUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PersonaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Los ids de un formulario de alta nuevo (ver [IdsAltaPersona]).
  IdsAltaPersona nuevosIds() =>
      IdsAltaPersona(persona: _generarId(), vinculo: _generarId(), nota: _generarId());

  @override
  Future<Either<Failure, Persona>> call(RegistrarPersonaParams params) {
    final espacioId = params.espacioId.trim();
    final colportorId = params.colportorId.trim();
    final ids = params.ids;
    final problemaNombre = ValidadorPersona.problemaNombre(params.nombre);
    final problemaTelefono = ValidadorPersona.problemaTelefono(params.telefono);

    final campos = <String, String>{
      if (ids.persona.trim().isEmpty || ids.vinculo.trim().isEmpty || ids.nota.trim().isEmpty)
        'ids': 'Falta el identificador del alta de la persona',
      if (espacioId.isEmpty) 'espacio': 'Falta el espacio de la persona',
      if (colportorId.isEmpty) 'colportorId': 'No hay un colportor para registrar a la persona',
      if (problemaNombre != null) 'nombre': ValidadorPersona.mensajeNombre(problemaNombre),
      if (problemaTelefono != null) 'telefono': ValidadorPersona.mensajeTelefono(problemaTelefono),
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));

    final ahora = _ahora();
    Auditoria auditoria() => Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId);
    final persona = Persona(
      id: ids.persona.trim(),
      nombre: ValidadorPersona.limpiar(params.nombre),
      apellido: ValidadorPersona.limpiar(params.apellido),
      telefono: ValidadorPersona.telefonoLimpio(params.telefono),
      auditoria: auditoria(),
    );
    final textoNota = params.nota.trim();
    return _repository.registrar(
      persona: persona,
      vinculo: EspacioPersona(
        id: ids.vinculo.trim(),
        espacioId: espacioId,
        personaId: persona.id,
        auditoria: auditoria(),
      ),
      nota: textoNota.isEmpty
          ? null
          : NotaPersona(
              id: ids.nota.trim(),
              personaId: persona.id,
              texto: textoNota,
              auditoria: auditoria(),
            ),
    );
  }
}
