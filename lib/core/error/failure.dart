import 'package:equatable/equatable.dart';

/// Resultado negativo de un caso de uso.
///
/// El dominio **nunca lanza excepciones** (convenciones §4.3): devuelve `Either<Failure, T>`.
/// Al ser `sealed`, un `switch` sobre un [Failure] es exhaustivo — la UI está obligada a
/// contemplar cada caso.
///
/// Ningún `Failure` transporta PII: [mensaje] es texto para el usuario y [codigo] un identificador
/// estable para logs y telemetría.
sealed class Failure extends Equatable {
  const Failure({required this.mensaje, required this.codigo});

  /// Texto apto para mostrar al usuario final.
  final String mensaje;

  /// Código estable (`MODULO_MOTIVO`) para logs. Nunca contiene datos personales.
  final String codigo;

  @override
  List<Object?> get props => [mensaje, codigo];

  @override
  String toString() => '$runtimeType($codigo)';
}

/// Datos de entrada inválidos, con el detalle por campo para que el formulario lo muestre.
final class FailureValidacion extends Failure {
  const FailureValidacion({required this.campos, super.mensaje = 'Revisá los datos ingresados'})
    : super(codigo: 'VALIDACION');

  /// `nombreDelCampo → mensaje`.
  final Map<String, String> campos;

  @override
  List<Object?> get props => [...super.props, campos];
}

/// Email o contraseña incorrectos. No distingue cuál, a propósito.
final class FailureCredencialesInvalidas extends Failure {
  const FailureCredencialesInvalidas()
    : super(mensaje: 'Email o contraseña incorrectos', codigo: 'AUTH_CREDENCIALES');
}

/// Ya existe una cuenta con ese correo (HU-AUTH-001, "Error - email ya registrado"). Solo lo usa
/// el registro (nunca el login): el mensaje literal del criterio de aceptación es seguro acá.
final class FailureEmailYaRegistrado extends Failure {
  const FailureEmailYaRegistrado()
    : super(
        mensaje:
            'Ya existe una cuenta con ese email. ¿Querés iniciar sesión o recuperar tu '
            'contraseña?',
        codigo: 'AUTH_EMAIL_DUPLICADO',
      );
}

/// Pasaron 30 días sin actividad de red y la sesión venció (HU-AUTH-007, "Expiración por
/// inactividad"). Los datos locales siguen intactos: se abren al volver a entrar.
final class FailureSesionExpiradaPorInactividad extends Failure {
  const FailureSesionExpiradaPorInactividad()
    : super(
        mensaje: 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.',
        codigo: 'AUTH_SESION_INACTIVA',
      );
}

/// El servidor ya no acepta la sesión: se revocó (cambio de contraseña, cierre en todos los
/// equipos) o venció de su lado (HU-AUTH-007, "Edge - backend revocó la sesión"). La HU no fija el
/// texto: es la propuesta de la vista 17 (17-A03); los datos locales siguen intactos.
final class FailureSesionRevocada extends Failure {
  const FailureSesionRevocada()
    : super(
        mensaje:
            'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la '
            'contraseña. Entrá de nuevo.',
        codigo: 'AUTH_SESION_REVOCADA',
      );
}

/// Se cerró la sesión en este teléfono pero no había conexión para revocarla en el servidor
/// (HU-AUTH-006, "Logout sin conexión"): la revocación queda pendiente y se reintenta sola. El
/// login lo muestra como aviso; los datos locales siguen intactos.
final class FailureCierreSesionSinConexion extends Failure {
  const FailureCierreSesionSinConexion()
    : super(
        mensaje:
            'Cerraste sesión en este teléfono. Se va a cerrar por completo cuando haya conexión.',
        codigo: 'AUTH_CIERRE_SIN_CONEXION',
      );
}

/// El enlace de recuperación de contraseña ya no sirve (HU-AUTH-005, "Error - token expirado"):
/// venció, ya se usó o se abrió en otro teléfono. Supabase no distingue vencido de usado (mismo
/// `otp_expired`), así que la app tampoco. [mensaje] es el literal de la HU; la pantalla ofrece
/// pedir un enlace nuevo (HU-AUTH-004).
final class FailureEnlaceRecuperacionVencido extends Failure {
  const FailureEnlaceRecuperacionVencido()
    : super(mensaje: 'El enlace expiró. Solicitá uno nuevo.', codigo: 'AUTH_ENLACE_VENCIDO');
}

