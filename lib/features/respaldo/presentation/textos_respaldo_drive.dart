/// Los textos del respaldo en Drive (HU-SYNC-004, vista 16 «Cuenta Drive», artboards 16D·01 a
/// 16D·10; otra cuenta de Google, 16E·01 a 16E·04; la franja del Drive en Hoy, 16F·01 a 16F·04).
///
/// Los literales de la HU van tal cual; el resto es el del canvas. Los que no están en ninguno de
/// los dos (estado «Revisando…», «No pudimos ver el estado», «Todavía no hubo un respaldo»,
/// «No pudimos desconectar…», «Ocultar hasta mañana», los de lector de pantalla de 16E y 16F) son
/// propuesta: mapa §2, texto, a confirmar.
abstract final class TextosRespaldoDrive {
  // La sección y la fila.
  static const seccion = 'Respaldo';
  static const fila = 'Cuenta Drive';
  static const sinConectar = 'Sin conectar · tus datos no tienen respaldo';
  static const conectar = 'Conectar';
  static const reconectar = 'Reconectar';
  static const permisoRevocado = 'Sin permiso · los respaldos están frenados';
  static const sinEspacio = 'Tu Drive está lleno · el respaldo no se guardó';
  static const revisando = 'Revisando tu respaldo…';
  static const noPudimosVer = 'No pudimos ver el estado de tu respaldo.';
  static const reintentar = 'Reintentar';
  static const sinRespaldoTodavia = 'Todavía no hubo un respaldo';

  /// «Último respaldo: hoy 03:10», «ayer 03:10» o «el 12/10 03:10».
  static String ultimoRespaldo(DateTime respaldo, DateTime ahora) {
    final hora =
        '${respaldo.hour.toString().padLeft(2, '0')}:${respaldo.minute.toString().padLeft(2, '0')}';
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(respaldo.year, respaldo.month, respaldo.day);
    final cuando = switch (hoy.difference(dia).inDays) {
      0 => 'hoy',
      1 => 'ayer',
      _ => 'el ${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}',
    };
    return 'Último respaldo: $cuando $hora';
  }

  /// El aviso de Inicio con más de 7 días sin un respaldo exitoso (HU-SYNC-005, «Aviso por > 7 días
  /// sin backup»): el literal de la HU, con [dias] en lugar del número. «Reintentar» y
  /// «Reintentando…» son propuesta (mapa §2, texto, a confirmar).
  static String avisoSinRespaldo(int dias) =>
      'Llevás $dias días sin respaldo. Revisá tu conexión y reintentá.';
  static const reintentando = 'Reintentando…';

  /// Lo que se le dice tras tocar «Reintentar» si no se pudo (decisión del 29/10, QA #185): sin
  /// conexión, y cualquier otro fallo. Salen dentro del mismo aviso.
  static const reintentoSinConexion = 'Necesitás conexión para hacer el respaldo.';
  static const reintentoFallido = 'No pudimos hacer el respaldo. Probá de nuevo en un rato.';

  // Los avisos de arriba de Configuración.
  static const avisoRevocado =
      'Google ya no nos deja guardar tu respaldo. Volvé a conectar tu Drive para no perder datos.';
  static const avisoCancelado = 'No conectamos tu Drive. Podés hacerlo cuando quieras.';

  // La hoja de conectar (16D·02, 03, 08, 09).
  static const tituloConectar = 'Respaldo en tu Google Drive';

  /// Texto previo al consentimiento, el de 16D·02 (decisión del agente de decisiones, regla R3:
  /// el canvas precisa a HU-SYNC-004, que se ajusta con docs#76).
  static const explicacionCifrado =
      'Guardamos una copia de tus datos en una carpeta oculta de tu Drive. Los archivos van '
      'cifrados, Google no los puede leer, y solo esta app los puede acceder.';

  /// Lo que dice el lector de pantalla de la fila con Drive conectado: tocarla abre las opciones.
  static const pistaDesconectar = 'Abre las opciones para desconectar';
  static const cadaNoche = 'Se respalda cada noche. Podés desconectarlo cuando quieras.';
  static const conectarConGoogle = 'Conectar con Google';
  static const conectando = 'Conectando…';
  static const ahoraNo = 'Ahora no';
  static const sinConexion = 'Necesitás conexión para conectar Google Drive.';

