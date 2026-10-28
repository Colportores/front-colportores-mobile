import '../domain/entities/tipo_agenda.dart';

/// Los textos de «Agendar una visita» (vista 23, grupo A, HU-VIS-001, 23A·01 a 23A·08).
///
/// Los del canvas van letra por letra. Los que el canvas no dibuja son propuestas: quedan marcadas en
/// el PR como «para confirmar» (mapa §2: texto/aviso).
abstract final class TextosAgendarVisita {
  // 23A·01: el formulario.
  static const rotulo = 'AGENDAR';
  static const titulo = 'Agendar visita';
  static const cerrar = 'Cerrar';
  static const etiquetaTipo = 'TIPO';
  static const entrevista = 'Entrevista';
  static const cobranza = 'Cobranza';
  static const etiquetaDiaYHora = 'DÍA Y HORA';
  static const etiquetaFranja = 'FRANJA SUGERIDA';
  static const etiquetaNota = 'NOTA (OPCIONAL)';
  static const sugerenciaNota = 'Solo la ves vos';
  static const agendar = 'Agendar';

  /// 23A·04.
  static const agendando = 'Agendando…';

  /// 23A·06: el botón pasa a decir «Reintentar».
  static const reintentar = 'Reintentar';

  /// 23A·01: lo que dice debajo del formulario con los avisos prendidos.
  static String recordatorio(int minutos) =>
      'Te avisamos $minutos min antes. Lo cambiás en Preferencias de notificaciones.';

  // 23A·02: la hoja «Día y hora».
  static const hojaTitulo = 'Día y hora';
  static const etiquetaDia = 'DÍA';
  static const hoy = 'Hoy';
  static const manana = 'Mañana';
  static const otroDia = 'Otro día…';
  static const etiquetaHora = 'Hora';
  static const listo = 'Listo';
  static const masHora = 'Subir la hora';
  static const menosHora = 'Bajar la hora';

  /// «Franja sugerida: primera tarde» (la etiqueta, en minúscula).
  static String franjaSugerida(String etiqueta) =>
      'Franja sugerida: ${etiqueta[0].toLowerCase()}${etiqueta.substring(1)}';

  // 23A·03: la hora ya pasó.
  static const horaPasadaCorta = 'Esa hora ya pasó';
  static const agendarIgual = 'Agendar igual';
  static const cambiarLaHora = 'Cambiar la hora';

  /// «Hoy a las 11:00 ya pasó (son las 14:35). ¿La agendás igual?». [cuando] es «Hoy a las 11:00» o
  /// «El lun 12/10 a las 11:00».
  static String horaPasadaTexto(String cuando, String ahora) =>
      '$cuando ya pasó (son las $ahora). ¿La agendás igual?';

  /// 23A·03: debajo del formulario, cuando la hora elegida ya pasó, el aviso de que no habrá
  /// recordatorio («Agendar igual no programa el recordatorio»).
  static const horaPasadaSinRecordatorio =
      'Si la agendás igual, no te vamos a avisar: la hora ya pasó.';

  // 23A·05: el aviso de éxito.
  static String agendada(TipoAgenda tipo) => switch (tipo) {
    TipoAgenda.entrevista => 'Agendada. La casa queda como «Entrevista agendada».',
    TipoAgenda.cobranza || TipoAgenda.entrega => 'Agendada.',
  };

  /// La visita quedó agendada, pero faltaba menos que la anticipación y no hay recordatorio.
  static String agendadaSinTiempoDeAviso(int minutos) =>
      'Agendada. Falta menos de $minutos min para la visita: no hay recordatorio.';

  /// La visita quedó agendada, pero el teléfono no pudo programar el aviso.
  static const agendadaSinAviso =
      'Agendada, pero no pudimos programar el recordatorio. Revisá la visita en tu agenda.';

  /// 23A·07 en el aviso de éxito: se agendó con las notificaciones apagadas.
  static const agendadaSinPermiso =
      'Agendada. Las notificaciones están apagadas: no te va a llegar el recordatorio.';

  /// Se agendó, con los recordatorios apagados en las preferencias.
  static const agendadaConRecordatoriosApagados =
      'Agendada. Los recordatorios están apagados: no te vamos a avisar.';

  /// Debajo del formulario: la visita es en menos que la anticipación y no habrá recordatorio.
  static String sinTiempoDeAviso(int minutos) =>
      'Falta menos de $minutos min para la visita: no hay recordatorio.';

  /// Hora pasada confirmada: se agendó sin aviso.
  static const agendadaSinAvisoHoraPasada =
      'Agendada. La hora ya había pasado: no hay recordatorio.';

  // 23A·06: falla al guardar.
  static const noPudimosGuardar = 'No pudimos guardar la agenda en tu teléfono. Probá de nuevo.';

  // 23A·07: sin permiso de notificaciones.
  static const sinPermiso =
      'Las notificaciones están apagadas: la visita se agenda, pero no te va a llegar el recordatorio.';
  static const activarNotificaciones = 'Activar notificaciones';

  /// Las notificaciones están bloqueadas en los ajustes del teléfono: solo se activan allá.
  static const abrirAjustes = 'Abrir ajustes del teléfono';

  /// No se pudo pedir el permiso o abrir los ajustes.
  static const noPudimosActivar =
      'No pudimos activar las notificaciones desde acá. Activalas en los ajustes del teléfono.';

  /// Los recordatorios están apagados en las preferencias (HU-NOT-004).
  static const recordatoriosApagados =
      'Los recordatorios de agenda están apagados: la visita se agenda, pero no te vamos a avisar. '
      'Los prendés en Preferencias de notificaciones.';

  // Lo que el canvas no dibuja: leer la casa.
  static const cargando = 'Cargando la casa…';
  static const noPudimosLeer = 'No pudimos leer la casa en tu teléfono.';
  static const casaNoEstaMas =
      'Esta casa ya no está en tu teléfono. Volvé al mapa y elegila de nuevo.';
  static const sinPersona = 'Sin persona';

  /// La etiqueta del renglón de la persona para el lector de pantalla.
  static String lectorPersona(String nombre, String donde) => '$nombre, $donde';

  /// El campo «DÍA Y HORA» para el lector: «Día y hora: jueves 24/10, 14:30. Tocá para cambiar».
  static String lectorDiaYHora(String valor) => 'Día y hora: $valor. Tocá para cambiar';

  /// La franja elegida / sin elegir, para el lector.
  static String lectorFranja(String etiqueta, String rango, {required bool elegida}) =>
      '$etiqueta, $rango${elegida ? ', elegida' : ''}';
}
