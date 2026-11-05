import '../entities/estado_alta_ubicacion.dart';

/// Dónde está el alta de las ubicaciones del teléfono respecto del servidor (HU-UBI-006, «Par
/// local»). Lo lee la vista 10 para no ofrecer conservar la que solo está en el teléfono.
abstract interface class ConsultorAltaUbicacion {
  /// Las ubicaciones cuya alta **no** está en el servidor, por id: [EstadoAltaUbicacion.soloEnTelefono]
  /// o [EstadoAltaUbicacion.subiendo]. Una que no figura está en el servidor. Emite de nuevo ante
  /// cualquier cambio de la cola.
  Stream<Map<String, EstadoAltaUbicacion>> observarSinConfirmar();
}
