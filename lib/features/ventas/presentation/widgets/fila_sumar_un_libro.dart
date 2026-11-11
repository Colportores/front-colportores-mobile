import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../providers/ventas_providers.dart';
import '../textos_venta_que_crece.dart';

/// «Sumar un libro» (42B·09A, «Venta crece»): la fila debajo de la persona, en la hoja de la casa y en
/// su ficha (32B), **solo si esa persona tiene una venta abierta** (con saldo o con algo por entregar).
/// Con una sola dice a cuál se suma («A la venta 0039 de Pedro, sin otro talonario»); con varias, que
/// se elige después. Sin ventas abiertas, o si no se pueden leer, no se dibuja (un botón que no lleva a
/// ningún lado sería mentir).
///
/// [alTocar] lo arma quien muestra la fila (comparte la guarda de una acción a la vez); `null` = no se
/// ofrece. Mientras [ocupada] la fila queda apagada.
class FilaSumarUnLibro extends ConsumerWidget {
  const FilaSumarUnLibro({
    super.key,
    required this.personaId,
    required this.nombre,
    required this.alTocar,
    this.ocupada = false,
    this.separacion = 0,
  });

  final String personaId;

  /// El nombre de pila de la persona («de Pedro»); vacío o `null` = sin nombre.
  final String? nombre;
  final VoidCallback? alTocar;
  final bool ocupada;

  /// El aire de arriba, solo cuando la fila se dibuja (sin venta abierta no deja un hueco).
  final double separacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (alTocar == null) return const SizedBox.shrink();
    final abiertas = ref.watch(ventasAbiertasDeProvider(personaId)).asData?.value ?? const [];
    if (abiertas.isEmpty) return const SizedBox.shrink();
    final detalle = abiertas.length == 1
        ? TextosVentaQueCrece.aLaVenta(abiertas.single.numeroTalonario, nombre)
        : TextosVentaQueCrece.aUnaDeSusVentas(nombre);
    final alPresionar = ocupada ? null : alTocar;
    final fila = Semantics(
      key: ClavesSumarUnLibro.fila,
      container: true,
      button: true,
      enabled: alPresionar != null,
      label: '${TextosVentaQueCrece.sumarUnLibro}. $detalle',
      onTap: alPresionar,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE3E7EE)),
        ),
        child: InkWell(
          key: ClavesSumarUnLibro.tocar,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: alPresionar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6EEF8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '+',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: ColoresAgenda.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          TextosVentaQueCrece.sumarUnLibro,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          detalle,
                          key: ClavesSumarUnLibro.detalle,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: ColoresAgenda.gris,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '›',
                    style: TextStyle(fontSize: 20, height: 1, color: ColoresAgenda.gris),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return separacion > 0
        ? Padding(
            padding: EdgeInsets.only(top: separacion),
            child: fila,
          )
        : fila;
  }
}

/// Las claves de «Sumar un libro» (para los tests y la QA).
abstract final class ClavesSumarUnLibro {
  static const fila = Key('sumar_un_libro');
  static const tocar = Key('sumar_un_libro_tocar');
  static const detalle = Key('sumar_un_libro_detalle');
}
