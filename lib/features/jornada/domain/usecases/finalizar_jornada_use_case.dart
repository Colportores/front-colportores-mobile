import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/jornada.dart';
import '../repositories/jornada_repository.dart';
import '../services/disparador_backup.dart';

/// Parámetros de [FinalizarJornadaUseCase].
final class FinalizarJornadaParams extends Equatable {
  const FinalizarJornadaParams({required this.colportorId, this.hora});

  /// UUID del usuario con la sesión iniciada; la capa de presentación lo toma de la sesión.
  final String colportorId;

  /// Hora de fin elegida a mano, hasta 30 minutos hacia atrás y no antes del inicio. `null` =
  /// ahora (el toque).
  final DateTime? hora;

  @override
  List<Object?> get props => [colportorId, hora];
}

/// HU-JOR-002 — Finalizar jornada de trabajo.
///
/// 1. Si el colportor no tiene una jornada en curso devuelve `Left(FailureSinJornadaActiva)`.
/// 2. Si no, la cierra con `fin = now()` en UTC y truncado al milisegundo (la precisión de la DB
///    local, como en `IniciarJornadaUseCase`), `updated_at = now()`, y devuelve la jornada
///    cerrada: la pantalla arma el resumen con [Jornada.duracion].
/// 3. Si llega [FinalizarJornadaParams.hora], la jornada termina a esa hora, siempre que esté en
///    `[max(now − 30 min, inicio), now]` (HU-JOR-002, decisión de Cristian del 23/09 en #70: solo
///    hacia atrás, sin horas futuras). Fuera de ese rango devuelve `Left(FailureHoraFueraDeRango)`
///    con el rango explícito; nunca la ajusta en silencio.
/// 4. Con la jornada ya guardada, pide el backup automático ([DisparadorBackup], HU-SYNC-005). Un
///    error del backup no deshace ni oculta el cierre.
///
/// El borde de `now − 30 min` se compara al minuto, igual que al iniciar (el selector ofrece
/// minutos enteros y el mensaje de error habla en minutos). El borde del inicio se compara
/// exacto: un fin anterior al inicio daría una duración negativa, y la tabla lo rechaza.
///
/// Resumen del día: por ahora solo horas. Casas visitadas, ventas y cobros (y los totales
/// `total_visitas`/`total_ventas`, que se denormalizan al cerrar) dependen de módulos que llegan
/// en los Sprints 8-11 (#74).
final class FinalizarJornadaUseCase implements UseCase<Jornada, FinalizarJornadaParams> {
  FinalizarJornadaUseCase(this._repository, this._backup, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  /// Cuánto hacia atrás se puede marcar el fin (HU-JOR-002).
  static const margenHaciaAtras = Duration(minutes: 30);

  final JornadaRepository _repository;
  final DisparadorBackup _backup;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Jornada>> call(FinalizarJornadaParams params) async {
    // La hora del toque, no la de después de consultar la DB.
    final ahora = _alMilisegundo(_ahora());
    final colportorId = params.colportorId.trim();

    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para finalizar la jornada'}),
      );
    }

    final activa = await _repository.obtenerActiva(colportorId);
    return activa.fold<Future<Either<Failure, Jornada>>>((failure) async => Left(failure), (
      abierta,
    ) async {
      if (abierta == null) return const Left(FailureSinJornadaActiva());

      final DateTime fin;
      final elegida = params.hora;
      if (elegida == null) {
        fin = ahora;
      } else {
        final hace30 = _alMinuto(ahora.subtract(margenHaciaAtras));
        final desde = abierta.inicio.isAfter(hace30) ? abierta.inicio : hace30;
        final hora = _alMilisegundo(elegida);
        if (hora.isBefore(desde) || hora.isAfter(ahora)) {
          return Left(FailureHoraFueraDeRango(desde: desde, hasta: ahora));
        }
        fin = hora;
      }

      if (fin.isBefore(abierta.inicio)) {
        // Solo pasa si el reloj del teléfono quedó antes del inicio (lo atrasaron a mano).
        return const Left(
          FailureValidacion(
            campos: {'hora': 'La hora del teléfono es anterior al inicio de la jornada'},
            mensaje:
                'La hora del teléfono es anterior al inicio de tu jornada. Revisá la fecha y '
                'hora del teléfono y volvé a intentar.',
          ),
        );
      }

      final resultado = await _repository.finalizar(
        abierta.finalizada(fin: fin, actualizadaEn: ahora),
      );
      if (resultado.isRight()) await _pedirBackup(colportorId);
      return resultado;
    });
  }

  Future<void> _pedirBackup(String colportorId) async {
    try {
      await _backup.solicitar(colportorId);
    } on Object {
      // El cierre ya quedó guardado; el backup se vuelve a pedir en su próxima ventana
      // (HU-SYNC-005). No se informa como error de "finalizar jornada".
    }
  }

  /// [fecha] en UTC y sin lo que haya por debajo del milisegundo (ver `IniciarJornadaUseCase`).
  static DateTime _alMilisegundo(DateTime fecha) =>
      DateTime.fromMillisecondsSinceEpoch(fecha.millisecondsSinceEpoch, isUtc: true);

  /// [fecha] en UTC, al principio de su minuto.
  static DateTime _alMinuto(DateTime fecha) {
    final utc = fecha.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }
}
