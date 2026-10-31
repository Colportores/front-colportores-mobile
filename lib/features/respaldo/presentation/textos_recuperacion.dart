/// Los textos del asistente de recuperación del primer arranque (HU-SYNC-006, vista 34, artboards
/// 34·01 a 34·10).
///
/// Los literales de la HU y los del canvas van tal cual. Los que no están en ninguno de los dos
/// (estado «Buscando…», los pasos de reenviar y traer lo último, «No pudimos buscar», el respaldo
/// de varias llaves, sin clave, ilegible, fallido y los detalles de lo que quedó afuera) son
/// propuesta: mapa §2, texto, a confirmar (ver el archivo de pendientes del PR).
abstract final class TextosRecuperacion {
  // El encabezado de cada paso: «RECUPERAR · PASO 1 DE 3».
  static String paso(int n) => 'RECUPERAR · PASO $n DE 3';

  // Los títulos de cada artboard.
  static const tituloEncontrado = 'Encontramos un respaldo';
  static const tituloConectar = 'Buscá tu respaldo';
  static const tituloContrasena = 'Abrí tu copia';
  static const tituloRestaurando = 'Restaurando';
  static const tituloInterrumpida = 'Se cortó la conexión';
  static const tituloParcial = 'Recuperamos casi todo';
  static const tituloListo = 'Tus datos están de vuelta';
  static const tituloSinRespaldo = 'No encontramos un respaldo';
  static const tituloSinConexion = 'Recuperar mis datos';

  // Buscando (estado de carga: la HU pide el progreso, el canvas no dibuja este instante).
  static const tituloBuscando = 'Buscando tu respaldo';
  static const buscando = 'Buscando tu respaldo en Google Drive…';

  // 34·01.
  static const textoEncontrado =
      'Podés traer a este teléfono todo lo que tenías: ubicaciones, personas, notas, ventas y '
      'cobros.';
  static const recuperar = 'Recuperar mis datos';
  static const empezarSinRecuperar = 'Empezar sin recuperar';

  // 34·02.
  static const textoConectar =
      'Tu respaldo está en tu Google Drive. Conectalo para buscarlo; solo esta app puede abrir '
      'esos archivos.';
  static const conectarConGoogle = 'Conectar con Google';
  static const conectando = 'Conectando…';

  // 34·03 y 34·04.
  static const campoContrasena = 'CONTRASEÑA';
  static const ayudaContrasena = 'La que usabas cuando se hizo este respaldo.';

  /// El texto de la HU (R32), el mismo del canvas.
  static const contrasenaNoAbre =
      'Esta contraseña no abre tu copia; probá la que usabas cuando hiciste el último respaldo.';
  static const abrirCopia = 'Abrir copia';
  static const mostrarContrasena = 'Mostrar contraseña';
  static const ocultarContrasena = 'Ocultar contraseña';

  /// La confirmación previa de la HU, con [megas] de peso: avisa antes de empezar que puede tardar.
  static String confirmacionPrevia(String megas) =>
      'Vamos a restaurar $megas. La operación puede tardar varios minutos.';

  // 34·05.
  static const infoRestaurando =
      'Lo que había en este teléfono no se toca hasta que termine. Si se corta, no se pierde nada.';
  static const restaurandoBoton = 'Restaurando…';
  static const cancelar = 'Cancelar';
  static const bajandoBase = 'Bajando base…';
  static const bajandoPartes = 'Bajando partes…';
  static const armandoLaCopia = 'Armando tu copia…';
  static const reenviando = 'Reenviando lo que estaba pendiente…';
  static const trayendoLoUltimo = 'Trayendo lo último de tu cuenta…';

  /// «12/15 partes».
  static String partes(int hechas, int total) => '$hechas/$total partes';

  // 34·06.
  static String quedoEnLaParte(int n) => 'Quedó en la parte $n';
  static const quedoEnElPrincipio = 'Todavía no bajamos ninguna parte';
  static const sinConexionAlPrincipio =
      'Se cortó la conexión. Lo que tenías antes en el teléfono no se tocó. Cuando vuelva, '
      'seguimos desde el principio.';
  static String sinConexionALaMitad(int n) =>
      'Se cortó la conexión. Lo que tenías antes en el teléfono no se tocó. Cuando vuelva, '
      'seguimos desde la parte $n.';
  static const reintentar = 'Reintentar';

