import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../catalogo/presentation/formato_precios.dart';
import '../../../cuenta/presentation/widgets/piezas_cuenta.dart' show ColoresCuenta;
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/armado_del_pedido.dart';
import '../../domain/entities/pedido.dart';
import '../../domain/services/calculador_del_pedido.dart';
import '../../domain/usecases/enviar_pedido_use_case.dart';
import '../providers/pedidos_providers.dart';
import '../textos_pedidos.dart';
import '../widgets/piezas_pedidos.dart';
import 'mis_pedidos_page.dart';

/// Solicitar un pedido a la casa editora (vista 37A, HU-STK-009): la colportora arma su pedido (producto ×
/// cantidad, a los precios de compra), ve su situación (deuda actual, deuda con este pedido, por cobrar,
/// libros por entregar) y lo envía a su coordinador.
///
/// Estados del canvas: armar (37A·01), otra categoría (37A·08), pasa el límite (37A·02: avisa y **no
/// bloquea**), sin productos (37A·03), enviando (37A·04), enviado (37A·05), sin conexión (37A·06: el pedido
/// queda guardado y sube solo) y error al enviar (37A·07, con «Reintentar»).
///
/// El pedido tiene su id desde que se abre la pantalla y lo mantiene en los reintentos: un doble toque o un
/// reintento tras una falla no manda dos. Mientras se envía no se cambia nada y el botón no se toca de nuevo;
/// si falla, vuelve a habilitarse con lo armado a salvo.
class PedirPedidoPage extends ConsumerStatefulWidget {
  const PedirPedidoPage({super.key, required this.colportorId});

  /// UUID de la colportora con la sesión iniciada: el pedido es «mío».
  final String colportorId;

  /// Abre «Nuevo pedido» encima de lo que se esté viendo.
  static Future<void> abrir(BuildContext context, {required String colportorId}) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => PedirPedidoPage(colportorId: colportorId)));

  @override
  ConsumerState<PedirPedidoPage> createState() => _PedirPedidoPageState();
}

class _PedirPedidoPageState extends ConsumerState<PedirPedidoPage> {
  final _cantidades = <String, int>{};
  final _idsDeLineas = <String, String>{};
  var _categoria = CategoriaDelPedido.libros;
  var _enviando = false;
  Failure? _falla;
  PedidoEnviado? _enviado;

  /// El pedido se mandó sin conexión: queda guardado y sube solo (37A·05 dice otra cosa).
  var _enviadoSinConexion = false;

  late final String _pedidoId;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _pedidoId = ref.read(generadorIdPedidoProvider)();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Después de un envío (bien o mal) lo que importa está arriba: el éxito, o el aviso del error. Quien tocó
  /// el botón de abajo no lo vería.
  void _irArriba() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  int get _unidades => _cantidades.values.fold(0, (s, n) => s + n);

  void _cambiar(String productoId, int cantidad) {
    if (_enviando) return;
    setState(() {
      if (cantidad <= 0) {
        _cantidades.remove(productoId);
      } else {
        _cantidades[productoId] = cantidad;
      }
      // Lo que se toca después de una falla es otro intento.
      _falla = null;
    });
  }

