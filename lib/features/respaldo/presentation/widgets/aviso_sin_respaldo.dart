import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/services/servicio_respaldo.dart';
import '../providers/respaldo_automatico_providers.dart';
import '../providers/respaldo_drive_providers.dart';
import '../textos_respaldo_drive.dart';
import 'aviso_drive.dart';

/// El aviso de Inicio cuando la persona lleva más de 7 días sin un respaldo exitoso (HU-SYNC-005):
/// «Llevás N días sin backup. Revisá tu conexión y reintentá.», con «Reintentar».
///
/// Sale solo con Drive conectado y un respaldo anterior desde el cual contar. «Reintentar» pide el
/// respaldo ya mismo, sin esperar a Wi-Fi ni batería: lo pidió la persona. Mientras corre, el botón
/// queda apagado (un segundo toque no pide otro). Si sale bien, el aviso se va solo: llega el
/// respaldo nuevo y ya no pasan 7 días. Si no, sigue ahí y la persona puede volver a tocarlo.
///
/// Sin nada que mostrar no ocupa lugar. Con muchos renglones (texto al 200 %) ocupa a lo sumo el 40 %
/// del alto y se desplaza: el contenido de Inicio nunca queda tapado del todo.
class AvisoSinRespaldo extends ConsumerStatefulWidget {
  const AvisoSinRespaldo({super.key, this.ahora});

  /// La hora de «ahora», para los tests.
  final DateTime Function()? ahora;

  @override
  ConsumerState<AvisoSinRespaldo> createState() => _AvisoSinRespaldoState();
}

class _AvisoSinRespaldoState extends ConsumerState<AvisoSinRespaldo> {
  /// Hay un reintento corriendo. Es un campo y no solo el estado: la guarda tiene que cortar el
  /// segundo toque aunque llegue antes de que se vuelva a dibujar.
  bool _reintentando = false;

  /// Lo que dejó el último «Reintentar» si no salió (sin conexión, o falló). Se borra al volver a
  /// tocar; si salió bien, el aviso se va solo y no queda nada que mostrar.
  String? _detalle;

  /// El aviso entero, para llevarlo a la vista cuando aparece el motivo del reintento.
  final _avisoKey = GlobalKey();

  Future<void> _reintentar() async {
    if (_reintentando) return;
    setState(() {
      _reintentando = true;
      _detalle = null;
    });
    String? detalle;
    try {
      final resultado = await ref
          .read(servicioRespaldoProvider)
          .respaldar(OrigenRespaldo.pedidoPorLaPersona);
      detalle = switch (resultado) {
        RespaldoOmitido(motivo: MotivoOmision.sinConexion) =>
          TextosRespaldoDrive.reintentoSinConexion,
        RespaldoFallido() => TextosRespaldoDrive.reintentoFallido,
        _ => null,
      };
    } on Object {
      // El servicio no lanza; si algún día lo hiciera, el botón no puede quedar apagado para
      // siempre ni el error salir sin atender de un `unawaited`.
      detalle = TextosRespaldoDrive.reintentoFallido;
    } finally {
      // Con la pantalla cerrada no hay nada que volver a dibujar.
      if (mounted) {
        setState(() {
          _reintentando = false;
          _detalle = detalle;
        });
        if (detalle != null) _mostrarElMotivo();
      }
    }
  }

  /// Con el texto grande el aviso se desplaza (tope de 40 % propio, y el de la franja de Inicio): el
  /// motivo y «Reintentar» están al pie y quedarían fuera de la vista, y la persona vería el mismo
  /// aviso de antes sin enterarse del error (QA #185, ronda 2). Se lleva el pie del aviso a la vista,
  /// en cada desplazable que lo contiene, sin animación.
  void _mostrarElMotivo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _avisoKey.currentContext;
      if (!mounted || contexto == null || !contexto.mounted) return;
      unawaited(Scrollable.ensureVisible(contexto, alignment: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final conectada = ref.watch(
      estadoRespaldoDriveProvider.select((estado) => estado.value is DriveConectada),
    );
    final ultimo = ref.watch(ultimoRespaldoDriveProvider).value;
    final dias = conectada
        ? diasSinRespaldo(ultimo: ultimo, ahora: (widget.ahora ?? DateTime.now)())
        : null;
    if (dias == null) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SizedBox(
          key: _avisoKey,
          child: AvisoDrive(
            key: const Key('aviso_sin_respaldo'),
            clase: ClaseAvisoDrive.error,
            texto: TextosRespaldoDrive.avisoSinRespaldo(dias),
            detalle: _detalle,
            accion: _reintentando
                ? TextosRespaldoDrive.reintentando
                : TextosRespaldoDrive.reintentar,
            alAccionar: _reintentando ? null : () => unawaited(_reintentar()),
          ),
        ),
      ),
    );
  }
}