/// El login fue rechazado porque la cuenta todavía no confirmó su correo (HU-AUTH-002, Supabase
/// `email_not_confirmed`). [mensaje] es el texto que ya veía el login. Además del login, la usa el
/// login en silencio que decide qué pasó con un enlace de verificación `otp_expired`: si la cuenta
/// sigue sin confirmar, el enlace de verdad expiró.
final class FailureEmailNoVerificado extends Failure {
  const FailureEmailNoVerificado()
    : super(
        mensaje: 'Tenés que verificar tu correo antes de entrar. Revisá tu bandeja.',
        codigo: 'AUTH_EMAIL_NO_VERIFICADO',
      );
}

/// El colportor ya tiene una jornada en curso (HU-JOR-001: "solo una jornada activa a la vez").
/// [mensaje] es el texto literal del criterio de aceptación "Bloqueo - jornada ya activa".
final class FailureJornadaActiva extends Failure {
  const FailureJornadaActiva()
    : super(
        mensaje: 'Tenés una jornada en curso. Cerrala antes de iniciar otra.',
        codigo: 'JOR_JORNADA_ACTIVA',
      );
}

/// El colportor quiso finalizar una jornada, pero no tiene ninguna en curso (HU-JOR-002): ya la
/// cerró —dos toques seguidos en "Finalizar jornada"— o nunca la inició.
final class FailureSinJornadaActiva extends Failure {
  const FailureSinJornadaActiva()
    : super(mensaje: 'No tenés una jornada en curso para finalizar.', codigo: 'JOR_SIN_JORNADA');
}

/// La hora elegida a mano para una jornada cae fuera del rango permitido (HU-JOR-001: "editable
/// hasta 30 minutos hacia atrás", decisión de Cristian del 23/09 en #70). [mensaje] trae el rango
/// explícito en hora local ("La hora tiene que estar entre las 14:05 y las 14:35."), para que el
/// colportor sepa qué elegir: la hora nunca se ajusta en silencio.
final class FailureHoraFueraDeRango extends Failure {
  FailureHoraFueraDeRango({required this.desde, required this.hasta})
    : super(
        mensaje:
            'La hora tiene que estar entre las ${_horaLocal(desde)} y las ${_horaLocal(hasta)}.',
        codigo: 'JOR_HORA_FUERA_DE_RANGO',
      );

  /// Primer instante válido (incluido).
  final DateTime desde;

  /// Último instante válido (incluido).
  final DateTime hasta;

  @override
  List<Object?> get props => [...super.props, desde, hasta];

  /// `HH:MM` en la zona del dispositivo: la hora que el colportor ve en su reloj.
  static String _horaLocal(DateTime instante) {
    final local = instante.toLocal();
    String dosDigitos(int n) => n.toString().padLeft(2, '0');
    return '${dosDigitos(local.hour)}:${dosDigitos(local.minute)}';
  }
}

/// La jornada en curso empezó un día anterior (HU-JOR-002, "Jornada que quedó abierta"): no se
/// cierra con la hora de hoy, porque eso inventaría un `fin` y sumaría horas que no se trabajaron.
/// Se cierra con la corrección de la HU —"¿A qué hora terminaste?", entre el inicio y las 23:59 de
/// ese día—, que es otra pantalla. [mensaje] nombra el día en la zona del dispositivo ("Tenés una
/// jornada del lunes 21 sin cerrar.", como la HU).
final class FailureJornadaDeDiaAnterior extends Failure {
  FailureJornadaDeDiaAnterior({required this.inicio})
    : super(
        mensaje:
            'Tenés una jornada del ${_dia(inicio)} sin cerrar. No la cerramos con la hora de hoy '
            'para no sumarle horas que no trabajaste: hay que indicar a qué hora terminaste ese '
            'día.',
        codigo: 'JOR_JORNADA_DIA_ANTERIOR',
      );

