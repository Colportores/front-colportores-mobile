/// Los textos del respaldo en Drive (HU-SYNC-004, vista 16 «Cuenta Drive», artboards 16D·01 a
/// 16D·10).
///
/// Los literales de la HU van tal cual; el resto es el del canvas. Los que no están en ninguno de
/// los dos (estado «Revisando…», «No pudimos ver el estado», «Todavía no hubo un respaldo»,
/// «No pudimos desconectar…») son propuesta: mapa §2, texto, a confirmar.
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
}
