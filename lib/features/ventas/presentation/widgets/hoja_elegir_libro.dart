import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../catalogo/domain/entities/item_de_precio.dart';
import '../../../catalogo/domain/services/resolvedor_de_precios.dart';
import '../formato_venta.dart';
import 'piezas_venta.dart';

/// La hoja «Libro 2» / «Cambiar el libro 1» (27A·03 y 27A·06): el catálogo de libros de la ciudad
/// con un buscador por nombre o código. Devuelve el libro elegido al tocar «Listo», o `null` si se
/// cierra sin elegir.
Future<PrecioDeProducto?> mostrarHojaElegirLibro(
  BuildContext context, {
  required String titulo,
  required List<PrecioDeProducto> libros,
  PrecioDeProducto? actual,
}) => showModalBottomSheet<PrecioDeProducto>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => HojaElegirLibro(titulo: titulo, libros: libros, actual: actual),
);

class HojaElegirLibro extends StatefulWidget {
  const HojaElegirLibro({super.key, required this.titulo, required this.libros, this.actual});

  final String titulo;
  final List<PrecioDeProducto> libros;
  final PrecioDeProducto? actual;

  @override
  State<HojaElegirLibro> createState() => _HojaElegirLibroState();
}

class _HojaElegirLibroState extends State<HojaElegirLibro> {
  final _busqueda = TextEditingController();
  PrecioDeProducto? _elegido;
  var _consulta = '';

  @override
  void initState() {
    super.initState();
    _elegido = widget.actual;
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _consulta.trim().isEmpty
        ? widget.libros
        : ResolvedorDePrecios.buscar(
            widget.libros,
            _consulta,
          ).whereType<PrecioDeProducto>().toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Semantics(
              header: true,
              child: Text(
                widget.titulo,
                key: const Key('venta_hoja_libro_titulo'),
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: CampoDeVenta(
              key: const Key('venta_hoja_libro_busqueda'),
              rotulo: null,
              controlador: _busqueda,
              alCambiar: (t) => setState(() => _consulta = t),
              hint: TextosVenta.buscar,
              icono: Icons.search,
            ),
          ),
          Flexible(
            child: visibles.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.libros.isEmpty
                          ? TextosVenta.sinLibrosParaElegir
                          : TextosVenta.sinResultados,
                      key: const Key('venta_hoja_libro_vacia'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: ColoresAgenda.gris),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final libro = visibles[i];
                      return FilaElegible(
                        titulo: libro.nombre,
                        detalle: libro.esBonificable
                            ? TextosVenta.subtituloLibroBonificable
                            : TextosVenta.subtituloLibro,
                        elegida: libro.id == _elegido?.id,
                        alPresionar: () => setState(() => _elegido = libro),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: BotonDeVenta(
              texto: TextosVenta.listo,
              alPresionar: _elegido == null ? null : () => Navigator.of(context).pop(_elegido),
            ),
          ),
        ],
      ),
    );
  }
}
