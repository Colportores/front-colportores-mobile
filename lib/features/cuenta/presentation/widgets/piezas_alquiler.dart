import 'package:flutter/material.dart';

import '../../../ventas/presentation/widgets/piezas_venta.dart' show BotonDeVenta;
import '../../domain/entities/alquiler.dart';
import '../textos_alquiler.dart';
import '../textos_cuenta.dart' show FormatoCuenta;
import 'piezas_cuenta.dart';

// Las piezas de «Mi alquiler» (vista 38C, HU-CTA-007). Todas crecen con el texto (`textScaler` 2.0):
// nada tiene alto fijo salvo el mínimo táctil de 48.

/// El encabezado de «Mi alquiler»: «‹ MI CUENTA» y «Alquiler» (38C).
class CabeceraAlquiler extends StatelessWidget {
  const CabeceraAlquiler({super.key, required this.alVolver});

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
                key: const Key('alquiler_volver'),
                onPressed: alVolver,
                tooltip: TextosAlquiler.volver,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.chevron_left, color: ColoresCuenta.navy),
              ),
              const Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    TextosAlquiler.eyebrow,
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
                TextosAlquiler.titulo,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 26,
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

/// La línea de Mi Cuenta que lleva a «Mi alquiler» (33A·01, la lista de enlaces): «Alquiler» y lo que
/// falta pagar entre todas las campañas. Solo se dibuja si alguna campaña cobra alquiler.
class FilaDeAlquilerEnCuenta extends StatelessWidget {
  const FilaDeAlquilerEnCuenta({super.key, required this.alquiler, required this.alAbrir});

  final AlquilerDelColportor alquiler;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    final debe = alquiler.saldoCentavos > 0;
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: FormatoAlquiler.filaHablada(alquiler),
      onTap: alAbrir,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresCuenta.borde),
        ),
        child: InkWell(
          key: const Key('cuenta_fila_alquiler'),
          borderRadius: BorderRadius.circular(14),
          onTap: alAbrir,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                const Expanded(
                  child: Text(
                    TextosAlquiler.filaDeCuenta,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14.5,
                      color: ColoresCuenta.gris,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    TextosAlquiler.resumenDeLaFila(alquiler),
                    key: const Key('cuenta_fila_alquiler_valor'),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: debe ? ColoresCuenta.tinta : ColoresCuenta.verde,
                    ),
                  ),
                ),
                const ExcludeSemantics(
                  child: Text('›', style: TextStyle(fontSize: 18, color: ColoresCuenta.gris)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El alquiler de UNA campaña (38C·01, 02, 03 y 05): lo que falta pagar, el monto, lo pagado, los
/// avisos, los pagos y «Cargar pago de alquiler».
///
/// [alCargarPago] es `null` mientras ya se está abriendo «Registrar depósito» (un segundo toque no abre
/// otra encima). Sin saldo, el botón no se dibuja (38C·03).
class BloqueDeAlquiler extends StatelessWidget {
  const BloqueDeAlquiler({
    super.key,
    required this.alquiler,
    required this.ahora,
    required this.alCargarPago,
    required this.indice,
    this.conSeparador = false,
  });

  final AlquilerDeCampania alquiler;
  final DateTime ahora;
  final VoidCallback? alCargarPago;

  /// La posición del bloque en la pantalla: parte de las claves.
  final int indice;

  /// Una línea entre campañas.
  final bool conSeparador;

  @override
  Widget build(BuildContext context) {
    final saldo = alquiler.saldoCentavos;
    final porValidar = alquiler.porValidarCentavos;
    return Padding(
      key: Key('alquiler_bloque_$indice'),
      padding: EdgeInsets.fromLTRB(20, conSeparador ? 20 : 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (conSeparador) const Divider(height: 1, color: ColoresCuenta.borde),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 4),
              child: Text(
                TextosAlquiler.subtitulo(alquiler.campania),
                key: Key('alquiler_subtitulo_$indice'),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  color: ColoresCuenta.gris,
                ),
              ),
            ),
          ),
          if (porValidar > 0)
            AvisoInformativoAlquiler(
              key: Key('alquiler_por_validar_$indice'),
              texto: TextosAlquiler.porValidar(porValidar),
            ),
          _TeFaltaPagar(indice: indice, centavos: saldo),
          _FilasDeMontos(
            indice: indice,
            monto: alquiler.montoCentavos,
            pagado: alquiler.pagadoCentavos,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              TextosAlquiler.noBloquea,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.45,
                color: ColoresCuenta.gris,
              ),
            ),
          ),
          if (alquiler.pagos.isNotEmpty) ...[
            const _RotuloDePagos(),
            for (var i = 0; i < alquiler.pagos.length; i++)
              TarjetaDePagoDeAlquiler(
                key: Key('alquiler_pago_${indice}_$i'),
                pago: alquiler.pagos[i],
                ahora: ahora,
              ),
          ],
          if (saldo > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: BotonDeVenta(
                key: Key('alquiler_cargar_pago_$indice'),
                texto: TextosAlquiler.cargarPago,
                alPresionar: alCargarPago,
              ),
            ),
        ],
      ),
    );
  }
}

/// «TE FALTA PAGAR» y la cifra: en verde cuando ya no falta nada (38C·03).
class _TeFaltaPagar extends StatelessWidget {
  const _TeFaltaPagar({required this.indice, required this.centavos});

  final int indice;
  final int centavos;