  /// Inicio de la jornada que quedó abierta.
  final DateTime inicio;

  @override
  List<Object?> get props => [...super.props, inicio];

  static const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  /// `lunes 21`, en la zona del dispositivo.
  static String _dia(DateTime instante) {
    final local = instante.toLocal();
    return '${_dias[local.weekday - 1]} ${local.day}';
  }
}

/// No se pudo armar el resumen de lo guardado en el teléfono por una falla inesperada. Se puede
/// reintentar; nada se borró.
final class FailureDatosLocalesIlegibles extends Failure {
  const FailureDatosLocalesIlegibles()
    : super(
        mensaje:
            'No pudimos revisar los datos de este teléfono. No se borró nada: reintentá en un '
            'momento.',
        codigo: 'DATOS_LOCALES_ILEGIBLES',
      );
}

/// No hay red o el servidor no respondió. La operación puede reintentarse.
final class FailureSinConexion extends Failure {
  const FailureSinConexion()
    : super(mensaje: 'Sin conexión. Reintentá cuando tengas señal', codigo: 'NET_SIN_CONEXION');
}

/// El servidor respondió con error (5xx, contrato roto, etc.). [mensaje] se puede reemplazar
/// cuando el origen sabe qué decirle al usuario (p. ej. "confirmá tu email"), igual que en
/// [FailureValidacion]; el código no cambia.
final class FailureServidor extends Failure {
  const FailureServidor({this.status, super.mensaje = 'El servidor no pudo procesar la solicitud'})
    : super(codigo: 'NET_SERVIDOR');

  final int? status;

  @override
  List<Object?> get props => [...super.props, status];
}

/// Cualquier cosa no prevista. [causa] va solo a logs, nunca al usuario.
final class FailureInesperado extends Failure {
  const FailureInesperado({this.causa})
    : super(mensaje: 'Ocurrió un error inesperado', codigo: 'INESPERADO');

  final Object? causa;

  @override
  List<Object?> get props => [...super.props, causa];
}

/// El almacén seguro del dispositivo (Keystore/Keychain) falló, o lo que guarda no se puede
/// interpretar (HU-AUTH-009). El mensaje es el de la HU con el cambio que decidió Cristian el 25/09
/// (#26): en Android reinstalar borra la DB, así que dice "consultá a soporte antes de reinstalar".
final class FailureAlmacenSeguro extends Failure {
  const FailureAlmacenSeguro()
    : super(
        mensaje:
            'No pudimos preparar el almacenamiento seguro. Consultá a soporte antes de '
            'reinstalar la app.',
        codigo: 'DB_ALMACEN_SEGURO',
      );
}

/// No hay espacio en disco para crear la DB local (HU-AUTH-009). El mensaje es el que fija la HU.
final class FailureSinEspacio extends Failure {
  const FailureSinEspacio()
    : super(mensaje: 'No hay espacio suficiente para preparar el app', codigo: 'DB_SIN_ESPACIO');
}

/// La DEK que guarda el almacén seguro no abre la DB local que hay en el dispositivo: el archivo o
/// el almacén se corrompieron (ADR-006). **No se borra nada**: los datos siguen en el archivo.
final class FailureClaveDbIncorrecta extends Failure {
  const FailureClaveDbIncorrecta()
    : super(
        mensaje:
            'No pudimos abrir los datos guardados en este teléfono. No se borró nada: consultá a '
            'soporte antes de reinstalar la app.',
        codigo: 'DB_CLAVE_INCORRECTA',
      );
}

/// El equipo no tiene bloqueo de pantalla (PIN, patrón, contraseña ni biometría), y sin él no se
/// inicializa la DB local (ADR-006, HU-AUTH-009). [mensaje] explica por qué y cómo configurarlo.
final class FailureSinBloqueoPantalla extends Failure {
  const FailureSinBloqueoPantalla()
    : super(
        mensaje:
            'Para proteger los datos de tus clientes, tu teléfono necesita un bloqueo de pantalla. '
            'Configurá un PIN, un patrón, una contraseña o tu huella en los ajustes de seguridad '
            'del teléfono y volvé a intentar.',
        codigo: 'DB_SIN_BLOQUEO_PANTALLA',
      );
}

