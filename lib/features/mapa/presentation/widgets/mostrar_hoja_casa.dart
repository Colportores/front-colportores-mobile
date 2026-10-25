import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/lista_ubicaciones.dart';
import '../providers/lista_ubicaciones_notifier.dart';
import '../providers/lista_ubicaciones_providers.dart';
import 'hoja_casa.dart';

/// Abre la hoja de la casa desde la Lista (vista 05): «la misma que en el mapa»
/// (`00 Navegacion.dc.html`). Es una hoja modal a la altura de su contenido; la ✕, el atrás del
/// teléfono y tocar afuera la cierran sin cambiar nada.
///
/// La hoja sigue a la Lista: si la casa cambia mientras está abierta (se reactivó, cambió su color)
/// se ve el cambio; si la casa sale de la lista que se está viendo (otro filtro) queda la última
/// que se tuvo. [alReactivar] es el «Reactivar» de una casa dada de baja (E·04); sin él, el aviso va
/// sin acción.
Future<void> mostrarHojaCasa(
  BuildContext context, {
  required String colportorId,
  required ItemListaUbicacion item,
  FutureOr<void> Function(ItemListaUbicacion item)? alReactivar,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) =>
      _HojaCasaDeLaLista(colportorId: colportorId, inicial: item, alReactivar: alReactivar),
);

class _HojaCasaDeLaLista extends ConsumerWidget {
  const _HojaCasaDeLaLista({
    required this.colportorId,
    required this.inicial,
    required this.alReactivar,
  });

  final String colportorId;
  final ItemListaUbicacion inicial;
  final FutureOr<void> Function(ItemListaUbicacion item)? alReactivar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = inicial.ubicacion.id;
    final vivo = ref.watch(
      listaUbicacionesProvider(colportorId).select((estado) {
        for (final fila in estado.lista?.items ?? const <ItemListaUbicacion>[]) {
          if (fila.ubicacion.id == id) return fila;
        }
        return null;
      }),
    );
    final item = vivo ?? inicial;
    return HojaCasa(
      item: item,
      ahora: ref.watch(relojListaUbicacionesProvider)(),
      alCerrar: () => Navigator.of(context).maybePop(),
      alReactivar: alReactivar == null || !item.puedeReactivarse ? null : () => alReactivar!(item),
    );
  }
}