  // El éxito (16D·04): el de la HU si todavía no hay primer respaldo, el del canvas si lo hubo.
  static const exitoSinPrimerRespaldo = 'Backup configurado. Próximo backup nocturno.';
  static const exitoConPrimerRespaldo = 'Listo. Hicimos el primer respaldo en tu Drive.';

  // La hoja de desconectar (16D·05).
  static const tituloDesconectar = '¿Desconectar Google Drive?';
  static const textoDesconectar =
      'Los respaldos dejan de hacerse. Las copias que ya están en tu Drive no se borran: si '
      'querés, las borrás desde Drive.';
  static const desconectar = 'Desconectar';
  static const desconectando = 'Desconectando…';
  static const cancelar = 'Cancelar';
  static const noPudimosDesconectar = 'No pudimos desconectar tu Drive. Probá de nuevo.';

  // Otra cuenta de Google (16E·01 a 16E·04, #550).
  static const tituloOtraCuenta = 'Esta no es la cuenta de tu respaldo';
  static String textoOtraCuenta({required String anterior, required String nueva}) =>
      'Tu respaldo anterior quedó en $anterior. Ahora te conectaste con $nueva.';
  static const rotuloRespaldoAnterior = 'Respaldo anterior';
  static const rotuloUltimoRespaldo = 'Último respaldo';
  static const rotuloCuentaDeAhora = 'Cuenta de ahora';
  static const noSeBorraNada = 'No se borra nada: el respaldo anterior sigue en la otra cuenta.';
  static const volverALaCuentaAnterior = 'Volver a la cuenta anterior';
  static const seguirConLaCuentaNueva = 'Seguir con la cuenta nueva';
  static const tituloSeguirConLaNueva = '¿Seguir con la cuenta nueva?';
  static String textoSeguirConLaNueva({required String anterior, required String nueva}) =>
      'Desde esta noche el respaldo se guarda en $nueva. El anterior queda en $anterior: no se '
      'borra, pero deja de actualizarse.';
  static const volverALaAnterior = 'Volver a la anterior';
  static const sinConexionParaCambiarDeCuenta = 'Necesitás conexión para cambiar de cuenta.';
  static String volvioALaAnterior(String anterior) => 'Listo. Tu respaldo sigue en $anterior.';
  static const sinRespaldoEnEstaCuenta = 'Todavía sin respaldo en esta cuenta';

  /// Lo que dice el lector de pantalla de la fila con otra cuenta por confirmar (propuesta).
  static const pistaCuentaPorConfirmar = 'Abre las opciones para elegir con qué cuenta seguir';

  /// «20/10 · 03:10»: el último respaldo en la hoja de otra cuenta.
  static String fechaDelUltimoRespaldo(DateTime respaldo) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(respaldo.day)}/${dos(respaldo.month)} · ${dos(respaldo.hour)}:${dos(respaldo.minute)}';
  }

  // La franja del Drive en Hoy (16F·01 a 16F·04, #550).
  static const franjaRevocada =
      'Google ya no nos deja guardar tu respaldo. Lo que cargues desde ahora no tiene copia.';
  static const franjaReconectarEnConfiguracion = 'Reconectar en Configuración';
  static const franjaDriveLleno = 'Tu Drive está lleno. El respaldo de anoche no se guardó.';
  static const franjaVerEnConfiguracion = 'Ver en Configuración';
  static const franjaOculta = 'Te lo recordamos mañana. Lo ves en Configuración.';

  /// La franja de Hoy con otra cuenta por confirmar: el respaldo está frenado hasta que elija
  /// (decisión del 23/11, R7, #739).
  static const franjaFrenada = 'Tu respaldo está frenado: elegí con qué cuenta de Google seguir.';
  static const franjaElegirCuenta = 'Elegir cuenta';

  /// El botón de la hoja de otra cuenta para dejar el Drive desconectado hasta decidir (decisión del
  /// 23/11, R6, #739).
  static const desconectarDrive = 'Desconectar Drive';

  /// Cómo se cierra la franja (el canvas solo dibuja el resultado, 16F·04): propuesta.
  static const ocultarHastaManiana = 'Ocultar hasta mañana';

  /// Si no se pudo anotar que se ocultó (propuesta): la franja sigue a la vista.
  static const noPudimosOcultar = 'No pudimos ocultar el aviso. Probá de nuevo.';

  /// El engranaje de Hoy con la marca roja mientras la franja está oculta y el problema sigue
  /// (16F·04): propuesta para el lector de pantalla.
  static const configuracionConAviso = 'Configuración: hay un aviso del respaldo';
}
