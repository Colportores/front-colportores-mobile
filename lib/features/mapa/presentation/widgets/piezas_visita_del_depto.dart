import 'package:flutter/material.dart';

import '../../../agenda/domain/entities/visita.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/ultima_visita_del_espacio.dart';
import '../textos_personas.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart';

/// Claves de lo que el encabezado del depto (vista 11·04) agrega para la visita.
abstract final class ClavesVisitaDelDepto {
  static const estado = Key('visita_del_depto_estado');
  static const registrar = Key('visita_del_depto_registrar');
}

/// El estado de la última visita del depto y «Registrar visita» (vista 11·04, HU-VIS-005, #151): la
/// píldora verde con el tilde y «Entrevista hecha · 20/09», y el botón azul oscuro de abajo.
///
/// - [ultima] `null` con [conEstado]: el depto no tiene ninguna visita («Sin visitas todavía»). Sin
///   [conEstado] (se está leyendo, o no se pudo leer) no se dibuja el estado: no se afirma lo que no se
///   sabe.
/// - [alRegistrar] `null`: no se ofrece el botón (sin destino enganchado, o el depto está dado de baja).
class VisitaDelDepto extends StatelessWidget {
  const VisitaDelDepto({
    super.key,
    required this.conEstado,
    required this.ultima,
    required this.alRegistrar,
  });

  final bool conEstado;
  final UltimaVisitaDelEspacio? ultima;
  final VoidCallback? alRegistrar;

  @override
  Widget build(BuildContext context) {
    if (!conEstado && alRegistrar == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (conEstado) _EstadoDeLaVisita(ultima: ultima),
          if (conEstado && alRegistrar != null) const SizedBox(height: 10),
          if (alRegistrar != null)
            FilledButton(
              key: ClavesVisitaDelDepto.registrar,
              onPressed: alRegistrar,
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 52),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
              child: const Text(TextosPersonas.registrarVisita, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

/// La píldora del estado: la insignia de la visita y su rótulo con el día.
class _EstadoDeLaVisita extends StatelessWidget {
  const _EstadoDeLaVisita({required this.ultima});

  final UltimaVisitaDelEspacio? ultima;

  @override
  Widget build(BuildContext context) {
    final visita = ultima;
    final texto = visita == null ? TextosPersonas.sinVisitas : FormatoPersonas.ultimaVisita(visita);
    final (EstadoCasa estado, Color fondo, Color tinta) = switch (visita?.resultado) {
      null => (EstadoCasa.sinVisita, ColoresAlta.grisFondo, ColoresAlta.tinta),
      TipoResultadoVisita.entrevista => (
        EstadoCasa.entrevistaHecha,
        ColoresAlta.verdeFondo,
        const Color(0xFF154D29),
      ),
      TipoResultadoVisita.venta => (
        EstadoCasa.ventaCompleta,
        ColoresAlta.verdeFondo,
        const Color(0xFF154D29),
      ),
      TipoResultadoVisita.noContesto => (
        EstadoCasa.noContesto,
        ColoresAlta.grisFondo,
        ColoresAlta.tinta,
      ),
      TipoResultadoVisita.rechazo => (
        EstadoCasa.rechazo,
        const Color(0xFFF8E6E4),
        const Color(0xFF7A241F),
      ),
      TipoResultadoVisita.cobranza => (
        EstadoCasa.cobranzaPendiente,
        ColoresAlta.azulFondo,
        ColoresAlta.azul,
      ),
    };
    return Semantics(
      key: ClavesVisitaDelDepto.estado,
      container: true,
      label: texto,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            InsigniaEstadoCasa(estado: estado, tamano: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tinta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
