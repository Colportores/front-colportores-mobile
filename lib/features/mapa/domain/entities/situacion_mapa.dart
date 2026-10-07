import 'package:equatable/equatable.dart';

import '../../../tiles/domain/entities/paquete_tiles.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../services/fuente_mapa.dart';

/// El aviso que acompaña al mapa cuando no se ven las calles o se ven por un camino que conviene
/// cambiar (HU-UBI-003, vista 06: artboards 06C·05, 06C·06 y 06C·07). Cada uno dice solo lo que se
/// sabe: nunca «Sin conexión» si la app no sabe que no hay conexión.
sealed class AvisoMapa extends Equatable {
  const AvisoMapa();

  @override
  List<Object?> get props => const [];
}

/// Sin conexión y sin el mapa de la ciudad descargado (06C·05, y 06C·06 minimizado): las
/// ubicaciones se siguen viendo, sin calles.
final class AvisoSinConexion extends AvisoMapa {
  const AvisoSinConexion();
}

/// Con datos móviles y sin el mapa descargado (06C·07): el mapa se ve en línea y se sugiere
/// descargarlo. [paquete] es el del catálogo: de ahí sale el peso que muestra el botón.
final class AvisoDatosMoviles extends AvisoMapa {
  const AvisoDatosMoviles(this.paquete);

  final PaqueteTiles paquete;

  /// Lo que pesa el paquete entero, en MB redondeados para arriba (el del catálogo, no un ejemplo).
  int get megabytes => paquete.megabytes;

  @override
  List<Object?> get props => [paquete];
}

/// Hay conexión y el mapa igual no se puede cargar: el servidor no respondió o el catálogo no trae
/// la ciudad. No se dice «Sin conexión»: se dice qué pasa y se ofrece reintentar.
final class AvisoMapaNoCarga extends AvisoMapa {
  const AvisoMapaNoCarga();
}

/// Qué se sabe del paquete del catálogo que cubre el lugar del colportor.
sealed class PaqueteDelAmbito extends Equatable {
  const PaqueteDelAmbito();

  @override
  List<Object?> get props => const [];
}

/// Todavía no se sabe en qué ciudad o zona trabaja (la ciudad del alta aún no se propuso, o no se
/// pudo leer): sin ámbito no hay paquete que elegir ni aviso que dar.
final class PaqueteSinAmbito extends PaqueteDelAmbito {
  const PaqueteSinAmbito();
}

/// No se pudo preguntar al catálogo: sin conexión (o todavía no se sabe si hay).
final class PaqueteSinRed extends PaqueteDelAmbito {
  const PaqueteSinRed();
}

/// El catálogo trae un paquete que cubre el lugar.
final class PaqueteHallado extends PaqueteDelAmbito {
  const PaqueteHallado(this.paquete);

  final PaqueteTiles paquete;

  @override
  List<Object?> get props => [paquete];
}

/// Con conexión, el catálogo no se pudo leer o no trae ningún paquete que cubra el lugar.
final class PaqueteNoDisponible extends PaqueteDelAmbito {
  const PaqueteNoDisponible();
}

/// El paquete que cubre el lugar ya está descargado: no hay nada que sugerir. El mapa sale del
/// teléfono (lo decide `rutasDescargadas`); si esta consulta llega sin descargas es una lectura
/// vieja (se acaba de borrar el paquete), así que no se afirma nada hasta que se vuelva a preguntar.
final class PaqueteYaDescargado extends PaqueteDelAmbito {
  const PaqueteYaDescargado();
}

/// El mapa que se dibuja y el aviso que lo acompaña, según la conexión, el paquete descargado y el
/// catálogo.
final class SituacionMapa extends Equatable {
  const SituacionMapa({required this.fuente, this.aviso});

  /// Todavía no se sabe nada (se está leyendo la conexión o el registro de descargas): el color liso
  /// del diseño y ningún aviso, porque no hay nada cierto que decir.
  const SituacionMapa.sinDatos() : fuente = const FuenteMapa.sinTiles(), aviso = null;

  final FuenteMapa fuente;

  /// `null`: ningún aviso (el mapa descargado, o Wi-Fi con el mapa en línea).
  final AvisoMapa? aviso;

  @override
  List<Object?> get props => [fuente, aviso];
}

/// Elige el [SituacionMapa]. Función pura: la conexión, lo descargado y el catálogo los informan
/// otros (#189). Un dato en `null` es que todavía no se sabe (se está leyendo): sin saberlo no se
/// afirma nada, ni «Sin conexión» ni «No pudimos cargar el mapa».
///
/// - Con el paquete descargado: el mapa sale de él, con o sin conexión, y no hay aviso.
/// - Sin él y sin conexión: color liso y [AvisoSinConexion].
/// - Sin él y con conexión: el mapa en línea del paquete del catálogo (con datos móviles, además
///   [AvisoDatosMoviles]); si el catálogo no lo trae, [AvisoMapaNoCarga]. Sin ámbito no hay aviso.
abstract final class ResolutorSituacionMapa {
  static SituacionMapa resolver({
    required TipoConexion? conexion,
    required List<String>? rutasDescargadas,
    required PaqueteDelAmbito? consulta,
  }) {
    if (rutasDescargadas == null) return const SituacionMapa.sinDatos();
    if (rutasDescargadas.isNotEmpty) {
      return SituacionMapa(
        fuente: FuenteMapa.resolver(rutasOffline: rutasDescargadas, hayRed: false),
      );
    }
    if (conexion == null) return const SituacionMapa.sinDatos();
    if (conexion == TipoConexion.sinConexion) {
      return const SituacionMapa(fuente: FuenteMapa.sinTiles(), aviso: AvisoSinConexion());
    }
    return switch (consulta) {
      PaqueteHallado(:final paquete) => SituacionMapa(
        fuente: FuenteMapa.resolver(
          urlsOnline: [for (final parte in paquete.partes) parte.origen.toString()],
          hayRed: true,
        ),
        aviso: conexion == TipoConexion.datosMoviles ? AvisoDatosMoviles(paquete) : null,
      ),
      PaqueteNoDisponible() => const SituacionMapa(
        fuente: FuenteMapa.sinTiles(),
        aviso: AvisoMapaNoCarga(),
      ),
      PaqueteSinAmbito() ||
      PaqueteSinRed() ||
      PaqueteYaDescargado() ||
      null => const SituacionMapa.sinDatos(),
    };
  }
}
