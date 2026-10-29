import '../../../agenda/domain/services/recordatorios.dart';
import '../repositories/preferencias_recordatorios_repository.dart';

/// Mantiene los recordatorios de acuerdo con las agendas ocultas (HU-VIS-002, «Agenda baja», regla R7:
/// mientras la agenda está oculta tampoco suena su recordatorio; si la casa se reactiva, vuelve con la
/// agenda).
///
/// Recibe cada lectura de [AgendasObservablesParaRecordar] y compara con la anterior:
/// - una agenda que **pasa a oculta** (o que ya estaba oculta al abrir la app) pierde su aviso;
/// - una agenda que **deja de estar oculta** vuelve a programarlo, con la hora y la dirección de
///   ahora (`Recordatorios.programar` respeta lo apagado y lo que ya pasó).
///
/// Lo que no cambia no se toca: los avisos de las agendas visibles no se reprograman en cada lectura.
/// Las llamadas siguen el orden de las lecturas (una a la vez).
final class ConciliadorRecordatoriosOcultos {
  ConciliadorRecordatoriosOcultos(this._recordatorios);

  final Recordatorios _recordatorios;

  /// Si cada agenda estaba oculta en la lectura anterior, por `agendaId`.
  Map<String, bool> _anterior = const {};

  Future<void> _cola = Future<void>.value();

  /// Aplica una lectura. Nunca lanza.
  Future<void> aplicar(List<AgendaConAviso> actuales) {
    final siguiente = _cola.then((_) => _aplicar(actuales));
    _cola = siguiente.then<void>((_) {}, onError: (Object _) {});
    return siguiente;
  }

  Future<void> _aplicar(List<AgendaConAviso> actuales) async {
    final previo = _anterior;
    _anterior = {for (final a in actuales) a.visita.agendaId: a.oculta};
    for (final a in actuales) {
      final id = a.visita.agendaId;
      final estabaOculta = previo[id];
      if (a.oculta) {
        if (estabaOculta != true) await _recordatorios.cancelar(id);
      } else if (estabaOculta == true) {
        await _recordatorios.programar(a.visita);
      }
    }
  }
}