  // 34·07.
  static String parteDanada(int n, int total, String hasta) =>
      'La parte $n de $total está dañada. Restauramos todo hasta el $hasta; lo posterior quedó '
      'afuera.';
  static const quedoAfuera = 'Quedó afuera';
  static const restaurado = 'Restaurado';
  static const todoLoAnterior = 'Todo lo anterior';
  static String loPosteriorA(String dia) => 'Lo registrado después del $dia';
  static String telefonoViejo(String dia) =>
      'Si tenés el teléfono viejo, lo posterior al $dia puede estar ahí.';
  static const seguirConLoRecuperado = 'Seguir con lo recuperado';
  static const verQueQuedoAfuera = 'Ver qué quedó afuera';
  static const ocultarQueQuedoAfuera = 'Ocultar lo que quedó afuera';
  static const detalleQueQuedoAfuera =
      'Lo que ya había subido a tu cuenta vuelve con la sincronización. Lo que registraste después '
      'del último respaldo y no llegó a subir solo está en el teléfono anterior.';

  // 34·08.
  static String comoElDia(String fecha) => 'Como el $fecha';
  static const ubicaciones = 'Ubicaciones';
  static const personas = 'Personas';
  static const ventas = 'Ventas';
  static const cobros = 'Cobros';
  static const irAMiInicio = 'Ir a mi inicio';

  // 34·09.
  static String sinRespaldoEn(String cuenta) =>
      'En $cuenta no hay un respaldo de Colportaje. Si lo hiciste con otra cuenta de Google, probá '
      'con esa.';
  static const sinRespaldoSinCuenta =
      'En tu Google Drive no hay un respaldo de Colportaje. Si lo hiciste con otra cuenta de '
      'Google, probá con esa.';
  static const probarConOtraCuenta = 'Probar con otra cuenta';

  // 34·10.
  static const necesitaConexion = 'Necesitás conexión (mejor Wi-Fi) para traer tu respaldo.';

  // Casos que el canvas no dibuja.
  static const tituloNoPudimosBuscar = 'No pudimos buscar tu respaldo';
  static const noPudimosBuscar =
      'Algo falló al mirar tu Google Drive. Probá de nuevo; si sigue pasando, podés empezar sin '
      'recuperar.';
  static const tituloVariosRespaldos = 'Encontramos más de un respaldo';
  static const variosRespaldos =
      'Hay respaldos de más de un teléfono en tu Drive y todavía no sabemos cuál traerte. Todavía '
      'no los tocamos: podés reintentar más tarde o empezar sin recuperar.';
  static const tituloVersionMasNueva = 'Actualizá la app';

  /// El texto de la HU, tal cual.
  static const versionMasNueva =
      'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus datos.';
  static const actualizar = 'Actualizar';
  static const actualizarComo =
      'Buscá Colportores en la tienda de tu celular (Google Play o App Store) y actualizala.';
  static const tituloSinLlave = 'No podemos abrir este respaldo';
  static const sinLlave =
      'Este respaldo no tiene la clave que hace falta para abrirlo, y ninguna contraseña la '
      'reemplaza. No se tocó nada de tu teléfono.';
  static const tituloIlegible = 'No pudimos leer tu respaldo';
  static const ilegible =
      'El respaldo está dañado y no hay nada para traer. No se tocó nada de tu teléfono.';
  static const tituloFallida = 'No pudimos recuperar tus datos';
  static const fallida =
      'Algo falló y no se pudo terminar. No se tocó nada de tu teléfono. Probá de nuevo en unos '
      'minutos.';
  static const sinPermiso =
      'Google ya no nos deja abrir tu Drive. Conectalo de nuevo para seguir con tu respaldo.';

  // Formatos.

  /// «22/10» en la zona del teléfono.
  static String dia(DateTime fecha) {
    final f = fecha.toLocal();
    return '${_dos(f.day)}/${_dos(f.month)}';
  }

  /// «22/10 a las 03:10» en la zona del teléfono.
  static String diaYHora(DateTime fecha) {
    final f = fecha.toLocal();
    return '${dia(fecha)} a las ${_dos(f.hour)}:${_dos(f.minute)}';
  }

  /// «15 partes · 38 MB» (una sola parte: «1 parte · …»).
  static String partesYPeso(int partes, int bytes) {
    final megas = (bytes / (1024 * 1024)).round();
    final peso = bytes <= 0 ? '0 MB' : '${megas < 1 ? 1 : megas} MB';
    return '$partes ${partes == 1 ? 'parte' : 'partes'} · $peso';
  }

  /// «38 MB», para la confirmación previa.
  static String peso(int bytes) {
    final megas = (bytes / (1024 * 1024)).round();
    return '${megas < 1 ? 1 : megas} MB';
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}
