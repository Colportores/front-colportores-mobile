import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../jornada/presentation/formato_jornada.dart';
import '../../../jornada/presentation/providers/jornada_actual_notifier.dart';
import '../../../jornada/presentation/providers/jornada_providers.dart';
import '../../../jornada/presentation/widgets/aviso_jornada.dart';
import '../../../jornada/presentation/widgets/con_espera.dart';
import '../../../jornada/presentation/widgets/fila_hora_jornada.dart';
import '../../../jornada/presentation/widgets/fin_de_jornada.dart';
import '../../domain/entities/sesion.dart';
import '../providers/sesion_notifier.dart';

/// Lo que dice la sección «Terminar jornada» de la pantalla de la cuenta restringida (#472).
/// El nombre del botón es el de la decisión de Cristian (25/10, «Jornada susp.»); el cierre usa los
/// mismos textos que «Hoy» (hora de fin, errores, tope).
abstract final class TextosTerminarJornadaDeLaCuenta {
  static const terminar = 'Terminar jornada';
  static const terminando = 'Terminando…';

  /// Dice por qué aparece el botón en una cuenta que no puede trabajar: la jornada sigue abierta.
  static String abierta(String hora) =>
      'Tu jornada sigue abierta desde las $hora. Poné la hora a la que terminaste y guardala.';
}

/// «Terminar jornada» en la pantalla de la cuenta que no accede a los módulos de campo (pendiente o
/// suspendida), solo si la persona tiene una jornada abierta (#472, seguimiento de #383): la app se
/// enteró tarde de la restricción, la persona no tenía nada más abierto y fue directo a esa pantalla,
/// que no tiene «Hoy». La jornada es lo abierto que se termina, con la hora de fin que ella pone
/// (no se inventa) y los mismos topes y validaciones que en «Hoy» ([FinDeJornada]); se guarda en el
/// teléfono y sube cuando el servidor lo permita. No se puede empezar nada nuevo desde acá.
///
/// Sin jornada abierta (o sin poder leerla) no ocupa lugar.
class TerminarJornadaDeLaCuenta extends ConsumerStatefulWidget {
  const TerminarJornadaDeLaCuenta({super.key});

  @override
  ConsumerState<TerminarJornadaDeLaCuenta> createState() => _TerminarJornadaDeLaCuentaState();
}

class _TerminarJornadaDeLaCuentaState extends ConsumerState<TerminarJornadaDeLaCuenta>
    with FinDeJornada<TerminarJornadaDeLaCuenta> {
  /// La última sesión vista: si la sesión se cierra a mitad del cierre, la jornada (que es del
  /// teléfono) se termina igual con quien la abrió.
  Sesion? _sesion;

  @override
  Sesion get sesionDelFin => _sesion ?? ref.read(sesionProvider).value!;

  @override
  void initState() {
    super.initState();
    iniciarTic();
  }

  @override
  void dispose() {
    detenerTic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ahora = ref.watch(relojJornadaProvider)();
    ahoraMostrado = ahora;
    final sesion = ref.watch(sesionProvider).value;
    if (sesion == null) return const SizedBox.shrink();
    _sesion = sesion;
    final jornada = ref.watch(jornadaActualProvider(sesion.usuarioId)).value;
    if (jornada == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final maximo = maximoAtrasFinDeJornada(jornada, ahora);
    final elegida = horaElegidaFin(jornada, ahora);
    final escala = MediaQuery.textScalerOf(context).scale(15);
    final base = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: escala > 20
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
          : const StadiumBorder(),
    );

    return Padding(
      key: const Key('cuenta_terminar_jornada'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            TextosTerminarJornadaDeLaCuenta.abierta(horaCorta(jornada.inicio)),
            key: const Key('cuenta_jornada_abierta'),
            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
          ),
          if (errorFin case final error?)
            AvisoJornada(key: const Key('jornada_error_fin'), texto: error, esError: true),
          FilaHoraJornada(
            sufijoKey: '_fin',
            etiqueta: 'HORA DE FIN',
            hora: elegida == null ? 'Ahora' : horaCorta(elegida),
            detalle: elegida == null
                ? horaCorta(ahora)
                : 'hace ${minutosAtrasDe(ahora, elegida)} min',
            onTap: finalizando || maximo == 0 ? null : () => elegirHoraFin(ahora, maximo),
          ),
          FilledButton(
            key: const Key('cuenta_terminar_jornada_boton'),
            onPressed: finalizando ? null : () => finalizarJornada(jornada),
            style: finalizando ? ConEspera.estiloDelBoton(context).merge(base) : base,
            child: finalizando
                ? const ConEspera(TextosTerminarJornadaDeLaCuenta.terminando)
                : const Text(TextosTerminarJornadaDeLaCuenta.terminar, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
