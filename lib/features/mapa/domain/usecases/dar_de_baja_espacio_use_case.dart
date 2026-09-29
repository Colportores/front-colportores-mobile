import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/motivo_rechazo_espacio.dart';
import '../entities/resultado_baja_espacio.dart';
import '../entities/ubicacion.dart';
import '../repositories/espacio_repository.dart';
import '../services/contador_personas_espacio.dart';

/// Parámetros de [DarDeBajaEspacioUseCase].
final class DarDeBajaEspacioParams extends Equatable {
  const DarDeBajaEspacioParams({required this.id, this.confirmaConPersonas = false});

  final String id;

  /// El colportor ya vio el aviso de que el espacio tiene personas y eligió seguir.
  final bool confirmaConPersonas;

  @override
  List<Object?> get props => [id, confirmaConPersonas];
}

/// HU-UBI-007 — Baja lógica de un espacio (R-UB04).
///
/// En orden:
///
/// 1. Sin `id`, o un espacio que no existe: `Left(FailureValidacion)`.
/// 2. Espacio de una `CASA`: `Left(FailureValidacion)` — su espacio default es invisible y no se
///    gestiona.
/// 3. Ya dado de baja: `Right(BajaRealizada)` sin escribir (repetir el pedido es inocuo).
/// 4. Con personas y es el último espacio activo de la ubicación:
///    `Left(FailureUltimoEspacioConPersonas)` ("Edge — único espacio activo con personas").
/// 5. Con personas y sin confirmar: `Right(BajaRequiereConfirmacion)`, sin escribir ("Baja de
///    espacio con personas"). Repetido con `confirmaConPersonas: true` procede.
/// 6. Si no, la baja: `deleted_at` en el espacio, en una transacción con el encolado del sync. Las
///    personas no se tocan: quedan accesibles con la etiqueta "Espacio dado de baja".
///
/// Sin personas, se puede dar de baja hasta el último espacio de un edificio o negocio: la regla
/// de "mínimo 1" solo protege a las personas.
final class DarDeBajaEspacioUseCase
    implements UseCase<ResultadoBajaEspacio, DarDeBajaEspacioParams> {
  DarDeBajaEspacioUseCase(this._repository, this._personas, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final EspacioRepository _repository;
  final ContadorPersonasEspacio _personas;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoBajaEspacio>> call(DarDeBajaEspacioParams params) async {
    final id = params.id.trim();
    if (id.isEmpty) {
      return const Left(FailureValidacion(campos: {'id': 'Falta el espacio a dar de baja'}));
    }

    final buscado = await _repository.buscar(id);
    final falloBusqueda = buscado.fold<Failure?>((f) => f, (_) => null);
    if (falloBusqueda != null) return Left(falloBusqueda);
    final encontrado = buscado.getOrElse(() => null);
    if (encontrado == null) return _rechazo(MotivoRechazoEspacio.espacioInexistente);

    final espacio = encontrado.espacio;
    if (encontrado.ubicacion.tipo == TipoUbicacion.casa) {
      return _rechazo(MotivoRechazoEspacio.ubicacionCasa);
    }
    if (espacio.estaBorrada) return Right(BajaRealizada(espacio));

    final int personas;
    try {
      personas = await _personas.activasEn(id);
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e));
    }
    if (personas > 0) {
      final activos = await _repository.contarActivos(espacio.ubicacionId);
      final falloConteo = activos.fold<Failure?>((f) => f, (_) => null);
      if (falloConteo != null) return Left(falloConteo);
      if (activos.getOrElse(() => 0) <= 1) return const Left(FailureUltimoEspacioConPersonas());
      if (!params.confirmaConPersonas) return Right(BajaRequiereConfirmacion(personas: personas));
    }

    final baja = await _repository.darDeBaja(id, ahora: _ahora());
    return baja.map(BajaRealizada.new);
  }

  static Either<Failure, ResultadoBajaEspacio> _rechazo(MotivoRechazoEspacio motivo) =>
      Left(FailureValidacion(campos: {motivo.campo: motivo.mensaje}));
}
