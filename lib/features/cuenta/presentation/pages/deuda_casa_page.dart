import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cuenta_providers.dart' show relojCuentaProvider;
import '../providers/deuda_casa_providers.dart';
import '../textos_deuda.dart';
import '../widgets/piezas_cuenta.dart';
import '../widgets/piezas_deuda.dart';

/// La deuda con la casa editora (vista 33B, HU-CTA-002): el total de arriba y, debajo, los pedidos
/// que todavía tienen saldo con lo que valió cada uno y lo que ya se pagó. Se abre al tocar la tarjeta
/// «Deuda con la casa editora» de Mi Cuenta.
///
/// La cuenta la hace el servidor; el teléfono muestra lo último que llegó y pide de nuevo al abrir.
/// Estados: con deuda (33B·01), sin deuda (33B·02), error con «Reintentar» (33B·03), cargando (un
/// bloque gris por parte, como 33A·03) y sin conexión (lo último que llegó con su hora, como 33A·02).
/// Si se pagó de más, el total dice «A favor $ X».
class DeudaCasaPage extends ConsumerStatefulWidget {
  const DeudaCasaPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada: la deuda es «mi deuda».
  final String colportorId;

  /// Abre la deuda encima de lo que se esté viendo.
  static Future<void> abrir(BuildContext context, {required String colportorId}) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => DeudaCasaPage(colportorId: colportorId)));

  @override
  ConsumerState<DeudaCasaPage> createState() => _DeudaCasaPageState();
}

class _DeudaCasaPageState extends ConsumerState<DeudaCasaPage> {
  @override
  void initState() {
    super.initState();
    // Al abrirla se vuelve a pedir: la tarjeta de Mi Cuenta pudo leer hace rato. Después del primer
    // cuadro: tocar un provider durante `initState` marca a quien lo mira en plena construcción.
    // Si ya hay un pedido en curso no suma otro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(deudaConLaCasaProvider(widget.colportorId).notifier).actualizar());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = deudaConLaCasaProvider(widget.colportorId);
    final estado = ref.watch(provider);
    final lectura = estado.lectura;

    final List<Widget> cuerpo;
    if (lectura == null && estado.fallo == null) {
      // Cargando, también al tocar «Reintentar»: mientras vuelve a pedir no queda el error a la vista
      // ni se puede tocar dos veces.
      cuerpo = const [SliverToBoxAdapter(child: EsqueletoDeuda())];
    } else if (lectura == null) {
      cuerpo = [
        SliverToBoxAdapter(
          child: BannerErrorCuenta(
            // Sin conexión y sin nada guardado: lo que falta es la red, no el servidor.
            texto: estado.fallo == FalloDeLaDeuda.sinConexion
                ? TextosDeuda.necesitasConexion
                : TextosDeuda.errorTraer,
            alReintentar: () => ref.read(provider.notifier).actualizar(),
          ),
        ),
      ];
    } else {
      final deuda = lectura.deuda;
      final fallo = estado.fallo;
      cuerpo = [
        if (fallo == FalloDeLaDeuda.sinConexion)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: AvisoSinConexionCuenta(
                texto: FormatoDeuda.avisoDeLoGuardado(
                  fallo!,
                  lectura.leidaEn,
                  ref.read(relojCuentaProvider)(),
                ),
              ),
            ),
          )
        else if (fallo == FalloDeLaDeuda.noDisponible)
          // «No pudimos actualizarla…» se puede reintentar (decisión del 04/11, mapa §2).
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BannerErrorCuenta(
                texto: FormatoDeuda.avisoDeLoGuardado(
                  fallo!,
                  lectura.leidaEn,
                  ref.read(relojCuentaProvider)(),
                ),
                alReintentar: () => ref.read(provider.notifier).actualizar(),
              ),
            ),
          ),
        SliverToBoxAdapter(child: TotalDeLaDeuda(deuda: deuda)),
        if (deuda.sinDeuda)
          const SliverToBoxAdapter(child: SinDeudaConLaCasa())
        else if (deuda.pedidos.isNotEmpty) ...[
          const SliverToBoxAdapter(child: RotuloDeSeccionDeuda(texto: TextosDeuda.pedidosConSaldo)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: deuda.pedidos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) =>
                  TarjetaDePedidoConSaldo(key: Key('deuda_pedido_$i'), pedido: deuda.pedidos[i]),
            ),
          ),
        ],
        if (deuda.saldosNoDanElTotal)
          const SliverToBoxAdapter(child: NotaDeLaDeuda(texto: TextosDeuda.saldosNoDanElTotal)),
      ];
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('deuda_lista'),
          slivers: [
            SliverToBoxAdapter(child: CabeceraDeuda(alVolver: () => Navigator.maybePop(context))),
            ...cuerpo,
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
