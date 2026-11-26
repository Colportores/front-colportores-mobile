import '../../domain/entities/companiero_de_campania.dart';
import '../../domain/entities/transferencia.dart';
import '../textos_transferencias.dart';

/// Lo que las pantallas de la lista y del detalle necesitan para poner nombre a una transferencia: cómo se
/// llama cada producto y quién es la otra punta. Todo sale de lo que el teléfono sabe.
final class LecturaDeTransferencias {
  const LecturaDeTransferencias({
    required this.colportorId,
    required this.nombresDeProductos,
    required this.companieros,
  });

  final String colportorId;

  /// `id de producto → nombre`.
  final Map<String, String> nombresDeProductos;

  /// Los compañeros de campaña si el servidor los dio; `null` si no (sin conexión o sin fuente).
  final CompanierosDeCampania? companieros;

  /// El nombre del producto de la línea, o «Material» si no está en el catálogo del teléfono.
  String nombreDelProducto(LineaDeTransferencia l) =>
      nombresDeProductos[l.productoId] ?? TextosTransferencias.materialSinNombre;

  /// Las líneas con nombre y cantidad.
  List<(String, int)> lineasConNombre(Transferencia t) => [
    for (final l in t.lineas) (nombreDelProducto(l), l.cantidad),
  ];

  /// «Salud y Hogar × 2» o «… y 1 más».
  String resumen(Transferencia t) => TextosTransferencias.resumenDeLineas(lineasConNombre(t));

  /// Cómo se llama el usuario [id]: el compañero si se sabe, y si no «otro colportor».
  String nombreDe(String id) => companieros?.por(id)?.nombre ?? TextosTransferencias.otroColportor;

  /// El nombre de la otra punta de [t] para quien mira.
  String contraparte(Transferencia t) => nombreDe(t.contraparteDe(colportorId));

  /// El nombre de una punta, o «Vos» si es quien mira.
  String punta(String id) => id == colportorId ? TextosTransferencias.vos : nombreDe(id);
}
