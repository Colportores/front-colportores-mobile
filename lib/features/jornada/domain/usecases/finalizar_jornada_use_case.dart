import 'dart:async';

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
/// 2. Si el margen normal (ahora, o hasta 30 min hacia atrás) ya no llega al día del inicio (en
///    la zona del dispositivo) y no llegó [FinalizarJornadaParams.hora], devuelve
///    `Left(FailureJornadaDeDiaAnterior)`: cerrarla con la hora de hoy inventaría un `fin` —el
///    lunes olvidado y cerrado el martes a las 8:00 daría 14 h—, y la HU pide que nunca se
///    invente uno. Es la señal para que la pantalla ofrezca la corrección de la HU ("¿A qué hora
///    terminaste?"). Cerca de la medianoche sí vale elegir una hora del día del inicio dentro de
///    los 30 minutos (a las 00:10, las 23:50): ver el punto 4.
/// 2b. Si en cambio SÍ llegó [FinalizarJornadaParams.hora] para esa misma jornada de día
///    anterior, es la corrección: se acepta si está estrictamente después del inicio y no pasa
///    de las 23:59:59.999 (zona del dispositivo) de ese día — sin el margen de 30 min, porque es
///    una corrección, no un ajuste del momento. Fuera de ese rango, `Left(FailureHoraFueraDeRango)`.
/// 3. Si no, la cierra con `fin = now()` en UTC y truncado al milisegundo (la precisión de la DB
///    local, como en `IniciarJornadaUseCase`), `updated_at = now()`, y devuelve la jornada
///    cerrada: la pantalla arma el resumen con [Jornada.duracion].
/// 4. Si llega [FinalizarJornadaParams.hora], la jornada termina a esa hora, siempre que esté en
///    `[max(now − 30 min, inicio), now]` (HU-JOR-002, decisión de Cristian del 23/09 en #70: solo
///    hacia atrás, sin horas futuras). Fuera de ese rango devuelve `Left(FailureHoraFueraDeRango)`
///    con el rango explícito; nunca la ajusta en silencio.
/// 5. Con la jornada ya guardada, pide el backup automático ([DisparadorBackup], HU-SYNC-005)
///    **sin esperarlo**: la pantalla recibe el cierre enseguida. Un error del backup no deshace ni
///    oculta el cierre; va a `alFallarBackup` (el cableado lo manda al log), porque el colportor no
///    puede hacer nada con él.
///
/// El borde de `now − 30 min` se compara al minuto, igual que al iniciar (el selector ofrece
/// minutos enteros y el mensaje de error habla en minutos). El borde del inicio se compara
/// exacto: un fin anterior al inicio daría una duración negativa, y la tabla lo rechaza.
///
/// Resumen del día: por ahora solo horas. Casas visitadas, ventas y cobros (y los totales
/// `total_visitas`/`total_ventas`, que se denormalizan al cerrar) dependen de módulos que llegan
/// en los Sprints 8-11 (#74).
final class FinalizarJornadaUseCase implements UseCase<Jornada, FinalizarJornadaParams> {
  /// `alFallarBackup` recibe el error si pedir el backup falla. El dominio no loguea (no conoce
  /// `AppLogger`): el cableado de la feature lo conecta al log.
  FinalizarJornadaUseCase(
    this._repository,
    this._backup, {
    DateTime Function()? ahora,
    this._alFallarBackup,
  }) : _ahora = ahora ?? DateTime.now;

  /// Cuánto hacia atrás se puede marcar el fin (HU-JOR-002).
  static const margenHaciaAtras = Duration(minutes: 30);

  final JornadaRepository _repository;
  final DisparadorBackup _backup;
  final DateTime Function() _ahora;
  final void Function(Object error, StackTrace rastro)? _alFallarBackup;

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

      final hace30 = _alMinuto(ahora.subtract(margenHaciaAtras));
      final desde = abierta.inicio.isAfter(hace30) ? abierta.inicio : hace30;
      final elegida = params.hora;

      final DateTime fin;
      // Ni la hora más temprana del margen normal (30 min) cae en el día del inicio: es la
      // "jornada que quedó abierta" (HU-JOR-002). Se corrige con una hora elegida a mano entre
      // el inicio (excluido) y las 23:59 de ese día; sin hora elegida, se pide la corrección.
      if (_caeEnOtroDia(abierta.inicio, desde)) {
        if (elegida == null) {
          return Left(FailureJornadaDeDiaAnterior(inicio: abierta.inicio));
        }
        final hora = _alMilisegundo(elegida);
        final finDelDia = _finDelDiaLocal(abierta.inicio);
        if (!hora.isAfter(abierta.inicio) || hora.isAfter(finDelDia)) {
          return Left(FailureHoraFueraDeRango(desde: abierta.inicio, hasta: finDelDia));
        }
        fin = hora;
      } else if (elegida == null) {
        fin = ahora;
      } else {
        final hora = _alMilisegundo(elegida);
        if (hora.isBefore(desde) || hora.isAfter(ahora)) {
          return Left(FailureHoraFueraDeRango(desde: desde, hasta: ahora));
        }
        fin = hora;
      }

      // Una jornada no cruza la medianoche (HU-JOR-002: el fin tiene tope en las 23:59 del día del
      // inicio). A las 00:10, elegir las 23:50 de ayer vale; las 00:05 de hoy, no. La rama de
      // corrección de arriba ya valida este mismo tope contra `finDelDia`: este chequeo es un
      // resguardo para el camino normal (nunca debería dispararse desde la corrección).
      if (_caeEnOtroDia(abierta.inicio, fin)) {
        return Left(FailureJornadaDeDiaAnterior(inicio: abierta.inicio));
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
      if (resultado.isRight()) unawaited(_pedirBackup(colportorId));
      return resultado;
    });
  }

  /// El cierre ya quedó guardado: el backup se vuelve a pedir en su próxima ventana (HU-SYNC-005).
  /// Su falla no es un error de "finalizar jornada", pero tampoco se pierde: va al log.
  Future<void> _pedirBackup(String colportorId) async {
    try {
      await _backup.solicitar(colportorId);
    } on Object catch (e, rastro) {
      _alFallarBackup?.call(e, rastro);
    }
  }

  /// Si [instante] cae en un día calendario posterior al de [inicio], en la zona del dispositivo
  /// (el día del colportor, no el de UTC).
  static bool _caeEnOtroDia(DateTime inicio, DateTime instante) {
    final i = inicio.toLocal();
    final x = instante.toLocal();
    return DateTime(i.year, i.month, i.day).isBefore(DateTime(x.year, x.month, x.day));
  }

  /// 23:59:59.999 del día LOCAL de [inicio] (el día del colportor), como instante UTC — el tope
  /// de la corrección de "jornada que quedó abierta" (HU-JOR-002).
  static DateTime _finDelDiaLocal(DateTime inicio) {
    final local = inicio.toLocal();
    return DateTime(local.year, local.month, local.day, 23, 59, 59, 999).toUtc();
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
