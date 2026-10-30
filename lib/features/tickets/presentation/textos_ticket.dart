/// Los textos de la vista 29 C, «Foto del ticket de tarjeta» (HU-COB-007, artboards 29C-01 a 29C-08), y
/// del paso «Datos del ticket» (campos de 38A-01). Los del canvas, tal cual; los que el canvas no
/// dibuja, decididos como están y anotados en el PR (archivo de pendientes del issue #427).
abstract final class TextosTicket {
  // --- Del canvas 29 C ---
  static const eyebrow = 'TICKET DE TARJETA';
  static const encuadra = 'Encuadrá el ticket entero dentro del marco';
  static const sacarFoto = 'Sacar foto';

  /// La pregunta es la de la HU («¿Se lee bien el ticket?»); el canvas dice «…el texto?». Manda la HU.
  static const seLeeBien = '¿Se lee bien el ticket?';
  static const revisa = 'Revisá que se lean el monto, la fecha y el número de aprobación.';
  static const seLeeBienSubir = 'Se lee bien, subir';
  static const sacarOtra = 'Sacar otra';
  static const vistaPrevia = 'Vista previa del ticket, con el texto a tamaño real';
  static const subiendoTitulo = 'Subiendo el ticket';
  static const subiendo = 'Subiendo…';
  static const subidoTitulo = 'Ticket subido';
  static const subidoTuCoordinador = 'Tu coordinador lo va a revisar';
  static const subidoAvisamos = 'Te avisamos cuando lo valide. Queda guardado 4 meses.';
  static const copiaEnElTelefono = 'Copia en este teléfono';
  static const borrar = 'Borrar';
  static const listo = 'Listo';
  static const enColaTitulo = 'Ticket guardado';
  static const sinConexion =
      'Sin conexión. El ticket queda en cola y se sube solo cuando vuelva la red.';
  static const esperandoConexion = 'Esperando conexión';
  static const enCola = 'En cola';
  static const noSePudoSubir = 'No se pudo subir';
  static const errorAlSubir =
      'No pudimos subir el ticket. Lo guardamos en el teléfono y lo reintentamos solo.';
  static const reintentarAhora = 'Reintentar ahora';
  static const sinCamaraTitulo = 'Necesitamos la cámara';
  static const sinCamara =
      'Para sacarle foto al ticket, permití que Colportaje use la cámara en los ajustes del teléfono.';
  static const abrirAjustes = 'Abrir ajustes';
  static const despues = 'Después';
  static const borrarCopiaTitulo = '¿Borrar la copia de este teléfono?';
  static const borrarCopiaTexto =
      'El ticket sigue en el servidor por 4 meses y tu coordinador lo puede revisar.';
  static const borrarCopia = 'Borrar copia';
  static const cancelar = 'Cancelar';

  /// «Ticket del 23/10 · $ 1.200» (29C-05).
  static String ticketDel(String dia, String monto) => 'Ticket del $dia · $monto';

  /// «480 KB» (29C-04): el peso de la copia, con el KB entero hacia arriba.
  static String peso(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1).replaceFirst('.', ',')} MB';
    }
    return '${(bytes / 1024).ceil().clamp(1, 1 << 30)} KB';
  }

  // --- Del canvas 38A-01 (paso «Datos del ticket») ---
  static const datosTitulo = 'Datos del ticket';
  static const monto = 'MONTO';
  static const montoHint = r'$ 0';
  static const fecha = 'FECHA';
  static const cambiar = 'Cambiar';
  static const autorizacion = 'Nº DE AUTORIZACIÓN';
  static const tarjeta = 'TARJETA';
  static const marca = 'MARCA (OPCIONAL)';
  static const enviarTicket = 'Enviar ticket';
  static const enviando = 'Enviando…';
  static const ingresaElMonto = 'Ingresá el monto del ticket.';
  static const fotoDelTicket = 'Foto del ticket · tocá para cambiarla';

  // --- Sin dibujo en el canvas (texto y accesibilidad; decididos como están) ---
  static const elegirDeLaGaleria = 'Elegir de la galería';
  static const masCalidad = 'Probar con más calidad';
  static const preparando = 'Preparando la foto…';
  static const fotoIlegible =
      'No pudimos preparar esa foto. Sacá otra, con el ticket entero y bien de cerca.';
  static const camaraFallo =
      'No pudimos abrir la cámara. Probá de nuevo o elegí una foto de la galería.';
  static const galeriaFallo = 'No pudimos abrir la galería. Probá de nuevo.';
  static const faltaLaAutorizacion = 'Falta el número de autorización.';
  static const autorizacionHint = 'Lo dice el ticket';
  static const fechaFutura = 'La fecha del ticket no puede ser de mañana.';
  static const hojaDeLaFecha = '¿De qué día es el ticket?';
  static const fechaPista = 'No puede ser de mañana.';
  static const tipoDeTarjeta = 'Tipo de tarjeta';
  static const marcaOtraRotulo = 'OTRA MARCA';
  static const marcaOtraHint = 'Escribí la marca';
  static const errorAlGuardar =
      'No pudimos guardar el ticket en tu teléfono. No se cargó nada: probá de nuevo.';
  static const cobroConTicket = 'Este cobro ya tiene su ticket, o ya no está. Volvé atrás.';
  static const reintentar = 'Reintentar';
  static const reintentando = 'Reintentando…';
  static const ticketEnviado = 'Ticket enviado';
  static const errorDeLectura =
      'No pudimos leer el ticket guardado en tu teléfono. Está guardado: probá de nuevo en un rato.';
  static const copiaSinSubir =
      'Esta foto todavía no subió. Cuando haya conexión sube sola y ahí podés borrarla.';
  static const loRevisaAdministracion = 'Lo revisa Administración';
  static const rechazadaTitulo = 'No se pudo subir';
  static const rechazada =
      'El servidor no aceptó esta foto y no se va a reintentar. Avisale a tu coordinador.';
  static const cargandoElTicket = 'Cargando el ticket';
  static const volver = 'Volver';
  static const cerrar = 'Cerrar';
  static const fotoDelTicketSemantica = 'Foto del ticket';
  static const noSePudoBorrar = 'No pudimos borrar la copia. Probá de nuevo.';
  static const copiaBorrada = 'Copia borrada de este teléfono.';
  static const sacarFotoDelTicket = 'Sacar foto del ticket';

  /// El aviso de «el monto no coincide con el cobro» (HU-COB-007): avisa y no bloquea.
  static String montoDistinto(String monto, String cobro) =>
      'El monto del ticket ($monto) no coincide con el cobro ($cobro). Revisalo; si es correcto, '
      'podés enviarlo igual.';
}
