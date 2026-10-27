import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/presentation/providers/agenda_providers.dart';
import '../../../agenda/presentation/providers/recordatorios_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/datasources/agendas_para_recordar_drift.dart';
import '../../data/repositories/preferencias_recordatorios_repository_impl.dart';
import '../../domain/entities/preferencias_recordatorios.dart';
import '../../domain/repositories/preferencias_recordatorios_repository.dart';
import '../../domain/usecases/cambiar_preferencias_recordatorios_use_case.dart';

// Cableado de las preferencias de los recordatorios (HU-NOT-004, vista 24 grupo B).

/// Lo que el teléfono recuerda de las preferencias. En el equipo, `main.dart` lo sobreescribe con el
/// almacén seguro (y es también lo que lee `RecordatoriosLocales`); por defecto (tests), en memoria.
final preferenciasRecordatoriosRepositoryProvider = Provider<PreferenciasRecordatoriosRepository>(
  (ref) => PreferenciasRecordatoriosRepositoryEnMemoria(),
);

/// Las agendas pendientes de la DB local. Sin DB abierta no hay agendas que leer: pedirlas lanza, y
/// quien lo usa lo traduce a un error.
final agendasParaRecordarProvider = Provider<AgendasParaRecordar>((ref) {
  final db = ref.watch(dbLocalProvider);
  return db == null ? const _SinDbAbierta() : AgendasParaRecordarDrift(db);
});

final class _SinDbAbierta implements AgendasParaRecordar {
  const _SinDbAbierta();

  @override
  Future<List<RecordatorioDeVisita>> pendientes({
    required String colportorId,
    required DateTime desde,
  }) async => throw StateError('La base de datos local no está abierta');
}

final reprogramarRecordatoriosUseCaseProvider = Provider<ReprogramarRecordatoriosUseCase>(
  (ref) => ReprogramarRecordatoriosUseCase(
    ref.watch(agendasParaRecordarProvider),
    ref.watch(recordatoriosProvider),
    ahora: ref.watch(relojVisitaProvider),
  ),
);

final cambiarPreferenciasRecordatoriosUseCaseProvider =
    Provider<CambiarPreferenciasRecordatoriosUseCase>(
      (ref) => CambiarPreferenciasRecordatoriosUseCase(
        ref.watch(preferenciasRecordatoriosRepositoryProvider),
        ref.watch(reprogramarRecordatoriosUseCaseProvider),
      ),
    );

/// Sin reintento automático: si no se pueden leer las preferencias, la pantalla ofrece «Reintentar».
Duration? _sinReintentos(int intento, Object error) => null;

/// Lo que ve la pantalla de preferencias de los recordatorios.
final class EstadoPreferenciasRecordatorios extends Equatable {
  const EstadoPreferenciasRecordatorios({required this.preferencias, this.falla});

  /// Lo que se muestra: el cambio se ve apenas se pide, aunque todavía no esté guardado (si no se
  /// puede guardar, vuelve a como estaba).
  final PreferenciasRecordatorios preferencias;

  /// El último cambio que no se pudo guardar (24B·06), con lo último que se quiso dejar (juntando todo lo
  /// pedido mientras se guardaba), para «Reintentar».
  final PreferenciasRecordatorios? falla;

  @override
  List<Object?> get props => [preferencias, falla];
}

/// Las preferencias de los recordatorios de agenda (HU-NOT-004): leerlas, cambiarlas y reprogramar los
/// recordatorios ya agendados al guardar.
///
/// - Cada cambio se ve enseguida (el interruptor se mueve) y se guarda en segundo plano. Si no se
///   puede guardar o reprogramar, todo vuelve a como estaba y [EstadoPreferenciasRecordatorios.falla]
///   dice qué se quiso (24B·06).
/// - **Dos cambios seguidos** no se pisan ni se pierden: se guardan de a uno, en orden, y si llega
///   uno nuevo mientras otro se guarda, se guarda también lo último. Quien pidió el cambio recibe la
///   cantidad de recordatorios reprogramados de la última vez.
/// - Vive mientras la pantalla lo mira (`autoDispose`).
final preferenciasRecordatoriosProvider =
    AsyncNotifierProvider.autoDispose<
      PreferenciasRecordatoriosNotifier,
      EstadoPreferenciasRecordatorios
    >(PreferenciasRecordatoriosNotifier.new, retry: _sinReintentos);

