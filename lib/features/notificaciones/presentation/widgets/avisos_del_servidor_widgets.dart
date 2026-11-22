import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/avisos_del_servidor.dart';
import 'aviso_notificaciones.dart';
import 'preferencias_recordatorios_widgets.dart';

/// Abre el selector de hora del sistema (24 h) en [actual] y devuelve la hora elegida, o `null` si se
/// cerró sin elegir.
Future<HoraDelAviso?> elegirHoraDelAviso(BuildContext context, HoraDelAviso actual) async {
  final elegida = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: actual.hora, minute: actual.minuto),
    helpText: TextosNotificaciones.horaElegirAyuda,
    builder: (contexto, hijo) => MediaQuery(
      data: MediaQuery.of(contexto).copyWith(alwaysUse24HourFormat: true),
      child: hijo!,
    ),
  );
  if (elegida == null) return null;
  return HoraDelAviso(elegida.hour, elegida.minute);
}

/// El renglón «Hora del aviso · 09:00» de una tarjeta (HU-NOT-004, decisión «Hora avisos»): se toca
/// para abrir el selector de hora. [habilitada] en `false` (con el aviso apagado) lo deja a la vista
/// y sin tocar. Un segundo toque mientras el selector está abierto no abre otro.
class FilaHoraDelAviso extends StatefulWidget {
  const FilaHoraDelAviso({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.hora,
    required this.habilitada,
    required this.onElegir,
    this.valorKey,
  });

  final String titulo;
  final String detalle;
  final HoraDelAviso hora;
  final bool habilitada;
  final ValueChanged<HoraDelAviso> onElegir;
  final Key? valorKey;

  @override
  State<FilaHoraDelAviso> createState() => _FilaHoraDelAvisoState();
}

class _FilaHoraDelAvisoState extends State<FilaHoraDelAviso> {
  bool _eligiendo = false;

  Future<void> _elegir() async {
    if (_eligiendo) return;
    setState(() => _eligiendo = true);
    try {
      final elegida = await elegirHoraDelAviso(context, widget.hora);
      if (elegida != null && elegida != widget.hora && mounted) widget.onElegir(elegida);
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final habilitada = widget.habilitada;
    return Semantics(
      button: true,
      enabled: habilitada,
      label: widget.titulo,
      value: widget.hora.texto,
      hint: habilitada ? 'Tocá para cambiarla' : null,
      // El toque va en la semántica propia: `excludeSemantics` deja afuera el del `InkWell`, y sin esto
      // el lector de pantalla anuncia el botón pero no lo puede activar.
      onTap: habilitada && !_eligiendo ? () => unawaited(_elegir()) : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: habilitada && !_eligiendo ? () => unawaited(_elegir()) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            // `Wrap` y no `Row`: con el texto al 200 % el título y la hora no entran en un renglón.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.titulo,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: habilitada ? null : colores.gris,
                        ),
                      ),
                      Text(
                        widget.detalle,
                        style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                      ),
                    ],
                  ),
                ),
                Text(
                  widget.hora.texto,
                  key: widget.valorKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w500,
                    color: habilitada ? theme.colorScheme.primary : colores.gris,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Cuotas» (24B·01) con su hora: el interruptor y, debajo, «Hora del aviso».
class TarjetaAvisoCuotas extends StatelessWidget {
  const TarjetaAvisoCuotas({
    super.key,
    required this.activado,
    required this.hora,
    required this.onCambio,
    required this.onElegirHora,
  });

  final bool activado;
  final HoraDelAviso hora;
  final ValueChanged<bool> onCambio;
  final ValueChanged<HoraDelAviso> onElegirHora;

  @override
  Widget build(BuildContext context) => TarjetaPreferencia(
    hijo: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InterruptorPreferencia(
          interruptorKey: const Key('aviso_cuotas_interruptor'),
          titulo: TextosNotificaciones.avisoCuotas,
          activado: activado,
          onCambio: onCambio,
        ),
        const Divider(height: 1),
        FilaHoraDelAviso(
          key: const Key('aviso_cuotas_hora'),
          valorKey: const Key('aviso_cuotas_hora_valor'),
          titulo: TextosNotificaciones.horaCuotaTitulo,
          detalle: TextosNotificaciones.horaCuotaDetalle,
          hora: hora,
          habilitada: activado,
          onElegir: onElegirHora,
        ),
      ],
    ),
  );
}

/// «Aviso de las visitas de mañana» (HU-NOT-004, decisión «Hora avisos»): la hora de «Mañana tenés
/// visitas». Con «Recordatorios de agenda» apagados queda a la vista y sin tocar.
class TarjetaHoraAgenda extends StatelessWidget {
  const TarjetaHoraAgenda({
    super.key,
    required this.hora,
    required this.habilitada,
    required this.onElegirHora,
  });

  final HoraDelAviso hora;
  final bool habilitada;
  final ValueChanged<HoraDelAviso> onElegirHora;

  @override
  Widget build(BuildContext context) => TarjetaPreferencia(
    hijo: FilaHoraDelAviso(
      key: const Key('aviso_agenda_hora'),
      valorKey: const Key('aviso_agenda_hora_valor'),
      titulo: TextosNotificaciones.horaAgendaTitulo,
      detalle: TextosNotificaciones.horaAgendaDetalle,
      hora: hora,
      habilitada: habilitada,
      onElegir: onElegirHora,
    ),
  );
}

/// El «cargando» de la sección AVISOS (24B·05): bloques grises con la forma de lo que viene.
class CargandoAvisos extends StatelessWidget {
  const CargandoAvisos({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto) => Container(
      height: alto,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE4),
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      label: 'Cargando',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('avisos_cargando'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [bloque(60), bloque(116), bloque(60), bloque(60)],
        ),
      ),
    );
  }
}
