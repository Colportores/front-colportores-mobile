import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'seguridad_dispositivo.dart';

part 'dispositivo_providers.g.dart';

/// Seguridad del equipo (bloqueo de pantalla, nivel del Keystore — ADR-006).
///
/// Sin implementación por defecto, como el almacén seguro: `main.dart` lo sobreescribe con
/// `SeguridadDispositivoCanal` y los tests con `SeguridadDispositivoFija`. Así ningún test toca el
/// canal nativo sin decirlo.
@Riverpod(keepAlive: true)
SeguridadDispositivo seguridadDispositivo(Ref ref) {
  throw UnimplementedError('seguridadDispositivoProvider se sobreescribe en main.dart');
}
