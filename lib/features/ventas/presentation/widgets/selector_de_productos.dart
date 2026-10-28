import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../catalogo/domain/entities/item_de_precio.dart';
import '../../../catalogo/domain/services/resolvedor_de_precios.dart';
import '../formato_venta.dart';
import '../providers/nueva_venta_notifier.dart';
import 'piezas_venta.dart';

/// Lo que se elige para vender (27A·01, 27A·07 y 27A·08): las categorías como chips y, debajo, las
/// colecciones (se elige una y se arma) o los productos sueltos con su cantidad.
///
/// Parte de lo que la venta ya lleva ([actual]), así que abrirlo de nuevo no pierde nada.
class SelectorDeProductos extends StatefulWidget {
  const SelectorDeProductos({
    super.key,
    required this.items,
    required this.actual,
    required this.alArmarLaColeccion,
    required this.alAgregarProductos,
  });

  final List<ItemDePrecio> items;
  final NuevaVentaState actual;

  /// «Armar la colección» con la colección elegida.
  final ValueChanged<PrecioDeCombo> alArmarLaColeccion;

  /// «Agregar a la venta» con lo que cambió en las cantidades.
  final ValueChanged<List<ProductoElegido>> alAgregarProductos;

  @override
  State<SelectorDeProductos> createState() => _SelectorDeProductosState();
}

class _SelectorDeProductosState extends State<SelectorDeProductos> {
  late CategoriaDePrecios _categoria;
  String? _comboId;
  late final Map<String, int> _cantidades;

  @override
  void initState() {
    super.initState();
    _cantidades = {
      for (final item in widget.items)
        if (item is PrecioDeProducto) item.id: widget.actual.cantidadDe(item.id),
    };
    _categoria = CategoriaDePrecios.values.firstWhere(
      (c) => ResolvedorDePrecios.deLaCategoria(widget.items, c).isNotEmpty,
      orElse: () => CategoriaDePrecios.colecciones,
    );
  }

  static const _nombres = {
    CategoriaDePrecios.colecciones: TextosVenta.colecciones,
    CategoriaDePrecios.libros: TextosVenta.libros,
    CategoriaDePrecios.misioneros: TextosVenta.misioneros,
    CategoriaDePrecios.revistas: TextosVenta.revistas,
  };

  List<ProductoElegido> _cambios() {
    final productos = {
      for (final item in widget.items)
        if (item is PrecioDeProducto) item.id: item,
    };
    return [
      for (final e in _cantidades.entries)
        if (e.value != widget.actual.cantidadDe(e.key))
          ProductoElegido(producto: productos[e.key]!, cantidad: e.value),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final deLaCategoria = ResolvedorDePrecios.deLaCategoria(widget.items, _categoria);
    final cambios = _cambios();
    final esColecciones = _categoria == CategoriaDePrecios.colecciones;
    final combo = esColecciones
        ? deLaCategoria.whereType<PrecioDeCombo>().where((c) => c.id == _comboId).firstOrNull
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final c in CategoriaDePrecios.values)
              ChipDeVenta(
                texto: _nombres[c]!,
                elegido: c == _categoria,
                alPresionar: () => setState(() => _categoria = c),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (deLaCategoria.isEmpty)
          Padding(
            key: const Key('venta_categoria_vacia'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    TextosVenta.sinProductosEnLaCategoria,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  TextosVenta.sinProductosEnLaCategoriaSub,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: ColoresAgenda.gris),
                ),
              ],
            ),
          )
        else if (esColecciones)
          for (final item in deLaCategoria.whereType<PrecioDeCombo>())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilaElegible(
                titulo: item.nombre,
                detalle: _detalleDelCombo(item),
                precio: FormatoVenta.monto(item.centavos),
                elegida: item.id == _comboId,
                alPresionar: () => setState(() => _comboId = item.id),
              ),
            )
        else ...[
          for (final item in deLaCategoria.whereType<PrecioDeProducto>())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilaDeCantidad(
                titulo: item.nombre,
                // Un misionero no lleva precio de lista: va sin cobrar.
                precio: item.categoria == CategoriaDePrecios.misioneros
                    ? TextosVenta.sinCobrar
                    : FormatoVenta.monto(item.centavos),
                cantidad: _cantidades[item.id] ?? 0,
                alCambiar: (n) => setState(() => _cantidades[item.id] = n),
                etiqueta: switch (item.categoria) {
                  CategoriaDePrecios.misioneros => TextosVenta.misionero,
                  CategoriaDePrecios.revistas => TextosVenta.revista,
                  _ => item.esBonificable ? '◆ Bonificable' : null,
                },
                tintaEtiqueta: item.categoria == CategoriaDePrecios.misioneros
                    ? const Color(0xFF1F6E3A)
                    : ColoresAgenda.ambarTinta,
                fondoEtiqueta: item.categoria == CategoriaDePrecios.misioneros
                    ? const Color(0xFFDDE8D3)
                    : ColoresAgenda.ambarFondo,
              ),
            ),
        ],
        const SizedBox(height: 12),
        if (esColecciones)
          BotonDeVenta(
            texto: TextosVenta.armarLaColeccion,
            alPresionar: combo == null ? null : () => widget.alArmarLaColeccion(combo),
          )
        else
          BotonDeVenta(
            texto: TextosVenta.agregarALaVenta,
            alPresionar: cambios.isEmpty ? null : () => widget.alAgregarProductos(cambios),
          ),
      ],
    );
  }

  String _detalleDelCombo(PrecioDeCombo combo) {
    final base = combo.componentes.map((c) => c.nombre).join(', ');
    final libros = combo.librosAElegir > 0 ? TextosVenta.librosAElegir(combo.librosAElegir) : null;
    return [if (base.isNotEmpty) base, ?libros].join(' + ');
  }
}