/// El Keystore del equipo es por software (Supuesto S10, HU-AUTH-009): hace falta el consentimiento
/// explícito del usuario para seguir. No es un error: la UI muestra la advertencia (el [mensaje] es
/// el texto literal de la HU) con "Entiendo el riesgo y quiero continuar" y "Cancelar".
final class FailureAlmacenPocoSeguro extends Failure {
  const FailureAlmacenPocoSeguro()
    : super(
        mensaje:
            'Tu dispositivo tiene almacenamiento menos seguro. Los datos siguen cifrados pero el '
            'nivel de protección es menor.',
        codigo: 'DB_ALMACEN_SOFTWARE',
      );
}

/// La DB local es de una versión más nueva de la app (HU-AUTH-009): no se migra ni se borra. La UI
/// muestra una pantalla bloqueante con el botón **Actualizar** y no ofrece empezar de nuevo.
final class FailureEsquemaPosterior extends Failure {
  const FailureEsquemaPosterior()
    : super(
        mensaje:
            'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
            'datos.',
        codigo: 'DB_ESQUEMA_POSTERIOR',
      );
}

/// El almacén seguro falló (o perdió la DEK) con la DB en el teléfono, y hay un envoltorio por
/// contraseña: la DEK se recupera con la contraseña (recuperación guiada de ADR-006, texto literal
/// del ADR). No se borró nada.
final class FailureAlmacenSeguroRecuperable extends Failure {
  const FailureAlmacenSeguroRecuperable()
    : super(
        mensaje: 'Tu almacenamiento seguro falló. Ingresá tu contraseña para recuperar tus datos',
        codigo: 'DB_ALMACEN_RECUPERABLE',
      );
}

/// El almacén seguro falló (o perdió la DEK) con la DB en el teléfono, y **no** hay envoltorio por
/// contraseña (usuario de Google sin backup): ADR-006 muestra el mensaje de [FailureAlmacenSeguro]
/// y ofrece "empezar de nuevo", que avisa qué se pierde. **Nunca se borra sin ese sí.**
final class FailureAlmacenSeguroSinRecuperacion extends Failure {
  const FailureAlmacenSeguroSinRecuperacion()
    : super(
        mensaje:
            'No pudimos preparar el almacenamiento seguro. Consultá a soporte antes de '
            'reinstalar la app.',
        codigo: 'DB_ALMACEN_SIN_RECUPERACION',
      );
}

/// En la recuperación guiada (ADR-006), la contraseña no abre la DEK envuelta de este teléfono.
/// Puede ser la contraseña vieja: el envoltorio queda con la que había al armarlo si después se
/// cambió en otro lado (ADR-006, riesgos abiertos).
final class FailurePasswordNoAbreDatos extends Failure {
  const FailurePasswordNoAbreDatos()
    : super(
        mensaje:
            'Esa contraseña no abre tus datos guardados en este teléfono. Si la cambiaste hace '
            'poco, probá con la anterior.',
        codigo: 'DB_PASSWORD_NO_ABRE',
      );
}

/// La cuenta entra con contraseña pero no hay con qué armar el envoltorio de la DEK (sesión
/// restaurada, sin el login a mano): antes de crear la DB, o de dar por lista una que no lo tiene,
/// se pide la contraseña (revisión del PR #130, "ante la duda, bloquear"). Sin envoltorio, si el
/// almacén seguro falla solo queda "empezar de nuevo" (ADR-006). El texto es propio: para
/// confirmar.
final class FailurePasswordParaProteger extends Failure {
  const FailurePasswordParaProteger()
    : super(
        mensaje:
            'Para proteger tus datos, confirmá tu contraseña. Con ella vas a poder recuperarlos si '
            'este teléfono pierde su clave.',
        codigo: 'DB_FALTA_PASSWORD',
      );
}

/// La sesión se cerró (o no había) mientras se preparaba la DB local: no se abre nada sin sesión.
final class FailureSesionCerrada extends Failure {
  const FailureSesionCerrada()
    : super(
        mensaje: 'La sesión se cerró antes de terminar de preparar tus datos',
        codigo: 'AUTH_SESION_CERRADA',
      );
}

