import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';

/// Los colores de la lista (vista 05) que el tema no cubre. Los demás salen de `Theme.of(context)`.
abstract final class ColoresLista {
  static const grisEstado = Color(0xFF6B7688);
  static const ambar = Color(0xFFE0B43C);
  static const tinta = Color(0xFF0E1A2B);
  static const verde = Color(0xFF1F6E3A);
  static const azul = Color(0xFF13407A);
  static const azulClaro = Color(0xFF5C82B8);
  static const rojo = Color(0xFFA8312A);
  static const azulFondo = Color(0xFFE6EEF8);
  static const grisBorde = Color(0xFFCFD6E1);
  static const filaBaja = Color(0xFFF3F1EA);
  static const grisTexto = Color(0xFF2A3A52);
  static const chevron = Color(0xFF90A0B7);
}

/// √2, para el período de las franjas a 135° de «Entrega y pago».
const _raiz2 = 1.4142135623730951;

/// `true` si el texto está agrandado lo suficiente para que la fila apile la distancia debajo.
bool textoGrande(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) > 13;

/// La insignia del estado de la casa: círculo para los de la visita y cuadrado redondeado para los
/// de la venta (canvas, «Círculo: estados de la visita. Cuadrado: estados de la venta»). Con un
/// rótulo para el lector de pantalla; el glifo no crece con el texto: el significado lo lleva el
/// rótulo y la segunda línea de la fila.
class InsigniaEstadoCasa extends StatelessWidget {
  const InsigniaEstadoCasa({super.key, required this.estado, this.tamano = 30});

