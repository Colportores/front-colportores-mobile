import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/notificaciones_page.dart';
import '../providers/notificaciones_providers.dart';
import 'aviso_notificaciones.dart';

/// 24A·03: el aviso sutil de Hoy cuando la persona dijo que no al pedido y las notificaciones siguen
/// apagadas (HU-NOT-001). «Ir a configuración» lleva a Configuración › Notificaciones; la ✕ lo cierra
/// y no vuelve a salir en esta instalación. Se va solo si las activa (en los ajustes del teléfono o
/// desde Configuración).
///
/// Sin nada que mostrar no ocupa lugar. Con muchos renglones (texto al 200 %) ocupa a lo sumo el 40 %
/// del alto y se desplaza: el contenido de Hoy nunca queda tapado del todo.
class AvisoNotificacionesApagadas extends ConsumerStatefulWidget {
  const AvisoNotificacionesApagadas({super.key});

  @override
  ConsumerState<AvisoNotificacionesApagadas> createState() => _AvisoNotificacionesApagadasState();
}

class _AvisoNotificacionesApagadasState extends ConsumerState<AvisoNotificacionesApagadas> {
  /// Mientras Configuración › Notificaciones está abierta: un segundo toque no apila otra igual.
  bool _abierta = false;

  Future<void> _irAConfiguracion() async {
    if (_abierta) return;
    _abierta = true;
    try {
      await Navigator.of(context).push(NotificacionesPage.ruta());
    } finally {
      _abierta = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mostrar = ref.watch(
      notificacionesProvider.select((estado) => estado.value?.mostrarAviso ?? false),
    );
    if (!mostrar) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: AvisoNotificaciones(
          tono: TonoAviso.info,
          texto: TextosNotificaciones.avisoApagadas,
          textoKey: const Key('aviso_notificaciones_texto'),
          textoAccion: TextosNotificaciones.avisoIrAConfiguracion,
          accionKey: const Key('aviso_notificaciones_ir'),
          onAccion: () => unawaited(_irAConfiguracion()),
          cerrarKey: const Key('aviso_notificaciones_cerrar'),
          onCerrar: () => unawaited(ref.read(notificacionesProvider.notifier).cerrarAviso()),
        ),
      ),
    );
  }
}
