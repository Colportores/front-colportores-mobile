/// Los textos del centro de notificaciones (vista 24, grupo C, HU-NOT-005).
///
/// Salen del canvas (`24 Notificaciones.dc.html`, 24C·01 a 24C·07) salvo los marcados «propuesta»:
/// el canvas no los dibuja y están para confirmar (pendiente «mapa §2: texto/aviso» del PR).
abstract final class TextosCentroNotificaciones {
  /// 24C·01. El rótulo de arriba y el título.
  static const rotulo = 'NOTIFICACIONES';
  static const titulo = 'Notificaciones';

  /// La campana del encabezado de Hoy. Propuesta (el canvas no la dibuja; la nombra la navegación).
  static const campana = 'Notificaciones';
  static String campanaConNuevas(int n) =>
      n == 1 ? 'Notificaciones, 1 sin leer' : 'Notificaciones, $n sin leer';

  /// El «⋯» del encabezado. Propuesta.
  static const menu = 'Opciones de las notificaciones';

  /// La marca de una no leída.
  static const nueva = 'Nueva';

  /// 24C·02.
  static const marcarTodas = 'Marcar todas como leídas';
  static const borrarTodas = 'Borrar todas';
  static const cerrar = 'Cerrar';

  /// 24C·03. Con una sola, el singular es propuesta.
  static String borrarTitulo(int n) =>
      n == 1 ? '¿Borrar la notificación?' : '¿Borrar las $n notificaciones?';
  static const borrarTexto =
      'Se borran de este teléfono. Lo que avisaban (agendas, pedidos, tickets) no cambia.';
  static const cancelar = 'Cancelar';

  /// 24C·04.
  static const vacioTitulo = 'No tenés notificaciones';
  static const vacioTexto = 'Acá ves los avisos de los últimos 90 días.';

  /// 24C·05. Propuesta de la etiqueta para el lector de pantalla (el canvas dibuja los bloques).
  static const cargando = 'Cargando tus notificaciones';

  /// 24C·06.
  static const errorAlLeer = 'No pudimos leer tus notificaciones.';
  static const reintentar = 'Reintentar';

  /// 24C·07. El de una agenda; el de cada destino nuevo se suma con su pantalla.
  static const agendaYaNoEsta = 'Esa agenda ya no está: se canceló o se borró.';

  /// Lo que el canvas no dibuja (propuesta): las fallas de cada acción, con qué hacer.
  static const errorAlAbrir = 'No pudimos abrir ese aviso. Probá de nuevo.';
  static const errorAlMarcar = 'No pudimos marcar las notificaciones como leídas. Probá de nuevo.';
  static const errorAlBorrar = 'No pudimos borrar las notificaciones. Probá de nuevo.';

  /// Lo que se anuncia al lector de pantalla cuando una acción cambia la lista (propuesta).
  static const anuncioMarcadas = 'Todas las notificaciones quedaron como leídas.';
  static const anuncioBorradas = 'Se borraron las notificaciones.';

  /// «Marcar todas como leídas» sin nada para marcar (propuesta).
  static const nadaParaMarcar = 'No hay notificaciones sin leer';

  /// El rótulo del día de un aviso (24C·01: «HOY», «AYER», «LUNES 21»). Más de una semana atrás,
  /// con el mes (propuesta: el canvas no llega a esos días).
  static const hoy = 'HOY';
  static const ayer = 'AYER';
}
