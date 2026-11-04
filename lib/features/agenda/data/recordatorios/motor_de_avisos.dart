/// Lo mínimo que la app le pide al sistema de avisos del teléfono (HU-NOT-002): programar un aviso a
/// una hora, cancelarlo y enterarse de qué aviso se tocó. Puerto en Dart puro; el de producción es
/// `MotorDeAvisosPlugin` (`flutter_local_notifications`) y el de los tests, un fake.
///
/// Todo lo que falle en la plataforma sale como excepción: quien lo usa (`RecordatoriosLocales`) la
/// traduce y no deja que llegue a la visita.
abstract interface class MotorDeAvisos {
  /// Prepara el plugin y registra [alTocar], que recibe el `payload` de cada aviso tocado con la app
  /// viva. Hay que llamarlo antes que cualquier otra operación y una sola vez.
  Future<void> iniciar({required void Function(String? payload) alTocar});

  /// El `payload` del aviso que abrió la app desde cero, o `null` si la app no arrancó por un aviso.
  Future<String?> payloadQueAbrioLaApp();

  /// Programa un aviso con [id] para [instante] (UTC). Si ya había uno con ese [id], lo reemplaza.
  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime instante,
    required String payload,
  });

  /// Cancela el aviso [id]. Sin aviso con ese id no hace nada.
  Future<void> cancelar(int id);
}
