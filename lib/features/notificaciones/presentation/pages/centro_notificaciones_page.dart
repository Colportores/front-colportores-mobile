import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/destino_notificacion.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/usecases/historial_notificaciones_use_cases.dart';
import '../formato_centro_notificaciones.dart';
import '../providers/historial_notificaciones_providers.dart';
import '../widgets/aviso_notificaciones.dart';
import '../widgets/fila_notificacion.dart';
import '../widgets/hojas_centro_notificaciones.dart';
import '../widgets/textos_centro_notificaciones.dart';

/// Centro de notificaciones (vista 24, grupo C; HU-NOT-005): los avisos de los últimos 90 días, el
/// más reciente primero y agrupados por día, con los que no se leyeron marcados «Nueva». Se entra por
/// la campana del encabezado de Hoy.
///
/// - Tocar un aviso lo marca como leído y lleva al mismo lugar que la notificación original. Si ese
///   lugar ya no existe (24C·07) la lista queda abierta y lo explica.
/// - «⋯» (24C·02): marcar todas como leídas, o borrarlas (24C·03, con confirmación). Solo con avisos.
/// - Sin avisos (24C·04), cargando (24C·05) y error al leer con «Reintentar» (24C·06).
class CentroNotificacionesPage extends ConsumerStatefulWidget {
  const CentroNotificacionesPage({super.key});

  static Route<void> ruta() =>
      MaterialPageRoute<void>(builder: (_) => const CentroNotificacionesPage());

  @override
  ConsumerState<CentroNotificacionesPage> createState() => _CentroNotificacionesPageState();
}

class _CentroNotificacionesPageState extends ConsumerState<CentroNotificacionesPage> {
  /// Un aviso se está abriendo: un segundo toque (o el de otro aviso) no abre dos veces.
  bool _abriendo = false;

  /// El menú o una de sus acciones está en curso.
  bool _conMenu = false;

  @override
  void initState() {
    super.initState();
    // Mantenimiento: lo que pasó de los 90 días se borra al abrir el centro. Lo vencido ya no se lee
    // aunque esto falle.
    unawaited(_purgar());
  }

