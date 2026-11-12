import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart' show ColoresAlta;
import '../../domain/entities/venta_abierta.dart';
import '../formato_venta.dart';
import '../textos_venta_que_crece.dart';

/// «¿A qué venta lo sumás?» (42B·09B, «Venta crece»): con más de una venta abierta de la persona, la
/// colportora elige a cuál se suma el libro, con la forma de «¿Qué venta?» del cobro (39 C·08). Viene
/// elegida la más reciente ([ventas] llega de la más reciente a la más vieja). Devuelve la elegida, o
/// `null` si tocó «Cancelar» o cerró sin elegir.
///
/// [subtitulo] es «Pedro Gómez · Grecia 3307».
Future<VentaAbierta?> mostrarHojaAQueVenta(
  BuildContext context, {
  required List<VentaAbierta> ventas,
  required String subtitulo,
}) => showModalBottomSheet<VentaAbierta>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaAQueVenta(ventas: ventas, subtitulo: subtitulo),
);

/// La hoja de «¿A qué venta lo sumás?». Ver [mostrarHojaAQueVenta].
class HojaAQueVenta extends StatefulWidget {
  const HojaAQueVenta({super.key, required this.ventas, required this.subtitulo});

  final List<VentaAbierta> ventas;
  final String subtitulo;

  @override
  State<HojaAQueVenta> createState() => _HojaAQueVentaState();
}

class _HojaAQueVentaState extends State<HojaAQueVenta> {
  /// La venta tocada; `null` = la primera (la más reciente).
  String? _elegidaId;

  /// Ya se está cerrando: un doble toque no cierra dos veces.
  var _cerrando = false;

  VentaAbierta? get _elegida => widget.ventas.isEmpty
      ? null
      : widget.ventas.firstWhere((v) => v.ventaId == _elegidaId, orElse: () => widget.ventas.first);

  void _cerrarCon(VentaAbierta? venta) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(venta);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elegida = _elegida;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ColoresAlta.grisBorde,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Flexible(
          child: ListView.separated(
            key: ClavesAQueVenta.lista,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            itemCount: widget.ventas.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        TextosVentaQueCrece.aQueVenta,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    if (widget.subtitulo.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          widget.subtitulo,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris,
                          ),
                        ),
                      ),
                  ],
                );
              }
              final venta = widget.ventas[i - 1];
              return _Opcion(
                key: ClavesAQueVenta.fila(venta.ventaId),
                venta: venta,
                elegida: venta.ventaId == elegida?.ventaId,
                alTocar: () => setState(() => _elegidaId = venta.ventaId),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: ClavesAQueVenta.sumar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: elegida == null ? null : () => _cerrarCon(_elegida),
                child: const Text(TextosVentaQueCrece.sumarAEstaVenta, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: ClavesAQueVenta.cancelar,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  foregroundColor: ColoresAlta.tinta,
                  side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
                ),
                onPressed: () => _cerrarCon(null),
                child: const Text(TextosVentaQueCrece.cancelar, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Una venta de 42B·09B: el círculo de elección, «Venta 0039 · 23/10», qué se vendió y su saldo, y a
/// la derecha el total. Elegida: fondo azul claro y borde de 2.
class _Opcion extends StatelessWidget {
  const _Opcion({super.key, required this.venta, required this.elegida, required this.alTocar});

  final VentaAbierta venta;
  final bool elegida;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navy = theme.colorScheme.primary;
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    return Semantics(
      container: true,
      excludeSemantics: true,
      inMutuallyExclusiveGroup: true,
      checked: elegida,
      label: TextosVentaQueCrece.opcionParaLector(venta),
      onTap: alTocar,
      child: Material(
        color: elegida ? const Color(0xFFF2F6FB) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: elegida
              ? BorderSide(color: navy, width: 2)
              : const BorderSide(color: Color(0xFFE3E7EE)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: elegida ? navy : Colors.white,
                      border: Border.all(color: elegida ? navy : ColoresAlta.gris, width: 1.5),
                    ),
                    child: elegida ? const Icon(Icons.circle, size: 8, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TextosVentaQueCrece.ventaDel(venta),
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          TextosVentaQueCrece.detalleDe(venta),
                          style: theme.textTheme.bodyMedium?.copyWith(color: gris),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    FormatoVenta.monto(venta.montoTotalCentavos),
                    key: ClavesAQueVenta.total(venta.ventaId),
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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

/// Las claves de «¿A qué venta lo sumás?» (para los tests y la QA).
abstract final class ClavesAQueVenta {
  static const lista = Key('a_que_venta_lista');
  static const sumar = Key('a_que_venta_sumar');
  static const cancelar = Key('a_que_venta_cancelar');

  static Key fila(String ventaId) => Key('a_que_venta_fila_$ventaId');
  static Key total(String ventaId) => Key('a_que_venta_total_$ventaId');
}
