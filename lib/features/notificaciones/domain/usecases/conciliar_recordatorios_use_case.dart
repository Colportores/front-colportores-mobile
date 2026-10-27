import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../agenda/domain/entities/anticipacion_recordatorio.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/domain/services/texto_recordatorio.dart';
import '../entities/destino_notificacion.dart';
import '../entities/notificacion.dart';
import '../entities/tipo_notificacion.dart';
import '../repositories/conciliacion_recordatorios_repository.dart';
import '../repositories/preferencias_recordatorios_repository.dart';
import 'historial_notificaciones_use_cases.dart';

/// Guarda en el historial los recordatorios de visitas que ya sonaron (HU-NOT-005, decisión del
/// orquestador del 26/10 en #416). Un recordatorio no avisa a la app cuando suena —con la app
/// cerrada lo muestra el teléfono solo—, así que se **concilia** al abrir la app y al volver a ella:
/// cada agenda `PROGRAMADA` cuya hora de aviso cayó desde la última revisión se guarda con
/// [idDeRecordatorio] (idempotente) y con la hora del aviso como momento.
///
/// - No se guarda al programar: el centro mostraría un aviso que todavía no sonó.
/// - Una agenda cancelada, cumplida o borrada ya no está `PROGRAMADA`: no se guarda. Reprogramar
///   cambia la hora de aviso, y por eso el id.
/// - Con «Recordatorios de agenda» apagado no sonó nada: se avanza la marca sin guardar.
/// - La marca ([MarcaConciliacionRecordatorios]) sube hasta «ahora» solo si todo se guardó; así lo
///   que se borró con «Borrar todas» no vuelve, y lo que falló se reintenta la próxima vez. Dos
///   revisiones seguidas dejan lo mismo.
///
/// Nunca lanza. Devuelve cuántos avisos nuevos quedaron en el historial.
class ConciliarRecordatoriosUseCase {
  ConciliarRecordatoriosUseCase(
    this._agendas,
    this._preferencias,
    this._marca,
    this._registrar, {
    required this._ahora,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final AgendasConAvisoVencido _agendas;
  final PreferenciasRecordatoriosRepository _preferencias;
  final MarcaConciliacionRecordatorios _marca;
  final RegistrarNotificacionUseCase _registrar;
  final DateTime Function() _ahora;
  final AppLogger _log;

  /// Cuánto se guarda un aviso (HU-NOT-005, supuesto S27): lo más viejo se purgaría al guardarse.
  static const Duration retencion = Duration(days: 90);

  /// El id del aviso en el historial: `recordatorio-<agendaId>-<instante>`, con el instante del aviso
  /// en milisegundos UTC desde la época. El mismo aviso guardado dos veces queda una sola vez.
  static String idDeRecordatorio(String agendaId, DateTime avisoEn) =>
      'recordatorio-$agendaId-${avisoEn.toUtc().millisecondsSinceEpoch}';

  Future<Either<Failure, int>> call(String colportorId) async {
    try {
      final ahora = _ahora().toUtc();
      final marca = await _marca.leer();
      if (marca == null) {
        // Primera revisión de este teléfono: no hay nada anterior que contar.
        await _marca.guardar(ahora);
        return const Right(0);
      }
      // El reloj fue hacia atrás: no se revisa ni se mueve la marca.
      if (!ahora.isAfter(marca)) return const Right(0);

      final prefs = await _leerPreferencias();
      if (!prefs.activados) {
        // Apagados, no sonó ninguno: lo que pase de acá en adelante cuenta desde «ahora».
        await _marca.guardar(ahora);
        return const Right(0);
      }
      final minutos = AnticipacionRecordatorio.acotar(prefs.minutos);
      final piso = ahora.subtract(retencion);
      final desde = marca.isAfter(piso) ? marca : piso;

      final visitas = await _agendas.conAvisoEntre(
        colportorId: colportorId,
        desde: desde,
        hasta: ahora,
        anticipacionMinutos: minutos,
      );
      var nuevos = 0;
      var fallaron = 0;
      for (final visita in visitas) {
        final guardado = await _guardar(visita, minutos);
        guardado.fold((_) => fallaron++, (esNuevo) {
          if (esNuevo) nuevos++;
        });
      }
      // Si alguno falló, la marca se queda donde estaba: la próxima revisión lo vuelve a intentar.
      if (fallaron == 0) await _guardarMarca(ahora);
      return Right(nuevos);
    } on Object catch (e) {
      _log.error(
        LogModulo.push,
        'RECORDATORIOS_CONCILIAR',
        'no se pudieron guardar los recordatorios que sonaron',
        {'error': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }

  Future<Either<Failure, bool>> _guardar(RecordatorioDeVisita visita, int minutos) {
    final avisoEn = visita.fechaProgramada.subtract(Duration(minutes: minutos));
    return _registrar(
      Notificacion(
        id: idDeRecordatorio(visita.agendaId, avisoEn),
        tipo: TipoNotificacion.recordatorioVisita,
        titulo: TextoRecordatorio.titulo,
        detalle: TextoRecordatorio.cuerpo(
          tipo: visita.tipo,
          direccion: visita.direccion,
          fechaProgramada: visita.fechaProgramada,
        ),
        destino: DestinoAgenda(visita.agendaId),
        recibidaEn: avisoEn,
      ),
    );
  }

  /// Sin poder leer las preferencias se asume lo de siempre (prendidos, 30 minutos), igual que al
  /// programar el aviso.
  Future<({bool activados, int minutos})> _leerPreferencias() async {
    try {
      final p = await _preferencias.leer();
      return (activados: p.activados, minutos: p.anticipacionMinutos);
    } on Object catch (e) {
      _log.warn(
        LogModulo.push,
        'RECORDATORIOS_CONCILIAR_PREFERENCIAS',
        'no se pudieron leer las preferencias de los recordatorios; se usan las de siempre',
        {'error': e.runtimeType.toString()},
      );
      return (activados: true, minutos: AnticipacionRecordatorio.porDefecto);
    }
  }

  Future<void> _guardarMarca(DateTime ahora) async {
    try {
      await _marca.guardar(ahora);
    } on Object catch (e) {
      // Los avisos ya quedaron guardados; la próxima revisión los encuentra y no los duplica.
      _log.warn(
        LogModulo.push,
        'RECORDATORIOS_CONCILIAR_MARCA',
        'no se pudo guardar hasta dónde se revisaron los recordatorios',
        {'error': e.runtimeType.toString()},
      );
    }
  }
}