/// Por qué no hay una lectura de GPS utilizable (HU-UBI-001: "denegado, sin señal").
enum MotivoSinGps {
  /// El colportor no dio (o sacó) el permiso de ubicación.
  permisoDenegado,

  /// La ubicación del teléfono está apagada.
  servicioApagado,

  /// No llegó una posición a tiempo, o llegó `(0, 0)`, que se trata como sin GPS (caso borde de
  /// HU-UBI-001).
  sinSenal,
}

/// No hay GPS para el alta de ubicación (HU-UBI-001, "Alta sin GPS - colocación manual"): el alta
/// sigue con el marcador puesto a mano en el mapa. [motivo] le deja a la pantalla elegir el camino
/// (pedir el permiso, prender la ubicación o marcar a mano).
///
/// Texto para confirmar con Cristian: la HU no trae uno.
final class FailureGpsNoDisponible extends Failure {
  const FailureGpsNoDisponible({required this.motivo})
    : super(
        mensaje:
            'No pudimos tomar tu ubicación por GPS. Tocá "Marcar en el mapa" para ubicar el '
            'punto a mano.',
        codigo: 'UBI_SIN_GPS',
      );

  final MotivoSinGps motivo;

  @override
  List<Object?> get props => [...super.props, motivo];
}

/// El alta de ubicación llegó sin `ciudad_id` (HU-UBI-001, "Error - ciudad no en catálogo": "no
/// permite crear la ubicación sin `ciudad_id`"). La pantalla ofrece "Seleccionar ciudad
/// manualmente" o "Solicitar alta de ciudad al administrador".
///
/// Texto para confirmar con Cristian: la HU nombra las dos acciones, no el aviso.
final class FailureCiudadRequerida extends Failure {
  const FailureCiudadRequerida()
    : super(
        mensaje:
            'No encontramos la ciudad de este punto en el catálogo. Seleccionala a mano o pedile '
            'al administrador que la dé de alta.',
        codigo: 'UBI_SIN_CIUDAD',
      );
}

/// HU-UBI-007, "único espacio activo con personas": no se puede dar de baja el último espacio
/// activo de un edificio o negocio si tiene personas. El mensaje es el que fija la HU.
final class FailureUltimoEspacioConPersonas extends Failure {
  const FailureUltimoEspacioConPersonas()
    : super(
        mensaje:
            'No podés borrar el último espacio activo con personas. Agregá otro o reubicá las '
            'personas primero.',
        codigo: 'ESPACIO_ULTIMO_CON_PERSONAS',
      );
}

/// Se quiso pasar un `EDIFICIO` a `CASA` o `NEGOCIO` teniendo espacios activos (HU-UBI-004,
/// "Cambio de tipo bloqueado", Supuesto S17). Texto literal del criterio de aceptación.
final class FailureUbicacionConEspacios extends Failure {
  const FailureUbicacionConEspacios({required this.cantidadEspacios})
    : super(
        mensaje: 'Esta ubicación tiene $cantidadEspacios espacios. Borralos o reubicalos primero.',
        codigo: 'UBI_CON_ESPACIOS',
      );

  final int cantidadEspacios;

  @override
  List<Object?> get props => [...super.props, cantidadEspacios];
}

/// La ubicación que se quiso modificar no está en el teléfono.
final class FailureUbicacionInexistente extends Failure {
  const FailureUbicacionInexistente()
    : super(
        mensaje: 'No encontramos esta ubicación en tu teléfono. Volvé a la lista y probá de nuevo.',
        codigo: 'UBI_INEXISTENTE',
      );
}

/// La ubicación cambió (una edición, o el sync entrante) entre que se leyó para modificarla y que
/// se guardó: se descarta el guardado para no pisar el cambio (HU-UBI-004, "edición concurrente
/// con sync entrante"). La pantalla la vuelve a leer y el colportor reintenta.
final class FailureUbicacionCambio extends Failure {
  const FailureUbicacionCambio()
    : super(
        mensaje: 'Esta ubicación cambió mientras la editabas. Abrila de nuevo y repetí el cambio.',
        codigo: 'UBI_CAMBIO_CONCURRENTE',
      );
}

