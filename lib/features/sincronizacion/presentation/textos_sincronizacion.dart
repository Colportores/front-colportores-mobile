import '../domain/entities/estado_sincronizacion.dart';

/// Los textos de la vista 25 (HU-SYNC-007, HU-SYNC-008). Salen del canvas
/// (`25 Sincronizacion.dc.html`, 25-01 a 25-11) salvo los marcados «propuesta»: el canvas no los
/// dibuja y están para confirmar.
abstract final class TextosSincronizacion {
  static const eyebrow = 'CONFIGURACIÓN';
  static const titulo = 'Sincronización y respaldo';

  /// La fila de Configuración que abre la pantalla. Propuesta: el canvas de la vista 16 de `main`
  /// todavía no la dibuja (el mapa de navegación la ubica en «Respaldo → Sincronización»).
  static const filaConfiguracion = 'Sincronización y respaldo';
  static const filaConfiguracionDetalle = 'Estado, actualizar ahora y modo ahorro de datos';
  static const seccionConfiguracion = 'Sincronización';

  // --- La tarjeta grande (25-01, 02, 03, 06) ---
  static const alDia = 'Todo al día';
  static const alDiaDetalle = 'Tu avance llegó y tenés lo último de tu coordinador.';

  /// Propuesta: al día pero el teléfono todavía no trajo cambios desde que se abrió la app.
  static const alDiaSinActualizacion =
      'Tu avance llegó. Tocá «Actualizar ahora» para traer lo último de tu coordinador.';

  /// Propuesta: al día, pero el modo ahorro dejó la bajada de cambios esperando al Wi-Fi (el
  /// canvas, 25-08, dice «lo último de tu coordinador» y no sería cierto).
  static const alDiaConActualizacionEnEspera =
      'Tu avance llegó. Lo nuevo de tu coordinador espera al Wi-Fi.';
  static const pendientesDetalle = 'Se envían solas cuando haya conexión.';
  static const actualizando = 'Actualizando…';

  /// Propuesta: la parte de bajar los cambios, cuando ya no queda nada por enviar.
  static const trayendoCambios = 'Trayendo los cambios de tu coordinador…';
  static const conErrorDetalle = 'El resto está al día.';

  static String pendientes(int n) =>
      n == 1 ? '1 operación sin enviar' : '$n operaciones sin enviar';

  static String enviando(int actual, int total) =>
      'Enviando $actual de $total · después traemos los cambios';

  static String conError(int n) =>
      n == 1 ? '1 operación no se pudo enviar' : '$n operaciones no se pudieron enviar';

  /// Propuesta: hay rechazadas y además otras que todavía esperan salir.
  static String conErrorYPendientes(int pendientes) => pendientes == 1
      ? 'Hay 1 operación más esperando para enviarse.'
      : 'Hay $pendientes operaciones más esperando para enviarse.';

  // --- Las cifras ---
  static const filaUltimoEnvio = 'Último envío';
  static const filaPendientes = 'Pendientes de enviar';
  static const filaUltimaActualizacion = 'Última actualización recibida';
  static const filaUltimoRespaldo = 'Último respaldo';
  static const respaldoNunca = 'nunca';

  /// Propuesta: el teléfono no tiene el dato (el motor lo guarda en memoria desde que se abre la
  /// app, decisión del 26/10 en #182): no se dice «nunca» si no se sabe.
  static const todaviaNoHubo = 'Todavía no hubo';
  static const esperaWifi = 'espera Wi-Fi';
  static const destinoRespaldo = 'Google Drive';

  // --- Los avisos ---
  static const sinConexion =
      'Sin conexión. Lo pendiente se envía solo cuando vuelva; podés seguir trabajando.';
  static const errorAlActualizar =
      'No pudimos actualizar: el servidor no responde. Lo pendiente sigue guardado en tu teléfono.';

  /// Propuesta: el servidor contesta que la sesión no vale (`401`) y reintentar no lo arregla.
  static const sesionSinRenovar =
      'No pudimos renovar tu sesión, así que no se puede enviar lo pendiente. Lo pendiente sigue '
      'guardado en tu teléfono: cerrá sesión y volvé a entrar.';
  static const modoAhorroConDatos =
      'Modo ahorro con datos móviles: la actualización y el respaldo esperan al Wi-Fi. Ventas y '
      'cobros se envían igual.';
  static const sinRespaldo =
      'Tus datos no tienen respaldo. Conectá tu Google Drive para no perderlos si le pasa algo al '
      'teléfono.';
  static const conectarDrive = 'Conectar Google Drive';

