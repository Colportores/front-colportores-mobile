import '../entities/avisos_del_servidor.dart';

/// Por qué no se pudieron leer o guardar los avisos. Nunca es por falta de conexión: se leen y se guardan en
/// el teléfono (backend-supabase 0207, «Avisos s/red»).
sealed class AvisosDelServidorException implements Exception {
  const AvisosDelServidorException();
}

/// La base del teléfono no pudo leer o guardar los avisos.
final class AvisosServidorException extends AvisosDelServidorException {
  const AvisosServidorException({this.codigo});

  /// Un código de la falla, si lo hubo (en los tests, el SQLSTATE que el servidor devolvía antes).
  final String? codigo;

  @override
  String toString() => 'AvisosServidorException($codigo)';
}

/// Dónde viven los avisos de la colportora que manda el servidor (HU-NOT-004): en `preferencia_de_avisos`, la
/// fila de la persona en la base del teléfono, que baja y sube con la sincronización (backend-supabase 0207;
/// el servidor la copia a `usuario.notif_preferences`, que es lo que lee para mandar los avisos). Se leen y se
/// guardan en el teléfono, sin conexión (decisión de Cristian, 24/11, «Avisos s/red»).
abstract interface class AvisosDelServidorRepository {
  /// Lo guardado, o los valores de siempre si nunca se eligió nada. Si falla, lanza.
  Future<AvisosDelServidor> leer();

  /// Reemplaza lo guardado por [avisos] entero. Si falla, lanza.
  Future<void> guardar(AvisosDelServidor avisos);
}
