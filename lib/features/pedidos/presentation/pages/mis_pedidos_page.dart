import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/pedido.dart';
import '../providers/pedidos_providers.dart';
import '../textos_pedidos.dart';
import '../widgets/piezas_pedidos.dart';
import 'detalle_de_pedido_page.dart';
import 'pedir_pedido_page.dart';

/// Qué pedidos se ven en «Mis pedidos».
enum FiltroDePedidos {
  todos(TextosPedidos.filtroTodos),
  porAutorizar(TextosPedidos.filtroPorAutorizar),
  enCamino(TextosPedidos.filtroEnCamino),
  recibidos(TextosPedidos.filtroRecibidos);

  const FiltroDePedidos(this.rotulo);

  final String rotulo;

  bool deja(Pedido p) => switch (this) {
    todos => true,
    porAutorizar => p.estado == EstadoDelPedido.porAutorizar,
    enCamino => p.estado.enCamino,
    recibidos => p.estado == EstadoDelPedido.recibido,
  };
}

/// Mis pedidos (vista 37B, HU-STK-009): los pedidos a la casa editora con su estado, el más nuevo primero.
/// Se lee de la base del teléfono, así que sin conexión se ve lo último que bajó (y los que armó acá).
///
/// Estados del canvas: la lista (37B·01), sin pedidos (37B·04), cargando (37B·05) y error con «Reintentar»
/// (37B·06). «+ Nuevo pedido» abre «Nuevo pedido» (37A); tocar uno abre su detalle (37B·02, 37B·03).
class MisPedidosPage extends ConsumerStatefulWidget {
  const MisPedidosPage({super.key, required this.colportorId});

  final String colportorId;

  /// Abre «Mis pedidos» encima de lo que se esté viendo.
  static Future<void> abrir(BuildContext context, {required String colportorId}) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => MisPedidosPage(colportorId: colportorId)));

  @override
  ConsumerState<MisPedidosPage> createState() => _MisPedidosPageState();
}

class _MisPedidosPageState extends ConsumerState<MisPedidosPage> {
  var _filtro = FiltroDePedidos.todos;

  /// Ya se está abriendo una pantalla: un segundo toque antes de que termine no abre otra encima.
  var _abriendo = false;

  Future<void> _abrir(Future<void> Function() abrir) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await abrir();
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosProvider(widget.colportorId));
    final ahora = ref.read(relojPedidoProvider)();

    final Widget cuerpo;
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
    } else {
      final todos = pedidos.requireValue;
      final visibles = [
        for (final p in todos)
          if (_filtro.deja(p)) p,
      ];
      cuerpo = todos.isEmpty
          ? const HeroDePedido(
              glifo: '▤',
              titulo: TextosPedidos.sinPedidosTitulo,
              texto: TextosPedidos.sinPedidosTexto,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in FiltroDePedidos.values)
                        Semantics(
                          selected: f == _filtro,
                          button: true,
                          child: ChoiceChip(
                            key: Key('pedidos_filtro_${f.name}'),
                            label: Text(f.rotulo),
                            selected: f == _filtro,
                            onSelected: (_) => setState(() => _filtro = f),
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            selectedColor: const Color(0xFF002856),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFE3E7EE), width: 1.5),
                            shape: const StadiumBorder(),
                            labelStyle: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: f == _filtro ? Colors.white : const Color(0xFF0E1A2B),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (visibles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        TextosPedidos.sinPedidosEnElFiltro,
                        key: Key('pedidos_filtro_vacio'),
                        style: TextStyle(fontSize: 14, color: Color(0xFF5B6B82)),
                      ),
                    )
                  else
                    Column(
                      spacing: 8,
                      children: [
                        for (final p in visibles)
                          TarjetaDePedido(
                            pedido: p,
                            ahora: ahora,
                            alAbrir: () => unawaited(
                              _abrir(
                                () => DetalleDePedidoPage.abrir(
                                  context,
                                  colportorId: widget.colportorId,
                                  pedidoId: p.id,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            );
    }

    return PaginaDePedidos(
      clave: const Key('pedidos_lista'),
      encabezado: CabeceraDePedidos(
        eyebrow: TextosPedidos.eyebrowMis,
        titulo: TextosPedidos.tituloMis,
        glifo: '‹',
        alVolver: () => Navigator.of(context).maybePop(),
      ),
      cuerpo: cuerpo,
      pie: BotonDePedido(
        texto: TextosPedidos.nuevoPedido,
        alTocar: () => unawaited(
          _abrir(() => PedirPedidoPage.abrir(context, colportorId: widget.colportorId)),
        ),
      ),
    );
  }
}
