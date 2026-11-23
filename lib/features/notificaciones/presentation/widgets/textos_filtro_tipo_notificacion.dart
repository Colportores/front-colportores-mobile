import '../../domain/entities/tipo_notificacion.dart';

/// Los textos del filtro por tipo del centro de notificaciones (vista 24, grupo D, HU-NOT-005, #484).
///
/// Salen del canvas (`24 Notificaciones.dc.html`, 24D·01 a 24D·04) salvo los marcados «propuesta»:
/// el canvas solo escribe el vacío de «Pedido autorizado» y los demás siguen su molde.
abstract final class TextosFiltroTipoNotificacion {
  /// 24D·01. El rótulo chico de la fila y lo que dice sin filtro.
  static const rotuloFila = 'TIPO DE AVISO';
  static const todos = 'Todos';
  static const cambiar = 'Cambiar';

  /// 24D·03. «✕ Quitar»: la ✕ es un ícono; para el lector de pantalla se dice completo (propuesta).
  static const quitar = 'Quitar';
  static const quitarEtiqueta = 'Quitar el filtro y ver todos los avisos';

  /// 24D·02.
  static const hojaTitulo = 'Ver avisos de';
  static const listo = 'Listo';

  /// 24D·04.
  static const verTodos = 'Ver todos';

  /// El orden de los chips de 24D·02 (el del canvas): «Todos» (`null`) y los 7 tipos.
  static const orden = <TipoNotificacion>[
    TipoNotificacion.recordatorioVisita,
    TipoNotificacion.agendaManana,
    TipoNotificacion.pedidoAutorizado,
    TipoNotificacion.ticketValidado,
    TipoNotificacion.ticketRechazado,
    TipoNotificacion.asignacionCampania,
    TipoNotificacion.cuotaPendiente,
  ];

  /// El nombre de un tipo en la fila y en los chips; `null` es «Todos».
  static String nombre(TipoNotificacion? tipo) => switch (tipo) {
    null => todos,
    TipoNotificacion.recordatorioVisita => 'Recordatorios de visita',
    TipoNotificacion.agendaManana => 'Visitas de mañana',
    TipoNotificacion.pedidoAutorizado => 'Pedido autorizado',
    TipoNotificacion.ticketValidado => 'Ticket validado',
    TipoNotificacion.ticketRechazado => 'Ticket rechazado',
    TipoNotificacion.asignacionCampania => 'Asignaciones',
    TipoNotificacion.cuotaPendiente => 'Cuota pendiente',
  };

  /// La etiqueta de la fila para el lector de pantalla (propuesta).
  static String etiquetaFila(TipoNotificacion? tipo) => 'Tipo de aviso: ${nombre(tipo)}. $cambiar';

  /// 24D·04: dice qué tipo está filtrado. Solo el de «Pedido autorizado» está en el canvas; los
  /// otros seis son propuesta con el mismo molde.
  static String vacioTitulo(TipoNotificacion tipo) => switch (tipo) {
    TipoNotificacion.recordatorioVisita => 'No tenés avisos de recordatorios de visita',
    TipoNotificacion.agendaManana => 'No tenés avisos de visitas de mañana',
    TipoNotificacion.pedidoAutorizado => 'No tenés avisos de pedidos autorizados',
    TipoNotificacion.ticketValidado => 'No tenés avisos de tickets validados',
    TipoNotificacion.ticketRechazado => 'No tenés avisos de tickets rechazados',
    TipoNotificacion.asignacionCampania => 'No tenés avisos de asignaciones',
    TipoNotificacion.cuotaPendiente => 'No tenés avisos de cuotas pendientes',
  };

  /// 24D·04: qué hace llegar un aviso de ese tipo.
  static String vacioTexto(TipoNotificacion tipo) => switch (tipo) {
    TipoNotificacion.recordatorioVisita =>
      'Antes de cada visita agendada, el recordatorio queda acá.',
    TipoNotificacion.agendaManana => 'Cuando tengas visitas para mañana, el aviso queda acá.',
    TipoNotificacion.pedidoAutorizado => 'Cuando tu coordinador autorice un pedido, lo ves acá.',
    TipoNotificacion.ticketValidado => 'Cuando tu coordinador valide un ticket, lo ves acá.',
    TipoNotificacion.ticketRechazado => 'Cuando tu coordinador rechace un ticket, lo ves acá.',
    TipoNotificacion.asignacionCampania => 'Cuando te asignen una zona o una campaña, lo ves acá.',
    TipoNotificacion.cuotaPendiente => 'Cuando una cuota lleve días pendiente, te avisamos acá.',
  };

  /// Lo que se anuncia al lector de pantalla cuando el filtro cambia la lista (propuesta).
  static String anuncioFiltro(TipoNotificacion? tipo) => tipo == null
      ? 'Mostrando todos los avisos.'
      : 'Mostrando solo los avisos de ${nombre(tipo)}.';
}
