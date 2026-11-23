import '../../catalogo/presentation/formato_precios.dart';
import '../domain/entities/armado_del_pedido.dart';
import '../domain/entities/pedido.dart';

/// Los textos de «Solicitar un pedido» y «Mis pedidos» (vista 37, HU-STK-009). Los del canvas van tal cual;
/// los que el canvas no dibuja llevan arriba por qué y el origen («mapa §2: texto»: a confirmar).
abstract final class TextosPedidos {
  // --- 37A: armar el pedido ---
  static const eyebrowArmar = 'SOLICITAR PEDIDO';
  static const tituloArmar = 'Nuevo pedido';
  static const subtituloArmar = 'A la casa editora';
  static const quePedis = 'QUÉ PEDÍS · PRECIO DE COMPRA';
  static const tuSituacion = 'TU SITUACIÓN';
  static const deudaActual = 'Deuda actual';
  static const estePedido = 'Este pedido';
  static const deudaConEstePedido = 'Deuda con este pedido';
  static const porCobrar = 'Por cobrar';
  static const librosPorEntregar = 'Libros por entregar';
  static const enviar = 'Enviar a mi coordinador';
  static const enviando = 'Enviando…';
  static const enviarCuandoHayConexion = 'Enviar cuando haya conexión';
  static const reintentar = 'Reintentar';
  static const sumaUnProducto = 'Sumá al menos un producto.';
  static const cerrar = 'Cerrar';

  /// El aviso del límite (37A·02): solo avisa, no bloquea.
  static String superaElLimite(int limiteCentavos) =>
      'Con este pedido tu deuda pasa el límite de ${FormatoPrecios.monto(limiteCentavos)} que fijó tu '
      'coordinador. Lo podés enviar igual: tu coordinador decide al autorizar.';

  /// 37A·07. El canvas dice «Quedó guardado acá», que solo es cierto si la falla es posterior al guardado;
  /// cuando falla la escritura no se guardó nada, así que el texto es el de la falla (mapa §2: texto).
  static const errorAlEnviar = 'No pudimos enviar el pedido. No se envió nada: probá de nuevo.';

  /// 37A·06: lo que se ve sin conexión es lo último que se sincronizó.
  static String sinConexion(DateTime? bajadoEn, DateTime ahora) => bajadoEn == null
      ? 'Sin conexión. Tu deuda y lo que tenés por cobrar todavía no se bajaron: pueden no estar al día.'
      : 'Sin conexión. Tu deuda y lo que tenés por cobrar son ${_cuandoYHora(bajadoEn, ahora)}.';

  static String _cuandoYHora(DateTime instante, DateTime ahora) {
    final momento = instante.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(momento.year, momento.month, momento.day);
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = switch (hoy.difference(dia).inDays) {
      0 => 'de hoy',
      1 => 'de ayer',
      _ => 'del ${dos(dia.day)}/${dos(dia.month)}',
    };
    return '$cuando a las ${dos(momento.hour)}:${dos(momento.minute)}';
  }

  /// Lo que se ve de cada producto: «Tenés 2 · $ 1.870 c/u».
  static String tenesYPrecio(ProductoPedible p) =>
      'Tenés ${p.stock} · ${FormatoPrecios.monto(p.precioDeCompraCentavos)} c/u';

  /// El chip de una categoría con cuántas unidades lleva pedidas: «Libros · 6».
  static String chip(CategoriaDelPedido categoria, int unidades) =>
      unidades > 0 ? '${categoria.rotulo} · $unidades' : categoria.rotulo;

  static String quitar(String producto) => 'Quitar uno de $producto';
  static String sumar(String producto) => 'Sumar uno de $producto';
  static String cantidadDe(String producto, int n) =>
      '$producto: $n ${n == 1 ? 'unidad' : 'unidades'}';

  /// El catálogo todavía no bajó o ninguna categoría tiene productos con costo (el canvas no lo dibuja; mapa
  /// §2: texto).
  static const sinProductosEnCategoria = 'No hay productos para pedir en esta categoría.';
  static const sinCatalogo =
      'Todavía no bajamos el catálogo. Conectate para poder armar un pedido.';

  /// El teléfono no pudo leer los productos (el canvas no lo dibuja; mapa §2: texto).
  /// La situación no se pudo leer de la base del teléfono (el canvas no lo dibuja; mapa §2: texto). El
  /// pedido se puede enviar igual: el servidor mide el límite al recibirlo.
  static const errorSituacion =
      'No pudimos leer tu situación. Podés enviar el pedido igual: tu coordinador ve tu deuda.';
  static const errorProductos = 'No pudimos traer los productos para pedir.';

  /// Salir de armar con algo armado (mapa §2: texto): se pierde, y avisa antes.
  static const descartarTitulo = '¿Salir sin enviar?';
  static const descartarTexto = 'Lo que armaste se pierde.';
  static const descartar = 'Salir y descartar';
  static const seguirArmando = 'Seguir armando';

  // --- 37A·05: enviado ---
  static const tituloEnviado = 'Pedido enviado';
  static const heroEnviado = 'Tu coordinador lo tiene que autorizar';
  static const detalleEnviado = 'Te avisamos cuando lo autorice o lo despachen.';

