import 'package:flutter/material.dart';

/// Una capa encima del mapa principal (vista 41, #655): el alta, el aviso de duplicado, la edición y
/// comparar un par son hojas sobre **el mismo mapa**, no pantallas con otro mapa.
///
/// A diferencia de una pantalla común, la capa no tapa el mapa ni le pone velo ni barrera: lo que la
/// capa no dibuja deja pasar los toques y los arrastres al mapa de abajo, que sigue vivo (la misma
/// cámara, el mismo GPS), y el lector de pantalla lo sigue encontrando. La capa dibuja solo su hoja
/// (o lo que necesite) y es lo único que atrapa los toques en lo que ocupa.
///
/// El atrás del teléfono la cierra como a cualquier pantalla (con `PopScope` adentro, si hace falta
/// preguntar antes). [settings] lleva el nombre de la capa (`RutasCapaDelMapa`): con él el
/// seguimiento de la ubicación (#670) sabe que el mapa sigue a la vista.
final class RutaCapaDelMapa<T> extends PageRoute<T> {
  RutaCapaDelMapa({required this.builder, required RouteSettings super.settings});

  /// Lo que dibuja la capa: solo la hoja (por ejemplo, alineada abajo); el resto queda transparente.
  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  /// Sin barrera: una pantalla común pone debajo de ella una barrera que se queda con todos los
  /// toques. Esta capa no tiene ninguna, así que tocar fuera de la hoja toca el mapa.
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}
