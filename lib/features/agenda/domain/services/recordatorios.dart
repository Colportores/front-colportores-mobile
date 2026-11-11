import '../entities/recordatorio_de_visita.dart';

/// Qué pasó al programar el recordatorio de una visita. Programar **nunca falla**: guardar la
/// visita no puede depender de que el teléfono acepte el aviso.
enum ResultadoRecordatorio {
  /// Quedó programado y el teléfono puede mostrarlo.
  programado,

  /// Quedó programado, pero las notificaciones están apagadas en el teléfono: no se va a ver hasta que
  /// se activen (23A·07 avisa «la visita se agenda, pero no te va a llegar el recordatorio»).
  sinPermiso,

  /// La hora del aviso ya pasó (la visita es en menos que la anticipación): no se programó y, si
  /// había un recordatorio anterior de esa agenda, se canceló. Es lo decidido el 26/10 (mapa §2): ni
  /// aviso al instante ni a mitad de camino. Quien guarda la visita no promete un recordatorio que no
  /// va a sonar: 23C·03 dice «Guardado. Falta menos de N min para la visita: no hay recordatorio.»,
  /// con la anticipación real (#409).
  yaPaso,

  /// La persona apagó «Recordatorios de agenda» (HU-NOT-004): no se programó y, si había un
  /// recordatorio anterior de esa agenda, se canceló.
  apagados,

  /// El teléfono no pudo programarlo (falló la plataforma). El recordatorio anterior de esa agenda,
  /// si lo había, se canceló: ya no tiene la hora buena.
  noSePudo,
}

/// Los recordatorios locales de las visitas agendadas (HU-NOT-002).
///
/// Es el puerto que usan los casos de uso de la agenda (HU-VIS-001 a 004) para que se prueben sin el
/// plugin del teléfono. Las operaciones se ejecutan **en el orden en que se piden**: un «cancelar»
/// pedido justo después de un «programar» gana. Ninguna lanza.
abstract interface class Recordatorios {
  /// Programa el aviso de [visita] con la anticipación elegida. Si esa agenda ya tenía uno, lo
  /// reemplaza (cambiar la hora de la visita lo reprograma). Ver [ResultadoRecordatorio].
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita);

  /// Cancela el aviso de la agenda [agendaId] (la visita se canceló o se cumplió). Sin recordatorio
  /// no hace nada. Devuelve `false` si el teléfono no pudo cancelarlo: la visita igual queda
  /// cancelada, pero el aviso podría sonar.
  Future<bool> cancelar(String agendaId);

  /// Si el teléfono deja mostrar los avisos. Con el permiso negado los recordatorios se programan
  /// igual (suenan si la persona lo activa después). Si no se puede saber, `false`: es mejor avisar
  /// de más que dejar a alguien sin recordatorio sin saberlo.
  Future<bool> puedeAvisar();
}

/// La persona tocó un recordatorio: hay que abrir el detalle de esa visita (vista 23, 23C·01).
abstract interface class ToquesDeRecordatorios {
  /// El `agenda.id` de cada recordatorio tocado con la app abierta o en segundo plano y alguien
  /// escuchando.
  Stream<String> get agendasTocadas;

  /// El `agenda.id` de un recordatorio que se tocó cuando nadie escuchaba (la app arrancó por él, o
  /// estaba en la pantalla de ingreso), o `null`. Se entrega una sola vez.
  Future<String?> tomarAgendaPendiente();
}

/// Cuántos minutos antes de la visita suena el recordatorio (HU-NOT-002, `notif_anticipacion_minutos`).
abstract interface class AnticipacionRecordatorios {
  /// Los minutos elegidos; quien los usa los acota a `AnticipacionRecordatorio.acotar`.
  Future<int> minutos();
}

/// Si «Recordatorios de agenda» está prendido (HU-NOT-004). Apagado, no se programa ninguno y los ya
/// programados se cancelan.
abstract interface class RecordatoriosActivados {
  Future<bool> estan();
}

/// [RecordatoriosActivados] que dice siempre que sí: el default mientras no haya preferencias
/// guardadas.
final class RecordatoriosSiempreActivados implements RecordatoriosActivados {
  const RecordatoriosSiempreActivados();

  @override
  Future<bool> estan() async => true;
}

/// [AnticipacionRecordatorios] que vale siempre lo mismo: los 30 minutos de default mientras la
/// pantalla de preferencias (#155) no guarde otro valor.
final class AnticipacionFija implements AnticipacionRecordatorios {
  const AnticipacionFija([this.valor = 30]);

  final int valor;

  @override
  Future<int> minutos() async => valor;
}
