/// Puertos que usa `DescargadorPaquetesTiles` (HU-SYNC-010). Son interfaces de dominio (ADR-009):
/// la descarga no conoce el cliente HTTP, la librería de conectividad ni el sistema de archivos.
///
/// Adaptadores (decisiones del 02/10 en el issue #189): [ClienteDescargaRango] con `package:http`,
/// [CalculadorChecksum] con SHA-256 de `package:crypto`, [MonitorConectividad] con
/// `connectivity_plus`, [MedidorEspacioDisco] con un canal propio (StatFs en Android,
/// `volumeAvailableCapacityForImportantUsage` en iOS) y [ArchivosTiles] con `dart:io`. Los tests
/// usan fakes (`test/helpers/tiles_falsos.dart`).
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

/// No hay lugar en el teléfono para seguir escribiendo (disco lleno a mitad de la descarga, aunque
/// al empezar sí alcanzaba): la descarga falla con `FailureEspacioInsuficiente` y deja el `.part`
/// para reanudar cuando haya lugar.
final class ErrorEspacioTiles implements Exception {
  const ErrorEspacioTiles([this.causa]);

  final Object? causa;

  @override
  String toString() => 'ErrorEspacioTiles($causa)';
}

/// Un archivo del directorio de los paquetes, para limpiar lo que quedó de descargas cortadas.
final class ArchivoTiles {
  const ArchivoTiles({
    required this.nombre,
    required this.ruta,
    required this.bytes,
    required this.modificado,
  });

  /// El nombre sin la carpeta: es lo que anota el registro (la carpeta de la app puede cambiar entre
  /// una versión y otra).
  final String nombre;
  final String ruta;
  final int bytes;
  final DateTime modificado;

  /// Un `.part`: una descarga sin terminar o terminada y todavía sin registrar.
  bool get esParcial => nombre.endsWith(extensionParcial);

  /// Un `.pmtiles`: lo que el registro dice que está descargado.
  bool get esFinal => nombre.endsWith(extensionFinal);

  static const extensionFinal = '.pmtiles';
  static const extensionParcial = '.pmtiles.part';
}

/// Los archivos de los paquetes, en el directorio de la app.
///
/// Cada parte de un paquete tiene dos rutas, por [clave] (`PaqueteTiles.claveDeParte`): el `.part`
/// mientras se descarga y el `.pmtiles` definitivo, al que solo se llega renombrando el `.part`
/// después de validar su checksum. Así un corte nunca deja un archivo que se tome por válido.
abstract interface class ArchivosTiles {
  String rutaParcial(String clave);
  String rutaFinal(String clave);

  /// Tamaño de [ruta] en bytes; 0 si no existe.
  Future<int> tamano(String ruta);
  Future<bool> existe(String ruta);

  /// Abre [ruta] para escribir: al final si [anexar], si no desde cero (lo trunca o lo crea).
  Future<EscrituraArchivo> abrir(String ruta, {required bool anexar});

  /// Renombra [desde] a [hasta] y reemplaza [hasta] si existe.
  Future<void> renombrar(String desde, String hasta);

  /// Borra [ruta]; si no existe no hace nada.
  Future<void> borrar(String ruta);

  /// Los `.part` y `.pmtiles` del directorio; vacía si el directorio no existe.
  Future<List<ArchivoTiles>> listar();
}

/// Un archivo abierto para escribir. [agregar] termina cuando el pedazo ya salió al sistema de
/// archivos: la descarga espera ese final antes de pedir más bytes, así, si la red va más rápido
/// que el disco, el buffer no crece sin tope en memoria. [cerrar] vuelca todo y lanza si alguna
/// escritura falló. Los dos lanzan [ErrorEspacioTiles] si el disco se llenó.
abstract interface class EscrituraArchivo {
  Future<void> agregar(List<int> bytes);
  Future<void> cerrar();
}

/// Calcula el checksum de un archivo con el mismo algoritmo y formato que publica el catálogo
/// (SHA-256 en hex minúscula).
abstract interface class CalculadorChecksum {
  Future<String> calcular(String ruta);
}
