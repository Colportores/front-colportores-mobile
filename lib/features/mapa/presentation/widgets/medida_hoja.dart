import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'piezas_alta.dart';

/// La medida de la hoja inferior de las vistas 03 («Alta de ubicación») y 07 («Modificar ubicación»),
/// compartida por las dos (#324, seguimiento de #320 y #307).
///
/// La hoja ocupa el 62 % del cuerpo. Con el teclado abierto eso no alcanza a veces para el campo que
/// se escribe y la acción (teléfono chico, texto grande): la regla es una sola para las dos hojas.
/// - Si el campo con foco no entra entero sobre la acción (y su motivo, debajo de ella), la hoja crece
///   lo justo para que entre, con un tope del 80 % del cuerpo, y la acción («Registrar», «Guardar
///   cambios») queda fija al pie. El motivo debajo de la acción solo pide alto mientras el mapa
///   conserva lo que «Cerrar» y el pin necesitan; si no, el motivo pasa al final de lo que se desplaza.
/// - Si ni así entra el campo entero sobre la acción, la acción pasa al final de lo que se desplaza:
///   nada desborda y el campo que se escribe se ve entero.
/// - Sin teclado nada cambia: 62 %.

/// El aire de arriba de la hoja (10), el asa (4 y 12 de margen) y el aire de abajo (20), sin la barra
/// de abajo del sistema.
const double cromoDeLaHoja = 46;

/// El aire entre lo que se desplaza y la acción fija.
const double separacionDelBoton = 14;

/// El aire entre la acción fija y el motivo de abajo.
const double separacionDelMotivo = 8;

/// Lo que ocupa de la hoja el cuerpo de la vista sin teclado, y con el teclado abierto como tope.
const double fraccionDeLaHoja = .62;
const double fraccionConTeclado = .80;

/// El aire que el campo pide, además de su alto, para quedar entero. `EditableText` lleva el cursor a
/// la vista con 20 dp de aire arriba y, abajo, lo que piden los controles de selección (35 dp en
/// Android): el cursor (23 dp a 1×) más esos 55 dp tiene que caber en la zona que se desplaza; si no
/// cabe, el campo se alinea con un borde y queda cortado del otro. El cursor mide en proporción al
/// campo (campo menos 28 dp), así que el campo más este relleno da siempre lo que el cursor pide.
const double rellenoDelCampo = 28;

/// Lo que la zona del mapa conserva como mínimo cuando la hoja crece para dejar el motivo debajo de la
/// acción: «Cerrar» entero (48 dp, a 8 dp del borde de arriba, bajo la barra de estado) y el pin (44 dp
/// de alto con la punta en el centro del mapa, así que el mapa mide al menos 88 dp).
double reservaDelMapa(double barraDeArriba) => math.max(88, barraDeArriba + 8 + 48);

/// Lo que la hoja midió de sí misma y la medida necesita para saber cuánto alto pedir.
@immutable
class NecesidadHoja {
  const NecesidadHoja({required this.campo, required this.boton, this.motivo = 0});

  /// El alto de un campo de texto (sin su rótulo).
  final double campo;

  /// El alto de la acción fija, medido con el texto que tiene (no un alto fijo).
  final double boton;

  /// El alto del motivo que va debajo de la acción, con el aire que lo separa; 0 si no hay.
  final double motivo;

  @override
  bool operator ==(Object other) =>
      other is NecesidadHoja &&
      (other.campo - campo).abs() < .5 &&
      (other.boton - boton).abs() < .5 &&
      (other.motivo - motivo).abs() < .5;

  @override
  int get hashCode => Object.hash(campo.round(), boton.round(), motivo.round());
}

/// Dónde queda la acción de la hoja y su motivo.
enum LugarDeLaAccion {
  /// La acción fija al pie y el motivo debajo de ella (como en el canvas).
  fijaConMotivoAbajo,

  /// La acción fija al pie y el motivo al final de lo que se desplaza.
  fijaConMotivoArriba,

  /// La acción (y su motivo, arriba de ella) al final de lo que se desplaza.
  alFinalDeLoQueSeDesplaza,
}

/// El alto máximo de toda la hoja (con su borde y su asa) para un cuerpo de alto [cuerpo].
///
/// Sin teclado, o antes de que la hoja se haya medido, es el 62 %. Con el teclado, crece solo si el
/// campo con foco no entra entero sobre la acción dentro del 62 %, y lo justo para que entre, sin pasar
/// del 80 %: así el mapa no pierde más de lo necesario. El motivo debajo de la acción se suma a lo que
/// pide mientras el mapa conserve la [reservaDelMapa]; si no, queda al final de lo que se desplaza.
double topeDeLaHoja({
  required double cuerpo,
  required double barraDeArriba,
  required double barraDeAbajo,
  required bool tecladoAbierto,
  NecesidadHoja? necesidad,
}) {
  final base = cuerpo * fraccionDeLaHoja;
  if (!tecladoAbierto || necesidad == null || necesidad.campo <= 0) return base;
  final maximo = cuerpo * fraccionConTeclado;
  final cromo = cromoDeLaHoja + barraDeAbajo;
  final sinMotivo =
      cromo + separacionDelBoton + necesidad.boton + necesidad.campo + rellenoDelCampo;
  final conMotivo = sinMotivo + necesidad.motivo;
  final conElMapa = math.min(maximo, cuerpo - reservaDelMapa(barraDeArriba));
  final pide = conMotivo <= conElMapa ? conMotivo : sinMotivo;
  return math.max(base, math.min(pide, maximo));
}

