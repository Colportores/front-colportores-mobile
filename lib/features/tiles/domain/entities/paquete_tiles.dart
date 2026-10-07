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

  /// Hay al menos un lugar conocido: sin ninguno no se puede elegir un paquete.
  bool get conocido => zonaId != null || ciudadId != null || departamentoId != null;

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

/// Un archivo `.pmtiles` de un paquete: lo que se baja, con lo que hace falta para validarlo.
///
/// Una ciudad que no entra en un solo archivo (plan Free de Storage: menos de 50 MB cada uno) se
/// parte en varios; cada parte se baja y se valida sola.
final class ParteTiles extends Equatable {
  const ParteTiles({required this.origen, required this.tamanoBytes, required this.sha256});

  /// De dónde se baja: la ruta del catálogo resuelta contra la URL del catálogo (ADR-011: directo
  /// de Storage, sin pasar por el BFF).
  final Uri origen;

  /// Lo que pesa el archivo; la descarga lo comprueba contra lo que baja y contra el `.part`.
  final int tamanoBytes;

  /// SHA-256 del archivo en hex minúscula (el del catálogo; el mismo de `sha256sum`).
  final String sha256;

  /// Los primeros 12 caracteres del SHA-256, como en el nombre del archivo del bucket: el archivo
  /// local los lleva, así un `.part` de una versión vieja nunca se reanuda con bytes de otra.
  String get huella => sha256.length <= _largoHuella ? sha256 : sha256.substring(0, _largoHuella);

  @override
  List<Object?> get props => [origen, tamanoBytes, sha256];
}

const _largoHuella = 12;

/// Un paquete PMTiles del catálogo: lo que se puede descargar (HU-SYNC-010, ADR-011).
///
/// Sale de `catalogo.json` del bucket público `mapas` (backend-supabase, `docs/mapas-tiles.md`).
/// [version] es lo que cambia cuando hay un mapa nuevo: el SHA-256 de la parte, o el de los
/// SHA-256 de las partes unidos con un salto de línea. El paquete está disponible recién cuando
/// **todas** sus [partes] se bajaron y se validaron.
final class PaqueteTiles extends Equatable {
  const PaqueteTiles({
    required this.id,
    required this.nivel,
    required this.ambitoId,
    this.nombre,
    required this.version,
    required this.partes,
  });

  /// Identifica al paquete dentro del catálogo (`ciudad-montevideo`) y nombra sus archivos en el
  /// dispositivo. Solo letras, números, `-` y `_`.
  final String id;
  final NivelCobertura nivel;

  /// El id de la zona, la ciudad o el departamento que cubre; `null` para Uruguay completo. La app
  /// elige el paquete por este id, nunca por el nombre.
  final String? ambitoId;

  /// Lo que ve el colportor: "Montevideo" en "Descargar Montevideo (87 MB)". Los paquetes de zona
  /// no lo traen (el catálogo es público): la app ya conoce sus zonas por la réplica local.
  final String? nombre;

  /// Qué mapa es: cambia cuando se publica uno nuevo (`hayActualizacion`).
  final String version;
  final List<ParteTiles> partes;

  /// Lo que pesa el paquete entero: la suma de sus partes.
  int get tamanoBytes => partes.fold(0, (suma, parte) => suma + parte.tamanoBytes);

  /// El tamaño en MB para mostrar, redondeado para arriba ([megabytesDe]).
  int get megabytes => megabytesDe(tamanoBytes);

  /// El nombre de los archivos locales de la parte [indice]: `<id>-p<n>-<huella>`. Con la huella
  /// en el nombre, el `.part` de una versión no se mezcla con el de otra.
  String claveDeParte(int indice) => '$id-p${indice + 1}-${partes[indice].huella}';

  /// `true` si el paquete tiene los tiles del lugar de [ambito]. Uruguay cubre cualquier lugar.
  bool cubre(AmbitoTrabajo ambito) {
    if (nivel == NivelCobertura.uruguay) return true;
    final id = ambito.idPara(nivel);
    return id != null && id == ambitoId;
  }

  @override
  List<Object?> get props => [id, nivel, ambitoId, nombre, version, partes];
}

/// Un paquete ya descargado, con todas sus partes validadas. [rutas] son los `.pmtiles` en el
/// directorio de la app, en el orden de las partes, listos para que el mapa los use sin red.
final class PaqueteDescargado extends Equatable {
  const PaqueteDescargado({required this.paquete, required this.rutas});

  final PaqueteTiles paquete;
  final List<String> rutas;

  String get id => paquete.id;

  @override
  List<Object?> get props => [paquete, rutas];
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
