import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/domain/entities/sesion.dart';
import '../../domain/entities/jornada.dart';
import '../formato_jornada.dart';
import '../providers/jornada_actual_notifier.dart';

/// "¿A qué hora terminaste?" (HU-JOR-002, "Jornada que quedó abierta"): corrige una jornada que
/// quedó abierta de un día anterior, con una hora elegida a mano entre el inicio (excluido) y
/// las 23:59 de ese día — [FinalizarJornadaUseCase] valida el rango real; acá solo se ofrece el
/// selector, nunca se inventa un fin. `JornadaPage` llega a esta pantalla cuando "Finalizar
/// jornada" devuelve `FailureJornadaDeDiaAnterior` (issue #109). Sin diseño de Claude Design, con
/// el tema y los componentes existentes (decisión del 22/09 para las vistas del Sprint 4).
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
    final mensaje = FailureJornadaDeDiaAnterior(inicio: widget.inicio).mensaje;
    final horaElegida = _horaElegida;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const Key('corregir_jornada_atras'),
                tooltip: 'Volver',
                onPressed: _cerrando ? null : () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text('JORNADA SIN CERRAR', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Text(
                    '¿A qué hora terminaste?',
                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    mensaje,
                    key: const Key('corregir_jornada_mensaje'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    key: const Key('corregir_jornada_elegir_hora'),
                    onPressed: _cerrando ? null : _elegirHora,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      horaElegida == null
                          ? 'Elegir la hora'
                          : 'Terminé a las ${horaCorta(_horaCompleta!)}',
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_error case final error?) ...[
                    Text(
                      error,
                      key: const Key('corregir_jornada_error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    key: const Key('corregir_jornada_cerrar'),
                    onPressed: (horaElegida == null || _cerrando) ? null : _cerrar,
                    child: _cerrando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cerrar'),
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