/// Dónde va la acción dentro de la hoja, con lo que realmente le queda de alto ([contenido]: el alto
/// que recibe lo de adentro del borde y del asa).
///
/// - Con el teclado abierto manda el campo que se escribe: la acción queda fija mientras le deje a lo
///   que se desplaza el alto de un campo entero; si no, pasa al final de lo que se desplaza.
/// - Sin teclado: el motivo va debajo mientras lo fijo (acción y motivo) no pase de dos tercios de la
///   hoja y a lo que se desplaza le quede al menos el alto de un campo (#305, #320).
LugarDeLaAccion lugarDeLaAccion({
  required double contenido,
  required bool tecladoAbierto,
  required double boton,
  required double motivo,
  double? campo,
}) {
  final hayMotivo = motivo > 0;
  final fijoConMotivo = separacionDelBoton + boton + (hayMotivo ? separacionDelMotivo + motivo : 0);
  if (tecladoAbierto) {
    final campoEntero = (campo ?? 0) + (campo == null ? 0 : rellenoDelCampo);
    if (fijoConMotivo + campoEntero <= contenido) return LugarDeLaAccion.fijaConMotivoAbajo;
    if (separacionDelBoton + boton + campoEntero <= contenido) {
      return LugarDeLaAccion.fijaConMotivoArriba;
    }
    return LugarDeLaAccion.alFinalDeLoQueSeDesplaza;
  }
  if (!hayMotivo) return LugarDeLaAccion.fijaConMotivoAbajo;
  if (fijoConMotivo > contenido * (2 / 3)) return LugarDeLaAccion.fijaConMotivoArriba;
  final cabeElCampo = campo == null || contenido - fijoConMotivo >= campo;
  return cabeElCampo ? LugarDeLaAccion.fijaConMotivoAbajo : LugarDeLaAccion.fijaConMotivoArriba;
}

/// Lo que la hoja de adentro sabe de la medida: si el teclado está abierto y cómo informar lo que
/// midió.
class MedidaDeLaHoja extends InheritedWidget {
  const MedidaDeLaHoja({
    super.key,
    required this.tecladoAbierto,
    required this.informar,
    required super.child,
  });

  final bool tecladoAbierto;
  final ValueChanged<NecesidadHoja> informar;

  /// `null` si la hoja no está dentro de una [HojaInferior] (por ejemplo, en un test de la hoja sola).
  static MedidaDeLaHoja? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MedidaDeLaHoja>();

  @override
  bool updateShouldNotify(MedidaDeLaHoja old) => old.tecladoAbierto != tecladoAbierto;
}

/// El borde y el asa de la hoja inferior de las vistas 03 y 07, con el alto que [topeDeLaHoja] da.
///
/// [cuerpo] es el alto del cuerpo de la pantalla (ya sin el teclado) y [tecladoAbierto] se lee arriba
/// del `Scaffold`: adentro de su cuerpo `viewInsets.bottom` siempre da 0.
class HojaInferior extends StatefulWidget {
  const HojaInferior({
    super.key,
    required this.cuerpo,
    required this.tecladoAbierto,
    required this.hijo,
  });

  final double cuerpo;
  final bool tecladoAbierto;
  final Widget hijo;

  @override
  State<HojaInferior> createState() => _HojaInferiorState();
}

class _HojaInferiorState extends State<HojaInferior> {
  /// Lo último que la hoja de adentro midió de sí misma.
  final _necesidad = ValueNotifier<NecesidadHoja?>(null);

  @override
  void dispose() {
    _necesidad.dispose();
    super.dispose();
  }

  void _informar(NecesidadHoja nueva) {
    if (_necesidad.value != nueva) _necesidad.value = nueva;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NecesidadHoja?>(
      valueListenable: _necesidad,
      builder: (context, necesidad, _) {
        final tope = topeDeLaHoja(
          cuerpo: widget.cuerpo,
          barraDeArriba: MediaQuery.paddingOf(context).top,
          barraDeAbajo: MediaQuery.paddingOf(context).bottom,
          tecladoAbierto: widget.tecladoAbierto,
          necesidad: necesidad,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: tope),
          child: MedidaDeLaHoja(
            tecladoAbierto: widget.tecladoAbierto,
            informar: _informar,
            child: Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: const Color(0x1F0E1A2B),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: ColoresAlta.grisBorde,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Flexible(child: widget.hijo),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
