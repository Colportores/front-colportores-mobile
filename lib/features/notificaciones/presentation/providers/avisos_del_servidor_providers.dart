import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/datasources/preferencias_de_avisos_local_data_source_drift.dart';
import '../../data/repositories/avisos_del_servidor_repository_impl.dart';
import '../../domain/entities/avisos_del_servidor.dart';
import '../../domain/repositories/avisos_del_servidor_repository.dart';
import 'preferencias_recordatorios_providers.dart';

// Cableado de los avisos del servidor (HU-NOT-004, vista 24 grupo B, sección AVISOS; #516).

/// Dónde viven los avisos que manda el servidor: `preferencia_de_avisos`, la fila de la persona en la base del
/// teléfono, que baja y sube con la sincronización (backend-supabase 0207, «Avisos s/red»): cambiarlos no
/// necesita conexión. Sin base abierta (tests, demo) un repositorio en memoria que recuerda lo que se le dice
/// mientras la app está abierta.
final avisosDelServidorRepositoryProvider = Provider<AvisosDelServidorRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return AvisosDelServidorEnMemoria();
  return AvisosDelServidorLocal(
    PreferenciasDeAvisosLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      // Al momento de leer o guardar, no al armar el repositorio: la sesión puede cambiar sin rearmarlo.
      usuarioId: () => ref.read(sesionProvider).value?.usuarioId,
    ),
  );
});

/// Sin reintento automático: si no se pueden leer los avisos, la pantalla ofrece «Reintentar».
Duration? _sinReintentos(int intento, Object error) => null;

/// Por qué no se pudo guardar el último cambio.
enum FalloDeAvisos {
  /// La base del teléfono no pudo guardarlo (no hay falla de conexión: se guarda en el teléfono).
  servidor,
}

/// Lo que ve la sección AVISOS.
final class EstadoAvisosDelServidor extends Equatable {
  const EstadoAvisosDelServidor({required this.avisos, this.falla, this.fallo});

  /// Lo que se muestra: el cambio se ve apenas se pide, aunque todavía no esté guardado (si no se
  /// puede guardar, vuelve a como estaba).
  final AvisosDelServidor avisos;

  /// Lo último que se quiso dejar y no se pudo guardar (24B·06), para «Reintentar».
  final AvisosDelServidor? falla;

  /// Por qué no se pudo; `null` si no hubo falla.
  final FalloDeAvisos? fallo;

  @override
  List<Object?> get props => [avisos, falla, fallo];
}

/// Los avisos del servidor de la colportora: leerlos, cambiarlos y guardarlos.
///
/// - Cada cambio se ve enseguida (el interruptor se mueve) y se guarda en segundo plano. Si no se
///   puede guardar, todo vuelve a como estaba y [EstadoAvisosDelServidor.falla] dice qué se quiso
///   (24B·06).
/// - **Dos cambios seguidos** no se pisan ni se pierden: se guardan de a uno, en orden, y si llega uno
///   nuevo mientras otro se guarda, se guarda también lo último (el servidor recibe siempre el objeto
///   entero).
/// - Nunca se guarda sin haber leído antes: sin lo que hay en el servidor, reescribir el objeto
///   borraría lo que no se ve.
/// - «Recordatorios de agenda» vive en el teléfono (funciona sin conexión); el servidor guarda una
///   copia para no mandar «Mañana tenés visitas» con los recordatorios apagados. Esa copia se
///   sincroniza en silencio: al abrir la pantalla, si difiere, y al cambiar el interruptor. Si no hay
///   conexión no se le dice nada a la colportora (lo suyo ya quedó guardado en el teléfono) y se
///   vuelve a intentar la próxima vez.
/// - Vive mientras la pantalla lo mira (`autoDispose`).
final avisosDelServidorProvider =
    AsyncNotifierProvider.autoDispose<AvisosDelServidorNotifier, EstadoAvisosDelServidor>(
      AvisosDelServidorNotifier.new,
      retry: _sinReintentos,
    );

class AvisosDelServidorNotifier extends AsyncNotifier<EstadoAvisosDelServidor> {
  /// Lo que está guardado de verdad en el servidor, y lo que la persona quiere dejar.
  late AvisosDelServidor _guardados;
  late AvisosDelServidor _deseados;

  /// El guardado en curso (si lo hay): un cambio nuevo lo comparte.
  Future<bool>? _enCurso;

  @override
  Future<EstadoAvisosDelServidor> build() async {
    final leidos = await ref.read(avisosDelServidorRepositoryProvider).leer();
    _guardados = leidos;
    _deseados = leidos;
    // La copia del servidor del interruptor de agenda: si el teléfono dice otra cosa, el teléfono manda.
    unawaited(_alinearAgendaConElTelefono(leidos));
    return EstadoAvisosDelServidor(avisos: leidos);
  }

  Future<void> _alinearAgendaConElTelefono(AvisosDelServidor leidos) async {
    try {
      final local = await ref.read(preferenciasRecordatoriosRepositoryProvider).leer();
      if (!ref.mounted || local.activados == leidos.agenda) return;
      await sincronizarAgenda(activados: local.activados);
    } on Object {
      // Sin leer el teléfono no hay nada que alinear: se verá la próxima vez.
    }
  }

