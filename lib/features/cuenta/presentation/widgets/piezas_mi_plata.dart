import 'package:flutter/material.dart';

import '../../../depositos/domain/entities/deposito.dart';
import '../../../depositos/domain/entities/totales_de_depositos.dart';
import '../../domain/entities/detalle_de_mi_plata.dart';
import '../textos_cuenta.dart';
import 'piezas_cuenta.dart';

/// Las categorías de «Mi plata» (vista 33C): su rótulo, su glifo, sus colores y qué dice si no hay
/// nada.
enum CategoriaDeMiPlata {
  depositado(
    rotulo: TextosMiPlata.depositado,
    glifo: '⇣',
    fondo: ColoresCuenta.verdeFondo,
    tinta: ColoresCuenta.verde,
    sinNada: TextosMiPlata.sinDepositos,
  ),
  enMano(
    rotulo: TextosMiPlata.enMano,
    glifo: r'$',
    fondo: ColoresCuenta.ambarFondo,
    tinta: ColoresCuenta.ambarTinta,
    sinNada: TextosMiPlata.sinEfectivoEnMano,
  ),
  porCobrar(
    rotulo: TextosMiPlata.porCobrar,
    glifo: '◷',
    fondo: ColoresCuenta.azulFondo,
    tinta: ColoresCuenta.azul,
    sinNada: TextosMiPlata.sinPorCobrar,
  );

  const CategoriaDeMiPlata({
    required this.rotulo,
    required this.glifo,
    required this.fondo,
    required this.tinta,
    required this.sinNada,
  });

  final String rotulo;
  final String glifo;
  final Color fondo;
  final Color tinta;

  /// Lo que dice la categoría abierta cuando no tiene filas (33C·03).
  final String sinNada;

  /// La categoría de la tarjeta de Mi Cuenta que se tocó.
  static CategoriaDeMiPlata de(TipoDeCifra tipo) => switch (tipo) {
    TipoDeCifra.depositado => depositado,
    TipoDeCifra.enMano => enMano,
    TipoDeCifra.porCobrar => porCobrar,
  };
}

/// El encabezado de «Mi plata»: «‹ MI CUENTA» y «Mi plata» (33C).
class CabeceraMiPlata extends StatelessWidget {
  const CabeceraMiPlata({super.key, required this.alVolver});

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
                key: const Key('mi_plata_volver'),
                onPressed: alVolver,
                tooltip: TextosMiPlata.volver,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.chevron_left, color: ColoresCuenta.navy),
              ),
              const Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    TextosMiPlata.eyebrow,
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
                TextosMiPlata.titulo,
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

/// Una categoría que se despliega: su glifo, el nombre y el total con `▴` / `▾` (33C·01, 33C·02).
class CategoriaDesplegable extends StatelessWidget {
  const CategoriaDesplegable({
    super.key,
    required this.categoria,
    required this.centavos,
    required this.abierta,
    required this.alTocar,
  });

  final CategoriaDeMiPlata categoria;
  final int centavos;
  final bool abierta;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final monto = FormatoCuenta.monto(centavos);
    final sinNada = centavos == 0;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      expanded: abierta,
      onTap: alTocar,
      label:
          '${categoria.rotulo}, $monto, '
          '${abierta ? TextosMiPlata.desplegado : TextosMiPlata.plegado}',
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: abierta ? ColoresCuenta.azul : ColoresCuenta.borde,
            width: abierta ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: alTocar,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sinNada ? ColoresCuenta.grisFondo : categoria.fondo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    categoria.glifo,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: sinNada ? ColoresCuenta.gris : categoria.tinta,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        categoria.rotulo,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$monto  ${abierta ? '▴' : '▾'}',
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 14,
                          color: ColoresCuenta.tinta,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila del detalle: quién y cuándo a la izquierda, cuánto a la derecha. Con el texto grande el
/// monto baja a la línea siguiente en vez de apretar el nombre.
class FilaDeMiPlata extends StatelessWidget {
  const FilaDeMiPlata({
    super.key,
    required this.detalle,
    required this.monto,
    this.apagada = false,
    this.baja = false,
  });

  /// «María Fernández · 20/10».
  final String detalle;

  /// Ya escrito: «$ 1.200».
  final String monto;

  /// Todavía no cuenta (un depósito por validar): el monto va en gris.
  final bool apagada;

  /// Es plata que baja lo que hay (un depósito en «En mano»): el monto va en el color de la baja.
  final bool baja;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$detalle, $monto',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: ColoresCuenta.borde)),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(detalle, style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5)),
            Text(
              monto,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 13.5,
                color: baja
                    ? ColoresCuenta.rojo
                    : apagada
                    ? ColoresCuenta.gris
                    : ColoresCuenta.tinta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que dice una categoría abierta sin filas (33C·03).
class TextoSinNada extends StatelessWidget {
  const TextoSinNada({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Text(
        texto,
        style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: ColoresCuenta.gris),
      ),
    );
  }
}

/// El aparte de «Depositado» con lo que espera su validación: «Por validar  $ 1.800» y qué esperar.
class SeccionPorValidar extends StatelessWidget {
  const SeccionPorValidar({super.key, required this.centavos});

  final int centavos;

  @override
  Widget build(BuildContext context) {
    final monto = FormatoCuenta.monto(centavos);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        header: true,
        label: '${TextosMiPlata.porValidar}, $monto. ${TextosMiPlata.avisoPorValidar}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                const Text(
                  TextosMiPlata.porValidar,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  monto,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 13.5,
                    color: ColoresCuenta.gris,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              TextosMiPlata.avisoPorValidar,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: ColoresCuenta.gris),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las filas de cada categoría, con el texto que les toca.
abstract final class FilasDeMiPlata {
  static String cobro(MovimientoEnMano m) => switch (m.deposito) {
    final d? => '${TextosMiPlata.deposito} · ${deposito(d)}',
    null => '${m.cliente} · ${FormatoCuenta.fecha(m.fecha)}',
  };

  static String saldo(SaldoDeCliente s) =>
      '${s.cliente} · ${TextosMiPlata.desde} ${FormatoCuenta.fecha(s.desde)}';

  /// «Casa editora · Banco · 20/10»: un depósito no es de un cliente, sino para qué y dónde.
  static String deposito(DepositoDeLaLista d) {
    final concepto = switch (d.concepto) {
      ConceptoDeDeposito.casaEditora => TextosMiPlata.casaEditora,
      ConceptoDeDeposito.alquiler => TextosMiPlata.alquiler,
    };
    final destino = switch (d.destino) {
      DestinoDeDeposito.banco => TextosMiPlata.banco,
      DestinoDeDeposito.oficina => TextosMiPlata.oficina,
      DestinoDeDeposito.retiroCoordinador => TextosMiPlata.retiro,
    };
    return '$concepto · $destino · ${FormatoCuenta.fecha(d.fecha)}';
  }
}
