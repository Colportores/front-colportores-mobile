import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../entities/preferencias_recordatorios.dart';

/// Lo que el teléfono recuerda de las preferencias de los recordatorios (HU-NOT-004): guardado fuera
/// de la DB (almacén seguro), porque en el S8 no suben al servidor.
///
/// Las operaciones se ejecutan **en el orden en que se piden**. Leer y guardar lanzan si el almacén
/// falla: la pantalla lo dice (24B·06) y vuelve a lo que había.
abstract interface class PreferenciasRecordatoriosRepository {
  /// Lo guardado, o los valores de siempre (prendidos, 30 minutos) si nunca se eligió nada. Un valor
  /// guardado que no se entiende cuenta como «nunca se eligió»; uno fuera de rango se acota.
  Future<PreferenciasRecordatorios> leer();

  Future<void> guardarActivados({required bool activados});

  /// Guarda [minutos], acotado a `5..120`.
  Future<void> guardarAnticipacion(int minutos);
}

/// Las visitas agendadas que todavía esperan su recordatorio: las que hay que reprogramar al cambiar
/// una preferencia.
abstract interface class AgendasParaRecordar {
  /// Las agendas `PROGRAMADA` de [colportorId], sin baja y con la visita después de [desde], con la
  /// dirección que va en el aviso (la alternativa si es una cobranza en otra dirección). Lanza si no
  /// se puede leer.
  Future<List<RecordatorioDeVisita>> pendientes({
    required String colportorId,
    required DateTime desde,
  });
}

/// Una visita pendiente de recordar y si hoy está **oculta**: su casa o su depto están dados de baja
/// (HU-VIS-002, «Agenda baja»). Una agenda oculta no se muestra ni suena.
typedef AgendaConAviso = ({RecordatorioDeVisita visita, bool oculta});

/// Lo mismo que [AgendasParaRecordar] pero en vivo y con las ocultas: para sacar el recordatorio de
/// la agenda cuya casa se da de baja y devolverlo si se reactiva.
abstract interface class AgendasObservablesParaRecordar {
  /// Las agendas `PROGRAMADA` de [colportorId], sin baja propia y con la visita después de [desde],
  /// ocultas o no, que se vuelve a emitir cuando cambia una agenda, un espacio o una ubicación. Un
  /// error al leer sale por el `Stream`.
  Stream<List<AgendaConAviso>> observarPendientes({
    required String colportorId,
    required DateTime desde,
  });
}
