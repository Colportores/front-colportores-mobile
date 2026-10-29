import '../../ventas/domain/services/reglas_de_venta.dart';
import '../../ventas/presentation/formato_venta.dart';
import '../domain/entities/venta_con_saldo.dart';
import 'textos_cobro.dart';

/// Los textos de «¿Qué venta?» (vista 39, C·08, #440): los del canvas tal cual, y los de los estados
/// que el canvas no dibuja (decididos por mapa §2: texto, en línea con #439 P1).
abstract final class TextosQueVenta {
  // --- Del canvas (C·08) ---
  static const cobrar = 'Cobrar';
  static const cancelar = 'Cancelar';

  /// «¿Qué le cobrás a Pedro?»: con el nombre de pila de quien debe. Sin nombre (la persona ya no
  /// está en la casa), la pregunta sin él.
  static String titulo(String? nombre) {
    final n = nombre?.trim() ?? '';
    return n.isEmpty ? '¿Qué venta cobrás?' : '¿Qué le cobrás a $n?';
  }

  /// «Venta 0038 · 12/10»: la primera línea de cada opción, igual que el resumen del cobro (28).
  static String ventaDel(VentaConSaldo venta) =>
      TextosCobro.ventaDel(venta.numeroTalonario, ReglasDeVenta.diaDeMontevideo(venta.fecha));

  /// «$ 1.200»: lo que falta cobrar de la venta, a la derecha de la opción.
  static String saldo(VentaConSaldo venta) => FormatoVenta.monto(venta.saldoCentavos);

  // --- Estados que el canvas no dibuja (decididos, mapa §2: texto) ---
  static const cargando = 'Cargando las ventas…';
  static const noPudimosLeer = 'No pudimos leer las ventas guardadas en tu teléfono.';
  static const reintentar = 'Reintentar';
  static const cerrar = 'Cerrar';

  /// Ya no debe nada: pagó todo mientras la hoja de la casa estaba abierta.
  static String sinSaldo(String? nombre) {
    final n = nombre?.trim() ?? '';
    return n.isEmpty
        ? 'No hay ventas con saldo. No queda nada para cobrar.'
        : '$n no tiene ventas con saldo. No queda nada para cobrar.';
  }

  /// Lo que lee el lector de pantalla de una opción: «Venta 0038 · 12/10. Colección de 1 libro.
  /// Saldo $ 1.200». Sin la palabra «Saldo» el monto suelto no dice qué es.
  static String opcionParaLector(VentaConSaldo venta) {
    final partes = [
      ventaDel(venta),
      if (venta.descripcion.trim().isNotEmpty) venta.descripcion.trim(),
      'Saldo ${saldo(venta)}',
    ];
    return partes.join('. ');
  }
}
