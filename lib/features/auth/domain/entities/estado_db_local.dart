import 'package:equatable/equatable.dart';

/// Qué dice el almacén seguro sobre la inicialización de la DB local (HU-AUTH-009).
enum MarcaDbLocal {
  /// El dispositivo completó la creación de la DB.
  puesta,

  /// No hay marca: primer login, una inicialización que quedó a mitad de camino, o un almacén que
  /// perdió todo (ver `InicializarDbLocalUseCase` para cómo se distinguen con la DB en disco).
  ausente,

  /// El almacén no respondió o lo guardado no se puede interpretar. Con la DB en disco no se sabe
  /// si tiene datos: rige la recuperación guiada de ADR-006, nunca "dispositivo nuevo".
  ilegible,
}

/// Lo que hay en este dispositivo antes de abrir la DB local cifrada (HU-AUTH-009, ADR-006).
///
/// Junta cosas que se guardan en lugares distintos y **se desincronizan**: la marca de
/// inicialización vive en el almacén seguro, el archivo SQLCipher y el envoltorio por contraseña en
/// disco. En iOS el Keychain sobrevive a la desinstalación de la app y los archivos no, así que
/// tras reinstalar puede haber marca sin archivo. Por eso el flujo mira todo antes de elegir camino.
final class EstadoDbLocal extends Equatable {
  const EstadoDbLocal({
    required this.marca,
    required this.archivoExiste,
    required this.envoltorioExiste,
  });

  final MarcaDbLocal marca;

  /// Si el archivo SQLCipher existe en disco. No dice nada de si la DEK lo abre.
  final bool archivoExiste;

  /// Si hay una DEK envuelta con la contraseña en este equipo. No dice si se puede abrir.
  final bool envoltorioExiste;

  @override
  List<Object?> get props => [marca, archivoExiste, envoltorioExiste];
}
