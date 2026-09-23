// Los errores que el motor le devuelve a la app.
//
// Son de programación, no de runtime recuperable: ninguno se atrapa en un
// try/catch de producción. Existen para que una violación del contrato explote
// en el test o en el arranque, y no se convierta en una fuga silenciosa de
// datos personales seis meses después.

/// Se intentó `stage()` sobre una entidad declarada `local` (§2).
///
/// Es la garantía técnica de la Ley 18.331: `persona` y `nota` no salen del
/// dispositivo por sync, y la prohibición deja de ser una convención de code
/// review para pasar a ser un error de runtime.
class LocalOnlyViolationError extends Error {
  LocalOnlyViolationError(this.entity);

  final String entity;

  @override
  String toString() => 'LocalOnlyViolationError: "$entity" está declarada '
      'local (§2): jamás sale del dispositivo por sync. Solo participa del '
      'backup E2E cifrado.';
}

/// Se intentó `stage()` sobre una entidad `pull`, que es réplica de solo
/// lectura: la app nunca escribe esas tablas (§2).
class ReadOnlyEntityError extends Error {
  ReadOnlyEntityError(this.entity);

  final String entity;

  @override
  String toString() => 'ReadOnlyEntityError: "$entity" es una réplica de solo '
      'lectura (política pull, §2). La app no escribe esa tabla.';
}

/// Una o más entidades de la DB local no tienen `SyncSpec`.
///
/// §2: "Una entidad sin registrar es un error en tiempo de arranque, no un
/// comportamiento por defecto". Sin esto, agregar una tabla con datos
/// personales y olvidarse de declararla sería silencioso.
class UnregisteredEntityError extends Error {
  UnregisteredEntityError(this.entities);

  final List<String> entities;

  @override
  String toString() => 'UnregisteredEntityError: sin SyncSpec: '
      '${entities.join(", ")}. Toda entidad se registra con exactamente una '
      'política (§2).';
}

/// La misma entidad se declaró dos veces.
class DuplicateSpecError extends Error {
  DuplicateSpecError(this.entity);

  final String entity;

  @override
  String toString() =>
      'DuplicateSpecError: "$entity" tiene más de un SyncSpec. '
      'Exactamente una política por entidad (§2).';
}
