import '../entities/deuda_con_la_casa.dart';

/// Un pedido a la casa editora que carga la deuda (AUTORIZADO, DESPACHADO o RECIBIDO), tal como baja
/// con la sincronización.
final class PedidoDeLaDeuda {
  const PedidoDeLaDeuda({
    required this.pedidoId,
    required this.fechaPedido,
    required this.montoCentavos,
    this.numero,
    this.lineas = const [],
  });

  final String pedidoId;

  /// El «Pedido #231» del servidor; desempata dos pedidos de la misma hora.
  final int? numero;

  /// Cuándo llegó el pedido al servidor.
  final DateTime fechaPedido;

  /// Lo que el pedido suma a la deuda: lo autorizado, o lo pedido si no se redujo.
  final int montoCentavos;

  /// Los libros del pedido, ya por nombre y sin las líneas autorizadas en cero.
  final List<LineaDePedido> lineas;
}

/// Un cambio de la deuda: desde [desde] valió [deudaCentavos] (`cuenta_deuda_historial`).
final class CambioDeLaDeuda {
  const CambioDeLaDeuda({required this.desde, required this.deudaCentavos, this.id = ''});

  final DateTime desde;
  final int deudaCentavos;

  /// Desempata dos cambios de la misma hora.
  final String id;
}

/// Lo que baja con la sincronización y alcanza para contar la deuda con la casa editora.
final class InsumosDeLaDeuda {
  const InsumosDeLaDeuda({
    required this.deudaTotalCentavos,
    required this.historial,
    required this.pedidos,
    required this.depositosValidadosCentavos,
    required this.tarjetasValidadasCentavos,
  });

  /// `cuenta_colportor.deuda_total`; 0 si no tiene cuenta o está de baja (no debe nada).
  final int deudaTotalCentavos;

  /// `cuenta_deuda_historial` de la colportora, sin las filas dadas de baja.
  final List<CambioDeLaDeuda> historial;

  /// Los pedidos AUTORIZADO, DESPACHADO y RECIBIDO vivos.
  final List<PedidoDeLaDeuda> pedidos;

  /// Lo que sumaron los depósitos a la casa editora con `validado_en`.
  final int depositosValidadosCentavos;

  /// Lo que sumaron los cobros con tarjeta validados: pagan como un depósito (decisión del 04/11,
  /// «Tarjeta ped.»).
  final int tarjetasValidadasCentavos;
}

/// La cuenta de la deuda con la casa editora hecha en el teléfono (decisión de Cristian, 05/11: la
/// deuda baja con la sincronización y el teléfono la calcula, #671). Es la misma regla que
/// `mi_deuda_con_la_casa_editora()` del servidor (backend-supabase 0164, 0165 y 0168), que los tests
/// reproducen caso por caso:
///
/// - la deuda real es la de la cuenta ([InsumosDeLaDeuda.deudaTotalCentavos]);
/// - los pedidos van por `fecha_pedido, numero, id`; lo pagado (depósitos validados más tarjetas
///   validadas) cubre primero el más viejo: el pagado de cada pedido es
///   `min(monto, max(pagadoTotal − montoDeLosAnteriores, 0))`;
/// - solo se listan los de saldo mayor que 0;
/// - la deuda de hace 7 días es la de la última fila del historial con `desde` igual o anterior a
///   «ahora − 7 × 24 h», o `null` si no hay una.
abstract final class CalculadorDeLaDeuda {
  static DeudaConLaCasa calcular(InsumosDeLaDeuda insumos, {required DateTime ahora}) {
    final pedidos = [...insumos.pedidos]..sort(_primeroElMasViejo);
    final pagadoTotal = insumos.depositosValidadosCentavos + insumos.tarjetasValidadasCentavos;

    var antes = 0;
    var sumaDeSaldos = 0;
    final conSaldo = <PedidoConSaldo>[];
    for (final p in pedidos) {
      final pagado = _minimo(p.montoCentavos, _maximo(pagadoTotal - antes, 0));
      final saldo = p.montoCentavos - pagado;
      antes += p.montoCentavos;
      if (saldo <= 0) continue;
      sumaDeSaldos += saldo;
      conSaldo.add(
        PedidoConSaldo(
          pedidoId: p.pedidoId,
          fechaPedido: p.fechaPedido,
          montoCentavos: p.montoCentavos,
          pagadoCentavos: pagado,
          saldoCentavos: saldo,
          lineas: p.lineas,
        ),
      );
    }

    return DeudaConLaCasa(
      deudaTotalCentavos: insumos.deudaTotalCentavos,
      sumaDeSaldosCentavos: sumaDeSaldos,
      depositosValidadosCentavos: insumos.depositosValidadosCentavos,
      pedidos: conSaldo,
      deudaHace7DiasCentavos: _deudaDeHace7Dias(insumos.historial, ahora),
    );
  }

  static int _primeroElMasViejo(PedidoDeLaDeuda a, PedidoDeLaDeuda b) {
    final porFecha = a.fechaPedido.compareTo(b.fechaPedido);
    if (porFecha != 0) return porFecha;
    final porNumero = (a.numero ?? 0).compareTo(b.numero ?? 0);
    if (porNumero != 0) return porNumero;
    return a.pedidoId.compareTo(b.pedidoId);
  }

  static int? _deudaDeHace7Dias(List<CambioDeLaDeuda> historial, DateTime ahora) {
    final limite = ahora.toUtc().subtract(const Duration(days: 7));
    CambioDeLaDeuda? elegido;
    for (final c in historial) {
      if (c.desde.isAfter(limite)) continue;
      if (elegido == null) {
        elegido = c;
        continue;
      }
      final porFecha = c.desde.compareTo(elegido.desde);
      if (porFecha > 0 || (porFecha == 0 && c.id.compareTo(elegido.id) > 0)) elegido = c;
    }
    return elegido?.deudaCentavos;
  }

  static int _minimo(int a, int b) => a < b ? a : b;
  static int _maximo(int a, int b) => a > b ? a : b;
}
