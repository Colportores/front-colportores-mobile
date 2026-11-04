import 'package:flutter/material.dart';

import '../../domain/entities/item_de_precio.dart';
import '../formato_precios.dart';
import 'piezas_precios.dart';

const _scrim = Color(0x730E1A2B);

/// Abre el detalle de un combo (26·03): de qué productos se compone y su precio en [ciudad].
Future<void> mostrarHojaDetalleDelCombo(
  BuildContext context, {
  required PrecioDeCombo combo,
  required String ciudad,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  barrierColor: _scrim,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaDetalleDelCombo(combo: combo, ciudad: ciudad),
);

/// La hoja «Detalle de una colección» (26·03): «Siempre van», «Libros a elegir» y «Precio en `ciudad`».
class HojaDetalleDelCombo extends StatelessWidget {
  const HojaDetalleDelCombo({super.key, required this.combo, required this.ciudad});

  final PrecioDeCombo combo;
  final String ciudad;

  @override
  Widget build(BuildContext context) {
    final fijos = [
      for (final c in combo.componentes) c.cantidad > 1 ? '${c.cantidad} × ${c.nombre}' : c.nombre,
    ].join(', ');
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 8),
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFCFD6E1),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Semantics(
                header: true,
                child: Text(
                  combo.nombre,
                  style: const TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
              child: Text(
                FormatoPrecios.textoDelCombo(combo),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  height: 1.5,
                  color: ColoresPrecios.tinta,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ColoresPrecios.borde),
                ),
                child: Column(
                  children: [
                    if (fijos.isNotEmpty) _Fila(TextosPrecios.siempreVan, fijos),
                    if (combo.librosAElegir > 0)
                      _Fila(TextosPrecios.librosAElegir, '${combo.librosAElegir}'),
                    _Fila(
                      'Precio en $ciudad',
                      FormatoPrecios.monto(combo.centavos),
                      fuerte: true,
                      clave: const Key('precios_detalle_precio'),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
              child: OutlinedButton(
                key: const Key('precios_cerrar_detalle'),
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: ColoresPrecios.tinta,
                  side: const BorderSide(color: Color(0xFFCFD6E1), width: 1.5),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text(TextosPrecios.cerrar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.rotulo, this.valor, {this.fuerte = false, this.clave});

  final String rotulo;
  final String valor;
  final bool fuerte;
  final Key? clave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 2,
        children: [
          Text(
            rotulo,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: ColoresPrecios.gris),
          ),
          const SizedBox(width: 12),
          Text(
            valor,
            key: clave,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: fuerte ? 'JetBrainsMono' : 'Inter',
              fontSize: 14,
              fontWeight: fuerte ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