  /// Propuesta: no se pudo leer el estado.
  static const errorAlLeer = 'No pudimos revisar el estado de la sincronización.';
  static const reintentarLectura = 'Reintentar';

  // --- El modo ahorro ---
  static const modoAhorro = 'Modo ahorro de datos';
  static const modoAhorroDetalle =
      'Las actualizaciones y los respaldos esperan al Wi-Fi. Ventas y cobros se envían igual.';

  /// Propuesta: el cambio no se pudo guardar y el modo vuelve a como estaba.
  static const modoAhorroNoGuardo = 'No pudimos guardar el cambio. Probá de nuevo.';

  // --- El botón ---
  static const actualizarAhora = 'Actualizar ahora';
  static const reintentar = 'Reintentar';

  static String reintentarFallidas(int n) =>
      n == 1 ? 'Reintentar la que falló' : 'Reintentar las $n';

  // --- Los avisos de éxito ---
  /// 25-04. Los demás son propuesta: el canvas solo dibuja el caso con envío y recepción.
  static String listo(ActualizacionCompleta r) {
    final partes = [
      if (r.enviadas > 0)
        r.enviadas == 1 ? 'enviamos 1 operación' : 'enviamos ${r.enviadas} operaciones',
      if (r.recibidas > 0)
        r.recibidas == 1 ? 'recibimos 1 cambio' : 'recibimos ${r.recibidas} cambios',
    ];
    final hecho = partes.isEmpty ? 'todo estaba al día' : partes.join(' y ');
    if (r.rechazadas > 0) {
      final no = r.rechazadas == 1
          ? '1 operación no se pudo enviar'
          : '${r.rechazadas} operaciones no se pudieron enviar';
      return 'Listo: $hecho, pero $no.';
    }
    return 'Listo: $hecho.';
  }

  // --- La lista de rechazadas y su detalle (25-06, 25-07) ---
  static const rechazadas = 'NO SE PUDIERON ENVIAR';
  static const detalleSinMotivo = 'El servidor la rechazó.';
  static const detalleCerrar = 'Cerrar';
  static const detalleReintentar = 'Reintentar';
  static const filaTipo = 'Tipo';
  static const filaFecha = 'Fecha';
  static const filaCodigo = 'Código';
  static const errorAlLeerFallidas = 'No pudimos mostrar las operaciones que no se enviaron.';

  static String detalleTexto(String error) {
    final motivo = error.trim();
    if (motivo.isEmpty) {
      return 'El servidor rechazó esta operación. Si el dato ya se corrigió, tocá «Reintentar».';
    }
    final conPunto = RegExp(r'[.!?…]$').hasMatch(motivo) ? motivo : '$motivo.';
    return 'El servidor la rechazó: $conPunto Si el dato ya se corrigió, tocá «Reintentar».';
  }

  static String tipo(TipoOperacion tipo) => switch (tipo) {
    TipoOperacion.alta => 'Alta',
    TipoOperacion.cambio => 'Cambio',
    TipoOperacion.baja => 'Baja',
  };

  /// «Venta del 22/10»: de qué es la operación y cuándo se hizo, sin los datos de la fila.
  static String tituloOperacion(OperacionFallida f, String fecha) =>
      '${nombreDeLaTabla(f.tabla)} del $fecha';

  static String nombreDeLaTabla(String tabla) => switch (tabla) {
    'venta' => 'Venta',
    'cobranza' || 'cobro' => 'Cobro',
    'visita' => 'Visita',
    'agenda' => 'Cita de la agenda',
    'jornada' => 'Jornada',
    'ubicacion' => 'Ubicación',
    'espacio' => 'Espacio',
    'espacio_persona' => 'Persona de un espacio',
    'ubicacion_par_decidido' => 'Decisión de posibles duplicados',
    'house_status' => 'Estado de una casa',
    'entrega' => 'Entrega',
    '' => 'Operación',
    _ => _humanizar(tabla),
  };

  static String _humanizar(String nombre) {
    final s = nombre.replaceAll('_', ' ').trim();
    return s.isEmpty ? 'Operación' : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  // --- La hoja de datos móviles (25-09) ---
  static const datosTitulo = '¿Actualizar con datos móviles?';
  static const datosTexto =
      'Tenés el modo ahorro activo. Traer las actualizaciones puede gastar unos 2 MB; el respaldo '
      'sigue esperando al Wi-Fi.';
  static const datosActualizarIgual = 'Actualizar igual';
  static const datosEsperarWifi = 'Esperar al Wi-Fi';
}
