import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tiles/domain/entities/paquete_tiles.dart' show AmbitoTrabajo;
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/value_objects/coordenadas.dart';
import 'alta_ubicacion_providers.dart' show ciudadesParaAltaProvider;
import 'mapa_ubicaciones_notifier.dart';

// Cableado del mapa de ubicaciones (vista 06, HU-UBI-003). Usa la lista del colportor y el aviso del
// mapa que ya existen (`lista_ubicaciones_providers`, `situacion_mapa_providers`); lo único propio
// es de qué ciudad es el mapa.

/// De qué ciudad es el mapa de la vista 06: de ahí salen las calles (el paquete descargado o el
/// mapa en línea) y el aviso de conexión con su «Descargar mapa».
///
/// La ciudad sale del puerto [CiudadesParaAlta], la misma fuente que el alta (decisión del 07/10 en
/// el #199, sin respaldo por posición, bbox ni ubicaciones): se pide con el último GPS si ya hay y,
/// si todavía no había, **una sola vez más** con la primera lectura del GPS (sin punto el puerto solo
/// sabe contestar cuando hay zona asignada o una única ciudad). Mientras no hay ciudad (el puerto
/// falla, la campaña no tiene ciudades o falta el punto) el ámbito está vacío: el mapa se ve sin
/// calles, sin aviso y sin «Descargar mapa» (no hay a qué ciudad pedirlo). Hasta que el adaptador
/// real exista (#274) la app es siempre así.
class AmbitoMapaUbicacionesNotifier extends Notifier<AmbitoTrabajo> {
  AmbitoMapaUbicacionesNotifier(this.colportorId);

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// Cuál es el último pedido al puerto: la respuesta de uno anterior se descarta, gana el último.
  int _secuencia = 0;

  /// Ya se pidió con un punto del GPS: no se vuelve a pedir con las lecturas que siguen.
  bool _pidioConElGps = false;

  @override
  AmbitoTrabajo build() {
    final proveedor = mapaUbicacionesProvider(colportorId);
    ref.listen(proveedor.select((estado) => estado.posicion), (_, posicion) {
      if (posicion != null && !_pidioConElGps) unawaited(_pedir(posicion));
    });
    final posicion = ref.read(proveedor).posicion;
    // Todavía no hay `state` dentro de `build`: la respuesta del puerto llega después de él.
    unawaited(_pedir(posicion));
    return const AmbitoTrabajo();
  }

  Future<void> _pedir(Coordenadas? punto) async {
    final numero = ++_secuencia;
    if (punto != null) _pidioConElGps = true;
    AmbitoTrabajo? ambito;
    try {
      final propuesta = await ref
          .read(ciudadesParaAltaProvider)
          .proponer(colportorId: colportorId, punto: punto);
      ambito = propuesta.fold<AmbitoTrabajo?>(
        (_) => null,
        (propuesta) => switch (propuesta) {
          CiudadPropuesta(:final ciudad) => AmbitoTrabajo(ciudadId: ciudad.id),
          CampaniaSinCiudades() || FaltaElPunto() => null,
        },
      );
    } on Object {
      // Un puerto que lanza (en vez de devolver una falla) es lo mismo que uno que no sabe.
      ambito = null;
    }
    if (!ref.mounted || numero != _secuencia) return;
    // La segunda pregunta (con el GPS) no tira la ciudad que ya se sabía si ahora no hay respuesta.
    final nuevo = ambito ?? state;
    if (nuevo != state) state = nuevo;
  }
}

/// La ciudad del mapa de la vista 06 del colportor [colportorId]. Se descarta con la pestaña.
final ambitoMapaUbicacionesProvider = NotifierProvider.autoDispose
    .family<AmbitoMapaUbicacionesNotifier, AmbitoTrabajo, String>(
      AmbitoMapaUbicacionesNotifier.new,
    );
