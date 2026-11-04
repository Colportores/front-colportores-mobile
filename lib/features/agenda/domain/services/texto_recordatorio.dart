import '../entities/tipo_agenda.dart';

/// Lo que dice el recordatorio de una visita (HU-NOT-002): el tipo, la dirección y la hora. **Nunca
/// el nombre del cliente** ni ningún otro dato de la persona: esta clase no los recibe.
abstract final class TextoRecordatorio {
  /// El título de la notificación. La HU solo fija el cuerpo; este texto quedó decidido el 26/10
  /// (mapa §2), coherente con «Recordatorios de tus visitas» de la vista 24.
  static const String titulo = 'Recordatorio de visita';

  /// «Entrevista en Av. Italia 1234 a las 14:00». La hora es la del teléfono (24 horas). Sin
  /// dirección: «Entrevista a las 14:00». Los saltos de línea y los espacios repetidos de la dirección
  /// se llevan a un solo espacio.
  static String cuerpo({
    required TipoAgenda tipo,
    required String direccion,
    required DateTime fechaProgramada,
  }) {
    final etiqueta = switch (tipo) {
      TipoAgenda.entrevista => 'Entrevista',
      TipoAgenda.cobranza => 'Cobranza',
    };
    final hora = fechaProgramada.toLocal();
    final hh = hora.hour.toString().padLeft(2, '0');
    final mm = hora.minute.toString().padLeft(2, '0');
    final lugar = direccion.replaceAll(RegExp(r'\s+'), ' ').trim();
    return lugar.isEmpty ? '$etiqueta a las $hh:$mm' : '$etiqueta en $lugar a las $hh:$mm';
  }

  /// «Av. Italia 1234»: la [calle] y el [numero] unidos por un espacio; solo uno si falta el otro,
  /// vacía si faltan los dos (la dirección que va en el aviso de una visita).
  static String direccionDe(String? calle, String? numero) => [
    for (final parte in [calle, numero])
      if (parte != null && parte.trim().isNotEmpty) parte.trim(),
  ].join(' ');

  /// El dato que viaja con la notificación para saber qué visita abrir al tocarla: solo el id.
  static String payloadDe(String agendaId) => '$_prefijo$agendaId';

  /// Inversa de [payloadDe]; `null` si el payload no es de un recordatorio de agenda.
  static String? agendaDelPayload(String? payload) {
    if (payload == null || !payload.startsWith(_prefijo)) return null;
    final id = payload.substring(_prefijo.length);
    return id.isEmpty ? null : id;
  }

  static const String _prefijo = 'agenda:';
}
