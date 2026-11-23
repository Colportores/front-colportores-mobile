import 'package:flutter/material.dart';

import '../../../catalogo/domain/entities/catalogo_local.dart' show CategoriaDeProducto;
import '../../../catalogo/presentation/formato_precios.dart';
import '../../../cuenta/presentation/widgets/piezas_cuenta.dart' show ColoresCuenta;
import '../../domain/entities/armado_del_pedido.dart';
import '../../domain/entities/pedido.dart';
import '../textos_pedidos.dart';

/// El encabezado de las pantallas de la vista 37: el rótulo de arriba («SOLICITAR PEDIDO», «MI CUENTA»), el
/// título y, si hay, la línea de abajo. [glifo] es el botón de la izquierda del canvas: «✕» al armar, «‹» en
/// las listas y detalles; sin él (37A·05) no hay botón.
class CabeceraDePedidos extends StatelessWidget {
  const CabeceraDePedidos({
    super.key,
    required this.eyebrow,
    required this.titulo,
    this.subtitulo,
    this.glifo,
    this.alVolver,
    this.tooltipDeVolver = TextosPedidos.volver,
  });

  final String eyebrow;
  final String titulo;
  final String? subtitulo;

  /// `'✕'` o `'‹'`; `null` = sin botón.
  final String? glifo;
  final VoidCallback? alVolver;
  final String tooltipDeVolver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (glifo != null)
                IconButton(
                  key: const Key('pedidos_volver'),
                  onPressed: alVolver,
                  tooltip: tooltipDeVolver,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(
                    glifo == '✕' ? Icons.close : Icons.chevron_left,
                    color: ColoresCuenta.navy,
                  ),
                )
              else
                const SizedBox(height: 48, width: 12),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    eyebrow,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 2,
                      color: ColoresCuenta.navy,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Semantics(
              header: true,
              child: Text(
                titulo,
                key: const Key('pedidos_titulo'),
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (subtitulo != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                subtitulo!,
                key: const Key('pedidos_subtitulo'),
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: ColoresCuenta.gris),
              ),
            ),
        ],
      ),
    );
  }
}

/// De qué clase es un [AvisoDePedido].
enum ClaseDeAviso {
  /// Pasa el límite (37A·02, 37B·02): ámbar, avisa y no bloquea.
  limite,

  /// Falló algo (37A·07, 37B·03, 37B·06): rojo.
  error,

  /// Sin conexión (37A·06): gris.
  sinConexion,
}

/// El aviso de color de la vista 37, con un botón opcional («Reintentar»). Un lector de pantalla lo anuncia
/// al aparecer.
class AvisoDePedido extends StatelessWidget {
  const AvisoDePedido({
    super.key,
    required this.clase,
    required this.texto,
    this.textoDelBoton,
    this.alTocarElBoton,
  });

  final ClaseDeAviso clase;
  final String texto;
  final String? textoDelBoton;
  final VoidCallback? alTocarElBoton;

  @override
  Widget build(BuildContext context) {
    final (color, fondo, glifo) = switch (clase) {
      ClaseDeAviso.limite => (ColoresCuenta.ambarTinta, ColoresCuenta.ambarFondo, '!'),
      ClaseDeAviso.error => (ColoresCuenta.rojo, Colors.white, '!'),
      ClaseDeAviso.sinConexion => (ColoresCuenta.gris, Colors.white, '✕'),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(14, 13, 14, textoDelBoton == null ? 13 : 4),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: clase == ClaseDeAviso.limite ? const Color(0xFFE0B43C) : color,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Text(
                      glifo,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    texto,
                    key: const Key('pedidos_aviso_texto'),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13.5,
                      height: 1.45,
                      color: ColoresCuenta.tinta,
                    ),
                  ),
                ),
              ],
            ),
            if (textoDelBoton != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('pedidos_aviso_boton'),
                  onPressed: alTocarElBoton,
                  style: TextButton.styleFrom(
                    foregroundColor: ColoresCuenta.azul,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(textoDelBoton!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un rótulo de sección en mayúsculas («QUÉ PEDÍS · PRECIO DE COMPRA», «TU SITUACIÓN»).
class RotuloDePedido extends StatelessWidget {
  const RotuloDePedido(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        texto,
        style: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10.5,
          letterSpacing: 1.6,
          color: ColoresCuenta.gris,
        ),
      ),
    );
  }
}

