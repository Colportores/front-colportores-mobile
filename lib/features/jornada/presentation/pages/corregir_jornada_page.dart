import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/sesion.dart';
import '../../domain/jornada_sin_cerrar.dart';
import '../formato_jornada.dart';
import '../providers/jornada_actual_notifier.dart';
import '../providers/jornada_providers.dart';
import '../widgets/hoja_hora_inicio.dart';

/// "¿A qué hora terminaste?" (HU-JOR-002, "Jornada que quedó abierta"): corrige una jornada que
/// quedó abierta de un día anterior, con una hora elegida a mano entre el inicio (excluido) y
/// 12 h después, sin pasar de ahora: el fin puede caer al día siguiente, aunque cruce la
/// medianoche (decisión de Cristian, 30/09, #250) — [FinalizarJornadaUseCase] valida el rango
/// real ([JornadaSinCerrar]); acá solo se ofrece el selector, nunca se inventa un fin.
/// `JornadaPage` llega a esta pantalla cuando "Finalizar jornada" devuelve
/// `FailureJornadaDeDiaAnterior` (issue #109). Vista 21 del diseño (A08); el texto de la
/// explicación es el literal de la HU, no la propuesta del diseño.
class CorregirJornadaPage extends ConsumerStatefulWidget {
  const CorregirJornadaPage({super.key, required this.sesion, required this.inicio});

  final Sesion sesion;

  /// Inicio de la jornada que quedó abierta.
  final DateTime inicio;

  @override
  ConsumerState<CorregirJornadaPage> createState() => _CorregirJornadaPageState();
}

class _CorregirJornadaPageState extends ConsumerState<CorregirJornadaPage> {
  /// La hora de fin que eligió, como instante absoluto: puede caer en el día del inicio o en el
  /// siguiente, así que no alcanza con la hora del reloj.
  DateTime? _horaElegida;
  bool _cerrando = false;
  String? _error;

  /// Del primer minuto válido al último, en la zona del dispositivo y al minuto, o `null` si ya no
  /// queda ninguno (el reloj del teléfono quedó antes del inicio): ahí no hay hora que elegir y la
  /// pantalla no puede ser una trampa, así que deja volver. Es la misma regla que valida el caso
  /// de uso ([JornadaSinCerrar]).
  ({DateTime primero, DateTime ultimo})? _rango(DateTime ahora) {
    final primero = JornadaSinCerrar.primerMinutoDelFin(widget.inicio).toLocal();
    final tope = JornadaSinCerrar.topeDelFin(inicio: widget.inicio, ahora: ahora).toLocal();
    final ultimo = DateTime(tope.year, tope.month, tope.day, tope.hour, tope.minute);
    return ultimo.isBefore(primero) ? null : (primero: primero, ultimo: ultimo);
  }

  /// Si el fin cae al día siguiente del inicio (el rango cruza la medianoche) lo dice, porque
  /// "00:05" solo no aclara de qué día es. `null` si cae el mismo día.
  String? _notaDelDia(DateTime hora) => JornadaSinCerrar.caeEnOtroDia(widget.inicio, hora)
      ? 'Termina el ${diaCorto(hora).toLowerCase()}, al día siguiente.'
      : null;

  /// La hoja propia (la misma que Hoy) en vez del selector del sistema: valida el rango sin
  /// ajustar nada en silencio y aguanta el texto al 200 %.
  Future<void> _elegirHora() async {
    final rango = _rango(ref.read(relojJornadaProvider)());
    if (rango == null) return;
    final maximo = rango.ultimo.difference(rango.primero).inMinutes;
    final actual = _horaElegida;
    final elegida = await mostrarHojaHoraInicio(
      context,
      ahora: rango.ultimo,
      margenMinutos: maximo,
      minutosAtras: actual == null
          ? maximo
          : rango.ultimo.difference(actual).inMinutes.clamp(0, maximo),
      pregunta: '¿A qué hora terminaste?',
      etiquetaCampo: 'HORA DE FIN',
      mostrarRelativo: false,
      notaDeHora: _notaDelDia,
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _horaElegida = elegida.hora;
      _error = null;
    });
  }

  Future<void> _cerrar() async {
    final hora = _horaElegida;
    if (hora == null || _cerrando) return;

    setState(() {
      _cerrando = true;
      _error = null;
    });

    final resultado = await ref
        .read(jornadaActualProvider(widget.sesion.usuarioId).notifier)
        .finalizar(hora: hora);

    if (!mounted) return;

    // Otro teléfono ya la cerró (o un doble toque): no hay nada que corregir. Sale sin jornada y
    // Hoy relee lo guardado (`finalizar` ya invalidó el estado). Sin esto, con la pantalla sin
    // salida, la persona quedaría atrapada.
    if (resultado.fold((failure) => failure is FailureSinJornadaActiva, (_) => false)) {
      Navigator.of(context).pop();
      return;
    }

    resultado.fold(
      (failure) => setState(() {
        _cerrando = false;
        _error = switch (failure) {
          FailureHoraFueraDeRango(:final mensaje) => '$mensaje Elegí otra hora y volvé a intentar.',
          // Un fallo del sistema al guardar: qué pasó y qué hacer (el mismo texto que Hoy).
          FailureInesperado() || FailureServidor() || FailureSinConexion() =>
            'No pudimos guardar el fin de tu jornada, que sigue abierta. Probá de nuevo; si sigue '
                'pasando, avisale a tu coordinador.',
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
    final horaElegida = _horaElegida;
    final sinHoraValida = _rango(ref.watch(relojJornadaProvider)()) == null;

    // Sin flecha de volver ni atrás del sistema (decisión de Cristian, 29/09, como el diseño): el
    // colportor indica la hora de fin antes de seguir; nunca se inventa un fin. El `pop` al cerrar
    // (o si la jornada ya estaba cerrada) no pasa por acá, y sin minuto válido sí se puede volver.
    return PopScope(
      canPop: sinHoraValida,
      child: _scaffold(context, theme, colores, esquema, mensaje, horaElegida, sinHoraValida),
    );
  }

  Widget _scaffold(
    BuildContext context,
    ThemeData theme,
    ColoresColportaje colores,
    ColorScheme esquema,
    String mensaje,
    DateTime? horaElegida,
    bool sinHoraValida,
  ) {
    final notaDelDia = horaElegida == null ? null : _notaDelDia(horaElegida);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 44, 20, 26),
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
                      if (sinHoraValida)
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
                            if (notaDelDia != null)
                              Text(
                                notaDelDia,
                                key: const Key('corregir_jornada_dia_fin'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: esquema.onSurfaceVariant,
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
