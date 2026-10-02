import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../configuracion/presentation/providers/nombre_cuenta_provider.dart';
import '../../domain/entities/jornada.dart';
import '../formato_jornada.dart';

/// El cierre del día a pantalla completa (vista 21, HU-JOR-002 "se muestra resumen"), después de
/// finalizar la jornada. "Volver al inicio" vuelve a "Hoy", ya sin jornada.
///
/// Casas visitadas, ventas y cobros se dibujan con «—» y la copia de seguridad con «Todavía no
/// disponible» hasta que cada módulo traiga su dato (#151, #158, #163, #185; decisión de Cristian,
/// 29/09): no se muestran cifras que no son del colportor.
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
        child: LayoutBuilder(
          builder: (context, restricciones) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 44, 26, 26),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (restricciones.maxHeight - 70).clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                style: theme.textTheme.labelSmall?.copyWith(color: esquema.primary),
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
                        style: theme.textTheme.bodyLarge?.copyWith(color: esquema.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      const _CifrasDelDia(),
                      const _CopiaDeSeguridad(),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('jornada_resumen_volver'),
                    onPressed: () {
                      if (_saliendo) return;
                      _saliendo = true;
                      Navigator.of(context).pop();
                    },
                    child: const Text('Volver al inicio'),
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

/// Casas visitadas, ventas y cobros del día: «—» hasta que cada módulo traiga su dato.
class _CifrasDelDia extends StatelessWidget {
  const _CifrasDelDia();

  static const _rotulos = ['Casas visitadas', 'Ventas', 'Cobros'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

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
                  label: '${_rotulos[i]}: sin dato todavía',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          '—',
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