class PreferenciasRecordatoriosNotifier extends AsyncNotifier<EstadoPreferenciasRecordatorios> {
  /// Lo que está guardado de verdad, y lo que la persona quiere dejar.
  late PreferenciasRecordatorios _guardadas;
  late PreferenciasRecordatorios _deseadas;

  /// El guardado en curso (si lo hay): un cambio nuevo lo comparte.
  Future<int?>? _enCurso;

  @override
  Future<EstadoPreferenciasRecordatorios> build() async {
    final leidas = await ref.read(preferenciasRecordatoriosRepositoryProvider).leer();
    _guardadas = leidas;
    _deseadas = leidas;
    return EstadoPreferenciasRecordatorios(preferencias: leidas);
  }

  /// Prende o apaga «Recordatorios de agenda». Devuelve cuántos recordatorios quedaron programados, o
  /// `null` si no se pudo guardar (el interruptor vuelve a como estaba).
  Future<int?> cambiarActivados({required bool activados}) =>
      _pedir((actuales) => actuales.copyWith(activados: activados));

  /// Cambia la anticipación a [minutos] (se acota a 5..120). Devuelve a cuántos recordatorios les
  /// tocó la hora nueva, o `null` si no se pudo guardar.
  Future<int?> cambiarAnticipacion(int minutos) =>
      _pedir((actuales) => actuales.copyWith(anticipacionMinutos: minutos));

  /// «Reintentar» del error al guardar (24B·06): vuelve a pedir lo que no se pudo.
  Future<int?> reintentar() {
    final intento = state.value?.falla;
    if (intento == null) return Future.value();
    return _pedir((_) => intento);
  }

  Future<int?> _pedir(PreferenciasRecordatorios Function(PreferenciasRecordatorios) cambio) {
    final actual = state.value;
    if (actual == null || !ref.mounted) return Future.value();
    _deseadas = cambio(_deseadas);
    state = AsyncData(EstadoPreferenciasRecordatorios(preferencias: _deseadas));
    return _enCurso ??= _guardar();
  }

  /// Quién tiene las agendas que se reprograman: el de la sesión, o `null` sin sesión.
  Future<String?> _colportor() async {
    try {
      return (await ref.read(sesionProvider.future))?.usuarioId;
    } on Object {
      return null;
    }
  }

  /// Guarda de a un cambio hasta que lo guardado sea lo deseado. Revisa «¿queda algo?» y suelta
  /// [_enCurso] en el mismo tramo síncrono, así un cambio que llega justo al final no se pierde.
  Future<int?> _guardar() async {
    // Que `_enCurso` ya esté asignado cuando sigue el cuerpo.
    await Future<void>.value();
    // Si la persona sale de la pantalla con un cambio sin guardar, se termina de guardar igual.
    final vivo = ref.keepAlive();
    int? reprogramados;
    try {
      while (ref.mounted && _deseadas != _guardadas) {
        final objetivo = _deseadas;
        final colportorId = await _colportor();
        if (!ref.mounted) return null;
        final resultado = await ref
            .read(cambiarPreferenciasRecordatoriosUseCaseProvider)
            .call(colportorId: colportorId, previas: _guardadas, nuevas: objetivo);
        if (!ref.mounted) return null;
        var fallo = false;
        resultado.fold(
          (_) {
            fallo = true;
            AppLogger.instance.warn(
              LogModulo.push,
              'PREF_RECORDATORIOS',
              'no se pudo guardar el cambio de las preferencias de los recordatorios',
            );
            // «Reintentar» repite lo último que se pidió (con todos los cambios que se juntaron
            // mientras tanto), no solo el que estaba guardándose.
            final pedido = _deseadas;
            _deseadas = _guardadas;
            state = AsyncData(
              EstadoPreferenciasRecordatorios(preferencias: _guardadas, falla: pedido),
            );
          },
          (cambio) {
            _guardadas = objetivo;
            reprogramados = cambio.reprogramados;
          },
        );
        if (fallo) return null;
      }
      return reprogramados;
    } finally {
      _enCurso = null;
      vivo.close();
    }
  }
}
