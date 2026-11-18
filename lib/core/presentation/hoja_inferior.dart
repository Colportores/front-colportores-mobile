import 'package:flutter/material.dart';

/// Abre una hoja inferior modal que nunca queda bajo la barra de navegación del sistema (#717).
///
/// En Android 15 o más la app se dibuja de borde a borde: la barra de navegación (los tres botones o
/// la línea de gestos) flota sobre la parte de abajo de la pantalla. `showModalBottomSheet` con
/// `useSafeArea: true` cuida solo el borde de arriba, así que, sin esto, los botones del pie de una
/// hoja quedaban tapados por esa barra. Acá la hoja se abre siempre con `useSafeArea: true` y su
/// contenido se envuelve en un `SafeArea`: el fondo de la hoja sigue llegando hasta el borde de la
/// pantalla y los botones quedan encima de la barra. Si el contenido ya traía su propio `SafeArea`
/// no se suma otro margen (el de afuera ya le quitó el inset al de adentro).
///
/// Toda hoja inferior de la app se abre por acá, no con `showModalBottomSheet`: un test de
/// arquitectura (`hojas_respetan_la_barra_inferior_test.dart`) lo exige.
///
/// [conBarraInferior] en `false` es solo para la hoja que pinta ella misma su fondo y arrastra su
/// altura (la de una ubicación, `DraggableScrollableSheet`): ahí el `SafeArea` va adentro de su
/// `Material`, no afuera, para que el fondo siga llegando al borde.
Future<T?> mostrarHojaInferior<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool? showDragHandle,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  bool conBarraInferior = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: true,
  enableDrag: enableDrag,
  showDragHandle: showDragHandle,
  backgroundColor: backgroundColor,
  barrierColor: barrierColor,
  shape: shape,
  builder: conBarraInferior
      ? (contexto) => SafeArea(top: false, child: builder(contexto))
      : builder,
);
