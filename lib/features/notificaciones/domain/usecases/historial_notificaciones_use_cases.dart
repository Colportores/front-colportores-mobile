import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/destino_notificacion.dart';
import '../entities/notificacion.dart';
import '../repositories/historial_notificaciones_repository.dart';

/// Los casos de uso del historial de avisos (HU-NOT-005). Cada uno recibe el reloj ya resuelto:
/// la pantalla y los tests deciden «ahora».

/// Guarda un aviso recibido (un recordatorio local que sonó; las push, con HU-NOT-003). Es lo que
/// llama quien lo recibe. Idempotente por `id`.
final class RegistrarNotificacionUseCase {
  const RegistrarNotificacionUseCase(this._repositorio, {required this._ahora});

  final HistorialNotificacionesRepository _repositorio;
  final DateTime Function() _ahora;

  /// `Right(true)` si se guardó, `Right(false)` si ya estaba. Un aviso sin título o sin id es un
  /// `FailureValidacion`: no se guarda una fila que la pantalla no sabría mostrar.
  Future<Either<Failure, bool>> call(Notificacion notificacion) async {
    if (notificacion.id.trim().isEmpty) {
      return const Left(FailureValidacion(campos: {'id': 'El aviso necesita un identificador.'}));
    }
    if (notificacion.titulo.trim().isEmpty) {
      return const Left(FailureValidacion(campos: {'titulo': 'El aviso necesita un título.'}));
    }
    return _repositorio.registrar(notificacion, ahora: _ahora());
  }
}

final class MarcarNotificacionLeidaUseCase {
  const MarcarNotificacionLeidaUseCase(this._repositorio, {required this._ahora});

  final HistorialNotificacionesRepository _repositorio;
  final DateTime Function() _ahora;

  Future<Either<Failure, Unit>> call(String id) => _repositorio.marcarLeida(id, ahora: _ahora());
}

final class MarcarTodasLeidasUseCase {
  const MarcarTodasLeidasUseCase(this._repositorio, {required this._ahora});

  final HistorialNotificacionesRepository _repositorio;
  final DateTime Function() _ahora;

  Future<Either<Failure, Unit>> call() => _repositorio.marcarTodasLeidas(ahora: _ahora());
}

final class BorrarTodasLasNotificacionesUseCase {
  const BorrarTodasLasNotificacionesUseCase(this._repositorio);

  final HistorialNotificacionesRepository _repositorio;

  /// Borra lo recibido hasta [hasta] (el momento en que se abrió la confirmación) o todo si es
  /// `null`.
  Future<Either<Failure, int>> call({DateTime? hasta}) => _repositorio.borrarTodas(hasta: hasta);
}

final class PurgarHistorialNotificacionesUseCase {
  const PurgarHistorialNotificacionesUseCase(this._repositorio, {required this._ahora});

  final HistorialNotificacionesRepository _repositorio;
  final DateTime Function() _ahora;

  Future<Either<Failure, int>> call() => _repositorio.purgarVencidas(ahora: _ahora());
}

/// Si el lugar al que lleva un aviso todavía existe (24C·07). Lo implementa quien conoce ese lugar
/// (para una agenda, la tabla `agenda`).
abstract interface class ConsultorDestinosNotificacion {
  /// `true` si [destino] se puede abrir. Una agenda cancelada o borrada ya no se puede.
  Future<bool> existe(DestinoNotificacion destino);
}

/// Qué pasó al resolver el destino de un aviso tocado.
sealed class DestinoResuelto {
  const DestinoResuelto();
}

/// El aviso no lleva a ningún lado: solo se marca como leído.
final class SinDestino extends DestinoResuelto {
  const SinDestino();
}

/// El destino existe: se abre.
final class DestinoDisponible extends DestinoResuelto {
  const DestinoDisponible(this.destino);

  final DestinoNotificacion destino;
}

/// El destino ya no existe (24C·07): la lista queda abierta y se explica.
final class DestinoYaNoExiste extends DestinoResuelto {
  const DestinoYaNoExiste(this.destino);

  final DestinoNotificacion destino;
}

final class ResolverDestinoNotificacionUseCase {
  const ResolverDestinoNotificacionUseCase(this._consultor);

  final ConsultorDestinosNotificacion _consultor;

  /// Nunca lanza: si no se puede saber si el destino existe, `Left`.
  Future<Either<Failure, DestinoResuelto>> call(Notificacion notificacion) async {
    final destino = notificacion.destino;
    if (destino == null) return const Right(SinDestino());
    try {
      return Right(
        await _consultor.existe(destino) ? DestinoDisponible(destino) : DestinoYaNoExiste(destino),
      );
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }
}
