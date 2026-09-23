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

/// El colportor ya tiene una jornada en curso (HU-JOR-001: "solo una jornada activa a la vez").
/// [mensaje] es el texto literal del criterio de aceptación "Bloqueo - jornada ya activa".
final class FailureJornadaActiva extends Failure {
  const FailureJornadaActiva()
    : super(
        mensaje: 'Tenés una jornada en curso. Cerrala antes de iniciar otra.',
        codigo: 'JOR_JORNADA_ACTIVA',
      );
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
