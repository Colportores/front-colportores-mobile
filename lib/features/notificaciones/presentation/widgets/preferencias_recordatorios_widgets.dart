import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../agenda/domain/entities/anticipacion_recordatorio.dart';
import 'aviso_notificaciones.dart';

/// Tarjeta blanca con borde de las preferencias (el `toggle` y el `slider` del canvas, vista 24 B).
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.hijo});

  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `Material` y no `DecoratedBox`: el renglón del interruptor pinta su fondo y su toque ahí.
    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: hijo,
    );
  }
}

/// «Recordatorios de agenda» (24B·01): título, detalle y el interruptor. Todo el renglón se toca; el
/// lector de pantalla lo anuncia como un interruptor con su estado.
class InterruptorRecordatorios extends StatelessWidget {
  const InterruptorRecordatorios({super.key, required this.activado, required this.onCambio});

  final bool activado;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return _Tarjeta(
      hijo: SwitchListTile(
        key: const Key('pref_recordatorios_interruptor'),
        value: activado,
        onChanged: onCambio,
        contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          TextosNotificaciones.recordatoriosTitulo,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          TextosNotificaciones.recordatoriosDetalle,
          style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
        ),
        activeThumbColor: Colors.white,
        activeTrackColor: theme.colorScheme.primary,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: const Color(0xFF90A0B7),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (estados) =>
              estados.contains(WidgetState.selected) ? Colors.transparent : const Color(0xFF5B6B82),
        ),
      ),
    );
  }
}

/// «Anticipación» (24B·01): minutos antes de la visita, de 5 a 120.
///
/// Mientras se arrastra solo se mueve lo que se ve; el cambio se pide al soltar ([onGuardar]). Para el
/// lector de pantalla es un control ajustable de a 5 minutos por vez (subir y bajar), que guarda al
/// instante. [habilitada] en `false` (con los recordatorios apagados) lo deja a la vista y sin tocar.
class TarjetaAnticipacion extends StatefulWidget {
  const TarjetaAnticipacion({
    super.key,
    required this.minutos,
    required this.habilitada,
    required this.onGuardar,
  });

  final int minutos;
  final bool habilitada;
  final ValueChanged<int> onGuardar;

  /// El paso del lector de pantalla (decidido el 27/10, mapa §2: de a 5 con el lector, de a 1 con el
  /// dedo, siempre entre 5 y 120).
  static const int pasoAccesible = 5;

  @override
  State<TarjetaAnticipacion> createState() => _TarjetaAnticipacionState();
}

class _TarjetaAnticipacionState extends State<TarjetaAnticipacion> {
  /// El valor mientras el dedo arrastra; `null` si no se está arrastrando.
  int? _arrastre;

  int get _visible => _arrastre ?? widget.minutos;

  void _ajustar(int paso) {
    final nuevo = AnticipacionRecordatorio.acotar(widget.minutos + paso);
    if (nuevo != widget.minutos) widget.onGuardar(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final valor = TextosNotificaciones.anticipacionValor(_visible);
    final mas = AnticipacionRecordatorio.acotar(_visible + TarjetaAnticipacion.pasoAccesible);
    final menos = AnticipacionRecordatorio.acotar(_visible - TarjetaAnticipacion.pasoAccesible);
    return _Tarjeta(
      hijo: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  TextosNotificaciones.anticipacionTitulo,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                ExcludeSemantics(
                  child: Text(
                    valor,
                    key: const Key('pref_anticipacion_valor'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.w500,
                      color: widget.habilitada ? theme.colorScheme.primary : colores.gris,
                    ),
                  ),
                ),
              ],
            ),
            Semantics(
              slider: true,
              enabled: widget.habilitada,
              label: TextosNotificaciones.anticipacionTitulo,
              value: valor,
              increasedValue: TextosNotificaciones.anticipacionValor(mas),
              decreasedValue: TextosNotificaciones.anticipacionValor(menos),
              onIncrease: widget.habilitada
                  ? () => _ajustar(TarjetaAnticipacion.pasoAccesible)
                  : null,
              onDecrease: widget.habilitada
                  ? () => _ajustar(-TarjetaAnticipacion.pasoAccesible)
                  : null,
              child: ExcludeSemantics(
                child: Slider(
                  key: const Key('pref_anticipacion_slider'),
                  value: _visible.toDouble(),
                  min: AnticipacionRecordatorio.minimo.toDouble(),
                  max: AnticipacionRecordatorio.maximo.toDouble(),
                  divisions: AnticipacionRecordatorio.maximo - AnticipacionRecordatorio.minimo,
                  onChanged: widget.habilitada
                      ? (v) => setState(() => _arrastre = v.round())
                      : null,
                  onChangeEnd: widget.habilitada
                      ? (v) {
                          final elegido = v.round();
                          setState(() => _arrastre = null);
                          if (elegido != widget.minutos) widget.onGuardar(elegido);
                        }
                      : null,
                ),
              ),
            ),
            ExcludeSemantics(
              // `Wrap` y no `Row`: con el texto al 300 % las dos puntas no entran en un renglón.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text(
                    TextosNotificaciones.anticipacionMin,
                    style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                  ),
                  Text(
                    TextosNotificaciones.anticipacionMax,
                    style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El «cargando» de las preferencias (24B·05): bloques grises con la forma de lo que viene.
class CargandoPreferencias extends StatelessWidget {
  const CargandoPreferencias({super.key});

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
          key: const Key('notificaciones_cargando'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [bloque(60), bloque(96)],
        ),
      ),
    );
  }
}
