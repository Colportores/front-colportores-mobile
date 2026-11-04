import 'dart:async';

import '../../../domain/entities/recordatorio_de_visita.dart';
import '../../../domain/services/recordatorios.dart';

/// [Recordatorios] y [ToquesDeRecordatorios] en memoria.
///
/// **No es código de producción.** Es el default de los tests y de la app sin el plugin: los casos de
/// uso de la agenda (HU-VIS-001 a 004) se prueban contra él, sin tocar el teléfono. Guarda el
/// recordatorio vigente de cada agenda y cuenta las llamadas.
final class RecordatoriosEnMemoria implements Recordatorios, ToquesDeRecordatorios {
  RecordatoriosEnMemoria({this.permisoConcedido = true});

  /// Lo que contesta [puedeAvisar]; con `false`, [programar] devuelve `sinPermiso`.
  bool permisoConcedido;

  /// Si no es `null`, es lo que contesta [programar] (por ejemplo `yaPaso`) sin guardar nada.
  ResultadoRecordatorio? resultadoForzado;

  /// Si es `false`, [cancelar] devuelve `false` y no cancela nada.
  bool puedeCancelar = true;

  /// Si no es `null`, [programar] espera a que se complete.
  Completer<void>? programacionDemorada;

  /// El recordatorio vigente de cada agenda, por `agendaId`.
  final Map<String, RecordatorioDeVisita> programados = {};

  /// Cada pedido en el orden en que llegó: `programar:<agendaId>`, `cancelar:<agendaId>`.
  final List<String> llamadas = [];

  final StreamController<String> _toques = StreamController<String>.broadcast();
  String? _pendiente;

  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) async {
    llamadas.add('programar:${visita.agendaId}');
    final demora = programacionDemorada;
    if (demora != null) await demora.future;
    final forzado = resultadoForzado;
    if (forzado != null) return forzado;
    programados[visita.agendaId] = visita;
    return permisoConcedido ? ResultadoRecordatorio.programado : ResultadoRecordatorio.sinPermiso;
  }

  @override
  Future<bool> cancelar(String agendaId) async {
    llamadas.add('cancelar:$agendaId');
    if (!puedeCancelar) return false;
    programados.remove(agendaId);
    return true;
  }

  @override
  Future<bool> puedeAvisar() async => permisoConcedido;

  /// Simula que la persona toca el recordatorio de [agendaId]: lo recibe quien escucha, o queda
  /// pendiente.
  void tocar(String agendaId) {
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
