import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/item_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/presentation/formato_agenda.dart';
import '../../../agenda/presentation/providers/consulta_agenda_providers.dart';
import '../../../agenda/presentation/providers/detalle_agenda_providers.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../notificaciones/domain/entities/preferencias_recordatorios.dart';
import '../../domain/entities/estado_casa.dart';
import '../textos_ficha_persona.dart';
import 'estados_hoja_casa.dart';
import 'piezas_alta.dart' show ColoresAlta;
import 'piezas_ficha_persona.dart';
import 'piezas_lista_ubicaciones.dart' show InsigniaEstadoCasa;

/// «PRÓXIMA VISITA» de la ficha de la persona (vista 23, 23A·05, #405): la visita agendada que viene,
/// «Entrevista · jue 24/10 · 14:30», con su franja y a qué hora suena el aviso. Tocarla abre su
/// detalle (23C·01). Se lee en vivo: al agendar desde la ficha —o desde cualquier otro lado— aparece
/// sola, y al cancelarla o registrarla se va.
///
/// - Con la persona de [soloLectura] solo se ve si ya tiene una visita agendada, y sin «+ Agendar».
/// - Sin visita, «+ Agendar» (si hay [alAgendar]) y el texto de que todavía no hay ninguna; con
///   [mostrarSinVisita] apagado (la ficha vacía de 32B·05) no se dibuja nada.
/// - Mientras lee no ocupa lugar. Si no se puede leer, lo dice con «Reintentar»: la ficha sigue.
/// - El detalle se abre de a uno: un doble toque abre una sola vez; si falla, avisa y la tarjeta
///   vuelve a poder tocarse. **Sin destino** ([abrirDetalleDeAgendaProvider] `null`) no se toca y no
///   lleva «›».
class ProximaVisitaDeLaFicha extends ConsumerStatefulWidget {
  const ProximaVisitaDeLaFicha({
    super.key,
    required this.personaId,
    required this.colportorId,
    required this.ahora,
    required this.soloLectura,
    required this.alAgendar,
    this.mostrarSinVisita = true,
  });

  final String personaId;
  final String colportorId;
  final DateTime ahora;
  final bool soloLectura;

  /// «+ Agendar»; `null` si no se puede agendar desde acá.
  final VoidCallback? alAgendar;

  /// Dibujar la sección aunque no haya visita (con «+ Agendar» y el aviso de que no hay ninguna).
  final bool mostrarSinVisita;

  @override
  ConsumerState<ProximaVisitaDeLaFicha> createState() => _ProximaVisitaDeLaFichaState();
}

class _ProximaVisitaDeLaFichaState extends ConsumerState<ProximaVisitaDeLaFicha> {
  /// Hay un detalle abriéndose: es un campo y no solo estado de la UI para que corte el segundo toque
  /// aunque llegue antes de volver a dibujar.
  bool _abriendo = false;

