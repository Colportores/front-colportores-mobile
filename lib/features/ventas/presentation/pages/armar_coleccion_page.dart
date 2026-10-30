import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../catalogo/domain/entities/item_de_precio.dart';
import '../../domain/entities/componente_vendido.dart';
import '../formato_venta.dart';
import '../widgets/hoja_elegir_libro.dart';
import '../widgets/piezas_venta.dart';

/// Un producto que siempre va en la colección (lo que el combo trae fijo).
final class BaseDeColeccion {
  const BaseDeColeccion({required this.componente, required this.nombre, required this.glifo});

  final ComponenteVendido componente;
  final String nombre;
  final String glifo;
}

/// Lo que la colportora armó: los libros que eligió, en orden.
final class ColeccionArmada {
  const ColeccionArmada(this.elegidos);

  final List<PrecioDeProducto> elegidos;
}

/// Armar una colección (27A·02, 27A·04 y 27A·06): lo que siempre va y un lugar por cada libro a
/// elegir del catálogo. «Agregar a la venta» se enciende cuando están todos.
///
/// [elegidosAlAbrir] son los libros de una colección que ya estaba en la venta (27A·06); con ellos
/// se puede cambiar uno o, con [alQuitar], sacarla.
class ArmarColeccionPage extends StatefulWidget {
  const ArmarColeccionPage({
    super.key,
    required this.combo,
    required this.ciudad,
    required this.base,
    required this.libros,
    this.elegidosAlAbrir = const [],
    this.alQuitar,
  });

  final PrecioDeCombo combo;
  final String ciudad;
  final List<BaseDeColeccion> base;

  /// Los libros del catálogo que se pueden elegir.
  final List<PrecioDeProducto> libros;
  final List<PrecioDeProducto> elegidosAlAbrir;
  final VoidCallback? alQuitar;

  @override
  State<ArmarColeccionPage> createState() => _ArmarColeccionPageState();
}

class _ArmarColeccionPageState extends State<ArmarColeccionPage> {
  late final List<PrecioDeProducto?> _elegidos;
  var _abriendo = false;

  @override
  void initState() {
    super.initState();
    _elegidos = [
      for (var i = 0; i < widget.combo.librosAElegir; i++)
        i < widget.elegidosAlAbrir.length ? widget.elegidosAlAbrir[i] : null,
    ];
  }

  int get _primeroSinElegir => _elegidos.indexWhere((l) => l == null);

  bool get _completa =>
      _primeroSinElegir < 0 && (_elegidos.isNotEmpty || widget.combo.librosAElegir == 0);

  Future<void> _elegir(int i) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      final libro = await mostrarHojaElegirLibro(
        context,
        titulo: TextosVenta.tituloHojaLibro(i + 1, yaElegido: _elegidos[i] != null),
        libros: widget.libros,
        actual: _elegidos[i],
      );
      if (libro != null && mounted) setState(() => _elegidos[i] = libro);
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final precio = TextosVenta.precioEn(FormatoVenta.monto(widget.combo.centavos), widget.ciudad);
    final falta = _primeroSinElegir;
    return Scaffold(
      key: const Key('armar_coleccion_pagina'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: CabeceraVenta(
                      eyebrow: TextosVenta.eyebrowColeccion,
                      titulo: widget.combo.nombre,
                      subtitulo: precio,
                      alVolver: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const RotuloDeSeccion(TextosVenta.siempreVan),
                  for (final b in widget.base)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: TarjetaDeLibro(glifo: b.glifo, titulo: b.nombre, accion: '⊙'),
                    ),
                  if (widget.combo.librosAElegir > 0) ...[
                    const SizedBox(height: 4),
                    const RotuloDeSeccion(TextosVenta.librosQueElegis),
                    if (widget.libros.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          TextosVenta.sinLibrosParaElegir,
                          key: Key('armar_sin_libros'),
                          style: TextStyle(fontSize: 14, color: ColoresAgenda.gris),
                        ),
                      ),
                    for (var i = 0; i < _elegidos.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: TarjetaDeLibro(
                          key: Key('armar_libro_${i + 1}'),
                          glifo: '${i + 1}',
                          rotulo: TextosVenta.libroN(i + 1),
                          titulo: _elegidos[i]?.nombre ?? TextosVenta.elegirDelCatalogo,
                          accion: _elegidos[i] == null ? '›' : TextosVenta.cambiar,
                          vacia: _elegidos[i] == null,
                          alPresionar: () => _elegir(i),
                        ),
                      ),
                  ],
                  if (widget.alQuitar != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('armar_quitar'),
                        onPressed: widget.alQuitar,
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        child: const Text(
                          TextosVenta.quitar,
                          style: TextStyle(color: ColoresAgenda.rojo, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: BotonDeVenta(
                texto: TextosVenta.agregarALaVenta,
                nota: _completa || falta < 0 ? null : TextosVenta.elegiElLibro(falta + 1),
                alPresionar: _completa
                    ? () => Navigator.of(
                        context,
                      ).pop(ColeccionArmada([for (final l in _elegidos) ?l]))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
