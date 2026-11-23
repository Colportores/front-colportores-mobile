import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cuenta/presentation/widgets/piezas_cuenta.dart' show ColoresCuenta;
import '../../domain/entities/pedido.dart';
import '../providers/pedidos_providers.dart';
import '../textos_pedidos.dart';

/// La fila «Mis pedidos · 1 por autorizar ›» de Mi Cuenta (33A·01): abre la lista de pedidos a la casa
/// editora (37B). Con pedidos por autorizar los cuenta; sin ninguno, o si todavía no se leyeron, solo el
/// «›»: no inventa un cero.
class EnlaceAMisPedidos extends ConsumerWidget {
  const EnlaceAMisPedidos({super.key, required this.colportorId, required this.alAbrir});

  final String colportorId;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final porAutorizar = ref.watch(
      pedidosProvider(
        colportorId,
      ).select((p) => p.value?.where((e) => e.estado == EstadoDelPedido.porAutorizar).length ?? 0),
    );
    final resumen = porAutorizar > 0 ? TextosPedidos.porAutorizar(porAutorizar) : null;
    return Semantics(
      button: true,
      container: true,
      label: resumen == null ? TextosPedidos.misPedidos : '${TextosPedidos.misPedidos}, $resumen',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresCuenta.borde, width: 1.5),
        ),
        child: InkWell(
          key: const Key('cuenta_mis_pedidos'),
          borderRadius: BorderRadius.circular(14),
          onTap: alAbrir,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        TextosPedidos.misPedidos,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (resumen != null)
                      Flexible(
                        child: Text(
                          resumen,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13.5, color: ColoresCuenta.gris),
                        ),
                      ),
                    const Icon(Icons.chevron_right, color: ColoresCuenta.gris),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