  Future<void> _enviar(List<ProductoPedible> productos, bool excede, bool sinConexion) async {
    // La guarda es un campo y no solo el estado: tiene que cortar el segundo toque aunque llegue antes
    // de que se redibuje.
    if (_enviando || _unidades == 0) return;
    final generar = ref.read(generadorIdPedidoProvider);
    final enviar = ref.read(enviarPedidoUseCaseProvider);
    _enviando = true;
    setState(() => _falla = null);
    try {
      final resultado = await enviar(
        EnviarPedidoParams(
          pedidoId: _pedidoId,
          colportorId: widget.colportorId,
          cantidades: Map.of(_cantidades),
          productos: productos,
          idsDeLineas: {
            for (final id in _cantidades.keys) id: _idsDeLineas.putIfAbsent(id, generar),
          },
          excedeLimite: excede,
        ),
      );
      if (!mounted) return;
      setState(() {
        resultado.fold((falla) => _falla = falla, (enviado) {
          _enviado = enviado;
          _enviadoSinConexion = sinConexion;
        });
      });
      _irArriba();
    } on Object {
      // El caso de uso no lanza; si algo se escapa, el botón no queda trabado en «Enviando…».
      if (mounted) {
        setState(() => _falla = const FailurePedidoNoGuardado());
        _irArriba();
      }
    } finally {
      _enviando = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _salir() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(TextosPedidos.descartarTitulo),
        content: const Text(TextosPedidos.descartarTexto),
        actions: [
          TextButton(
            key: const Key('pedido_seguir_armando'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(TextosPedidos.seguirArmando),
          ),
          TextButton(
            key: const Key('pedido_descartar'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(TextosPedidos.descartar),
          ),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _verMisPedidos() async {
    final navegador = Navigator.of(context);
    unawaited(
      navegador.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => MisPedidosPage(colportorId: widget.colportorId)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enviado = _enviado;
    final sinRed = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final productos = ref.watch(productosPedibles(widget.colportorId));
    final situacion = ref.watch(situacionDelPedidoProvider(widget.colportorId));
    final reloj = ref.read(relojPedidoProvider);

    final lista = productos.value ?? const <ProductoPedible>[];
    final monto = CalculadorDelPedido.montoDe(_cantidades, lista);
    final sit = situacion.value;
    final excede = sit != null && CalculadorDelPedido.superaElLimite(sit, monto);

    final Widget cuerpo;
    final Widget? pie;
    if (enviado != null) {
      cuerpo = _Enviado(enviado: enviado, sinConexion: _enviadoSinConexion);
      pie = BotonDePedido(texto: TextosPedidos.verMisPedidos, alTocar: _verMisPedidos);
    } else {
      cuerpo = _Armar(
        productos: productos,
        categoria: _categoria,
        cantidades: _cantidades,
        situacion: situacion,
        monto: monto,
        sinRed: sinRed,
        falla: _falla,
        enviando: _enviando,
        excede: excede,
        ahora: reloj(),
        alElegirCategoria: (c) => setState(() => _categoria = c),
        alCambiar: _cambiar,
        alReintentarProductos: () => ref.invalidate(productosPedibles(widget.colportorId)),
        alReintentarSituacion: () {
          ref.invalidate(contextoDelPedidoProvider(widget.colportorId));
        },
      );
      final vacio = _unidades == 0;
      pie = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vacio && !_enviando)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                TextosPedidos.sumaUnProducto,
                key: Key('pedido_nota_vacio'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: ColoresCuenta.gris),
              ),
            ),
          BotonDePedido(
            texto: _enviando
                ? TextosPedidos.enviando
                : _falla != null
                ? TextosPedidos.reintentar
                : sinRed
                ? TextosPedidos.enviarCuandoHayConexion
                : TextosPedidos.enviar,
            ocupado: _enviando,
            alTocar: vacio || !productos.hasValue
                ? null
                : () => unawaited(_enviar(lista, excede, sinRed)),
          ),
        ],
      );
    }

    return PopScope(
      // Con algo armado, salir lo descarta: se avisa antes. Mientras se envía no se sale (el envío sigue y
      // la pantalla tiene que mostrar cómo terminó).
      canPop: enviado != null || (_cantidades.isEmpty && !_enviando),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_enviando) unawaited(_salir());
      },
      child: PaginaDePedidos(
        clave: const Key('pedido_lista'),
        controlador: _scroll,
        encabezado: CabeceraDePedidos(
          eyebrow: TextosPedidos.eyebrowArmar,
          titulo: enviado != null ? TextosPedidos.tituloEnviado : TextosPedidos.tituloArmar,
          subtitulo: enviado != null ? null : TextosPedidos.subtituloArmar,
          glifo: enviado != null ? null : '✕',
          alVolver: () => Navigator.of(context).maybePop(),
        ),
        cuerpo: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), child: cuerpo),
        pie: pie,
      ),
    );
  }
}

/// El cuerpo de armar el pedido (37A·01 a 37A·07).
class _Armar extends StatelessWidget {
  const _Armar({
    required this.productos,
    required this.categoria,
    required this.cantidades,
    required this.situacion,
    required this.monto,
    required this.sinRed,
    required this.falla,
    required this.enviando,
    required this.excede,
    required this.ahora,
    required this.alElegirCategoria,
    required this.alCambiar,
    required this.alReintentarProductos,
    required this.alReintentarSituacion,
  });

  final AsyncValue<List<ProductoPedible>> productos;
  final CategoriaDelPedido categoria;
  final Map<String, int> cantidades;
  final AsyncValue<SituacionDelColportor> situacion;
  final int monto;
  final bool sinRed;
  final Failure? falla;
  final bool enviando;
  final bool excede;
  final DateTime ahora;
  final ValueChanged<CategoriaDelPedido> alElegirCategoria;
  final void Function(String, int) alCambiar;
  final VoidCallback alReintentarProductos;
  final VoidCallback alReintentarSituacion;