  final EstadoCasa estado;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final esGrande = tamano >= 26;
    final glifo = FormatoListaUbicaciones.glifo(estado);
    final forma = estado.esDeVenta
        ? BorderRadius.circular(esGrande ? 8 : 5)
        : BorderRadius.circular(tamano);
    final (Color fondo, Color tinta, Border? borde, Gradient? degradado) = switch (estado) {
      EstadoCasa.sinVisita => (
        Colors.white,
        ColoresLista.grisEstado,
        Border.all(color: ColoresLista.grisEstado, width: 2.5),
        null,
      ),
      EstadoCasa.noContesto => (ColoresLista.grisEstado, Colors.white, null, null),
      EstadoCasa.entrevistaAgendada => (ColoresLista.ambar, ColoresLista.tinta, null, null),
      EstadoCasa.entrevistaHecha => (ColoresLista.verde, Colors.white, null, null),
      EstadoCasa.ventaCompleta => (ColoresLista.verde, Colors.white, null, null),
      EstadoCasa.cobranzaPendiente => (ColoresLista.azul, Colors.white, null, null),
      EstadoCasa.entregaYPago => (
        ColoresLista.azul,
        Colors.white,
        null,
        // Franjas a 135°: 4 px de azul y 3 de azul claro (canvas, «Entrega y pago»).
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-1 + 2 * (7 / _raiz2) / tamano, -1 + 2 * (7 / _raiz2) / tamano),
          tileMode: TileMode.repeated,
          colors: const [
            ColoresLista.azul,
            ColoresLista.azul,
            ColoresLista.azulClaro,
            ColoresLista.azulClaro,
          ],
          stops: const [0, 4 / 7, 4 / 7, 1],
        ),
      ),
      EstadoCasa.rechazo => (ColoresLista.rojo, Colors.white, null, null),
    };
    return Semantics(
      image: true,
      label: FormatoListaUbicaciones.estado(estado),
      child: ExcludeSemantics(
        child: Container(
          width: tamano,
          height: tamano,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: degradado == null ? fondo : null,
            gradient: degradado,
            border: borde,
            borderRadius: forma,
          ),
          child: glifo.isEmpty
              ? null
              : Text(
                  glifo,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: tinta,
                    fontSize: esGrande ? 15 : 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Lo que va en el lugar de la insignia cuando todavía no se sabe el estado de la casa (no hay
/// `house_status` local): un círculo neutro con el ícono del tipo. No dice «Sin visita»: no se sabe.
class InsigniaTipoUbicacion extends StatelessWidget {
  const InsigniaTipoUbicacion({super.key, required this.tipo});

  final TipoUbicacion tipo;

  @override
  Widget build(BuildContext context) {
    final icono = switch (tipo) {
      TipoUbicacion.casa => Icons.home_outlined,
      TipoUbicacion.negocio => Icons.storefront_outlined,
      TipoUbicacion.edificio => Icons.apartment_outlined,
    };
    return ExcludeSemantics(
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ColoresLista.azulFondo,
          border: Border.all(color: ColoresLista.grisBorde, width: 1.5),
        ),
        child: Icon(icono, size: 17, color: ColoresLista.grisTexto),
      ),
    );
  }
}

/// El círculo punteado de una ubicación dada de baja (canvas: «un círculo punteado en lugar del
/// ícono»).
class InsigniaBaja extends StatelessWidget {
  const InsigniaBaja({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: SizedBox(
        width: 30,
        height: 30,
        child: CustomPaint(painter: _CirculoPunteado(color: Color(0xFF5B6B82))),
      ),
    );
  }
}

class _CirculoPunteado extends CustomPainter {
  const _CirculoPunteado({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const grosor = 1.5;
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;
    final ruta = Path()..addOval((Offset.zero & size).deflate(grosor / 2));
    for (final tramo in ruta.computeMetrics()) {
      for (var d = 0.0; d < tramo.length; d += 6) {
        canvas.drawPath(
          tramo.extractPath(d, d + 3.5 > tramo.length ? tramo.length : d + 3.5),
          pincel,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CirculoPunteado viejo) => viejo.color != color;
}

/// Una fila de la lista (canvas, 05B): la insignia del estado, la dirección, la segunda línea y a
/// la derecha la distancia o la última actualización. Una baja lleva «BAJA», el círculo punteado,
/// fondo tostado y ni flecha ni toque.
class FilaUbicacionLista extends StatelessWidget {
  const FilaUbicacionLista({
    super.key,
    required this.item,
    required this.lista,
    required this.ahora,
    this.alTocar,
  });

  final ItemListaUbicacion item;
  final ListaUbicaciones lista;
  final DateTime ahora;

  /// `null`: la fila no se puede tocar (todavía no hay a dónde ir, o es una baja).
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const colores = ColoresColportaje.unica;
    final esBaja = item.esBaja;
    final tocable = item.esInteractiva && alTocar != null;
    final apilada = textoGrande(context);
    final derecha = FormatoListaUbicaciones.derecha(item, lista, ahora);

    final textoDerecha = Text(
      derecha,
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 12,
        color: esBaja ? colores.gris : ColoresLista.grisTexto,
      ),
    );

    final cuerpo = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (esBaja)
          const InsigniaBaja()
        else if (item.estado != null)
          InsigniaEstadoCasa(estado: item.estado!)
        else
          InsigniaTipoUbicacion(tipo: item.ubicacion.tipo),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    FormatoUbicaciones.direccion(item.ubicacion),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: esBaja ? ColoresLista.grisTexto : null,
                    ),
                  ),
                  if (esBaja) const _EtiquetaBaja(),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                FormatoListaUbicaciones.meta(item, ahora),
                style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: colores.gris),
              ),
              if (apilada) ...[const SizedBox(height: 3), textoDerecha],
            ],
          ),
        ),
        if (!apilada) ...[const SizedBox(width: 12), textoDerecha],
        // En el canvas la «›» quiere decir «se abre»: sin destino (o en una baja) no se muestra.
        if (tocable) ...[
          const SizedBox(width: 12),
          const ExcludeSemantics(
            child: Text('›', style: TextStyle(color: ColoresLista.chevron, fontSize: 18)),
          ),
        ],
      ],
    );

    final fila = Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: esBaja ? ColoresLista.filaBaja : Colors.white,
        border: Border(bottom: BorderSide(color: colores.borde)),
      ),
      child: cuerpo,
    );

    return Semantics(
      container: true,
      button: tocable,
      enabled: !esBaja,
      label: FormatoListaUbicaciones.etiquetaFila(item, lista, ahora),
      onTap: tocable ? alTocar : null,
      child: ExcludeSemantics(
        child: tocable ? InkWell(onTap: alTocar, child: fila) : fila,
      ),
    );
  }
}

class _EtiquetaBaja extends StatelessWidget {
  const _EtiquetaBaja();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ColoresColportaje.unica.gris,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'BAJA',
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          letterSpacing: 1,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// El botón «☷ Filtros» con el número de filtros activos.
class BotonFiltrosLista extends StatelessWidget {
  const BotonFiltrosLista({super.key, required this.cantidad, required this.alPresionar});

  final int cantidad;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: cantidad == 0 ? 'Filtros' : 'Filtros, $cantidad activos',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: navy, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '☷ Filtros',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: navy,
                      ),
                    ),
                    if (cantidad > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: navy,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$cantidad',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
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

/// Un filtro activo, como chip con «✕»: un toque lo quita (canvas: «Quitar filtro»). El chip mide
/// 36 de alto y el área táctil 48.
class ChipFiltroLista extends StatelessWidget {
  const ChipFiltroLista({super.key, required this.texto, required this.alQuitar});

  final String texto;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: '$texto. Quitar filtro',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alQuitar,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: ColoresLista.azulFondo,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      texto,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: navy,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text('✕', style: TextStyle(fontSize: 12, color: navy)),
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
