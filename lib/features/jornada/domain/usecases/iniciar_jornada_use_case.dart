import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/jornada.dart';
import '../repositories/jornada_repository.dart';

/// Parámetros de [IniciarJornadaUseCase].
final class IniciarJornadaParams extends Equatable {
  const IniciarJornadaParams({required this.colportorId, this.hora});

  /// UUID del usuario con la sesión iniciada; la capa de presentación lo toma de la sesión.
  final String colportorId;

  /// Hora de inicio elegida a mano, hasta 30 minutos hacia atrás. `null` = ahora (el toque).
  final DateTime? hora;

  @override
  List<Object?> get props => [colportorId, hora];
}

/// HU-JOR-001 — Iniciar jornada de trabajo.
///
/// 1. Si el colportor ya tiene una jornada en curso devuelve `Left(FailureJornadaActiva)` ("solo
///    una jornada activa a la vez"). El repositorio vuelve a garantizarlo al escribir, para el
///    caso de dos inicios casi simultáneos (ver [JornadaRepository.crear]).
/// 2. Si no, crea la jornada con `inicio = now()` en UTC y truncado al milisegundo (la precisión
///    de la DB local, ver [_alMilisegundo]), `id` UUID v7 generado localmente
///    (esquema-datos.md §Principios 2) y la auditoría con el colportor como `created_by`.
/// 3. Si llega [IniciarJornadaParams.hora], la jornada empieza a esa hora, siempre que esté entre
///    `now − 30 min` y `now` (HU-JOR-001: "editable hasta 30 minutos hacia atrás", sin horas
///    futuras). Fuera de ese rango devuelve `Left(FailureHoraFueraDeRango)` con el rango
///    explícito; nunca la ajusta en silencio (decisión de Cristian del 23/09 en #70).
///
/// El borde de abajo se compara al minuto (`14:05:00` vale aunque sean las `14:35:20`): el
/// selector de la pantalla ofrece minutos enteros y el mensaje de error habla en minutos
/// ("entre las 14:05 y las 14:35"), así que el rango que se valida es el mismo que se muestra.
///
/// El `id` y el reloj se inyectan: el dominio no depende del paquete `uuid` y los tests fijan la
/// hora sin esperar.
final class IniciarJornadaUseCase implements UseCase<Jornada, IniciarJornadaParams> {
  /// [_generarId] se pasa como `generarId:` (parámetro nombrado privado, Dart ≥ 3.10).
  IniciarJornadaUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  /// Cuánto hacia atrás se puede marcar el inicio (HU-JOR-001).
  static const margenHaciaAtras = Duration(minutes: 30);

  final JornadaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Jornada>> call(IniciarJornadaParams params) async {
    // La hora del toque, no la de después de consultar la DB.
    final ahora = _alMilisegundo(_ahora());
    final colportorId = params.colportorId.trim();

    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para iniciar la jornada'}),
      );
    }

    final elegida = params.hora;
    final DateTime inicio;
    if (elegida == null) {
      inicio = ahora;
    } else {
      final desde = _alMinuto(ahora.subtract(margenHaciaAtras));
      final hora = _alMilisegundo(elegida);
      if (hora.isBefore(desde) || hora.isAfter(ahora)) {
        return Left(FailureHoraFueraDeRango(desde: desde, hasta: ahora));
      }
      inicio = hora;
    }

    final activa = await _repository.obtenerActiva(colportorId);
    return activa.fold<Future<Either<Failure, Jornada>>>((failure) async => Left(failure), (
      abierta,
    ) async {
      if (abierta != null) return const Left(FailureJornadaActiva());

      final jornada = Jornada(
        id: _generarId(),
        colportorId: colportorId,
        inicio: inicio,
        auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: colportorId),
      );
      return _repository.crear(jornada);
    });
  }

  /// [fecha] en UTC y sin lo que haya por debajo del milisegundo.
  ///
  /// La DB local guarda las fechas en epoch ms (08-conceptos-transversales §8.11; el
  /// `FechaUtcConverter` descarta los microsegundos al guardar). Sin truncar acá, la jornada que
  /// devuelve el caso de uso tendría microsegundos y la que se relee de la DB no —`==` daría
  /// `false` para la misma fila—, y `JornadaModel.toJson()` mandaría al cloud `.123999Z` mientras
  /// el dispositivo tiene `.123`.
  ///
  /// Se aplica en el origen de la fecha, no en los constructores de `Jornada`/`Auditoria` (que
  /// ya normalizan a UTC): ver el comentario de la revisión en #70.
  static DateTime _alMilisegundo(DateTime fecha) =>
      DateTime.fromMillisecondsSinceEpoch(fecha.millisecondsSinceEpoch, isUtc: true);

  /// [fecha] en UTC, al principio de su minuto.
  static DateTime _alMinuto(DateTime fecha) {
    final utc = fecha.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }
}
