import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart' show AvisoDeVenta;
import '../providers/depositos_providers.dart';
import '../textos_deposito.dart';

/// El aviso de 38A-08: la foto de un ticket de depósito no pudo subir. El depósito ya quedó
/// registrado y la cola de fotos la reintenta sola; «Reintentar ahora» hace una pasada ya.
///
/// Sin tickets en esa situación (o mientras se lee) no ocupa lugar. Lo muestran «Registrar depósito»
/// arriba del formulario, como el canvas, y Mi Cuenta, donde el colportor vuelve después.
class AvisoDeTicketsSinSubir extends ConsumerStatefulWidget {
  const AvisoDeTicketsSinSubir({super.key, this.margen = EdgeInsets.zero});

  /// El espacio alrededor cuando se ve.
  final EdgeInsetsGeometry margen;

  @override
  ConsumerState<AvisoDeTicketsSinSubir> createState() => _AvisoDeTicketsSinSubirState();
}

class _AvisoDeTicketsSinSubirState extends ConsumerState<AvisoDeTicketsSinSubir> {
  /// Hay una pasada en curso: otro toque no lanza una segunda.
  var _reintentando = false;

  Future<void> _reintentar() async {
    if (_reintentando) return;
    setState(() => _reintentando = true);
    try {
      await ref.read(reintentarSubidaDeTicketsProvider)();
    } on Object catch (e, st) {
      // La foto sigue guardada y la cola la vuelve a probar sola: el aviso queda como estaba.
      AppLogger.instance.error(
        LogModulo.net,
        'DEPOSITO_REINTENTO_FOTO_FAIL',
        'falló el reintento a mano de las fotos de los tickets',
        {'tipo': e.runtimeType.toString()},
        null,
        st,
      );
    } finally {
      if (mounted) setState(() => _reintentando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuantos = ref.watch(ticketsDeDepositoSinSubirProvider).value ?? 0;
    if (cuantos == 0) return const SizedBox.shrink();
    return Padding(
      padding: widget.margen,
      child: AvisoDeVenta(
        key: const Key('deposito_ticket_sin_subir'),
        texto: TextosDeposito.ticketsSinSubir(cuantos),
        textoAccion: TextosDeposito.reintentarAhora,
        alAccion: _reintentando ? null : () => unawaited(_reintentar()),
      ),
    );
  }
}
