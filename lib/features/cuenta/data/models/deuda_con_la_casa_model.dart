import '../../domain/entities/deuda_con_la_casa.dart';

/// El JSON del RPC `mi_deuda_con_la_casa_editora` ↔ [DeudaConLaCasa] (backend-supabase 0164 y, para
/// `deuda_hace_7_dias`, 0168).
///
/// Un campo que falta o que no tiene el tipo esperado lanza una [FormatException]: una respuesta
/// rara no se adivina ni se muestra a medias (ante la duda, no se afirma nada de la deuda).
abstract final class DeudaConLaCasaModel {
  static DeudaConLaCasa desdeJson(Object? json) {
    final mapa = _mapa(json, 'la respuesta');
    final pedidos = _lista(mapa['pedidos'], 'pedidos');
    return DeudaConLaCasa(
      deudaTotalCentavos: _entero(mapa['deuda_total'], 'deuda_total'),
      sumaDeSaldosCentavos: _entero(mapa['suma_de_saldos'], 'suma_de_saldos'),
      depositosValidadosCentavos: _entero(mapa['depositos_validados'], 'depositos_validados'),
      pedidos: [for (final p in pedidos) _pedido(_mapa(p, 'un pedido'))],
      // Una respuesta guardada antes de 0168 no trae la clave: es como `null` (sin datos de la semana
      // anterior). Si viene, tiene que ser un entero o `null`.
      deudaHace7DiasCentavos: mapa['deuda_hace_7_dias'] == null
          ? null
          : _entero(mapa['deuda_hace_7_dias'], 'deuda_hace_7_dias'),
    );
  }

  static PedidoConSaldo _pedido(Map<String, Object?> p) => PedidoConSaldo(
    pedidoId: _texto(p['pedido_id'], 'pedido_id'),
    fechaPedido: _fecha(p['fecha_pedido'], 'fecha_pedido'),
    montoCentavos: _entero(p['monto'], 'monto'),
    pagadoCentavos: _entero(p['pagado'], 'pagado'),
    saldoCentavos: _entero(p['saldo'], 'saldo'),
    lineas: [
      for (final l in _lista(p['lineas'], 'lineas'))
        LineaDePedido(
          nombre: _texto(_mapa(l, 'una línea')['nombre'], 'nombre'),
          cantidad: _entero(_mapa(l, 'una línea')['cantidad'], 'cantidad'),
        ),
    ],
  );

  static Map<String, Object?> _mapa(Object? valor, String que) {
    if (valor is Map) return valor.cast<String, Object?>();
    throw FormatException('$que no es un objeto');
  }

  static List<Object?> _lista(Object? valor, String que) {
    if (valor is List) return valor.cast<Object?>();
    throw FormatException('$que no es una lista');
  }

  static int _entero(Object? valor, String que) {
    if (valor is num && valor == valor.truncate()) return valor.toInt();
    throw FormatException('$que no es un entero');
  }

  static String _texto(Object? valor, String que) {
    if (valor is String) return valor;
    throw FormatException('$que no es un texto');
  }

  static DateTime _fecha(Object? valor, String que) {
    if (valor is String) {
      final fecha = DateTime.tryParse(valor);
      if (fecha != null) return fecha.toUtc();
    }
    throw FormatException('$que no es una fecha');
  }
}
