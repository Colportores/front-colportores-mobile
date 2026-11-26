import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../configuracion/presentation/providers/nombre_cuenta_provider.dart';
import '../../domain/entities/jornada.dart';
import '../formato_jornada.dart';
import '../providers/acompaniamiento_providers.dart';
import '../textos_acompaniamiento.dart';
import '../widgets/aviso_jornada.dart';
import '../widgets/tarjeta_de_tendencia.dart';

/// El cierre del día a pantalla completa (vista 21, HU-JOR-002 "se muestra resumen"), después de
/// finalizar la jornada. "Volver al inicio" vuelve a "Hoy", ya sin jornada.
///
/// Casas visitadas y ventas salen de lo que el teléfono tiene guardado (HU-JOR-002, vista 21; #146); los cobros
/// y la copia de seguridad se dibujan con «—» y «Todavía no disponible» hasta que su módulo traiga el dato
/// (decisión de Cristian, 29/09): no se muestran cifras que no son de la colportora. Con una jornada anterior en
/// la misma campaña, 21J·03 suma cómo va contra ella y con quién trabajó.
class ResumenJornadaPage extends ConsumerStatefulWidget {
  const ResumenJornadaPage({super.key, required this.jornada});

  final Jornada jornada;

  @override
  ConsumerState<ResumenJornadaPage> createState() => _ResumenJornadaPageState();
}

class _ResumenJornadaPageState extends ConsumerState<ResumenJornadaPage> {
  /// Un doble toque en "Volver al inicio" no debe sacar también la pantalla de abajo.
  bool _saliendo = false;

  Jornada get jornada => widget.jornada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    final fin = jornada.fin ?? jornada.inicio;
    final duracion = jornada.duracion ?? Duration.zero;
    final nombre = ref.watch(nombreCuentaProvider);

    return Scaffold(
      body: SafeArea(
        // «Volver al inicio» queda fijo al pie: con el acompañamiento y la tendencia el cierre es más alto
        // que una pantalla chica, y el botón no puede quedar bajo el pliegue.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 44, 26, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Row(
                            spacing: 6,
                            children: [
                              Icon(Icons.check, size: 16, color: esquema.primary),
                              Flexible(
                                child: Text(
                                  'JORNADA FINALIZADA',
                                  key: const Key('jornada_resumen'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: esquema.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          nombre == null ? 'Buen trabajo' : 'Buen trabajo, $nombre',
                          key: const Key('jornada_resumen_saludo'),
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'TRABAJASTE',
                          style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                        ),
                        Text(
                          duracionCorta(duracion),
                          key: const Key('jornada_resumen_duracion'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 52,
                            color: esquema.primary,
                            height: 1.05,
                          ),
                        ),
                        Text(
                          'De las ${horaCorta(jornada.inicio)} a las ${horaCorta(fin)}',
                          key: const Key('jornada_resumen_horario'),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: esquema.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _TeAcompanio(jornadaId: jornada.id),
                        TarjetaDeTendencia(
                          colportorId: jornada.colportorId,
                          jornada: jornada,
                          soloConComparacion: true,
                        ),
                        _CifrasDelDia(jornada: jornada),
                        _AvisoSiNoMarcaste(jornadaId: jornada.id),
                        const _CopiaDeSeguridad(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 26),
              child: FilledButton(
                key: const Key('jornada_resumen_volver'),
                onPressed: () {
                  if (_saliendo) return;
                  _saliendo = true;
                  Navigator.of(context).pop();
                },
                child: const Text('Volver al inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Casas visitadas, ventas y cobros del día: las dos primeras salen de lo que el teléfono tiene guardado (las
/// mismas cifras de la tendencia, 21J·03); los cobros siguen en «—» hasta que su módulo traiga el dato.
class _CifrasDelDia extends ConsumerWidget {
  const _CifrasDelDia({required this.jornada});

  final Jornada jornada;

  static const _rotulos = ['Casas visitadas', 'Ventas', 'Cobros'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final tendencia = ref
        .watch(
          tendenciaDeLaJornadaProvider((
            colportorId: jornada.colportorId,
            jornadaId: jornada.id,
            inicio: jornada.inicio,
            fin: jornada.fin,
          )),
        )
        .value;
    final valores = <String>[
      tendencia == null ? '—' : '${tendencia.casasVisitadas}',
      tendencia == null ? '—' : '${tendencia.ventas}',
      '—',
    ];

    return Container(
      key: const Key('jornada_resumen_cifras'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _rotulos.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: colores.borde),
              Expanded(
                child: Semantics(
                  container: true,
                  label: valores[i] == '—'
                      ? '${_rotulos[i]}: sin dato todavía'
                      : '${_rotulos[i]}: ${valores[i]}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          valores[i],
                          key: Key('jornada_resumen_cifra_$i'),
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          _rotulos[i],
                          style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de la copia de seguridad: «Todavía no disponible» hasta que exista el motor de backup.
class _CopiaDeSeguridad extends StatelessWidget {
  const _CopiaDeSeguridad();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Container(
      key: const Key('jornada_resumen_backup'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          ExcludeSemantics(child: Icon(Icons.cloud_off_outlined, color: colores.gris)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  'Copia de seguridad',
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Todavía no disponible',
                  key: const Key('jornada_resumen_backup_estado'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 21J·03: «Te acompañó: Nadie» o los nombres de quienes la acompañaron. Sin lectura no se afirma nada.
class _TeAcompanio extends ConsumerWidget {
  const _TeAcompanio({required this.jornadaId});

  final String jornadaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quienes = ref.watch(acompaniantesDeLaJornadaProvider(jornadaId)).value;
    if (quienes == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Semantics(
      container: true,
      // `Wrap`: con letra grande o varios nombres, la lista baja al renglón de abajo en vez de desbordar.
      child: Wrap(
        key: const Key('jornada_resumen_acompanio'),
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(
            '${TextosAcompaniamiento.teAcompanio}:',
            style: theme.textTheme.bodyLarge?.copyWith(color: colores.gris),
          ),
          Text(
            TextosAcompaniamiento.teAcompanioA(quienes),
            key: const Key('jornada_resumen_acompanio_quienes'),
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 21J·03: si nadie figura como acompañante, el aviso de que el coordinador puede agregarlo desde el panel.
class _AvisoSiNoMarcaste extends ConsumerWidget {
  const _AvisoSiNoMarcaste({required this.jornadaId});

  final String jornadaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quienes = ref.watch(acompaniantesDeLaJornadaProvider(jornadaId)).value;
    if (quienes == null || quienes.isNotEmpty) return const SizedBox.shrink();
    return const AvisoJornada(
      key: Key('jornada_resumen_aviso_acompanio'),
      texto: TextosAcompaniamiento.avisoSiTeOlvidaste,
    );
  }
}
