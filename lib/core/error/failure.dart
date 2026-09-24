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

/// La cuenta existe pero todavía no fue habilitada (HU-AUTH-008).
final class FailureCuentaPendiente extends Failure {
  const FailureCuentaPendiente()
    : super(
        mensaje: 'Tu cuenta está pendiente de aprobación por el coordinador',
        codigo: 'AUTH_CUENTA_PENDIENTE',
      );
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

/// El enlace de recuperación de contraseña ya no sirve (HU-AUTH-005, "Error - token expirado"):
/// venció, ya se usó o se abrió en otro teléfono. Supabase no distingue vencido de usado (mismo
/// `otp_expired`), así que la app tampoco. [mensaje] es el literal de la HU; la pantalla ofrece
/// pedir un enlace nuevo (HU-AUTH-004).
final class FailureEnlaceRecuperacionVencido extends Failure {
  const FailureEnlaceRecuperacionVencido()
    : super(mensaje: 'El enlace expiró. Solicitá uno nuevo.', codigo: 'AUTH_ENLACE_VENCIDO');
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
/// interpretar (HU-AUTH-009). El mensaje es el que fija la HU.
final class FailureAlmacenSeguro extends Failure {
  const FailureAlmacenSeguro()
    : super(
        mensaje:
            'No pudimos preparar el almacenamiento seguro. Probá reinstalar el app o consultá a '
            'soporte.',
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
/// contraseña (usuario de Google sin backup): ADR-006 muestra el mensaje de HU-AUTH-009 y ofrece
/// "empezar de nuevo", que avisa qué se pierde. **Nunca se borra sin ese sí.**
final class FailureAlmacenSeguroSinRecuperacion extends Failure {
  const FailureAlmacenSeguroSinRecuperacion()
    : super(
        mensaje:
            'No pudimos preparar el almacenamiento seguro. Probá reinstalar el app o consultá a '
            'soporte.',
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

/// La sesión se cerró (o no había) mientras se preparaba la DB local: no se abre nada sin sesión.
final class FailureSesionCerrada extends Failure {
  const FailureSesionCerrada()
    : super(
        mensaje: 'La sesión se cerró antes de terminar de preparar tus datos',
        codigo: 'AUTH_SESION_CERRADA',
      );
}