  Future<bool> cambiarPedidos({required bool activado}) =>
      _pedir((a) => a.copyWith(pedidos: activado));

  Future<bool> cambiarTickets({required bool activado}) =>
      _pedir((a) => a.copyWith(tickets: activado));

  Future<bool> cambiarCuotas({required bool activado}) =>
      _pedir((a) => a.copyWith(cuotas: activado));

  Future<bool> cambiarAsignaciones({required bool activado}) =>
      _pedir((a) => a.copyWith(asignaciones: activado));

  Future<bool> cambiarHoraCuota(HoraDelAviso hora) => _pedir((a) => a.copyWith(horaCuota: hora));

  Future<bool> cambiarHoraAgenda(HoraDelAviso hora) => _pedir((a) => a.copyWith(horaAgenda: hora));

  /// Prende o apaga «Recordatorios de agenda» en el teléfono y le dice al servidor cómo quedó.
  ///
  /// La copia del servidor se corrige desde acá y no desde la pantalla: si la persona sale mientras el
  /// teléfono todavía guarda, el notificador se mantiene vivo hasta terminar y el servidor no queda con
  /// una copia vieja (y mandando «Mañana tenés visitas» con los recordatorios apagados). En silencio:
  /// no hay aviso nuevo, porque la persona no tiene nada que hacer. Sin haber leído el servidor no
  /// hay copia que corregir: al leerlo, [build] la alinea.
  Future<void> cambiarRecordatoriosDeAgenda({required bool activados}) async {
    final vivo = ref.keepAlive();
    try {
      // Se arranca antes de cualquier espera: así el guardado ya empezó mientras la pantalla estaba.
      final guardado = ref
          .read(preferenciasRecordatoriosProvider.notifier)
          .cambiarActivados(activados: activados);
      await guardado;
      if (state.value == null) return;
      // Lo que quedó de verdad en el teléfono (otro cambio pudo volver a prender mientras tanto, o el
      // guardado pudo fallar): el teléfono manda.
      final local = await ref.read(preferenciasRecordatoriosRepositoryProvider).leer();
      await sincronizarAgenda(activados: local.activados);
    } on Object {
      // Sin leer el teléfono no hay nada que alinear: se verá la próxima vez que se abra la pantalla.
    } finally {
      vivo.close();
    }
  }

  /// Le dice al servidor cómo quedó «Recordatorios de agenda» en el teléfono. En silencio: si no se
  /// puede, queda para la próxima vez (ver el comentario de la clase). Sin haber leído el servidor no
  /// hace nada.
  Future<bool> sincronizarAgenda({required bool activados}) =>
      _pedir((a) => a.copyWith(agenda: activados));

  /// «Reintentar» del error al guardar (24B·06): vuelve a pedir lo que no se pudo.
  Future<bool> reintentar() {
    final intento = state.value?.falla;
    if (intento == null) return Future.value(false);
    return _pedir((_) => intento);
  }

  Future<bool> _pedir(AvisosDelServidor Function(AvisosDelServidor) cambio) {
    final actual = state.value;
    if (actual == null || !ref.mounted) return Future.value(false);
    _deseados = cambio(_deseados);
    state = AsyncData(EstadoAvisosDelServidor(avisos: _deseados));
    return _enCurso ??= _guardar();
  }

  /// Guarda de a un cambio hasta que lo guardado sea lo deseado. Revisa «¿queda algo?» y suelta
  /// [_enCurso] en el mismo tramo síncrono, así un cambio que llega justo al final no se pierde.
  Future<bool> _guardar() async {
    // Que `_enCurso` ya esté asignado cuando sigue el cuerpo.
    await Future<void>.value();
    // Si la persona sale de la pantalla con un cambio sin guardar, se termina de guardar igual.
    final vivo = ref.keepAlive();
    var guardo = false;
    try {
      while (ref.mounted && _deseados != _guardados) {
        final objetivo = _deseados;
        final repositorio = ref.read(avisosDelServidorRepositoryProvider);
        FalloDeAvisos? fallo;
        try {
          await repositorio.guardar(objetivo);
        } on Object catch (e) {
          fallo = FalloDeAvisos.servidor;
          AppLogger.instance.warn(
            LogModulo.push,
            'AVISOS_GUARDAR',
            'no se pudo guardar el cambio de los avisos',
            {'error': e.runtimeType.toString()},
          );
        }
        if (!ref.mounted) return false;
        if (fallo == null) {
          _guardados = objetivo;
          guardo = true;
          continue;
        }
        // «Reintentar» repite lo último que se pidió (con todos los cambios que se juntaron mientras
        // tanto), no solo el que estaba guardándose.
        final pedido = _deseados;
        _deseados = _guardados;
        // Si lo único que no se guardó es la copia de «Recordatorios de agenda», no hay nada que decir.
        final soloLaCopiaDeAgenda = pedido == _guardados.copyWith(agenda: pedido.agenda);
        state = AsyncData(
          soloLaCopiaDeAgenda
              ? EstadoAvisosDelServidor(avisos: _guardados)
              : EstadoAvisosDelServidor(avisos: _guardados, falla: pedido, fallo: fallo),
        );
        return false;
      }
      return guardo;
    } finally {
      _enCurso = null;
      vivo.close();
    }
  }
}
