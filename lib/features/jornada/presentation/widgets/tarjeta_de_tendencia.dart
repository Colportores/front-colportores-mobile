import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/jornada.dart';
import '../providers/acompaniamiento_providers.dart';
import '../textos_acompaniamiento.dart';

/// Cómo va la jornada contra la anterior (vista 21, 21J·01, 21J·02, 21J·03 y 21J·04): casas visitadas y
/// ventas con ▲ o ▼ (además del color), contra la última jornada cerrada de la misma campaña. Los cobros no
/// entran. En la primera de la campaña no hay tendencia: solo las cifras y la frase de 21J·04. Mientras no se
/// sabe la campaña de la jornada, o si la lectura falla, no se muestra nada.
class TarjetaDeTendencia extends ConsumerWidget {
  const TarjetaDeTendencia({
    super.key,
    required this.colportorId,
    required this.jornada,
    this.soloConComparacion = false,
  });

  final String colportorId;
  final Jornada jornada;

  /// En el cierre (21J·03) la primera jornada no repite las cifras: solo se muestra con algo contra qué comparar.
  final bool soloConComparacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tendencia = ref
        .watch(
          tendenciaDeLaJornadaProvider((
            colportorId: colportorId,
            jornadaId: jornada.id,
            inicio: jornada.inicio,
            fin: jornada.fin,
          )),
        )
        .value;
    if (tendencia == null || (soloConComparacion && tendencia.esPrimera)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Container(
      key: const Key('jornada_tendencia'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            tendencia.esPrimera
                ? TextosAcompaniamiento.tuJornada
                : TextosAcompaniamiento.contraLaAnterior,
            style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
          ),
          _Fila(
            claveBase: 'casas',
            rotulo: TextosAcompaniamiento.casasVisitadas,
            valor: tendencia.casasVisitadas,
            diferencia: tendencia.diferenciaDeCasas,
          ),
          _Fila(
            claveBase: 'ventas',
            rotulo: TextosAcompaniamiento.ventas,
            valor: tendencia.ventas,
            diferencia: tendencia.diferenciaDeVentas,
          ),
          if (tendencia.esPrimera)
            Text(
              TextosAcompaniamiento.primeraJornada,
              key: const Key('jornada_tendencia_primera'),
              style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
            ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.claveBase,
    required this.rotulo,
    required this.valor,
    required this.diferencia,
  });

  final String claveBase;
  final String rotulo;
  final int valor;
  final int? diferencia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final dif = diferencia;
    // Verde si sube, rojo si baja y gris si es igual: el signo ▲ ▼ va igual, el color no es lo único.
    final color = dif == null || dif == 0
        ? colores.gris
        : dif > 0
        ? const Color(0xFF1F6E3A)
        : const Color(0xFFA8312A);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: dif == null
          ? '$rotulo: $valor'
          : '$rotulo: $valor, ${TextosAcompaniamiento.variacionHablada(dif)}',
      // `Wrap` y no `Row`: con letra grande o cifras largas, el valor baja al renglón de abajo en vez de
      // desbordar.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(rotulo, style: theme.textTheme.bodyLarge),
          Wrap(
            spacing: 10,
            children: [
              Text(
                '$valor',
                key: Key('jornada_tendencia_${claveBase}_valor'),
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (dif != null)
                Text(
                  TextosAcompaniamiento.variacion(dif),
                  key: Key('jornada_tendencia_${claveBase}_variacion'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
