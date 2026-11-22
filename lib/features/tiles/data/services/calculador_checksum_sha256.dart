import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../domain/services/puertos_descarga.dart';

/// [CalculadorChecksum] con SHA-256 de `package:crypto` (decisión d3 de #189): el mismo hash que
/// calcula `sha256sum` en el script que publica el mapa y que trae el catálogo.
///
/// Lee el archivo por bloques (los 64 KB de `File.openRead`): no lo carga entero en memoria y no
/// traba el hilo de la interfaz, porque cada bloque deja pasar al bucle de eventos. Se hace sobre
/// el archivo ya bajado, no mientras baja: una descarga reanudada tendría que guardar el estado del
/// hash entre sesiones.
final class CalculadorChecksumSha256 implements CalculadorChecksum {
  const CalculadorChecksumSha256();

  @override
  Future<String> calcular(String ruta) async {
    final digest = await sha256.bind(File(ruta).openRead()).first;
    return digest.toString();
  }
}
