import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/persona.dart';
import '../entities/resultado_baja_persona.dart';
import '../repositories/persona_repository.dart';
import '../services/cuenta_de_persona.dart';

// Los casos de uso de la baja de una persona (HU-UBI-011). Todo es local: sin red se completan, y no
// se encola nada al sync.

/// Parámetros de [DarDeBajaPersonaUseCase].
final class DarDeBajaPersonaParams extends Equatable {
  const DarDeBajaPersonaParams({required this.personaId, this.motivo, this.confirmaSaldo = false});

  /// Cuántos caracteres puede tener el motivo.
  static const maximoMotivo = 120;

  final String personaId;

  /// Por qué se da de baja, opcional (`reason` del evento `persona_baja`). El canvas no lo pide.
  final String? motivo;

  /// La colportora ya vio que la persona debe algo y confirmó las dos veces (32D·02 y 32D·03).
  final bool confirmaSaldo;

  /// El motivo es texto de la colportora: ver `Persona.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [personaId, motivo, confirmaSaldo];
}

/// HU-UBI-011 — Baja de persona (soft delete, local-only).
///
/// 1. Valida el id y el largo del motivo (`FailureValidacion`, sin tocar la DB).
/// 2. Si la persona debe algo y no vino [DarDeBajaPersonaParams.confirmaSaldo], **no escribe** y
///    devuelve [BajaPersonaRequiereConfirmacion] con la cuenta: la doble confirmación no se puede
///    saltear aunque la pantalla se haya abierto antes de que llegara una venta. Si no se puede leer la
///    cuenta, tampoco se da de baja (`FailureInesperado`): ante la duda se frena.
/// 3. Da de baja a la persona en el repositorio (`deleted_at` y evento `persona_baja`, una
///    transacción).
final class DarDeBajaPersonaUseCase
    implements UseCase<ResultadoBajaPersona, DarDeBajaPersonaParams> {
  DarDeBajaPersonaUseCase(this._repository, this._cuentas, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PersonaRepository _repository;
  final CuentasDePersonas _cuentas;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoBajaPersona>> call(DarDeBajaPersonaParams params) async {
    final id = params.personaId.trim();
    final recortado = params.motivo?.trim();
    final motivo = recortado == null || recortado.isEmpty ? null : recortado;
    final errores = <String, String>{
      if (id.isEmpty) 'persona': 'Falta la persona que se da de baja',
      if (motivo != null && motivo.length > DarDeBajaPersonaParams.maximoMotivo)
        'motivo': 'El motivo puede tener hasta ${DarDeBajaPersonaParams.maximoMotivo} caracteres',
    };
    if (errores.isNotEmpty) return Left(FailureValidacion(campos: errores));

    if (!params.confirmaSaldo) {
      try {
        final cuenta = await _cuentas.resumenDe(id);
        if (cuenta != null && cuenta.tieneSaldo) {
          return Right(BajaPersonaRequiereConfirmacion(cuenta));
        }
      } on Object catch (e) {
        // Solo el tipo: la excepción de un adaptador puede traer datos de la persona.
        return Left(FailureInesperado(causa: e.runtimeType.toString()));
      }
    }
    final baja = await _repository.darDeBaja(personaId: id, ahora: _ahora(), motivo: motivo);
    return baja.map<ResultadoBajaPersona>(PersonaDadaDeBaja.new);
  }
}

/// Reactiva a una persona dada de baja («Reactivar», 32D·04). Idempotente.
final class ReactivarPersonaUseCase implements UseCase<Persona, String> {
  ReactivarPersonaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PersonaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Persona>> call(String personaId) => personaId.trim().isEmpty
      ? Future.value(
          const Left(FailureValidacion(campos: {'persona': 'Falta la persona que se reactiva'})),
        )
      : _repository.reactivar(personaId: personaId.trim(), ahora: _ahora());
}

/// La cuenta de [personaId] para la hoja de la baja (32D·01 contra 32D·02): `null` si no tiene ventas.
/// Si no se puede leer devuelve la falla: la hoja no da por hecho que no debe nada.
final class ConsultarCuentaDePersonaUseCase implements UseCase<ResumenCuentaPersona?, String> {
  const ConsultarCuentaDePersonaUseCase(this._cuentas);

  final CuentasDePersonas _cuentas;

  @override
  Future<Either<Failure, ResumenCuentaPersona?>> call(String personaId) async {
    try {
      return Right(await _cuentas.resumenDe(personaId.trim()));
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }
}
