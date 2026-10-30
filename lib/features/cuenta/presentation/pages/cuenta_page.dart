import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cuenta_providers.dart';
import '../widgets/piezas_cuenta.dart';
import '../widgets/piezas_mi_plata.dart';
import 'mi_plata_page.dart';

/// La pestaña «Cuenta» (vista 33A, HU-CTA-001): las cifras de la plata del colportor con cuánto
/// cambiaron contra la semana pasada.
///
/// Vive dentro de la pantalla principal (`IndexedStack`): [activa] dice si la pestaña está a la vista.
/// Todo sale del teléfono, así que sin conexión se ve igual (33A·02) y sin aviso: no hay nada que el
/// colportor pueda hacer ni dato que esté viejo. Mientras se calcula, un bloque gris por tarjeta
/// (33A·03); si la base no se puede leer, el error con «Reintentar» (33A·05), nunca ceros.
///
/// En V1 son dos tarjetas, En mano y Por cobrar. La deuda con la casa editora llega con los pedidos
/// (V2) y «Depositado» cuando el teléfono sepa qué validó el coordinador (#596). Cada tarjeta se toca
/// y abre su detalle en «Mi plata» (HU-CTA-003, 33C); no se dibuja lo que no lleva a ningún lado.
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
  /// Ya se está abriendo «Mi plata»: un segundo toque antes de que termine no abre otra encima.
  var _abriendo = false;

  Future<void> _abrir(TipoDeCifra tipo) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await MiPlataPage.abrir(
        context,
        colportorId: widget.colportorId,
        abierta: CategoriaDeMiPlata.de(tipo),
      );
    } finally {
      _abriendo = false;
    }
  }

  @override
  void didUpdateWidget(CuentaPage anterior) {
    super.didUpdateWidget(anterior);
    // Al volver a la pestaña se vuelve a leer: «hace una semana» corre con el reloj aunque no haya
    // cambiado ninguna venta. Con el dato anterior a la vista, sin pasar por la carga. Después del
    // cuadro: invalidar un provider durante `didUpdateWidget` marca a quien lo mira en plena
    // construcción.
    if (widget.activa && !anterior.activa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.activa) ref.invalidate(resumenDeCuentaProvider(widget.colportorId));
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
                for (final tipo in TipoDeCifra.values)
                  TarjetaDeCifra(
                    key: Key('cuenta_${tipo.name}'),
                    tipo: tipo,
                    alAbrir: () => _abrir(tipo),
                    cifra: switch (tipo) {
                      TipoDeCifra.enMano => datos.enMano,
                      TipoDeCifra.porCobrar => datos.porCobrar,
                    },
                  ),
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
}
