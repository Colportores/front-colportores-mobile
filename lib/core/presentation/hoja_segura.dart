import 'package:flutter/material.dart';

/// El contenido de una hoja inferior (`showModalBottomSheet`) con el borde de abajo a salvo de la
/// barra del sistema: la barra de gestos del iPhone (34 dp), la de 3 botones de Android con
/// edge-to-edge (~48 dp) o la de gestos de Android.
///
/// `useSafeArea: true` de `showModalBottomSheet` aplica `SafeArea(bottom: false)`: protege el
/// borde de arriba (la isla, el notch, la barra de estado) y deja el de abajo al contenido. Sin esto,
/// el último botón de la hoja queda pegado o debajo de la barra del sistema (#722, #717).
///
/// No se pone a mano en cada hoja: lo pone `mostrarHojaInferior` (`hoja_inferior.dart`), por donde se
/// abren todas las hojas de la app (#717). Queda suelto para quien arme una hoja fuera de ese helper,
/// como los tests. El fondo de la hoja (blanco, redondeado) sigue llegando hasta el borde de la
/// pantalla: lo que se corre es el contenido, no la hoja. Con el teclado abierto el relleno baja a 0
/// solo (el teclado ya cubre la barra), así que no se suma al `viewInsets` que cada hoja ya maneja.
///
/// Si el contenido ya tiene su propio `SafeArea`, envolverlo de nuevo no suma nada: el de adentro ve
/// el relleno ya consumido.
class HojaSegura extends StatelessWidget {
  const HojaSegura({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: child);
}