/// Las categorías del canvas como chips de 48 dp de alto, con las unidades que lleva cada una.
class ChipsDeCategoria extends StatelessWidget {
  const ChipsDeCategoria({
    super.key,
    required this.unidadesPorCategoria,
    required this.elegida,
    required this.alElegir,
  });

  final Map<CategoriaDelPedido, int> unidadesPorCategoria;
  final CategoriaDelPedido elegida;
  final ValueChanged<CategoriaDelPedido> alElegir;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in CategoriaDelPedido.values)
          Semantics(
            selected: c == elegida,
            button: true,
            child: ChoiceChip(
              key: Key('pedido_chip_${c.name}'),
              label: Text(TextosPedidos.chip(c, unidadesPorCategoria[c] ?? 0)),
              selected: c == elegida,
              onSelected: (_) => alElegir(c),
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: c == elegida ? Colors.white : ColoresCuenta.tinta,
              ),
              selectedColor: ColoresCuenta.navy,
              backgroundColor: Colors.white,
              side: const BorderSide(color: ColoresCuenta.borde, width: 1.5),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
      ],
    );
  }
}

/// Un producto del pedido con sus botones de menos y de más: el nombre, lo que tiene y cuánto cuesta, su
/// etiqueta y la cantidad que se pide.
class FilaDeProductoPedible extends StatelessWidget {
  const FilaDeProductoPedible({
    super.key,
    required this.producto,
    required this.cantidad,
    required this.alCambiar,
    this.habilitada = true,
  });

  final ProductoPedible producto;
  final int cantidad;
  final ValueChanged<int> alCambiar;

  /// Mientras se envía no se cambia nada.
  final bool habilitada;

  /// Lo más que cabe en una línea.
  static const maximo = 999;

  @override
  Widget build(BuildContext context) {
    final etiqueta = _etiquetaDe(producto);
    return Semantics(
      container: true,
      label: TextosPedidos.cantidadDe(producto.nombre, cantidad),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cantidad > 0 ? ColoresCuenta.navy : ColoresCuenta.borde,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ColoresCuenta.tinta,
                      ),
                    ),
                    Text(
                      TextosPedidos.tenesYPrecio(producto),
                      style: const TextStyle(fontSize: 12.5, color: ColoresCuenta.gris),
                    ),
                    if (etiqueta != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          etiqueta.texto,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ColoresCuenta.azul,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: Key('pedido_menos_${producto.id}'),
              onPressed: habilitada && cantidad > 0 ? () => alCambiar(cantidad - 1) : null,
              tooltip: TextosPedidos.quitar(producto.nombre),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.remove_circle_outline),
              color: ColoresCuenta.azul,
              disabledColor: ColoresCuenta.borde,
            ),
            SizedBox(
              width: 36,
              child: ExcludeSemantics(
                child: Text(
                  '$cantidad',
                  key: Key('pedido_cantidad_${producto.id}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              key: Key('pedido_mas_${producto.id}'),
              onPressed: habilitada && cantidad < maximo ? () => alCambiar(cantidad + 1) : null,
              tooltip: TextosPedidos.sumar(producto.nombre),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.add_circle_outline),
              color: ColoresCuenta.azul,
              disabledColor: ColoresCuenta.borde,
            ),
          ],
        ),
      ),
    );
  }

  /// La etiqueta de la categoría (misioneros, revistas, espirituales) y, si no, «◆ Bonificable» si cuenta
  /// para la beca (la misma regla que Precios).
  static EtiquetaDeProducto? _etiquetaDe(ProductoPedible p) => switch (p.categoriaDelCatalogo) {
    CategoriaDeProducto.misioneros => EtiquetaDeProducto.misionero,
    CategoriaDeProducto.revistas => EtiquetaDeProducto.revista,
    CategoriaDeProducto.bonificables => EtiquetaDeProducto.bonificable,
    CategoriaDeProducto.espirituales =>
      p.esBonificable ? EtiquetaDeProducto.bonificable : EtiquetaDeProducto.espiritual,
    CategoriaDeProducto.material || CategoriaDeProducto.otra => null,
  };
}