  /// Enviado sin conexión: no llegó todavía (el canvas dibuja solo el éxito con red; mapa §2: texto).
  static const heroEnCola = 'Tu pedido quedó guardado';
  static const detalleEnCola =
      'Se envía solo cuando haya conexión. Después tu coordinador lo tiene que autorizar.';
  static const pedido = 'Pedido';
  static const monto = 'Monto';
  static const verMisPedidos = 'Ver mis pedidos';

  static String productos(int n) => '$n ${n == 1 ? 'producto' : 'productos'}';

  // --- 37B: mis pedidos ---
  static const eyebrowMis = 'MI CUENTA';
  static const tituloMis = 'Mis pedidos';
  static const nuevoPedido = '+ Nuevo pedido';
  static const volver = 'Volver';
  static const filtroTodos = 'Todos';
  static const filtroPorAutorizar = 'Por autorizar';
  static const filtroEnCamino = 'En camino';
  static const filtroRecibidos = 'Recibidos';
  static const sinPedidosTitulo = 'Todavía no pediste nada';
  static const sinPedidosTexto = 'Armá un pedido y tu coordinador lo autoriza.';

  /// Un filtro sin pedidos (el canvas no lo dibuja; mapa §2: texto).
  static const sinPedidosEnElFiltro = 'No hay pedidos en esta lista.';
  static const errorTraer = 'No pudimos traer tus pedidos.';
  static const cargando = 'Cargando tus pedidos';

  /// La etiqueta de cada estado en la lista y el detalle (37B·01 y 37B·03).
  static String estado(EstadoDelPedido e) => switch (e) {
    EstadoDelPedido.porAutorizar => 'Por autorizar',
    EstadoDelPedido.autorizado => 'Autorizado',
    EstadoDelPedido.despachado => 'Despachado',
    EstadoDelPedido.recibido => 'Recibido',
    EstadoDelPedido.rechazado => 'No autorizado',
    EstadoDelPedido.cancelado => 'Cancelado',
  };

  /// La fecha de la tarjeta: «HOY» o «15/10».
  static String fechaCorta(DateTime fecha, DateTime ahora) {
    final f = fecha.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(f.year, f.month, f.day);
    if (hoy == dia) return 'HOY';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}';
  }

  /// El pedido todavía no llegó al servidor (le falta el número).
  static const sinLlegar = 'Esperando conexión para enviarse';

  // --- 37B·02/03: detalle ---
  static String eyebrowDetalle(Pedido p, DateTime ahora) {
    final f = p.fecha.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    String dos(int n) => n.toString().padLeft(2, '0');
    if (hoy == DateTime(f.year, f.month, f.day)) return 'PEDIDO DE HOY';
    return 'PEDIDO DEL ${dos(f.day)}/${dos(f.month)}';
  }

  /// «Por autorizar · enviado hoy 14:35». Sin llegar todavía, «guardado» y no «enviado».
  static String subtituloDetalle(Pedido p, DateTime ahora) {
    final f = p.fecha.toLocal();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = hoy == DateTime(f.year, f.month, f.day)
        ? 'hoy ${dos(f.hour)}:${dos(f.minute)}'
        : 'el ${dos(f.day)}/${dos(f.month)}';
    return switch (p.estado) {
      EstadoDelPedido.porAutorizar =>
        '${estado(p.estado)} · ${p.llego ? 'enviado' : 'guardado'} $cuando',
      _ => estado(p.estado),
    };
  }

  static const excedioElLimite =
      'Lo enviaste pasando el límite de deuda. Tu coordinador lo va a tener en cuenta.';

  /// 37B·03. Sin motivo, el aviso dice qué hacer igual (mapa §2: texto).
  static String noAutorizado(String? motivo) {
    final m = motivo?.trim() ?? '';
    return m.isEmpty
        ? 'Tu coordinador no lo autorizó. Hablá con él y armá un pedido nuevo si hace falta.'
        : 'Tu coordinador no lo autorizó: «$m».';
  }

  static const pedidoCancelado = 'Cancelaste este pedido. Ya no le llega a tu coordinador.';
  static const cancelarPedido = 'Cancelar pedido';
  static const cancelando = 'Cancelando…';
  static const armarUnoNuevo = 'Armar uno nuevo';

  /// Cancelar no vuelve atrás (decisión «Cancelar ped»): se confirma (mapa §2: texto).
  static const cancelarTitulo = '¿Cancelar este pedido?';
  static const cancelarTexto =
      'Deja de llegarle a tu coordinador y no se puede deshacer. Si lo necesitás, armás uno nuevo.';
  static const cancelarConfirmar = 'Sí, cancelar';
  static const noCancelar = 'No, dejarlo';

  /// El pedido que se abrió ya no está en el teléfono (mapa §2: texto).
  static const pedidoNoEncontrado = 'No encontramos este pedido.';
  static const montoAutorizado = 'Autorizado';
  static const montoPedido = 'Pedido';
  static String lineaAutorizada(int pedidas, int autorizadas) =>
      '× $autorizadas (pediste $pedidas)';
  static String linea(int n) => '× $n';
  static const productoSinNombre = 'Producto';

  // --- Mi Cuenta ---
  static const hacerUnPedido = '+ Hacer un pedido';
  static const misPedidos = 'Mis pedidos';
  static String porAutorizar(int n) => n == 1 ? '1 por autorizar' : '$n por autorizar';
}