  Future<void> _purgar() async {
    try {
      await ref.read(purgarHistorialNotificacionesUseCaseProvider)();
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.db,
        'NOTIF_PURGA_FAIL',
        'no se pudo purgar el historial al abrir el centro',
        {'tipo': e.runtimeType.toString()},
      );
    }
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            spacing: 12,
            children: [
              const ExcludeSemantics(child: Icon(Icons.info_outline, color: Color(0xFFB9D3F2))),
              Expanded(child: Text(texto)),
            ],
          ),
        ),
      );
  }

  void _anunciar(String texto) {
    unawaited(
      SemanticsService.sendAnnouncement(View.of(context), texto, Directionality.of(context)),
    );
  }

  /// Tocar un aviso: lo marca como leído, comprueba que su destino exista y lo abre.
  Future<void> _abrir(Notificacion aviso) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      if (!aviso.leida) {
        // Si no se pudo marcar, igual se abre: el aviso sigue «Nueva» y se puede volver a tocar.
        final marcada = await ref.read(marcarNotificacionLeidaUseCaseProvider)(aviso.id);
        marcada.fold(
          (_) => AppLogger.instance.warn(
            LogModulo.db,
            'NOTIF_LEER_FAIL',
            'no se pudo marcar el aviso como leído',
            {'id': aviso.id},
          ),
          (_) {},
        );
      }
      final resuelto = await ref.read(resolverDestinoNotificacionUseCaseProvider)(aviso);
      if (!mounted) return;
      await resuelto.fold<Future<void>>(
        (_) async => _avisar(TextosCentroNotificaciones.errorAlAbrir),
        (r) async {
          switch (r) {
            case SinDestino():
              break;
            case DestinoYaNoExiste(:final destino):
              _avisar(switch (destino) {
                DestinoAgenda() => TextosCentroNotificaciones.agendaYaNoEsta,
              });
            case DestinoDisponible(:final destino):
              await ref.read(abridorDestinoNotificacionProvider)(context, destino);
          }
        },
      );
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.db,
        'NOTIF_ABRIR_FAIL',
        'no se pudo abrir el destino del aviso',
        {'tipo': e.runtimeType.toString()},
      );
      if (mounted) _avisar(TextosCentroNotificaciones.errorAlAbrir);
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _abrirMenu(List<Notificacion> avisos) async {
    if (_conMenu) return;
    _conMenu = true;
    try {
      final accion = await mostrarMenuCentroNotificaciones(
        context,
        haySinLeer: avisos.any((a) => !a.leida),
      );
      if (!mounted || accion == null) return;
      switch (accion) {
        case AccionMenuCentro.marcarTodas:
          await _marcarTodas();
        case AccionMenuCentro.borrarTodas:
          await _confirmarBorrado(avisos.length);
      }
    } finally {
      _conMenu = false;
    }
  }

  Future<void> _marcarTodas() async {
    final resultado = await ref.read(marcarTodasLeidasUseCaseProvider)();
    if (!mounted) return;
    resultado.fold(
      (_) => _avisar(TextosCentroNotificaciones.errorAlMarcar),
      (_) => _anunciar(TextosCentroNotificaciones.anuncioMarcadas),
    );
  }

  Future<void> _confirmarBorrado(int cantidad) async {
    // Lo que llegue mientras la confirmación está abierta no se borra: no estaba en la cuenta.
    final corte = ref.read(relojHistorialNotificacionesProvider)();
    final borrado = await mostrarHojaBorrarTodasLasNotificaciones(
      context,
      cantidad: cantidad,
      borrar: () async {
        final r = await ref.read(borrarTodasLasNotificacionesUseCaseProvider)(hasta: corte);
        return r.isRight();
      },
    );
    if (!mounted || borrado != true) return;
    _anunciar(TextosCentroNotificaciones.anuncioBorradas);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final estado = ref.watch(historialNotificacionesProvider);
    final avisos = switch (estado) {
      AsyncData(:final value) => value,
      _ => null,
    };

    return Scaffold(
      key: const Key('centro_notificaciones_pagina'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('centro_atras'),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ExcludeSemantics(
                        child: Text(
                          TextosCentroNotificaciones.rotulo,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // El menú solo tiene sentido con avisos que marcar o borrar.
                  if (avisos != null && avisos.isNotEmpty)
                    IconButton(
                      key: const Key('centro_menu'),
                      tooltip: TextosCentroNotificaciones.menu,
                      onPressed: () => unawaited(_abrirMenu(avisos)),
                      icon: const Icon(Icons.more_horiz),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 4, 26, 8),
              child: Semantics(
                header: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    TextosCentroNotificaciones.titulo,
                    maxLines: 1,
                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                  ),
                ),
              ),
            ),
            Expanded(
              child: switch (estado) {
                AsyncData(:final value) when value.isEmpty => _Vacio(colores: colores),
                AsyncData(:final value) => _Lista(avisos: value, onAbrir: _abrir),
                AsyncError() => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  children: [
                    AvisoNotificaciones(
                      tono: TonoAviso.error,
                      texto: TextosCentroNotificaciones.errorAlLeer,
                      textoKey: const Key('centro_error'),
                      textoAccion: TextosCentroNotificaciones.reintentar,
                      accionKey: const Key('centro_reintentar'),
                      onAccion: () => ref.invalidate(historialNotificacionesProvider),
                    ),
                  ],
                ),
                _ => const _Cargando(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.avisos, required this.onAbrir});

  final List<Notificacion> avisos;
  final void Function(Notificacion aviso) onAbrir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.watch(relojHistorialNotificacionesProvider)();
    // Rótulo de día + avisos, en una sola lista para que se construya perezosa.
    final filas = <Object>[];
    String? ultimoDia;
    for (final aviso in avisos) {
      final dia = rotuloDelDia(aviso.recibidaEn, ahora: ahora);
      if (dia != ultimoDia) {
        filas.add(dia);
        ultimoDia = dia;
      }
      filas.add(aviso);
    }
    return ListView.separated(
      key: const Key('centro_lista'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: filas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => switch (filas[i]) {
        final String dia => RotuloDiaNotificaciones(texto: dia),
        final Notificacion aviso => FilaNotificacion(
          key: Key('centro_aviso_${aviso.id}'),
          notificacion: aviso,
          onAbrir: () => onAbrir(aviso),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.colores});

  final ColoresColportaje colores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, restricciones) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 40, 30, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: restricciones.maxHeight - 60),
          child: Semantics(
            key: const Key('centro_vacio'),
            container: true,
            liveRegion: true,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE6EEF8),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  TextosCentroNotificaciones.vacioTitulo,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  TextosCentroNotificaciones.vacioTexto,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('centro_cargando'),
      container: true,
      label: TextosCentroNotificaciones.cargando,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          children: [
            for (final alto in const [20.0, 70.0, 70.0, 70.0])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: alto,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEBE4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
