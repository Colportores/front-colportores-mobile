import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/resumen_de_cuenta.dart';
import '../providers/cuenta_providers.dart';
import '../providers/deuda_casa_providers.dart';
import '../textos_cuenta.dart';
import '../widgets/piezas_cuenta.dart';
import '../widgets/tarjeta_de_deuda.dart';

/// La pestaña «Cuenta» (vista 33A, HU-CTA-001): las cifras de la plata del colportor con cuánto
/// cambiaron contra la semana pasada.
///
/// Vive dentro de la pantalla principal (`IndexedStack`): [activa] dice si la pestaña está a la vista.
/// Todo sale del teléfono, así que sin conexión se ve igual (33A·02); el único dato que puede estar
/// viejo es «Depositado» (viene del servidor) y es el que el aviso nombra. Sin «Depositado» no hay
/// aviso: no hay nada viejo que decir. Mientras se calcula, un bloque gris por tarjeta
/// (33A·03); si la base no se puede leer, el error con «Reintentar» (33A·05), nunca ceros.
///
/// Son cuatro tarjetas: la deuda con la casa editora, Depositado, En mano y Por cobrar. «Depositado» suma
/// solo lo que el coordinador validó y baja del servidor por el pull: mientras el teléfono no bajó nada
/// no se dibuja (ni un cero), y sin conexión un aviso dice de cuándo es (33A·02). La deuda la cuenta el
/// servidor (HU-CTA-002): se muestra lo último que llegó y su toque abre el detalle por pedido (33B). El
/// toque en las otras tarjetas llega con su detalle (HU-CTA-003): hasta entonces no se dibuja lo que no
/// lleva a ningún lado.
class CuentaPage extends ConsumerStatefulWidget {
  const CuentaPage({super.key, required this.colportorId, this.activa = true});

  /// UUID del colportor con la sesión iniciada: Mi Cuenta es «mi plata».
  final String colportorId;

  /// La pestaña está a la vista.
  final bool activa;

  @override
  ConsumerState<CuentaPage> createState() => _CuentaPageState();
}

class _CuentaPageState extends ConsumerState<CuentaPage> {
  @override
  void didUpdateWidget(CuentaPage anterior) {
    super.didUpdateWidget(anterior);
    // Al volver a la pestaña se vuelve a leer: «hace una semana» corre con el reloj aunque no haya
    // cambiado ninguna venta. Con el dato anterior a la vista, sin pasar por la carga. Después del
    // cuadro: invalidar un provider durante `didUpdateWidget` marca a quien lo mira en plena
    // construcción.
    if (widget.activa && !anterior.activa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.activa) {
          ref.invalidate(resumenDeCuentaProvider(widget.colportorId));
          // La deuda se vuelve a pedir al servidor; la última que llegó sigue a la vista mientras tanto.
          unawaited(ref.read(deudaConLaCasaProvider(widget.colportorId).notifier).actualizar());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = resumenDeCuentaProvider(widget.colportorId);
    final resumen = ref.watch(provider);

    final List<Widget> cuerpo;
    if (resumen.isLoading && !resumen.hasValue) {
      // También al tocar «Reintentar»: mientras vuelve a calcular no queda el error a la vista ni se
      // puede tocar dos veces.
      cuerpo = const [SliverToBoxAdapter(child: EsqueletoCuenta())];
    } else if (resumen.hasError) {
      cuerpo = [
        SliverToBoxAdapter(child: BannerErrorCuenta(alReintentar: () => ref.invalidate(provider))),
      ];
    } else {
      final datos = resumen.requireValue;
      final depositadoAl = datos.depositadoAl;
      final sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
      // La hora de la deuda guardada: si difiere de la de lo depositado, el aviso la nombra.
      final deudaLeidaEn = ref.watch(
        deudaConLaCasaProvider(widget.colportorId).select((e) => e.lectura?.leidaEn),
      );
      cuerpo = [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          // Las tarjetas son pocas: una columna y no una lista perezosa, así la segunda existe (y
          // la lee el lector de pantalla) aunque el texto grande la deje fuera de la pantalla.
          sliver: SliverToBoxAdapter(
            child: Column(
              spacing: 8,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sinConexion && depositadoAl != null)
                  AvisoSinConexionCuenta(
                    texto: FormatoCuenta.sinConexion(
                      depositadoAl,
                      ref.read(relojCuentaProvider)(),
                      deudaLeidaEn: deudaLeidaEn,
                    ),
                  ),
                TarjetaDeDeuda(colportorId: widget.colportorId),
                for (final tipo in TipoDeCifra.values)
                  if (_cifraDe(tipo, datos) case final cifra?)
                    TarjetaDeCifra(key: Key('cuenta_${tipo.name}'), tipo: tipo, cifra: cifra),
              ],
            ),
          ),
        ),
      ];
    }

    // Todo se desplaza junto: con el texto al 200 % el encabezado y las tarjetas ocupan casi la
    // pantalla y la segunda tiene que poder llegar a la vista.
    return CustomScrollView(
      key: const Key('cuenta_pestana'),
      slivers: [
        const SliverToBoxAdapter(child: CabeceraCuenta()),
        ...cuerpo,
      ],
    );
  }

  /// La cifra de cada tarjeta; `null` = no se dibuja («Depositado» antes de la primera bajada).
  static CifraDeCuenta? _cifraDe(TipoDeCifra tipo, ResumenDeCuenta datos) => switch (tipo) {
    TipoDeCifra.depositado => datos.depositado,
    TipoDeCifra.enMano => datos.enMano,
    TipoDeCifra.porCobrar => datos.porCobrar,
  };
}
