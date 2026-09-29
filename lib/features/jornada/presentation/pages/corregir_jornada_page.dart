import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/sesion.dart';
import '../../domain/entities/jornada.dart';
import '../formato_jornada.dart';
import '../providers/jornada_actual_notifier.dart';

/// "¿A qué hora terminaste?" (HU-JOR-002, "Jornada que quedó abierta"): corrige una jornada que
/// quedó abierta de un día anterior, con una hora elegida a mano entre el inicio (excluido) y
/// las 23:59 de ese día — [FinalizarJornadaUseCase] valida el rango real; acá solo se ofrece el
/// selector, nunca se inventa un fin. `JornadaPage` llega a esta pantalla cuando "Finalizar
/// jornada" devuelve `FailureJornadaDeDiaAnterior` (issue #109). Vista 21 del diseño (A08); el texto
/// de la explicación es el literal de la HU, no la propuesta del diseño.
class CorregirJornadaPage extends ConsumerStatefulWidget {
  const CorregirJornadaPage({super.key, required this.sesion, required this.inicio});

  final Sesion sesion;

  /// Inicio de la jornada que quedó abierta.
  final DateTime inicio;

  @override
  ConsumerState<CorregirJornadaPage> createState() => _CorregirJornadaPageState();
}

class _CorregirJornadaPageState extends ConsumerState<CorregirJornadaPage> {
  TimeOfDay? _horaElegida;
  bool _cerrando = false;
  String? _error;

  DateTime get _inicioLocal => widget.inicio.toLocal();

  /// [_horaElegida] combinada con el día de [Jornada.inicio] (la corrección es siempre ese día).
  DateTime? get _horaCompleta {
    final elegida = _horaElegida;
    if (elegida == null) return null;
    final base = _inicioLocal;
    return DateTime(base.year, base.month, base.day, elegida.hour, elegida.minute);
  }

  Future<void> _elegirHora() async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: _horaElegida ?? TimeOfDay.fromDateTime(_inicioLocal),
      helpText: 'A QUÉ HORA TERMINASTE',
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _horaElegida = elegida;
      _error = null;
    });
  }

  Future<void> _cerrar() async {
    final hora = _horaCompleta;
    if (hora == null || _cerrando) return;

    setState(() {
      _cerrando = true;
      _error = null;
    });

    final resultado = await ref
        .read(jornadaActualProvider(widget.sesion.usuarioId).notifier)
        .finalizar(hora: hora);

    if (!mounted) return;

    resultado.fold(
      (failure) => setState(() {
        _cerrando = false;
        _error = switch (failure) {
          FailureHoraFueraDeRango(:final mensaje) => '$mensaje Elegí otra hora y volvé a intentar.',
          Failure(:final mensaje) => mensaje,
        };
      }),
      (cerrada) => Navigator.of(context).pop(cerrada),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    final mensaje = FailureJornadaDeDiaAnterior(inicio: widget.inicio).mensaje;
    final horaElegida = _horaCompleta;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (restricciones.maxHeight - 26).clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        key: const Key('corregir_jornada_atras'),
                        tooltip: 'Volver',
                        onPressed: _cerrando ? null : () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            const SizedBox(height: 12),
                            Text(
                              'JORNADA SIN CERRAR',
                              style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                            ),
                            Text('¿A qué hora terminaste?', style: theme.textTheme.headlineMedium),
                            Text(
                              mensaje,
                              key: const Key('corregir_jornada_mensaje'),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: esquema.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'A QUÉ HORA TERMINASTE',
                              style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                            ),
                            InkWell(
                              key: const Key('corregir_jornada_elegir_hora'),
                              onTap: _cerrando ? null : _elegirHora,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 48),
                                padding: const EdgeInsets.only(top: 4, bottom: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: colores.bordeInput, width: 1.5),
                                  ),
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.end,
                                  spacing: 12,
                                  children: [
                                    Text(
                                      horaElegida == null ? '--:--' : horaCorta(horaElegida),
                                      key: const Key('corregir_jornada_hora'),
                                      style: theme.textTheme.headlineMedium,
                                    ),
                                    Text(
                                      'Elegir la hora',
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: esquema.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              '${diaCorto(widget.inicio)} · después de las '
                              '${horaCorta(widget.inicio)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colores.gris,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: [
                      if (_error case final error?)
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            key: const Key('corregir_jornada_error'),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: esquema.errorContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 12,
                              children: [
                                Icon(Icons.error_outline, color: esquema.onErrorContainer),
                                Expanded(
                                  child: Text(
                                    error,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: esquema.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      FilledButton(
                        key: const Key('corregir_jornada_cerrar'),
                        onPressed: (horaElegida == null || _cerrando) ? null : _cerrar,
                        child: _cerrando
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                horaElegida == null
                                    ? 'Cerrar'
                                    : 'Terminé a las ${horaCorta(horaElegida)}',
                              ),
                      ),
                    ],
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
