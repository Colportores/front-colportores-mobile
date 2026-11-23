import '../entities/avisos_del_servidor.dart';

/// Por qué el servidor no leyó o no guardó los avisos.
sealed class AvisosDelServidorException implements Exception {
  const AvisosDelServidorException();
}

/// Sin red, con el servidor cortado a mitad o sin contestar a tiempo.
final class AvisosSinConexionException extends AvisosDelServidorException {
  const AvisosSinConexionException();

  @override
  String toString() => 'AvisosSinConexionException';
}

/// El servidor contestó con un error (o no hay sesión: `42501`).
final class AvisosServidorException extends AvisosDelServidorException {
  const AvisosServidorException({this.codigo});

  /// El SQLSTATE de la falla, si lo hubo.
  final String? codigo;

  @override
  String toString() => 'AvisosServidorException($codigo)';
}

/// Dónde viven los avisos de la colportora que manda el servidor (`usuario.notif_preferences`,
/// HU-NOT-004): se leen de la fila propia y se guardan con la función
/// `guardar_mis_preferencias_de_avisos`, nunca con un PATCH (ADR-013, decisión del 04/11, R7).
abstract interface class AvisosDelServidorRepository {
  /// Lo guardado en el servidor, o los valores de siempre si nunca se eligió nada. Lanza una
  /// [AvisosDelServidorException].
  Future<AvisosDelServidor> leer();

  /// Reemplaza lo guardado por [avisos] entero. Lanza una [AvisosDelServidorException].
  Future<void> guardar(AvisosDelServidor avisos);
}
