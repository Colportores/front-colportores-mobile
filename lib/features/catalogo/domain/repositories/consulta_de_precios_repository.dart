import '../entities/catalogo_local.dart';

/// La lectura del catálogo de ventas replicado en el teléfono (HU-CAT-006): reactiva y solo local, así
/// que funciona sin conexión.
abstract interface class ConsultaDePreciosRepository {
  /// El catálogo para la ciudad de la campaña [campaniaCiudadId]: todos los productos y combos (los
  /// dados de baja, marcados: el `ResolvedorDePrecios` no los ofrece, pero un combo vivo sigue
  /// nombrando a un libro que ya no se vende suelto), las excepciones de **esa** ciudad y los precios
  /// generales, estos dos sin las bajas lógicas. Emite de nuevo
  /// cada vez que el pull o el Realtime cambian algo de eso. Un error al leer sale por el `Stream`.
  Stream<CatalogoLocal> observar(String campaniaCiudadId);
}