  @override
  Widget build(BuildContext context) {
    final sit = situacion.value;
    final lista = productos.value ?? const <ProductoPedible>[];
    final unidades = <CategoriaDelPedido, int>{};
    for (final p in lista) {
      final c = p.categoria;
      if (c != null) unidades[c] = (unidades[c] ?? 0) + (cantidades[p.id] ?? 0);
    }
    final deLaCategoria = [
      for (final p in lista)
        if (p.categoria == categoria) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sinRed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AvisoDePedido(
              clase: ClaseDeAviso.sinConexion,
              texto: TextosPedidos.sinConexion(sit?.deudaLeidaEn, ahora),
            ),
          ),
        if (falla != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AvisoDePedido(clase: ClaseDeAviso.error, texto: falla!.mensaje),
          ),
        const RotuloDePedido(TextosPedidos.quePedis),
        const SizedBox(height: 8),
        ChipsDeCategoria(
          unidadesPorCategoria: unidades,
          elegida: categoria,
          alElegir: enviando ? (_) {} : alElegirCategoria,
        ),
        const SizedBox(height: 10),
        if (productos.isLoading && !productos.hasValue)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (productos.hasError)
          AvisoDePedido(
            clase: ClaseDeAviso.error,
            texto: TextosPedidos.errorProductos,
            textoDelBoton: TextosPedidos.reintentar,
            alTocarElBoton: alReintentarProductos,
          )
        else if (lista.isEmpty)
          const _Nota(TextosPedidos.sinCatalogo)
        else if (deLaCategoria.isEmpty)
          const _Nota(TextosPedidos.sinProductosEnCategoria)
        else
          Column(
            spacing: 8,
            children: [
              for (final p in deLaCategoria)
                FilaDeProductoPedible(
                  key: Key('pedido_fila_${p.id}'),
                  producto: p,
                  cantidad: cantidades[p.id] ?? 0,
                  alCambiar: (n) => alCambiar(p.id, n),
                  habilitada: !enviando,
                ),
            ],
          ),
        const SizedBox(height: 18),
        const RotuloDePedido(TextosPedidos.tuSituacion),
        const SizedBox(height: 6),
        if (situacion.hasError)
          AvisoDePedido(
            clase: ClaseDeAviso.error,
            texto: TextosPedidos.errorSituacion,
            textoDelBoton: TextosPedidos.reintentar,
            alTocarElBoton: alReintentarSituacion,
          )
        else if (sit == null)
          const _EsqueletoDeSituacion()
        else
          _Situacion(situacion: sit, monto: monto, excede: excede),
        if (excede && sit != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AvisoDePedido(
              clase: ClaseDeAviso.limite,
              texto: TextosPedidos.superaElLimite(sit.limiteDeudaCentavos!),
            ),
          ),
      ],
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      texto,
      key: const Key('pedido_nota'),
      style: const TextStyle(fontSize: 14, height: 1.45, color: ColoresCuenta.gris),
    ),
  );
}

class _EsqueletoDeSituacion extends StatelessWidget {
  const _EsqueletoDeSituacion();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('pedido_situacion_cargando'),
    height: 150,
    decoration: BoxDecoration(
      color: ColoresCuenta.esqueleto,
      borderRadius: BorderRadius.circular(14),
    ),
  );
}

/// «TU SITUACIÓN»: las cinco cifras de la HU. La deuda con el pedido va en rojo cuando pasa el límite.
class _Situacion extends StatelessWidget {
  const _Situacion({required this.situacion, required this.monto, required this.excede});

  final SituacionDelColportor situacion;
  final int monto;
  final bool excede;

  @override
  Widget build(BuildContext context) {
    return CuadroDeDatos(
      hijos: [
        FilaDeDato(
          rotulo: TextosPedidos.deudaActual,
          valor: FormatoPrecios.monto(situacion.deudaActualCentavos),
        ),
        FilaDeDato(rotulo: TextosPedidos.estePedido, valor: '+ ${FormatoPrecios.monto(monto)}'),
        FilaDeDato(
          rotulo: TextosPedidos.deudaConEstePedido,
          valor: FormatoPrecios.monto(CalculadorDelPedido.deudaConPedido(situacion, monto)),
          enfasis: true,
          enRojo: excede,
        ),
        FilaDeDato(
          rotulo: TextosPedidos.porCobrar,
          valor: FormatoPrecios.monto(situacion.porCobrarCentavos),
        ),
        FilaDeDato(
          rotulo: TextosPedidos.librosPorEntregar,
          valor: '${situacion.librosPorEntregar}',
          mono: false,
        ),
      ],
    );
  }
}

/// El pedido ya está guardado (37A·05). Con conexión es el éxito del canvas; sin ella dice la verdad: quedó
/// guardado y sube solo.
class _Enviado extends StatelessWidget {
  const _Enviado({required this.enviado, required this.sinConexion});

  final PedidoEnviado enviado;
  final bool sinConexion;

  @override
  Widget build(BuildContext context) {
    final pedido = enviado.pedido;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroDePedido(
          glifo: '✓',
          fondo: ColoresCuenta.verdeFondo,
          tinta: ColoresCuenta.verde,
          titulo: sinConexion ? TextosPedidos.heroEnCola : TextosPedidos.heroEnviado,
          texto: sinConexion ? TextosPedidos.detalleEnCola : TextosPedidos.detalleEnviado,
        ),
        CuadroDeDatos(
          hijos: [
            FilaDeDato(
              rotulo: TextosPedidos.pedido,
              valor: TextosPedidos.productos(pedido.unidades),
              mono: false,
            ),
            FilaDeDato(
              rotulo: TextosPedidos.monto,
              valor: FormatoPrecios.monto(pedido.montoCentavos),
              enfasis: true,
            ),
          ],
        ),
      ],
    );
  }
}