/// Una fila «rótulo — valor» de la situación o del detalle. Con [enfasis] el valor va en negrita (y en rojo
/// con [enRojo]).
class FilaDeDato extends StatelessWidget {
  const FilaDeDato({
    super.key,
    required this.rotulo,
    required this.valor,
    this.enfasis = false,
    this.enRojo = false,
    this.mono = true,
  });

  final String rotulo;
  final String valor;
  final bool enfasis;
  final bool enRojo;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final peso = enfasis ? FontWeight.w600 : FontWeight.w400;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                rotulo,
                style: TextStyle(fontSize: 14.5, fontWeight: peso, color: ColoresCuenta.tinta),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valor,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: mono ? 'JetBrainsMono' : 'Inter',
                  fontSize: 14.5,
                  fontWeight: peso,
                  color: enRojo ? ColoresCuenta.rojo : ColoresCuenta.tinta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El cuadro blanco con borde donde van las filas de datos.
class CuadroDeDatos extends StatelessWidget {
  const CuadroDeDatos({super.key, required this.hijos});

  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresCuenta.borde, width: 1.5),
      ),
      child: Column(children: hijos),
    );
  }
}

/// El botón grande de abajo: lleno (el principal) o con borde (el secundario, en rojo si [peligro]). Con
/// [ocupado] dice qué está haciendo y se apaga: no se toca dos veces.
class BotonDePedido extends StatelessWidget {
  const BotonDePedido({
    super.key,
    required this.texto,
    required this.alTocar,
    this.ocupado = false,
    this.secundario = false,
    this.peligro = false,
  });

  final String texto;

  /// `null` = apagado.
  final VoidCallback? alTocar;
  final bool ocupado;
  final bool secundario;
  final bool peligro;

  @override
  Widget build(BuildContext context) {
    final enabled = alTocar != null && !ocupado;
    final color = peligro ? ColoresCuenta.rojo : ColoresCuenta.navy;
    final hijo = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ocupado) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: secundario ? color : Colors.white,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(child: Text(texto, textAlign: TextAlign.center)),
      ],
    );
    const forma = StadiumBorder();
    const texto0 = TextStyle(fontFamily: 'Inter', fontSize: 15.5, fontWeight: FontWeight.w600);
    if (secundario) {
      return OutlinedButton(
        key: const Key('pedidos_boton_secundario'),
        onPressed: enabled ? alTocar : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: color,
          disabledForegroundColor: ColoresCuenta.gris,
          backgroundColor: Colors.white,
          side: BorderSide(color: enabled || ocupado ? color : ColoresCuenta.borde, width: 1.5),
          shape: forma,
          textStyle: texto0,
        ),
        child: hijo,
      );
    }
    return FilledButton(
      key: const Key('pedidos_boton_principal'),
      onPressed: enabled ? alTocar : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: color,
        foregroundColor: Colors.white,
        // Un botón apagado de Material pinta `onSurface` al 38 %: ilegible sobre azul. Apagado es gris legible.
        disabledBackgroundColor: ocupado ? color : ColoresCuenta.grisFondo,
        disabledForegroundColor: ocupado ? Colors.white : ColoresCuenta.gris,
        shape: forma,
        textStyle: texto0,
      ),
      child: hijo,
    );
  }
}

/// Un mensaje grande al centro con su glifo (el éxito de 37A·05 y el «Todavía no pediste nada» de 37B·04).
class HeroDePedido extends StatelessWidget {
  const HeroDePedido({
    super.key,
    required this.glifo,
    required this.titulo,
    required this.texto,
    this.fondo = ColoresCuenta.grisFondo,
    this.tinta = ColoresCuenta.gris,
  });

