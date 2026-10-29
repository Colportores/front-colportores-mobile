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

  Future<void> _reintentar() async {
    if (_reintentando) return;
    setState(() => _reintentando = true);
    try {
      await ref.read(servicioRespaldoProvider).respaldar(OrigenRespaldo.pedidoPorLaPersona);
    } on Object {
      // El servicio no lanza; si algún día lo hiciera, el botón no puede quedar apagado para
      // siempre ni el error salir sin atender de un `unawaited`.
    } finally {
      // Con la pantalla cerrada no hay nada que volver a dibujar.
      if (mounted) setState(() => _reintentando = false);
    }
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
        child: AvisoDrive(
          key: const Key('aviso_sin_respaldo'),
          clase: ClaseAvisoDrive.error,
          texto: TextosRespaldoDrive.avisoSinRespaldo(dias),
          accion: _reintentando ? TextosRespaldoDrive.reintentando : TextosRespaldoDrive.reintentar,
          alAccionar: _reintentando ? null : () => unawaited(_reintentar()),
        ),
      ),
    );
  }
}