/// La ubicación cambió entre que se abrió y que se quiso darla de baja (HU-UBI-005): texto propio
/// para la baja, no el de la edición ([FailureUbicacionCambio]).
final class FailureBajaCambioReciente extends Failure {
  const FailureBajaCambioReciente()
    : super(
        mensaje: 'Esta ubicación cambió recién. Abrila de nuevo y volvé a darla de baja.',
        codigo: 'UBI_BAJA_CAMBIO_RECIENTE',
      );
}

/// La ubicación cambió entre que "Ver bajas" la cargó y que se quiso reactivarla (HU-UBI-005).
final class FailureReactivacionCambioReciente extends Failure {
  const FailureReactivacionCambioReciente()
    : super(
        mensaje: 'Esta ubicación cambió recién. Abrila de nuevo y volvé a reactivarla.',
        codigo: 'UBI_REACTIVACION_CAMBIO_RECIENTE',
      );
}

/// Al marcar un duplicado, la ubicación que se conserva ya está dada de baja (HU-UBI-006): el par
/// cambió desde que se mostró.
final class FailureConservadaDeBaja extends Failure {
  const FailureConservadaDeBaja()
    : super(
        mensaje: 'La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.',
        codigo: 'UBI_CONSERVADA_DE_BAJA',
      );
}

/// No hay lugar en el teléfono para el paquete de mapa que se quiere descargar (HU-SYNC-010).
/// [megabytesRequeridos] es lo que falta bajar: al reanudar descuenta lo que ya está descargado.
/// El mensaje es el literal de la HU más qué hacer (para confirmar en #189).
final class FailureEspacioInsuficiente extends Failure {
  const FailureEspacioInsuficiente({required this.megabytesRequeridos})
    : super(
        mensaje:
            'Espacio insuficiente - se requieren $megabytesRequeridos MB. Liberá espacio en el '
            'teléfono o elegí una cobertura más chica.',
        codigo: 'TILES_SIN_ESPACIO',
      );

  final int megabytesRequeridos;

  @override
  List<Object?> get props => [...super.props, megabytesRequeridos];
}

/// Los mapas se descargan solo con Wi-Fi salvo que el colportor autorice datos móviles para esa
/// descarga (HU-SYNC-010, override manual), y el teléfono está con datos móviles.
final class FailureDescargaRequiereWifi extends Failure {
  const FailureDescargaRequiereWifi()
    : super(
        mensaje:
            'Los mapas se descargan solo con Wi-Fi. Conectate a una red Wi-Fi o permití usar '
            'datos móviles.',
        codigo: 'TILES_REQUIERE_WIFI',
      );
}

/// El paquete descargado no pasó la validación de checksum (HU-SYNC-010): se borró y hay que
/// descargarlo de nuevo.
final class FailurePaqueteTilesCorrupto extends Failure {
  const FailurePaqueteTilesCorrupto()
    : super(
        mensaje: 'El mapa se descargó con errores y se descartó. Volvé a descargarlo.',
        codigo: 'TILES_CHECKSUM',
      );
}

/// "Conservar ambos" sobre dos ubicaciones con la misma calle, número y ciudad cuando la decisión
/// D1 (backend-supabase#24) no lo admite (`CriterioDuplicadoUbicacion.
/// mismaDireccionAdmiteConservarAmbos`): tiene que quedar una sola (HU-UBI-006).
///
/// Texto para confirmar con Cristian: la HU y la vista 10 no traen uno para este caso.
final class FailureDuplicadoMismaDireccion extends Failure {
  const FailureDuplicadoMismaDireccion()
    : super(
        mensaje:
            'Estas dos ubicaciones tienen la misma dirección y no pueden quedar las dos. Marcá cuál '
            'es el duplicado o corregí la dirección de una.',
        codigo: 'UBI_DUPLICADO_MISMA_DIRECCION',
      );
}

