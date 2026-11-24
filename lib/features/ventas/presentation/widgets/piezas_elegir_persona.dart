import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../textos_elegir_persona.dart';

// Las piezas de «¿A quién le vendés?» que no existen en las vistas aprobadas: la caja de búsqueda
// (con el aspecto de la de Precios, vista 26) y el esqueleto mientras se leen las personas. La fila de
// cada persona es `FilaPersonaDeLaCasa` (32A·05).

/// La caja «Buscar por nombre o dirección».
class CampoDeBusquedaDePersonas extends StatelessWidget {
  const CampoDeBusquedaDePersonas({
    super.key,
    required this.controlador,
    required this.alCambiar,
    required this.alBorrar,
  });

  final TextEditingController controlador;
  final ValueChanged<String> alCambiar;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ColoresAgenda.bordeChip, width: 1.5),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Text('⌕', style: TextStyle(fontSize: 15, color: ColoresAgenda.gris)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('personas_busqueda'),
              controller: controlador,
              onChanged: alCambiar,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
              decoration: const InputDecoration(
                hintText: TextosElegirPersona.buscar,
                hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, color: Color(0xFF6B7688)),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controlador,
            builder: (context, valor, _) => valor.text.isEmpty
                ? const SizedBox(width: 14)
                : IconButton(
                    key: const Key('personas_borrar_busqueda'),
                    tooltip: TextosElegirPersona.borrarBusqueda,
                    onPressed: alBorrar,
                    icon: const Text(
                      '✕',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    color: ColoresAgenda.gris,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Mientras se leen las personas: tres filas grises, anunciadas como «Cargando las personas».
class EsqueletoDePersonas extends StatelessWidget {
  const EsqueletoDePersonas({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque() => Container(
      height: 60,
      decoration: BoxDecoration(
        color: ColoresAgenda.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Semantics(
        liveRegion: true,
        label: TextosElegirPersona.cargando,
        child: ExcludeSemantics(
          child: Column(
            key: const Key('personas_cargando'),
            spacing: 10,
            children: [bloque(), bloque(), bloque()],
          ),
        ),
      ),
    );
  }
}
