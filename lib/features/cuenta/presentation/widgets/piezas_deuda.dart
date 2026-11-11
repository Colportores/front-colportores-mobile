import 'package:flutter/material.dart';

import '../../domain/entities/deuda_con_la_casa.dart';
import '../textos_deuda.dart';
import 'piezas_cuenta.dart';

/// El encabezado de la deuda con la casa editora: «‹ MI CUENTA» y el título (33B).
class CabeceraDeuda extends StatelessWidget {
  const CabeceraDeuda({super.key, required this.alVolver});

  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('deuda_volver'),
                onPressed: alVolver,
                tooltip: TextosDeuda.volver,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.chevron_left, color: ColoresCuenta.navy),
              ),
              const Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    TextosDeuda.eyebrow,
                    style: TextStyle(
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
              child: const Text(
                TextosDeuda.titulo,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El total de arriba (33B·01): en rojo si se debe, en verde si quedó a favor y con la tinta normal en
/// cero. Si quedó a favor, dice qué pasa con eso.
class TotalDeLaDeuda extends StatelessWidget {
  const TotalDeLaDeuda({super.key, required this.deuda});

  final DeudaConLaCasa deuda;

  @override
  Widget build(BuildContext context) {
    final color = deuda.aFavor
        ? ColoresCuenta.verde
        : deuda.deudaTotalCentavos > 0
        ? ColoresCuenta.rojo
        : ColoresCuenta.tinta;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 4),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label:
            '${FormatoDeuda.totalHablado(deuda)}.'
            '${deuda.aFavor ? ' ${TextosDeuda.aFavorExplica}' : ''}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            const Text(
              TextosDeuda.total,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                color: ColoresCuenta.gris,
              ),
            ),
            // Con el texto al 200 % un monto largo no entra en una línea: se achica antes que
            // cortarse o saltar de renglón.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                FormatoDeuda.total(deuda),
                key: const Key('deuda_total'),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (deuda.aFavor)
              const Text(
                TextosDeuda.aFavorExplica,
                key: Key('deuda_a_favor_explica'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF2A3A52),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El rótulo de una sección (33B·01: «PEDIDOS CON SALDO»).
class RotuloDeSeccionDeuda extends StatelessWidget {
  const RotuloDeSeccionDeuda({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 4),
      child: Semantics(
        header: true,
        child: Text(
          texto,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 1.4,
            color: ColoresCuenta.gris,
          ),
        ),
      ),
    );
  }
}

/// Un pedido con saldo (33B·01): su fecha, lo que falta, qué libros eran y cuánto valió y cuánto se
/// pagó. No se toca: no lleva a ningún lado.
class TarjetaDePedidoConSaldo extends StatelessWidget {
  const TarjetaDePedidoConSaldo({super.key, required this.pedido});

  final PedidoConSaldo pedido;

  @override
  Widget build(BuildContext context) {
    final productos = FormatoDeuda.productos(pedido);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: FormatoDeuda.pedidoHablado(pedido),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresCuenta.borde),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 12,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ColoresCuenta.azulFondo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '▤',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: ColoresCuenta.navy,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    FormatoDeuda.rotuloDelPedido(pedido),
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      letterSpacing: 0.44,
                      color: ColoresCuenta.gris,
                    ),
                  ),
                  Text(
                    FormatoDeuda.saldo(pedido),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ColoresCuenta.tinta,
                    ),
                  ),
                  if (productos.isNotEmpty)
                    Text(
                      productos,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF2A3A52),
                      ),
                    ),
                  Text(
                    FormatoDeuda.montoYPagado(pedido),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      height: 1.4,
                      color: ColoresCuenta.gris,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «No le debés nada a la casa editora» (33B·02).
class SinDeudaConLaCasa extends StatelessWidget {
  const SinDeudaConLaCasa({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: TextosDeuda.sinDeuda,
        child: const Column(
          spacing: 12,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: ColoresCuenta.verdeFondo, shape: BoxShape.circle),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Text(
                    '✓',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: ColoresCuenta.verde,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              TextosDeuda.sinDeuda,
              key: Key('deuda_sin_deuda'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que aclara la pantalla cuando los saldos de los pedidos no dan el total.
class NotaDeLaDeuda extends StatelessWidget {
  const NotaDeLaDeuda({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 0),
      child: Semantics(
        container: true,
        child: Text(
          texto,
          key: const Key('deuda_nota'),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            height: 1.45,
            color: ColoresCuenta.gris,
          ),
        ),
      ),
    );
  }
}

/// La carga (33A·03 aplicado a 33B): el total y dos pedidos como bloques grises.
class EsqueletoDeuda extends StatelessWidget {
  const EsqueletoDeuda({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(String clave, double alto) => Container(
      key: Key(clave),
      height: alto,
      decoration: BoxDecoration(
        color: ColoresCuenta.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosDeuda.cargando,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              bloque('deuda_esqueleto_total', 64),
              bloque('deuda_esqueleto_pedido_1', 74),
              bloque('deuda_esqueleto_pedido_2', 74),
            ],
          ),
        ),
      ),
    );
  }
}
