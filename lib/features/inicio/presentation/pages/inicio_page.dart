import 'dart:async';

import 'package:flutter/material.dart';

import '../../../auth/domain/entities/sesion.dart';
import '../../../configuracion/presentation/pages/configuracion_page.dart';
import '../../../jornada/presentation/pages/jornada_page.dart';
import '../widgets/barra_pestanas_inicio.dart';

export '../widgets/barra_pestanas_inicio.dart' show PestanaInicio;

/// Estructura de la app una vez con sesión: la marca y el engranaje de Configuración arriba, la
/// barra inferior Hoy · Mapa · Lista · Agenda · Ventas abajo, y en el medio la pestaña elegida.
///
/// "Hoy" es la jornada (HU-JOR-001/002). Mapa, Lista, Agenda y Ventas todavía no tienen pantalla:
/// quedan con [PestanaProvisoria] («Esta sección llega pronto.») hasta que llegue la HU de cada
/// una (Mapa #199, Lista #196). El atrás del sistema desde esas pestañas vuelve a "Hoy", y desde
/// "Hoy" cierra la app (decisión de Cristian, 29/09). Las pestañas se mantienen vivas al cambiar (`IndexedStack`): no se pierde lo que el
/// colportor estaba haciendo en "Hoy", como la hora de inicio elegida.
class InicioPage extends StatefulWidget {
  const InicioPage({super.key, required this.sesion});

  final Sesion sesion;

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  PestanaInicio _actual = PestanaInicio.hoy;

  void _ir(PestanaInicio pestana) => setState(() => _actual = pestana);

  /// Configuración devuelve la pestaña elegida en su barra inferior (vista 16), o `null` si se
  /// salió con "volver".
  Future<void> _abrirConfiguracion() async {
    final pestana = await Navigator.of(context).push(ConfiguracionPage.ruta());
    if (pestana != null && mounted) _ir(pestana);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _actual == PestanaInicio.hoy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _ir(PestanaInicio.hoy);
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;

    return Scaffold(
      key: const Key('inicio_principal'),
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: esquema.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 26,
        title: const _Marca(),
        actions: [
          // Cerrar sesión (con confirmación) y borrar datos viven en Configuración (HU-AUTH-006/010).
          IconButton(
            key: const Key('inicio_configuracion'),
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => unawaited(_abrirConfiguracion()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _actual.index,
        children: [
          JornadaPage(sesion: widget.sesion, onAbrirMapa: () => _ir(PestanaInicio.mapa)),
          for (final pestana in PestanaInicio.values.skip(1))
            PestanaProvisoria(key: Key('pestana_${pestana.name}'), pestana: pestana),
        ],
      ),
      bottomNavigationBar: BarraPestanasInicio(seleccionada: _actual, onSeleccionar: _ir),
    );
  }
}

/// Pantalla de una pestaña cuya HU todavía no está: el ícono de la sección y «Esta sección llega
/// pronto.», sin contenido inventado. Se reemplaza en el issue de cada HU.
class PestanaProvisoria extends StatelessWidget {
  const PestanaProvisoria({super.key, required this.pestana});

  final PestanaInicio pestana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: pestana.etiqueta,
      container: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              ExcludeSemantics(
                child: Icon(pestana.icono, size: 48, color: theme.colorScheme.primary),
              ),
              Text(
                'Esta sección llega pronto.',
                key: const Key('pestana_pronto'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marca de la app en la barra: la palabra "COLPORTAJE" en mono, como en el diseño.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Text(
        'COLPORTAJE',
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          letterSpacing: 2.4,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
