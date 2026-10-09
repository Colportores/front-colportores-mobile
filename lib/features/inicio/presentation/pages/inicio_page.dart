import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/entities/sesion.dart';
import '../../../auth/presentation/providers/avisos_zona_notifier.dart';
import '../../../auth/presentation/widgets/aviso_zona_banner.dart';
import '../../../configuracion/presentation/pages/configuracion_page.dart';
import '../../../jornada/presentation/pages/jornada_page.dart';
import '../../../mapa/presentation/pages/lista_ubicaciones_page.dart';
import '../../../mapa/presentation/pages/mapa_ubicaciones_page.dart';
import '../../../mapa/presentation/providers/mapa_ubicaciones_notifier.dart';
import '../widgets/barra_pestanas_inicio.dart';

export '../widgets/barra_pestanas_inicio.dart' show PestanaInicio;

/// Estructura de la app una vez con sesión: la marca y el engranaje de Configuración arriba, la
/// barra inferior Hoy · Mapa · Lista · Agenda · Ventas abajo, y en el medio la pestaña elegida.
///
/// "Hoy" es la jornada (HU-JOR-001/002), "Mapa" y "Lista" las ubicaciones del colportor sobre el mapa
/// y en una lista (HU-UBI-003 y HU-UBI-002). Agenda y Ventas todavía no tienen pantalla: quedan con
/// [PestanaProvisoria] («Esta sección llega pronto.») hasta que llegue la HU de cada una. El atrás
/// del sistema desde las pestañas vuelve a "Hoy", y desde
/// "Hoy" cierra la app (decisión de Cristian, 29/09). Las pestañas se mantienen vivas al cambiar (`IndexedStack`): no se pierde lo que el
/// colportor estaba haciendo en "Hoy", como la hora de inicio elegida.
class InicioPage extends ConsumerStatefulWidget {
  const InicioPage({super.key, required this.sesion});

  final Sesion sesion;

  @override
  ConsumerState<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends ConsumerState<InicioPage> {
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
    // Con la vista previa del mapa abierta el atrás es de ella (la cierra, como su ✕): la pantalla
    // principal no vuelve a «Hoy». Flutter avisa a todos los `PopScope` de la ruta, así que no
    // alcanza con que el del mapa también atienda: esta pantalla tiene que saber, al construirse y
    // no al atender el atrás (el del mapa ya pudo haber cerrado la vista previa), que no le toca.
    final mapaConVistaPrevia =
        _actual == PestanaInicio.mapa &&
        ref.watch(
          mapaUbicacionesProvider(
            widget.sesion.usuarioId,
          ).select((estado) => estado.seleccionada != null),
        );
    return PopScope(
      canPop: _actual == PestanaInicio.hoy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !mapaConVistaPrevia) _ir(PestanaInicio.hoy);
      },
      child: _LectorTeclado(child: _scaffold(context)),
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
      body: Column(
        children: [
          // El aviso de zona (HU-CAM-006, #251) va arriba de la pestaña, en cualquiera de ellas.
          _AvisosDeZona(colportorId: widget.sesion.usuarioId),
          Expanded(
            child: IndexedStack(
              index: _actual.index,
              children: [
                JornadaPage(sesion: widget.sesion, onAbrirMapa: () => _ir(PestanaInicio.mapa)),
                for (final pestana in PestanaInicio.values.skip(1))
                  switch (pestana) {
                    // El mapa de ubicaciones (HU-UBI-003, #199) y la lista (HU-UBI-002, #196). El GPS se
                    // pide al abrir la pestaña, no antes.
                    PestanaInicio.mapa => MapaUbicacionesPage(
                      key: Key('pestana_${pestana.name}'),
                      colportorId: widget.sesion.usuarioId,
                      activa: _actual == PestanaInicio.mapa,
                    ),
                    PestanaInicio.lista => ListaUbicacionesPage(
                      key: Key('pestana_${pestana.name}'),
                      colportorId: widget.sesion.usuarioId,
                      activa: _actual == PestanaInicio.lista,
                    ),
                    _ => PestanaProvisoria(key: Key('pestana_${pestana.name}'), pestana: pestana),
                  },
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BarraPestanasInicio(seleccionada: _actual, onSeleccionar: _ir),
    );
  }
}

/// Los avisos de zona pendientes (HU-CAM-006, #251). Es un widget aparte para que un aviso nuevo, o
/// uno cerrado, reconstruya solo esta franja y no la pestaña de abajo.
class _AvisosDeZona extends ConsumerWidget {
  const _AvisosDeZona({required this.colportorId});

  final String colportorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = avisosZonaProvider(colportorId);
    // Se mira siempre, aunque la franja se oculte: así el estado de los avisos (y lo cerrado en la
    // sesión) no se pierde mientras el teclado está abierto.
    final avisos = ref.watch(provider);
    // Con el teclado abierto gana el campo que se escribe (precedente: #322): la franja se oculta y
    // vuelve sola al cerrarlo. El aviso sigue pendiente; solo «Entendido» lo anota como avisado.
    if (_EstadoTeclado.abiertoEn(context)) return const SizedBox.shrink();
    return AvisosZonaPendientes(
      avisos: avisos,
      onCerrar: (aviso) => unawaited(ref.read(provider.notifier).cerrar(aviso)),
    );
  }
}

/// Le dice a la franja de avisos si el teclado está abierto. Se lee arriba del `Scaffold` porque el
/// `MediaQuery` de su cuerpo ya viene sin el alto del teclado (el `Scaffold` lo descuenta al
/// redimensionarse). [child] llega armado de afuera: mientras el teclado se anima no se reconstruye
/// nada más que lo que depende de «abierto o cerrado».
class _LectorTeclado extends StatelessWidget {
  const _LectorTeclado({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _EstadoTeclado(abierto: MediaQuery.viewInsetsOf(context).bottom > 0, child: child);
}

class _EstadoTeclado extends InheritedWidget {
  const _EstadoTeclado({required this.abierto, required super.child});

  final bool abierto;

  static bool abiertoEn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EstadoTeclado>()?.abierto ?? false;

  @override
  bool updateShouldNotify(_EstadoTeclado oldWidget) => abierto != oldWidget.abierto;
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
