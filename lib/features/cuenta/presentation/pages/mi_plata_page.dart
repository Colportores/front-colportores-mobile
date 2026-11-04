import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/detalle_de_mi_plata.dart';
import '../providers/cuenta_providers.dart';
import '../textos_cuenta.dart';
import '../widgets/piezas_cuenta.dart';
import '../widgets/piezas_mi_plata.dart';

/// «Mi plata» (vista 33C, HU-CTA-003): el detalle de cada cifra de Mi Cuenta, con qué clientes, en qué
/// fecha y por cuánto. Se abre al tocar una tarjeta de Mi Cuenta, con esa categoría desplegada.
///
/// En V1 son **Depositado**, **En mano** y **Por cobrar**. «Depositado» suma solo lo que el coordinador
/// validó y muestra aparte lo que espera su validación; no se dibuja mientras el teléfono no bajó nada
/// del servidor. «Registrar depósito» llega con HU-CTA-004: no se dibuja lo que no se puede hacer. Todo
/// sale del teléfono: sin conexión se ve igual. Cargando y error son los de Mi Cuenta (33A·03, 33A·05).
class MiPlataPage extends ConsumerStatefulWidget {
  const MiPlataPage({super.key, required this.colportorId, required this.abierta});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// La categoría que llega desplegada.
  final CategoriaDeMiPlata abierta;

  /// Abre «Mi plata» encima de lo que se esté viendo.
  static Future<void> abrir(
    BuildContext context, {
    required String colportorId,
    required CategoriaDeMiPlata abierta,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MiPlataPage(colportorId: colportorId, abierta: abierta),
    ),
  );

  @override
  ConsumerState<MiPlataPage> createState() => _MiPlataPageState();
}

class _MiPlataPageState extends ConsumerState<MiPlataPage> {
  late final Set<CategoriaDeMiPlata> _abiertas = {widget.abierta};

  void _alternar(CategoriaDeMiPlata categoria) => setState(() {
    if (!_abiertas.remove(categoria)) _abiertas.add(categoria);
  });

  @override
  Widget build(BuildContext context) {
    final provider = detalleDeMiPlataProvider(widget.colportorId);
    final detalle = ref.watch(provider);

    final List<Widget> cuerpo;
    if (detalle.isLoading && !detalle.hasValue) {
      cuerpo = const [SliverToBoxAdapter(child: EsqueletoCuenta())];
    } else if (detalle.hasError) {
      cuerpo = [
        SliverToBoxAdapter(child: BannerErrorCuenta(alReintentar: () => ref.invalidate(provider))),
      ];
    } else {
      cuerpo = _categorias(detalle.requireValue);
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('mi_plata_lista'),
          slivers: [
            SliverToBoxAdapter(child: CabeceraMiPlata(alVolver: () => Navigator.maybePop(context))),
            ...cuerpo,
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _categorias(DetalleDeMiPlata d) {
    final depositado = d.depositado;
    return [
      if (depositado != null) _depositado(depositado),
      _categoria(
        CategoriaDeMiPlata.enMano,
        d.enManoCentavos,
        d.enMano.length,
        (i) => FilaDeMiPlata(
          key: Key('mi_plata_fila_enMano_$i'),
          detalle: FilasDeMiPlata.cobro(d.enMano[i]),
          monto: FormatoCuenta.monto(d.enMano[i].centavos),
        ),
      ),
      _categoria(
        CategoriaDeMiPlata.porCobrar,
        d.porCobrarCentavos,
        d.porCobrar.length,
        (i) => FilaDeMiPlata(
          key: Key('mi_plata_fila_porCobrar_$i'),
          detalle: FilasDeMiPlata.saldo(d.porCobrar[i]),
          monto: FormatoCuenta.monto(d.porCobrar[i].centavos),
        ),
      ),
    ];
  }

  /// «Depositado»: primero lo validado (lo que suma a la cifra) y, aparte, lo que espera su validación.
  Widget _depositado(DepositadoEnMiPlata d) {
    return _categoria(
      CategoriaDeMiPlata.depositado,
      d.validadoCentavos,
      d.validados.length,
      (i) => FilaDeMiPlata(
        key: Key('mi_plata_fila_depositado_$i'),
        detalle: FilasDeMiPlata.deposito(d.validados[i]),
        monto: FormatoCuenta.monto(d.validados[i].montoCentavos),
      ),
      sinFilas: d.porValidar.isEmpty,
      aparte: d.porValidar.isEmpty
          ? const []
          : [
              SliverToBoxAdapter(
                child: SeccionPorValidar(
                  key: const Key('mi_plata_por_validar'),
                  centavos: d.porValidarCentavos,
                ),
              ),
              SliverList.builder(
                itemCount: d.porValidar.length,
                itemBuilder: (_, i) => FilaDeMiPlata(
                  key: Key('mi_plata_fila_porValidar_$i'),
                  detalle: FilasDeMiPlata.deposito(d.porValidar[i]),
                  monto: FormatoCuenta.monto(d.porValidar[i].montoCentavos),
                  apagada: true,
                ),
              ),
            ],
    );
  }

  /// La tarjeta de una categoría y, si está abierta, sus filas (o lo que dice cuando no tiene).
  Widget _categoria(
    CategoriaDeMiPlata categoria,
    int centavos,
    int cantidad,
    Widget Function(int) fila, {
    bool sinFilas = true,
    List<Widget> aparte = const [],
  }) {
    final abierta = _abiertas.contains(categoria);
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          sliver: SliverToBoxAdapter(
            child: CategoriaDesplegable(
              key: Key('mi_plata_categoria_${categoria.name}'),
              categoria: categoria,
              centavos: centavos,
              abierta: abierta,
              alTocar: () => _alternar(categoria),
            ),
          ),
        ),
        if (abierta && cantidad == 0 && sinFilas)
          SliverToBoxAdapter(
            child: TextoSinNada(
              key: Key('mi_plata_vacio_${categoria.name}'),
              texto: categoria.sinNada,
            ),
          )
        else if (abierta && cantidad > 0)
          SliverList.builder(itemCount: cantidad, itemBuilder: (_, i) => fila(i)),
        if (abierta) ...aparte,
      ],
    );
  }
}
