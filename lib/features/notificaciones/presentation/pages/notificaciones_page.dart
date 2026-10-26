import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_notificaciones.dart';
import '../providers/notificaciones_providers.dart';
import '../widgets/aviso_notificaciones.dart';

/// Configuración › Notificaciones (vista 24): hoy, el estado del permiso del teléfono. Las opciones de
/// los recordatorios (anticipación) llegan con HU-NOT-004 y el centro de avisos con HU-NOT-005, en
/// esta misma pantalla.
///
/// - Activadas: lo dice.
/// - Sin pedir (dijo «Ahora no», o el teléfono no deja preguntar de nuevo sin saberlo): «Activar»
///   muestra el diálogo del sistema (24A·02).
/// - Bloqueadas (24A·06): desde la app ya no se pueden activar; «Abrir ajustes del teléfono» lleva a
///   donde sí se puede. Al volver a la app, el estado se vuelve a leer solo.
class NotificacionesPage extends ConsumerStatefulWidget {
  const NotificacionesPage({super.key});

  static Route<void> ruta() => MaterialPageRoute<void>(builder: (_) => const NotificacionesPage());

  @override
  ConsumerState<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends ConsumerState<NotificacionesPage> {
  /// Mientras el diálogo del sistema está abierto: «Activar» no pide dos veces.
  bool _activando = false;

  /// El último «Activar» falló (la plataforma no mostró el diálogo).
  bool _falloAlActivar = false;

  /// Mientras se abren los ajustes del teléfono, y si no se pudieron abrir.
  bool _abriendoAjustes = false;
  bool _ajustesNoAbren = false;

  Future<void> _activar() async {
    if (_activando) return;
    setState(() {
      _activando = true;
      _falloAlActivar = false;
    });
    final mensajero = ScaffoldMessenger.of(context);
    final sinConexion = ref.read(conexionProvider).value == TipoConexion.sinConexion;
    final resultado = await ref.read(notificacionesProvider.notifier).activar();
    if (resultado == ResultadoActivacion.activadas) {
      avisarNotificacionesActivadas(mensajero, sinConexion: sinConexion);
    }
    if (!mounted) return;
    setState(() {
      _activando = false;
      _falloAlActivar = resultado == ResultadoActivacion.fallo;
    });
  }

  Future<void> _abrirAjustes() async {
    if (_abriendoAjustes) return;
    setState(() {
      _abriendoAjustes = true;
      _ajustesNoAbren = false;
    });
    final abiertos = await ref.read(notificacionesProvider.notifier).abrirAjustes();
    if (!mounted) return;
    setState(() {
      _abriendoAjustes = false;
      _ajustesNoAbren = !abiertos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final estado = ref.watch(notificacionesProvider);

    return Scaffold(
      key: const Key('notificaciones_pagina'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('notificaciones_atras'),
                  tooltip: 'Volver',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'CONFIGURACIÓN',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Notificaciones',
                          maxLines: 1,
                          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: switch (estado) {
                  AsyncData(:final value) => _Contenido(
                    permiso: value.permiso,
                    activando: _activando,
                    falloAlActivar: _falloAlActivar,
                    abriendoAjustes: _abriendoAjustes,
                    ajustesNoAbren: _ajustesNoAbren,
                    onActivar: () => unawaited(_activar()),
                    onAbrirAjustes: () => unawaited(_abrirAjustes()),
                  ),
                  AsyncError() => AvisoNotificaciones(
                    tono: TonoAviso.error,
                    texto: TextosNotificaciones.errorAlLeer,
                    textoKey: const Key('notificaciones_error'),
                    textoAccion: TextosNotificaciones.reintentar,
                    accionKey: const Key('notificaciones_reintentar'),
                    onAccion: () => ref.invalidate(notificacionesProvider),
                  ),
                  _ => Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        key: const Key('notificaciones_cargando'),
                        color: colores.gris,
                        semanticsLabel: 'Cargando',
                      ),
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.permiso,
    required this.activando,
    required this.falloAlActivar,
    required this.abriendoAjustes,
    required this.ajustesNoAbren,
    required this.onActivar,
    required this.onAbrirAjustes,
  });

  final EstadoPermisoNotificaciones permiso;
  final bool activando;
  final bool falloAlActivar;
  final bool abriendoAjustes;
  final bool ajustesNoAbren;
  final VoidCallback onActivar;
  final VoidCallback onAbrirAjustes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        switch (permiso) {
          EstadoPermisoNotificaciones.activadas => Row(
            spacing: 10,
            children: [
              ExcludeSemantics(
                child: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
              ),
              Expanded(
                child: Text(
                  TextosNotificaciones.activadasEstado,
                  key: const Key('notificaciones_activadas'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          EstadoPermisoNotificaciones.sinPedir => AvisoNotificaciones(
            tono: TonoAviso.info,
            texto: TextosNotificaciones.apagadas,
            textoKey: const Key('notificaciones_apagadas'),
            textoAccion: TextosNotificaciones.activarCorto,
            accionKey: const Key('notificaciones_activar'),
            onAccion: activando ? null : onActivar,
          ),
          EstadoPermisoNotificaciones.bloqueadas => AvisoNotificaciones(
            tono: TonoAviso.advertencia,
            texto: TextosNotificaciones.bloqueadas,
            textoKey: const Key('notificaciones_bloqueadas'),
            textoAccion: TextosNotificaciones.abrirAjustes,
            accionKey: const Key('notificaciones_abrir_ajustes'),
            onAccion: abriendoAjustes ? null : onAbrirAjustes,
          ),
        },
        if (falloAlActivar)
          Semantics(
            liveRegion: true,
            child: Text(
              TextosNotificaciones.activarFallo,
              key: const Key('notificaciones_fallo'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (ajustesNoAbren)
          Semantics(
            liveRegion: true,
            child: Text(
              TextosNotificaciones.ajustesNoAbren,
              key: const Key('notificaciones_ajustes_no_abren'),
              style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
            ),
          ),
      ],
    );
  }
}
