// Falsos de «cada recordatorio local se guarda al dispararse» (HU-NOT-005, #416): las agendas con su
// aviso vencido, en memoria, que respetan la ventana igual que la consulta real.
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/conciliacion_recordatorios_repository.dart';

/// Las agendas `PROGRAMADA` del colportor, sin más filtro que la ventana del aviso.
final class AgendasConAvisoVencidoEnMemoria implements AgendasConAvisoVencido {
  AgendasConAvisoVencidoEnMemoria([Iterable<RecordatorioDeVisita> visitas = const []])
    : visitas = [...visitas];

  final List<RecordatorioDeVisita> visitas;

  /// Cada pedido: `desde|hasta|minutos` (para afirmar sobre la ventana).
  final List<String> pedidos = [];

  /// Con un error, la lectura lanza.
  Object? error;

  @override
  Future<List<RecordatorioDeVisita>> conAvisoEntre({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
    required int anticipacionMinutos,
  }) async {
    pedidos.add(
      '${desde.toUtc().toIso8601String()}|${hasta.toUtc().toIso8601String()}|$anticipacionMinutos',
    );
    final e = error;
    if (e != null) throw e;
    final anticipacion = Duration(minutes: anticipacionMinutos);
    return [
      for (final v in visitas)
        if (v.fechaProgramada.subtract(anticipacion).isAfter(desde) &&
            !v.fechaProgramada.subtract(anticipacion).isAfter(hasta))
          v,
    ];
  }
}

RecordatorioDeVisita visitaParaAviso(
  String agendaId,
  DateTime cuando, {
  TipoAgenda tipo = TipoAgenda.entrevista,
  String direccion = 'Av. Italia 1234',
}) => RecordatorioDeVisita(
  agendaId: agendaId,
  tipo: tipo,
  direccion: direccion,
  fechaProgramada: cuando,
);
