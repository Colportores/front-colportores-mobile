import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/entrega_pendiente.dart';
import '../formato_entrega_diferida.dart';
import '../providers/entrega_diferida_providers.dart';
import '../providers/entrega_providers.dart';
import 'piezas_entrega_diferida.dart';

/// «¿Qué venta?» de «Registrar entrega» en la ficha de la persona (32B·01): cuando tiene más de una
/// venta con algo pendiente de entregar, la colportora elige cuál entrega, como C·08 del cobro. Tocar
/// una fila la elige y cierra la hoja; «Cancelar», atrás o tocar afuera devuelven `null`.
///
/// Las filas son las de «Entregas pendientes» (27C·02, [TarjetaDeEntregaPendiente]): el día (o «Sin
/// fecha»), la venta y qué falta. El canvas no la dibuja: reusa piezas aprobadas.
Future<EntregaPendiente?> mostrarHojaQueEntrega(
  BuildContext context, {
  required List<EntregaPendiente> pendientes,
}) => showModalBottomSheet<EntregaPendiente>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => HojaQueEntrega(pendientes: pendientes),
);

/// La hoja de [mostrarHojaQueEntrega].
class HojaQueEntrega extends ConsumerStatefulWidget {
  const HojaQueEntrega({super.key, required this.pendientes});

  final List<EntregaPendiente> pendientes;

  @override
  ConsumerState<HojaQueEntrega> createState() => _HojaQueEntregaState();
}

class _HojaQueEntregaState extends ConsumerState<HojaQueEntrega> {
  /// Ya se está cerrando: un segundo toque no cierra otra vez (sacaría también la pantalla de abajo).
  var _cerrando = false;

  void _cerrar([EntregaPendiente? elegida]) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(elegida);
  }

  @override
  Widget build(BuildContext context) {
    final nombres = ref.watch(nombresDeLosPendientesProvider).value;
    final ahora = ref.read(relojEntregaProvider)();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosEntregaDiferida.queVenta,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              TextosEntregaDiferida.queVentaSub,
              style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF5B6B82)),
            ),
            const SizedBox(height: 14),
            for (final p in widget.pendientes) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE3E7EE)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TarjetaDeEntregaPendiente(
                  key: ValueKey('que_entrega_${p.ventaId}'),
                  tono: p.sinFecha
                      ? TonoDeEntrega.sinFecha
                      : p.estaAtrasada(ahora)
                      ? TonoDeEntrega.atrasada
                      : TonoDeEntrega.proxima,
                  dia: p.fechaPrevista == null
                      ? TextosEntregaDiferida.sinFecha
                      : FormatoEntregaDiferida.rotuloDeLaTarjeta(p.fechaPrevista!),
                  persona: p.numeroTalonario == null
                      ? ''
                      : TextosEntregaDiferida.venta(p.numeroTalonario!),
                  detalle: FormatoEntregaDiferida.detalleDeLaTarjeta(
                    p,
                    direccion: '',
                    nombres: nombres,
                  ),
                  alAbrir: () => _cerrar(p),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            OutlinedButton(
              key: const Key('que_entrega_cancelar'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _cerrar,
              child: const Text(TextosEntregaDiferida.cancelar),
            ),
          ],
        ),
      ),
    );
  }
}