/// Se quiso mover (a otro punto u otra ciudad) una ubicación que registró otro colportor a un lugar
/// que queda fuera de las zonas asignadas a quien la mueve, o fuera de toda zona. El servidor la
/// rechaza (backend-supabase 0010, «mover una casa a otra zona: solo casas propias»), así que la
/// app lo avisa antes de guardar.
///
/// Texto para confirmar con Cristian: ni la HU ni las vistas traen uno para este caso (#231).
final class FailureUbicacionAjenaFueraDeZona extends Failure {
  const FailureUbicacionAjenaFueraDeZona()
    : super(
        mensaje:
            'Esta ubicación la registró otro colportor y solo podés moverla dentro de tu zona. '
            'Volvé a ponerla dentro de tu zona o pedile a tu coordinador que la mueva.',
        codigo: 'UBI_AJENA_FUERA_DE_ZONA',
      );
}

/// El borrado de datos locales (HU-AUTH-010) no se hizo porque, al ejecutarse, había operaciones
/// sin sincronizar (o no se pudieron contar): borrar las perdería. No se tocó nada. [pendientes] es
/// `null` si no se pudieron contar.
///
/// Es la guarda del caso de uso: la pantalla ya bloquea "Continuar" con pendientes, pero se puede
/// sumar una operación entre el resumen y la confirmación (vista 19, #228).
final class FailureBorradoConPendientes extends Failure {
  const FailureBorradoConPendientes({this.pendientes})
    : super(
        mensaje:
            'Apareció trabajo sin sincronizar y no se borró nada. Sincronizalo antes de borrar '
            'los datos de este teléfono.',
        codigo: 'AUTH_BORRADO_CON_PENDIENTES',
      );

  final int? pendientes;

  @override
  List<Object?> get props => [...super.props, pendientes];
}

/// No se pudo leer, o el valor guardado está mal formado, el contador de intentos de contraseña del
/// borrado de datos locales (vista 19). Falla cerrado: sin saber cuántos intentos van no se prueba
/// la contraseña ni se borra. Se puede reintentar; nada se borró.
final class FailureIntentosBorradoIlegibles extends Failure {
  const FailureIntentosBorradoIlegibles()
    : super(
        mensaje:
            'No pudimos revisar tus intentos anteriores, así que por seguridad no se puede '
            'confirmar el borrado ahora. No se borró nada: reintentá en un momento o, si sigue '
            'igual, cerrá y volvé a abrir la app.',
        codigo: 'AUTH_INTENTOS_BORRADO_ILEGIBLES',
      );
}

/// La contraseña de la confirmación final del borrado (HU-AUTH-010) no abre la DEK de este
/// teléfono. [intentosRestantes] cuenta los que quedan antes de la espera (vista 19, artboard 05b).
final class FailurePasswordBorradoIncorrecta extends Failure {
  const FailurePasswordBorradoIncorrecta({required this.intentosRestantes})
    : super(mensaje: 'Contraseña incorrecta.', codigo: 'AUTH_BORRADO_PASSWORD_INCORRECTA');

  final int intentosRestantes;

  @override
  List<Object?> get props => [...super.props, intentosRestantes];
}

/// Se agotaron los intentos de contraseña de la confirmación final del borrado: no se puede
/// volver a intentar hasta [hasta] (5 intentos, 5 minutos de espera; vista 19).
final class FailureBorradoBloqueado extends Failure {
  FailureBorradoBloqueado({required DateTime hasta})
    : hasta = hasta.toUtc(),
      super(
        mensaje: 'Demasiados intentos. Probá nuevamente en 5 minutos.',
        codigo: 'AUTH_BORRADO_BLOQUEADO',
      );

  final DateTime hasta;

  @override
  List<Object?> get props => [...super.props, hasta];
}

/// "Sincronizar ahora" no pudo correr porque el motor de sync todavía no está en la app (ADR-007,
/// #178 / #182). Provisoria: se reemplaza al conectar el motor.
final class FailureSincronizacionNoDisponible extends Failure {
  const FailureSincronizacionNoDisponible()
    : super(
        mensaje:
            'Todavía no se puede sincronizar desde acá. Cuando esté disponible, vas a poder '
            'subir tus operaciones y borrar los datos.',
        codigo: 'SYNC_NO_DISPONIBLE',
      );
}
