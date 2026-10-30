import 'package:flutter/material.dart';

import '../../domain/entities/persona_del_espacio.dart';
import '../formato_hoja_casa.dart';
import 'piezas_alta.dart' show AvisoAlta, ColoresAlta;
import 'piezas_hoja_casa.dart';
import 'piezas_lista_ubicaciones.dart' show ColoresLista;

// Las piezas de la hoja de la casa «arriba» (vista 39, C·02 a C·05): las pestañas Personas, Historial
// y Notas, y el contenido de Personas. Historial y Notas llegan con sus issues (#446 y #447) por
// `pestanaHistorialDeLaCasaProvider` y `pestanaNotasDeLaCasaProvider`.

/// Las pestañas de la hoja arriba, en el orden del canvas.
enum PestanaHojaCasa {
  personas('personas', TextosPestanasHojaCasa.personas),
  historial('historial', TextosPestanasHojaCasa.historial),
  notas('notas', TextosPestanasHojaCasa.notas);

  const PestanaHojaCasa(this.id, this.rotulo);

  /// Para las claves de los tests.
  final String id;
  final String rotulo;
}

/// El control segmentado de las pestañas (canvas, `Bloques` · seg): una píldora gris `#F3F1EA` con una
/// opción blanca, azul y en negrita por la pestaña elegida. Cada opción mide 48 dp de alto, el objetivo
/// táctil mínimo.
///
/// Solo se ofrecen las pestañas que tienen contenido ([pestanas]); con una sola igual se dibuja (la
/// hoja no cambia de forma cuando llegan las otras).
class PestanasDeLaHoja extends StatelessWidget {
  const PestanasDeLaHoja({
    super.key,
    required this.pestanas,
    required this.elegida,
    required this.alElegir,
  });

  final List<PestanaHojaCasa> pestanas;
  final PestanaHojaCasa elegida;
  final ValueChanged<PestanaHojaCasa> alElegir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        key: ClavesHojaCasa.pestanas,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F1EA),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          spacing: 4,
          children: [
            for (final pestana in pestanas)
              Expanded(
                child: _Opcion(
                  pestana: pestana,
                  elegida: pestana == elegida,
                  alTocar: () => alElegir(pestana),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.pestana, required this.elegida, required this.alTocar});

  final PestanaHojaCasa pestana;
  final bool elegida;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      label: pestana.rotulo,
      onTap: alTocar,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ClavesHojaCasa.pestana(pestana.id),
          customBorder: const StadiumBorder(),
          onTap: alTocar,
          child: Ink(
            decoration: BoxDecoration(
              color: elegida ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: elegida
                  ? const [BoxShadow(color: Color(0x240E1A2B), blurRadius: 3, offset: Offset(0, 1))]
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text(
                    pestana.rotulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: elegida ? FontWeight.w600 : FontWeight.w500,
                      color: elegida ? const Color(0xFF002856) : ColoresAlta.tinta,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una persona de la pestaña: lo que hace falta para dibujar su fila.
typedef FilaDePersona = ({
  PersonaDelEspacio persona,
  int? saldoCentavos,
  DateTime? cuota,
  String? detalle,
  VoidCallback? alCobrar,
  VoidCallback? alAbrir,
});

/// La pestaña **Personas** (C·02): las personas del lugar, cada una con su fila, y «+ Agregar persona».
///
/// - Sin personas dice que no hay y, si [alAgregar] lo permite, ofrece agregar la primera.
/// - [alAgregar] `null` = no se ofrece (la casa está dada de baja: solo se ve, o no hay quién agregue).
/// - [guardada] es el aviso de la última alta («Guardamos a Jorge en este teléfono.»).
/// - Las filas se arman por fuera ([filas]): la pestaña no sabe de cobros ni de fichas.
class PestanaPersonasDeLaCasa extends StatelessWidget {
  const PestanaPersonasDeLaCasa({
    super.key,
    required this.filas,
    required this.alAgregar,
    required this.ocupada,
    this.guardada,
    this.ahora,
  });

  final List<FilaDePersona> filas;

  /// «Hoy», para saber si la cuota de una fila venció.
  final DateTime? ahora;
  final VoidCallback? alAgregar;
  final bool ocupada;
  final String? guardada;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ClavesHojaCasa.listaDePersonas,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (guardada != null)
          AvisoAlta(
            key: ClavesHojaCasa.personaGuardada,
            color: ColoresAlta.verde,
            glyph: '✓',
            texto: guardada!,
          ),
        if (filas.isEmpty)
          const Padding(
            key: ClavesHojaCasa.sinPersonas,
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Text(
              TextosPestanasHojaCasa.sinPersonas,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                height: 1.4,
                color: ColoresLista.grisTexto,
              ),
            ),
          ),
        for (final fila in filas)
          FilaPersonaDeLaCasa(
            key: ValueKey('fila_persona_${fila.persona.persona.id}'),
            persona: fila.persona.persona,
            saldoCentavos: fila.saldoCentavos,
            cuota: fila.cuota,
            ahora: ahora,
            detalle: fila.detalle,
            alCobrar: fila.alCobrar,
            alAbrir: fila.alAbrir,
            ocupada: ocupada,
          ),
        if (alAgregar != null) _EnlaceAgregar(alTocar: ocupada ? null : alAgregar),
      ],
    );
  }
}

/// «+ Agregar persona» (canvas: texto azul de 13,5), con un objetivo táctil de 48 dp.
class _EnlaceAgregar extends StatelessWidget {
  const _EnlaceAgregar({required this.alTocar});

  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: alTocar != null,
      label: TextosPestanasHojaCasa.agregarPersona,
      onTap: alTocar,
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InkWell(
          key: ClavesHojaCasa.agregarPersona,
          borderRadius: BorderRadius.circular(8),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: Text(
                  TextosPestanasHojaCasa.agregarPersona,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: alTocar == null ? ColoresLista.grisTexto : ColoresAlta.azul,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
