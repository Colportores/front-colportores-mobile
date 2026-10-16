/// En qué estado está la cuenta del colportor (HU-AUTH-008). Lo decide el backend, nunca la app.
enum EstadoCuenta {
  /// Asignada a una campaña vigente: accede a todo.
  activa,

  /// Creada y verificada, pero sin campaña vigente: puede entrar, solo accede a Configuración.
  pendienteAsignacion,

  /// Suspendida por un administrador: el mismo acceso que [pendienteAsignacion].
  suspendida;

  /// Solo una cuenta activa ve los módulos de campo (ubicaciones, visitas, ventas, cobranzas,
  /// jornada, mi cuenta). Las otras quedan con Configuración (cerrar sesión, consentimientos,
  /// borrar datos).
  bool get accedeAModulosDeCampo => this == EstadoCuenta.activa;
}