  @override
  Widget build(BuildContext context) {
    final monto = FormatoCuenta.monto(centavos);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: '${TextosAlquiler.teFaltaPagar.toLowerCase()}, $monto',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            const Text(
              TextosAlquiler.teFaltaPagar,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                color: ColoresCuenta.gris,
              ),
            ),
            // Con el texto al 200 % un monto largo se achica antes que cortarse o saltar de renglón.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                monto,
                key: Key('alquiler_te_falta_$indice'),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  color: centavos == 0 ? ColoresCuenta.verde : ColoresCuenta.tinta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Alquiler de la campaña» y «Pagado (validado)», con sus montos.
class _FilasDeMontos extends StatelessWidget {
  const _FilasDeMontos({required this.indice, required this.monto, required this.pagado});

  final int indice;
  final int monto;
  final int pagado;

  @override
  Widget build(BuildContext context) {
    Widget fila(String clave, String rotulo, int centavos) {
      final texto = FormatoCuenta.monto(centavos);
      return Semantics(
        container: true,
        excludeSemantics: true,
        label: '$rotulo, $texto',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                rotulo,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14.5,
                  color: ColoresCuenta.gris,
                ),
              ),
              Text(
                texto,
                key: Key(clave),
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ColoresCuenta.tinta,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresCuenta.borde),
      ),
      child: Column(
        children: [
          fila('alquiler_monto_$indice', TextosAlquiler.alquilerDeLaCampania, monto),
          const Divider(height: 1, color: ColoresCuenta.borde),
          fila('alquiler_pagado_$indice', TextosAlquiler.pagadoValidado, pagado),
        ],
      ),
    );
  }
}

/// El rótulo «PAGOS».
class _RotuloDePagos extends StatelessWidget {
  const _RotuloDePagos();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Text(
        TextosAlquiler.pagos,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          letterSpacing: 1.4,
          color: ColoresCuenta.gris,
        ),
      ),
    );
  }
}

/// Un pago de la lista (38C·01): cuándo y dónde, cuánto, en qué estado y qué significa. No se toca.
class TarjetaDePagoDeAlquiler extends StatelessWidget {
  const TarjetaDePagoDeAlquiler({super.key, required this.pago, required this.ahora});

  final PagoDeAlquiler pago;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final (glifo, fondo, tinta) = switch (pago.estado) {
      EstadoDePagoDeAlquiler.porValidar => (
        '◷',
        ColoresCuenta.ambarFondo,
        ColoresCuenta.ambarTinta,
      ),
      EstadoDePagoDeAlquiler.validado => ('✓', ColoresCuenta.verdeFondo, ColoresCuenta.verde),
      EstadoDePagoDeAlquiler.rechazado => ('!', const Color(0xFFFBEDEC), ColoresCuenta.rojo),
      EstadoDePagoDeAlquiler.devuelto => ('↩', ColoresCuenta.grisFondo, ColoresCuenta.gris),
    };
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: FormatoAlquiler.pagoHablado(pago, ahora),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresCuenta.borde),
        ),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
              child: Text(
                glifo,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: tinta,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    FormatoAlquiler.rotuloDelPago(pago, ahora),
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      letterSpacing: 0.44,
                      color: ColoresCuenta.gris,
                    ),
                  ),
                  // El monto y la etiqueta del estado van juntos y se parten en renglones si no
                  // entran (texto al 200 %), nunca fuera de la tarjeta.
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        FormatoCuenta.monto(pago.montoCentavos),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ColoresCuenta.tinta,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: fondo,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          FormatoAlquiler.tag(pago.estado),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: tinta,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    FormatoAlquiler.explicacion(pago),
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

/// Un aviso que informa sin frenar (38C·02: «Tenés $ 6.000 por validar…»): fondo azul claro, o verde si
/// es una buena noticia (lo pagado de más bajó la deuda con la casa editora).
class AvisoInformativoAlquiler extends StatelessWidget {
  const AvisoInformativoAlquiler({super.key, required this.texto, this.exito = false});

  final String texto;
  final bool exito;

  @override
  Widget build(BuildContext context) {
    final tinta = exito ? ColoresCuenta.verde : ColoresCuenta.azul;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: exito ? ColoresCuenta.verdeFondo : ColoresCuenta.azulFondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tinta, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tinta, shape: BoxShape.circle),
                child: Text(
                  exito ? '✓' : 'i',
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Esta campaña no cobra alquiler» (38C·04).
class SinAlquiler extends StatelessWidget {
  const SinAlquiler({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 10),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: TextosAlquiler.sinAlquiler,
        child: const Column(
          spacing: 12,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: ColoresCuenta.grisFondo, shape: BoxShape.circle),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Text(
                    '⌂',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 28, color: ColoresCuenta.gris),
                  ),
                ),
              ),
            ),
            Text(
              TextosAlquiler.sinAlquiler,
              key: Key('alquiler_sin_alquiler'),
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

/// La carga: el total y dos bloques grises (el mismo lenguaje que 33A·03).
class EsqueletoAlquiler extends StatelessWidget {
  const EsqueletoAlquiler({super.key});

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
      label: TextosAlquiler.cargando,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              bloque('alquiler_esqueleto_total', 64),
              bloque('alquiler_esqueleto_montos', 74),
              bloque('alquiler_esqueleto_pago', 74),
            ],
          ),
        ),
      ),
    );
  }
}
