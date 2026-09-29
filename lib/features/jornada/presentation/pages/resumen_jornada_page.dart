import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/jornada.dart';
import '../formato_jornada.dart';

/// El cierre del día a pantalla completa (vista 21, HU-JOR-002 "se muestra resumen"), después de
/// finalizar la jornada. "Volver al inicio" vuelve a "Hoy", ya sin jornada.
///
/// Por ahora solo las horas trabajadas: casas visitadas, ventas y cobros llegan con sus módulos
/// (#74), y el estado de la copia de seguridad con el motor de backup (HU-SYNC-005). El diseño
/// dibuja esas dos secciones con cifras de ejemplo ("PRÓXIMAMENTE"); no se muestran cifras que no
/// son del colportor.
class ResumenJornadaPage extends StatefulWidget {
  const ResumenJornadaPage({super.key, required this.jornada});

  final Jornada jornada;

  @override
  State<ResumenJornadaPage> createState() => _ResumenJornadaPageState();
}

class _ResumenJornadaPageState extends State<ResumenJornadaPage> {
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
                      Text('Buen trabajo', style: theme.textTheme.headlineMedium),
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
