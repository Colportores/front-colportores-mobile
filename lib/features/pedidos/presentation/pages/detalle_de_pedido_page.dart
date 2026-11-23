import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../catalogo/presentation/formato_precios.dart';
import '../../domain/entities/pedido.dart';
import '../../domain/usecases/cancelar_pedido_use_case.dart';
import '../providers/pedidos_providers.dart';
import '../textos_pedidos.dart';
import '../widgets/piezas_pedidos.dart';
import 'pedir_pedido_page.dart';

/// El detalle de un pedido (vista 37B·02 y 37B·03, HU-STK-009): cuánto vale, en qué estado está y qué lleva.
/// Se lee de la base del teléfono, así que se ve sin conexión.
///
/// - **Por autorizar**: «Cancelar pedido» (la colportora lo puede cancelar mientras no esté autorizado; no
///   vuelve atrás, así que se confirma) y, si pasaba el límite, el aviso de que su coordinador lo tiene en
///   cuenta.
/// - **No autorizado**: el motivo de su coordinador y «Armar uno nuevo».
/// - Autorizado, despachado, recibido y cancelado: solo lectura (el canvas no los dibuja; con lo autorizado
///   cuando el coordinador redujo una línea).
///
/// Cancelar guarda la cancelación en el teléfono y la sube sola; si falla, el botón vuelve a habilitarse y el
/// pedido sigue como estaba.
class DetalleDePedidoPage extends ConsumerStatefulWidget {
  const DetalleDePedidoPage({super.key, required this.colportorId, required this.pedidoId});

  final String colportorId;
  final String pedidoId;

  static Future<void> abrir(
    BuildContext context, {
    required String colportorId,
    required String pedidoId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => DetalleDePedidoPage(colportorId: colportorId, pedidoId: pedidoId),
    ),
  );

  @override
  ConsumerState<DetalleDePedidoPage> createState() => _DetalleDePedidoPageState();
}

class _DetalleDePedidoPageState extends ConsumerState<DetalleDePedidoPage> {
  var _cancelando = false;
  Failure? _falla;

  Future<void> _cancelar() async {
    if (_cancelando) return;
    final confirmo = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text(TextosPedidos.cancelarTitulo),
        content: const Text(TextosPedidos.cancelarTexto),
        actions: [
          TextButton(
            key: const Key('pedido_no_cancelar'),
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text(TextosPedidos.noCancelar),
          ),
          TextButton(
            key: const Key('pedido_si_cancelar'),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text(TextosPedidos.cancelarConfirmar),
          ),
        ],
      ),
    );
    if (confirmo != true || !mounted || _cancelando) return;
    final cancelar = ref.read(cancelarPedidoUseCaseProvider);
    // La guarda es un campo: corta el segundo toque aunque llegue antes de que se redibuje.
    _cancelando = true;
    setState(() => _falla = null);
    try {
      final resultado = await cancelar(
        CancelarPedidoParams(pedidoId: widget.pedidoId, colportorId: widget.colportorId),
      );
      if (!mounted) return;
      // Si salió bien, el pedido cancelado llega por la lectura de la base.
      resultado.fold((falla) => setState(() => _falla = falla), (_) {});
    } on Object {
      if (mounted) setState(() => _falla = const FailurePedidoNoCancelado());
    } finally {
      _cancelando = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosProvider(widget.colportorId));
    final nombres = ref.watch(nombresDeProductosPedidoProvider).value ?? const <String, String>{};
    final ahora = ref.read(relojPedidoProvider)();

    Pedido? pedido;
    for (final p in pedidos.value ?? const <Pedido>[]) {
      if (p.id == widget.pedidoId) pedido = p;
    }

    final Widget cuerpo;
    Widget? pie;
    String eyebrow = TextosPedidos.eyebrowMis;
    String titulo = TextosPedidos.tituloMis;
    String? subtitulo;
    if (pedidos.isLoading && !pedidos.hasValue) {
      cuerpo = const EsqueletoDePedidos();
    } else if (pedidos.hasError) {
      cuerpo = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AvisoDePedido(
          clase: ClaseDeAviso.error,
          texto: TextosPedidos.errorTraer,
          textoDelBoton: TextosPedidos.reintentar,
          alTocarElBoton: () => ref.invalidate(pedidosProvider(widget.colportorId)),
        ),
      );
    } else if (pedido == null) {
      cuerpo = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Text(
          TextosPedidos.pedidoNoEncontrado,
          key: Key('pedido_no_encontrado'),
          style: TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF5B6B82)),
        ),
      );
    } else {
      eyebrow = TextosPedidos.eyebrowDetalle(pedido, ahora);
      titulo = FormatoPrecios.monto(pedido.montoVigenteCentavos);
      subtitulo = TextosPedidos.subtituloDetalle(pedido, ahora);
      cuerpo = _Cuerpo(pedido: pedido, nombres: nombres, falla: _falla);
      pie = switch (pedido.estado) {
        EstadoDelPedido.porAutorizar => BotonDePedido(
          texto: _cancelando ? TextosPedidos.cancelando : TextosPedidos.cancelarPedido,
          ocupado: _cancelando,
          secundario: true,
          peligro: true,
          alTocar: () => unawaited(_cancelar()),
        ),
        EstadoDelPedido.rechazado => BotonDePedido(
          texto: TextosPedidos.armarUnoNuevo,
          alTocar: () => unawaited(PedirPedidoPage.abrir(context, colportorId: widget.colportorId)),
        ),
        _ => null,
      };
    }

    return PaginaDePedidos(
      clave: const Key('pedido_detalle'),
      encabezado: CabeceraDePedidos(
        eyebrow: eyebrow,
        titulo: titulo,
        subtitulo: subtitulo,
        glifo: '‹',
        alVolver: () => Navigator.of(context).maybePop(),
      ),
      cuerpo: cuerpo,
      pie: pie,
    );
  }
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.pedido, required this.nombres, required this.falla});

  final Pedido pedido;
  final Map<String, String> nombres;
  final Failure? falla;

  @override
  Widget build(BuildContext context) {
    final lineas = pedido.lineas;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (falla != null) AvisoDePedido(clase: ClaseDeAviso.error, texto: falla!.mensaje),
          if (pedido.estado == EstadoDelPedido.rechazado)
            AvisoDePedido(
              clase: ClaseDeAviso.error,
              texto: TextosPedidos.noAutorizado(pedido.motivoRechazo),
            ),
          if (pedido.estado == EstadoDelPedido.cancelado)
            const AvisoDePedido(
              clase: ClaseDeAviso.sinConexion,
              texto: TextosPedidos.pedidoCancelado,
            ),
          if (lineas.isNotEmpty)
            CuadroDeDatos(
              hijos: [
                for (final l in lineas)
                  FilaDeDato(
                    key: Key('pedido_linea_${l.productoId}'),
                    rotulo: nombres[l.productoId] ?? TextosPedidos.productoSinNombre,
                    valor: l.cantidadAutorizada != null && l.cantidadAutorizada != l.cantidad
                        ? TextosPedidos.lineaAutorizada(l.cantidad, l.cantidadAutorizada!)
                        : TextosPedidos.linea(l.cantidad),
                    mono: false,
                  ),
              ],
            ),
          // Solo mientras sigue en juego: un pedido ya decidido no necesita el aviso.
          if (pedido.excedeLimite && pedido.estado == EstadoDelPedido.porAutorizar)
            const AvisoDePedido(clase: ClaseDeAviso.limite, texto: TextosPedidos.excedioElLimite),
        ],
      ),
    );
  }
}
