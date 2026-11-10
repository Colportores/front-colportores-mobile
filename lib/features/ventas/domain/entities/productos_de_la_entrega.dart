import 'package:equatable/equatable.dart';

/// Lo que el catálogo dice de lo que se vendió, para armar las filas de «Entregar ahora» (27B·01).
final class ProductosDeLaEntrega extends Equatable {
  const ProductosDeLaEntrega({this.nombres = const {}, this.baseDeCombos = const {}});

  /// `producto.id` → nombre.
  final Map<String, String> nombres;

  /// `coleccion.id` → los `producto.id` que el combo lleva siempre (lo que no elige la colportora).
  /// Un combo que no está acá no se agrupa: cada componente va en su fila.
  final Map<String, Set<String>> baseDeCombos;

  @override
  List<Object?> get props => [nombres, baseDeCombos];
}
