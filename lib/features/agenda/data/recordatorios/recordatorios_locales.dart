import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/permiso_notificaciones_sistema.dart';
import '../../domain/entities/anticipacion_recordatorio.dart';
import '../../domain/entities/recordatorio_de_visita.dart';
import '../../domain/services/recordatorios.dart';
import '../../domain/services/texto_recordatorio.dart';
import 'motor_de_avisos.dart';

/// [Recordatorios] y [ToquesDeRecordatorios] sobre el [MotorDeAvisos] del teléfono (HU-NOT-002).
///
/// - El aviso suena [AnticipacionRecordatorio] minutos antes de la visita (`notif_anticipacion_minutos`,
///   30 por defecto, entre 5 y 120). Su texto no lleva el nombre del cliente ([TextoRecordatorio]).
/// - El id del aviso sale del `agenda.id` ([idDeAviso]): programar de nuevo lo reemplaza y cancelar lo
///   borra, sin guardar nada aparte.
/// - Las operaciones se hacen **en el orden en que se piden** (cola): reprogramar dos veces seguidas
///   deja la última hora, y un «cancelar» pedido antes de que termine el «programar» lo deja
///   cancelado. Ninguna lanza; las fallas van al log, sin direcciones ni nombres.
/// - Con las notificaciones apagadas en el teléfono igual se programa: suenan si la persona las
///   activa después. [programar] avisa con [ResultadoRecordatorio.sinPermiso].
final class RecordatoriosLocales implements Recordatorios, ToquesDeRecordatorios {
  RecordatoriosLocales({
    required this._motor,
    required this._permiso,
    this._anticipacion = const AnticipacionFija(),
    this._activados = const RecordatoriosSiempreActivados(),
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final MotorDeAvisos _motor;
  final PermisoNotificacionesSistema _permiso;
  final AnticipacionRecordatorios _anticipacion;
  final RecordatoriosActivados _activados;
  final DateTime Function() _ahora;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();
  final StreamController<String> _toques = StreamController<String>.broadcast();
  String? _pendiente;

  /// Prepara el plugin y recoge el aviso que abrió la app, si lo hubo. Si el plugin no arranca, la app
  /// sigue: los recordatorios quedan en [ResultadoRecordatorio.noSePudo].
  Future<void> iniciar() async {
    try {
      await _motor.iniciar(alTocar: _alTocar);
      _alTocar(await _motor.payloadQueAbrioLaApp());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.agenda,
        'RECORDATORIO_INICIAR',
        'no se pudo preparar el sistema de avisos',
        {'error': e.runtimeType.toString()},
        e,
        st,
      );
    }
  }

  /// Número de aviso de [agendaId]: FNV-1a de 32 bits, positivo (el sistema pide un entero de 32
  /// bits). Dos agendas con el mismo número en el mismo teléfono es astronómicamente raro (con 100
  /// avisos pendientes, 2 en un millón).
  static int idDeAviso(String agendaId) {
    var h = 0x811c9dc5;
    for (final unidad in agendaId.codeUnits) {
      h ^= unidad;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) =>
      _encolar(() => _programar(visita));

  Future<ResultadoRecordatorio> _programar(RecordatorioDeVisita visita) async {
    final id = idDeAviso(visita.agendaId);
    if (!await _estanActivados()) {
      // Apagados: ni se programa ni queda un aviso viejo sonando.
      await _cancelarSinFallar(id, visita.agendaId, 'RECORDATORIO_APAGADOS');
      return ResultadoRecordatorio.apagados;
    }
    final minutos = await _minutos();
    final avisarEn = visita.fechaProgramada.subtract(Duration(minutes: minutos));
    if (!avisarEn.isAfter(_ahora())) {
      // Un aviso viejo con la hora de antes no puede quedar sonando.
      await _cancelarSinFallar(id, visita.agendaId, 'RECORDATORIO_YA_PASO');
      return ResultadoRecordatorio.yaPaso;
    }
    try {
      await _motor.programar(
        id: id,
        titulo: TextoRecordatorio.titulo,
        cuerpo: TextoRecordatorio.cuerpo(
          tipo: visita.tipo,
          direccion: visita.direccion,
          fechaProgramada: visita.fechaProgramada,
        ),
        instante: avisarEn,
        payload: TextoRecordatorio.payloadDe(visita.agendaId),
      );
    } on Object catch (e, st) {
      _log.error(
        LogModulo.agenda,
        'RECORDATORIO_PROGRAMAR',
        'no se pudo programar el recordatorio',
        {'agenda_id': visita.agendaId, 'error': e.runtimeType.toString()},
        e,
        st,
      );
      await _cancelarSinFallar(id, visita.agendaId, 'RECORDATORIO_PROGRAMAR');
      return ResultadoRecordatorio.noSePudo;
    }
    return await puedeAvisar()
        ? ResultadoRecordatorio.programado
        : ResultadoRecordatorio.sinPermiso;
  }

  /// Sin poder leer la preferencia se asume prendida: es mejor avisar de más que dejar a alguien sin
  /// recordatorio sin saberlo.
  Future<bool> _estanActivados() async {
    try {
      return await _activados.estan();
    } on Object catch (e) {
      _log.warn(
        LogModulo.agenda,
        'RECORDATORIO_PREFERENCIA',
        'no se pudo leer si los recordatorios están activados; se asume que sí',
        {'error': e.runtimeType.toString()},
      );
      return true;
    }
  }

  Future<int> _minutos() async {
    try {
      return AnticipacionRecordatorio.acotar(await _anticipacion.minutos());
    } on Object catch (e) {
      _log.warn(
        LogModulo.agenda,
        'RECORDATORIO_ANTICIPACION',
        'no se pudo leer la anticipación; se usa la de siempre',
        {'error': e.runtimeType.toString()},
      );
      return AnticipacionRecordatorio.porDefecto;
    }
  }

  @override
  Future<bool> cancelar(String agendaId) =>
      _encolar(() => _cancelarSinFallar(idDeAviso(agendaId), agendaId, 'RECORDATORIO_CANCELAR'));

  Future<bool> _cancelarSinFallar(int id, String agendaId, String operacion) async {
    try {
      await _motor.cancelar(id);
      return true;
    } on Object catch (e, st) {
      _log.error(
        LogModulo.agenda,
        operacion,
        'no se pudo cancelar el recordatorio',
        {'agenda_id': agendaId, 'error': e.runtimeType.toString()},
        e,
        st,
      );
      return false;
    }
  }

  @override
  Future<bool> puedeAvisar() async {
    try {
      return await _permiso.leerEstado() == EstadoSistemaNotificaciones.activadas;
    } on Object catch (e) {
      _log.warn(
        LogModulo.agenda,
        'RECORDATORIO_PERMISO',
        'no se pudo leer si las notificaciones están activadas',
        {'error': e.runtimeType.toString()},
      );
      return false;
    }
  }

  void _alTocar(String? payload) {
    final agendaId = TextoRecordatorio.agendaDelPayload(payload);
    if (agendaId == null) return;
    if (_toques.hasListener) {
      _toques.add(agendaId);
    } else {
      _pendiente = agendaId;
    }
  }

  @override
  Stream<String> get agendasTocadas => _toques.stream;

  @override
  Future<String?> tomarAgendaPendiente() async {
    final agendaId = _pendiente;
    _pendiente = null;
    return agendaId;
  }
}
