import 'package:flutter/material.dart';

import '../textos_alta_por_pin.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart' show ColoresLista;
import 'pin_nueva_casa.dart';

/// N·01 «Soltar el pin: ¿está acá?» (vista 39): la hoja de abajo mientras el pin está puesto en el mapa.
/// Sin velo (el mapa sigue a la vista y se toca para ajustar el lugar), con la dirección que el mapa
/// conoce de ese punto como título y «Confirmar posición».
///
/// La ✕ (y el atrás del sistema) cancelan: el canvas no la dibuja, pero sin ella un pin soltado de
/// más no tiene salida a la vista en el teléfono sin botón de atrás.
class HojaPosicionNueva extends StatelessWidget {
  const HojaPosicionNueva({
    super.key,
    required this.titulo,
    required this.alConfirmar,
    required this.alCancelar,
  });

  /// La dirección del punto, «Buscando la dirección…» o «Sin dirección en el mapa».
  final String titulo;
  final VoidCallback alConfirmar;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height;
    return Container(
      key: ClavesPinNuevaCasa.posicion,
      constraints: BoxConstraints(maxHeight: alto * .6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x290E1A2B), blurRadius: 24, offset: Offset(0, -8))],
      ),
      // «Confirmar posición» queda fijo al pie: con el texto grande en un teléfono chico lo que se
      // desplaza es el título y la ayuda, nunca la acción.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(22, 10, 10, 0), child: _Asa()),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 10, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14, right: 8),
                          child: Semantics(
                            header: true,
                            liveRegion: true,
                            child: Text(
                              titulo,
                              key: ClavesPinNuevaCasa.direccion,
                              style: const TextStyle(
                                fontFamily: 'SourceSerif4',
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: ColoresLista.tinta,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: TextosAltaPorPin.cancelar,
                        onTap: alCancelar,
                        child: ExcludeSemantics(
                          child: InkResponse(
                            key: ClavesPinNuevaCasa.cancelar,
                            onTap: alCancelar,
                            radius: 24,
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.close, size: 20, color: ColoresLista.grisTexto),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      TextosAltaPorPin.ayudaPosicion,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: FilledButton(
              key: ClavesPinNuevaCasa.confirmar,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
              onPressed: alConfirmar,
              child: const Text(TextosAltaPorPin.confirmarPosicion, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColoresAlta.grisBorde,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}
