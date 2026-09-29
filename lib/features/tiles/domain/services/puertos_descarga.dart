/// Puertos que usa `DescargadorPaquetesTiles` (HU-SYNC-010). Son interfaces de dominio (ADR-009):
/// la descarga no conoce el cliente HTTP, la librería de conectividad ni el sistema de archivos.
///
/// Adaptadores: [ArchivosTiles] tiene `ArchivosTilesIo` (dart:io, sin librerías nuevas). Los de
/// conectividad, espacio libre, cliente HTTP con `Range` y checksum no existen todavía: el repo no
/// tiene librería para eso y la documentación no la fija, así que elegirla queda para Cristian
/// (opciones en el issue #189). Los tests usan fakes (`test/helpers/tiles_falsos.dart`).
library;

/// Qué conexión tiene el teléfono.
enum TipoConexion { wifi, datosMoviles, sinConexion }

/// Conectividad del teléfono: la descarga usa solo Wi-Fi salvo override (HU-SYNC-010).
abstract interface class MonitorConectividad {
  Future<TipoConexion> actual();

  /// Emite cada cambio de conexión; con esto una descarga cortada sigue sola al volver la red.
  Stream<TipoConexion> get cambios;
}

/// Espacio libre en el volumen donde se guardan los paquetes.
abstract interface class MedidorEspacioDisco {
  Future<int> bytesLibres();
}

/// Lo que devolvió el servidor al pedir un paquete.
final class RespuestaDescarga {
  const RespuestaDescarga({required this.desde, required this.bytes});

  /// Desde qué byte viene el cuerpo: el pedido si el servidor respondió 206 (respetó el `Range`),
  /// o 0 si respondió 200 porque no soporta `Range` y manda el archivo entero. Otro valor es un
  /// error del adaptador.
  final int desde;

  /// El cuerpo, en pedazos. Un corte de red llega como error del stream.
  final Stream<List<int>> bytes;
}

/// Cliente HTTP que pide un archivo a partir de un byte (`Range: bytes=<desde>-`).
abstract interface class ClienteDescargaRango {
  /// Pide [origen] desde el byte [desde] (0 = el archivo entero, sin `Range`).
  ///
  /// Lanza [ErrorRedTiles] si no hay red o se corta antes de la respuesta, y [ErrorServidorTiles]
  /// si el servidor responde con error (4xx o 5xx, incluido un 416).
  Future<RespuestaDescarga> pedir(Uri origen, {required int desde});
}

/// No hay red o se cortó: la descarga queda en pausa y sigue sola cuando vuelve la conexión.
final class ErrorRedTiles implements Exception {
  const ErrorRedTiles([this.causa]);

  final Object? causa;

  @override
  String toString() => 'ErrorRedTiles($causa)';
}

/// El servidor respondió con error: la descarga falla con `FailureServidor`.
final class ErrorServidorTiles implements Exception {
  const ErrorServidorTiles(this.status);

  final int status;

  @override
  String toString() => 'ErrorServidorTiles($status)';
}

/// Los archivos de los paquetes, en el directorio de la app.
///
/// Cada paquete tiene dos rutas: el `.part` mientras se descarga y el `.pmtiles` definitivo, al
/// que solo se llega renombrando el `.part` después de validar el checksum. Así un corte nunca
/// deja un archivo que se tome por válido.
abstract interface class ArchivosTiles {
  String rutaParcial(String paqueteId);
  String rutaFinal(String paqueteId);

  /// Tamaño de [ruta] en bytes; 0 si no existe.
  Future<int> tamano(String ruta);
  Future<bool> existe(String ruta);

  /// Abre [ruta] para escribir: al final si [anexar], si no desde cero (lo trunca o lo crea).
  Future<EscrituraArchivo> abrir(String ruta, {required bool anexar});

  /// Renombra [desde] a [hasta] y reemplaza [hasta] si existe.
  Future<void> renombrar(String desde, String hasta);

  /// Borra [ruta]; si no existe no hace nada.
  Future<void> borrar(String ruta);
}

/// Un archivo abierto para escribir. [agregar] encola (como un `IOSink`); [cerrar] vuelca todo y
/// lanza si alguna escritura falló.
abstract interface class EscrituraArchivo {
  void agregar(List<int> bytes);
  Future<void> cerrar();
}

/// Calcula el checksum de un archivo con el mismo algoritmo y formato que publica el catálogo.
abstract interface class CalculadorChecksum {
  Future<String> calcular(String ruta);
}
