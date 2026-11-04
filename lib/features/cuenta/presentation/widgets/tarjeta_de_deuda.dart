import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/deuda_casa_page.dart';
import '../providers/deuda_casa_providers.dart';
import '../textos_deuda.dart';
import 'piezas_cuenta.dart';

/// La tarjeta «Deuda con la casa editora» de Mi Cuenta (33A·01): el total que dijo el servidor por
/// última vez y un toque que abre el detalle por pedido (33B).
///
/// Si todavía no llegó nada (primera vez, sin conexión), no se dibuja una cifra: solo el rótulo, y el
/// toque lleva al detalle, que explica qué pasa. Cuánto cambió contra la semana pasada no se dibuja:
/// el servidor no guarda la deuda de hace una semana.
class TarjetaDeDeuda extends ConsumerStatefulWidget {
  const TarjetaDeDeuda({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  @override
  ConsumerState<TarjetaDeDeuda> createState() => _TarjetaDeDeudaState();
}

class _TarjetaDeDeudaState extends ConsumerState<TarjetaDeDeuda> {
  /// Ya se está abriendo el detalle: un segundo toque antes de que termine no abre otro encima.
  var _abriendo = false;

  Future<void> _abrir() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await DeudaCasaPage.abrir(context, colportorId: widget.colportorId);
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deuda = ref.watch(deudaConLaCasaProvider(widget.colportorId)).lectura?.deuda;
    final aFavor = deuda?.aFavor ?? false;
    final monto = deuda == null ? null : FormatoDeuda.total(deuda);
    final hablado = deuda == null ? null : FormatoDeuda.totalHablado(deuda);
    final sinNada = deuda != null && deuda.deudaTotalCentavos == 0;
    final fondo = sinNada
        ? ColoresCuenta.grisFondo
        : (aFavor ? ColoresCuenta.verdeFondo : _rojoFondo);
    final tinta = sinNada
        ? ColoresCuenta.gris
        : (aFavor ? ColoresCuenta.verde : ColoresCuenta.rojo);

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      onTap: _abrir,
      label: hablado == null
          ? 'Deuda con la casa editora'
          : 'Deuda con la casa editora, ${hablado.replaceFirst('Total, ', '')}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresCuenta.borde),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('cuenta_deuda'),
          onTap: _abrir,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '▤',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: tinta),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        TextosDeuda.rotuloTarjeta,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          letterSpacing: 1.4,
                          color: ColoresCuenta.gris,
                        ),
                      ),
                      if (monto != null)
                        Text(
                          monto,
                          key: const Key('cuenta_deuda_monto'),
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: ColoresCuenta.tinta,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const ExcludeSemantics(
                  child: Text(
                    '›',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 18, color: ColoresCuenta.gris),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _rojoFondo = Color(0xFFFBEDEC);
}
