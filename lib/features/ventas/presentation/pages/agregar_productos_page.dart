import 'package:flutter/material.dart';

import '../../../catalogo/domain/entities/item_de_precio.dart';
import '../formato_venta.dart';
import '../providers/nueva_venta_notifier.dart';
import '../widgets/piezas_venta.dart';
import '../widgets/selector_de_productos.dart';

/// Lo que "+ Agregar" devuelve: una colección para armar o productos sueltos con su cantidad.
sealed class LoAgregado {
  const LoAgregado();
}

final class AgregoColeccion extends LoAgregado {
  const AgregoColeccion(this.combo);

  final PrecioDeCombo combo;
}

final class AgregoProductos extends LoAgregado {
  const AgregoProductos(this.productos);

  final List<ProductoElegido> productos;
}

/// «Agregar productos» (27A·07 y 27A·08): se abre desde «+ Agregar» de una venta que ya tiene algo.
class AgregarProductosPage extends StatelessWidget {
  const AgregarProductosPage({super.key, required this.items, required this.actual});

  final List<ItemDePrecio> items;
  final NuevaVentaState actual;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('agregar_productos_pagina'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            CabeceraVenta(
              eyebrow: TextosVenta.eyebrowAgregar,
              titulo: TextosVenta.tituloAgregar,
              alVolver: () => Navigator.of(context).maybePop(),
            ),
            SelectorDeProductos(
              items: items,
              actual: actual,
              alArmarLaColeccion: (c) => Navigator.of(context).pop(AgregoColeccion(c)),
              alAgregarProductos: (p) => Navigator.of(context).pop(AgregoProductos(p)),
            ),
          ],
        ),
      ),
    );
  }
}