  Future<void> _abrir(FutureOr<Object?> Function(String) destino, String agendaId) async {
    if (_abriendo) return;
    _abriendo = true;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      await destino(agendaId);
    } on Object {
      // El detalle del error puede llevar datos de la visita: se avisa y no se loguea.
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosAgenda.noPudimosAbrir)));
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clave = (colportorId: widget.colportorId, personaId: widget.personaId);
    final leida = ref.watch(visitasAgendadasDeLaPersonaProvider(clave));

    if (leida.hasError) {
      // Sin poder leer la agenda no se sabe si hay visita: se dice, con cómo seguir.
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          key: ClavesFicha.proximaVisita,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RotuloDeSeccion(texto: TextosFicha.proximaVisitaRotulo),
            const SizedBox(height: 6),
            AvisoHojaCasa.errorAlLeerAgendas(
              key: ClavesFicha.errorProximaVisita,
              alReintentar: () => ref.invalidate(visitasAgendadasDeLaPersonaProvider(clave)),
            ),
          ],
        ),
      );
    }
    final visitas = leida.value;
    if (visitas == null) return const SizedBox.shrink();

    final proxima = FormatoFicha.proximaVisita(visitas, widget.ahora);
    final puedeAgendar = !widget.soloLectura && widget.alAgendar != null;
    if (proxima == null && !(widget.mostrarSinVisita && puedeAgendar)) {
      return const SizedBox.shrink();
    }
    final detalle = ref.watch(abrirDetalleDeAgendaProvider);
    // Mientras no se saben las preferencias no se dice a qué hora suena el aviso: no se inventa.
    final preferencias = ref.watch(preferenciasDelAvisoProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        key: ClavesFicha.proximaVisita,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RotuloDeSeccion(
            texto: TextosFicha.proximaVisitaRotulo,
            accion: puedeAgendar ? TextosFicha.masAgendar : null,
            alAccion: puedeAgendar ? widget.alAgendar : null,
            claveAccion: ClavesFicha.botonAgendar,
          ),
          if (proxima == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                TextosFicha.sinProximaVisita,
                key: ClavesFicha.sinProximaVisita,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            TarjetaProximaVisita(
              key: ClavesFicha.tarjetaProximaVisita,
              item: proxima,
              ahora: widget.ahora,
              conAviso: !preferencias.isLoading,
              preferencias: preferencias.value,
              alTocar: detalle == null ? null : () => unawaited(_abrir(detalle, proxima.agenda.id)),
            ),
        ],
      ),
    );
  }
}

/// La tarjeta de una visita agendada en la ficha (23A·05): «Entrevista · jue 24/10 · 14:30» y, debajo,
/// «Primera tarde · te avisamos a las 14:00». Alto mínimo 64; sin [alTocar] no se toca y no lleva «›».
class TarjetaProximaVisita extends StatelessWidget {
  const TarjetaProximaVisita({
    super.key,
    required this.item,
    required this.ahora,
    this.preferencias,
    this.conAviso = true,
    this.alTocar,
  });

  final ItemAgenda item;
  final DateTime ahora;
  final PreferenciasRecordatorios? preferencias;

  /// Decir a qué hora suena el aviso; apagado mientras todavía no se leen las preferencias.
  final bool conAviso;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final vencida = item.estaVencida(ahora);
    final titulo = FormatoFicha.cuandoDeLaVisita(item, ahora);
    final detalle = FormatoFicha.detalleDeLaVisita(
      item,
      ahora,
      preferencias: preferencias,
      conAviso: conAviso,
    );
    final contenido = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InsigniaEstadoCasa(
          estado: item.agenda.tipo == TipoAgenda.entrevista
              ? EstadoCasa.entrevistaAgendada
              : EstadoCasa.cobranzaPendiente,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.tinta,
                ),
              ),
              if (detalle != null)
                Text(
                  detalle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: ColoresAgenda.gris,
                  ),
                ),
              if (vencida)
                const Text(
                  TextosAgenda.pasoLaHora,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ColoresAgenda.rojo,
                  ),
                ),
            ],
          ),
        ),
        if (alTocar != null) ...[
          const SizedBox(width: 8),
          const Text('›', style: TextStyle(color: Color(0xFF90A0B7), fontSize: 18)),
        ],
      ],
    );
    return Semantics(
      container: true,
      button: alTocar != null,
      label: [titulo, ?detalle, if (vencida) TextosAgenda.pasoLaHora].join('. '),
      onTap: alTocar,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: vencida ? ColoresAlta.ambarBorde : const Color(0xFFE3E7EE),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Material(
            color: Colors.transparent,
            child: alTocar == null
                ? Padding(padding: const EdgeInsets.all(12), child: contenido)
                : InkWell(
                    onTap: alTocar,
                    child: Padding(padding: const EdgeInsets.all(12), child: contenido),
                  ),
          ),
        ),
      ),
    );
  }
}
