import 'package:flutter/material.dart';

import '../formato_fuera_del_area.dart';
import '../mapa_base/modelo_mapa_base.dart' show ColoresMapa;
import 'piezas_alta.dart' show ColoresAlta;

/// Las claves de las piezas de «fuera del área» (#713).
abstract final class ClavesFueraDelArea {
  /// El aviso de las casas ocultas sobre el mapa (debajo de «Referencias»).
  static const avisoMapa = Key('fuera_del_area_aviso_mapa');

  /// El mismo aviso, primero en la lista de «Cercanía».
  static const avisoHoja = Key('fuera_del_area_aviso_hoja');

  /// El interruptor de «Referencias».
  static const interruptor = Key('fuera_del_area_interruptor');

  /// La fila de «Referencias» que explica la marca.
  static const leyenda = Key('fuera_del_area_leyenda');

  /// La etiqueta «FUERA DE TU ÁREA» (fila y hoja de la casa).
  static const etiqueta = Key('fuera_del_area_etiqueta');
}

/// La etiqueta «FUERA DE TU ÁREA» de la fila de «Cercanía» y de la hoja de la casa: la misma forma
/// que la de «BAJA», en el ámbar del aro del mapa (blanco sobre ámbar, 6,6:1).
class EtiquetaFueraDelArea extends StatelessWidget {
  const EtiquetaFueraDelArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: TextosFueraDelArea.etiquetaLector,
      excludeSemantics: true,
      child: Container(
        key: ClavesFueraDelArea.etiqueta,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: ColoresMapa.fueraDelArea,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          TextosFueraDelArea.etiqueta,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 1,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// El aro ámbar tal como lo dibuja el mapa, alrededor de un marcador [interior] (o vacío).
class AroFueraDelArea extends StatelessWidget {
  const AroFueraDelArea({super.key, this.lado = 28, this.interior});

  final double lado;
  final Widget? interior;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x99FFFFFF),
        shape: BoxShape.circle,
        border: Border.all(color: ColoresMapa.fueraDelArea, width: 3),
      ),
      child: interior,
    );
  }
}

/// El aviso de las casas fuera del área ocultas: «3 casas fuera de tu área ocultas · Ver». Todo el
/// aviso es el botón (48 dp de alto como mínimo); el texto se parte en renglones si no entra.
class AvisoFueraDelAreaOcultas extends StatelessWidget {
  const AvisoFueraDelAreaOcultas({super.key, required this.cantidad, required this.alVer});

  final int cantidad;
  final VoidCallback alVer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      container: true,
      label: FormatoFueraDelArea.ocultasLector(cantidad),
      onTap: alVer,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: alVer,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AroFueraDelArea(lado: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      FormatoFueraDelArea.ocultas(cantidad),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        color: ColoresAlta.tinta,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    TextosFueraDelArea.ver,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ColoresAlta.azul,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
