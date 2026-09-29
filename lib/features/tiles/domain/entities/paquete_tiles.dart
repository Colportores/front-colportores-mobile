import 'package:equatable/equatable.dart';

/// Los cuatro niveles de cobertura de un paquete PMTiles, del más chico al más grande
/// (HU-SYNC-010, ajuste S15 del PO del 19/05). El orden de los valores es el de la jerarquía.
enum NivelCobertura {
  /// La zona asignada al colportor: el default sugerido, ~5–20 MB.
  zona,

  /// La ciudad completa, ~30–100 MB.
  ciudad,

  /// El departamento completo, ~100–300 MB.
  departamento,

  /// Todo Uruguay, ~500 MB–1 GB.
  uruguay,
}

/// Dónde trabaja el colportor: su zona, su ciudad y el departamento de esa ciudad.
///
/// Con esto se sabe qué paquete cubre el lugar (el mapa lo prioriza sobre el online, HU-UBI-003)
/// y qué paquete sugerir cuando lo reasignan (HU-CAM-005). Cualquiera puede faltar (un colportor
/// todavía sin zona): entonces ningún paquete de ese nivel lo cubre.
final class AmbitoTrabajo extends Equatable {
  const AmbitoTrabajo({this.zonaId, this.ciudadId, this.departamentoId});

  final String? zonaId;
  final String? ciudadId;
  final String? departamentoId;

  /// El id del lugar que corresponde a [nivel]; `null` para Uruguay o si falta.
  String? idPara(NivelCobertura nivel) => switch (nivel) {
    NivelCobertura.zona => zonaId,
    NivelCobertura.ciudad => ciudadId,
    NivelCobertura.departamento => departamentoId,
    NivelCobertura.uruguay => null,
  };

  @override
  List<Object?> get props => [zonaId, ciudadId, departamentoId];
}

/// Un paquete PMTiles del catálogo: lo que se puede descargar (HU-SYNC-010, ADR-011).
///
/// La documentación no fija el formato del catálogo, dónde se publica ni el algoritmo de
/// [checksum] (ver el issue #189). Para el dominio [checksum] es un texto opaco que se compara tal
/// cual con el que calcula `CalculadorChecksum`, y [origen] es de dónde se baja el archivo
/// (ADR-011: directo de Storage, sin pasar por el BFF).
final class PaqueteTiles extends Equatable {
  const PaqueteTiles({
    required this.id,
    required this.nivel,
    required this.ambitoId,
    required this.nombre,
    required this.tamanoBytes,
    required this.checksum,
    required this.origen,
  });

  /// Identifica al paquete y nombra su archivo en el dispositivo.
  final String id;
  final NivelCobertura nivel;

  /// El id de la zona, la ciudad o el departamento que cubre; `null` para Uruguay completo.
  final String? ambitoId;

  /// Lo que ve el colportor: "Montevideo" en "Descargar Montevideo (87 MB)".
  final String nombre;
  final int tamanoBytes;
  final String checksum;
  final Uri origen;

  /// El tamaño en MB para mostrar, redondeado para arriba ([megabytesDe]).
  int get megabytes => megabytesDe(tamanoBytes);

  /// `true` si el paquete tiene los tiles del lugar de [ambito]. Uruguay cubre cualquier lugar.
  bool cubre(AmbitoTrabajo ambito) {
    if (nivel == NivelCobertura.uruguay) return true;
    final id = ambito.idPara(nivel);
    return id != null && id == ambitoId;
  }

  @override
  List<Object?> get props => [id, nivel, ambitoId, nombre, tamanoBytes, checksum, origen];
}

/// Un paquete ya descargado y con el checksum validado. [ruta] es el `.pmtiles` en el directorio
/// de la app, listo para que el mapa lo use sin red.
final class PaqueteDescargado extends Equatable {
  const PaqueteDescargado({required this.paquete, required this.ruta});

  final PaqueteTiles paquete;
  final String ruta;

  String get id => paquete.id;

  @override
  List<Object?> get props => [paquete, ruta];
}

/// El paquete descargado que usa el mapa para [ambito] (HU-UBI-003 lo prioriza sobre el online):
/// entre los que lo cubren, el de nivel más chico. `null` si ninguno lo cubre: el mapa cae al
/// servidor online o a "sin tiles".
///
/// Se engancha con `ResolutorFuenteTiles.resolver` (#198) como
/// `hayPaqueteOffline: elegirPaqueteOffline(descargados, ambito) != null`.
PaqueteDescargado? elegirPaqueteOffline(
  Iterable<PaqueteDescargado> descargados,
  AmbitoTrabajo ambito,
) {
  PaqueteDescargado? elegido;
  for (final descargado in descargados) {
    if (!descargado.paquete.cubre(ambito)) continue;
    if (elegido == null || descargado.paquete.nivel.index < elegido.paquete.nivel.index) {
      elegido = descargado;
    }
  }
  return elegido;
}

/// Bytes a MB (1 MB = 1 000 000 bytes, como los muestra Android) redondeando para arriba: así el
/// tamaño que se muestra, o el espacio que se pide, nunca queda corto.
int megabytesDe(int bytes) => bytes <= 0 ? 0 : (bytes + _bytesPorMb - 1) ~/ _bytesPorMb;

const _bytesPorMb = 1000 * 1000;
