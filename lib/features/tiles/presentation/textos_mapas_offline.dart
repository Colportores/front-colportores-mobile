import '../domain/entities/estado_descarga.dart';
import '../domain/entities/paquete_tiles.dart';

/// Los textos de «Mapas offline» (vista 35, HU-SYNC-010). Los literales del canvas van tal cual; lo
/// que el canvas no dibuja (sin conexión, falla, lugar desconocido) es de mapa §2 (texto que guía),
/// a confirmar. Nada de lo que se muestra se inventa: pesos y espacio salen del catálogo y del
/// teléfono.
abstract final class TextosMapasOffline {
  static const filaConfiguracion = 'Mapas offline';
  static const seccionConfiguracion = 'Mapas';
  static const sinMapasDescargados = 'Sin mapas descargados';
  static const titulo = 'Mapas offline';
  static const etiqueta01 = 'MAPAS OFFLINE · 01';
  static const etiqueta02 = 'MAPAS OFFLINE · 02';
  static const subtitulo = 'Para usar el mapa sin señal.';
  static const cuantoMapa = 'CUÁNTO MAPA';
  static const miZona = 'Mi zona';
  static const miCiudad = 'Mi ciudad';
  static const miDepartamento = 'Mi departamento';
  static const todoUruguay = 'Todo Uruguay';
  static const llegaConPro = 'Llega con el paso a Pro';
  static const sinZona = 'No tenés zona asignada';
  static const zonaSinPaquete = 'Todavía no está disponible. Tu ciudad lo cubre.';
  static const sinPaquete = 'Todavía no está disponible';
  static const yaDescargado = 'Descargado';
  static const ayudaCiudad =
      'Las casas de la ciudad entera ya bajan siempre; esto es solo el mapa de fondo.';
  static const descargar = 'Descargar';
  static const descargarConWifi = 'Descargar con Wi-Fi';
  static const yaLoTenes = 'Ya lo tenés descargado.';
  static const datosMoviles =
      'Estás con datos móviles. La descarga empieza cuando te conectes a Wi-Fi.';
  static const sinConexion = 'No hay conexión. La descarga empieza cuando te conectes a Wi-Fi.';
  static const sinCatalogo = 'Necesitás conexión para ver los mapas que se pueden descargar.';
  static const reintentar = 'Reintentar';
  static const revisando = 'Revisando los mapas…';
  static const descargando = 'Descargando';
  static const descargado = 'Descargado';
  static const verificando = 'Verificando…';
  static const enPausa = 'En pausa';
  static const noSePudo = 'No se pudo';
  static const pausar = 'Pausar';
  static const seguir = 'Seguir';
  static const puedeSeguirUsandoLaApp =
      'Podés seguir usando la app. Si la cerrás, la descarga sigue sola al volver.';
  static const pausadaSinWifi = 'Pausada: sin Wi-Fi. Sigue sola cuando vuelva.';
  static const pausadaSinConexion = 'Pausada: sin conexión. Sigue sola cuando vuelva.';
  static const pausadaPorVos = 'Pausada. Tocá Seguir para continuar.';
  static const cambiarCobertura = 'Cambiar cobertura';
  static const borrarMapa = 'Borrar mapa';
  static const borrar = 'Borrar';
  static const borrarTexto = 'Para volver a tenerlo vas a necesitar Wi-Fi.';
  static String borrarTitulo(String nombre) => '¿Borrar el mapa de $nombre?';
  static const actualizar = 'Actualizar';
  static const cancelar = 'Cancelar';
  static const ahoraNo = 'Ahora no';
  static const volver = 'Volver';
  static const noPudimosBorrar = 'No pudimos borrar el mapa. Probá de nuevo.';
  static const noPudimosPedir = 'No pudimos empezar la descarga. Probá de nuevo.';

  static String restante(Duration? falta) {
    if (falta == null) return '';
    if (falta.inSeconds < 60) return 'Queda menos de 1 min';
    return 'Quedan unos ${(falta.inSeconds / 60).round()} min';
  }

