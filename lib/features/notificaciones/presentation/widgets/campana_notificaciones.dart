import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/centro_notificaciones_page.dart';
import '../providers/historial_notificaciones_providers.dart';
import 'textos_centro_notificaciones.dart';

/// La campana del encabezado de Hoy (vista 00, «Centro de notificaciones · Campana del
/// encabezado»): abre el centro y muestra cuántos avisos siguen sin leer. Sin avisos nuevos, la
/// campana queda sola; más de 99 se escribe «99+».
///
/// Para el lector de pantalla es un solo botón: «Notificaciones, 3 sin leer». El número del globo
/// no se lee aparte.
class CampanaNotificaciones extends ConsumerStatefulWidget {
  const CampanaNotificaciones({super.key});

  @override
  ConsumerState<CampanaNotificaciones> createState() => _CampanaNotificacionesState();
}

class _CampanaNotificacionesState extends ConsumerState<CampanaNotificaciones> {
  /// El centro se está abriendo: un doble toque no apila dos.
  bool _abriendo = false;

  Future<void> _abrir() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await Navigator.of(context).push(CentroNotificacionesPage.ruta());
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si no se puede leer, la campana queda sin número: el motivo se ve en el centro.
    final sinLeer = ref.watch(notificacionesNoLeidasProvider).value ?? 0;
    return IconButton(
      key: const Key('inicio_notificaciones'),
      tooltip: sinLeer == 0
          ? TextosCentroNotificaciones.campana
          : TextosCentroNotificaciones.campanaConNuevas(sinLeer),
      onPressed: _abrir,
      icon: ExcludeSemantics(
        child: Badge(
          isLabelVisible: sinLeer > 0,
          label: Text(
            sinLeer > 99 ? '99+' : '$sinLeer',
            key: const Key('inicio_notificaciones_numero'),
          ),
          child: const Icon(Icons.notifications_none),
        ),
      ),
    );
  }
}
