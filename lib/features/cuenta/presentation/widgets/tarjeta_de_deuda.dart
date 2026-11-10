import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/deuda_casa_page.dart';
import '../providers/deuda_casa_providers.dart';
import '../textos_deuda.dart';
import 'piezas_cuenta.dart';

/// La tarjeta «Deuda con la casa editora» de Mi Cuenta (33A·01): el total que dijo el servidor por
/// última vez y un toque que abre el detalle por pedido (33B).
///
/// Debajo del total va cuánto cambió contra la semana pasada, con la deuda de hace 7 días que registra
/// el servidor (33A·01: «▼ $ 2.100 contra la semana pasada»; sin ese dato, «Sin datos de la semana
/// anterior»).
///
/// Si todavía no llegó nada (primera vez) no se dibuja una cifra: solo el rótulo, y una línea gris que
/// dice por qué (decisión del orquestador, 04/11, por el mapa: estados que no se saben): leyendo, el
/// bloque gris de 33A·03; sin conexión, que hace falta; con la red y una falla, que no se pudo. El
/// toque lleva al detalle, que lo explica y ofrece «Reintentar».
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
    final estado = ref.watch(deudaConLaCasaProvider(widget.colportorId));
    final deuda = estado.lectura?.deuda;
    final sinLectura = deuda == null ? _lineaSinLectura(estado) : null;
    final aFavor = deuda?.aFavor ?? false;
    final monto = deuda == null ? null : FormatoDeuda.total(deuda);
    final String etiqueta;
    if (deuda == null) {
      etiqueta = [TextosDeuda.titulo, if (sinLectura != null) sinLectura.hablado].join('. ');
    } else {
      final total = FormatoDeuda.totalHablado(deuda).replaceFirst('Total, ', '');
      etiqueta = '${TextosDeuda.titulo}, $total. ${FormatoDeuda.variacionHablada(deuda)}';
    }
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
      label: etiqueta,
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
                      if (deuda != null)
                        Text(
                          FormatoDeuda.lineaDeVariacion(deuda),
                          key: const Key('cuenta_deuda_variacion'),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            color: _colorDeLaVariacion(deuda.variacionCentavos),
                          ),
                        ),
                      if (sinLectura != null) sinLectura.widget,
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

  /// Verde si la deuda bajó (buena noticia); gris si no hay con qué comparar, no se movió o subió, que
  /// el canvas no dibuja (el mismo criterio de las otras tarjetas de Mi Cuenta).
  static Color _colorDeLaVariacion(int? variacionCentavos) =>
      variacionCentavos != null && variacionCentavos < 0 ? ColoresCuenta.verde : ColoresCuenta.gris;

  /// La línea gris de la tarjeta sin lectura, o `null` si no hay nada que decir (no se está pidiendo
  /// ni falló: no pasa en la práctica, pero entonces queda solo el rótulo, como antes).
  static _LineaSinLectura? _lineaSinLectura(EstadoDeLaDeuda estado) {
    final fallo = estado.fallo;
    if (fallo != null) {
      final texto = fallo == FalloDeLaDeuda.sinConexion
          ? TextosDeuda.necesitasConexion
          : TextosDeuda.tarjetaNoDisponible;
      return _LineaSinLectura(
        hablado: texto,
        widget: Text(
          texto,
          key: const Key('cuenta_deuda_sin_lectura'),
          style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: ColoresCuenta.gris),
        ),
      );
    }
    if (estado.actualizando) {
      return const _LineaSinLectura(
        hablado: TextosDeuda.cargando,
        widget: Padding(
          padding: EdgeInsets.only(top: 6),
          child: ExcludeSemantics(
            child: DecoratedBox(
              key: Key('cuenta_deuda_cargando'),
              decoration: BoxDecoration(
                color: ColoresCuenta.esqueleto,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: SizedBox(width: 150, height: 14),
            ),
          ),
        ),
      );
    }
    return null;
  }

  static const _rojoFondo = Color(0xFFFBEDEC);
}

/// Lo que va bajo el rótulo cuando no hay lectura, y lo que dice el lector de pantalla.
final class _LineaSinLectura {
  const _LineaSinLectura({required this.hablado, required this.widget});

  final String hablado;
  final Widget widget;
}