  static String disponibleSinConexion(String nombre) =>
      'El mapa de $nombre está disponible sin conexión.';

  static String mapaBorrado(int megabytes) =>
      megabytes <= 0 ? 'Mapa borrado.' : 'Mapa borrado. Liberaste $megabytes MB.';

  static String descargadoListo(String peso) => '$peso · listo para usar sin conexión';

  static String avanceDe(int recibidos, int total) =>
      '${megabytesDe(recibidos)} de ${megabytesDe(total)} MB';

  static String versionNueva(String nombre, String peso) =>
      'Hay una versión nueva del mapa de $nombre ($peso). Se baja con Wi-Fi.';

  /// El renglón de espacio libre al pie de la pantalla 01.
  static String espacioLibre(int bytes) =>
      'Se baja con Wi-Fi. En el teléfono te quedan '
      '${pesoLibre(bytes)} libres.';

  static String sinLugar(String nombre, String peso, String libre, {required bool haySalida}) =>
      'No hay lugar: $nombre ocupa $peso y te quedan $libre. '
      '${haySalida ? 'Elegí un mapa más chico o liberá espacio.' : 'Liberá espacio en el teléfono.'}';

  static String achicarTitulo(NivelCobertura nivel) => switch (nivel) {
    NivelCobertura.zona => '¿Quedarte solo con tu zona?',
    NivelCobertura.ciudad => '¿Quedarte solo con tu ciudad?',
    NivelCobertura.departamento => '¿Quedarte solo con tu departamento?',
    NivelCobertura.uruguay => '¿Quedarte con todo Uruguay?',
  };

  static String achicarTexto({
    required String mayor,
    required String elegido,
    required int liberanMegabytes,
  }) =>
      'Borramos el mapa de $mayor y liberás $liberanMegabytes MB. Fuera de $elegido, el mapa sin '
      'señal se ve en blanco.';

  static String achicarAccion(NivelCobertura nivel) => switch (nivel) {
    NivelCobertura.zona => 'Quedarme con mi zona',
    NivelCobertura.ciudad => 'Quedarme con mi ciudad',
    NivelCobertura.departamento => 'Quedarme con mi departamento',
    NivelCobertura.uruguay => 'Quedarme con Uruguay',
  };

  static String nivel(NivelCobertura nivel) => switch (nivel) {
    NivelCobertura.zona => miZona,
    NivelCobertura.ciudad => miCiudad,
    NivelCobertura.departamento => miDepartamento,
    NivelCobertura.uruguay => todoUruguay,
  };

  /// Cómo se llama un mapa: el nombre del catálogo; el de zona no lo trae, así que se lo da la
  /// réplica local; sin nada, el nivel.
  static String nombreDe(PaqueteTiles paquete, {String? nombreZona}) =>
      paquete.nombre ??
      (paquete.nivel == NivelCobertura.zona ? nombreZona : null) ??
      nivel(paquete.nivel);

  /// Lo que pesa un paquete, redondeado para arriba: «86 MB», «1,2 GB».
  static String peso(int bytes) {
    final megas = megabytesDe(bytes);
    if (megas < 1000) return '$megas MB';
    return '${_decimal((bytes / 1e8).ceil() / 10)} GB';
  }

  /// El espacio libre, redondeado para abajo: nunca promete más lugar del que hay.
  static String pesoLibre(int bytes) {
    if (bytes < 0) return '0 MB';
    if (bytes < 1000 * 1000 * 1000) return '${bytes ~/ (1000 * 1000)} MB';
    return '${_decimal((bytes / 1e8).floor() / 10)} GB';
  }

  static String _decimal(double valor) => valor.toStringAsFixed(1).replaceAll('.', ',');

  static String motivoDePausa(DescargaPausada pausa) => switch (pausa.motivo) {
    MotivoPausa.usuario => pausadaPorVos,
    MotivoPausa.sinWifi => pausadaSinWifi,
    MotivoPausa.sinConexion => pausadaSinConexion,
  };
}
