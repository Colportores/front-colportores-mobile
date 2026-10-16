import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart';
import '../../domain/entities/asignacion_campania.dart';
import '../providers/asignacion_campania_providers.dart';

/// Textos de «Ya te asignaron» (vista 18, 18-A07). Son propuesta del diseño.
abstract final class TextosCuentaAsignada {
  static const titulo = 'Ya te asignaron';
  static const abriendo = 'Abriendo tu pantalla principal…';

  static String zona(AsignacionCampania a) => 'Zona ${a.zona} · ${a.ciudad}';
}

/// 18-A07: la cuenta pasó a activa con la app abierta. Dice a qué campaña y zona se asignó al
/// colportor y, al terminar la barra de progreso, llama a [onTerminar] (la raíz muestra entonces
/// la pantalla principal). Si no se conoce la asignación (no hay fuente todavía, o falló la
/// consulta) los renglones de campaña y zona no se muestran: nunca se inventan.
class CuentaAsignadaPage extends ConsumerStatefulWidget {
  const CuentaAsignadaPage({super.key, required this.onTerminar});

  /// Cuánto se ve la pantalla antes de pasar a la principal.
  static const duracion = Duration(milliseconds: 2400);

  final VoidCallback onTerminar;

  @override
  ConsumerState<CuentaAsignadaPage> createState() => _CuentaAsignadaPageState();
}

class _CuentaAsignadaPageState extends ConsumerState<CuentaAsignadaPage> {
  AsignacionCampania? _asignacion;
  bool _termino = false;

  @override
  void initState() {
    super.initState();
    unawaited(_cargarAsignacion());
  }

  Future<void> _cargarAsignacion() async {
    try {
      final asignacion = await ref.read(asignacionCampaniaDataSourceProvider).consultar();
      if (mounted) setState(() => _asignacion = asignacion);
    } on Object {
      // Sin la asignación la pantalla sale igual, solo con «Ya te asignaron».
    }
  }

  void _terminar() {
    if (_termino) return; // Una sola vez, aunque la animación avise de más.
    _termino = true;
    widget.onTerminar();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    const verde = Color(0xFF1F6E3A);
    final asignacion = _asignacion;

    return Scaffold(
      key: const Key('cuenta_asignada'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: verde),
                        child: const Icon(Icons.check, color: Colors.white, size: 28),
                      ),
                    ),
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        TextosCuentaAsignada.titulo,
                        key: const Key('asignada_titulo'),
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    if (asignacion != null)
                      Column(
                        key: const Key('asignada_detalle'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(asignacion.campania, style: theme.textTheme.bodyLarge),
                          Text(
                            TextosCuentaAsignada.zona(asignacion),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          ExcludeSemantics(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: CuentaAsignadaPage.duracion,
                              onEnd: _terminar,
                              builder: (context, valor, _) => ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  key: const Key('asignada_progreso'),
                                  value: valor,
                                  minHeight: 4,
                                  backgroundColor: colores.borde,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            TextosCuentaAsignada.abriendo,
                            style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Los módulos ya están disponibles, pero esta pantalla es de paso: la barra se ve y no se toca.
      bottomNavigationBar: ExcludeSemantics(
        child: IgnorePointer(
          child: BarraPestanasInicio(seleccionada: PestanaInicio.hoy, onSeleccionar: (_) {}),
        ),
      ),
    );
  }
}
