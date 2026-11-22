/// Los textos de la ubicación alternativa de cobranza (HU-UBI-013, vista 22 grupo A). Los rótulos y los
/// avisos son los del canvas, tal cual; el canvas manda sobre el texto de la HU cuando difieren.
///
/// Los que el canvas no dibuja (el aviso al quitar, los errores de lectura, la alternativa que no está
/// en el teléfono) están marcados «a confirmar»: salen de un archivo de pendientes, no de la vista.
abstract final class TextosUbicacionAlternativa {
  // ---- Escenarios de la HU (los rótulos de las acciones de la HU).

  /// Acción de la ficha de la persona (escenario «Asignar ubicación alternativa existente»).
  static const establecer = 'Establecer ubicación alternativa de cobranza';

  /// Escenario «Quitar ubicación alternativa».
  static const quitar = 'Quitar ubicación alternativa';

  /// Banner del escenario «alternativa dada de baja»; HU-VIS no la sugiere.
  static const bannerDeBaja = 'Ubicación alternativa dada de baja';

  /// Regla de negocio: lo que muestra la persona cuando la referenciada se dio de baja (texto de la HU;
  /// la ficha usa el del canvas, [avisoDeBajaCanvas]).
  static const avisoDeBaja =
      'Ubicación alternativa dada de baja — actualizar antes de agendar cobranza';

  /// Escenario «sin otras ubicaciones registradas»: el estado vacío del selector (la HU; el canvas lo
  /// dibuja con [vacioTitulo] y [vacioDetalle]).
  static const sinOtrasUbicaciones = 'Registrá otra ubicación para usarla como alternativa';

  // ---- La ficha de la persona (22A·01, 22A·06, 22A·08, 22A·09).

  /// El rótulo de la sección de la ficha.
  static const rotuloSeccion = 'COBRANZA';

  static const sinAlternativaTitulo = 'Cobrar en otro lugar';
  static const sinAlternativaDetalle =
      'Si acepta que le cobres en su trabajo u otra dirección que ya registraste.';
  static const elegir = 'Elegir';
  static const guardando = 'Guardando…';

  static const seCobraAca = 'SE COBRA ACÁ';
  static const dadaDeBajaRotulo = 'DADA DE BAJA';

  /// 22A·08: el aviso de la alternativa dada de baja (el texto del canvas, con su guion).
  static const avisoDeBajaCanvas =
      'Ubicación alternativa dada de baja - actualizá antes de cobrar acá';
  static const elegirOtra = 'Elegir otra';

  /// 22A·09: no se pudo escribir en el teléfono.
  static const noPudimosGuardar =
      'No pudimos guardar la ubicación alternativa en tu teléfono. Probá de nuevo.';
  static const reintentar = 'Reintentar';

  /// A confirmar: la referencia guardada no está en el teléfono (el sync no garantiza el orden, o se
  /// recuperó la cuenta sin copia). No se afirma que esté de baja.
  static const faltanteRotulo = 'NO ESTÁ EN TU TELÉFONO';
  static const faltanteTitulo = 'Ubicación alternativa';
  static const avisoFaltante =
      'No encontramos la ubicación alternativa en tu teléfono. Elegí otra o quitala.';

  /// A confirmar: la lectura de dónde se le cobra falló.
  static String noPudimosLeer(String nombre) =>
      'No pudimos leer dónde se le cobra a $nombre. Probá de nuevo.';

  static String cargando(String nombre) => 'Cargando dónde se le cobra a $nombre';

  /// 22A·06: la alternativa quedó vinculada. [direccion] es la de la ubicación elegida.
  static String vinculada(String nombre, String direccion) =>
      'Las cobranzas de $nombre se van a proponer en $direccion.';

  /// 22A·10: sin conexión el vínculo igual se guarda (vive en el teléfono) y se sube al volver la red.
  static const guardadoEnElTelefono = 'Guardado en tu teléfono.';

  /// A confirmar: se quitó la alternativa (el canvas no dibuja el aviso).
  static String quitada(String nombre) => 'Las cobranzas de $nombre se van a proponer en su casa.';

  // ---- El selector (22A·02 a 22A·05).

  static const selectorRotulo = 'COBRAR EN OTRO LUGAR';
  static const selectorTitulo = '¿Dónde le cobrás?';
  static const selectorSubtitulo = 'Elegí una de tus ubicaciones. Si no está, registrala primero.';
  static const buscar = 'Buscar por dirección o nombre';
  static const limpiarBusqueda = 'Borrar la búsqueda';
  static const cerrar = 'Cerrar';

  /// El rótulo de la lista: con GPS van por cercanía; sin él, el rótulo no promete lo que no hay.
  static const listaPorCercania = 'TUS UBICACIONES · POR CERCANÍA';
  static const lista = 'TUS UBICACIONES';

  static const registrarMas = '+ Registrar una ubicación';
  static const registrar = 'Registrar una ubicación';

  static const vacioTitulo = 'No tenés otra ubicación para elegir';
  static const vacioDetalle =
      'Registrá primero el lugar donde le vas a cobrar (por ejemplo, su trabajo) y volvé a esta ficha.';

  static const sinResultadosTitulo = 'Ninguna ubicación coincide';
  static const sinResultadosDetalle = 'Probá con otra parte de la dirección o registrala.';

  /// A confirmar: la lectura de las ubicaciones del selector falló.
  static const noPudimosLeerUbicaciones =
      'No pudimos leer tus ubicaciones en tu teléfono. Probá de nuevo.';

  static const cargandoUbicaciones = 'Cargando tus ubicaciones';

  /// 22A·02: «a 1,2 km».
  static String aDistancia(String distancia) => 'a $distancia';

  // ---- Quitar (22A·07).

  /// El título de la hoja; [direccion] es la de la ubicación que se quita.
  static String quitarTitulo(String direccion) => '¿Quitar $direccion?';

  /// Cuando la referencia no se puede nombrar (no está en el teléfono).
  static const quitarTituloSinNombre = '¿Quitar la ubicación alternativa?';

  /// El cuerpo de la hoja: [casa] es dónde vive la persona («Mataojo 2044 · Depto 3B»).
  static String quitarCuerpo(String nombre, String? casa) {
    final donde = casa == null || casa.isEmpty ? 'su casa' : 'su casa, $casa';
    return 'Las próximas cobranzas de $nombre se van a proponer en $donde. '
        'Las que ya agendaste no cambian.';
  }

  static const quitarAccion = 'Quitar';
  static const quitando = 'Quitando…';
  static const cancelar = 'Cancelar';

  /// A confirmar: no se pudo quitar.
  static String noPudimosQuitar(String nombre) =>
      'No pudimos quitar la ubicación alternativa de $nombre. Probá de nuevo.';

  // ---- Lector de pantalla.

  static String semanticaQuitar(String direccion) => 'Quitar la ubicación alternativa $direccion';
  static String semanticaElegirFila(String direccion, String tipo, String? distancia) =>
      distancia == null ? '$direccion, $tipo' : '$direccion, $tipo, a $distancia';
}
