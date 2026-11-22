import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../agenda/domain/services/recordatorios.dart';
import '../entities/preferencias_recordatorios.dart';
import '../repositories/preferencias_recordatorios_repository.dart';

/// Vuelve a programar el recordatorio de cada visita agendada pendiente según las preferencias de
/// ahora (HU-NOT-004): con los recordatorios apagados los cancela, con la anticipación nueva los
/// pasa a su hora nueva. Devuelve cuántos quedaron programados (los que el teléfono va a mostrar a su
/// hora: no cuenta los que ya no tienen aviso porque la visita es en menos que la anticipación).
///
/// Nunca lanza: si no se pueden leer las agendas, es un `FailureInesperado`. Un recordatorio puntual
/// que el teléfono no acepta no frena a los demás: se loguea en `RecordatoriosLocales` y no suma.
class ReprogramarRecordatoriosUseCase {
  ReprogramarRecordatoriosUseCase(
    this._agendas,
    this._recordatorios, {
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final AgendasParaRecordar _agendas;
  final Recordatorios _recordatorios;
  final DateTime Function() _ahora;
  final AppLogger _log;

  Future<Either<Failure, int>> call(String colportorId) async {
    try {
      final pendientes = await _agendas.pendientes(colportorId: colportorId, desde: _ahora());
      var programados = 0;
      for (final visita in pendientes) {
        final resultado = await _recordatorios.programar(visita);
        if (resultado == ResultadoRecordatorio.programado ||
            resultado == ResultadoRecordatorio.sinPermiso) {
          programados++;
        }
      }
      return Right(programados);
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'RECORDATORIOS_REPROGRAMAR',
        'no se pudieron reprogramar los recordatorios',
        {'error': e.runtimeType.toString()},
        e,
      );
      return Left(FailureInesperado(causa: e));
    }
  }
}

/// Lo que dejó un cambio guardado: las preferencias como quedaron y a cuántos recordatorios les tocó
/// la hora nueva.
typedef CambioGuardado = ({PreferenciasRecordatorios preferencias, int reprogramados});

/// Guarda un cambio en las preferencias de los recordatorios y reprograma los ya agendados
/// (HU-NOT-004, 24B·02, 24B·03 y 24B·06).
///
/// **Todo o nada**: si no se puede guardar, o no se pueden reprogramar los recordatorios, las
/// preferencias vuelven a como estaban (la pantalla dice «El interruptor volvió a como estaba») y se
/// intenta dejar los recordatorios como antes. Solo escribe lo que cambió.
///
/// Antes de escribir nada llama a [_antesDeCambiar]: el historial de avisos (HU-NOT-005) guarda lo que
/// sonó con las preferencias de antes. Si eso falla, el cambio sigue.
class CambiarPreferenciasRecordatoriosUseCase {
  CambiarPreferenciasRecordatoriosUseCase(
    this._repositorio,
    this._reprogramar, {
    this._antesDeCambiar,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final PreferenciasRecordatoriosRepository _repositorio;
  final ReprogramarRecordatoriosUseCase _reprogramar;
  final Future<void> Function(String colportorId)? _antesDeCambiar;
  final AppLogger _log;

  /// Pasa de [previas] a [nuevas]. [colportorId] es quien tiene las agendas; sin él no hay nada que
  /// reprogramar y solo se guarda.
  Future<Either<Failure, CambioGuardado>> call({
    required String? colportorId,
    required PreferenciasRecordatorios previas,
    required PreferenciasRecordatorios nuevas,
  }) async {
    final escritas = <Future<void> Function()>[];
    if (colportorId != null) {
      try {
        await _antesDeCambiar?.call(colportorId);
      } on Object catch (e) {
        _log.warn(
          LogModulo.push,
          'PREF_RECORDATORIOS_ANTES',
          'no se pudo guardar lo que sonó antes de cambiar las preferencias',
          {'error': e.runtimeType.toString()},
        );
      }
    }
    try {
      if (nuevas.activados != previas.activados) {
        await _repositorio.guardarActivados(activados: nuevas.activados);
        escritas.add(() => _repositorio.guardarActivados(activados: previas.activados));
      }
      if (nuevas.anticipacionMinutos != previas.anticipacionMinutos) {
        await _repositorio.guardarAnticipacion(nuevas.anticipacionMinutos);
        escritas.add(() => _repositorio.guardarAnticipacion(previas.anticipacionMinutos));
      }
    } on Object catch (e) {
      _log.warn(
        LogModulo.push,
        'PREF_RECORDATORIOS_GUARDAR',
        'no se pudieron guardar las preferencias de los recordatorios',
        {'error': e.runtimeType.toString()},
      );
      await _deshacer(escritas);
      return Left(FailureInesperado(causa: e));
    }

    if (colportorId == null) return Right((preferencias: nuevas, reprogramados: 0));
    final reprogramados = await _reprogramar(colportorId);
    return reprogramados.fold((falla) async {
      await _deshacer(escritas);
      // Los recordatorios que alcanzaron a cambiar vuelven a su hora de antes.
      await _reprogramar(colportorId);
      return Left<Failure, CambioGuardado>(falla);
    }, (cantidad) async => Right((preferencias: nuevas, reprogramados: cantidad)));
  }

  Future<void> _deshacer(List<Future<void> Function()> escritas) async {
    for (final deshacer in escritas.reversed) {
      try {
        await deshacer();
      } on Object catch (e) {
        _log.warn(
          LogModulo.push,
          'PREF_RECORDATORIOS_DESHACER',
          'no se pudo volver a las preferencias de antes',
          {'error': e.runtimeType.toString()},
        );
      }
    }
  }
}
