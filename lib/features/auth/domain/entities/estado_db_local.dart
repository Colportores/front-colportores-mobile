import 'package:equatable/equatable.dart';

/// Lo que hay en este dispositivo antes de abrir la DB local cifrada (HU-AUTH-009).
///
/// Junta dos cosas que se guardan en lugares distintos y **se desincronizan**: la marca de
/// inicialización vive en el almacén seguro y el archivo SQLCipher en disco. En iOS el Keychain
/// sobrevive a la desinstalación de la app y el archivo no, así que tras reinstalar puede haber
/// marca sin archivo. Por eso el flujo de inicialización mira las dos antes de elegir camino.
final class EstadoDbLocal extends Equatable {
  const EstadoDbLocal({required this.inicializada, required this.archivoExiste});

  /// Si el almacén seguro dice que este dispositivo ya completó la creación de la DB.
  final bool inicializada;

  /// Si el archivo SQLCipher existe en disco. No dice nada de si la clave lo abre.
  final bool archivoExiste;

  @override
  List<Object?> get props => [inicializada, archivoExiste];
}