  final String glifo;
  final String titulo;
  final String texto;
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Semantics(
        container: true,
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: fondo, shape: BoxShape.circle),
                child: Text(
                  glifo,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 28, color: tinta, height: 1),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: ColoresCuenta.gris),
            ),
          ],
        ),
      ),
    );
  }
}

/// La tarjeta de un pedido en «Mis pedidos» (37B·01): su estado, la fecha, el monto y cuántos productos.
class TarjetaDePedido extends StatelessWidget {
  const TarjetaDePedido({
    super.key,
    required this.pedido,
    required this.ahora,
    required this.alAbrir,
  });

  final Pedido pedido;
  final DateTime ahora;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    final (glifo, fondo, tinta) = switch (pedido.estado) {
      EstadoDelPedido.porAutorizar => ('◷', ColoresCuenta.ambarFondo, ColoresCuenta.ambarTinta),
      EstadoDelPedido.autorizado ||
      EstadoDelPedido.despachado => ('⇢', ColoresCuenta.azulFondo, ColoresCuenta.azul),
      EstadoDelPedido.recibido => ('✓', ColoresCuenta.verdeFondo, ColoresCuenta.verde),
      EstadoDelPedido.rechazado => ('!', Colors.white, ColoresCuenta.rojo),
      EstadoDelPedido.cancelado => ('✕', ColoresCuenta.grisFondo, ColoresCuenta.gris),
    };
    final fecha = TextosPedidos.fechaCorta(pedido.fecha, ahora);
    final monto = FormatoPrecios.monto(pedido.montoVigenteCentavos);
    final estado = TextosPedidos.estado(pedido.estado);
    final productos = TextosPedidos.productos(pedido.unidades);
    return Semantics(
      button: true,
      container: true,
      label: '$estado, ${fecha == 'HOY' ? 'hoy' : fecha}, $monto, $productos',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresCuenta.borde, width: 1.5),
        ),
        child: InkWell(
          key: Key('pedido_${pedido.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: alAbrir,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: fondo,
                        borderRadius: BorderRadius.circular(10),
                        border: pedido.estado == EstadoDelPedido.rechazado
                            ? Border.all(color: tinta, width: 1.5)
                            : null,
                      ),
                      child: Text(
                        glifo,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: 18, color: tinta, height: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$fecha · $monto',
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            productos,
                            style: const TextStyle(fontSize: 12.5, color: ColoresCuenta.gris),
                          ),
                          Text(
                            estado,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: tinta,
                            ),
                          ),
                        ],
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

/// La carga de «Mis pedidos» (37B·05): un bloque gris por parte. Un lector de pantalla lee que está cargando.
class EsqueletoDePedidos extends StatelessWidget {
  const EsqueletoDePedidos({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto) => Container(
      height: alto,
      decoration: BoxDecoration(
        color: ColoresCuenta.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      label: TextosPedidos.cargando,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          key: const Key('pedidos_esqueleto'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(spacing: 8, children: [bloque(40), bloque(72), bloque(72)]),
        ),
      ),
    );
  }
}

/// El marco de las pantallas de la vista 37: el encabezado, el cuerpo y, al pie, el botón. **Todo se
/// desplaza junto**: con el texto al 200 % en un teléfono chico el encabezado y el cuerpo ocupan casi toda la
/// pantalla, y un botón fijo abajo le dejaría al cuerpo menos que nada. Con poco contenido, el botón queda
/// pegado al pie.
class PaginaDePedidos extends StatelessWidget {
  const PaginaDePedidos({
    super.key,
    required this.clave,
    required this.encabezado,
    required this.cuerpo,
    this.pie,
    this.controlador,
  });

  /// Para llevar la pantalla arriba cuando cambia lo que hay que ver (el éxito o el error de un envío).
  final ScrollController? controlador;

  /// La clave del desplazable (los tests la usan para llegar al final).
  final Key clave;
  final Widget encabezado;
  final Widget cuerpo;

  /// El botón (o la nota y el botón) de abajo; `null` = sin pie.
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          key: clave,
          controller: controlador,
          slivers: [
            SliverToBoxAdapter(child: encabezado),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cuerpo,
                  const Spacer(),
                  if (pie != null)
                    Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), child: pie),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
