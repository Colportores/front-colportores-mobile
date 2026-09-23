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

/// Ya existe una cuenta con ese correo (HU-AUTH-001).
final class FailureEmailYaRegistrado extends Failure {
  const FailureEmailYaRegistrado()
    : super(mensaje: 'Ya existe una cuenta con ese correo.', codigo: 'AUTH_EMAIL_DUPLICADO');
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

/// La clave derivada no abre la DB local que ya hay en el dispositivo: la contraseña no es la
/// misma con la que se creó, o la sal guardada no corresponde a ese archivo.
final class FailureClaveDbIncorrecta extends Failure {
  const FailureClaveDbIncorrecta()
    : super(
        mensaje: 'No pudimos abrir los datos guardados en este dispositivo con esa contraseña',
        codigo: 'DB_CLAVE_INCORRECTA',
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
