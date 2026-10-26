import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_notificaciones.dart';
import '../providers/notificaciones_providers.dart';
import '../widgets/aviso_notificaciones.dart';

/// 24A·01: el pedido del permiso de notificaciones en el primer ingreso (HU-NOT-001, vista 24).
///
/// Va después de preparar el espacio seguro (vista 13) y antes de la pantalla principal. Explica para
/// qué sirven las notificaciones y ofrece «Activar notificaciones» (muestra el diálogo del sistema,
/// 24A·02) o «Ahora no». Con cualquiera de las dos respuestas la pantalla se va sola (la raíz deja de
/// pedir en cuanto se contesta) y no se vuelve a mostrar; si dijo que no, Hoy lo recuerda con un aviso
/// sutil (24A·03). Si activa, el toast de 24A·04 (o 24A·05 sin conexión) queda a la vista en la
/// pantalla que sigue.
class PedidoPermisoNotificacionesPage extends ConsumerStatefulWidget {
  const PedidoPermisoNotificacionesPage({super.key});

  @override
  ConsumerState<PedidoPermisoNotificacionesPage> createState() =>
      _PedidoPermisoNotificacionesPageState();
}

class _PedidoPermisoNotificacionesPageState extends ConsumerState<PedidoPermisoNotificacionesPage> {
  /// Mientras el diálogo del sistema está abierto (o se guarda la respuesta): los dos botones
  /// quedan apagados, un segundo toque no pide dos veces.
  bool _pidiendo = false;

  /// El pedido falló (la plataforma no mostró el diálogo): se dice y se puede reintentar.
  bool _fallo = false;

  /// Los botones (y el aviso de falla encima): al fallar se los trae a la vista.
  final _zonaDeBotones = GlobalKey();

  Future<void> _activar() async {
    if (_pidiendo) return;
    setState(() {
      _pidiendo = true;
      _fallo = false;
    });
    // El mensajero es el de la app: sobrevive a esta pantalla, que se va en cuanto se contesta.
    final mensajero = ScaffoldMessenger.of(context);
    final notificaciones = ref.read(notificacionesProvider.notifier);
    // Sin lectura de la conexión no se afirma nada: el aviso es el de siempre.
    final sinConexion = ref.read(conexionProvider).value == TipoConexion.sinConexion;
    final resultado = await notificaciones.activar();
    if (resultado == ResultadoActivacion.activadas) {
      avisarNotificacionesActivadas(mensajero, sinConexion: sinConexion);
    }
    if (!mounted) return;
    setState(() {
      _pidiendo = false;
      _fallo = resultado == ResultadoActivacion.fallo;
    });
    if (_fallo) {
      // El aviso empuja los botones hacia abajo: en un teléfono chico quedarían fuera de la vista.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final contexto = _zonaDeBotones.currentContext;
        if (contexto != null && contexto.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              contexto,
              duration: const Duration(milliseconds: 150),
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            ),
          );
        }
      });
    }
  }

  Future<void> _ahoraNo() async {
    if (_pidiendo) return;
    setState(() => _pidiendo = true);
    await ref.read(notificacionesProvider.notifier).ahoraNo();
    if (!mounted) return;
    setState(() => _pidiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene vivo el estado mientras la pantalla está abierta: «Activar» necesita haberlo leído.
    ref.watch(notificacionesProvider.select((estado) => estado.hasValue));
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final esquema = theme.colorScheme;
    // A texto grande los botones dejan la píldora (la etiqueta se parte en dos renglones).
    final grande = MediaQuery.textScalerOf(context).scale(14) > 20;
    final forma = grande
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        : const StadiumBorder();

    return Scaffold(
      key: const Key('permiso_notificaciones_pagina'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      const SizedBox(height: 24),
                      Align(
                        child: ExcludeSemantics(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: esquema.primary.withValues(alpha: .1),
                            ),
                            child: Icon(
                              Icons.notifications_none_outlined,
                              size: 34,
                              color: esquema.primary,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Semantics(
                          header: true,
                          child: Text(
                            TextosNotificaciones.pedidoTitulo,
                            key: const Key('permiso_notificaciones_titulo'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24),
                          ),
                        ),
                      ),
                      const _Motivo(
                        icono: Icons.event_note_outlined,
                        titulo: TextosNotificaciones.motivoRecordatorios,
                        detalle: TextosNotificaciones.motivoRecordatoriosDetalle,
                      ),
                      const _Motivo(
                        icono: Icons.fact_check_outlined,
                        titulo: TextosNotificaciones.motivoPedidos,
                      ),
                      const _Motivo(
                        icono: Icons.place_outlined,
                        titulo: TextosNotificaciones.motivoZona,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      key: _zonaDeBotones,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        if (_fallo)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              TextosNotificaciones.pedidoFallo,
                              key: const Key('permiso_notificaciones_fallo'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(color: esquema.error),
                            ),
                          ),
                        FilledButton(
                          key: const Key('permiso_notificaciones_activar'),
                          onPressed: _pidiendo ? null : () => unawaited(_activar()),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: forma,
                            padding: EdgeInsets.symmetric(
                              horizontal: grande ? 40 : 24,
                              vertical: 17,
                            ),
                          ),
                          child: _pidiendo
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    key: Key('permiso_notificaciones_pidiendo'),
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                    semanticsLabel: 'Esperando tu respuesta',
                                  ),
                                )
                              : const Text(
                                  TextosNotificaciones.activar,
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        OutlinedButton(
                          key: const Key('permiso_notificaciones_ahora_no'),
                          onPressed: _pidiendo ? null : () => unawaited(_ahoraNo()),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: forma,
                            side: BorderSide(color: colores.bordeInput),
                            padding: EdgeInsets.symmetric(horizontal: grande ? 40 : 24),
                          ),
                          child: const Text(TextosNotificaciones.ahoraNo),
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
    );
  }
}

/// Un motivo para activar las notificaciones: ícono, título y, si lo hay, una línea de detalle.
class _Motivo extends StatelessWidget {
  const _Motivo({required this.icono, required this.titulo, this.detalle});

  final IconData icono;
  final String titulo;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final esquema = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest,
        border: Border.all(color: colores.borde),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          spacing: 14,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: esquema.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, size: 20, color: esquema.primary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(titulo, style: theme.textTheme.titleSmall),
                  if (detalle != null)
                    Text(detalle!, style: theme.textTheme.bodySmall?.copyWith(color: colores.gris)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
